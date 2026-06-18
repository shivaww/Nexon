"""
TermuxForge Security Module
============================

Provides command safety filtering, path validation, risk classification,
and safety score calculation to prevent destructive operations in the
Termux environment.

All commands are evaluated against blocked patterns and risk levels
before execution is permitted.
"""

import re
import os
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

logger = logging.getLogger("termux_forge.security")


class RiskLevel(Enum):
    """Classification of command risk levels."""

    SAFE = "safe"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"
    BLOCKED = "blocked"


@dataclass
class SafetyResult:
    """Result of a safety evaluation on a command."""

    allowed: bool
    risk_level: RiskLevel
    score: float  # 0.0 (dangerous) to 1.0 (safe)
    reason: str
    matched_pattern: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "allowed": self.allowed,
            "risk_level": self.risk_level.value,
            "score": self.score,
            "reason": self.reason,
            "matched_pattern": self.matched_pattern,
        }


# ── Blocked command patterns ──────────────────────────────────────────
# Each tuple: (compiled regex, human-readable description)
BLOCKED_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\brm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/\s*$"), "rm on root filesystem"),
    (re.compile(r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s+/\b"), "recursive rm on root"),
    (re.compile(r"\brm\s+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*\s+/\b"), "recursive rm on root"),
    (re.compile(r"\bmkfs\b"), "filesystem format"),
    (re.compile(r"\bdd\s+.*of=/dev/"), "raw disk write"),
    (re.compile(r"\bformat\s+[a-zA-Z]:"), "drive format"),
    (re.compile(r">\s*/dev/sd[a-z]"), "redirect to disk device"),
    (re.compile(r"\bchmod\s+-[a-zA-Z]*R[a-zA-Z]*\s+777\s+/\s*$"), "chmod 777 on root"),
    (re.compile(r"\bchown\s+-[a-zA-Z]*R[a-zA-Z]*\s+.*\s+/\s*$"), "chown on root"),
    (re.compile(r":\(\)\{.*\|.*&\s*\};:"), "fork bomb"),
    (re.compile(r"\bsudo\s+rm\b"), "sudo rm"),
    (re.compile(r"\bsudo\s+dd\b"), "sudo dd"),
    (re.compile(r"\bsudo\s+mkfs\b"), "sudo mkfs"),
    (re.compile(r"\b>\s*/etc/passwd\b"), "overwrite passwd"),
    (re.compile(r"\b>\s*/etc/shadow\b"), "overwrite shadow"),
    (re.compile(r"\bcurl\s+.*\|\s*(ba)?sh\b"), "pipe curl to shell"),
    (re.compile(r"\bwget\s+.*\|\s*(ba)?sh\b"), "pipe wget to shell"),
    (re.compile(r"\beval\s+.*\$\(curl"), "eval remote code"),
    (re.compile(r"\bshutdown\b"), "system shutdown"),
    (re.compile(r"\breboot\b"), "system reboot"),
    (re.compile(r"\bhalt\b"), "system halt"),
    (re.compile(r"\binit\s+0\b"), "system init 0"),
    (re.compile(r"\bkillall\s+-9\s+-1\b"), "kill all processes"),
    (re.compile(r"\bkill\s+-9\s+-1\b"), "kill all processes"),
]

# ── High-risk patterns (allowed but flagged) ──────────────────────────
HIGH_RISK_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\brm\s+-[a-zA-Z]*r"), "recursive delete"),
    (re.compile(r"\bchmod\s+-R\b"), "recursive chmod"),
    (re.compile(r"\bchown\s+-R\b"), "recursive chown"),
    (re.compile(r"\bgit\s+push\s+.*--force\b"), "force push"),
    (re.compile(r"\bgit\s+reset\s+--hard\b"), "hard reset"),
    (re.compile(r"\bgit\s+clean\s+-[a-zA-Z]*f"), "git clean force"),
    (re.compile(r"\bpip\s+install\b.*--break-system"), "break system packages"),
    (re.compile(r"\bnpm\s+.*--force\b"), "npm force"),
]

# ── Medium-risk patterns ──────────────────────────────────────────────
MEDIUM_RISK_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bgit\s+push\b"), "git push"),
    (re.compile(r"\bgit\s+checkout\b"), "git checkout"),
    (re.compile(r"\bgit\s+merge\b"), "git merge"),
    (re.compile(r"\bpip\s+install\b"), "pip install"),
    (re.compile(r"\bnpm\s+install\b"), "npm install"),
    (re.compile(r"\bpkg\s+install\b"), "pkg install"),
    (re.compile(r"\bapt\s+install\b"), "apt install"),
    (re.compile(r"\bflutter\s+build\b"), "flutter build"),
    (re.compile(r"\bcurl\b"), "network request"),
    (re.compile(r"\bwget\b"), "network download"),
]

