"""
TermuxForge Tool Discovery
============================

Discovers installed developer tools in the Termux environment,
checks their versions, remembers availability, and suggests
installation commands for missing tools.
"""

import asyncio
import json
import logging
import os
import shutil
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger("termux_forge.tool_discovery")


@dataclass
class ToolInfo:
    """
    Information about a discovered tool.

    Attributes
    ----------
    name : str
        Human-readable tool name.
    command : str
        Executable command name.
    available : bool
        Whether the tool is installed and accessible.
    version : str
        Detected version string, or empty if unavailable.
    path : str
        Absolute path to the executable, or empty.
    install_hint : str
        Suggested command to install the tool.
    category : str
        Tool category (e.g., "language", "vcs", "build").
    """

    name: str
    command: str
    available: bool = False
    version: str = ""
    path: str = ""
    install_hint: str = ""
    category: str = "general"

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "command": self.command,
            "available": self.available,
            "version": self.version,
            "path": self.path,
            "installHint": self.install_hint,
            "category": self.category,
        }


# ── Tool definitions ─────────────────────────────────────────────────
# (name, command, version_flag, install_hint, category)
TOOL_DEFINITIONS: list[tuple[str, str, str, str, str]] = [
    # Languages & runtimes
    ("Flutter", "flutter", "--version", "See https://flutter.dev/docs/get-started/install", "framework"),
    ("Dart", "dart", "--version", "Included with Flutter SDK", "language"),
    ("Python 3", "python3", "--version", "pkg install python", "language"),
    ("Node.js", "node", "--version", "pkg install nodejs", "language"),
    ("Ruby", "ruby", "--version", "pkg install ruby", "language"),
    ("Go", "go", "version", "pkg install golang", "language"),
    ("Rust (rustc)", "rustc", "--version", "pkg install rust", "language"),
    ("Java", "java", "-version", "pkg install openjdk-17", "language"),
    ("Kotlin", "kotlin", "-version", "pkg install kotlin", "language"),

    # Package managers
    ("pip", "pip", "--version", "pkg install python-pip", "package_manager"),
    ("npm", "npm", "--version", "pkg install nodejs", "package_manager"),
    ("yarn", "yarn", "--version", "npm install -g yarn", "package_manager"),
    ("pnpm", "pnpm", "--version", "npm install -g pnpm", "package_manager"),
    ("cargo", "cargo", "--version", "pkg install rust", "package_manager"),
    ("gem", "gem", "--version", "pkg install ruby", "package_manager"),

    # Version control
    ("Git", "git", "--version", "pkg install git", "vcs"),
    ("GitHub CLI", "gh", "--version", "pkg install gh", "vcs"),

    # Build & CI
    ("Make", "make", "--version", "pkg install make", "build"),
    ("CMake", "cmake", "--version", "pkg install cmake", "build"),
    ("Gradle", "gradle", "--version", "pkg install gradle", "build"),

    # Cloud & services
    ("Firebase CLI", "firebase", "--version", "npm install -g firebase-tools", "cloud"),
    ("Supabase CLI", "supabase", "--version", "npm install -g supabase", "cloud"),
    ("Vercel CLI", "vercel", "--version", "npm install -g vercel", "cloud"),

    # Utilities
    ("curl", "curl", "--version", "pkg install curl", "utility"),
    ("wget", "wget", "--version", "pkg install wget", "utility"),
    ("jq", "jq", "--version", "pkg install jq", "utility"),
    ("ripgrep", "rg", "--version", "pkg install ripgrep", "utility"),
    ("fd", "fd", "--version", "pkg install fd", "utility"),
    ("fzf", "fzf", "--version", "pkg install fzf", "utility"),
    ("tmux", "tmux", "-V", "pkg install tmux", "utility"),
    ("htop", "htop", "--version", "pkg install htop", "utility"),
    ("Docker", "docker", "--version", "Not natively supported in Termux", "container"),
    ("ADB", "adb", "--version", "pkg install android-tools", "android"),
]


