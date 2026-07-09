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
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional

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


# ══════════════════════════════════════════════════════════════════════
#  OUTPUT RENDERER
# ══════════════════════════════════════════════════════════════════════

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
                exit_code=proc.returncode or -1,
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
#  FILE OPERATIONS (Python backend — atomic, safe, rich)
# ══════════════════════════════════════════════════════════════════════

@dataclass
class FileReadResult:
    """Result of a structured file read operation."""
    path: str
    content_block: str       # AI-rendered block with headers and line numbers
    total_lines: int
    shown_lines: int
    start_line: int
    end_line: int
    size_bytes: int
    encoding: str
    language: str
    was_truncated: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "stdout": self.content_block,   # stdout key so Dart _formatBridgeOutput picks it up
            "totalLines": self.total_lines,
            "shownLines": self.shown_lines,
            "startLine": self.start_line,
            "endLine": self.end_line,
            "sizeBytes": self.size_bytes,
            "encoding": self.encoding,
            "language": self.language,
            "wasTruncated": self.was_truncated,
            "exitCode": 0,
            "success": True,
        }


def read_file_rich(
    path: str,
    start_line: int = 1,
    end_line: int | None = None,
    max_lines: int = DEFAULT_MAX_LINES,
    encoding: str = "utf-8",
    show_line_numbers: bool = True,
) -> FileReadResult:
    """
    Read a file and return a structured, AI-optimized result.

    Features:
    - Numbered lines in a gutter column
    - File metadata header (language, size, total lines, age)
    - Navigation hints so the AI knows how to read the next chunk
    - Smart truncation with head+tail if the range is huge
    - Encoding fallback to latin-1

    Parameters
    ----------
    path : str
        Absolute or ~ path to the file.
    start_line : int
        First line to show (1-indexed, inclusive).
    end_line : int, optional
        Last line to show (1-indexed, inclusive). Defaults to start + max_lines.
    max_lines : int
        Maximum lines to return in one call.
    encoding : str
        File encoding.
    show_line_numbers : bool
        Whether to prefix lines with numbers.
    """
    p = Path(path).expanduser()

    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")
    if not p.is_file():
        raise IsADirectoryError(f"Path is a directory (use tree): {path}")

    stat_result = p.stat()
    size_bytes = stat_result.st_size
    mtime = stat_result.st_mtime
    lang = LANG_MAP.get(p.suffix.lower(), "Text")

    if _is_binary_file(p):
        mime = mimetypes.guess_type(str(p))[0] or "application/octet-stream"
        block = "\n".join([
            OutputRenderer.tool_header(
                f"BINARY FILE: {_rel_path(str(p))}",
                f"{mime}  │  {_human_size(size_bytes)}  │  sha256={_sha256_file(p)[:12]}...",
            ),
            OutputRenderer._divider(),
            "  Binary content was not read into the chat context.",
            "  Use stat_path for metadata, copy_path/move_path for file operations,",
            "  or a media-specific tool for preview/inspection.",
            OutputRenderer._divider(),
        ])
        return FileReadResult(
            path=str(p),
            content_block=block,
            total_lines=0,
            shown_lines=0,
            start_line=0,
            end_line=0,
            size_bytes=size_bytes,
            encoding="binary",
            language="Binary",
            was_truncated=True,
        )

    # Clamp range
    start_line = max(1, start_line)
    if end_line is None:
        end_line = start_line + max_lines - 1
    if end_line - start_line + 1 > MAX_LINES_HARD:
        end_line = start_line + MAX_LINES_HARD - 1

    large_window = size_bytes > MAX_TEXT_FILE_READ_BYTES
    if large_window:
        selected, last_seen, stopped_early = _read_line_window_safe(
            p, start_line, end_line, encoding,
        )
        total_lines = last_seen
        if stopped_early:
            total_lines = max(total_lines, end_line)
    else:
        all_lines = _read_lines_safe(p, encoding)
        total_lines = len(all_lines)
        end_line = min(end_line, total_lines)
        selected = all_lines[start_line - 1 : end_line]
        stopped_early = False

    shown = len(selected)

    # Build content body
    if show_line_numbers:
        body = _number_lines(selected, start_line)
    else:
        body = "".join(selected)

    body, was_truncated = _truncate_output(body)

    # ── Navigation hints ──
    hints = []
    if start_line > 1:
        prev_start = max(1, start_line - max_lines)
        hints.append(
            f"Previous: multi_read_rich reads=[{{\"path\":\"{path}\",\"start_line\":{prev_start},\"end_line\":{start_line - 1}}}]"
        )
    if end_line < total_lines:
        next_end = min(total_lines, end_line + max_lines)
        hints.append(
            f"Next: multi_read_rich reads=[{{\"path\":\"{path}\",\"start_line\":{end_line + 1},\"end_line\":{next_end}}}]"
        )
    if total_lines > max_lines:
        hints.append(f"Jump: read_file_rich path={path} start_line=N")
    if large_window:
        hints.append(
            "Large file mode: streamed only the requested window; total line count may be partial."
        )

    # ── Assemble block ──
    header = OutputRenderer.file_header(
        path=str(p),
        total_lines=total_lines,
        size_bytes=size_bytes,
        start_line=start_line,
        end_line=end_line,
        encoding=encoding,
    )

    age_line = f"  Modified: {_age_str(mtime)}"

    parts = [header, age_line, OutputRenderer._divider(), body, OutputRenderer._divider()]

    if hints:
        parts.append("  " + "\n  ".join(hints))

    if was_truncated or large_window:
        parts.append("  ⚠ Content was truncated within this range. Use narrower ranges.")

    block = "\n".join(parts)

    return FileReadResult(
        path=str(p),
        content_block=block,
        total_lines=total_lines,
        shown_lines=shown,
        start_line=start_line,
        end_line=end_line,
        size_bytes=size_bytes,
        encoding=encoding,
        language=lang,
        was_truncated=was_truncated or large_window,
    )


# ── Multi-file / multi-range batch read ───────────────────────────────

@dataclass
class MultiReadResult:
    """Result of a batch multi-file/multi-range read."""
    reads: list[FileReadResult]
    total_files: int
    total_lines_shown: int
    block: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "stdout": self.block,
            "reads": [r.to_dict() for r in self.reads],
            "totalFiles": self.total_files,
            "totalLinesShown": self.total_lines_shown,
            "exitCode": 0,
            "success": True,
        }


