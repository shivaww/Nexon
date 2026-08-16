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
import inspect
import json
import ipaddress
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
    OutputRenderer,
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
        self._INGESTED_THIS_SESSION: set[str] = set()
        self._server: Any = None
        self._shutdown_event = asyncio.Event()

        # Router
        self.router = MethodRouter()
        self._register_methods()
        self._register_hybrid_registry_tools()

    # ── Method registration ───────────────────────────────────────────

    def _register_hybrid_registry_tools(self) -> None:
        """Expose every hybrid registry tool as a JSON-RPC method.

        Explicit registrations in _register_methods() take precedence;
        this loop only fills the gaps (the registry now holds just
        tool_help — file tools live in the native C++ bridge).
        """
        import inspect as _inspect

        _drop = {"cwd", "auto_checkpoint", "server"}
        for tool in self.hybrid.list_tools():
            name = tool["name"]
            if self.router.has_method(name):
                continue
            handler = self.hybrid.get_handler(name)
            if handler is None:
                continue  # e.g. search_rich — async, registered separately
            if _inspect.iscoroutinefunction(handler):
                self.router.register(name, handler)
                continue

            async def _wrapped(_h=handler, _name=name, **kw):
                kw = {k: v for k, v in kw.items() if k not in _drop}
                try:
                    return await asyncio.to_thread(_h, **kw)
                except TypeError as exc:
                    # Retry once without optional injected params for tools
                    # whose signatures don't accept them.
                    optional = {k for k in ("workspace_dir", "dry_run") if k in kw}
                    if optional:
                        kw2 = {k: v for k, v in kw.items() if k not in optional}
                        try:
                            return await asyncio.to_thread(_h, **kw2)
                        except TypeError:
                            pass
                    return {
                        "stdout": f"ERROR: {_name}: {exc}",
                        "error": str(exc),
                        "exitCode": 1,
                        "success": False,
                    }

            self.router.register(name, _wrapped)

    def _register_methods(self) -> None:
        """Register all JSON-RPC method handlers."""
        r = self.router

        # ── Command execution ─────────────────────────────────────────
        r.register("execute_command", self._execute_command)
        r.register("execute_shell", self._execute_command)
        r.register("run_command", self._execute_command)
        r.register("kill_command", self._kill_command)

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
        r.register("workspace_list", self._workspace_list)
        r.register("workspace_search", self._workspace_search)
        r.register("workspace_ingest", self._workspace_ingest)
        r.register("workspace_read_page", self._workspace_read_page)
        r.register("workspace_get_outline", self._workspace_get_outline)
        r.register("workspace_check_deps", self._workspace_check_deps)
        r.register("workspace_cross_compare", self._workspace_cross_compare)

        # ── MCP ───────────────────────────────────────────────────────
        r.register("mcp_server_manage", self._mcp_server_manage)
        r.register("mcp_tool_discover", self._mcp_tool_discover)
        r.register("mcp_transport_handle", self._mcp_transport_handle)
        r.register("mcp_request", self._mcp_request)
        r.register("mcp_call", self._mcp_request)

        # ── Deep research ────────────────────────────────────────────
        r.register("deep_research.export_temp", self._deep_research_export_temp)
        r.register("deep_research.export_for_writer", self._deep_research_export_for_writer)
        r.register("deep_research.reset", self._deep_research_reset)
        r.register("deep_research.update_phase", self._deep_research_update_phase)
        r.register("deep_research.save_checkpoint", self._deep_research_save_checkpoint)
        r.register("deep_research.load_checkpoint", self._deep_research_load_checkpoint)
        r.register("deep_research.clear_checkpoint", self._deep_research_clear_checkpoint)
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

        # ── Hybrid tool registry (file tools moved to the native C++ bridge) ──
        r.register("tool_help",          self._hybrid_tool_help)

        # ── Background Service Manager ────────────────────────────────
        r.register("run_background",  self._run_background)
        r.register("list_services",   self._list_services)
        r.register("service_status",  self._service_status)
        r.register("service_logs",    self._service_logs)
        r.register("stop_service",    self._stop_service)
        r.register("wait_for_background", self._wait_for_background)
        r.register("background_time_limit", self._wait_for_background)

        # ── IDE / Analyzer Tools ─────────────────────────────────────
        r.register("dart_diagnostics", self._dart_diagnostics)
        r.register("dart_format",      self._dart_format)
        r.register("tool_stats",         self._tool_stats)

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

    async def _workspace_list(self) -> dict:
        from workspace import WorkspaceManager
        return WorkspaceManager().list_files()

    async def _workspace_search(self, query: str = "", queries: list = None, top_k: int = 5) -> list:
        from workspace import WorkspaceManager
        if queries:
            return WorkspaceManager().search_chunks(queries, top_k=top_k)
        return WorkspaceManager().search_chunks(query, top_k=top_k)

    async def _workspace_ingest(self, file_path: str = "") -> dict:
        from workspace import WorkspaceManager
        return WorkspaceManager().ingest_file(file_path)

    async def _workspace_read_page(self, file_path: str = "", page: int = 1) -> dict:
        from workspace import WorkspaceManager
        return WorkspaceManager().read_page(file_path, page=page)

    async def _workspace_get_outline(self, file_path: str = "") -> dict:
        from workspace import WorkspaceManager
        return WorkspaceManager().get_outline(file_path)

    async def _workspace_check_deps(self) -> dict:
        from workspace import WorkspaceManager
        return WorkspaceManager().check_dependencies()

    async def _workspace_cross_compare(self, query: str = "", max_per_doc: int = 2) -> dict:
        from workspace import WorkspaceManager
        return WorkspaceManager().cross_compare(query, max_per_doc=max_per_doc)

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

    async def _deep_research_export_temp(self) -> dict:
        """Return the bridge-owned retrieval payload for Flutter's writer stage."""
        content = self.deep_research.export_temp()
        return {"content": content}

    async def _deep_research_export_for_writer(
        self,
        max_evidence_tokens: int = 26000,
        prefer_facts: bool = True,
    ) -> dict:
        """Budget-aware evidence export (facts first, round-robin findings)."""
        result = self.deep_research.export_for_writer(
            max_evidence_tokens=int(max_evidence_tokens or 26000),
            prefer_facts=bool(prefer_facts),
        )
        # Also convert to compact structured text for the writer LLM
        if result.get("content") and result["content"] != "[]":
            try:
                phases = json.loads(result["content"])
                result["compact_text"] = self._format_evidence_compact(phases)
            except Exception:
                pass
        return result

    async def _deep_research_reset(self, keep_checkpoint: bool = False) -> dict:
        """Clear temp.json and in-memory caches."""
        return await self.deep_research.reset_run(keep_checkpoint=bool(keep_checkpoint))

    def _format_evidence_compact(self, phases: list) -> str:
        """Convert JSON evidence to structured text (~40% fewer tokens than JSON)."""
        lines = []
        for phase in phases:
            if not isinstance(phase, dict):
                continue
            title = phase.get("phase_title", "Unknown Phase")
            summary = phase.get("summary", "")
            facts = phase.get("facts", [])
            findings = phase.get("findings", [])

            lines.append(f"## {title}")
            if summary:
                lines.append(f"Summary: {summary}\n")
            if facts:
                lines.append(f"### Facts ({len(facts)})")
                for f in facts:
                    if not isinstance(f, dict):
                        continue
                    conf = f.get("confidence", "medium").upper()
                    metric = f.get("metric", "")
                    subject = f.get("subject", "")
                    value = f.get("value", "")
                    source = f.get("source", "")
                    lines.append(f"- [{conf}] {subject} {metric}: {value} (Source: {source})")
                lines.append("")
            if findings:
                lines.append(f"### Findings ({len(findings)})")
                for f in findings:
                    if not isinstance(f, dict):
                        continue
                    conf = f.get("confidence", "medium").upper()
                    text_val = f.get("text", "")
                    source = f.get("source", "")
                    lines.append(f"- [{conf}] {text_val} (Source: {source})")
                lines.append("")
        return "\n".join(lines)

    async def _deep_research_update_phase(
        self,
        stage_id: str = "",
        phase_title: str = "",
        summary: str = "",
        facts: list = None,
        findings: list = None,
        skipped_pdfs: list = None,
        failed_fetches: list = None,
        status: str = "running",
    ) -> dict:
        """Update phase facts and findings in temp.json."""
        return await self.deep_research.update_phase(
            stage_id=stage_id,
            phase_title=phase_title,
            summary=summary,
            facts=facts or [],
            findings=findings or [],
            skipped_pdfs=skipped_pdfs or [],
            failed_fetches=failed_fetches or [],
            status=status or "running",
        )

    async def _deep_research_save_checkpoint(
        self,
        run_id: str = "",
        status: str = "running",
        current_phase_index: int = 0,
        steps: list = None,
        stats: dict = None,
    ) -> dict:
        return await self.deep_research.save_checkpoint(
            run_id=run_id or "",
            status=status or "running",
            current_phase_index=int(current_phase_index or 0),
            steps=steps or [],
            stats=stats or {},
        )

    async def _deep_research_load_checkpoint(self) -> dict:
        return self.deep_research.load_checkpoint()

    async def _deep_research_clear_checkpoint(self) -> dict:
        return await self.deep_research.clear_checkpoint()

    async def _web_search(
        self,
        query: str = "",
        q: str = "",
        topic: str = "general",
        time_range: str | None = None,
        start_date: str | None = None,
        end_date: str | None = None,
        search_depth: str = "basic"
    ) -> dict:
        search_query = query or q
        if not search_query:
            return {"error": "Query is required."}
        api_key = os.getenv("TAVILY_API_KEY")
        if not api_key:
            return {"error": "TAVILY_API_KEY environment variable not configured."}
        try:
            import aiohttp
            
            # Map aliases d/w/m/y to day/week/month/year
            mapped_time_range = None
            if time_range:
                tr = time_range.strip().lower()
                if tr == "d":
                    mapped_time_range = "day"
                elif tr == "w":
                    mapped_time_range = "week"
                elif tr == "m":
                    mapped_time_range = "month"
                elif tr == "y":
                    mapped_time_range = "year"
                elif tr in ("day", "week", "month", "year"):
                    mapped_time_range = tr

            payload = {
                "api_key": api_key,
                "query": search_query,
                "search_depth": search_depth if search_depth in ("basic", "advanced") else "basic",
                "max_results": 4
            }
            if topic:
                payload["topic"] = topic
            if mapped_time_range:
                payload["time_range"] = mapped_time_range
            if start_date:
                payload["start_date"] = start_date
            if end_date:
                payload["end_date"] = end_date

            async with aiohttp.ClientSession() as session:
                async with session.post(
                    "https://api.tavily.com/search",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=30)
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
        self,
        url: str = "",
        uri: str = "",
        stage_id: str = "stage_mcp",
        query_id: str = "query_mcp",
        allow_pdf: bool = False,
        query: str = "",
    ) -> dict:
        """Fetch a URL via the bridge (single I/O path for Deep Research).

        HTML is cleaned with TextCleaner. PDFs are deliberately never extracted:
        a large PDF can exhaust the mobile process and writer context budget.
        When a query is provided, the cleaner applies keyword relevance filtering
        to reduce the output by ~90%, keeping only paragraphs relevant to the query.
        """
        target_url = url or uri
        if not target_url:
            return {"error": "Fetch failed: URL is required."}
        if not target_url.startswith("http"):
            target_url = "https://" + target_url

        try:
            from urllib.parse import urlparse
            parsed = urlparse(target_url)
            if parsed.scheme not in {"http", "https"} or not parsed.hostname:
                return {"error": "Fetch failed: only public HTTP(S) URLs are allowed."}
            host = parsed.hostname.lower()
            _blocked_hosts = {
                "localhost", "metadata.google.internal",
                "127.0.0.1", "0.0.0.0", "::1", "[::1]",
                "169.254.169.254",
            }
            if host in _blocked_hosts or host.endswith(".local") or host.endswith(".internal"):
                return {"error": "Fetch failed: local/private URLs are not allowed."}
            try:
                address = ipaddress.ip_address(host)
                if not address.is_global:
                    return {"error": "Fetch failed: local/private URLs are not allowed."}
            except ValueError:
                pass
        except Exception:
            return {"error": "Fetch failed: invalid URL."}

        looks_like_pdf = target_url.lower().split("?", 1)[0].endswith(".pdf")

        try:
            import aiohttp
            headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
                ),
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Sec-Ch-Ua": '"Chromium";v="124", "Google Chrome";v="124"',
                "Sec-Ch-Ua-Mobile": "?0",
                "Sec-Ch-Ua-Platform": '"Windows"',
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
                "Sec-Fetch-User": "?1",
                "Upgrade-Insecure-Requests": "1",
            }
            async with aiohttp.ClientSession(headers=headers) as session:
                # Termux often lacks proper CA certificates — try with SSL first,
                # fallback to no verification if SSL error occurs.
                try:
                    import ssl
                    ssl_context = ssl.create_default_context()
                except Exception:
                    ssl_context = False
                
                try:
                    async with session.get(
                        target_url, allow_redirects=True, max_redirects=10, 
                        timeout=aiohttp.ClientTimeout(total=45),
                        ssl=ssl_context
                    ) as resp:
                        result = await self._process_read_url_response(resp, target_url, query)
                        # Retry once on 5xx transient server errors
                        if result.get("retryable"):
                            import asyncio
                            logger.info("read_url: retrying %s after 5xx (status %d)", target_url, resp.status)
                            await asyncio.sleep(1.5)
                            async with session.get(
                                target_url, allow_redirects=True, max_redirects=10,
                                timeout=aiohttp.ClientTimeout(total=45),
                                ssl=ssl_context
                            ) as retry_resp:
                                result = await self._process_read_url_response(retry_resp, target_url, query)
                        return result
                except (aiohttp.ClientSSLError, ssl.SSLError) as ssl_err:
                    logger.warning(
                        "read_url: SSL verification failed for %s, retrying without verification: %s",
                        target_url, ssl_err
                    )
                    # Retry without SSL verification (insecure but functional on Termux)
                    async with session.get(
                        target_url, allow_redirects=True, max_redirects=10,
                        timeout=aiohttp.ClientTimeout(total=45),
                        ssl=False
                    ) as resp:
                        return await self._process_read_url_response(resp, target_url, query)
        except Exception as e:
            logger.error("read_url: Fetch failed completely. URL=%s, error=%s", target_url, e)
            return {"error": f"Fetch failed: {e}", "url": target_url}

    async def _process_read_url_response(self, resp, target_url: str, query: str) -> dict:
        """Process HTTP response for read_url (extracted to allow SSL retry logic)."""
        if resp.status < 200 or resp.status >= 300:
            _STATUS_HINTS = {
                400: "Bad Request — malformed URL or rejected by server",
                403: "Forbidden — server blocked the request (bot/rate-limit)",
                404: "Not Found — URL path does not exist",
                408: "Request Timeout",
                429: "Too Many Requests — rate limited, retry later",
                500: "Internal Server Error",
                502: "Bad Gateway",
                503: "Service Unavailable — server temporarily overloaded",
                504: "Gateway Timeout",
            }
            hint = _STATUS_HINTS.get(resp.status, "")
            return {
                "error": f"Fetch failed: HTTP {resp.status}{' — ' + hint if hint else ''}",
                "url": target_url,
                "status_code": resp.status,
                "retryable": resp.status >= 500,
            }

        content_type = (resp.headers.get("content-type") or "").lower()
        looks_like_pdf = target_url.lower().split("?", 1)[0].endswith(".pdf")
        is_pdf = looks_like_pdf or "application/pdf" in content_type

        if is_pdf:
            return {
                "status": "skipped_pdf",
                "reason": "PDF files are excluded from Deep Research to protect memory and context budget",
                "url": target_url,
                "parse_format": "skipped_pdf",
            }

        try:
            body = await resp.text(errors="replace")
            from deep_research.cleaner import TextCleaner
            text = TextCleaner().clean(body, query=query)
            # Defensive: log if cleaning stripped too much content
            if len(text) < 500 and len(body) > 5000:
                logger.warning(
                    "read_url: TextCleaner stripped aggressively. "
                    "URL=%s, original=%d chars, cleaned=%d chars, query=%s",
                    target_url, len(body), len(text), query or "(none)"
                )
            return {
                "status": "success",
                "content": text,
                "url": target_url,
                "parse_format": "html",
            }
        except Exception as e:
            logger.error("read_url extraction_failed: URL=%s, error=%s", target_url, e)
            return {"error": f"Extraction failed: {e}", "url": target_url}

    async def _mcp_transport_handle(
        self, server: str, method: str, params: dict | None = None,
    ) -> dict:
        return await self.mcp.route_request(server, method, params)

    async def _mcp_request(self, **kwargs) -> dict:
        """Dispatcher for <mcp_request> tool calls.

        Extracts method/tool name and params, routing to registered bridge methods
        (e.g., web_search, read_url, deep_research.*) or underlying MCP servers.
        """
        method = kwargs.get("method") or kwargs.get("name") or kwargs.get("tool") or kwargs.get("action")
        params = kwargs.get("params") or kwargs.get("arguments") or kwargs.get("args") or {}
        if not isinstance(params, dict):
            params = {}

        for k, v in kwargs.items():
            if k not in {"method", "name", "tool", "action", "params", "arguments", "args"}:
                params[k] = v

        if not method:
            return {"error": "mcp_request missing target method/tool name."}

        handler = self.router._methods.get(str(method))
        if handler:
            sig = inspect.signature(handler)
            has_var_kw = any(p.kind == inspect.Parameter.VAR_KEYWORD for p in sig.parameters.values())
            call_params = params if has_var_kw else {k: v for k, v in params.items() if k in sig.parameters}
            if inspect.iscoroutinefunction(handler):
                return await handler(**call_params)
            else:
                return handler(**call_params)

        server = kwargs.get("server") or "default"
        return await self.mcp.route_request(server, str(method), params)

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

    async def _hybrid_tool_help(self) -> dict:
        """Return a full reference of all hybrid tools with parameter schemas."""
        block = self.hybrid.tool_help_block()
        return {"stdout": block, "exitCode": 0, "success": True}

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

    async def _tool_stats(self, limit: int = 25, **kw) -> dict:
        """IMPROVEMENT: per-method tool reliability stats from continuous telemetry."""
        from protocol import summarize_tool_calls
        data = summarize_tool_calls(limit=limit)
        tools = data.get("tools", [])
        lines = []
        for t in tools:
            row = (
                f"  {t['method']:<24} calls={t['calls']:<5} ok={t['ok']:<5} "
                f"fail={t['fail']:<4} rate={t['success_rate']:.0%} "
                f"avg={t['avg_ms']}ms max={t['max_ms']}ms"
            )
            if t["last_error"]:
                row += f"  last_err={t['last_error'][:60]}"
            lines.append(row)
        block = f"TOOL TELEMETRY — {data.get('total', 0)} recorded calls\n" + "\n".join(lines) if lines else "TOOL TELEMETRY — no calls recorded yet"
        return {"stdout": block, "total": data.get("total", 0), "tools": tools, "exitCode": 0, "success": True}

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

    async def _wait_for_background(
        self,
        pid: int = None,
        id: int = None,
        time_limit_seconds: float = 15,
        poll_interval_seconds: float = 2,
        log_lines: int = 20,
    ) -> dict:
        """Wait a bounded time for a tracked background service to finish.

        This pauses the calling agent, never the service. The limit is capped
        below the Flutter bridge request timeout so the caller always receives
        a status update instead of an indefinitely pending tool call.
        """
        target = pid if pid is not None else id
        if target is None:
            return {"error": "Must provide the background service 'pid' or 'id'."}

        target = self._resolve_pid(target)
        limit = max(1.0, min(float(time_limit_seconds), 90.0))
        poll_interval = max(0.5, min(float(poll_interval_seconds), 10.0))
        started = time.monotonic()

        while True:
            status = self.services.service_status(target)
            alive = status.get("alive") is True
            elapsed = time.monotonic() - started
            if not alive or elapsed >= limit:
                logs = self.services.service_logs(target, max(1, min(int(log_lines), 100)))
                return {
                    "pid": target,
                    "waited_seconds": round(elapsed, 2),
                    "time_limit_seconds": limit,
                    "timed_out": alive,
                    "completed": not alive,
                    "status": status,
                    "logs": logs,
                    "exitCode": 0,
                }
            await asyncio.sleep(min(poll_interval, limit - elapsed))



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

    async def _handle_workspace_upload(self, request: web.Request) -> web.Response:
        """Handle file upload for Study Mode / Cross-Document Analysis.

        Accepts multipart/form-data with a 'file' field. Streams the file
        to the workspace directory and triggers chunk indexing via
        WorkspaceManager — avoiding full in-memory text extraction on the
        Flutter side.
        """
        try:
            reader = await request.multipart()
            if reader is None:
                return web.json_response({"error": "Expected multipart/form-data"}, status=400)

            field = await reader.next()
            if field is None or field.name != 'file':
                return web.json_response({"error": "Missing 'file' field in upload"}, status=400)

            filename = field.filename or 'upload.dat'
            # Sanitise filename to prevent path traversal
            safe_name = Path(filename).name

            # Pre-check extension before streaming — reject non-document files
            from workspace import ALLOWED_EXTENSIONS, BLOCKED_EXTENSIONS
            file_ext = Path(safe_name).suffix.lower()
            if file_ext in BLOCKED_EXTENSIONS:
                return web.json_response(
                    {"status": "error", "message": f"Blocked file type: {file_ext}. Binary/media files are not allowed."},
                    status=415,
                )
            if file_ext not in ALLOWED_EXTENSIONS:
                return web.json_response(
                    {"status": "error", "message": f"Unsupported file type: {file_ext}. Allowed: {', '.join(sorted(ALLOWED_EXTENSIONS))}"},
                    status=415,
                )

            from workspace import WorkspaceManager
            mgr = WorkspaceManager()

            # New session owns the bucket: clear stale docs from previous sessions
            session_id = request.query.get("session", "")
            if session_id:
                mgr.ensure_session(session_id)

            # Quota pre-check before writing
            quota = mgr.check_storage_quota()
            if not quota.get("allowed", False):
                return web.json_response(
                    {"status": "error", "message": quota.get("reason", "Quota exceeded")},
                    status=413,
                )

            dest = mgr.workspace_path / safe_name
            # Stream to disk in 64 KB chunks — memory-efficient for mobile
            size_written = 0
            with open(dest, 'wb') as out_f:
                while True:
                    chunk = await field.read_chunk(65536)
                    if not chunk:
                        break
                    size_written += len(chunk)
                    if size_written > 150 * 1024 * 1024:  # 150 MB hard cap
                        out_f.close()
                        dest.unlink(missing_ok=True)
                        return web.json_response(
                            {"status": "error", "message": "File exceeds 150 MB upload limit"},
                            status=413,
                        )
                    out_f.write(chunk)

            # Ingest via WorkspaceManager. Skip indexing if ?ingest=false (for batch uploads).
            ingest_now = request.query.get("ingest", "true").lower() != "false"
            result = mgr.ingest_file(str(dest), rebuild=ingest_now)
            if result.get("status") == "error":
                return web.json_response(result, status=422)

            return web.json_response({
                "status": "success",
                "file": safe_name,
                "workspace_path": str(dest),
                "size_bytes": size_written,
                "index_summary": result.get("index_summary", {}),
            })

        except Exception as exc:
            logger.error("Workspace upload failed: %s", exc)
            return web.json_response({"status": "error", "message": str(exc)}, status=500)

    async def _handle_workspace_reindex(self, request: web.Request) -> web.Response:
        """Trigger a full workspace re-index (chunking) after batch uploads.

        Runs the CPU-bound rebuild in a thread so the event loop stays
        responsive, and enforces an overall timeout so the app always
        receives a response instead of hanging forever.
        """
        try:
            from workspace import WorkspaceManager
            mgr = WorkspaceManager()
            loop = asyncio.get_running_loop()
            try:
                summary = await asyncio.wait_for(
                    loop.run_in_executor(None, mgr.rebuild_index),
                    timeout=240,
                )
            except asyncio.TimeoutError:
                logger.error("Workspace reindex timed out after 240s")
                return web.json_response({
                    "status": "error",
                    "message": "Reindex timed out after 240s (oversized file or hung extractor)",
                }, status=504)
            return web.json_response({
                "status": "success",
                "index_summary": summary,
            })
        except Exception as exc:
            logger.error("Workspace reindex failed: %s", exc)
            return web.json_response({"status": "error", "message": str(exc)}, status=500)

    async def _handle_workspace_clear(self, request: web.Request) -> web.Response:
        """Clear previous-session documents so a new session gets a clean quota."""
        try:
            from workspace import WorkspaceManager
            return web.json_response(WorkspaceManager().clear_session_documents())
        except Exception as exc:
            logger.error("Workspace clear failed: %s", exc)
            return web.json_response({"status": "error", "message": str(exc)}, status=500)

    async def _handle_workspace_deps(self, request: web.Request) -> web.Response:
        """Return dependency status for workspace document extraction."""
        try:
            from workspace import WorkspaceManager
            mgr = WorkspaceManager()
            deps = mgr.check_dependencies()
            return web.json_response(deps)
        except Exception as exc:
            logger.error("Workspace dep check failed: %s", exc)
            return web.json_response({"error": str(exc)}, status=500)

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
                # Legacy ingest was removed; all evidence now flows through
                # update_phase / read_url / export_*.
                if method == "deep_research.ingest":
                    return web.json_response(
                        {
                            "error": (
                                "deep_research.ingest is no longer supported. "
                                "Use read_url + deep_research.update_phase instead."
                            )
                        },
                        status=410,
                    )
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
            async def _run_notification():
                try:
                    await self.router.dispatch(request)
                except Exception:
                    logger.exception("Notification handler error: %s", request.method)
            asyncio.create_task(_run_notification())
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
        self._http_app = web.Application(client_max_size=200 * 1024 * 1024)  # 200 MB upload limit (allows 150MB files)
        self._http_app.router.add_post('/mcp', self._handle_http_post)
        self._http_app.router.add_post('/workspace/upload', self._handle_workspace_upload)
        self._http_app.router.add_post('/workspace/reindex', self._handle_workspace_reindex)
        self._http_app.router.add_post('/workspace/clear', self._handle_workspace_clear)
        self._http_app.router.add_get('/workspace/deps', self._handle_workspace_deps)
        
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
        self._http_app.router.add_options('/workspace/upload', handle_options)
        
        self._http_runner = web.AppRunner(self._http_app)
        await self._http_runner.setup()
        self._http_site = web.TCPSite(self._http_runner, self.host, 8390)
        await self._http_site.start()

        # Background embedding worker task is no longer needed since RAG/vector-embedding has been removed.
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
