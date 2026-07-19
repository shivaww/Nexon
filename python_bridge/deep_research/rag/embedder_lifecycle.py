"""Robust background server lifecycle manager for llama-server.

Addresses:
1. Race conditions during spawn (using cooperative fcntl.flock).
2. Process leaks/orphans (using start_new_session, SIGTERM/SIGHUP handlers, and PID tracking).
3. Idle timeouts (using event-driven wait instead of polling).
4. Stale-process reaping (detecting and killing dead/stale port-holding processes).
"""

from __future__ import annotations

import atexit
import fcntl
import logging
import os
import re
import shutil
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request

import psutil

logger = logging.getLogger("termux_forge.deep_research.lifecycle")

LOCK_FILE_PATH = "/data/data/com.termux/files/home/.termux_forge_embedder.lock"
PID_FILE_PATH = "/data/data/com.termux/files/home/.termux_forge_embedder.pid"


class ServerLifecycleManager:
    """Manages the lifecycle of llama-server on mobile devices."""

    def __init__(self, idle_timeout: float = 120.0) -> None:
        self.idle_timeout = idle_timeout
        self.last_used_time = time.time()
        self.activity_event = threading.Event()
        self.server_process: subprocess.Popen | None = None
        self._idle_thread: threading.Thread | None = None
        self._lock = threading.Lock()
        self._registered_signals = False

        # Ensure lock directory exists
        os.makedirs(os.path.dirname(LOCK_FILE_PATH), exist_ok=True)

        # Register sig handlers on the main thread during import
        self._register_signals()

        # Proactively clean up any stale llama-server processes on startup
        try:
            self._proactive_cleanup()
        except Exception as e:
            logger.warning(f"Failed to perform proactive startup cleanup: {e}")

    def ensure_server(self, model_path: str, endpoint: str) -> bool:
        """Cooperatively ensure llama-server is online and healthy."""
        # 1. Grab file lock to prevent concurrent spawns
        lock_file = open(LOCK_FILE_PATH, "w")
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX)

            # 2. Check if the server is already online
            if self._is_server_online(endpoint):
                self.touch()
                return True

            # 3. Port/Process audit: Reap any stale process holding the port
            self._reap_stale_processes(endpoint)

            # 4. Ingest sanity checks
            if not os.path.exists(model_path):
                logger.error(f"Embedding model not found at: {model_path}")
                return False

            binary = shutil.which("llama-server")
            if not binary:
                logger.error("llama-server binary not found in path")
                return False

            # 5. Extract port for cmd binding
            port = "8080"
            match = re.search(r":(\d+)", endpoint)
            if match:
                port = match.group(1)

            cmd = [
                binary,
                "-m", model_path,
                "--port", port,
                "--embedding",
                "--threads", "4",
                "--ctx-size", "1024",
                "--batch-size", "512",
                "--ubatch-size", "512",
            ]

            logger.info(f"Spawning background server on port {port}...")
            # Spawn the server in a new process group (prevents orphan groups)
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            self.server_process = proc

            # Write process ID to PID file
            with open(PID_FILE_PATH, "w") as f:
                f.write(str(proc.pid))

            # 6. Wait for the server to become responsive
            if self._wait_for_server(endpoint):
                self.touch()
                # Start the idle loop thread if not already running
                with self._lock:
                    if self._idle_thread is None or not self._idle_thread.is_alive():
                        self._idle_thread = threading.Thread(target=self._idle_loop, daemon=True)
                        self._idle_thread.start()
                return True
            else:
                logger.error("Spawned llama-server failed to become ready.")
                self.shutdown()
                return False

        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)
            lock_file.close()

    def touch(self) -> None:
        """Mark server as active to extend idle timer."""
        self.last_used_time = time.time()
        self.activity_event.set()

    def shutdown(self) -> None:
        """Shut down the server, reap the processes, and clean up files."""
        with self._lock:
            # 1. Terminate server process if managed by this instance
            if self.server_process is not None:
                try:
                    logger.info(f"Terminating background server process PID={self.server_process.pid}")
                    self.server_process.terminate()
                    self.server_process.wait(timeout=2)
                except Exception:
                    try:
                        self.server_process.kill()
                    except Exception:
                        pass
                self.server_process = None

            # 2. Terminate any orphan recorded in the PID file
            if os.path.exists(PID_FILE_PATH):
                try:
                    with open(PID_FILE_PATH, "r") as f:
                        pid = int(f.read().strip())

                    # Only kill if we don't have a running server_process or if the PID matches ours
                    should_kill = False
                    if self.server_process is None:
                        should_kill = True
                    elif self.server_process.pid == pid:
                        should_kill = True

                    if should_kill and psutil.pid_exists(pid):
                        proc = psutil.Process(pid)
                        if proc.name() == "llama-server":
                            logger.info(f"Killing orphan process recorded in PID file: PID={pid}")
                            proc.terminate()
                            proc.wait(timeout=2)
                except Exception:
                    pass
                finally:
                    # Only remove the PID file if it matches our process or if we don't have a running server
                    try:
                        remove_file = False
                        if self.server_process is None:
                            remove_file = True
                        else:
                            with open(PID_FILE_PATH, "r") as f:
                                current_file_pid = int(f.read().strip())
                            if current_file_pid == self.server_process.pid:
                                remove_file = True
                        if remove_file and os.path.exists(PID_FILE_PATH):
                            os.remove(PID_FILE_PATH)
                    except Exception:
                        pass

    def _is_server_online(self, endpoint: str) -> bool:
        """Perform a synchronous health check to f"{endpoint}/health"."""
        try:
            url = f"{endpoint}/health"
            # Bypass system proxy configurations
            proxy_handler = urllib.request.ProxyHandler({})
            opener = urllib.request.build_opener(proxy_handler)
            req = urllib.request.Request(url, headers={"Connection": "close"}, method="GET")
            with opener.open(req, timeout=0.5) as response:
                return response.status < 300
        except Exception:
            return False

    def _wait_for_server(self, endpoint: str) -> bool:
        """Wait up to 30 seconds for server readiness."""
        for _ in range(60):
            if self._is_server_online(endpoint):
                return True
            time.sleep(0.5)
        return False

    def _is_port_held(self, port: int) -> bool:
        """Check if port is bound to localhost."""
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.5)
        try:
            s.bind(("127.0.0.1", port))
            s.close()
            return False
        except socket.error:
            s.close()
            return True

    def _proactive_cleanup(self) -> None:
        """Proactively kill any existing llama-server processes on startup to avoid stale binds."""
        logger.info("Performing proactive startup cleanup of any stale llama-server processes...")
        # 1. Read PID file if it exists, terminate it
        if os.path.exists(PID_FILE_PATH):
            try:
                with open(PID_FILE_PATH, "r") as f:
                    pid = int(f.read().strip())
                if psutil.pid_exists(pid):
                    proc = psutil.Process(pid)
                    if proc.name() in ("llama-server", "llama-server.bin"):
                        logger.info(f"Killing stale llama-server process {pid} from PID file")
                        proc.terminate()
                        proc.wait(timeout=1.0)
            except Exception:
                pass
            finally:
                try:
                    os.remove(PID_FILE_PATH)
                except Exception:
                    pass

        # 2. Sweep by process name
        for proc in psutil.process_iter(["pid", "name"]):
            try:
                if proc.info["name"] in ("llama-server", "llama-server.bin"):
                    logger.info(f"Killing stale llama-server process {proc.pid} by name")
                    proc.terminate()
                    proc.wait(timeout=1.0)
            except Exception:
                pass

        # 3. Specific pkill fallback
        try:
            subprocess.run(["pkill", "-f", "/data/data/com.termux/files/usr/bin/llama-server"], capture_output=True)
            subprocess.run(["pkill", "-f", "/data/data/com.termux/files/usr/bin/llama-server.bin"], capture_output=True)
        except Exception:
            pass

    def _reap_stale_processes(self, endpoint: str) -> None:
        """Find and terminate stale processes holding the target port (Android safe)."""
        pid = None
        if os.path.exists(PID_FILE_PATH):
            try:
                with open(PID_FILE_PATH, "r") as f:
                    pid = int(f.read().strip())
            except Exception:
                pass

        port = 8080
        match = re.search(r":(\d+)", endpoint)
        if match:
            port = int(match.group(1))

        port_held = self._is_port_held(port)

        if port_held:
            logger.info(f"Port {port} is busy. Auditing stale port-holding processes...")
            targets_to_kill = set()

            # 1. Target the PID recorded in our PID file (if still alive)
            if pid is not None:
                try:
                    if psutil.pid_exists(pid):
                        targets_to_kill.add(pid)
                except Exception:
                    pass

            # 2. Target any process named "llama-server" or "llama-server.bin"
            for proc in psutil.process_iter(["pid", "name"]):
                try:
                    name = proc.info["name"]
                    if name in ("llama-server", "llama-server.bin"):
                        targets_to_kill.add(proc.pid)
                    else:
                        # Fallback check if platform permissions allow connection inspection
                        try:
                            conns = proc.connections(kind="inet")
                            if any(conn.laddr.port == port for conn in conns):
                                targets_to_kill.add(proc.pid)
                        except Exception:
                            pass
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    pass

            killed_any = False
            for target_pid in targets_to_kill:
                try:
                    proc = psutil.Process(target_pid)
                    logger.warning(
                        f"Reaping stale process PID={proc.pid}, Name={proc.name()}"
                    )
                    proc.terminate()
                    try:
                        proc.wait(timeout=2)
                    except psutil.TimeoutExpired:
                        proc.kill()
                    killed_any = True
                except Exception:
                    pass

            # 3. Robust pkill fallback if targets couldn't be resolved or killed
            if not killed_any or self._is_port_held(port):
                logger.warning(f"Port {port} held, but target process couldn't be resolved or killed. Trying broad pkill sweep...")
                try:
                    subprocess.run(["pkill", "-f", "/data/data/com.termux/files/usr/bin/llama-server"], capture_output=True)
                    subprocess.run(["pkill", "-f", "/data/data/com.termux/files/usr/bin/llama-server.bin"], capture_output=True)
                    time.sleep(1.0)
                    killed_any = not self._is_port_held(port)
                except Exception as e:
                    logger.error(f"Error during pkill sweep: {e}")

            if not killed_any:
                logger.warning(f"Port {port} held, and broad sweep couldn't free it.")
        else:
            # Port is free, but if the recorded process is still running, clean it up
            if pid is not None:
                try:
                    if psutil.pid_exists(pid):
                        proc = psutil.Process(pid)
                        if proc.name() in ("llama-server", "llama-server.bin"):
                            logger.warning(f"Recorded PID={pid} is active but port is free. Terminating...")
                            proc.terminate()
                            proc.wait(timeout=2)
                except Exception:
                    pass

    def _idle_loop(self) -> None:
        """Event-driven idle shutdown worker (zero polling)."""
        try:
            while True:
                self.activity_event.clear()
                now = time.time()
                elapsed = now - self.last_used_time
                remaining = self.idle_timeout - elapsed
                if remaining <= 0:
                    logger.info("Idle timeout reached. Shutting down embedding server.")
                    self.shutdown()
                    break

                # Sleep exactly until timeout or wakes up immediately on activity touch()
                triggered = self.activity_event.wait(timeout=remaining)
                if not triggered:
                    # Timeout expired
                    now = time.time()
                    if now - self.last_used_time >= self.idle_timeout:
                        logger.info("Idle timeout reached. Shutting down embedding server.")
                        self.shutdown()
                        break
        except Exception as e:
            logger.error(f"Error in idle timeout loop: {e}")

    def _register_signals(self) -> None:
        """Register sig handlers for TERM/HUP and register exit cleanup hook."""

        def signal_handler(signum, frame):
            logger.info(f"Signal {signum} received. Closing embedding server...")
            self.shutdown()
            signal.signal(signum, signal.SIG_DFL)
            os.kill(os.getpid(), signum)

        try:
            signal.signal(signal.SIGTERM, signal_handler)
            signal.signal(signal.SIGHUP, signal_handler)
            atexit.register(self.shutdown)
            self._registered_signals = True
        except Exception as e:
            logger.warning(f"Failed to bind SIGTERM/SIGHUP handlers: {e}")


# Global lifecycle instance
_manager = ServerLifecycleManager()


def ensure_server(model_path: str, endpoint: str) -> bool:
    """Public wrapper to ensure background server is running."""
    return _manager.ensure_server(model_path, endpoint)


def touch() -> None:
    """Public wrapper to keep the server alive."""
    _manager.touch()


def shutdown() -> None:
    """Public wrapper to shut down the server."""
    _manager.shutdown()