def multi_read_rich(
    reads: list[dict[str, Any]],
    max_lines_per_file: int = DEFAULT_MAX_LINES,
) -> MultiReadResult:
    """
    Batch-read multiple files or multiple ranges from one file.

    Parameters
    ----------
    reads : list of dicts
        Each dict has:
            path: str           — file path
            start_line: int     — (optional, default 1)
            end_line: int       — (optional, default start + max_lines)
            label: str          — (optional) display label

    Returns
    -------
    MultiReadResult
        All reads combined into one AI block separated by clear dividers.
    """
    results: list[FileReadResult] = []
    blocks: list[str] = []
    total_lines = 0

    for i, spec in enumerate(reads):
        path = spec.get("path", "")
        start = int(spec.get("start_line", spec.get("start", 1)))
        end_val = spec.get("end_line", spec.get("end"))
        end = int(end_val) if end_val is not None else None
        label = spec.get("label", "")

        if label:
            blocks.append(f"\n{'═' * 66}\n  [{i + 1}/{len(reads)}] {label}\n{'═' * 66}")

        try:
            result = read_file_rich(path, start, end, max_lines_per_file)
            results.append(result)
            blocks.append(result.content_block)
            total_lines += result.shown_lines
        except (FileNotFoundError, IsADirectoryError, PermissionError) as exc:
            blocks.append(
                f"{'═' * 66}\n"
                f"  ✗ Cannot read {_rel_path(path)}: {exc}\n"
                f"{'═' * 66}"
            )

    return MultiReadResult(
        reads=results,
        total_files=len(reads),
        total_lines_shown=total_lines,
        block="\n".join(blocks),
    )


# ── Atomic file write ─────────────────────────────────────────────────

@dataclass
class WriteResult:
    """Result of a file write operation."""
    path: str
    action: str
    lines_before: int
    lines_after: int
    size_bytes: int
    backup_path: str
    block: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "stdout": self.block,
            "path": self.path,
            "action": self.action,
            "linesBefore": self.lines_before,
            "linesAfter": self.lines_after,
            "sizeBytes": self.size_bytes,
            "backupPath": self.backup_path,
            "exitCode": 0,
            "success": True,
        }


def write_file_rich(
    path: str,
    content: str,
    encoding: str = "utf-8",
    create_dirs: bool = True,
    backup: bool = True,
) -> WriteResult:
    """
    Atomically write a file with an optional backup.

    Uses a temp-file rename strategy so the write is atomic (no partial files).
    Creates parent directories by default.

    Parameters
    ----------
    path : str
        Target file path.
    content : str
        Full file content to write.
    encoding : str
        File encoding.
    create_dirs : bool
        Create parent directories if they don't exist.
    backup : bool
        If the file exists, save a .bak copy before overwriting.
    """
    p = Path(path).expanduser()
    lines_before = 0
    backup_path = ""

    if p.exists() and p.is_file():
        old_lines = _read_lines_safe(p)
        lines_before = len(old_lines)
        if backup:
            backup_path = str(p) + ".bak"
            shutil.copy2(str(p), backup_path)

    if create_dirs:
        p.parent.mkdir(parents=True, exist_ok=True)

    # Atomic write via temp file
    import tempfile
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(p.parent), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding=encoding) as f:
            f.write(content)
        os.replace(tmp_path, str(p))
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise

    size_bytes = p.stat().st_size
    lines_after = content.count("\n") + (1 if content and not content.endswith("\n") else 0)

    header = OutputRenderer.write_header(
        path=str(p),
        action="WRITTEN",
        lines_before=lines_before,
        lines_after=lines_after,
        size_bytes=size_bytes,
    )
    parts = [header]
    if backup_path:
        parts.append(f"  Backup: {_rel_path(backup_path)}")
    parts.append(f"  ✓ Write successful. Verify with: dart_diagnostics or read_file_rich path={path}")
    block = "\n".join(parts)

    return WriteResult(
        path=str(p), action="WRITTEN",
        lines_before=lines_before, lines_after=lines_after,
        size_bytes=size_bytes, backup_path=backup_path, block=block,
    )


# ── Patch file (multi search-replace) ────────────────────────────────

@dataclass
class PatchSpec:
    """A single search-and-replace patch."""
    search: str        # Exact text to find
    replace: str       # Replacement text
    count: int = 1     # Max occurrences to replace (0 = all)
    label: str = ""    # Human label for this patch


@dataclass
class PatchResult:
    """Result of applying patches to a file."""
    path: str
    patches_applied: int
    patches_failed: list[str]
    lines_before: int
    lines_after: int
    size_bytes: int
    diff: str
    block: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "stdout": self.block,
            "path": self.path,
            "patchesApplied": self.patches_applied,
            "patchesFailed": self.patches_failed,
            "linesBefore": self.lines_before,
            "linesAfter": self.lines_after,
            "sizeBytes": self.size_bytes,
            "diff": self.diff,
            "exitCode": 0 if not self.patches_failed else 1,
            "success": len(self.patches_failed) == 0,
        }


