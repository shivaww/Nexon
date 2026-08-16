"""
TermuxForge Hybrid Tools Framework
=====================================

A production-grade hybrid framework combining the raw power of Termux shell
commands with structured Python file operations to give AI models the maximum
quality, readable, and actionable output from every tool call.

Philosophy
----------
- Shell commands are the most powerful tool on Termux — never hide them.
- Python file ops give atomic, safe, structured operations with rich metadata.
- Every tool output is AI-optimized: consistent headers, line numbers, exit codes,
  duration, context, and suggestions — so models never need to guess what happened.
- The output format is human-readable AND machine-parseable simultaneously.

Output Format Standard
----------------------
Every tool call returns a "rich block" that looks like:

    ╔══ TOOL: read_file ═══════════════════════════════════════════╗
    ║  lib/main.dart  |  7188 lines  |  266 KB  |  Dart           ║
    ╚══════════════════════════════════════════════════════════════╝
       1 │ import 'dart:async';
       2 │ import 'dart:convert';
       ...
    ──────────────────────────────────────────────────────────────
    [Lines 1–50 of 7188 shown. Use multi_read ranges=51-100 for next block.]

Or for shell:

    ╔══ SHELL ══════════════════════════════════════════════════════╗
    ║  $ ls -la lib/  |  EXIT: 0 ✓  |  12ms  |  ~/projects/nexon ║
    ╚══════════════════════════════════════════════════════════════╝
    total 8
    drwxr-xr-x  9 user user 4096 Jul  4 03:58 .
    ──────────────────────────────────────────────────────────────
    [4 lines output. Command succeeded.]
"""

from __future__ import annotations

import asyncio
import difflib
import hashlib
import json
import logging
import math
import mimetypes
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Optional
from workspace import WorkspaceManager

workspace_mgr = WorkspaceManager()

logger = logging.getLogger("termux_forge.hybrid_tools")

# ── Constants ─────────────────────────────────────────────────────────

SHELL = os.environ.get("SHELL", "/data/data/com.termux/files/usr/bin/bash")
HOME = os.path.expanduser("~")
TERMUX_BIN = "/data/data/com.termux/files/usr/bin"

# Line number column width
LN_WIDTH = 5

# Max lines to show before truncating (can be overridden per call)
DEFAULT_MAX_LINES = 120
MAX_LINES_HARD = 600

# Max raw bytes in any single output to the AI
MAX_OUTPUT_BYTES = 40_000
MAX_TEXT_FILE_READ_BYTES = 2_000_000

# Languages we know about (extension → name)
LANG_MAP: dict[str, str] = {
    ".dart": "Dart", ".py": "Python", ".js": "JavaScript", ".ts": "TypeScript",
    ".jsx": "JSX", ".tsx": "TSX", ".java": "Java", ".kt": "Kotlin",
    ".go": "Go", ".rs": "Rust", ".cpp": "C++", ".c": "C", ".h": "C/C++ Header",
    ".swift": "Swift", ".rb": "Ruby", ".php": "PHP", ".sh": "Shell",
    ".bash": "Bash", ".zsh": "Zsh", ".yaml": "YAML", ".yml": "YAML",
    ".json": "JSON", ".toml": "TOML", ".xml": "XML", ".html": "HTML",
    ".css": "CSS", ".scss": "SCSS", ".md": "Markdown", ".sql": "SQL",
    ".gradle": "Gradle", ".kts": "Kotlin Script", ".lock": "Lockfile",
    ".txt": "Text", ".env": "Environment", ".gitignore": "Git Config",
}

# Skip dirs in tree/search
SKIP_DIRS = frozenset({
    ".git", ".dart_tool", "build", ".pub-cache", "__pycache__",
    "node_modules", ".gradle", ".idea", ".vscode", "coverage",
    ".pub", "android/.gradle",
})

# ── Production-grade safety / IO infrastructure ──────────────────────────
#
# These give the hybrid file tools VSCode-quality guarantees:
#   * a workspace "jail" (paths must stay inside the workspace),
#   * atomic writes (temp file + fsync + os.replace),
#   * pre-write validation (disk space, size cap, binary content, sha256),
#   * short-lived per-file locks (no two concurrent writers),
#   * soft-delete to a `.nexon/trash/` folder with restore support,
#   * an append-only audit log of every successful mutation.

