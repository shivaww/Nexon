"""
TermuxForge MCP Manager
=========================

Manages MCP (Model Context Protocol) servers, including lifecycle
management, health checks, tool discovery, request routing, and
support for stdio, SSE, and HTTP transports.
"""

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger("termux_forge.mcp_manager")

CONFIG_DIR = os.path.expanduser("~/.termux_forge/mcp")


class TransportType(Enum):
    """Supported MCP transport types."""

    STDIO = "stdio"
    SSE = "sse"
    HTTP = "http"


class ServerStatus(Enum):
    """MCP server lifecycle status."""

    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    ERROR = "error"
    STOPPING = "stopping"


@dataclass
class McpServerConfig:
    """
    Configuration for an MCP server.

    Attributes
    ----------
    name : str
        Unique server identifier.
    command : str
        Executable command (for stdio transport).
    args : list[str]
        Command arguments.
    env : dict[str, str]
        Environment variables for the server process.
    transport : TransportType
        Transport type to use.
    url : str
        Server URL (for SSE/HTTP transports).
    enabled : bool
        Whether the server is enabled.
    auto_start : bool
        Whether to start the server automatically.
    health_interval : int
        Seconds between health checks (0 = disabled).
    """

    name: str
    command: str = ""
    args: list[str] = field(default_factory=list)
    env: dict[str, str] = field(default_factory=dict)
    transport: TransportType = TransportType.STDIO
    url: str = ""
    enabled: bool = True
    auto_start: bool = False
    health_interval: int = 30

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "command": self.command,
            "args": self.args,
            "env": {k: "***" for k in self.env},  # Redact secrets
            "transport": self.transport.value,
            "url": self.url,
            "enabled": self.enabled,
            "autoStart": self.auto_start,
            "healthInterval": self.health_interval,
        }


@dataclass
class McpServerState:
    """Runtime state for an MCP server."""

    config: McpServerConfig
    status: ServerStatus = ServerStatus.STOPPED
    process: Optional[asyncio.subprocess.Process] = field(default=None, repr=False)
    tools: list[dict[str, Any]] = field(default_factory=list)
    last_health: float = 0.0
    error_message: str = ""
    start_time: float = 0.0
    lock: asyncio.Lock = field(default_factory=asyncio.Lock, repr=False)

    def to_dict(self) -> dict[str, Any]:
        uptime = time.time() - self.start_time if self.start_time else 0
        return {
            "name": self.config.name,
            "status": self.status.value,
            "transport": self.config.transport.value,
            "tools": self.tools,
            "lastHealth": self.last_health,
            "error": self.error_message,
            "uptime": round(uptime, 1),
        }


# ── Well-known MCP server presets ─────────────────────────────────────

PRESETS: dict[str, dict[str, Any]] = {
    "filesystem": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/data/data/com.termux/files/home"],
        "transport": "stdio",
    },
    "github": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-github"],
        "transport": "stdio",
        "env_keys": ["GITHUB_PERSONAL_ACCESS_TOKEN"],
    },
    "postgres": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-postgres"],
        "transport": "stdio",
        "env_keys": ["POSTGRES_CONNECTION_STRING"],
    },
    "brave-search": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-brave-search"],
        "transport": "stdio",
        "env_keys": ["BRAVE_API_KEY"],
    },
    "tavily": {
        "command": "npx",
        "args": ["-y", "tavily-mcp-server"],
        "transport": "stdio",
        "env_keys": ["TAVILY_API_KEY"],
    },
    "firecrawl": {
        "command": "npx",
        "args": ["-y", "firecrawl-mcp"],
        "transport": "stdio",
        "env_keys": ["FIRECRAWL_API_KEY"],
    },
    "supabase": {
        "command": "npx",
        "args": ["-y", "supabase-mcp-server"],
        "transport": "stdio",
        "env_keys": ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"],
    },
    "notion": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-notion"],
        "transport": "stdio",
        "env_keys": ["NOTION_API_KEY"],
    },
    "slack": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-slack"],
        "transport": "stdio",
        "env_keys": ["SLACK_BOT_TOKEN"],
    },
    "discord": {
        "command": "npx",
        "args": ["-y", "discord-mcp-server"],
        "transport": "stdio",
        "env_keys": ["DISCORD_BOT_TOKEN"],
    },
}