def patch_file_rich(
    path: str,
    patches: list[dict[str, Any]],
    encoding: str = "utf-8",
    backup: bool = True,
) -> PatchResult:
    """
    Apply multiple search-and-replace patches to a file atomically.

    All patches are applied in order to the in-memory content, then the
    result is written atomically. If any patch's search text is not found,
    it's reported in patches_failed but others still apply.

    The result includes a unified diff so the AI can verify exactly what changed.

    Parameters
    ----------
    path : str
        Target file path.
    patches : list of dicts
        Each dict: {search: str, replace: str, count: int (opt), label: str (opt)}
    encoding : str
        File encoding.
    backup : bool
        Save a .bak backup before modifying.
    """
    p = Path(path).expanduser()
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")

    original = p.read_text(encoding=encoding)
    lines_before = original.count("\n") + 1

    if backup:
        backup_path = str(p) + ".bak"
        shutil.copy2(str(p), backup_path)

    content = original
    applied = 0
    failed: list[str] = []

    for i, spec in enumerate(patches):
        search_text = spec.get("search", "")
        replace_text = spec.get("replace", "")
        count = int(spec.get("count", 1))
        label = spec.get("label", f"patch #{i + 1}")

        if not search_text:
            failed.append(f"{label}: empty search string")
            continue

        if search_text not in content:
            failed.append(f"{label}: search text not found — '{search_text[:60]}…'" if len(search_text) > 60 else f"{label}: search text not found — '{search_text}'")
            continue

        if count == 0:
            content = content.replace(search_text, replace_text)
        else:
            content = content.replace(search_text, replace_text, count)
        applied += 1

    # Compute diff before writing
    diff_lines = list(difflib.unified_diff(
        original.splitlines(keepends=True),
        content.splitlines(keepends=True),
        fromfile=f"a/{_rel_path(str(p))}",
        tofile=f"b/{_rel_path(str(p))}",
        n=3,
    ))
    diff_text = "".join(diff_lines[:200])  # cap diff at 200 lines

    # Atomic write
    write_file_rich(path, content, encoding, backup=False)

    size_bytes = p.stat().st_size
    lines_after = content.count("\n") + 1

    # ── Build AI block ──
    header = OutputRenderer.write_header(
        path=str(p), action="PATCHED",
        lines_before=lines_before, lines_after=lines_after, size_bytes=size_bytes,
    )
    parts = [header]
    parts.append(f"  ✓ {applied} patch(es) applied  │  {len(failed)} failed")

    if failed:
        parts.append(f"\n  ✗ FAILED PATCHES:")
        for f_msg in failed:
            parts.append(f"    • {f_msg}")

    if diff_text:
        parts.append(f"\n{OutputRenderer._divider()}\nDIFF:")
        parts.append(diff_text)

    parts.append(f"\n{OutputRenderer._divider()}")
    parts.append(f"  Next: verify with dart_diagnostics or read_file_rich path={path}")

    block = "\n".join(parts)

    return PatchResult(
        path=str(p),
        patches_applied=applied,
        patches_failed=failed,
        lines_before=lines_before,
        lines_after=lines_after,
        size_bytes=size_bytes,
        diff=diff_text,
        block=block,
    )


# ── Line-range operations ─────────────────────────────────────────────

def replace_lines_rich(
    path: str,
    start_line: int,
    end_line: int,
    new_content: str,
    encoding: str = "utf-8",
    backup: bool = True,
) -> PatchResult:
    """
    Replace a specific line range with new content.

    Preserves all lines outside the range. Returns a diff.
    """
    p = Path(path).expanduser()
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")

    original = p.read_text(encoding=encoding)
    lines = original.splitlines(keepends=True)

    start_idx = max(0, start_line - 1)
    end_idx = min(len(lines), end_line)

    # New content lines (ensure trailing newline)
    new_lines = new_content.splitlines(keepends=True)
    if new_lines and not new_lines[-1].endswith("\n"):
        new_lines[-1] += "\n"

    result_lines = lines[:start_idx] + new_lines + lines[end_idx:]
    new_content_full = "".join(result_lines)

    patch = PatchSpec(
        search="".join(lines[start_idx:end_idx]),
        replace=new_content,
        label=f"lines {start_line}–{end_line}",
    )
    return patch_file_rich(
        path=path,
        patches=[{"search": patch.search, "replace": patch.replace, "label": patch.label}],
        encoding=encoding,
        backup=backup,
    )


def insert_lines_rich(
    path: str,
    after_line: int,
    content: str,
    encoding: str = "utf-8",
) -> WriteResult:
    """
    Insert lines after a specific line number.

    after_line=0 inserts at the beginning of the file.
    """
    p = Path(path).expanduser()
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")

    lines = _read_lines_safe(p, encoding)
    new_lines = content.splitlines(keepends=True)
    if new_lines and not new_lines[-1].endswith("\n"):
        new_lines[-1] += "\n"

    insert_idx = max(0, min(after_line, len(lines)))
    result = lines[:insert_idx] + new_lines + lines[insert_idx:]
    return write_file_rich(path, "".join(result), encoding, backup=True)


def delete_lines_rich(
    path: str,
    start_line: int,
    end_line: int,
    encoding: str = "utf-8",
) -> WriteResult:
    """Delete a range of lines from a file."""
    p = Path(path).expanduser()
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")

    lines = _read_lines_safe(p, encoding)
    start_idx = max(0, start_line - 1)
    end_idx = min(len(lines), end_line)
    result = lines[:start_idx] + lines[end_idx:]
    return write_file_rich(path, "".join(result), encoding, backup=True)


# ── File outline (structure extraction) ───────────────────────────────

@dataclass
class FileOutlineResult:
    """Result of a file structure analysis."""
    path: str
    language: str
    symbols: list[dict[str, Any]]
    block: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "stdout": self.block,
            "path": self.path,
            "language": self.language,
            "symbols": self.symbols,
            "exitCode": 0,
            "success": True,
        }


# Language-specific outline patterns
_OUTLINE_PATTERNS: dict[str, list[tuple[str, re.Pattern]]] = {
    ".dart": [
        ("class",      re.compile(r"^(?:abstract\s+)?(?:base\s+)?(?:final\s+)?(?:interface\s+)?class\s+(\w+)")),
        ("mixin",      re.compile(r"^mixin\s+(\w+)")),
        ("extension",  re.compile(r"^extension\s+(\w+)")),
        ("enum",       re.compile(r"^enum\s+(\w+)")),
        ("function",   re.compile(r"^\s{0,2}(?:Future|void|String|int|bool|double|List|Map|Set|Widget|State|[\w<>\[\]?]+)\s+(\w+)\s*\(")),
    ],
    ".py": [
        ("class",    re.compile(r"^class\s+(\w+)")),
        ("function", re.compile(r"^def\s+(\w+)")),
        ("method",   re.compile(r"^\s{4}def\s+(\w+)")),
        ("async",    re.compile(r"^async\s+def\s+(\w+)")),
    ],
    ".js": [
        ("class",    re.compile(r"^(?:export\s+)?(?:default\s+)?class\s+(\w+)")),
        ("function", re.compile(r"^(?:export\s+)?(?:async\s+)?function\s+(\w+)")),
        ("arrow",    re.compile(r"^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=")),
    ],
    ".ts": [
        ("interface", re.compile(r"^(?:export\s+)?interface\s+(\w+)")),
        ("type",      re.compile(r"^(?:export\s+)?type\s+(\w+)")),
        ("class",     re.compile(r"^(?:export\s+)?(?:abstract\s+)?class\s+(\w+)")),
        ("function",  re.compile(r"^(?:export\s+)?(?:async\s+)?function\s+(\w+)")),
    ],
}