# Default workspace used when a tool call does not pass an explicit
# workspace_dir. Mirrors the app's default agentic workspace.
_DEFAULT_WORKSPACE = os.path.realpath(
    os.environ.get("TERMUX_WORKSPACE", "/data/data/com.termux/files/home")
)

# Module-level workspace override, configurable via set_workspace_dir().
_WORKSPACE_DIR = _DEFAULT_WORKSPACE

# Files larger than this (10 MB) cannot be written in a single call; the
# caller is told to use a streaming strategy instead.
MAX_SAFE_WRITE_BYTES = 10 * 1024 * 1024

# Per-file lock bookkeeping: {realpath: [threading.Lock, expiry_timestamp]}.
# Locks auto-expire after _LOCK_TTL seconds to avoid orphaned locks if a call
# is killed mid-flight.
_file_locks: dict[str, list] = {}
_LOCK_TTL = 30.0
_LOCKS_GUARD = threading.Lock()

# `.nexon/` support directory lives inside the active workspace.
_NEXON_DIR = os.path.join(_WORKSPACE_DIR, ".nexon")
_TRASH_DIR = os.path.join(_NEXON_DIR, "trash")
_AUDIT_LOG = os.path.join(_NEXON_DIR, "file_ops.log")

# Extra directories always excluded from search/walk, regardless of cwd.
EXTRA_SKIP_DIRS = frozenset({
    ".nexon", "build", ".dart_tool", "__pycache__", "node_modules", ".git",
    ".gradle", ".idea", ".vscode", "coverage",
})


def set_workspace_dir(path: str) -> None:
    """Set the active workspace used by the jail and support directories."""
    global _WORKSPACE_DIR, _NEXON_DIR, _TRASH_DIR, _AUDIT_LOG
    _WORKSPACE_DIR = os.path.realpath(os.path.expanduser(path))
    _NEXON_DIR = os.path.join(_WORKSPACE_DIR, ".nexon")
    _TRASH_DIR = os.path.join(_NEXON_DIR, "trash")
    _AUDIT_LOG = os.path.join(_NEXON_DIR, "file_ops.log")


def _workspace() -> str:
    """Return the currently configured workspace root (realpath)."""
    try:
        return os.path.realpath(_WORKSPACE_DIR)
    except OSError:
        return _WORKSPACE_DIR


def _is_safe(path: str, workspace_dir: str = "") -> bool:
    """
    Return True iff [path] resolves inside [workspace_dir] (the jail).

    Handles symlinks and `~` expansion, and treats the jail's own support
    directory as safe for bookkeeping even when computed under the lock. The
    `real` path of the target must be the workspace root itself or live under
    it; symlink targets that escape the jail are rejected.
    """
    if not path:
        return False
    base = workspace_dir or _workspace()
    try:
        work = os.path.realpath(base)
        real = os.path.realpath(os.path.expanduser(path))
    except OSError:
        return False
    if real == work:
        return True
    return real.startswith(work + os.sep)


def _unsafe_error(path: str) -> dict[str, Any]:
    return {
        "stdout": f"ERROR: Path outside workspace jail: {path}",
        "error": "Path outside workspace jail",
        "path": str(path),
        "exitCode": 1,
        "success": False,
    }


def _atomic_write(path: str, content: str, encoding: str = "utf-8") -> int:
    """
    Atomically write [content] to [path] via a temp file + fsync + replace.

    A crash mid-write can only ever leave the temp file behind; the target
    file is replaced in a single atomic syscall, so it is never half-written.
    Returns the number of bytes written.
    """
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(target.parent), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding=encoding) as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, str(target))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return target.stat().st_size


