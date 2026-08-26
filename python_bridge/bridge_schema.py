"""
TermuxForge — Cross-Bridge Schema Constants (Python side)
==========================================================

Single source of truth for tool names, method names, and JSON protocol
shapes shared between the Flutter app, the Python bridge, and the C++
native tools bridge.

This module mirrors `lib/services/termux_bridge/bridge_schema.dart` on the
Flutter side. When adding or renaming a tool, update both files.
"""

from __future__ import annotations

from typing import Final


# ── C++ native tools bridge ───────────────────────────────────────────

CPP_BRIDGE_TOOLS: Final[frozenset[str]] = frozenset({
    "sh", "search", "read", "patch", "edit", "git", "list", "find",
    "outline", "recent", "undo", "create_file", "create_directory", "mkdir",
    "cut", "extract", "fileops", "diagnostics", "version", "py",
})

CPP_BRIDGE_LONG_NAMES: Final[dict[str, str]] = {
    "sh": "shell_command_tool",
    "search": "multi_search_tool",
    "read": "multi_read_tool",
    "patch": "multi_patch_tool",
    "edit": "file_edit_tool",
    "git": "git_tool",
    "list": "list_tool",
    "find": "find_tool",
    "outline": "outline_tool",
    "recent": "recent_tool",
    "undo": "undo_tool",
    "create_file": "create_file_tool",
    "create_directory": "create_directory_tool",
    "cut": "cut_tool",
    "extract": "extract_tool",
    "fileops": "fileops_tool",
    "diagnostics": "diagnostics_tool",
    "version": "version",
    "py": "py_tool",
}


# ── Python bridge RPC methods ─────────────────────────────────────────

COMMAND_METHODS: Final[frozenset[str]] = frozenset({
    "execute_command", "execute_shell", "run_command", "kill_command",
})

GIT_METHODS: Final[frozenset[str]] = frozenset({
    "git_status", "git_diff", "git_commit", "git_push", "git_pull",
})

FLUTTER_METHODS: Final[frozenset[str]] = frozenset({
    "flutter_run", "flutter_test", "flutter_build",
})

DART_METHODS: Final[frozenset[str]] = frozenset({
    "dart_analyze", "dart_diagnostics", "dart_format",
})

WORKSPACE_METHODS: Final[frozenset[str]] = frozenset({
    "workspace_validate", "workspace_list", "workspace_search",
    "workspace_ingest", "workspace_read_page", "workspace_get_outline",
    "workspace_check_deps", "workspace_cross_compare",
})

MCP_METHODS: Final[frozenset[str]] = frozenset({
    "mcp_server_manage", "mcp_tool_discover", "mcp_transport_handle",
    "mcp_request", "mcp_call",
})

DEEP_RESEARCH_METHODS: Final[frozenset[str]] = frozenset({
    "deep_research.export_temp", "deep_research.export_for_writer",
    "deep_research.reset", "deep_research.update_phase",
    "deep_research.save_checkpoint", "deep_research.load_checkpoint",
    "deep_research.clear_checkpoint", "web_search", "read_url",
})

SERVICE_METHODS: Final[frozenset[str]] = frozenset({
    "run_background", "list_services", "service_status",
    "service_logs", "stop_service", "wait_for_background",
    "background_time_limit",
})

ENV_METHODS: Final[frozenset[str]] = frozenset({
    "env_status", "system_ram_headroom", "project_health",
    "ping", "version_check", "tool_stats", "tool_help",
    "install_package", "check_tool", "discover_tools",
    "get_command_history",
})

CHECKPOINT_METHODS: Final[frozenset[str]] = frozenset({
    "checkpoint_create", "checkpoint_rollback",
})

GITHUB_METHODS: Final[frozenset[str]] = frozenset({
    "github_workflow_trigger", "github_build_status",
    "github_download_artifact",
})

MEDIA_METHODS: Final[frozenset[str]] = frozenset({
    "media_discover",
})

WORKFLOW_METHODS: Final[frozenset[str]] = frozenset({
    "workflow_execute",
})

ALL_PYTHON_METHODS: Final[frozenset[str]] = (
    COMMAND_METHODS
    | GIT_METHODS
    | FLUTTER_METHODS
    | DART_METHODS
    | WORKSPACE_METHODS
    | MCP_METHODS
    | DEEP_RESEARCH_METHODS
    | SERVICE_METHODS
    | ENV_METHODS
    | CHECKPOINT_METHODS
    | GITHUB_METHODS
    | MEDIA_METHODS
    | WORKFLOW_METHODS
)


# ── C++ bridge JSON protocol keys ─────────────────────────────────────

CPP_TOOL_KEY: Final[str] = "t"
CPP_ARGS_KEY: Final[str] = "a"
CPP_ERROR_KEY: Final[str] = "err"
CPP_OUTPUT_KEY: Final[str] = "out"
CPP_RC_KEY: Final[str] = "rc"
CPP_RESULT_KEY: Final[str] = "r"
CPP_FILE_KEY: Final[str] = "f"
CPP_STATUS_KEY: Final[str] = "st"


# ── Transport endpoints ───────────────────────────────────────────────

DEFAULT_HOST: Final[str] = "127.0.0.1"
WEBSOCKET_PORT: Final[int] = 8765
HTTP_PORT: Final[int] = 8390
HTTP_PATH: Final[str] = "/mcp"