def file_outline_rich(path: str, encoding: str = "utf-8") -> FileOutlineResult:
    """
    Extract the structural outline of a source file.

    Returns classes, functions, methods with their line numbers.
    Works for Dart, Python, JS, TS. Falls back to grep-style for others.

    Useful for:
    - Understanding a file's structure before reading specific sections
    - Finding where a class or function is defined
    - Generating a table of contents
    """
    p = Path(path).expanduser()
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")

    lang = LANG_MAP.get(p.suffix.lower(), "Text")
    patterns = _OUTLINE_PATTERNS.get(p.suffix.lower(), [])

    lines = _read_lines_safe(p, encoding)
    total = len(lines)
    symbols: list[dict[str, Any]] = []

    for ln, line in enumerate(lines, start=1):
        for kind, pattern in patterns:
            m = pattern.match(line)
            if m:
                symbols.append({
                    "kind": kind,
                    "name": m.group(1),
                    "line": ln,
                    "snippet": line.rstrip()[:80],
                })
                break

    # ── Build block ──
    header = OutputRenderer.tool_header(
        f"OUTLINE: {_rel_path(str(p))}",
        f"{lang}  │  {total:,} lines  │  {len(symbols)} symbols found",
    )
    parts = [header, OutputRenderer._divider()]

    if not symbols:
        parts.append("  (No recognizable symbols found. Try symbol_search for this language.)")
    else:
        # Group by kind
        by_kind: dict[str, list[dict]] = {}
        for s in symbols:
            by_kind.setdefault(s["kind"], []).append(s)

        for kind, items in by_kind.items():
            parts.append(f"\n  {kind.upper()}S ({len(items)})")
            for s in items:
                ln_str = f"L{s['line']}"
                parts.append(f"    {ln_str:>6}  {s['name']}")

    parts.append(f"\n{OutputRenderer._divider()}")
    parts.append(f"  Tip: read_file_rich path={path} start_line=N to jump to any symbol")
    block = "\n".join(parts)

    return FileOutlineResult(
        path=str(p), language=lang, symbols=symbols, block=block
    )


# ── Smart grep / search ───────────────────────────────────────────────

@dataclass
class SearchResult:
    """Result of a grep/ripgrep search."""
    query: str
    path: str
    matches: list[dict[str, Any]]
    backend: str
    block: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "stdout": self.block,
            "query": self.query,
            "path": self.path,
            "matches": self.matches,
            "count": len(self.matches),
            "backend": self.backend,
            "exitCode": 0,
            "success": True,
        }


async def search_files_rich(
    query: str,
    path: str = HOME,
    extensions: list[str] | None = None,
    case_sensitive: bool = False,
    max_matches: int = 80,
    context_lines: int = 2,
) -> SearchResult:
    """
    Search for text in files using ripgrep (if available) or grep.

    Returns matches with:
    - File path (relative)
    - Line number
    - Matching line content
    - Context lines above and below

    Parameters
    ----------
    query : str
        Text or regex pattern to search.
    path : str
        Directory or file to search in.
    extensions : list of str, optional
        File extensions to restrict search (e.g., ["dart", "py"]).
    case_sensitive : bool
        Whether the search is case-sensitive.
    max_matches : int
        Maximum number of matches to return.
    context_lines : int
        Lines of context around each match.
    """
    # Try ripgrep first (much faster), fallback to grep
    rg = shutil.which("rg")
    backend = "ripgrep" if rg else "grep"

    if rg:
        cmd_parts = [rg, "--line-number", "--no-heading", "--color=never"]
        if not case_sensitive:
            cmd_parts.append("--ignore-case")
        if context_lines > 0:
            cmd_parts.extend([f"--context={context_lines}"])
        if extensions:
            for ext in extensions:
                cmd_parts.extend(["--glob", f"*.{ext.lstrip('.')}"])
        cmd_parts.extend(["--max-count", "1"])  # 1 match per file for context
        cmd_parts.extend([f"--max-filesize=2M", query, path])
        command = " ".join(shlex.quote(str(p)) for p in cmd_parts)
    else:
        flags = "-rnI" if case_sensitive else "-rnIi"
        cmd_parts = ["grep", flags]
        if context_lines > 0:
            cmd_parts.extend([f"-{context_lines}"])
        if extensions:
            for ext in extensions:
                cmd_parts.append(f"--include=*.{ext.lstrip('.')}")
        cmd_parts.extend([query, path])
        command = " ".join(shlex.quote(str(p)) for p in cmd_parts)

    result = await shell_exec(command, cwd=HOME, timeout=15)

    matches: list[dict[str, Any]] = []
    raw_lines = result.stdout.splitlines()

    for line in raw_lines[:max_matches * 3]:  # read extra, parse up to limit
        # ripgrep: file:line:content  or  file-line-content (context)
        # grep: file:line:content
        m = re.match(r"^([^:\-]+)[:\-](\d+)[:\-](.*)$", line)
        if m and ":" in line:
            matches.append({
                "file": m.group(1),
                "line": int(m.group(2)),
                "content": m.group(3),
            })
            if len(matches) >= max_matches:
                break

    # ── Build block ──
    header = OutputRenderer.search_header(query, path, len(matches), backend)
    parts = [header]

    if not matches:
        if result.exit_code == 0:
            parts.append("  (No matches found)")
        else:
            parts.append(f"  Search failed: {result.stderr[:200]}")
    else:
        # Group by file
        by_file: dict[str, list[dict]] = {}
        for m in matches:
            by_file.setdefault(m["file"], []).append(m)

        for file_path, file_matches in list(by_file.items())[:30]:
            rel = _rel_path(file_path)
            parts.append(f"\n  📄 {rel} ({len(file_matches)} match(es))")
            for fm in file_matches[:10]:
                ln = fm["line"]
                content = fm["content"][:100]
                parts.append(f"    L{ln:>5}: {content}")

    if len(matches) >= max_matches:
        parts.append(f"\n  ⚠ Results capped at {max_matches}. Narrow the query or path.")

    parts.append(f"\n{OutputRenderer._divider()}")
    parts.append(f"  Tip: read_file_rich path=<file> start_line=<L> to jump to any match")
    block = "\n".join(parts)

    return SearchResult(query=query, path=path, matches=matches, backend=backend, block=block)


# ── File diff (two versions) ──────────────────────────────────────────