def _pre_write_checks(path: str, content: str) -> dict[str, Any] | None:
    """
    Validate a proposed write. Returns an error dict, or None when safe.

    Enforced:
      * content > 10 MB  -> "File >10MB use streaming"
      * free disk < 2x content + 10 MB -> "Disk full"
      * existing file > 10 MB -> "File >10MB use streaming"
      * NUL byte in content -> "Binary file"
    """
    content_bytes = content.encode("utf-8")
    size = len(content_bytes)

    # Size cap for a single write.
    if size > MAX_SAFE_WRITE_BYTES:
        return {
            "stdout": f"ERROR: File too large ({_human_size(size)}). Use a streaming tool for files >10MB.",
            "error": "File >10MB use streaming",
            "path": path,
            "exitCode": 1,
            "success": False,
        }

    # Existing-file size guard.
    resolved = os.path.realpath(os.path.expanduser(path))
    if os.path.exists(resolved) and os.path.getsize(resolved) > MAX_SAFE_WRITE_BYTES:
        return {
            "stdout": f"ERROR: Target file is {_human_size(os.path.getsize(resolved))} (>10MB). Use a streaming tool.",
            "error": "File >10MB use streaming",
            "path": path,
            "exitCode": 1,
            "success": False,
        }

    # Binary-content guard (NUL byte in the payload).
    if b"\x00" in content_bytes[:8192]:
        return {
            "stdout": "ERROR: Refusing to write binary content.",
            "error": "Binary file",
            "path": path,
            "exitCode": 1,
            "success": False,
        }

    # Disk-space guard (2x content + 10 MB headroom).
    try:
        usage = shutil.disk_usage(resolved or ".")
        if usage.free < size * 2 + 10 * 1024 * 1024:
            return {
                "stdout": f"ERROR: Insufficient disk space (need ~{_human_size(size * 2 + 10 * 1024 * 1024)}, have {_human_size(usage.free)}).",
                "error": "Disk full",
                "path": path,
                "exitCode": 1,
                "success": False,
            }
    except OSError:
        pass

    return None


def _acquire_lock(path: str) -> dict[str, Any] | None:
    """Try to acquire a short-lived exclusive lock for [path]. Returns error dict if held."""
    key = os.path.realpath(os.path.expanduser(path))
    now = time.monotonic()
    with _LOCKS_GUARD:
        entry = _file_locks.get(key)
        if entry is not None and not entry[0].locked():
            _file_locks.pop(key, None)
            entry = None
        if entry is not None:
            if now < entry[1]:
                return {
                    "stdout": f"ERROR: File locked (in use): {path}",
                    "error": "File locked",
                    "path": path,
                    "exitCode": 423,
                    "success": False,
                }
        lock = threading.Lock()
        if not lock.acquire(blocking=False):
            # Race: another thread grabbed it between checks.
            entry = _file_locks.get(key)
            if entry is not None and now < entry[1]:
                return {
                    "stdout": f"ERROR: File locked (in use): {path}",
                    "error": "File locked",
                    "path": path,
                    "exitCode": 423,
                    "success": False,
                }
        _file_locks[key] = [lock, now + _LOCK_TTL]
    return None


def _release_lock(path: str) -> None:
    key = os.path.realpath(os.path.expanduser(path))
    with _LOCKS_GUARD:
        entry = _file_locks.get(key)
        if entry is not None:
            try:
                entry[0].release()
            except RuntimeError:
                pass
            _file_locks.pop(key, None)


def _audit_log(method: str, path: str, size: int, sha: str) -> None:
    """Append a single audit record to .nexon/file_ops.log."""
    try:
        os.makedirs(_NEXON_DIR, exist_ok=True)
        rec = f"[{datetime.now().isoformat(timespec='seconds')}] {method} {path} {size} {sha}"
        with open(_AUDIT_LOG, "a", encoding="utf-8") as f:
            f.write(rec + "\n")
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass


