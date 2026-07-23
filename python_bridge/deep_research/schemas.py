"""Data shapes for the deep-research pipeline (FACT/FINDING store)."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class FactRecord:
    metric: str = ""
    subject: str = ""
    value: str = ""
    date: str = ""
    source: str = ""
    confidence: str = "high"  # high | medium | low (snippets = low)

    def to_dict(self) -> dict[str, str]:
        return {k: str(v) for k, v in asdict(self).items()}


@dataclass
class FindingRecord:
    text: str = ""
    source: str = ""
    confidence: str = "high"

    def to_dict(self) -> dict[str, str]:
        return {k: str(v) for k, v in asdict(self).items()}


@dataclass
class PhaseRecord:
    stage_id: str
    phase_title: str
    facts: list[dict[str, str]] = field(default_factory=list)
    findings: list[dict[str, str]] = field(default_factory=list)
    skipped_pdfs: list[dict[str, str]] = field(default_factory=list)
    failed_fetches: list[dict[str, str]] = field(default_factory=list)
    status: str = "pending"  # pending | running | completed | failed

    def to_dict(self) -> dict[str, Any]:
        return {
            "stage_id": self.stage_id,
            "phase_title": self.phase_title,
            "facts": self.facts,
            "findings": self.findings,
            "skipped_pdfs": self.skipped_pdfs,
            "failed_fetches": self.failed_fetches,
            "status": self.status,
        }


@dataclass
class RunCheckpoint:
    """Durable mid-run state so Resume can skip completed phases."""

    run_id: str = ""
    status: str = "idle"  # idle | running | completed | failed
    current_phase_index: int = 0
    steps: list[dict[str, Any]] = field(default_factory=list)
    stats: dict[str, Any] = field(default_factory=dict)
    updated_ms: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "status": self.status,
            "current_phase_index": self.current_phase_index,
            "steps": self.steps,
            "stats": self.stats,
            "updated_ms": self.updated_ms,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> "RunCheckpoint":
        if not data:
            return cls()
        return cls(
            run_id=str(data.get("run_id") or ""),
            status=str(data.get("status") or "idle"),
            current_phase_index=int(data.get("current_phase_index") or 0),
            steps=list(data.get("steps") or []),
            stats=dict(data.get("stats") or {}),
            updated_ms=int(data.get("updated_ms") or 0),
        )