def diff_files_rich(path_a: str, path_b: str, context: int = 5) -> dict[str, Any]:
    """
    Compute a unified diff between two files.

    Returns a human+AI readable diff block with statistics.
    """
    pa = Path(path_a).expanduser()
    pb = Path(path_b).expanduser()

    a_lines = _read_lines_safe(pa) if pa.exists() else []
    b_lines = _read_lines_safe(pb) if pb.exists() else []

    diff = list(difflib.unified_diff(
        a_lines, b_lines,
        fromfile=_rel_path(str(pa)),
        tofile=_rel_path(str(pb)),
        n=context,
    ))

    added = sum(1 for l in diff if l.startswith("+") and not l.startswith("+++"))
    removed = sum(1 for l in diff if l.startswith("-") and not l.startswith("---"))

    header = OutputRenderer.tool_header(
        f"DIFF",
        f"a: {_rel_path(str(pa))}  →  b: {_rel_path(str(pb))}  │  +{added} -{removed}",
    )
    body = "".join(diff[:500]) if diff else "  (No differences)"
    block = f"{header}\n{OutputRenderer._divider()}\n{body}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "diff": "".join(diff),
        "linesAdded": added,
        "linesRemoved": removed,
        "exitCode": 0 if diff else 0,
        "success": True,
    }


# ── Directory tree ────────────────────────────────────────────────────

def tree_rich(
    path: str = HOME,
    max_depth: int = 4,
    show_hidden: bool = False,
    extensions: list[str] | None = None,
) -> dict[str, Any]:
    """
    Generate an annotated directory tree.

    Each file is annotated with size and modification time.
    Skips common noise directories (.git, build, __pycache__, etc.).

    Parameters
    ----------
    path : str
        Root directory.
    max_depth : int
        Max recursion depth.
    show_hidden : bool
        Whether to show dotfiles.
    extensions : list of str, optional
        If set, only show files with these extensions.
    """
    p = Path(path).expanduser()
    if not p.is_dir():
        raise NotADirectoryError(f"Not a directory: {path}")

    file_count = [0]
    dir_count = [0]
    lines: list[str] = []

    ext_filter = frozenset(f".{e.lstrip('.')}" for e in extensions) if extensions else None

    def _walk(cur: Path, prefix: str, depth: int) -> None:
        if depth > max_depth:
            return
        try:
            entries = sorted(cur.iterdir(), key=lambda e: (e.is_file(), e.name.lower()))
        except PermissionError:
            return

        visible = [
            e for e in entries
            if (show_hidden or not e.name.startswith("."))
            and e.name not in SKIP_DIRS
        ]

        for i, entry in enumerate(visible):
            is_last = (i == len(visible) - 1)
            connector = "└── " if is_last else "├── "
            ext_str = "  " + ("  " * depth)
            child_prefix = prefix + ("    " if is_last else "│   ")

            if entry.is_dir():
                dir_count[0] += 1
                lines.append(f"{prefix}{connector}📁 {entry.name}/")
                _walk(entry, child_prefix, depth + 1)
            else:
                if ext_filter and entry.suffix.lower() not in ext_filter:
                    continue
                file_count[0] += 1
                try:
                    s = entry.stat()
                    size = _human_size(s.st_size)
                    age = _age_str(s.st_mtime)
                    lang = LANG_MAP.get(entry.suffix.lower(), "")
                    meta = f"  [{size}, {age}]" if size else ""
                    lines.append(f"{prefix}{connector}{entry.name}{meta}")
                except OSError:
                    lines.append(f"{prefix}{connector}{entry.name}")

    header = OutputRenderer.tool_header(
        f"TREE: {_rel_path(str(p))}",
        f"depth={max_depth}  │  skip: .git, build, __pycache__, node_modules",
    )
    _walk(p, "", 0)
    footer = f"\n  {dir_count[0]} directories, {file_count[0]} files"

    block = f"{header}\n{OutputRenderer._divider()}\n" + "\n".join(lines) + f"\n{OutputRenderer._divider()}\n{footer}"

    return {
        "stdout": block,
        "fileCount": file_count[0],
        "dirCount": dir_count[0],
        "exitCode": 0,
        "success": True,
    }


# ══════════════════════════════════════════════════════════════════════
#  FILE SYSTEM TOOLS — append, delete, move, copy, mkdir, stat, chmod
# ══════════════════════════════════════════════════════════════════════


def append_file_rich(
    path: str,
    content: str,
    encoding: str = "utf-8",
    create_if_missing: bool = True,
) -> dict[str, Any]:
    """
    Append content to a file, optionally creating it if missing.

    Parameters
    ----------
    path : str
        Target file path.
    content : str
        Content to append.
    encoding : str
        File encoding (default utf-8).
    create_if_missing : bool
        If True and the file doesn't exist, create it (and parent dirs).
    """
    p = Path(path).expanduser()
    existed = p.exists()

    if not existed:
        if not create_if_missing:
            return {
                "stdout": f"ERROR: File does not exist: {path}",
                "exitCode": 1,
                "success": False,
                "error": f"File not found: {path}",
            }
        p.parent.mkdir(parents=True, exist_ok=True)

    lines_before = 0
    if existed and p.is_file():
        lines_before = len(_read_lines_safe(p, encoding))

    with open(str(p), "a", encoding=encoding) as f:
        f.write(content)

    new_lines = content.count("\n") + (1 if content and not content.endswith("\n") else 0)
    total_lines = lines_before + new_lines
    size_after = p.stat().st_size

    action = "APPENDED" if existed else "CREATED+APPENDED"
    header = OutputRenderer.tool_header(
        f"APPEND: {_rel_path(str(p))}",
        f"{action}  │  +{new_lines} lines  │  {_human_size(size_after)} total",
    )
    body = f"  Lines before: {lines_before}\n  Lines appended: {new_lines}\n  Total lines: {total_lines}\n  Size: {_human_size(size_after)}"
    block = f"{header}\n{OutputRenderer._divider()}\n{body}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "path": str(p),
        "linesBefore": lines_before,
        "linesAppended": new_lines,
        "totalLines": total_lines,
        "sizeBytes": size_after,
        "created": not existed,
        "exitCode": 0,
        "success": True,
    }