class OutputRenderer:
    """
    Renders tool outputs as structured, AI-readable text blocks.

    Every render method produces a self-contained block with a header
    (tool name + metadata), body (content), and footer (navigation hints).
    The format is consistent across all tools so AI models can parse any
    result with the same mental model.
    """

    # Box drawing chars
    _H = "─"   # horizontal
    _TL = "╔"  # top-left
    _TR = "╗"  # top-right
    _BL = "╚"  # bottom-left
    _BR = "╝"  # bottom-right
    _V = "║"   # vertical

    WIDTH = 66  # total box width

    @classmethod
    def _box_top(cls, title: str, right: str = "") -> str:
        """Render the top border of a box with a title."""
        inner = f" {title} "
        if right:
            inner = f" {title}  {right} "
        pad = cls.WIDTH - len(inner) - 2
        if pad < 2:
            pad = 2
        return f"{cls._TL}{cls._H}{inner}{cls._H * pad}{cls._TR}"

    @classmethod
    def _box_row(cls, content: str) -> str:
        """Render a data row inside a box."""
        pad = cls.WIDTH - len(content) - 3
        if pad < 0:
            content = content[:cls.WIDTH - 5] + "…"
            pad = 1
        return f"{cls._V}  {content}{' ' * pad}{cls._V}"

    @classmethod
    def _box_bottom(cls) -> str:
        return f"{cls._BL}{cls._H * (cls.WIDTH - 2)}{cls._BR}"

    @classmethod
    def _divider(cls) -> str:
        return cls._H * cls.WIDTH

    @classmethod
    def _hint(cls, msg: str) -> str:
        return f"▶ {msg}"

    # ── File header ────────────────────────────────────────────────────

    @classmethod
    def file_header(
        cls,
        path: str,
        total_lines: int,
        size_bytes: int,
        start_line: int,
        end_line: int,
        encoding: str = "utf-8",
    ) -> str:
        """Render the header block for a file read operation."""
        lang = LANG_MAP.get(Path(path).suffix.lower(), "Text")
        rel = _rel_path(path)
        size_str = _human_size(size_bytes)
        lines = [
            cls._box_top(f"FILE: {rel}"),
            cls._box_row(f"{lang}  │  {total_lines:,} lines  │  {size_str}  │  {encoding}"),
            cls._box_row(f"Showing lines {start_line}–{end_line} of {total_lines:,}"),
            cls._box_bottom(),
        ]
        return "\n".join(lines)

    # ── Shell header ───────────────────────────────────────────────────

    @classmethod
    def shell_header(
        cls,
        command: str,
        exit_code: int,
        duration_ms: int,
        cwd: str,
        timed_out: bool = False,
        line_count: int = 0,
    ) -> str:
        """Render the header block for a shell execution result."""
        status = "✓ OK" if exit_code == 0 else f"✗ FAIL({exit_code})"
        if timed_out:
            status = "⏱ TIMEOUT"
        short_cmd = command if len(command) <= 45 else command[:42] + "…"
        rel_cwd = _rel_path(cwd)
        lines = [
            cls._box_top("SHELL"),
            cls._box_row(f"$ {short_cmd}"),
            cls._box_row(f"EXIT: {status}  │  {duration_ms}ms  │  {rel_cwd}"),
        ]
        if line_count:
            lines.append(cls._box_row(f"{line_count} line(s) output"))
        lines.append(cls._box_bottom())
        return "\n".join(lines)

    # ── Write/edit result header ───────────────────────────────────────

    @classmethod
    def write_header(cls, path: str, action: str, lines_before: int, lines_after: int, size_bytes: int) -> str:
        rel = _rel_path(path)
        delta = lines_after - lines_before
        delta_str = f"+{delta}" if delta >= 0 else str(delta)
        lines = [
            cls._box_top(f"{action}: {rel}"),
            cls._box_row(f"Lines: {lines_before} → {lines_after} ({delta_str})  │  {_human_size(size_bytes)}"),
            cls._box_bottom(),
        ]
        return "\n".join(lines)

    # ── Search result header ───────────────────────────────────────────

    @classmethod
    def search_header(cls, query: str, path: str, count: int, backend: str) -> str:
        rel = _rel_path(path)
        lines = [
            cls._box_top(f"SEARCH: {query!r}"),
            cls._box_row(f"In: {rel}  │  {count} match(es)  │  via {backend}"),
            cls._box_bottom(),
        ]
        return "\n".join(lines)

    # ── Generic tool header ────────────────────────────────────────────

    @classmethod
    def tool_header(cls, tool: str, subtitle: str = "") -> str:
        lines = [cls._box_top(f"TOOL: {tool}")]
        if subtitle:
            lines.append(cls._box_row(subtitle))
        lines.append(cls._box_bottom())
        return "\n".join(lines)


# ══════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════

def _rel_path(path: str) -> str:
    """Return a path relative to $HOME, or absolute if outside."""
    try:
        return "~/" + str(Path(path).relative_to(HOME))
    except ValueError:
        return path


def _human_size(n: int) -> str:
    """Format a byte count as a human-readable string."""
    if n < 1024:
        return f"{n} B"
    if n < 1024 ** 2:
        return f"{n / 1024:.1f} KB"
    return f"{n / 1024 ** 2:.1f} MB"