class ToolDiscovery:
    """
    Discovers and caches information about installed developer tools.

    The cache is refreshed on demand via :meth:`scan_all`. Individual
    tools can be checked with :meth:`check_tool`.
    """

    def __init__(self) -> None:
        self._cache: dict[str, ToolInfo] = {}
        self._scanned = False

    # ── Public API ────────────────────────────────────────────────────

    async def scan_all(self) -> dict[str, ToolInfo]:
        """
        Scan all known tools and cache the results.

        Returns
        -------
        dict[str, ToolInfo]
            Map of command names to their ToolInfo.
        """
        logger.info("Starting full tool discovery scan…")
        tasks = [
            self._check_tool(name, cmd, ver_flag, hint, cat)
            for name, cmd, ver_flag, hint, cat in TOOL_DEFINITIONS
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        for result in results:
            if isinstance(result, ToolInfo):
                self._cache[result.command] = result
            elif isinstance(result, Exception):
                logger.error("Tool scan error: %s", result)

        self._scanned = True
        available = sum(1 for t in self._cache.values() if t.available)
        logger.info(
            "Tool scan complete: %d/%d available",
            available, len(self._cache),
        )
        return dict(self._cache)

    async def check_tool(self, command: str) -> ToolInfo:
        """
        Check a single tool by command name.

        If the tool is in the known definitions, use its metadata.
        Otherwise, probe for it generically.
        """
        for name, cmd, ver_flag, hint, cat in TOOL_DEFINITIONS:
            if cmd == command:
                info = await self._check_tool(name, cmd, ver_flag, hint, cat)
                self._cache[cmd] = info
                return info

        # Unknown tool – generic probe
        info = await self._check_tool(command, command, "--version", "", "unknown")
        self._cache[command] = info
        return info

    def get_cached(self) -> dict[str, ToolInfo]:
        """Return the cached tool information."""
        return dict(self._cache)

    def get_available(self) -> list[ToolInfo]:
        """Return only available (installed) tools."""
        return [t for t in self._cache.values() if t.available]

    def get_missing(self) -> list[ToolInfo]:
        """Return tools that are not installed."""
        return [t for t in self._cache.values() if not t.available]

    def get_by_category(self, category: str) -> list[ToolInfo]:
        """Return tools in a given category."""
        return [t for t in self._cache.values() if t.category == category]

    def to_json(self) -> str:
        """Serialize all cached tools to JSON."""
        return json.dumps(
            {cmd: info.to_dict() for cmd, info in self._cache.items()},
            indent=2,
        )

    def detect_package_managers(self) -> list[dict[str, str]]:
        """
        Detect which package managers are available.

        Returns
        -------
        list[dict]
            List of dicts with ``name``, ``command``, and ``type`` keys.
        """
        managers = []
        pm_checks = [
            ("pkg", "pkg", "system"),
            ("apt", "apt", "system"),
            ("pip", "pip", "python"),
            ("pip3", "pip3", "python"),
            ("npm", "npm", "node"),
            ("yarn", "yarn", "node"),
            ("pnpm", "pnpm", "node"),
            ("cargo", "cargo", "rust"),
            ("gem", "gem", "ruby"),
            ("go", "go", "go"),
        ]
        for name, cmd, pm_type in pm_checks:
            if shutil.which(cmd):
                managers.append({"name": name, "command": cmd, "type": pm_type})
        return managers

    # ── Private helpers ───────────────────────────────────────────────

    async def _check_tool(
        self, name: str, command: str, version_flag: str,
        install_hint: str, category: str,
    ) -> ToolInfo:
        """Probe a single tool for availability and version."""
        path = shutil.which(command) or ""
        if not path:
            return ToolInfo(
                name=name, command=command, available=False,
                install_hint=install_hint, category=category,
            )

        version = await self._get_version(command, version_flag)
        return ToolInfo(
            name=name, command=command, available=True,
            version=version, path=path,
            install_hint=install_hint, category=category,
        )

    @staticmethod
    async def _get_version(command: str, flag: str) -> str:
        """
        Run ``command flag`` and extract the first non-empty line.
        """
        try:
            proc = await asyncio.create_subprocess_exec(
                command, flag,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=10,
            )
            output = (stdout or stderr or b"").decode("utf-8", errors="replace")
            for line in output.strip().splitlines():
                line = line.strip()
                if line:
                    return line
        except Exception as exc:
            logger.debug("Version check failed for %s: %s", command, exc)
        return ""
