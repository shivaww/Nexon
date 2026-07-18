#!/usr/bin/env python3
"""
TermuxForge Bridge Server
===========================

Main WebSocket + HTTP bridge server that runs on ``127.0.0.1:8765``
in Termux and provides a JSON-RPC 2.0 interface for the Flutter app.

Supports:
- Real-time WebSocket communication
- 30+ RPC methods for file I/O, git, Flutter, MCP, workflows, etc.
- Output streaming via WebSocket
- Command safety filtering
- Approval tracking
- Command history persistence
- Graceful shutdown

Usage::

    python3 termux_forge_bridge.py
    python3 termux_forge_bridge.py --host 127.0.0.1 --port 8765
"""

import argparse
import asyncio
from aiohttp import web
import hashlib
import json
import logging
import os
import re
import shlex
import signal
import sys
import time
from pathlib import Path
from typing import Any, Optional

import websockets
from websockets.server import WebSocketServerProtocol

# ── Local imports ─────────────────────────────────────────────────────
# Add the bridge directory to the module path.
BRIDGE_DIR = os.path.dirname(os.path.abspath(__file__))
if BRIDGE_DIR not in sys.path:
    sys.path.insert(0, BRIDGE_DIR)

from protocol import (
    ErrorCode,
    JsonRpcError,
    JsonRpcRequest,
    JsonRpcResponse,
    MethodRouter,
)
from security import SecurityManager
from command_executor import CommandExecutor
from tool_discovery import ToolDiscovery
from mcp_manager import McpManager, McpServerConfig, TransportType
from workflow_runner import WorkflowRunner, WorkflowDefinition
from github_hooks import GitHubHooks
from media_hooks import MediaHooks
from checkpoint_hooks import CheckpointManager
from hybrid_tools import (
    build_registry,
    shell_exec as hybrid_shell_exec,
    read_file_rich,
    multi_read_rich,
    write_file_rich,
    patch_file_rich,
    replace_lines_rich,
    insert_lines_rich,
    delete_lines_rich,
    file_outline_rich,
    search_files_rich,
    tree_rich,
    diff_files_rich,
    OutputRenderer,
    append_file_rich,
    delete_path_rich,
    move_path_rich,
    copy_path_rich,
    mkdir_path_rich,
    stat_path_rich,
    chmod_path_rich,
)
from background_service_manager import (
    BackgroundServiceManager,
    detect_server_command,
)
from deep_research import DeepResearchOrchestrator

# ── Constants ─────────────────────────────────────────────────────────
VERSION = "1.0.0"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
MCP_HTTP_TIMEOUT_SECONDS = float(os.getenv("MCP_HTTP_TIMEOUT_SECONDS", "110"))
LOG_DIR = os.path.expanduser("~/.termux_forge/logs")
HISTORY_FILE = os.path.expanduser("~/.termux_forge/command_history.json")
DEFAULT_CWD = os.path.expanduser("~")