def _age_str(mtime: float) -> str:
    """Format a modification time as a human-readable age."""
    age = time.time() - mtime
    if age < 60:
        return f"{int(age)}s ago"
    if age < 3600:
        return f"{int(age // 60)}m ago"
    if age < 86400:
        return f"{int(age // 3600)}h ago"
    return f"{int(age // 86400)}d ago"


def _read_lines_safe(path: Path, encoding: str = "utf-8") -> list[str]:
    """Read a file line-by-line, falling back to latin-1 on decode errors."""
    try:
        with open(path, encoding=encoding) as f:
            return f.readlines()
    except UnicodeDecodeError:
        with open(path, encoding="latin-1") as f:
            return f.readlines()


def _is_binary_file(path: Path, sample_size: int = 8192) -> bool:
    """Detect binary files by sampling for NUL bytes and decode failures."""
    try:
        sample = path.read_bytes()[:sample_size]
    except OSError:
        return False
    if b"\x00" in sample:
        return True
    try:
        sample.decode("utf-8")
        return False
    except UnicodeDecodeError:
        textish = sum(1 for b in sample if b in b"\n\r\t" or 32 <= b <= 126)
        return bool(sample) and (textish / len(sample)) < 0.85


def _sha256_file(path: Path) -> str:
    """Compute a file SHA-256 hash without loading it into memory."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_line_window_safe(
    path: Path,
    start_line: int,
    end_line: int,
    encoding: str = "utf-8",
) -> tuple[list[str], int, bool]:
    """
    Stream a bounded line window from a large file.

    Returns selected lines, last line number visited, and whether the full file
    line count is unknown because reading stopped at the requested window.
    """
    selected: list[str] = []
    last_seen = 0
    stopped_early = False
    try:
        with open(path, encoding=encoding, errors="replace") as f:
            for line_no, line in enumerate(f, start=1):
                last_seen = line_no
                if line_no < start_line:
                    continue
                if line_no > end_line:
                    stopped_early = True
                    break
                selected.append(line)
    except UnicodeDecodeError:
        with open(path, encoding="latin-1", errors="replace") as f:
            for line_no, line in enumerate(f, start=1):
                last_seen = line_no
                if line_no < start_line:
                    continue
                if line_no > end_line:
                    stopped_early = True
                    break
                selected.append(line)
    return selected, last_seen, stopped_early


def _number_lines(lines: list[str], start: int) -> str:
    """Format lines with gutter line numbers."""
    parts = []
    for i, line in enumerate(lines, start=start):
        # Strip trailing newline for clean display
        stripped = line.rstrip("\n\r")
        parts.append(f"{i:{LN_WIDTH}d} │ {stripped}")
    return "\n".join(parts)


def _truncate_output(text: str, max_bytes: int = MAX_OUTPUT_BYTES) -> tuple[str, bool]:
    """
    Truncate output to max_bytes using head+tail strategy.

    Returns (truncated_text, was_truncated).
    """
    if len(text.encode("utf-8")) <= max_bytes:
        return text, False

    head_bytes = (max_bytes * 55) // 100  # 55% head
    tail_bytes = (max_bytes * 30) // 100  # 30% tail
    # The remaining 15% is the truncation notice

    head = text[:head_bytes].rsplit("\n", 1)[0]
    tail = text[-tail_bytes:].split("\n", 1)[-1]
    removed = len(text) - len(head) - len(tail)

    notice = (
        f"\n\n{'─' * 66}\n"
        f"  ⚠ OUTPUT TRUNCATED: {removed:,} chars removed from middle\n"
        f"  Head: first {len(head):,} chars shown above\n"
        f"  Tail: last {len(tail):,} chars shown below\n"
        f"  Tip: Use multi_read with specific line ranges for precise access\n"
        f"{'─' * 66}\n\n"
    )
    return head + notice + tail, True


def _full_env() -> dict[str, str]:
    """Build a full environment dict with Termux paths prepended."""
    env = dict(os.environ)
    current_path = env.get("PATH", "")
    if TERMUX_BIN not in current_path:
        env["PATH"] = f"{TERMUX_BIN}:{current_path}"
    return env


# ══════════════════════════════════════════════════════════════════════
#  SHELL EXECUTION (Power backend)
# ══════════════════════════════════════════════════════════════════════

@dataclass
class ShellResult:
    """Result of a shell command execution."""
    command: str
    cwd: str
    exit_code: int
    stdout: str
    stderr: str
    duration_ms: int
    timed_out: bool = False
    killed: bool = False

    @property
    def success(self) -> bool:
        return self.exit_code == 0 and not self.timed_out

    def to_ai_block(
        self,
        max_stdout_lines: int = DEFAULT_MAX_LINES,
        show_stderr_inline: bool = True,
    ) -> str:
        """
        Render this result as a rich AI-readable block.

        Includes: header box, stdout (with optional line numbers),
        stderr section (on failure), navigation hints.
        """
        stdout_lines = self.stdout.splitlines()
        stderr_lines = self.stderr.splitlines()
        total_stdout = len(stdout_lines)

        # ── Header ──
        header = OutputRenderer.shell_header(
            command=self.command,
            exit_code=self.exit_code,
            duration_ms=self.duration_ms,
            cwd=self.cwd,
            timed_out=self.timed_out,
            line_count=total_stdout,
        )

        parts = [header]

        # ── Stdout body ──
        if stdout_lines:
            shown = stdout_lines[:max_stdout_lines]
            body = "\n".join(shown)
            body, was_truncated = _truncate_output(body)
            parts.append(body)

            if len(stdout_lines) > max_stdout_lines:
                hidden = len(stdout_lines) - max_stdout_lines
                parts.append(
                    f"\n{OutputRenderer._divider()}\n"
                    f"  ▶ {hidden:,} more lines not shown. "
                    f"Pipe to head/tail or use search_rich to filter.\n"
                )

        # ── Stderr (always show on failure, or if non-empty) ──
        if stderr_lines and show_stderr_inline:
            label = "STDERR (non-zero exit — investigate this):" if not self.success else "STDERR:"
            parts.append(f"\n{OutputRenderer._divider()}\n{label}")
            stderr_body = "\n".join(stderr_lines[:80])
            if len(stderr_lines) > 80:
                stderr_body += f"\n  … ({len(stderr_lines) - 80} more lines)"
            parts.append(stderr_body)

        # ── Timeout notice ──
        if self.timed_out:
            parts.append(
                f"\n{OutputRenderer._divider()}\n"
                f"  ⚠ TIMED OUT after {self.duration_ms}ms\n"
                f"  Retry with: <command>timeout 120 {self.command}</command>\n"
                f"  Or add stream=true to get partial output as it runs.\n"
            )

        # ── Footer divider ──
        parts.append(OutputRenderer._divider())

        return "\n".join(parts)

    def to_dict(self) -> dict[str, Any]:
        """Machine-readable dict for JSON serialization."""
        return {
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "durationMs": self.duration_ms,
            "command": self.command,
            "cwd": self.cwd,
            "timedOut": self.timed_out,
            "killed": self.killed,
            "success": self.success,
            "aiBlock": self.to_ai_block(),
        }


async def shell_exec(
    command: str,
    cwd: str | None = None,
    timeout: int = 30,
    env: dict[str, str] | None = None,
    stream_callback: Callable[[str, str], None] | None = None,
) -> ShellResult:
    """
    Execute a shell command with full output capture.

    Parameters
    ----------
    command : str
        Shell command to execute.
    cwd : str, optional
        Working directory. Defaults to $HOME.
    timeout : int
        Seconds before the process is killed.
    env : dict, optional
        Extra environment variables.
    stream_callback : callable, optional
        Called with (stream_name, line) for real-time output.

    Returns
    -------
    ShellResult
        Rich result object with AI-readable rendering.
    """
    cwd = cwd or HOME
    full_env = _full_env()
    if env:
        full_env.update(env)

    if not os.path.isdir(cwd):
        return ShellResult(
            command=command, cwd=cwd, exit_code=1,
            stdout="", stderr=f"Directory not found: {cwd}",
            duration_ms=0,
        )

    start = time.monotonic()
    timed_out = False

    try:
        if stream_callback:
            # Streaming mode: read line by line
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=cwd,
                env=full_env,
                executable=SHELL,
            )
            stdout_lines: list[str] = []
            stderr_lines: list[str] = []

            async def _read(stream: asyncio.StreamReader | None, name: str, collector: list[str]) -> None:
                if stream is None:
                    return
                while True:
                    line = await stream.readline()
                    if not line:
                        break
                    decoded = line.decode("utf-8", errors="replace")
                    collector.append(decoded)
                    stream_callback(name, decoded)

            try:
                await asyncio.wait_for(
                    asyncio.gather(
                        _read(proc.stdout, "stdout", stdout_lines),
                        _read(proc.stderr, "stderr", stderr_lines),
                        proc.wait(),
                    ),
                    timeout=timeout,
                )
            except asyncio.TimeoutError:
                timed_out = True
                try:
                    proc.terminate()
                    await asyncio.wait_for(proc.wait(), timeout=5)
                except Exception:
                    proc.kill()

            duration_ms = int((time.monotonic() - start) * 1000)
            return ShellResult(
                command=command, cwd=cwd,
                exit_code=proc.returncode if proc.returncode is not None else -1,
                stdout="".join(stdout_lines),
                stderr="".join(stderr_lines),
                duration_ms=duration_ms,
                timed_out=timed_out,
            )

        else:
            # Batch mode: wait for completion
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=cwd,
                env=full_env,
                executable=SHELL,
            )
            try:
                stdout_bytes, stderr_bytes = await asyncio.wait_for(
                    proc.communicate(), timeout=timeout
                )
            except asyncio.TimeoutError:
                timed_out = True
                try:
                    proc.terminate()
                    await asyncio.wait_for(proc.wait(), timeout=5)
                except Exception:
                    proc.kill()
                stdout_bytes = b""
                stderr_bytes = f"Process killed after {timeout}s timeout".encode()

            duration_ms = int((time.monotonic() - start) * 1000)
            return ShellResult(
                command=command, cwd=cwd,
                exit_code=proc.returncode if proc.returncode is not None else -1,
                stdout=stdout_bytes.decode("utf-8", errors="replace"),
                stderr=stderr_bytes.decode("utf-8", errors="replace"),
                duration_ms=duration_ms,
                timed_out=timed_out,
            )

    except Exception as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        return ShellResult(
            command=command, cwd=cwd, exit_code=-1,
            stdout="", stderr=str(exc),
            duration_ms=duration_ms,
        )


# ══════════════════════════════════════════════════════════════════════
#  HYBRID TOOL REGISTRY
# ══════════════════════════════════════════════════════════════════════

class HybridToolRegistry:
    """
    Central registry of all hybrid tools.

    Acts as the integration point between the Python framework and
    the JSON-RPC bridge. Each tool is registered with a name, handler,
    description, and parameter schema for self-documentation.

    The registry also powers the tool_help RPC method so AI models
    can discover exact parameter names and examples without reading
    source code.
    """

    def __init__(self, executor, security) -> None:
        self.executor = executor     # CommandExecutor from bridge
        self.security = security     # SecurityManager from bridge
        self._tools: dict[str, dict[str, Any]] = {}

    def register(self, name: str, handler, description: str, params: dict) -> None:
        """Register a tool with its metadata."""
        self._tools[name] = {
            "handler": handler,
            "description": description,
            "params": params,
        }

    def get_handler(self, name: str):
        return self._tools[name]["handler"] if name in self._tools else None

    def list_tools(self) -> list[dict[str, Any]]:
        """Return all tools with their descriptions for AI discovery."""
        return [
            {
                "name": name,
                "description": info["description"],
                "params": info["params"],
            }
            for name, info in sorted(self._tools.items())
        ]

    def tool_help_block(self) -> str:
        """Render a full tool reference as an AI-readable block."""
        header = OutputRenderer.tool_header(
            "TOOL REFERENCE",
            f"{len(self._tools)} hybrid tools available",
        )
        parts = [header, OutputRenderer._divider()]
        for name, info in sorted(self._tools.items()):
            parts.append(f"\n  ┌─ {name}")
            parts.append(f"  │  {info['description']}")
            for p_name, p_desc in info["params"].items():
                parts.append(f"  │  • {p_name}: {p_desc}")
            parts.append(f"  └─")
        parts.append(f"\n{OutputRenderer._divider()}")
        return "\n".join(parts)


def build_registry(executor, security) -> HybridToolRegistry:
    """Build and populate the HybridToolRegistry with all tools."""
    reg = HybridToolRegistry(executor, security)

    reg.register(
        "tool_help",
        lambda **kw: {"stdout": reg.tool_help_block(), "exitCode": 0, "success": True},
        "List all hybrid tools with descriptions and parameter schemas",
        {},
    )


    return reg