# ── Default approved directories ──────────────────────────────────────
DEFAULT_APPROVED_PATHS: list[str] = [
    "/data/data/com.termux/files/home",
    "/data/data/com.termux/files/usr",
    "/sdcard",
    "/storage/emulated/0",
]


class SecurityManager:
    """
    Evaluates commands for safety before execution.

    Maintains a list of blocked patterns, risk classifications,
    and approved working directories.
    """

    def __init__(
        self,
        approved_paths: list[str] | None = None,
        extra_blocked: list[tuple[str, str]] | None = None,
    ) -> None:
        self.approved_paths = approved_paths or list(DEFAULT_APPROVED_PATHS)
        self.blocked_patterns = list(BLOCKED_PATTERNS)
        if extra_blocked:
            for pattern, desc in extra_blocked:
                self.blocked_patterns.append((re.compile(pattern), desc))

    # ── Public API ────────────────────────────────────────────────────

    def evaluate(self, command: str, cwd: str | None = None) -> SafetyResult:
        """
        Evaluate a command string for safety.

        Parameters
        ----------
        command : str
            The shell command to evaluate.
        cwd : str, optional
            Working directory; validated against approved paths.

        Returns
        -------
        SafetyResult
            Contains allowed flag, risk level, safety score, and reason.
        """
        command = command.strip()

        if not command:
            return SafetyResult(
                allowed=False,
                risk_level=RiskLevel.BLOCKED,
                score=0.0,
                reason="Empty command",
            )

        # Check working directory
        if cwd and not self.validate_path(cwd):
            return SafetyResult(
                allowed=False,
                risk_level=RiskLevel.BLOCKED,
                score=0.0,
                reason=f"Working directory outside approved paths: {cwd}",
            )

        # Check blocked patterns
        for pattern, desc in self.blocked_patterns:
            if pattern.search(command):
                logger.warning("BLOCKED command: %s (matched: %s)", command, desc)
                return SafetyResult(
                    allowed=False,
                    risk_level=RiskLevel.BLOCKED,
                    score=0.0,
                    reason=f"Command matches blocked pattern: {desc}",
                    matched_pattern=desc,
                )

        # Check high-risk patterns
        for pattern, desc in HIGH_RISK_PATTERNS:
            if pattern.search(command):
                logger.info("HIGH-RISK command: %s (matched: %s)", command, desc)
                return SafetyResult(
                    allowed=True,
                    risk_level=RiskLevel.HIGH,
                    score=0.3,
                    reason=f"High-risk operation: {desc}",
                    matched_pattern=desc,
                )

        # Check medium-risk patterns
        for pattern, desc in MEDIUM_RISK_PATTERNS:
            if pattern.search(command):
                return SafetyResult(
                    allowed=True,
                    risk_level=RiskLevel.MEDIUM,
                    score=0.6,
                    reason=f"Medium-risk operation: {desc}",
                    matched_pattern=desc,
                )

        # Check low-risk indicators
        risk = self._classify_low_risk(command)
        if risk:
            return risk

        return SafetyResult(
            allowed=True,
            risk_level=RiskLevel.SAFE,
            score=1.0,
            reason="Command appears safe",
        )

    def validate_path(self, path: str) -> bool:
        """
        Check whether a path is within approved directories.

        Parameters
        ----------
        path : str
            Absolute path to validate.

        Returns
        -------
        bool
            True if the path is within an approved directory.
        """
        resolved = os.path.realpath(path)
        for approved in self.approved_paths:
            if resolved.startswith(os.path.realpath(approved)):
                return True
        return False

    def add_approved_path(self, path: str) -> None:
        """Add a directory to the approved paths list."""
        resolved = os.path.realpath(path)
        if resolved not in self.approved_paths:
            self.approved_paths.append(resolved)
            logger.info("Added approved path: %s", resolved)

    def calculate_safety_score(self, command: str) -> float:
        """
        Calculate a numeric safety score for a command.

        Returns
        -------
        float
            Score between 0.0 (dangerous) and 1.0 (safe).
        """
        result = self.evaluate(command)
        return result.score

    # ── Private helpers ───────────────────────────────────────────────

    def _classify_low_risk(self, command: str) -> SafetyResult | None:
        """Classify commands with mild risk indicators."""
        low_risk_indicators = [
            (r"\bsudo\b", "uses sudo"),
            (r"\bsu\b", "switch user"),
            (r">\s*\S+", "file redirect"),
            (r">>\s*\S+", "file append"),
            (r"\|", "pipe"),
        ]
        for pattern, desc in low_risk_indicators:
            if re.search(pattern, command):
                return SafetyResult(
                    allowed=True,
                    risk_level=RiskLevel.LOW,
                    score=0.8,
                    reason=f"Low-risk indicator: {desc}",
                    matched_pattern=desc,
                )
        return None