# ── Logging setup ─────────────────────────────────────────────────────
os.makedirs(LOG_DIR, exist_ok=True)
log_file = os.path.join(LOG_DIR, "bridge.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler(log_file, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("termux_forge.bridge")


# ══════════════════════════════════════════════════════════════════════
#  BRIDGE SERVER
# ══════════════════════════════════════════════════════════════════════

class TermuxForgeBridge:
    """
    Main bridge server orchestrating all subsystems.

    Attributes
    ----------
    host : str
        Bind address.
    port : int
        Bind port.
    security : SecurityManager
        Command safety evaluator.
    executor : CommandExecutor
        Shell command executor.
    tools : ToolDiscovery
        Installed tool scanner.
    mcp : McpManager
        MCP server manager.
    workflows : WorkflowRunner
        Workflow execution engine.
    github : GitHubHooks
        GitHub CLI integration.
    media : MediaHooks
        Media provider integration.
    checkpoints : CheckpointManager
        File/git checkpoint manager.
    """

    def __init__(self, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
        self.host = host
        self.port = port

        # Subsystems
        self.security = SecurityManager()
        self.executor = CommandExecutor(self.security)
        self.tools = ToolDiscovery()
        self.mcp = McpManager()
        self.workflows = WorkflowRunner(self.executor)
        self.github = GitHubHooks()
        self.media = MediaHooks()
        self.checkpoints = CheckpointManager()

        # Hybrid Tools Framework
        self.hybrid = build_registry(self.executor, self.security)

        # Background Service Manager
        self.services = BackgroundServiceManager()

        # Deep research keeps retrieved source text out of the LLM tool result.
        self.deep_research = DeepResearchOrchestrator()

        # State
        self._clients: set[WebSocketServerProtocol] = set()
        self._approval_queue: dict[str, dict[str, Any]] = {}
        self._server: Any = None
        self._shutdown_event = asyncio.Event()

        # Router
        self.router = MethodRouter()
        self._register_methods()

    # ── Method registration ───────────────────────────────────────────

    def _register_methods(self) -> None:
        """Register all JSON-RPC method handlers."""
        r = self.router

        # ── Command execution ─────────────────────────────────────────
        r.register("execute_command", self._execute_command)
        r.register("execute_shell", self._execute_command)
        r.register("run_command", self._execute_command)
        r.register("kill_command", self._kill_command)

        # ── File operations ───────────────────────────────────────────
        # Legacy names are kept for compatibility, but they route to the
        # richer guarded implementations so older prompts do not bypass IDE
        # output, binary guards, path normalization, or checkpoint support.
        r.register("read_file", self._hybrid_read_file_rich)
        r.register("write_file", self._hybrid_write_file_rich)
        r.register("edit_file", self._legacy_edit_file_rich)
        r.register("list_files", self._hybrid_tree)
        r.register("search_files", self._hybrid_search_rich)
        r.register("file_info", self._hybrid_stat_path)
        r.register("multi_read", self._legacy_multi_read_rich)
        r.register("symbol_search", self._symbol_references)

        # ── Git operations ────────────────────────────────────────────
        r.register("git_status", self._git_status)
        r.register("git_diff", self._git_diff)
        r.register("git_commit", self._git_commit)
        r.register("git_push", self._git_push)
        r.register("git_pull", self._git_pull)

        # ── Flutter / Dart ────────────────────────────────────────────
        r.register("flutter_run", self._flutter_run)
        r.register("flutter_test", self._flutter_test)
        r.register("flutter_build", self._flutter_build)
        r.register("dart_analyze", self._dart_diagnostics)

        # ── Package management ────────────────────────────────────────
        r.register("install_package", self._install_package)

        # ── Tool discovery ────────────────────────────────────────────
        r.register("check_tool", self._check_tool)
        r.register("discover_tools", self._discover_tools)

        # ── History ───────────────────────────────────────────────────
        r.register("get_command_history", self._get_command_history)

        # ── Workspace / Version ───────────────────────────────────────
        r.register("ping", self._ping)
        r.register("version_check", self._version_check)
        r.register("workspace_validate", self._workspace_validate)

        # ── MCP ───────────────────────────────────────────────────────
        r.register("mcp_server_manage", self._mcp_server_manage)
        r.register("mcp_tool_discover", self._mcp_tool_discover)
        r.register("mcp_transport_handle", self._mcp_transport_handle)

        # ── Deep research ────────────────────────────────────────────
        r.register("deep_research.ingest", self._deep_research_ingest)
        r.register("deep_research.retrieve", self._deep_research_retrieve)
        r.register("deep_research.export_temp", self._deep_research_export_temp)
        r.register("web_search", self._web_search)
        r.register("read_url", self._read_url)

        # ── Workflows ─────────────────────────────────────────────────
        r.register("workflow_execute", self._workflow_execute)

        # ── Checkpoints ───────────────────────────────────────────────
        r.register("checkpoint_create", self._checkpoint_create)
        r.register("checkpoint_rollback", self._checkpoint_rollback)

        # ── Media ─────────────────────────────────────────────────────
        r.register("media_discover", self._media_discover)

        # ── GitHub CI/CD ──────────────────────────────────────────────
        r.register("github_workflow_trigger", self._github_workflow_trigger)
        r.register("github_build_status", self._github_build_status)
        r.register("github_download_artifact", self._github_download_artifact)

        # ── Environment / Project Health ──────────────────────────────
        r.register("env_status", self._env_status)
        r.register("system_ram_headroom", self._system_ram_headroom)
        r.register("project_health", self._project_health)

        # ── Hybrid Tools (shell + Python, AI-optimized output) ────────────
        r.register("read_file_rich",     self._hybrid_read_file_rich)
        r.register("multi_read_rich",    self._hybrid_multi_read_rich)
        r.register("write_file_rich",    self._hybrid_write_file_rich)
        r.register("patch_file",         self._hybrid_patch_file)
        r.register("replace_lines",      self._hybrid_replace_lines)
        r.register("insert_lines",       self._hybrid_insert_lines)
        r.register("delete_lines",       self._hybrid_delete_lines)
        r.register("file_outline",       self._hybrid_file_outline)
        r.register("search_rich",        self._hybrid_search_rich)
        r.register("tree",               self._hybrid_tree)
        r.register("diff_files",         self._hybrid_diff_files)
        r.register("tool_help",          self._hybrid_tool_help)
        r.register("shell_rich",         self._hybrid_shell_rich)
        r.register("append_file",        self._hybrid_append_file)
        r.register("delete_path",        self._hybrid_delete_path)
        r.register("move_path",          self._hybrid_move_path)
        r.register("copy_path",          self._hybrid_copy_path)
        r.register("mkdir_path",         self._hybrid_mkdir_path)
        r.register("stat_path",          self._hybrid_stat_path)
        r.register("chmod_path",         self._hybrid_chmod_path)

        # ── Background Service Manager ────────────────────────────────
        r.register("run_background",  self._run_background)
        r.register("list_services",   self._list_services)
        r.register("service_status",  self._service_status)
        r.register("service_logs",    self._service_logs)
        r.register("stop_service",    self._stop_service)

        # ── IDE / Analyzer Tools ─────────────────────────────────────
        r.register("dart_diagnostics", self._dart_diagnostics)
        r.register("dart_format",      self._dart_format)
        r.register("symbol_references", self._symbol_references)

    # ── Workspace / path helpers ─────────────────────────────────────

    def _effective_cwd(self, cwd: str = DEFAULT_CWD, workspace_dir: str = "") -> str:
        """Choose the working directory for command-like tools."""
        candidate = cwd
        if workspace_dir and (not candidate or candidate == DEFAULT_CWD):
            candidate = workspace_dir
        candidate = self.translate_termux_path(candidate or DEFAULT_CWD)
        return os.path.expanduser(str(candidate))

    def _render_command_ai_block(self, result: Any) -> str:
        """Render a CommandResult as a rich block without changing raw stdout."""
        stdout = result.stdout or ""
        stderr = result.stderr or ""
        stdout_lines = stdout.splitlines()
        stderr_lines = stderr.splitlines()
        header = OutputRenderer.shell_header(
            command=result.command,
            exit_code=result.exit_code,
            duration_ms=int(result.duration * 1000),
            cwd=result.cwd,
            timed_out=result.timed_out,
            line_count=len(stdout_lines),
        )
        parts = [header]
        if stdout_lines:
            parts.append(stdout.rstrip())
        if stderr_lines:
            parts.append(f"\n{OutputRenderer._divider()}")
            parts.append("STDERR:" if result.exit_code == 0 else "STDERR (command failed):")
            parts.append(stderr.rstrip())
        if result.timed_out:
            parts.append(f"\n{OutputRenderer._divider()}")
            parts.append(f"Timed out after {result.duration:.1f}s.")
        parts.append(OutputRenderer._divider())
        return "\n".join(parts)

    def _file_sha256(self, path: str) -> str:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()

    def _assert_expected_file_state(
        self,
        path: str,
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        expected_exists: bool | None = None,
    ) -> None:
        """Protect against overwriting files changed outside the agent flow."""
        p = Path(path).expanduser()
        exists = p.exists()
        if expected_exists is not None and exists != expected_exists:
            raise JsonRpcError(
                ErrorCode.VALIDATION_ERROR,
                f"File state changed for {path}: expected exists={expected_exists}, actual exists={exists}",
            )
        if expected_sha256:
            if not p.is_file():
                raise JsonRpcError(ErrorCode.VALIDATION_ERROR, f"Cannot verify SHA-256; not a file: {path}")
            actual = self._file_sha256(str(p))
            if actual.lower() != expected_sha256.lower():
                raise JsonRpcError(
                    ErrorCode.VALIDATION_ERROR,
                    f"File changed before edit: SHA-256 mismatch for {path}",
                    data={"expectedSha256": expected_sha256, "actualSha256": actual},
                )
        if expected_mtime is not None:
            if not exists:
                raise JsonRpcError(ErrorCode.VALIDATION_ERROR, f"Cannot verify mtime; path missing: {path}")
            actual_mtime = p.stat().st_mtime
            if abs(actual_mtime - float(expected_mtime)) > 0.001:
                raise JsonRpcError(
                    ErrorCode.VALIDATION_ERROR,
                    f"File changed before edit: mtime mismatch for {path}",
                    data={"expectedMtime": expected_mtime, "actualMtime": actual_mtime},
                )

    def _checkpoint_paths(self, paths: list[str], max_files: int = 500) -> list[str]:
        """Expand directories into a bounded list of files for checkpoints."""
        skip_dirs = {".git", ".dart_tool", "build", "node_modules", "__pycache__", ".gradle"}
        expanded: list[str] = []
        seen: set[str] = set()
        for raw in paths:
            if not raw:
                continue
            p = Path(raw).expanduser()
            if p.is_dir():
                for root, dirs, files in os.walk(str(p)):
                    dirs[:] = [d for d in dirs if d not in skip_dirs]
                    for name in files:
                        fp = os.path.join(root, name)
                        if fp not in seen:
                            expanded.append(fp)
                            seen.add(fp)
                        if len(expanded) >= max_files:
                            return expanded
            else:
                fp = str(p)
                if fp not in seen:
                    expanded.append(fp)
                    seen.add(fp)
        return expanded

    async def _auto_checkpoint(
        self,
        action: str,
        paths: list[str],
        workspace_dir: str = "",
        include_git: bool = True,
    ) -> dict | None:
        """Create a bounded safety checkpoint before mutating files."""
        checkpoint_paths = self._checkpoint_paths(paths)
        if not checkpoint_paths:
            return None
        workspace = workspace_dir or str(Path(checkpoint_paths[0]).parent)
        manager = CheckpointManager(workspace=workspace)
        cp = await manager.create(
            name=f"auto_{action}_{int(time.time())}",
            paths=checkpoint_paths,
            include_git=include_git,
            description=f"Automatic checkpoint before {action}",
        )
        return cp.to_dict()

    def _with_checkpoint(self, result: dict, checkpoint: dict | None) -> dict:
        if checkpoint:
            result["checkpoint"] = checkpoint
            if isinstance(result.get("stdout"), str):
                result["stdout"] += (
                    f"\n{OutputRenderer._divider()}\n"
                    f"  Safety checkpoint: {checkpoint.get('id')} ({checkpoint.get('fileCount')} file(s))"
                )
        return result

    # ══════════════════════════════════════════════════════════════════
    #  METHOD HANDLERS
    # ══════════════════════════════════════════════════════════════════

    # ── execute_command ───────────────────────────────────────────────

    async def _execute_command(
        self,
        command: str,
        cwd: str = DEFAULT_CWD,
        timeout: int = 30,
        env: dict | None = None,
        stream: bool = False,
        process_id: str | None = None,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Execute a shell command with safety checks."""
        cwd = self._effective_cwd(cwd, workspace_dir)

        # Auto-detect long-running background server commands
        is_server, _, _ = detect_server_command(command)
        if is_server:
            logger.info("Auto-intercepted long-running server command: %s", command)
            return await self._run_background(
                command=command, cwd=cwd, env=env, workspace_dir=workspace_dir,
            )

        try:
            if stream:
                result = await self.executor.execute_streaming(
                    command=command, cwd=cwd, timeout=timeout,
                    env=env, process_id=process_id,
                    on_output=lambda s, l: asyncio.ensure_future(
                        self._broadcast({
                            "type": "output",
                            "stream": s,
                            "line": l,
                            "processId": process_id,
                        })
                    ),
                )
            else:
                result = await self.executor.execute(
                    command=command, cwd=cwd, timeout=timeout,
                    env=env, process_id=process_id,
                )
            data = result.to_dict()
            data["rawStdout"] = data.get("stdout", "")
            data["rawStderr"] = data.get("stderr", "")
            data["aiBlock"] = self._render_command_ai_block(result)
            return data
        except ValueError as exc:
            raise JsonRpcError(ErrorCode.COMMAND_BLOCKED, str(exc))

    async def _kill_command(self, process_id: str) -> dict:
        """Kill a running command."""
        killed = await self.executor.kill(process_id)
        return {"killed": killed, "processId": process_id}

    # ── File operations ───────────────────────────────────────────────

    async def _read_file(self, path: str, encoding: str = "utf-8") -> dict:
        """Read a file and return its contents."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.exists():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"File not found: {path}")
            content = p.read_text(encoding=encoding)
            return {
                "path": path,
                "content": content,
                "size": p.stat().st_size,
                "encoding": encoding,
            }
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _write_file(
        self, path: str, content: str, encoding: str = "utf-8",
        create_dirs: bool = True,
    ) -> dict:
        """Write content to a file."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if create_dirs:
                p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding=encoding)
            return {"path": path, "size": p.stat().st_size, "written": True}
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _edit_file(
        self, path: str, search: str, replace: str,
    ) -> dict:
        """Search-and-replace edit in a file."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.exists():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"File not found: {path}")
            content = p.read_text()
            if search not in content:
                return {"path": path, "edited": False, "reason": "Search text not found"}
            new_content = content.replace(search, replace, 1)
            p.write_text(new_content)
            return {"path": path, "edited": True}
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _list_files(
        self, path: str = DEFAULT_CWD, pattern: str = "*",
        recursive: bool = False, max_depth: int = 3,
    ) -> dict:
        """List files in a directory."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.is_dir():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"Not a directory: {path}")

            files = []
            glob_func = p.rglob if recursive else p.glob
            for item in glob_func(pattern):
                # Limit depth for recursive searches
                if recursive:
                    rel = item.relative_to(p)
                    if len(rel.parts) > max_depth:
                        continue
                try:
                    stat = item.stat()
                    files.append({
                        "name": item.name,
                        "path": str(item),
                        "isDirectory": item.is_dir(),
                        "size": stat.st_size if item.is_file() else 0,
                        "modified": stat.st_mtime,
                    })
                except PermissionError:
                    continue
                if len(files) >= 500:
                    break

            return {"path": path, "files": files, "count": len(files)}
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _search_files(
        self, query: str, path: str = DEFAULT_CWD,
        extensions: list[str] | None = None,
    ) -> dict:
        """Search for text within files using grep."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        cmd = f"grep -rnI --max-count=100 '{query}' {path}"
        if extensions:
            includes = " ".join(f"--include='*.{ext}'" for ext in extensions)
            cmd = f"grep -rnI --max-count=100 {includes} '{query}' {path}"
        result = await self.executor.execute(cmd, timeout=15)
        matches = []
        for line in result.stdout.splitlines()[:100]:
            parts = line.split(":", 2)
            if len(parts) >= 3:
                matches.append({
                    "file": parts[0],
                    "line": int(parts[1]) if parts[1].isdigit() else 0,
                    "content": parts[2].strip(),
                })
        return {"query": query, "matches": matches, "count": len(matches)}

    async def _file_info(self, path: str) -> dict:
        """Get file info: size and line count."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.is_file():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"File not found: {path}")
            size_bytes = p.stat().st_size
            with open(p, 'r', encoding='utf-8', errors='ignore') as f:
                line_count = sum(1 for _ in f)
            return {
                "path": path,
                "size_bytes": size_bytes,
                "line_count": line_count,
                "success": True,
            }
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _multi_read(self, path: str, ranges: list | str) -> dict:
        """Batch N line ranges in one call."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.is_file():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"File not found: {path}")
            
            parsed_ranges = []
            if isinstance(ranges, str):
                parts = ranges.split(',')
                for part in parts:
                    subparts = part.strip().split('-')
                    if len(subparts) == 2:
                        parsed_ranges.append((int(subparts[0]), int(subparts[1])))
            elif isinstance(ranges, list):
                for item in ranges:
                    if isinstance(item, str):
                        subparts = item.strip().split('-')
                        if len(subparts) == 2:
                            parsed_ranges.append((int(subparts[0]), int(subparts[1])))
                    elif isinstance(item, (list, tuple)):
                        if len(item) >= 2:
                            parsed_ranges.append((int(item[0]), int(item[1])))
                    elif isinstance(item, dict):
                        start = item.get('start') or item.get('start_line')
                        end = item.get('end') or item.get('end_line')
                        if start is not None and end is not None:
                            parsed_ranges.append((int(start), int(end)))
                            
            if not parsed_ranges:
                raise JsonRpcError(ErrorCode.INVALID_PARAMS, "No valid ranges specified.")
                
            with open(p, 'r', encoding='utf-8', errors='replace') as f:
                lines = f.readlines()
                
            results = {}
            for start, end in parsed_ranges:
                start_idx = max(0, start - 1)
                end_idx = min(len(lines), end)
                snippet = "".join(lines[start_idx:end_idx])
                results[f"{start}-{end}"] = snippet
                
            return {"path": path, "ranges": results, "success": True}
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _symbol_search(self, symbol: str, path: str = DEFAULT_CWD) -> dict:
        """Search for class/function definitions for a symbol."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            patterns = [
                f"class {symbol}",
                f"enum {symbol}",
                f"struct {symbol}",
                f"interface {symbol}",
                f"mixin {symbol}",
                f"extension {symbol}",
                f"{symbol}(",
                f"{symbol}<",
            ]
            
            results = []
            def scan_dir(dir_path):
                for filepath in dir_path.iterdir():
                    if filepath.is_dir():
                        if filepath.name in ('.git', '.dart_tool', 'build', '.pub-cache', '__pycache__', 'node_modules'):
                            continue
                        yield from scan_dir(filepath)
                    elif filepath.is_file():
                        yield filepath

            files_to_scan = scan_dir(p) if p.is_dir() else [p]
            for filepath in files_to_scan:
                if filepath.is_file():
                    try:
                        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                            for i, line in enumerate(f):
                                matched = False
                                for pattern in patterns:
                                    if pattern in line:
                                        matched = True
                                        break
                                if not matched and symbol in line:
                                    words = line.split()
                                    if any(w in words for w in ('class', 'void', 'Future', 'String', 'int', 'bool', 'final', 'const')):
                                        matched = True
                                if matched:
                                    results.append({
                                        "file": str(filepath),
                                        "line_number": i + 1,
                                        "content": line.strip()
                                    })
                                    if len(results) > 100:
                                        break
                        if len(results) > 100:
                            break
                    except Exception:
                        pass
            return {"symbol": symbol, "results": results, "count": len(results)}
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    # ── Git operations ────────────────────────────────────────────────

    async def _git_status(self, cwd: str = DEFAULT_CWD) -> dict:
        r = await self.github.git_status(cwd)
        return r.to_dict()

    async def _git_diff(self, cwd: str = DEFAULT_CWD, staged: bool = False) -> dict:
        r = await self.github.git_diff(cwd, staged)
        return r.to_dict()

    async def _git_commit(
        self, message: str, cwd: str = DEFAULT_CWD, add_all: bool = True,
    ) -> dict:
        r = await self.github.git_commit(message, cwd, add_all)
        return r.to_dict()

    async def _git_push(
        self, message: str = "Update", branch: str | None = None,
        cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.push_code(message, branch, cwd)
        return r.to_dict()

    async def _git_pull(
        self, branch: str | None = None, cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.git_pull(branch, cwd)
        return r.to_dict()

    # ── Flutter / Dart ────────────────────────────────────────────────

    async def _flutter_run(
        self, cwd: str = DEFAULT_CWD, device: str | None = None,
        flavor: str | None = None,
    ) -> dict:
        cmd = "flutter run"
        if device:
            cmd += f" -d {device}"
        if flavor:
            cmd += f" --flavor {flavor}"
        result = await self.executor.execute(cmd, cwd=cwd, timeout=300)
        return result.to_dict()

    async def _flutter_test(
        self, cwd: str = DEFAULT_CWD, path: str | None = None,
    ) -> dict:
        cmd = "flutter test"
        if path:
            cmd += f" {path}"
        result = await self.executor.execute(cmd, cwd=cwd, timeout=120)
        return result.to_dict()

    async def _flutter_build(
        self, target: str = "apk", cwd: str = DEFAULT_CWD,
        release: bool = True, flavor: str | None = None,
    ) -> dict:
        cmd = f"flutter build {target}"
        if release:
            cmd += " --release"
        if flavor:
            cmd += f" --flavor {flavor}"
        result = await self.executor.execute(cmd, cwd=cwd, timeout=600)
        return result.to_dict()

    async def _dart_analyze(self, cwd: str = DEFAULT_CWD) -> dict:
        result = await self.executor.execute("dart analyze", cwd=cwd, timeout=60)
        return result.to_dict()

    # ── Package management ────────────────────────────────────────────

    async def _install_package(
        self, package: str, manager: str = "pkg",
    ) -> dict:
        managers = {
            "pkg": f"pkg install -y {package}",
            "pip": f"pip install {package}",
            "npm": f"npm install -g {package}",
        }
        cmd = managers.get(manager)
        if not cmd:
            raise JsonRpcError(
                ErrorCode.INVALID_PARAMS,
                f"Unknown package manager: {manager}",
            )
        result = await self.executor.execute(cmd, timeout=120)
        return result.to_dict()

    # ── Tool discovery ────────────────────────────────────────────────

    async def _check_tool(self, command: str) -> dict:
        info = await self.tools.check_tool(command)
        return info.to_dict()

    async def _discover_tools(self) -> dict:
        tools = await self.tools.scan_all()
        return {
            "tools": {k: v.to_dict() for k, v in tools.items()},
            "packageManagers": self.tools.detect_package_managers(),
            "available": len(self.tools.get_available()),
            "total": len(tools),
        }

    # ── History ───────────────────────────────────────────────────────

    async def _get_command_history(self, limit: int = 50) -> dict:
        return {"history": self.executor.get_history(limit)}

    # ── Workspace / Version ───────────────────────────────────────────

    async def _version_check(self) -> dict:
        return {
            "bridge": VERSION,
            "python": sys.version,
            "platform": sys.platform,
            "methods": self.router.list_methods(),
        }

    async def _ping(self) -> dict:
        return {"ok": True, "version": VERSION, "time": time.time()}

    async def _workspace_validate(self, path: str = DEFAULT_CWD) -> dict:
        p = Path(path)
        is_flutter = (p / "pubspec.yaml").exists()
        is_git = (p / ".git").exists()
        return {
            "path": path,
            "exists": p.exists(),
            "isDirectory": p.is_dir(),
            "isFlutterProject": is_flutter,
            "isGitRepo": is_git,
            "isApproved": self.security.validate_path(path),
        }

    # ── MCP ───────────────────────────────────────────────────────────

    async def _mcp_server_manage(
        self, action: str, name: str = "", config: dict | None = None,
    ) -> dict:
        if action == "start":
            if config:
                cfg = McpServerConfig(
                    name=config.get("name", name),
                    command=config.get("command", ""),
                    args=config.get("args", []),
                    env=config.get("env", {}),
                    transport=TransportType(config.get("transport", "stdio")),
                    url=config.get("url", ""),
                )
                return await self.mcp.start_server(cfg)
            elif name:
                return await self.mcp.start_from_preset(name)
            raise JsonRpcError(ErrorCode.INVALID_PARAMS, "Provide name or config")
        elif action == "stop":
            return await self.mcp.stop_server(name)
        elif action == "restart":
            return await self.mcp.restart_server(name)
        elif action == "status":
            return await self.mcp.health_check(name)
        elif action == "list":
            return {"servers": self.mcp.list_servers()}
        elif action == "presets":
            return {"presets": list(self.mcp.list_presets().keys())}
        raise JsonRpcError(ErrorCode.INVALID_PARAMS, f"Unknown action: {action}")

    async def _mcp_tool_discover(self, name: str = "") -> dict:
        if name:
            tools = await self.mcp.discover_tools(name)
            return {"server": name, "tools": tools}
        all_tools = await self.mcp.discover_all_tools()
        return {"tools": all_tools}

    # ── Deep research ─────────────────────────────────────────────────

    async def _deep_research_ingest(
        self, stage_id: str, query_id: str, source_url: str, text: str
    ) -> dict:
        """Index already-cleaned content, used internally by ``web_fetch`` and tests."""
        return await self.deep_research.ingest(stage_id, query_id, source_url, text)

    async def _deep_research_retrieve(self, stage_id: str, query: str) -> dict:
        """Write ranked chunks to temp.json and return confirmation metadata only."""
        return await self.deep_research.retrieve(stage_id, query)

    async def _deep_research_export_temp(self) -> dict:
        """Return the bridge-owned retrieval payload for Flutter's writer stage."""
        try:
            content = self.deep_research.temp_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            content = "{}"
        return {"content": content}

    async def _web_search(self, query: str = "", q: str = "") -> dict:
        search_query = query or q
        if not search_query:
            return {"error": "Query is required."}
        api_key = os.getenv("TAVILY_API_KEY")
        if not api_key:
            return {"error": "TAVILY_API_KEY environment variable not configured."}
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    "https://api.tavily.com/search",
                    json={
                        "api_key": api_key,
                        "query": search_query,
                        "search_depth": "basic",
                        "max_results": 4
                    },
                    timeout=aiohttp.ClientTimeout(total=15)
                ) as resp:
                    if resp.status >= 300:
                        body = await resp.text()
                        return {"error": f"Tavily API failed: {resp.status} - {body}"}
                    data = await resp.json()
                    results = []
                    for r in data.get("results", []):
                        results.append({
                            "title": r.get("title") or "Search Result",
                            "url": r.get("url") or "",
                            "snippet": r.get("content") or ""
                        })
                    return {"results": results}
        except Exception as e:
            return {"error": f"Tavily search execution failed: {e}"}

    async def _read_url(
        self, url: str = "", uri: str = "", stage_id: str = "stage_mcp", query_id: str = "query_mcp"
    ) -> dict:
        target_url = url or uri
        if not target_url:
            return {"error": "Fetch failed: URL is required."}
        if not target_url.startswith("http"):
            target_url = "https://" + target_url

        is_pdf = target_url.lower().endswith(".pdf")
        text = ""
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.get(target_url, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                    if resp.status < 200 or resp.status >= 300:
                        return {"error": f"Fetch failed: HTTP {resp.status}"}
                    content_type = resp.headers.get("content-type", "").lower()
                    if "application/pdf" in content_type:
                        is_pdf = True
                    if is_pdf:
                        try:
                            pdf_bytes = await resp.read()
                            if not pdf_bytes:
                                return {"error": "Extraction failed: Empty PDF"}
                            pypdf_text = ""
                            pypdf_err = None
                            try:
                                import io
                                from pypdf import PdfReader
                                reader = PdfReader(io.BytesIO(pdf_bytes))
                                text_parts = []
                                for page in reader.pages:
                                    t = page.extract_text()
                                    if t:
                                        text_parts.append(t)
                                pypdf_text = "\n".join(text_parts).strip()
                            except Exception as pe:
                                pypdf_err = pe

                            if len(pypdf_text) >= 10:
                                text = pypdf_text
                            else:
                                custom_text = ""
                                try:
                                    import zlib
                                    import re
                                    stream_pattern = re.compile(rb"stream[\r\n]+([\s\S]*?)[\r\n]+endstream")
                                    custom_parts = []
                                    for match in stream_pattern.finditer(pdf_bytes):
                                        stream_content = match.group(1)
                                        decompressed = None
                                        try:
                                            decompressed = zlib.decompress(stream_content)
                                        except Exception:
                                            decompressed = stream_content
                                        if decompressed:
                                            for bt_match in re.finditer(rb"BT([\s\S]*?)ET", decompressed):
                                                bt_data = bt_match.group(1)
                                                for text_match in re.finditer(rb"\((.*?)\)", bt_data):
                                                    try:
                                                        val = text_match.group(1).decode("utf-8", errors="ignore")
                                                        val = re.sub(r"\\[0-7]{3}", "", val)
                                                        val = val.replace("\\(", "(").replace("\\)", ")").replace("\\\\", "\\")
                                                        custom_parts.append(val)
                                                    except Exception:
                                                        pass
                                    custom_text = " ".join(custom_parts)
                                    custom_text = re.sub(rb"\s+", b" ", custom_text.encode("utf-8")).decode("utf-8").strip()
                                except Exception:
                                    pass

                                if len(custom_text) >= 10:
                                    text = custom_text
                                elif pypdf_err is not None:
                                    return {"error": f"Extraction failed: {pypdf_err}"}
                                else:
                                    return {"error": "Extraction failed: No text layer found (possibly scanned/image PDF)"}
                        except Exception as e:
                            return {"error": f"Extraction failed: {e}"}
                    else:
                        try:
                            body = await resp.text()
                            from deep_research.rag.cleaner import TextCleaner
                            text = TextCleaner().clean(body)
                        except Exception as e:
                            return {"error": f"Extraction failed: {e}"}
        except Exception as e:
            return {"error": f"Fetch failed: {e}"}

        try:
            res = await self.deep_research.ingest(stage_id, query_id, target_url, text)
            if res.get("failed") == True:
                return {"error": "Ingest failed: " + str(res.get("error", "Unknown ingestion error"))}
            return {
                "parse_format": "pdf" if is_pdf else "html",
                "new_chunks_added": res.get("new_chunks_added", 0),
                "novelty_ratio": res.get("novelty_ratio", 0.0),
                "total_chunks_stage": res.get("total_chunks_stage", 0),
                "stage": stage_id,
                "content": text[:200],
                "url": target_url
            }
        except Exception as e:
            return {"error": f"Ingest failed: {e}"}

    async def _mcp_transport_handle(
        self, server: str, method: str, params: dict | None = None,
    ) -> dict:
        return await self.mcp.route_request(server, method, params)

    # ── Workflows ─────────────────────────────────────────────────────

    async def _workflow_execute(self, workflow: dict) -> dict:
        definition = WorkflowDefinition.from_dict(workflow)
        result = await self.workflows.execute(definition)
        return result.to_dict()

    # ── Checkpoints ───────────────────────────────────────────────────

    async def _checkpoint_create(
        self, name: str, paths: list[str] | None = None,
        include_git: bool = True, description: str = "",
    ) -> dict:
        cp = await self.checkpoints.create(name, paths, include_git, description)
        return cp.to_dict()

    async def _checkpoint_rollback(
        self, checkpoint_id: str, restore_files: bool = True,
        restore_git: bool = False,
    ) -> dict:
        return await self.checkpoints.rollback(
            checkpoint_id, restore_files, restore_git,
        )

    # ── Media ─────────────────────────────────────────────────────────

    async def _media_discover(self) -> dict:
        providers = await self.media.discover_providers()
        return {"providers": providers}

    # ── GitHub CI/CD ──────────────────────────────────────────────────

    async def _github_workflow_trigger(
        self, workflow: str, ref: str = "main",
        inputs: dict | None = None, cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.trigger_workflow(workflow, ref, inputs, cwd)
        return r.to_dict()

    async def _github_build_status(
        self, workflow: str | None = None, limit: int = 5,
        cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.get_build_status(workflow, limit, cwd)
        return r.to_dict()

    # ── Environment / Project Health ─────────────────────────────────

    async def _env_status(self) -> dict:
        """
        Return a comprehensive environment snapshot for AI orientation.

        Includes OS, architecture, shell, HOME/PREFIX paths, available
        runtimes (flutter, dart, python3, node, git, etc.), and PATH entries.
        Call this at the start of a session to avoid blind recon turns.
        """
        import platform
        import shutil
        import subprocess

        def which_ver(cmd: str, ver_flag: str = "--version") -> dict:
            """Return {available, path, version} for a binary."""
            path = shutil.which(cmd)
            if not path:
                return {"available": False}
            try:
                proc = subprocess.run(
                    [cmd, ver_flag], capture_output=True, text=True, timeout=5
                )
                raw = (proc.stdout + proc.stderr).strip().splitlines()
                ver = raw[0] if raw else ""
            except Exception:
                ver = ""
            return {"available": True, "path": path, "version": ver}

        termux_prefix = os.environ.get("PREFIX", "/data/data/com.termux/files/usr")
        home = os.path.expanduser("~")
        cwd = os.getcwd()
        path_entries = os.environ.get("PATH", "").split(":")

        tools = {
            "flutter": which_ver("flutter"),
            "dart":    which_ver("dart"),
            "python3": which_ver("python3"),
            "node":    which_ver("node"),
            "npm":     which_ver("npm"),
            "git":     which_ver("git"),
            "gh":      which_ver("gh"),
            "pkg":     which_ver("pkg"),
            "pip":     which_ver("pip"),
            "rg":      which_ver("rg"),
            "fd":      which_ver("fd"),
            "jq":      which_ver("jq"),
            "tree":    which_ver("tree"),
            "curl":    which_ver("curl"),
            "ssh":     which_ver("ssh"),
            "tmux":    which_ver("tmux"),
        }

        return {
            "os": platform.system(),
            "arch": platform.machine(),
            "python": platform.python_version(),
            "shell": os.environ.get("SHELL", "unknown"),
            "home": home,
            "cwd": cwd,
            "termuxPrefix": termux_prefix,
            "pathEntries": path_entries,
            "tools": tools,
            "bridge": VERSION,
            "availableTools": [k for k, v in tools.items() if v.get("available")],
        }

    async def _system_ram_headroom(self) -> dict:
        """Return available RAM headroom in bytes using psutil."""
        try:
            import psutil
            mem = psutil.virtual_memory()
            return {"available_bytes": mem.available, "total_bytes": mem.total}
        except Exception as e:
            return {"error": str(e)}

    async def _project_health(self, path: str = DEFAULT_CWD) -> dict:
        """
        Scan a project workspace and return a health summary.

        Reports:
        - File counts by extension
        - Git status (branch, uncommitted changes)
        - Flutter/Dart project detection (pubspec.yaml)
        - Package dependency count
        - Whether dart analyze can run (package_config.json present)
        - README presence
        - TODO/FIXME count across source files
        """
        import re
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")

        p = Path(path)
        if not p.is_dir():
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"Not a directory: {path}")

        SKIP_DIRS = {".git", ".dart_tool", "build", ".pub-cache",
                     "__pycache__", "node_modules", ".gradle"}

        ext_counts: dict[str, int] = {}
        todo_count = 0
        total_lines = 0
        largest_files: list[dict] = []

        def scan(dir_path: Path, depth: int = 0) -> None:
            nonlocal todo_count, total_lines
            if depth > 8:
                return
            try:
                entries = list(dir_path.iterdir())
            except PermissionError:
                return
            for entry in entries:
                if entry.is_dir():
                    if entry.name not in SKIP_DIRS:
                        scan(entry, depth + 1)
                elif entry.is_file():
                    ext = entry.suffix.lower() or "(no ext)"
                    ext_counts[ext] = ext_counts.get(ext, 0) + 1
                    # Count lines and TODOs only in text source files
                    if ext in (".dart", ".py", ".js", ".ts", ".md",
                               ".yaml", ".yml", ".json", ".sh"):
                        try:
                            text = entry.read_text(encoding="utf-8", errors="ignore")
                            lines = text.count("\n")
                            total_lines += lines
                            todo_count += text.upper().count("TODO") + text.upper().count("FIXME")
                            size = entry.stat().st_size
                            largest_files.append({"path": str(entry), "lines": lines, "bytes": size})
                        except Exception:
                            pass

        scan(p)
        largest_files.sort(key=lambda x: x["lines"], reverse=True)
        largest_files = largest_files[:10]

        # Git info
        git_info: dict = {"isGitRepo": (p / ".git").exists()}
        if git_info["isGitRepo"]:
            try:
                branch_r = await self.executor.execute("git rev-parse --abbrev-ref HEAD", cwd=str(p), timeout=5)
                git_info["branch"] = branch_r.stdout.strip()
                status_r = await self.executor.execute("git status --short", cwd=str(p), timeout=5)
                changed = [l for l in status_r.stdout.splitlines() if l.strip()]
                git_info["uncommittedFiles"] = len(changed)
                git_info["changedFiles"] = changed[:20]
                log_r = await self.executor.execute("git log --oneline -5", cwd=str(p), timeout=5)
                git_info["recentCommits"] = log_r.stdout.strip().splitlines()
            except Exception as e:
                git_info["error"] = str(e)

        # Flutter / Dart project info
        flutter_info: dict = {"isFlutterProject": False}
        pubspec_path = p / "pubspec.yaml"
        if pubspec_path.exists():
            flutter_info["isFlutterProject"] = True
            try:
                import re as _re
                raw = pubspec_path.read_text(encoding="utf-8")
                # Count deps
                deps_match = _re.findall(r"^  [a-z_][a-z0-9_]*:", raw, _re.MULTILINE)
                flutter_info["dependencyCount"] = len(deps_match)
                sdk_match = _re.search(r"sdk:\s*([^\n]+)", raw)
                flutter_info["sdkConstraint"] = sdk_match.group(1).strip() if sdk_match else "unknown"
                flutter_info["hasPackageConfig"] = (p / ".dart_tool" / "package_config.json").exists()
                flutter_info["analyzable"] = flutter_info["hasPackageConfig"]
                if not flutter_info["hasPackageConfig"]:
                    flutter_info["analyzeWarning"] = "Run 'flutter pub get' first — .dart_tool/package_config.json is missing"
            except Exception as e:
                flutter_info["error"] = str(e)

        return {
            "path": str(p),
            "fileCountsByExtension": ext_counts,
            "totalSourceLines": total_lines,
            "todoCount": todo_count,
            "largestFiles": largest_files,
            "git": git_info,
            "flutter": flutter_info,
            "hasReadme": (p / "README.md").exists(),
        }

    async def _github_download_artifact(
        self, run_id: str, name: str | None = None,
        output_dir: str | None = None, cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.download_artifact(run_id, name, output_dir, cwd)
        return r.to_dict()

    # ══════════════════════════════════════════════════════════════════
    #  HYBRID TOOLS HANDLERS
    #  Thin async wrappers around hybrid_tools pure-Python functions.
    #  Each returns a dict whose "stdout" key contains the AI-readable
    #  rich block, so _formatBridgeOutput in Dart picks it up cleanly.
    # ══════════════════════════════════════════════════════════════════

    async def _hybrid_read_file_rich(
        self,
        path: str,
        start_line: int = 1,
        end_line: int | None = None,
        max_lines: int = 120,
        encoding: str = "utf-8",
        show_line_numbers: bool = True,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Read a file with numbered lines, language header, and navigation hints."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            result = read_file_rich(
                path=path,
                start_line=start_line,
                end_line=end_line,
                max_lines=max_lines,
                encoding=encoding,
                show_line_numbers=show_line_numbers,
            )
            return result.to_dict()
        except FileNotFoundError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _legacy_multi_read_rich(
        self,
        path: str,
        ranges: list | str,
        max_lines_per_file: int = 120,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Compatibility adapter for old multi_read(path, ranges) calls."""
        parsed_reads: list[dict[str, Any]] = []
        raw_ranges = ranges.split(",") if isinstance(ranges, str) else ranges
        if not isinstance(raw_ranges, list):
            raise JsonRpcError(ErrorCode.INVALID_PARAMS, "ranges must be a list or comma-separated string")

        for item in raw_ranges:
            start = end = None
            if isinstance(item, str):
                parts = item.strip().split("-", 1)
                if len(parts) == 2:
                    start, end = parts
            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                start, end = item[0], item[1]
            elif isinstance(item, dict):
                start = item.get("start_line", item.get("start"))
                end = item.get("end_line", item.get("end"))
            if start is not None and end is not None:
                parsed_reads.append({
                    "path": path,
                    "start_line": int(start),
                    "end_line": int(end),
                })

        if not parsed_reads:
            raise JsonRpcError(ErrorCode.INVALID_PARAMS, "No valid line ranges specified")

        return await self._hybrid_multi_read_rich(
            reads=parsed_reads,
            max_lines_per_file=max_lines_per_file,
            workspace_dir=workspace_dir,
            **kw,
        )

    async def _hybrid_multi_read_rich(
        self,
        reads: list,
        max_lines_per_file: int = 120,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Batch-read multiple files or ranges from one file in one call."""
        base_dir = workspace_dir or str(kw.get("cwd") or "")
        if base_dir:
            for spec in reads:
                if isinstance(spec, dict) and isinstance(spec.get("path"), str):
                    spec["path"] = self._resolve_path_value(spec["path"], base_dir)
        # Validate paths before reading
        for spec in reads:
            p = spec.get("path", "")
            if p and not self.security.validate_path(p):
                raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {p}")
        try:
            result = multi_read_rich(reads, max_lines_per_file)
            return result.to_dict()
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _legacy_edit_file_rich(
        self,
        path: str,
        search: str,
        replace: str,
        count: int = 1,
        encoding: str = "utf-8",
        backup: bool = True,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Compatibility adapter for old edit_file(path, search, replace) calls."""
        return await self._hybrid_patch_file(
            path=path,
            patches=[{
                "search": search,
                "replace": replace,
                "count": count,
                "label": "legacy edit_file",
            }],
            encoding=encoding,
            backup=backup,
            workspace_dir=workspace_dir,
            expected_sha256=expected_sha256,
            expected_mtime=expected_mtime,
            auto_checkpoint=auto_checkpoint,
            **kw,
        )

    async def _hybrid_write_file_rich(
        self,
        path: str,
        content: str,
        encoding: str = "utf-8",
        create_dirs: bool = True,
        backup: bool = True,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        expected_exists: bool | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Atomically write a file with auto-backup and write verification block."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            self._assert_expected_file_state(path, expected_sha256, expected_mtime, expected_exists)
            checkpoint = await self._auto_checkpoint("write_file", [path], workspace_dir) if auto_checkpoint else None
            result = write_file_rich(path, content, encoding, create_dirs, backup)
            return self._with_checkpoint(result.to_dict(), checkpoint)
        except Exception as exc:
            if isinstance(exc, JsonRpcError):
                raise
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_patch_file(
        self,
        path: str,
        patches: list,
        encoding: str = "utf-8",
        backup: bool = True,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Apply multiple search-replace patches atomically with unified diff output."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            self._assert_expected_file_state(path, expected_sha256, expected_mtime)
            checkpoint = await self._auto_checkpoint("patch_file", [path], workspace_dir) if auto_checkpoint else None
            result = patch_file_rich(path, patches, encoding, backup)
            return self._with_checkpoint(result.to_dict(), checkpoint)
        except FileNotFoundError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            if isinstance(exc, JsonRpcError):
                raise
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_replace_lines(
        self,
        path: str,
        start_line: int,
        end_line: int,
        new_content: str,
        encoding: str = "utf-8",
        backup: bool = True,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Replace a line range with new content, returning a diff."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            self._assert_expected_file_state(path, expected_sha256, expected_mtime)
            checkpoint = await self._auto_checkpoint("replace_lines", [path], workspace_dir) if auto_checkpoint else None
            result = replace_lines_rich(path, start_line, end_line, new_content, encoding, backup)
            return self._with_checkpoint(result.to_dict(), checkpoint)
        except FileNotFoundError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            if isinstance(exc, JsonRpcError):
                raise
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_insert_lines(
        self,
        path: str,
        after_line: int,
        content: str,
        encoding: str = "utf-8",
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Insert lines after a specific line number (0 = beginning of file)."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            self._assert_expected_file_state(path, expected_sha256, expected_mtime)
            checkpoint = await self._auto_checkpoint("insert_lines", [path], workspace_dir) if auto_checkpoint else None
            result = insert_lines_rich(path, after_line, content, encoding)
            return self._with_checkpoint(result.to_dict(), checkpoint)
        except FileNotFoundError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            if isinstance(exc, JsonRpcError):
                raise
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_delete_lines(
        self,
        path: str,
        start_line: int,
        end_line: int,
        encoding: str = "utf-8",
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Delete a specific line range from a file with backup."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            self._assert_expected_file_state(path, expected_sha256, expected_mtime)
            checkpoint = await self._auto_checkpoint("delete_lines", [path], workspace_dir) if auto_checkpoint else None
            result = delete_lines_rich(path, start_line, end_line, encoding)
            return self._with_checkpoint(result.to_dict(), checkpoint)
        except FileNotFoundError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            if isinstance(exc, JsonRpcError):
                raise
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_file_outline(
        self,
        path: str,
        encoding: str = "utf-8",
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Extract classes, functions, and methods with line numbers from a source file."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            result = file_outline_rich(path, encoding)
            return result.to_dict()
        except FileNotFoundError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_search_rich(
        self,
        query: str,
        path: str = DEFAULT_CWD,
        extensions: list | None = None,
        case_sensitive: bool = False,
        max_matches: int = 80,
        context_lines: int = 2,
        include: list | str | None = None,
        case_insensitive: bool | None = None,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Search text/regex across files using ripgrep or grep with context lines."""
        if include is not None and extensions is None:
            extensions = include if isinstance(include, list) else [include]
        if case_insensitive is not None:
            case_sensitive = not case_insensitive
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            result = await search_files_rich(
                query=query,
                path=path,
                extensions=extensions,
                case_sensitive=case_sensitive,
                max_matches=max_matches,
                context_lines=context_lines,
            )
            return result.to_dict()
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_tree(
        self,
        path: str = DEFAULT_CWD,
        max_depth: int = 4,
        show_hidden: bool = False,
        extensions: list | None = None,
        include: list | str | None = None,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Annotated directory tree with sizes, ages, and smart directory filtering."""
        if include is not None and extensions is None:
            extensions = include if isinstance(include, list) else [include]
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            return tree_rich(path, max_depth, show_hidden, extensions)
        except NotADirectoryError as exc:
            raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, str(exc))
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_diff_files(
        self,
        path_a: str,
        path_b: str,
        context: int = 5,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Compute a unified diff between two files."""
        for p in [path_a, path_b]:
            if not self.security.validate_path(p):
                raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {p}")
        try:
            return diff_files_rich(path_a, path_b, context)
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _hybrid_tool_help(self) -> dict:
        """Return a full reference of all hybrid tools with parameter schemas."""
        block = self.hybrid.tool_help_block()
        return {"stdout": block, "exitCode": 0, "success": True}

    async def _hybrid_shell_rich(
        self,
        command: str,
        cwd: str = DEFAULT_CWD,
        timeout: int = 30,
        env: dict | None = None,
        max_stdout_lines: int = 120,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """
        Execute a shell command using the hybrid engine.

        Returns a rich AI block with: header box, exit code, duration,
        numbered stdout (optional), stderr on failure, and navigation hints.
        This is the premium alternative to execute_command for AI agents.
        """
        cwd = self._effective_cwd(cwd, workspace_dir)

        # Security check
        safety = self.security.evaluate(command, cwd)
        if not safety.allowed:
            raise JsonRpcError(ErrorCode.COMMAND_BLOCKED, f"Command blocked: {safety.reason}")

        # Auto-detect long-running background server commands
        is_server, _, _ = detect_server_command(command)
        if is_server:
            logger.info("Auto-intercepted long-running server command in shell_rich: %s", command)
            return await self._run_background(
                command=command, cwd=cwd, env=env, workspace_dir=workspace_dir,
            )

        result = await hybrid_shell_exec(command, cwd, timeout, env)

        # Broadcast streaming-style output event to all clients
        await self._broadcast({
            "type": "shell_rich_complete",
            "command": command,
            "exitCode": result.exit_code,
            "durationMs": result.duration_ms,
            "timedOut": result.timed_out,
        })

        return result.to_dict()

    # ── File System Tool Handlers ─────────────────────────────────────

    async def _hybrid_append_file(
        self,
        path: str,
        content: str,
        encoding: str = "utf-8",
        create_if_missing: bool = True,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        expected_exists: bool | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Append content to a file (creates if missing)."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        self._assert_expected_file_state(path, expected_sha256, expected_mtime, expected_exists)
        checkpoint = await self._auto_checkpoint("append_file", [path], workspace_dir) if auto_checkpoint else None
        result = append_file_rich(
            path=path, content=content, encoding=encoding,
            create_if_missing=create_if_missing,
        )
        return self._with_checkpoint(result, checkpoint)

    async def _hybrid_delete_path(
        self,
        path: str,
        recursive: bool = False,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Delete a file or directory with safety guards."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        self._assert_expected_file_state(path, expected_sha256, expected_mtime)
        checkpoint = await self._auto_checkpoint("delete_path", [path], workspace_dir) if auto_checkpoint else None
        return self._with_checkpoint(delete_path_rich(path=path, recursive=recursive), checkpoint)

    async def _hybrid_move_path(
        self,
        src: str,
        dest: str,
        overwrite: bool = False,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Move/rename a file or directory."""
        if not self.security.validate_path(src):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Source path not allowed: {src}")
        if not self.security.validate_path(dest):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Dest path not allowed: {dest}")
        self._assert_expected_file_state(src, expected_sha256, expected_mtime)
        checkpoint_paths = [src]
        if Path(dest).exists():
            checkpoint_paths.append(dest)
        checkpoint = await self._auto_checkpoint("move_path", checkpoint_paths, workspace_dir) if auto_checkpoint else None
        return self._with_checkpoint(move_path_rich(src=src, dest=dest, overwrite=overwrite), checkpoint)

    async def _hybrid_copy_path(
        self,
        src: str,
        dest: str,
        overwrite: bool = False,
        workspace_dir: str = "",
        expected_dest_sha256: str = "",
        expected_dest_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Copy a file or directory."""
        if not self.security.validate_path(src):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Source path not allowed: {src}")
        if not self.security.validate_path(dest):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Dest path not allowed: {dest}")
        if Path(dest).exists():
            self._assert_expected_file_state(dest, expected_dest_sha256, expected_dest_mtime)
        checkpoint = None
        if auto_checkpoint and overwrite and Path(dest).exists():
            checkpoint = await self._auto_checkpoint("copy_overwrite", [dest], workspace_dir)
        return self._with_checkpoint(copy_path_rich(src=src, dest=dest, overwrite=overwrite), checkpoint)

    async def _hybrid_mkdir_path(
        self,
        path: str,
        parents: bool = True,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Create a directory."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        return mkdir_path_rich(path=path, parents=parents)

    async def _hybrid_stat_path(
        self,
        path: str,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """Return detailed file/directory metadata."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        return stat_path_rich(path=path)

    async def _hybrid_chmod_path(
        self,
        path: str,
        mode: str,
        recursive: bool = False,
        workspace_dir: str = "",
        expected_sha256: str = "",
        expected_mtime: float | None = None,
        auto_checkpoint: bool = True,
        **kw,
    ) -> dict:
        """Change file/directory permissions."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        self._assert_expected_file_state(path, expected_sha256, expected_mtime)
        checkpoint = await self._auto_checkpoint("chmod_path", [path], workspace_dir) if auto_checkpoint else None
        result = chmod_path_rich(path=path, mode=mode, recursive=recursive)
        if checkpoint and isinstance(result.get("stdout"), str):
            result["stdout"] += "\n  Note: checkpoint restores file contents; permission rollback may require chmod."
        return self._with_checkpoint(result, checkpoint)

    # ══════════════════════════════════════════════════════════════════
    #  IDE / ANALYZER HANDLERS
    # ══════════════════════════════════════════════════════════════════

    async def _dart_diagnostics(
        self,
        path: str = "",
        paths: list | None = None,
        cwd: str = DEFAULT_CWD,
        workspace_dir: str = "",
        fatal_infos: bool = False,
        fatal_warnings: bool = False,
        **kw,
    ) -> dict:
        """Run Dart analyzer and return machine-readable diagnostics when possible."""
        cwd = self._effective_cwd(cwd, workspace_dir)
        targets = paths if paths else ([path] if path else [cwd])
        target = " ".join(shlex.quote(str(p)) for p in targets)
        if not self.security.validate_path(cwd):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"CWD not allowed: {cwd}")
        for p in targets:
            if p and not self.security.validate_path(str(p)):
                raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {p}")

        flags = []
        if fatal_infos:
            flags.append("--fatal-infos")
        if fatal_warnings:
            flags.append("--fatal-warnings")
        command = f"dart analyze --format=json {' '.join(flags)} {target}".strip()
        result = await self.executor.execute(command, cwd=cwd, timeout=120)

        diagnostics: list[dict] = []
        parsed_json: dict | None = None
        if result.stdout.strip().startswith("{"):
            try:
                parsed_json = json.loads(result.stdout)
                diagnostics = parsed_json.get("diagnostics", []) or []
            except json.JSONDecodeError:
                parsed_json = None

        if parsed_json is None:
            fallback = await self.executor.execute(
                f"dart analyze {' '.join(flags)} {target}".strip(),
                cwd=cwd,
                timeout=120,
            )
            result = fallback
            for line in result.stdout.splitlines():
                stripped = line.strip()
                if stripped.startswith(("error", "warning", "info")):
                    diagnostics.append({"raw": stripped})

        stdout = result.stdout if result.stdout.strip() else "No analyzer output."
        block = "\n".join([
            OutputRenderer.tool_header(
                "DART DIAGNOSTICS",
                f"{len(diagnostics)} diagnostic(s)  │  exit={result.exit_code}  │  {cwd}",
            ),
            OutputRenderer._divider(),
            stdout.rstrip(),
            OutputRenderer._divider(),
        ])
        return {
            "stdout": block,
            "rawStdout": result.stdout,
            "stderr": result.stderr,
            "exitCode": result.exit_code,
            "success": result.exit_code == 0,
            "diagnostics": diagnostics,
            "cwd": cwd,
            "path": path or "",
            "paths": targets,
        }

    async def _dart_format(
        self,
        path: str = "",
        cwd: str = DEFAULT_CWD,
        workspace_dir: str = "",
        output: str = "write",
        set_exit_if_changed: bool = False,
        **kw,
    ) -> dict:
        """Run dart format on a file or directory."""
        cwd = self._effective_cwd(cwd, workspace_dir)
        target = path or cwd
        if not self.security.validate_path(cwd):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"CWD not allowed: {cwd}")
        if path and not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        parts = ["dart", "format"]
        if output in {"none", "show", "json"}:
            parts.extend(["--output", output])
        if set_exit_if_changed:
            parts.append("--set-exit-if-changed")
        parts.append(shlex.quote(target))
        result = await self.executor.execute(" ".join(parts), cwd=cwd, timeout=120)
        data = result.to_dict()
        data["aiBlock"] = self._render_command_ai_block(result)
        return data

    async def _symbol_references(
        self,
        symbol: str,
        path: str = DEFAULT_CWD,
        extensions: list | None = None,
        workspace_dir: str = "",
        max_matches: int = 120,
        **kw,
    ) -> dict:
        """Find likely references to a symbol across source files."""
        if not symbol.strip():
            raise JsonRpcError(ErrorCode.INVALID_PARAMS, "symbol is required")
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        query = rf"\b{re.escape(symbol)}\b"
        try:
            result = await search_files_rich(
                query=query,
                path=path,
                extensions=extensions or ["dart", "py", "js", "ts", "kt", "java"],
                case_sensitive=True,
                max_matches=max_matches,
                context_lines=1,
            )
            data = result.to_dict()
            data["symbol"] = symbol
            return data
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    # ══════════════════════════════════════════════════════════════════
    #  BACKGROUND SERVICE HANDLERS
    # ══════════════════════════════════════════════════════════════════

    async def _run_background(
        self,
        command: str,
        cwd: str = DEFAULT_CWD,
        name: str = "",
        startup_wait: float = 4.0,
        env: dict | None = None,
        workspace_dir: str = "",
        **kw,
    ) -> dict:
        """
        Launch a long-running process (HTTP server, MCP server, dev server, etc.)
        as a background service and return immediate rich feedback.

        Instead of hanging forever waiting for a non-terminating command,
        this method:
        - Starts the process detached (survives bridge restarts)
        - Collects startup output for `startup_wait` seconds
        - Detects which ports are now listening via /proc/net/tcp
        - Verifies readiness with a TCP connection probe
        - Returns: PID, URL(s), startup log, management commands

        Parameters
        ----------
        command : str
            Shell command to run (without trailing &).
        cwd : str
            Working directory (default: workspace dir).
        name : str
            Optional display name for the service.
        startup_wait : float
            Seconds to observe startup before returning (default 4.0).
        env : dict, optional
            Extra environment variables.
        """
        cwd = self._effective_cwd(cwd, workspace_dir)

        # Security check
        safety = self.security.evaluate(command, cwd)
        if not safety.allowed:
            raise JsonRpcError(ErrorCode.COMMAND_BLOCKED, f"Command blocked: {safety.reason}")

        # Auto-detect service type from command
        _, _, service_type = detect_server_command(command)

        result = await self.services.start_service(
            command=command,
            cwd=cwd or DEFAULT_CWD,
            name=name,
            startup_wait=startup_wait,
            env=env,
            service_type=service_type or "Server",
        )

        # Broadcast so the Flutter UI can show a "service started" badge
        if result.get("success"):
            await self._broadcast({
                "type": "service_started",
                "pid": result.get("pid"),
                "urls": result.get("urls", []),
                "name": name or service_type,
                "command": command[:60],
            })

        return result

    async def _list_services(self) -> dict:
        """List all tracked background services with live status."""
        return self.services.list_services()

    def _resolve_pid(self, target: int | str) -> int:
        if isinstance(target, int):
            return target
        try:
            return int(target)
        except ValueError:
            # Try to resolve by name or command substring, prioritizing running processes
            candidates = []
            for pid, rec in self.services._registry.items():
                if target == rec.name or target in rec.command:
                    candidates.append(rec)
            if not candidates:
                raise JsonRpcError(ErrorCode.INVALID_PARAMS, f"Could not find service matching '{target}'")
            # Sort: running first (1 > 0), then started_at descending (most recent first)
            candidates.sort(key=lambda r: (1 if r.status == "running" else 0, r.started_at), reverse=True)
            return candidates[0].pid

    async def _service_status(self, pid: int = None, id: int = None) -> dict:
        """Get detailed status for a specific background service PID."""
        target = pid if pid is not None else id
        if target is None:
            return {"error": "Must provide 'pid' or 'id'"}
        return self.services.service_status(self._resolve_pid(target))

    async def _service_logs(self, pid: int = None, id: int = None, lines: int = 60) -> dict:
        """Tail the log output of a background service."""
        target = pid if pid is not None else id
        if target is None:
            return {"error": "Must provide 'pid' or 'id'"}
        return self.services.service_logs(self._resolve_pid(target), lines)

    async def _stop_service(self, pid: int = None, id: int = None, force: bool = False) -> dict:
        """Stop a background service by PID. Uses SIGTERM then SIGKILL."""
        target = pid if pid is not None else id
        if target is None:
            return {"error": "Must provide 'pid' or 'id'"}
        target = self._resolve_pid(target)
        # Security: only allow stopping processes we started
        rec = self.services._registry.get(target)
        if not rec:
            return {
                "stdout": f"PID {pid} is not a tracked service. Use list_services to see managed processes.",
                "exitCode": 1,
            }
        return await self.services.stop_service(target, force)



    async def _handle_client(self, websocket: WebSocketServerProtocol) -> None:
        """Handle a WebSocket client connection."""
        client_addr = websocket.remote_address
        logger.info("Client connected: %s", client_addr)
        self._clients.add(websocket)

        try:
            async for raw_message in websocket:
                response = await self._process_message(str(raw_message))
                if response:
                    await websocket.send(response)
        except websockets.exceptions.ConnectionClosedOK:
            logger.info("Client disconnected gracefully: %s", client_addr)
        except websockets.exceptions.ConnectionClosedError as exc:
            logger.warning("Client disconnected with error: %s – %s", client_addr, exc)
        except Exception as exc:
            logger.exception("Unhandled error for client %s", client_addr)
        finally:
            self._clients.discard(websocket)

    def translate_termux_path(self, path_str: Any) -> Any:
        if not isinstance(path_str, str):
            return path_str
        
        # Strip file:// URI scheme if present
        if path_str.startswith("file://"):
            path_str = path_str[7:]
            
        termux_home = "/data/data/com.termux/files/home"
        actual_home = os.path.expanduser("~")
        
        if path_str.startswith(termux_home):
            path_str = path_str.replace(termux_home, actual_home, 1)
        elif path_str.startswith("~/"):
            path_str = path_str.replace("~/", actual_home + "/", 1)
            
        return path_str

    def _resolve_path_value(self, value: Any, workspace: str = "") -> Any:
        """Translate Termux aliases and resolve relative paths inside workspace."""
        if not isinstance(value, str):
            return value

        value = self.translate_termux_path(value.strip())
        if not value:
            return value
        if value.startswith(("http://", "https://")):
            return value
        if value.startswith("~"):
            return os.path.expanduser(value)
        if os.path.isabs(value):
            return value

        if workspace:
            resolved_workspace = self._resolve_path_value(workspace, "")
            return os.path.abspath(os.path.join(str(resolved_workspace), value))
        return os.path.abspath(os.path.expanduser(value))

    def translate_termux_path_in_str(self, val: Any) -> Any:
        if not isinstance(val, str):
            return val
        termux_home = "/data/data/com.termux/files/home"
        actual_home = os.path.expanduser("~")
        return val.replace(termux_home, actual_home)

    def resolve_params_paths(self, params: Any, workspace: str = "") -> Any:
        if isinstance(params, dict):
            local_workspace = (
                params.get("workspace_dir")
                or params.get("workspaceDir")
                or workspace
                or params.get("cwd")
                or ""
            )
            if local_workspace:
                local_workspace = self._resolve_path_value(local_workspace, "")
            new_params = {}
            for k, v in params.items():
                if k in (
                    "path", "file", "cwd", "workspace_dir", "workspaceDir",
                    "directory", "dir", "dir_path", "src", "dest",
                    "path_a", "path_b", "output_dir", "target",
                ):
                    base = "" if k in ("workspace_dir", "workspaceDir", "cwd") else local_workspace
                    new_params[k] = self._resolve_path_value(v, base)
                elif k in ("command", "args"):
                    new_params[k] = self.translate_termux_path_in_str(v) if isinstance(v, str) else ([self.translate_termux_path_in_str(item) for item in v] if isinstance(v, list) else v)
                else:
                    new_params[k] = self.resolve_params_paths(v, local_workspace)
            return new_params
        elif isinstance(params, list):
            return [self.resolve_params_paths(item, workspace) for item in params]
        return params

    async def _handle_http_post(self, request: web.Request) -> web.Response:
        """Handle HTTP POST requests to /mcp from the legacy Dart client."""
        if request.path != '/mcp':
            return web.json_response({"error": "Endpoint not found. Use /mcp"}, status=404)
            
        try:
            body = await request.text()
            # 1. Try parsing <command> XML fallback
            import re
            cmd_match = re.search(r'<command>(.*?)</command>', body, re.DOTALL)
            if cmd_match:
                command = cmd_match.group(1).strip()
                ws_match = re.search(r'<workspace_dir>(.*?)</workspace_dir>', body, re.DOTALL)
                cwd_match = re.search(r'<cwd>(.*?)</cwd>', body, re.DOTALL)
                
                workspace_dir_val = ws_match.group(1).strip() if ws_match else ""
                cwd_val = cwd_match.group(1).strip() if cwd_match else ""
                
                params = {"command": command}
                if workspace_dir_val:
                    params["workspace_dir"] = workspace_dir_val
                if cwd_val:
                    params["cwd"] = cwd_val
                elif workspace_dir_val:
                    params["cwd"] = workspace_dir_val
                    
                method = "run_command"
            else:
                # 2. JSON Payload
                try:
                    data = json.loads(body)
                except json.JSONDecodeError:
                    return web.json_response({"error": "Invalid request format"}, status=400)
                    
                method = data.get("method")
                params = data.get("params", {})
                
            if not method:
                return web.json_response({"error": "Method is required"}, status=400)
                
            # Make paths absolute
            params = self.resolve_params_paths(params)
            
            # Dispatch as internal JSON-RPC
            rpc_req = JsonRpcRequest(method=method, params=params, id="http-req", jsonrpc="2.0")
            try:
                rpc_resp = await asyncio.wait_for(
                    self.router.dispatch(rpc_req),
                    timeout=MCP_HTTP_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError:
                logger.error("MCP HTTP request timed out: method=%s", method)
                return web.json_response(
                    {"error": f"MCP request timed out after {MCP_HTTP_TIMEOUT_SECONDS:g}s"},
                    status=504,
                )
            
            if rpc_resp.error:
                error_msg = rpc_resp.error.get("message", "Unknown RPC error") if isinstance(rpc_resp.error, dict) else str(rpc_resp.error)
                return web.json_response({"error": error_msg}, status=500)
                
            # Keep legacy response format {"result": ...}
            return web.json_response({"result": rpc_resp.result})
            
        except Exception as e:
            return web.json_response({"error": str(e)}, status=500)

    async def _process_message(self, raw: str) -> str | None:
        """Parse and dispatch a JSON-RPC message."""
        try:
            request = JsonRpcRequest.from_json(raw)
            if request.params:
                request.params = self.resolve_params_paths(request.params)
        except JsonRpcError as exc:
            return JsonRpcResponse(id=None, error=exc.to_dict()).to_json()

        if request.is_notification():
            # Notifications don't get responses
            asyncio.create_task(self.router.dispatch(request))
            return None

        response = await self.router.dispatch(request)
        return response.to_json()

    async def _broadcast(self, data: dict) -> None:
        """Broadcast a message to all connected clients."""
        if not self._clients:
            return
        message = json.dumps(data)
        await asyncio.gather(
            *(client.send(message) for client in self._clients),
            return_exceptions=True,
        )

    # ── Server lifecycle ──────────────────────────────────────────────

    async def start(self) -> None:
        """Start the WebSocket and HTTP bridge servers."""
        logger.info("=" * 60)
        logger.info("TermuxForge Bridge v%s starting…", VERSION)
        logger.info("Listening on ws://%s:%d", self.host, self.port)
        logger.info("Listening for HTTP on http://%s:%d", self.host, 8390)
        logger.info("Log file: %s", log_file)
        logger.info("=" * 60)

        # Load saved command history
        self._load_history()

        # Start WebSocket server
        self._server = await websockets.serve(
            self._handle_client,
            self.host,
            self.port,
            ping_interval=30,
            ping_timeout=10,
            max_size=10 * 1024 * 1024,  # 10 MB max message
        )
        
        # Start HTTP server
        self._http_app = web.Application()
        self._http_app.router.add_post('/mcp', self._handle_http_post)
        
        # Also support OPTIONS for CORS if needed
        async def handle_options(request):
            return web.Response(
                status=200,
                headers={
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type',
                }
            )
        self._http_app.router.add_options('/mcp', handle_options)
        
        self._http_runner = web.AppRunner(self._http_app)
        await self._http_runner.setup()
        self._http_site = web.TCPSite(self._http_runner, self.host, 8390)
        await self._http_site.start()

        logger.info("Bridge servers running.")

        # Wait for shutdown signal
        await self._shutdown_event.wait()

    async def shutdown(self) -> None:
        """Gracefully shut down the servers."""
        logger.info("Shutting down bridge servers…")

        # Save history
        self._save_history()

        # Shutdown MCP servers
        await self.mcp.shutdown()
        
        # Stop HTTP server
        if hasattr(self, '_http_runner'):
            await self._http_runner.cleanup()

        # Close WebSocket server
        if self._server:
            self._server.close()
            await self._server.wait_closed()

        logger.info("Bridge servers stopped.")

    def request_shutdown(self) -> None:
        """Signal the server to shut down."""
        self._shutdown_event.set()

    # ── History persistence ───────────────────────────────────────────

    def _save_history(self) -> None:
        """Save command history to disk."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            history = self.executor.get_history(500)
            with open(HISTORY_FILE, "w") as f:
                json.dump(history, f, indent=2, default=str)
            logger.info("Saved %d history entries", len(history))
        except Exception as exc:
            logger.error("Failed to save history: %s", exc)

    def _load_history(self) -> None:
        """Load command history from disk."""
        if not os.path.exists(HISTORY_FILE):
            return
        try:
            with open(HISTORY_FILE) as f:
                entries = json.load(f)
            self.executor._history = entries[-500:]
            logger.info("Loaded %d history entries", len(entries))
        except Exception as exc:
            logger.error("Failed to load history: %s", exc)


# ══════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════

def main() -> None:
    """Parse arguments and run the bridge server."""
    parser = argparse.ArgumentParser(
        description="TermuxForge Python Bridge Server",
    )
    parser.add_argument(
        "--host", default=DEFAULT_HOST,
        help=f"Bind address (default: {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help=f"Bind port (default: {DEFAULT_PORT})",
    )
    args = parser.parse_args()

    bridge = TermuxForgeBridge(host=args.host, port=args.port)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    # Signal handling for graceful shutdown
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, bridge.request_shutdown)

    try:
        loop.run_until_complete(bridge.start())
    except KeyboardInterrupt:
        pass
    finally:
        loop.run_until_complete(bridge.shutdown())
        loop.close()


if __name__ == "__main__":
    main()
