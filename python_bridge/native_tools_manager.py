"""
Native tools (C++ `tools` binary) process manager for the TermuxForge bridge.

Spawns ONE persistent `tools --plain --max-output=N <workspace>` subprocess
per workspace and pipes JSON commands into its stdin, reading JSON results
back from stdout -- the same protocol the Flutter app used to speak to the
binary directly, and the same stdio pattern already used for generic MCP
servers in mcp_manager.py.

This exists so the Flutter app (a separate installed Android app, sandboxed
away from Termux's private storage) never touches the binary path or
process directly. It talks to this bridge over the loopback HTTP port
instead -- the same port (8390) it already trusts for /mcp -- and this
manager is the only thing that ever spawns or writes to the C++ process.
"""

import asyncio
import json
import logging
import os
from typing import Any, Optional

logger = logging.getLogger("termux_forge.native_tools")

# Same candidate search native_tools_service.dart used to do client-side.
# Kept here since this is now the only place that needs to search the
# filesystem for it -- and this code genuinely runs inside Termux, so the
# paths are real and reachable.
_CANDIDATES = [
    "nexon_bridge/tools",
    "nexon_bridge/nexon_code",
    "projects/termux_forge/cpp_bridge/tools",
    "projects/termux_forge/cpp_bridge/nexon_code",
    "codetools/tools",
    "codetools/nexon_code",
    "Nexon/cpp_bridge/tools",
    "Nexon/cpp_bridge/nexon_code",
    "nexon/cpp_bridge/tools",
    "nexon/cpp_bridge/nexon_code",
    "projects/Nexon/cpp_bridge/tools",
    "projects/Nexon/cpp_bridge/nexon_code",
    "projects/nexon/cpp_bridge/tools",
    "projects/nexon/cpp_bridge/nexon_code",
    "termux_forge/cpp_bridge/tools",
    "termux_forge/cpp_bridge/nexon_code",
    "storage/shared/Download/tools",
    "storage/shared/Download/nexon_code",
]


def find_binary(preferred: Optional[str] = None) -> Optional[str]:
    """Locate the tools binary. Order: explicit override, then known spots."""
    home = os.environ.get("HOME", "/data/data/com.termux/files/home")
    candidates = []
    if preferred and preferred.strip():
        candidates.append(preferred.strip())
    candidates += [os.path.join(home, c) for c in _CANDIDATES]
    candidates.append("/data/data/com.termux/files/usr/bin/nexon_code")
    for c in candidates:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


class NativeToolsManager:
    """
    Owns at most one running `tools` subprocess at a time, keyed by
    workspace. Restarted automatically if the workspace changes or the
    process dies. Calls are serialized: the C++ binary answers commands
    strictly in the order they are received.
    """

    def __init__(self) -> None:
        self._process: Optional[asyncio.subprocess.Process] = None
        self._workspace: str = ""
        self._binary_path: str = ""
        self._lock = asyncio.Lock()
        self._stderr_tail: list[str] = []
        self._stderr_task: Optional[asyncio.Task] = None

    @property
    def is_running(self) -> bool:
        return self._process is not None and self._process.returncode is None

    async def health(self) -> dict[str, Any]:
        """Report whether the binary can be found / is running, without
        starting anything -- used by the app's toggle + dialog check."""
        binary = find_binary()
        return {
            "binary_found": binary is not None,
            "binary_path": binary,
            "running": self.is_running,
            "workspace": self._workspace or None,
        }

    async def ensure_running(self, workspace: str, binary_path: Optional[str] = None) -> None:
        if self._process is not None and self._process.returncode is None and self._workspace == workspace:
            return
        async with self._lock:
            if self._process is not None and self._process.returncode is None and self._workspace == workspace:
                return
            await self._teardown()
            binary = binary_path or find_binary()
            if binary is None:
                raise RuntimeError(
                    "tools binary not found. Compile cpp_bridge/tools.cpp "
                    "(see install_bridge.sh) or pass an explicit path."
                )
            self._process = await asyncio.create_subprocess_exec(
                binary, "--plain", "--max-output=60000", workspace,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            self._binary_path = binary
            self._workspace = workspace
            self._stderr_tail = []
            self._stderr_task = asyncio.create_task(self._drain_stderr())
            logger.info(
                "Started native tools binary: %s (PID %d) workspace=%s",
                binary, self._process.pid, workspace,
            )

    async def _drain_stderr(self) -> None:
        proc = self._process
        if proc is None or proc.stderr is None:
            return
        try:
            while True:
                line = await proc.stderr.readline()
                if not line:
                    break
                text = line.decode(errors="replace").rstrip("\n")
                self._stderr_tail.append(text)
                if len(self._stderr_tail) > 40:
                    self._stderr_tail.pop(0)
        except Exception:
            pass

    async def call(
        self,
        workspace: str,
        tool: str,
        args: Optional[dict] = None,
        timeout: float = 130.0,
        binary_path: Optional[str] = None,
    ) -> dict[str, Any]:
        """Execute one tool call and return the parsed JSON result. Never
        raises for tool-level failures -- those come back as {"err": ...}
        dicts the caller (and ultimately the LLM) can read."""
        await self.ensure_running(workspace=workspace, binary_path=binary_path)
        async with self._lock:
            proc = self._process
            if proc is None or proc.stdin is None or proc.stdout is None:
                return {"err": "tools process not available", "t": tool}
            line = json.dumps({"t": tool, "a": args or {}}) + "\n"
            try:
                proc.stdin.write(line.encode())
                await proc.stdin.drain()
            except Exception as e:
                await self._teardown()
                return {"err": f"failed to write to tools process: {e}", "t": tool}
            try:
                raw = await asyncio.wait_for(proc.stdout.readline(), timeout=timeout)
            except asyncio.TimeoutError:
                await self._teardown()
                return {
                    "err": f"native tools call timed out after {timeout:.0f}s; the bridge was restarted",
                    "t": tool,
                }
            if not raw:
                await self._teardown()
                tail = " | ".join(self._stderr_tail) or "(none)"
                return {
                    "err": f"tools process exited unexpectedly; stderr tail: {tail}",
                    "t": tool,
                }
            try:
                return json.loads(raw.decode())
            except json.JSONDecodeError:
                return {
                    "err": "malformed JSON result (likely truncated at output cap)",
                    "t": tool,
                    "partial": raw.decode(errors="replace")[:200],
                }

    async def _teardown(self) -> None:
        proc = self._process
        self._process = None
        if self._stderr_task is not None:
            self._stderr_task.cancel()
            self._stderr_task = None
        if proc is not None and proc.returncode is None:
            try:
                proc.kill()
            except Exception:
                pass
            try:
                await asyncio.wait_for(proc.wait(), timeout=2)
            except Exception:
                pass

    async def dispose(self) -> None:
        await self._teardown()


# Module-level singleton -- mirrors the Dart NativeToolsService.instance
# pattern so the bridge's HTTP routes can share one manager instance.
_instance: Optional["NativeToolsManager"] = None


def get_manager() -> "NativeToolsManager":
    global _instance
    if _instance is None:
        _instance = NativeToolsManager()
    return _instance