class McpManager:
    """
    Manages the lifecycle of multiple MCP servers.

    Provides methods to start, stop, health-check, and discover
    tools from MCP servers running in various transports.
    """

    def __init__(self) -> None:
        self._servers: dict[str, McpServerState] = {}
        self._health_tasks: dict[str, asyncio.Task] = {}
        os.makedirs(CONFIG_DIR, exist_ok=True)

    # ── Server lifecycle ──────────────────────────────────────────────

    async def start_server(self, config: McpServerConfig) -> dict[str, Any]:
        """
        Start an MCP server with the given configuration.

        Returns status information about the started server.
        """
        name = config.name
        logger.info("Starting MCP server: %s", name)

        if name in self._servers and self._servers[name].status == ServerStatus.RUNNING:
            return {"status": "already_running", **self._servers[name].to_dict()}

        state = McpServerState(config=config, status=ServerStatus.STARTING)
        self._servers[name] = state

        try:
            if config.transport == TransportType.STDIO:
                await self._start_stdio(state)
            elif config.transport == TransportType.SSE:
                state.status = ServerStatus.RUNNING
                state.start_time = time.time()
                logger.info("SSE server registered: %s → %s", name, config.url)
            elif config.transport == TransportType.HTTP:
                state.status = ServerStatus.RUNNING
                state.start_time = time.time()
                logger.info("HTTP server registered: %s → %s", name, config.url)

            # Start health monitoring
            if config.health_interval > 0:
                self._health_tasks[name] = asyncio.create_task(
                    self._health_loop(name, config.health_interval)
                )

            self._save_config(config)
            return {"status": "started", **state.to_dict()}

        except Exception as exc:
            state.status = ServerStatus.ERROR
            state.error_message = str(exc)
            logger.exception("Failed to start MCP server: %s", name)
            return {"status": "error", "error": str(exc)}

    async def stop_server(self, name: str) -> dict[str, Any]:
        """Stop a running MCP server."""
        state = self._servers.get(name)
        if not state:
            return {"status": "not_found", "name": name}

        logger.info("Stopping MCP server: %s", name)
        state.status = ServerStatus.STOPPING

        # Cancel health monitoring
        task = self._health_tasks.pop(name, None)
        if task:
            task.cancel()

        # Terminate process
        if state.process:
            try:
                state.process.terminate()
                await asyncio.wait_for(state.process.wait(), timeout=5)
            except asyncio.TimeoutError:
                state.process.kill()
                await state.process.wait()
            except ProcessLookupError:
                pass

        state.status = ServerStatus.STOPPED
        state.process = None
        state.start_time = 0
        return {"status": "stopped", "name": name}

    async def restart_server(self, name: str) -> dict[str, Any]:
        """Restart an MCP server by stopping and starting it."""
        state = self._servers.get(name)
        if not state:
            return {"status": "not_found", "name": name}
        await self.stop_server(name)
        return await self.start_server(state.config)

    # ── Health checking ───────────────────────────────────────────────

    async def health_check(self, name: str) -> dict[str, Any]:
        """
        Perform a health check on a server.

        Returns status including whether the server process is alive.
        """
        state = self._servers.get(name)
        if not state:
            return {"name": name, "healthy": False, "error": "Server not found"}

        healthy = False

        if state.config.transport == TransportType.STDIO:
            healthy = (
                state.process is not None
                and state.process.returncode is None
            )
        elif state.config.transport in (TransportType.SSE, TransportType.HTTP):
            healthy = await self._http_health_check(state.config.url)

        state.last_health = time.time()
        if not healthy and state.status == ServerStatus.RUNNING:
            state.status = ServerStatus.ERROR
            state.error_message = "Health check failed"

        return {
            "name": name,
            "healthy": healthy,
            "status": state.status.value,
            "lastCheck": state.last_health,
        }

    # ── Tool discovery ────────────────────────────────────────────────

    async def discover_tools(self, name: str) -> list[dict[str, Any]]:
        """
        Discover available tools from an MCP server.

        For stdio-based servers, sends a ``tools/list`` request.
        """
        state = self._servers.get(name)
        if not state or state.status != ServerStatus.RUNNING:
            logger.warning("Cannot discover tools: %s not running", name)
            return []

        try:
            if state.config.transport == TransportType.STDIO:
                tools = await self._stdio_tools_list(state)
            elif state.config.transport in (TransportType.SSE, TransportType.HTTP):
                tools = await self._http_tools_list(state)
            else:
                tools = []

            state.tools = tools
            logger.info("Discovered %d tools from %s", len(tools), name)
            return tools

        except Exception as exc:
            logger.error("Tool discovery failed for %s: %s", name, exc)
            return []

    async def discover_all_tools(self) -> dict[str, list[dict[str, Any]]]:
        """Discover tools from all running servers."""
        results = {}
        for name, state in self._servers.items():
            if state.status == ServerStatus.RUNNING:
                results[name] = await self.discover_tools(name)
        return results

    # ── Request routing ───────────────────────────────────────────────

    async def route_request(
        self,
        server_name: str,
        method: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """
        Route a JSON-RPC request to a specific MCP server.

        Parameters
        ----------
        server_name : str
            Target server name.
        method : str
            JSON-RPC method name.
        params : dict, optional
            Method parameters.

        Returns
        -------
        dict
            Server response or error.
        """
        state = self._servers.get(server_name)
        if not state:
            return {"error": f"Server not found: {server_name}"}
        if state.status != ServerStatus.RUNNING:
            return {"error": f"Server not running: {server_name}"}

        request = {
            "jsonrpc": "2.0",
            "id": int(time.time() * 1000),
            "method": method,
            "params": params or {},
        }

        try:
            if state.config.transport == TransportType.STDIO:
                return await self._stdio_request(state, request)
            elif state.config.transport in (TransportType.SSE, TransportType.HTTP):
                return await self._http_request(state, request)
            return {"error": f"Unsupported transport: {state.config.transport.value}"}
        except Exception as exc:
            logger.error("MCP request failed (%s): %s", server_name, exc)
            return {"error": str(exc)}

    # ── Listing & presets ─────────────────────────────────────────────

    def list_servers(self) -> list[dict[str, Any]]:
        """Return information about all managed servers."""
        return [state.to_dict() for state in self._servers.values()]

    def list_presets(self) -> dict[str, dict[str, Any]]:
        """Return available server presets."""
        return dict(PRESETS)

    async def start_from_preset(
        self,
        preset_name: str,
        env: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """
        Start a server from a preset configuration.

        Parameters
        ----------
        preset_name : str
            Name of the preset (e.g., "github", "filesystem").
        env : dict, optional
            Environment variables (e.g., API keys).
        """
        preset = PRESETS.get(preset_name)
        if not preset:
            return {"error": f"Unknown preset: {preset_name}", "available": list(PRESETS.keys())}

        config = McpServerConfig(
            name=preset_name,
            command=preset["command"],
            args=preset.get("args", []),
            env=env or {},
            transport=TransportType(preset.get("transport", "stdio")),
            url=preset.get("url", ""),
        )
        return await self.start_server(config)

    # ── Shutdown ──────────────────────────────────────────────────────

    async def shutdown(self) -> None:
        """Stop all running servers and clean up."""
        logger.info("Shutting down all MCP servers…")
        for name in list(self._servers.keys()):
            await self.stop_server(name)

    # ── Private: stdio transport ──────────────────────────────────────

    async def _start_stdio(self, state: McpServerState) -> None:
        """Start a stdio-based MCP server as a subprocess."""
        env = dict(os.environ)
        env.update(state.config.env)

        cmd = [state.config.command] + state.config.args
        state.process = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )
        state.status = ServerStatus.RUNNING
        state.start_time = time.time()
        logger.info(
            "Started stdio MCP server: %s (PID %d)",
            state.config.name, state.process.pid,
        )

    async def _stdio_request(
        self, state: McpServerState, request: dict,
    ) -> dict[str, Any]:
        """Send a JSON-RPC request over stdio and read the response."""
        if not state.process or not state.process.stdin or not state.process.stdout:
            return {"error": "Server process not available"}

        async with state.lock:
            payload = json.dumps(request) + "\n"
            state.process.stdin.write(payload.encode())
            await state.process.stdin.drain()

            try:
                line = await asyncio.wait_for(
                    state.process.stdout.readline(), timeout=30,
                )
                return json.loads(line.decode())
            except asyncio.TimeoutError:
                return {"error": "Stdio request timed out"}
            except json.JSONDecodeError:
                return {"error": "Invalid JSON response from server"}

    async def _stdio_tools_list(self, state: McpServerState) -> list[dict]:
        """Request tool list from a stdio server."""
        response = await self._stdio_request(
            state, {
                "jsonrpc": "2.0", "id": 1,
                "method": "tools/list", "params": {},
            },
        )
        return response.get("result", {}).get("tools", [])

    # ── Private: HTTP / SSE transport ─────────────────────────────────

    async def _http_health_check(self, url: str) -> bool:
        """Check if an HTTP/SSE endpoint is reachable."""
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{url}/health", timeout=aiohttp.ClientTimeout(total=5),
                ) as resp:
                    return resp.status == 200
        except Exception:
            return False

    async def _http_request(
        self, state: McpServerState, request: dict,
    ) -> dict[str, Any]:
        """Send a JSON-RPC request over HTTP."""
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    state.config.url,
                    json=request,
                    timeout=aiohttp.ClientTimeout(total=30),
                ) as resp:
                    return await resp.json()
        except Exception as exc:
            return {"error": str(exc)}

    async def _http_tools_list(self, state: McpServerState) -> list[dict]:
        """Request tool list from an HTTP server."""
        response = await self._http_request(
            state, {
                "jsonrpc": "2.0", "id": 1,
                "method": "tools/list", "params": {},
            },
        )
        return response.get("result", {}).get("tools", [])

    # ── Private: health loop ──────────────────────────────────────────

    async def _health_loop(self, name: str, interval: int) -> None:
        """Periodic health check for a server."""
        while True:
            await asyncio.sleep(interval)
            try:
                await self.health_check(name)
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.error("Health loop error for %s: %s", name, exc)

    # ── Private: config persistence ───────────────────────────────────

    def _save_config(self, config: McpServerConfig) -> None:
        """Persist a server configuration to disk."""
        path = os.path.join(CONFIG_DIR, f"{config.name}.json")
        try:
            data = config.to_dict()
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
        except Exception as exc:
            logger.error("Failed to save config for %s: %s", config.name, exc)

    def load_configs(self) -> list[McpServerConfig]:
        """Load all saved server configurations from disk."""
        configs = []
        if not os.path.isdir(CONFIG_DIR):
            return configs
        for fname in os.listdir(CONFIG_DIR):
            if not fname.endswith(".json"):
                continue
            path = os.path.join(CONFIG_DIR, fname)
            try:
                with open(path) as f:
                    data = json.load(f)
                configs.append(McpServerConfig(
                    name=data["name"],
                    command=data.get("command", ""),
                    args=data.get("args", []),
                    transport=TransportType(data.get("transport", "stdio")),
                    url=data.get("url", ""),
                    enabled=data.get("enabled", True),
                    auto_start=data.get("autoStart", False),
                    health_interval=data.get("healthInterval", 30),
                ))
            except Exception as exc:
                logger.error("Failed to load config %s: %s", fname, exc)
        return configs