def delete_path_rich(
    path: str,
    recursive: bool = False,
) -> dict[str, Any]:
    """
    Delete a file or directory with safety guards.

    Parameters
    ----------
    path : str
        Target path to delete.
    recursive : bool
        If True, allow deleting non-empty directories.
        If False and path is a non-empty directory, fail safely.
    """
    p = Path(path).expanduser().resolve()

    # Hard-block: never delete system-critical paths
    PROTECTED_ROOTS = frozenset({
        "/", "/bin", "/sbin", "/usr", "/etc", "/var", "/dev", "/proc", "/sys",
        "/data", "/data/data", "/data/data/com.termux",
        "/data/data/com.termux/files", "/data/data/com.termux/files/usr",
        os.path.expanduser("~"),
    })
    if str(p) in PROTECTED_ROOTS:
        return {
            "stdout": f"ERROR: BLOCKED — Refusing to delete protected path: {p}",
            "exitCode": 1,
            "success": False,
            "error": f"Protected path: {p}",
        }

    if not p.exists():
        return {
            "stdout": f"ERROR: Path does not exist: {path}",
            "exitCode": 1,
            "success": False,
            "error": f"Path not found: {path}",
        }

    was_dir = p.is_dir()
    deleted_count = 0

    if p.is_file() or p.is_symlink():
        size = p.stat().st_size if p.is_file() else 0
        p.unlink()
        deleted_count = 1
        detail = f"  Deleted file: {_rel_path(str(p))}  ({_human_size(size)})"
    elif p.is_dir():
        if not recursive:
            # Check if empty
            children = list(p.iterdir())
            if children:
                return {
                    "stdout": f"ERROR: Directory is not empty ({len(children)} items). Use recursive=true to force.\n  Path: {path}",
                    "exitCode": 1,
                    "success": False,
                    "error": f"Non-empty directory ({len(children)} items). Set recursive=true.",
                }
            p.rmdir()
            deleted_count = 1
            detail = f"  Deleted empty directory: {_rel_path(str(p))}"
        else:
            # Count items before deletion
            for root, dirs, files in os.walk(str(p)):
                deleted_count += len(files)
                deleted_count += len(dirs)
            deleted_count += 1  # the root dir itself
            shutil.rmtree(str(p))
            detail = f"  Recursively deleted: {_rel_path(str(p))}\n  Items removed: {deleted_count}"
    else:
        return {
            "stdout": f"ERROR: Cannot delete special file type: {path}",
            "exitCode": 1,
            "success": False,
            "error": f"Unsupported file type: {path}",
        }

    kind = "directory" if was_dir else "file"
    header = OutputRenderer.tool_header(
        f"DELETE: {_rel_path(str(p))}",
        f"{kind}  │  {deleted_count} item(s) removed",
    )
    block = f"{header}\n{OutputRenderer._divider()}\n{detail}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "path": str(p),
        "wasDir": was_dir,
        "deletedCount": deleted_count,
        "exitCode": 0,
        "success": True,
    }


def move_path_rich(
    src: str,
    dest: str,
    overwrite: bool = False,
) -> dict[str, Any]:
    """
    Move (rename) a file or directory.

    Parameters
    ----------
    src : str
        Source path.
    dest : str
        Destination path.
    overwrite : bool
        If True, overwrite the destination if it exists.
    """
    ps = Path(src).expanduser().resolve()
    pd = Path(dest).expanduser()

    if not ps.exists():
        return {
            "stdout": f"ERROR: Source does not exist: {src}",
            "exitCode": 1,
            "success": False,
            "error": f"Source not found: {src}",
        }

    if pd.exists() and not overwrite:
        return {
            "stdout": f"ERROR: Destination already exists: {dest}\n  Set overwrite=true to replace.",
            "exitCode": 1,
            "success": False,
            "error": f"Destination exists: {dest}. Set overwrite=true.",
        }

    pd.parent.mkdir(parents=True, exist_ok=True)

    if pd.exists() and overwrite:
        if pd.is_dir():
            shutil.rmtree(str(pd))
        else:
            pd.unlink()

    # shutil.move handles cross-filesystem moves
    shutil.move(str(ps), str(pd))
    resolved_dest = Path(dest).expanduser().resolve()

    kind = "directory" if resolved_dest.is_dir() else "file"
    header = OutputRenderer.tool_header(
        f"MOVE",
        f"{_rel_path(str(ps))}  →  {_rel_path(str(resolved_dest))}  │  {kind}",
    )
    body = f"  From: {ps}\n  To:   {resolved_dest}"
    block = f"{header}\n{OutputRenderer._divider()}\n{body}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "src": str(ps),
        "dest": str(resolved_dest),
        "kind": kind,
        "exitCode": 0,
        "success": True,
    }


def copy_path_rich(
    src: str,
    dest: str,
    overwrite: bool = False,
) -> dict[str, Any]:
    """
    Copy a file or directory (recursively for directories).

    Parameters
    ----------
    src : str
        Source path.
    dest : str
        Destination path.
    overwrite : bool
        If True, overwrite the destination if it exists.
    """
    ps = Path(src).expanduser().resolve()
    pd = Path(dest).expanduser()

    if not ps.exists():
        return {
            "stdout": f"ERROR: Source does not exist: {src}",
            "exitCode": 1,
            "success": False,
            "error": f"Source not found: {src}",
        }

    if pd.exists() and not overwrite:
        return {
            "stdout": f"ERROR: Destination already exists: {dest}\n  Set overwrite=true to replace.",
            "exitCode": 1,
            "success": False,
            "error": f"Destination exists: {dest}. Set overwrite=true.",
        }

    pd.parent.mkdir(parents=True, exist_ok=True)

    if ps.is_dir():
        if pd.exists() and overwrite:
            shutil.rmtree(str(pd))
        shutil.copytree(str(ps), str(pd))
        kind = "directory"
    else:
        shutil.copy2(str(ps), str(pd))
        kind = "file"

    resolved_dest = Path(dest).expanduser().resolve()
    size = resolved_dest.stat().st_size if resolved_dest.is_file() else 0

    header = OutputRenderer.tool_header(
        f"COPY",
        f"{_rel_path(str(ps))}  →  {_rel_path(str(resolved_dest))}  │  {kind}  │  {_human_size(size) if size else 'dir'}",
    )
    body = f"  From: {ps}\n  To:   {resolved_dest}"
    block = f"{header}\n{OutputRenderer._divider()}\n{body}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "src": str(ps),
        "dest": str(resolved_dest),
        "kind": kind,
        "sizeBytes": size,
        "exitCode": 0,
        "success": True,
    }


