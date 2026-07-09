"""
TermuxForge Background Service Manager
=========================================

Handles long-running processes (HTTP servers, MCP servers, dev servers,
file watchers, etc.) so AI models get immediate, rich feedback instead
of a hanging connection.

Core problem solved
-------------------
When an AI runs ``python3 -m http.server 8080``, the process never exits.
The bridge hangs. The AI never learns if it worked or what port to share.

Solution
--------
1. Detect server-like commands automatically via pattern matching.
2. Launch them as detached background processes with log capture.
3. Wait a configurable startup window (default 4 s) collecting output.
4. Detect which ports the process bound to using /proc/net/tcp.
5. Verify readiness by connecting to each detected port.
6. Return a rich AI block with: status, URL(s), PID, how to stop, logs.
7. Persist the process registry so ``list_services`` works across calls.

AI Output Example
-----------------

    ╔══ SERVICE STARTED ═══════════════════════════════════════════════╗
    ║  python3 -m http.server 8080                                     ║
    ║  PID: 14337  │  Port: 8080  │  Status: ✓ LISTENING             ║
    ╚══════════════════════════════════════════════════════════════════╝

    🌐  http://localhost:8080
    📋  Copy & paste in browser: http://127.0.0.1:8080

    STARTUP OUTPUT (first 4s):
      Serving HTTP on 0.0.0.0 port 8080 (http://0.0.0.0:8080/) ...

    ── MANAGE THIS SERVICE ──────────────────────────────────────────
    • service_status  pid=14337
    • service_logs    pid=14337  lines=50
    • stop_service    pid=14337
    • list_services
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import signal
import socket
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger("termux_forge.service_manager")

# ── Paths ─────────────────────────────────────────────────────────────

HOME = os.path.expanduser("~")
SERVICES_DIR = Path(HOME) / ".termux_forge" / "services"
REGISTRY_FILE = SERVICES_DIR / "registry.json"
SHELL = os.environ.get("SHELL", "/data/data/com.termux/files/usr/bin/bash")
TERMUX_BIN = "/data/data/com.termux/files/usr/bin"

# ── Server command detection patterns ─────────────────────────────────

# Each entry: (regex_pattern, default_port, service_type_label)
SERVER_PATTERNS: list[tuple[re.Pattern, int | None, str]] = [
    # Python servers
    (re.compile(r"python3?\s+.*-m\s+http\.server"),           8000, "Python HTTP Server"),
    (re.compile(r"python3?\s+.*-m\s+flask"),                   5000, "Flask Dev Server"),
    (re.compile(r"python3?\s+.*-m\s+uvicorn"),                 8000, "Uvicorn ASGI"),
    (re.compile(r"python3?\s+.*-m\s+gunicorn"),                8000, "Gunicorn WSGI"),
    (re.compile(r"python3?\s+.*-m\s+fastapi"),                 8000, "FastAPI"),
    (re.compile(r"python3?\s+.*-m\s+mcp"),                     None, "MCP Server"),
    (re.compile(r"fastapi\s+(?:dev|run)"),                     8000, "FastAPI"),
    (re.compile(r"uvicorn\s+"),                                 8000, "Uvicorn ASGI"),
    (re.compile(r"gunicorn\s+"),                                8000, "Gunicorn WSGI"),
    (re.compile(r"flask\s+run"),                               5000, "Flask Dev Server"),
    (re.compile(r"python3?\s+\S*(?:server|app|main|index)\.py"), None, "Python Server"),
    (re.compile(r"python3?\s+\S*mcp\S*\.py"),                  None, "MCP Server"),
    (re.compile(r"uv\s+run\s+\S*(?:server|app|index|main|mcp)\.py"), None, "Python Server (uv)"),
    (re.compile(r"uv\s+run\s+-m\s+\S+"),                       None, "Python Server (uv)"),

    # Node.js / JavaScript / TypeScript / Bun / Deno
    (re.compile(r"node\s+\S*(?:server|app|index|main)\.js"),   3000, "Node.js Server"),
    (re.compile(r"node\s+"),                                     3000, "Node.js Process"),
    (re.compile(r"npm\s+(?:start|run\s+dev|run\s+start)"),     3000, "Node.js Dev Server"),
    (re.compile(r"npx\s+serve"),                               5000, "npx serve"),
    (re.compile(r"npx\s+(?:vite|webpack-dev-server|parcel)"),  5173, "Vite/Webpack Dev"),
    (re.compile(r"npx\s+next\s+(?:dev|start)"),                3000, "Next.js Server"),
    (re.compile(r"yarn\s+(?:start|dev)"),                       3000, "Yarn Dev Server"),
    (re.compile(r"bun\s+(?:run\s+)?(?:dev|start|server|app)"), 3000, "Bun Dev Server"),
    (re.compile(r"deno\s+run\s+.*(?:server|app|index|main|mcp)"), 8000, "Deno Server"),

    # Specific well-known tools
    (re.compile(r"live-server"),                               5500, "Live Server"),
    (re.compile(r"http-server"),                               8080, "http-server"),
    (re.compile(r"lite-server"),                               3000, "lite-server"),
    (re.compile(r"mkdocs\s+serve"),                            8000, "MkDocs Server"),
    (re.compile(r"jekyll\s+serve"),                            4000, "Jekyll Server"),
    (re.compile(r"hugo\s+server"),                             1313, "Hugo Server"),

    # MCP / AI tooling
    (re.compile(r"python3?\s+.*mcp"),                          None, "MCP Server"),
    (re.compile(r"uvx\s+"),                                     None, "uvx Process"),

    # Ruby
    (re.compile(r"ruby\s+.*server"),                            4567, "Ruby Server"),
    (re.compile(r"rails\s+server"),                             3000, "Rails Server"),

    # Generic daemon keywords
    (re.compile(r"\b(?:serve|server|daemon|watch)\b"),          None, "Generic Server"),
]

# Port regex — extract explicit port numbers from a command
PORT_IN_CMD = re.compile(
    r"(?:--port|-p|:)\s*(\d{2,5})|"          # --port 8080, -p 8080, :8080
    r"\b(8000|8080|8888|3000|3001|4000|"
    r"4200|5000|5173|5500|6000|7000|8765|"
    r"9000|9090|1313|4567|3333|4321)\b|"
    r"\b(\d{4,5})\b"                         # Any other 4-5 digit number
)

# ── Helpers ───────────────────────────────────────────────────────────

def _env() -> dict[str, str]:
    env = dict(os.environ)
    current_path = env.get("PATH", "")
    if TERMUX_BIN not in current_path:
        env["PATH"] = f"{TERMUX_BIN}:{current_path}"
    return env


def _human_age(ts: float) -> str:
    age = time.time() - ts
    if age < 60:
        return f"{int(age)}s ago"
    if age < 3600:
        return f"{int(age // 60)}m ago"
    return f"{int(age // 3600)}h ago"


def _port_open(port: int, host: str = "127.0.0.1", timeout: float = 0.5) -> bool:
    """Return True if a TCP port is accepting connections."""
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (OSError, ConnectionRefusedError, TimeoutError):
        return False


def _get_listening_ports_proc() -> set[int]:
    """
    Read listening TCP ports from /proc/net/tcp (and tcp6) without external tools.

    /proc/net/tcp lines look like:
      sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt uid ...
       0: 00000000:1F90 00000000:0000 0A ...

    State 0A = TCP_LISTEN. local_address is hex: ADDR:PORT (big-endian on ARM).
    """
    ports: set[int] = set()
    for fname in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(fname) as f:
                for line in f:
                    parts = line.split()
                    if len(parts) < 4:
                        continue
                    if parts[3] != "0A":   # 0A = LISTEN
                        continue
                    local = parts[1]
                    port_hex = local.split(":")[1] if ":" in local else local[-4:]
                    try:
                        ports.add(int(port_hex, 16))
                    except ValueError:
                        pass
        except OSError:
            pass
    return ports


# ══════════════════════════════════════════════════════════════════════
#  DATA MODEL
# ══════════════════════════════════════════════════════════════════════

@dataclass
class ServiceRecord:
    """Persisted record of a background service."""
    pid: int
    command: str
    cwd: str
    name: str
    service_type: str
    log_file: str
    started_at: float
    ports: list[int] = field(default_factory=list)
    urls: list[str] = field(default_factory=list)
    status: str = "running"  # running | stopped | crashed

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "ServiceRecord":
        return cls(**{k: v for k, v in d.items() if k in cls.__dataclass_fields__})

    def is_alive(self) -> bool:
        """Check if the process is still running."""
        if self.pid <= 0:
            return False
        try:
            os.kill(self.pid, 0)  # signal 0 = probe
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True  # exists but we can't signal it

    def ai_status_line(self) -> str:
        alive = self.is_alive()
        if alive:
            ports_str = ", ".join(str(p) for p in self.ports) if self.ports else "unknown"
            url_str = self.urls[0] if self.urls else "—"
            return f"✓ RUNNING  PID={self.pid}  Ports={ports_str}  URL={url_str}  Age={_human_age(self.started_at)}"
        return f"✗ STOPPED  PID={self.pid}  Stopped {_human_age(self.started_at)}"


# ══════════════════════════════════════════════════════════════════════
#  SERVICE DETECTOR
# ══════════════════════════════════════════════════════════════════════

def detect_server_command(command: str) -> tuple[bool, int | None, str]:
    """
    Detect whether a shell command starts a long-running server.

    Returns
    -------
    (is_server, detected_port, service_type)
        is_server : bool
        detected_port : int | None — explicit port found in the command, or default
        service_type : str — human-readable label
    """
    cmd = command.strip()

    # Background already requested by user
    if cmd.endswith("&") or " & " in cmd:
        return False, None, ""   # already handled by shell

    # Check against known patterns
    for pattern, default_port, label in SERVER_PATTERNS:
        if pattern.search(cmd):
            # Try to extract explicit port from command
            port_match = PORT_IN_CMD.search(cmd)
            explicit_port = None
            if port_match:
                raw = port_match.group(1) or port_match.group(2) or port_match.group(3)
                if raw:
                    try:
                        explicit_port = int(raw)
                    except ValueError:
                        pass
            detected_port = explicit_port or default_port
            return True, detected_port, label

    return False, None, ""


# ══════════════════════════════════════════════════════════════════════
#  MANAGER
# ══════════════════════════════════════════════════════════════════════

class BackgroundServiceManager:
    """
    Manages long-running background processes (servers, daemons, watchers).

    Lifecycle:
    1. ``start_service`` — launch a process, capture startup output, detect ports.
    2. ``list_services`` — enumerate all tracked services with live status.
    3. ``service_status`` — detailed status for a specific PID.
    4. ``service_logs`` — tail the log file of a service.
    5. ``stop_service`` — gracefully terminate (SIGTERM → SIGKILL).

    The service registry is persisted to disk so state survives bridge restarts.
    """

    def __init__(self) -> None:
        SERVICES_DIR.mkdir(parents=True, exist_ok=True)
        self._registry: dict[int, ServiceRecord] = {}
        self._load_registry()

    # ── Registry persistence ──────────────────────────────────────────

    def _load_registry(self) -> None:
        if REGISTRY_FILE.exists():
            try:
                data = json.loads(REGISTRY_FILE.read_text())
                for item in data:
                    try:
                        rec = ServiceRecord.from_dict(item)
                        self._registry[rec.pid] = rec
                    except Exception as e:
                        logger.warning("Skipping corrupt registry entry: %s", e)
            except Exception as e:
                logger.warning("Could not load service registry: %s", e)

    def _save_registry(self) -> None:
        try:
            data = [rec.to_dict() for rec in self._registry.values()]
            REGISTRY_FILE.write_text(json.dumps(data, indent=2))
        except Exception as e:
            logger.warning("Could not save service registry: %s", e)

    def _update_status(self, rec: ServiceRecord) -> None:
        """Refresh alive/stopped status and persist."""
        if not rec.is_alive():
            rec.status = "stopped"
        self._save_registry()

    # ── Start ─────────────────────────────────────────────────────────

    async def start_service(
        self,
        command: str,
        cwd: str = HOME,
        name: str = "",
        startup_wait: float = 4.0,
        env: dict[str, str] | None = None,
        service_type: str = "Server",
    ) -> dict[str, Any]:
        """
        Launch a command as a background service and return a rich AI block.

        Parameters
        ----------
        command : str
            Shell command to run (no trailing &).
        cwd : str
            Working directory.
        name : str
            Optional human name for the service.
        startup_wait : float
            Seconds to wait collecting startup output before returning.
        env : dict, optional
            Extra environment variables.
        service_type : str
            Human-readable type label shown in the output block.
        """
        cwd = cwd or HOME
        if not os.path.isdir(cwd):
            cwd = HOME

        # Create log file
        ts = int(time.time())
        safe_name = re.sub(r"[^\w]", "_", name or command[:30])
        log_file = str(SERVICES_DIR / f"{safe_name}_{ts}.log")

        # Sample ports BEFORE starting so we can detect new ones
        ports_before = _get_listening_ports_proc()

        # Detect expected port from command
        _, expected_port, auto_type = detect_server_command(command)
        if auto_type and not service_type:
            service_type = auto_type
        if not name:
            name = auto_type or command[:40]

        # Build full env
        full_env = _env()
        if env:
            full_env.update(env)

        # Launch the process — stdout/stderr → log file + we capture via pipe
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=cwd,
            env=full_env,
            executable=SHELL,
            # start_new_session=True makes the process survive even if the
            # bridge restarts, and prevents SIGINT from propagating to it.
            start_new_session=True,
        )

        pid = proc.pid
        started_at = time.time()
        startup_lines: list[str] = []

        # ── Collect startup output for `startup_wait` seconds ──
        async def _read_startup() -> None:
            try:
                while True:
                    line = await asyncio.wait_for(
                        proc.stdout.readline(),  # type: ignore[union-attr]
                        timeout=0.5,
                    )
                    if not line:
                        break
                    decoded = line.decode("utf-8", errors="replace")
                    startup_lines.append(decoded.rstrip())
                    # Write to log file
                    try:
                        with open(log_file, "a", encoding="utf-8") as lf:
                            lf.write(decoded)
                    except OSError:
                        pass
            except asyncio.TimeoutError:
                pass
            except Exception:
                pass

        # Kick off background reader and wait startup_wait seconds
        reader_task = asyncio.create_task(_read_startup())
        await asyncio.sleep(startup_wait)

        # Check if process is still alive (didn't crash in first 4s)
        alive = proc.returncode is None
        if not alive:
            reader_task.cancel()
            rc = proc.returncode or -1
            return self._crash_block(command, pid, rc, startup_lines, log_file, cwd)

        # ── Detect bound ports ──
        ports_after = _get_listening_ports_proc()
        new_ports = sorted(p for p in (ports_after - ports_before)
                           if 1024 <= p <= 65535)

        # Prefer detected new ports; fallback to expected port from pattern
        final_ports = new_ports or ([expected_port] if expected_port else [])

        # Verify readiness by attempting TCP connection
        confirmed_ports: list[int] = []
        for p in final_ports:
            if _port_open(p):
                confirmed_ports.append(p)

        # Accept unconfirmed ports if no confirmed ones (e.g. MCP stdio)
        serving_ports = confirmed_ports or final_ports

        # Build URLs
        urls = [f"http://localhost:{p}" for p in serving_ports]
        urls_127 = [f"http://127.0.0.1:{p}" for p in serving_ports]

        # ── Create record ──
        rec = ServiceRecord(
            pid=pid,
            command=command,
            cwd=cwd,
            name=name,
            service_type=service_type,
            log_file=log_file,
            started_at=started_at,
            ports=serving_ports,
            urls=urls,
            status="running",
        )
        self._registry[pid] = rec
        self._save_registry()

        # Continue draining output in background → log file
        async def _drain_to_log() -> None:
            try:
                async for line in proc.stdout:  # type: ignore[union-attr]
                    try:
                        with open(log_file, "a", encoding="utf-8") as lf:
                            lf.write(line.decode("utf-8", errors="replace"))
                    except OSError:
                        break
            except Exception:
                pass

        asyncio.create_task(_drain_to_log())
        reader_task.cancel()

        return self._success_block(rec, startup_lines, urls, urls_127, confirmed_ports)

    # ── Rich output blocks ─────────────────────────────────────────────

    def _success_block(
        self,
        rec: ServiceRecord,
        startup_lines: list[str],
        urls: list[str],
        urls_127: list[str],
        confirmed: list[int],
    ) -> dict[str, Any]:
        """Build the rich AI-readable success block."""
        W = 66
        H = "─"
        TL, TR, BL, BR, V = "╔", "╗", "╚", "╝", "║"

        port_str = ", ".join(str(p) for p in rec.ports) if rec.ports else "detecting…"
        status_str = "✓ LISTENING" if confirmed else "✓ RUNNING (port TBD)"
        title = f" SERVICE STARTED "
        pad = W - len(title) - 2
        box = [
            f"{TL}{H}{title}{H * pad}{TR}",
            f"{V}  {rec.name[:60]:<60}{V}",
            f"{V}  PID: {rec.pid}  │  Port: {port_str}  │  {status_str:<20}{V}" if len(f"  PID: {rec.pid}  │  Port: {port_str}  │  {status_str}  ") <= W else f"{V}  PID: {rec.pid}  │  {status_str:<50}{V}",
            f"{BL}{H * (W - 2)}{BR}",
        ]

        parts = ["\n".join(box)]

        # URLs section
        if urls:
            parts.append("")
            for url in urls:
                parts.append(f"  🌐  {url}")
            if urls_127 and urls_127 != urls:
                for u127 in urls_127:
                    parts.append(f"  📋  Copy & paste in browser: {u127}")
            else:
                for u127 in urls_127:
                    parts.append(f"  📋  Copy & paste in browser: {u127}")
        else:
            parts.append("\n  ℹ️  No HTTP port detected. This may be a stdio/socket service.")
            parts.append(f"     Check logs: service_logs pid={rec.pid}")

        # Startup output
        parts.append(f"\n{H * W}")
        parts.append("  STARTUP OUTPUT (first 4s):")
        if startup_lines:
            shown = startup_lines[:30]
            for line in shown:
                parts.append(f"    {line}")
            if len(startup_lines) > 30:
                parts.append(f"    … ({len(startup_lines) - 30} more lines in log)")
        else:
            parts.append("    (no output yet — service may be initializing)")

        # Management commands
        parts.append(f"\n{H * W}")
        parts.append("  MANAGE THIS SERVICE:")
        parts.append(f"  • Check status:  service_status  pid={rec.pid}")
        parts.append(f"  • Tail logs:     service_logs    pid={rec.pid}  lines=50")
        parts.append(f"  • Stop service:  stop_service    pid={rec.pid}")
        parts.append(f"  • All services:  list_services")
        parts.append(f"  • Log file:      {rec.log_file}")
        parts.append(f"{H * W}")

        block = "\n".join(parts)
        return {
            "stdout": block,
            "exitCode": 0,
            "success": True,
            "pid": rec.pid,
            "ports": rec.ports,
            "urls": urls,
            "urls127": urls_127,
            "logFile": rec.log_file,
            "serviceType": rec.service_type,
            "startedAt": rec.started_at,
        }

    def _crash_block(
        self,
        command: str,
        pid: int,
        exit_code: int,
        output: list[str],
        log_file: str,
        cwd: str,
    ) -> dict[str, Any]:
        """Block returned when the service crashes during startup."""
        W = 66
        H = "─"
        parts = [
            f"╔{H} SERVICE CRASHED {H * 46}╗",
            f"║  Command: {command[:55]:<55}║",
            f"║  PID: {pid}  │  Exit code: {exit_code}  │  ✗ FAILED to start  ║",
            f"╚{H * (W - 2)}╝",
            "",
            "  CRASH OUTPUT:",
        ]
        for line in output[:40]:
            parts.append(f"    {line}")
        parts += [
            f"\n{H * W}",
            "  NEXT STEPS:",
            "  • Check the output above for the error message",
            "  • Verify all dependencies are installed",
            "  • Check the port isn't already in use: <command>ss -tlnp | grep PORT</command>",
            "  • If import error: <command>pip install PACKAGE</command>",
            f"  • Log file: {log_file}",
            f"{H * W}",
        ]
        return {
            "stdout": "\n".join(parts),
            "exitCode": exit_code,
            "success": False,
            "crashed": True,
            "pid": pid,
        }

    # ── List services ──────────────────────────────────────────────────

    def list_services(self) -> dict[str, Any]:
        """Return all tracked services with live status."""
        W = 66
        H = "─"
        records = list(self._registry.values())

        if not records:
            block = (
                f"╔{H} SERVICES {H * 53}╗\n"
                f"║  No background services registered.{' ' * 29}║\n"
                f"║  Start one with: run_background command='...'    {' ' * 16}║\n"
                f"╚{H * (W - 2)}╝"
            )
            return {"stdout": block, "services": [], "count": 0, "exitCode": 0}

        parts = [
            f"╔{H} SERVICES ({len(records)} registered) {H * 41}╗",
            f"╚{H * (W - 2)}╝",
        ]
        running = 0
        for rec in sorted(records, key=lambda r: r.started_at, reverse=True):
            alive = rec.is_alive()
            if alive:
                running += 1
                rec.status = "running"
            else:
                rec.status = "stopped"
            status_icon = "✓" if alive else "✗"
            url_str = rec.urls[0] if rec.urls else "—"
            parts.append(f"\n  {status_icon} {rec.name[:40]}")
            parts.append(f"    PID={rec.pid}  │  {url_str}  │  {_human_age(rec.started_at)}")
            parts.append(f"    {rec.command[:60]}")

        parts += [
            f"\n{H * W}",
            f"  {running} running / {len(records)} total",
            "  Tip: service_logs pid=PID  |  stop_service pid=PID",
            f"{H * W}",
        ]
        self._save_registry()

        return {
            "stdout": "\n".join(parts),
            "services": [rec.to_dict() for rec in records],
            "count": len(records),
            "runningCount": running,
            "exitCode": 0,
        }

    # ── Status ────────────────────────────────────────────────────────

    def service_status(self, pid: int) -> dict[str, Any]:
        """Detailed status for a specific PID."""
        rec = self._registry.get(pid)
        W = 66
        H = "─"

        if not rec:
            # Try to infer from OS anyway
            try:
                os.kill(pid, 0)
                alive_str = "✓ PROCESS EXISTS (not tracked by service manager)"
            except ProcessLookupError:
                alive_str = "✗ PROCESS NOT FOUND"
            return {
                "stdout": f"PID {pid}: {alive_str}\nUse list_services to see all tracked services.",
                "found": False,
                "exitCode": 0,
            }

        alive = rec.is_alive()
        rec.status = "running" if alive else "stopped"
        self._save_registry()

        # Check ports
        listening = [p for p in rec.ports if _port_open(p)]

        parts = [
            f"╔{H} SERVICE STATUS {H * 47}╗",
            f"║  {rec.name[:60]:<60}║",
            f"╚{H * (W - 2)}╝",
            f"",
            f"  PID:       {rec.pid}",
            f"  Status:    {'✓ RUNNING' if alive else '✗ STOPPED'}",
            f"  Type:      {rec.service_type}",
            f"  Started:   {_human_age(rec.started_at)}",
            f"  CWD:       {rec.cwd}",
            f"  Ports:     {', '.join(str(p) for p in rec.ports) or 'none detected'}",
            f"  Listening: {', '.join(str(p) for p in listening) or ('—' if not alive else 'checking…')}",
        ]
        if rec.urls:
            parts.append(f"  URL(s):    {', '.join(rec.urls)}")
        parts += [
            f"  Log:       {rec.log_file}",
            f"",
            f"{H * W}",
            f"  Commands:",
            f"  • service_logs  pid={pid}  lines=100",
            f"  • stop_service  pid={pid}",
            f"{H * W}",
        ]

        return {
            "stdout": "\n".join(parts),
            "pid": pid,
            "alive": alive,
            "ports": rec.ports,
            "listeningPorts": listening,
            "urls": rec.urls,
            "exitCode": 0,
        }

    # ── Logs ──────────────────────────────────────────────────────────

    def service_logs(self, pid: int, lines: int = 60) -> dict[str, Any]:
        """Tail the log file of a background service."""
        rec = self._registry.get(pid)
        W = 66
        H = "─"

        if not rec:
            return {
                "stdout": f"No service found with PID {pid}. Use list_services to see all.",
                "exitCode": 1,
            }

        log_path = Path(rec.log_file)
        alive = rec.is_alive()

        parts = [
            f"╔{H} LOGS: {rec.name[:50]} {H * max(0, W - len(rec.name) - 10)}╗",
            f"║  PID: {rec.pid}  │  {'✓ RUNNING' if alive else '✗ STOPPED'}  │  last {lines} lines  {'':>25}║",
            f"╚{H * (W - 2)}╝",
        ]

        if not log_path.exists():
            parts.append("  (No log file found — service may have produced no output)")
        else:
            try:
                all_lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
                tail = all_lines[-lines:] if len(all_lines) > lines else all_lines
                if len(all_lines) > lines:
                    parts.append(f"  … ({len(all_lines) - lines} earlier lines omitted, see: {rec.log_file})")
                parts.append(H * W)
                for line in tail:
                    parts.append(f"  {line}")
            except OSError as e:
                parts.append(f"  Error reading log: {e}")

        parts += [
            f"{H * W}",
            f"  Log file: {rec.log_file}",
        ]
        if alive:
            parts.append(f"  Tip: use stop_service pid={pid} to stop this service")

        return {
            "stdout": "\n".join(parts),
            "pid": pid,
            "logFile": rec.log_file,
            "alive": alive,
            "exitCode": 0,
        }

    # ── Stop ──────────────────────────────────────────────────────────

    async def stop_service(self, pid: int, force: bool = False) -> dict[str, Any]:
        """
        Stop a background service.

        Sends SIGTERM first, waits 5 seconds, then SIGKILL if still running.
        """
        rec = self._registry.get(pid)
        name = rec.name if rec else f"PID {pid}"
        W = 66
        H = "─"

        if not self._pid_exists(pid):
            if rec:
                rec.status = "stopped"
                self._save_registry()
            return {
                "stdout": f"  ℹ️  Service '{name}' (PID {pid}) is already stopped.",
                "exitCode": 0,
                "stopped": True,
            }

        sig = signal.SIGKILL if force else signal.SIGTERM
        try:
            # Kill the entire process group (catches child processes too)
            try:
                pgid = os.getpgid(pid)
                if pgid != os.getpgrp():
                    os.killpg(pgid, sig)
                else:
                    os.kill(pid, sig)
            except (ProcessLookupError, PermissionError):
                os.kill(pid, sig)
        except ProcessLookupError:
            pass

        # Wait up to 5 seconds for graceful shutdown
        for _ in range(10):
            await asyncio.sleep(0.5)
            if not self._pid_exists(pid):
                break
        else:
            # Force kill if still alive
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

        alive = self._pid_exists(pid)
        if rec:
            rec.status = "stopped" if not alive else "running"
            self._save_registry()

        parts = [
            f"╔{H} {'SERVICE STOPPED' if not alive else 'STOP FAILED'} {H * 47}╗",
            f"║  {name[:60]:<60}║",
            f"╚{H * (W - 2)}╝",
            f"",
            f"  PID:    {pid}",
            f"  Status: {'✓ Terminated successfully' if not alive else '✗ Process still running — try stop_service pid=' + str(pid) + ' force=true'}",
        ]
        if rec and rec.urls:
            parts.append(f"  Was serving: {', '.join(rec.urls)}")

        return {
            "stdout": "\n".join(parts),
            "exitCode": 0 if not alive else 1,
            "stopped": not alive,
            "pid": pid,
        }

    def _pid_exists(self, pid: int) -> bool:
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
