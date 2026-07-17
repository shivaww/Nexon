"""Unit tests for ServerLifecycleManager verifying concurrent safety and SIGKILL recovery."""

from __future__ import annotations

import os
import signal
import socket
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import psutil

from .embedder_lifecycle import ServerLifecycleManager, LOCK_FILE_PATH, PID_FILE_PATH


def test_concurrent_ensure_server_real() -> None:
    """Launch concurrent threads and verify only a single process is spawned and recorded."""
    print("\n--- Running Real Concurrent Spawn Test ---")
    manager = ServerLifecycleManager(idle_timeout=5.0)

    # Use a dummy model path and dummy binary (python sleep command)
    with tempfile.NamedTemporaryFile() as tmp_model:
        import shutil
        real_which = shutil.which
        real_popen = subprocess.Popen

        def mock_which(cmd):
            if cmd == "llama-server":
                return real_which("python3")
            return real_which(cmd)

        port = 28181
        endpoint = f"http://127.0.0.1:{port}"

        dummy_script = (
            f"import socket, time; "
            f"s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); "
            f"s.bind(('127.0.0.1', {port})); "
            f"s.listen(1); "
            f"time.sleep(10)"
        )

        with patch("shutil.which", side_effect=mock_which), \
             patch("subprocess.Popen") as mock_popen, \
             patch.object(manager, "_is_server_online", return_value=False) as mock_online, \
             patch.object(manager, "_wait_for_server", return_value=True):

            spawned_pids = []
            spawn_count = 0
            lock = threading.Lock()

            def mock_popen_impl(cmd, **kwargs):
                nonlocal spawn_count
                with lock:
                    spawn_count += 1
                # Call the original unpatched Popen to avoid infinite recursion
                proc = real_popen(
                    ["python3", "-c", dummy_script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True
                )
                spawned_pids.append(proc.pid)
                # Simulate delay to test race
                time.sleep(0.3)
                return proc

            mock_popen.side_effect = mock_popen_impl

            def dynamic_online(ep):
                return len(spawned_pids) > 0
            mock_online.side_effect = dynamic_online

            threads = []
            for _ in range(3):
                t = threading.Thread(
                    target=manager.ensure_server,
                    args=(tmp_model.name, endpoint)
                )
                threads.append(t)

            for t in threads:
                t.start()
            for t in threads:
                t.join()

            manager.shutdown()

            # Clean up all spawned subprocesses
            for pid in spawned_pids:
                try:
                    os.kill(pid, signal.SIGKILL)
                except Exception:
                    pass

            assert spawn_count == 1, f"Expected exactly 1 process spawn, got {spawn_count}"
            assert len(spawned_pids) == 1, f"Expected exactly 1 running PID, got {len(spawned_pids)}"
            print(f"PASS: Concurrent check succeeded. Spawn count: {spawn_count}, Spawned PID: {spawned_pids}")


def test_kill_9_recovery() -> None:
    """Verify that a SIGKILL (kill -9) leaving a stale process holding the port is reaped and recovered."""
    print("\n--- Running SIGKILL / kill -9 Recovery Test ---")
    manager = ServerLifecycleManager(idle_timeout=5.0)
    port = 28182
    endpoint = f"http://127.0.0.1:{port}"

    with tempfile.NamedTemporaryFile() as tmp_model:
        # 1. Start a stale process manually holding the port
        # This simulates a previous run that crashed via SIGKILL/OOM but left a child holding the port
        dummy_script = (
            f"import socket, time; "
            f"s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); "
            f"s.bind(('127.0.0.1', {port})); "
            f"s.listen(1); "
            f"time.sleep(30)"
        )
        stale_proc = subprocess.Popen(
            ["python3", "-c", dummy_script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )

        # Write stale PID to the PID file to simulate unclean crash record
        with open(PID_FILE_PATH, "w") as f:
            f.write(str(stale_proc.pid))

        # Check that the port is busy
        time.sleep(0.3)
        assert manager._is_port_held(port) is True, "Port should be held by the stale process."
        print(f"Stale process PID={stale_proc.pid} holds port {port}.")

        # 2. Trigger ensure_server. It should detect the port is busy, find the stale process, kill it, and spawn a new one!
        # We mock Popen and health checks to avoid launching another python process
        with patch("shutil.which", return_value="/mock/path/llama-server"), \
             patch("os.path.exists", return_value=True), \
             patch("subprocess.Popen") as mock_popen, \
             patch.object(manager, "_wait_for_server", return_value=True), \
             patch.object(manager, "_is_server_online", return_value=False):

            new_proc = MagicMock()
            new_proc.pid = 77777
            mock_popen.return_value = new_proc

            print("Calling ensure_server() to trigger reaping...")
            success = manager.ensure_server(tmp_model.name, endpoint)
            assert success is True, "ensure_server failed during stale-process recovery."

            # Verify that the stale process was reaped/killed
            try:
                stale_proc.wait(timeout=2)
                print(f"Stale process PID={stale_proc.pid} was successfully reaped.")
            except subprocess.TimeoutExpired:
                stale_proc.kill()
                raise AssertionError("Stale process was not reaped by the manager.")

            # Verify that the new process was spawned
            mock_popen.assert_called_once()
            print(f"New server spawned successfully with PID={new_proc.pid}.")

            manager.shutdown()
            print("PASS: SIGKILL recovery test passed. Stale process holding the port was successfully reaped.")


if __name__ == "__main__":
    test_concurrent_ensure_server_real()
    test_kill_9_recovery()
    print("\nAll lifecycle verification tests passed successfully.")