def mkdir_path_rich(
    path: str,
    parents: bool = True,
) -> dict[str, Any]:
    """
    Create a directory (and parents if requested).

    Parameters
    ----------
    path : str
        Directory path to create.
    parents : bool
        If True, create parent directories as needed (like mkdir -p).
    """
    p = Path(path).expanduser()

    if p.exists():
        if p.is_dir():
            return {
                "stdout": f"  Directory already exists: {_rel_path(str(p))}",
                "exitCode": 0,
                "success": True,
                "alreadyExisted": True,
                "path": str(p.resolve()),
            }
        else:
            return {
                "stdout": f"ERROR: Path exists and is not a directory: {path}",
                "exitCode": 1,
                "success": False,
                "error": f"Path exists as file: {path}",
            }

    try:
        p.mkdir(parents=parents, exist_ok=True)
    except FileNotFoundError:
        return {
            "stdout": f"ERROR: Parent directory does not exist and parents=false: {path}",
            "exitCode": 1,
            "success": False,
            "error": f"Parent missing and parents=false: {path}",
        }

    resolved = p.resolve()
    header = OutputRenderer.tool_header(
        f"MKDIR: {_rel_path(str(resolved))}",
        f"parents={'yes' if parents else 'no'}",
    )
    block = f"{header}\n{OutputRenderer._divider()}\n  Created: {resolved}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "path": str(resolved),
        "alreadyExisted": False,
        "exitCode": 0,
        "success": True,
    }


def stat_path_rich(path: str) -> dict[str, Any]:
    """
    Return detailed metadata for a file or directory.

    Parameters
    ----------
    path : str
        Target path.
    """
    import datetime
    p = Path(path).expanduser().resolve()

    if not p.exists():
        return {
            "stdout": f"ERROR: Path does not exist: {path}",
            "exitCode": 1,
            "success": False,
            "error": f"Path not found: {path}",
        }

    try:
        s = p.stat()
    except OSError as e:
        return {
            "stdout": f"ERROR: Cannot stat: {e}",
            "exitCode": 1,
            "success": False,
            "error": str(e),
        }

    is_symlink = p.is_symlink()
    link_target = str(os.readlink(str(p))) if is_symlink else None
    kind = "symlink" if is_symlink else ("directory" if p.is_dir() else "file")
    permissions = stat.filemode(s.st_mode)
    lang = LANG_MAP.get(p.suffix.lower(), "") if p.is_file() else ""

    mtime_str = datetime.datetime.fromtimestamp(s.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
    atime_str = datetime.datetime.fromtimestamp(s.st_atime).strftime("%Y-%m-%d %H:%M:%S")
    ctime_str = datetime.datetime.fromtimestamp(s.st_ctime).strftime("%Y-%m-%d %H:%M:%S")

    header = OutputRenderer.tool_header(
        f"STAT: {_rel_path(str(p))}",
        f"{kind}  │  {permissions}  │  {_human_size(s.st_size)}",
    )
    lines = [
        f"  Path:        {p}",
        f"  Type:        {kind}",
        f"  Size:        {_human_size(s.st_size)} ({s.st_size:,} bytes)",
        f"  Permissions: {permissions} ({oct(s.st_mode)[-4:]})",
        f"  Owner UID:   {s.st_uid}",
        f"  Group GID:   {s.st_gid}",
        f"  Modified:    {mtime_str} ({_age_str(s.st_mtime)})",
        f"  Accessed:    {atime_str}",
        f"  Changed:     {ctime_str}",
        f"  Inode:       {s.st_ino}",
        f"  Hard links:  {s.st_nlink}",
    ]
    if lang:
        lines.append(f"  Language:    {lang}")
    if is_symlink:
        lines.append(f"  Link target: {link_target}")

    body = "\n".join(lines)
    block = f"{header}\n{OutputRenderer._divider()}\n{body}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "path": str(p),
        "kind": kind,
        "sizeBytes": s.st_size,
        "permissions": permissions,
        "permissionsOctal": oct(s.st_mode)[-4:],
        "uid": s.st_uid,
        "gid": s.st_gid,
        "mtime": s.st_mtime,
        "atime": s.st_atime,
        "isSymlink": is_symlink,
        "linkTarget": link_target,
        "language": lang,
        "exitCode": 0,
        "success": True,
    }


def chmod_path_rich(
    path: str,
    mode: str,
    recursive: bool = False,
) -> dict[str, Any]:
    """
    Change file/directory permissions.

    Parameters
    ----------
    path : str
        Target path.
    mode : str
        Octal mode string (e.g., '755', '644').
    recursive : bool
        If True and path is a directory, apply chmod recursively.
    """
    p = Path(path).expanduser().resolve()

    if not p.exists():
        return {
            "stdout": f"ERROR: Path does not exist: {path}",
            "exitCode": 1,
            "success": False,
            "error": f"Path not found: {path}",
        }

    # Parse octal mode
    try:
        octal_mode = int(mode, 8)
    except ValueError:
        return {
            "stdout": f"ERROR: Invalid octal mode: '{mode}'. Use e.g. '755', '644'.",
            "exitCode": 1,
            "success": False,
            "error": f"Invalid octal mode: {mode}",
        }

    # Safety: block chmod 777 on home dir
    home = os.path.expanduser("~")
    if str(p) == home and octal_mode == 0o777:
        return {
            "stdout": f"ERROR: BLOCKED — Refusing to chmod 777 on home directory.",
            "exitCode": 1,
            "success": False,
            "error": "Blocked: chmod 777 on home",
        }

    changed_count = 0
    old_mode = stat.filemode(p.stat().st_mode)

    if recursive and p.is_dir():
        for root, dirs, files in os.walk(str(p)):
            os.chmod(root, octal_mode)
            changed_count += 1
            for f in files:
                os.chmod(os.path.join(root, f), octal_mode)
                changed_count += 1
    else:
        os.chmod(str(p), octal_mode)
        changed_count = 1

    new_mode = stat.filemode(p.stat().st_mode)
    header = OutputRenderer.tool_header(
        f"CHMOD: {_rel_path(str(p))}",
        f"{old_mode} → {new_mode}  │  {changed_count} item(s)",
    )
    body = f"  Path: {p}\n  Old: {old_mode}\n  New: {new_mode} ({mode})\n  Items changed: {changed_count}"
    block = f"{header}\n{OutputRenderer._divider()}\n{body}\n{OutputRenderer._divider()}"

    return {
        "stdout": block,
        "path": str(p),
        "oldMode": old_mode,
        "newMode": new_mode,
        "modeOctal": mode,
        "changedCount": changed_count,
        "recursive": recursive,
        "exitCode": 0,
        "success": True,
    }


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
        "read_file_rich",
        lambda **kw: read_file_rich(**kw).to_dict(),
        "Read a file with numbered lines, language detection, and navigation hints",
        {
            "path": "str — absolute or ~ path",
            "start_line": "int (opt, default 1) — first line to show",
            "end_line": "int (opt) — last line to show",
            "max_lines": f"int (opt, default {DEFAULT_MAX_LINES}) — max lines per call",
        },
    )

    reg.register(
        "multi_read_rich",
        lambda reads, **kw: multi_read_rich(reads, **kw).to_dict(),
        "Batch-read multiple files or ranges in one call",
        {
            "reads": "list — each item: {path, start_line, end_line, label}",
            "max_lines_per_file": f"int (opt, default {DEFAULT_MAX_LINES})",
        },
    )

    reg.register(
        "write_file_rich",
        lambda **kw: write_file_rich(**kw).to_dict(),
        "Atomically write a file with auto-backup and write verification",
        {
            "path": "str — target file path",
            "content": "str — complete file content",
            "encoding": "str (opt, default utf-8)",
            "backup": "bool (opt, default true) — save .bak before overwriting",
        },
    )

    reg.register(
        "patch_file_rich",
        lambda **kw: patch_file_rich(**kw).to_dict(),
        "Apply multiple search-replace patches atomically with diff output",
        {
            "path": "str — target file path",
            "patches": "list — each: {search: str, replace: str, count: int, label: str}",
            "backup": "bool (opt, default true)",
        },
    )

    reg.register(
        "replace_lines_rich",
        lambda **kw: replace_lines_rich(**kw).to_dict(),
        "Replace a specific line range with new content, with diff output",
        {
            "path": "str — target file path",
            "start_line": "int — first line to replace (1-indexed)",
            "end_line": "int — last line to replace (inclusive)",
            "new_content": "str — replacement content",
        },
    )

    reg.register(
        "insert_lines_rich",
        lambda **kw: insert_lines_rich(**kw).to_dict(),
        "Insert lines after a specific line number",
        {
            "path": "str — target file path",
            "after_line": "int — insert after this line (0 = beginning)",
            "content": "str — content to insert",
        },
    )

    reg.register(
        "delete_lines_rich",
        lambda **kw: delete_lines_rich(**kw).to_dict(),
        "Delete a specific line range from a file",
        {
            "path": "str — target file path",
            "start_line": "int — first line to delete (1-indexed)",
            "end_line": "int — last line to delete (inclusive)",
        },
    )

    reg.register(
        "file_outline_rich",
        lambda **kw: file_outline_rich(**kw).to_dict(),
        "Extract classes, functions, methods with line numbers — structure map before reading",
        {
            "path": "str — source file path (Dart, Python, JS, TS supported)",
        },
    )

    reg.register(
        "search_rich",
        None,  # async — registered separately
        "Search text/regex across files using ripgrep (if available) or grep, with context",
        {
            "query": "str — search text or regex",
            "path": "str (opt) — directory or file to search",
            "extensions": "list[str] (opt) — e.g. ['dart', 'py']",
            "case_sensitive": "bool (opt, default false)",
            "max_matches": "int (opt, default 80)",
            "context_lines": "int (opt, default 2) — lines around each match",
        },
    )

    reg.register(
        "tree_rich",
        lambda **kw: tree_rich(**kw),
        "Annotated directory tree with file sizes and ages, skipping noise dirs",
        {
            "path": "str (opt, default $HOME) — root directory",
            "max_depth": "int (opt, default 4)",
            "show_hidden": "bool (opt, default false)",
            "extensions": "list[str] (opt) — filter by extension",
        },
    )

    reg.register(
        "diff_files_rich",
        lambda **kw: diff_files_rich(**kw),
        "Compute unified diff between two files",
        {
            "path_a": "str — original file",
            "path_b": "str — modified file",
            "context": "int (opt, default 5) — context lines",
        },
    )

    reg.register(
        "tool_help",
        lambda **kw: {"stdout": reg.tool_help_block(), "exitCode": 0, "success": True},
        "List all hybrid tools with descriptions and parameter schemas",
        {},
    )

    # ── File System Tools (append, delete, move, copy, mkdir, stat, chmod) ──

    reg.register(
        "append_file",
        lambda **kw: append_file_rich(**kw),
        "Append content to a file (creates if missing)",
        {
            "path": "str — target file path",
            "content": "str — content to append",
            "encoding": "str (opt, default utf-8)",
            "create_if_missing": "bool (opt, default true) — create file if it doesn't exist",
        },
    )

    reg.register(
        "delete_path",
        lambda **kw: delete_path_rich(**kw),
        "Delete a file or directory with safety guards (protects system dirs)",
        {
            "path": "str — path to delete",
            "recursive": "bool (opt, default false) — required for non-empty directories",
        },
    )

    reg.register(
        "move_path",
        lambda **kw: move_path_rich(**kw),
        "Move/rename a file or directory (cross-filesystem safe)",
        {
            "src": "str — source path",
            "dest": "str — destination path",
            "overwrite": "bool (opt, default false) — overwrite destination if exists",
        },
    )

    reg.register(
        "copy_path",
        lambda **kw: copy_path_rich(**kw),
        "Copy a file or directory (recursive for dirs, preserves metadata)",
        {
            "src": "str — source path",
            "dest": "str — destination path",
            "overwrite": "bool (opt, default false) — overwrite destination if exists",
        },
    )

    reg.register(
        "mkdir_path",
        lambda **kw: mkdir_path_rich(**kw),
        "Create a directory (mkdir -p by default)",
        {
            "path": "str — directory path to create",
            "parents": "bool (opt, default true) — create parent directories",
        },
    )

    reg.register(
        "stat_path",
        lambda **kw: stat_path_rich(**kw),
        "Return detailed file/dir metadata (size, permissions, timestamps, type)",
        {
            "path": "str — path to inspect",
        },
    )

    reg.register(
        "chmod_path",
        lambda **kw: chmod_path_rich(**kw),
        "Change file/directory permissions (with recursive option)",
        {
            "path": "str — target path",
            "mode": "str — octal mode (e.g. '755', '644')",
            "recursive": "bool (opt, default false) — apply recursively to directory contents",
        },
    )

    return reg
