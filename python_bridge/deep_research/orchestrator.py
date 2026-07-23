"""Orchestrator for 3-agent Deep Research storing structured FACT/FINDING records.

No embedding model, no vector search. Evidence lives in temp.json; run progress
lives in checkpoint.json so Resume can continue without re-planning.
"""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Any

from .schemas import RunCheckpoint

logger = logging.getLogger("termux_forge.deep_research")


class DeepResearchOrchestrator:
    def __init__(self, data_dir: str | Path | None = None) -> None:
        self.data_dir = Path(
            data_dir or os.getenv("DEEP_RESEARCH_DIR", "~/.termux_forge/deep_research")
        ).expanduser()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.temp_path = Path(
            os.getenv("DEEP_RESEARCH_TEMP_PATH", self.data_dir / "temp.json")
        ).expanduser()
        self.checkpoint_path = Path(
            os.getenv(
                "DEEP_RESEARCH_CHECKPOINT_PATH", self.data_dir / "checkpoint.json"
            )
        ).expanduser()
        self.run_ingested_urls: set[str] = set()

    # ── Run lifecycle ─────────────────────────────────────────────────

    def reset_run(self, keep_checkpoint: bool = False) -> dict[str, str]:
        """Clear temp.json and in-memory caches for a new research run."""
        self.run_ingested_urls.clear()
        self._write_temp([])
        if not keep_checkpoint:
            self._write_checkpoint(RunCheckpoint().to_dict())
        logger.info("Deep Research run reset (keep_checkpoint=%s).", keep_checkpoint)
        return {"status": "ok"}

    def update_phase(
        self,
        stage_id: str,
        phase_title: str,
        facts: list[dict[str, str]] | None = None,
        findings: list[dict[str, str]] | None = None,
        skipped_pdfs: list[dict[str, str]] | None = None,
        failed_fetches: list[dict[str, str]] | None = None,
        status: str = "running",
    ) -> dict[str, str]:
        """Update or insert a phase record in temp.json."""
        payload = self._read_temp()

        phase_idx = -1
        for idx, phase in enumerate(payload):
            if phase.get("stage_id") == stage_id:
                phase_idx = idx
                break

        new_phase = {
            "stage_id": stage_id,
            "phase_title": phase_title,
            "facts": facts or [],
            "findings": findings or [],
            "skipped_pdfs": skipped_pdfs or [],
            "failed_fetches": failed_fetches or [],
            "status": status or "running",
        }

        if phase_idx != -1:
            payload[phase_idx] = new_phase
        else:
            payload.append(new_phase)

        self._write_temp(payload)
        logger.info("Updated phase record for %s in temp.json.", stage_id)
        return {"status": "ok"}

    def export_temp(self) -> str:
        """Return the raw JSON content of temp.json."""
        if not self.temp_path.exists():
            return "[]"
        try:
            return self.temp_path.read_text(encoding="utf-8")
        except Exception as e:
            logger.error("Failed to read temp.json: %s", e)
            return "[]"

    # ── Checkpoint / resume ───────────────────────────────────────────

    def save_checkpoint(
        self,
        run_id: str = "",
        status: str = "running",
        current_phase_index: int = 0,
        steps: list[dict[str, Any]] | None = None,
        stats: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        cp = RunCheckpoint(
            run_id=run_id or "",
            status=status or "running",
            current_phase_index=int(current_phase_index or 0),
            steps=list(steps or []),
            stats=dict(stats or {}),
            updated_ms=int(time.time() * 1000),
        )
        data = cp.to_dict()
        self._write_checkpoint(data)
        return {"status": "ok", "checkpoint": data}

    def load_checkpoint(self) -> dict[str, Any]:
        data = self._read_checkpoint()
        return {"status": "ok", "checkpoint": data}

    def clear_checkpoint(self) -> dict[str, str]:
        self._write_checkpoint(RunCheckpoint().to_dict())
        return {"status": "ok"}

    # ── Budget-aware evidence export ──────────────────────────────────

    def export_for_writer(
        self,
        max_evidence_tokens: int = 26000,
        prefer_facts: bool = True,
    ) -> dict[str, Any]:
        """
        Export evidence trimmed to fit a token budget.

        Strategy (better than dropping whole phases):
        1. Always keep phase headers.
        2. Prefer FACT records over FINDING records.
        3. Round-robin findings across phases.
        4. Drop low-confidence findings first.
        """
        phases = self._read_temp()
        if not phases:
            return {
                "content": "[]",
                "token_estimate": 0,
                "truncated_facts": 0,
                "truncated_findings": 0,
                "truncated_phases": 0,
            }

        # Normalize + sort findings: high confidence first within each phase
        working: list[dict[str, Any]] = []
        for phase in phases:
            if not isinstance(phase, dict):
                continue
            facts = list(phase.get("facts") or [])
            findings = list(phase.get("findings") or [])

            def conf_rank(item: dict) -> int:
                c = str(item.get("confidence") or "high").lower()
                return {"high": 0, "medium": 1, "low": 2}.get(c, 1)

            findings_sorted = sorted(
                [f for f in findings if isinstance(f, dict)],
                key=conf_rank,
            )
            working.append(
                {
                    "stage_id": phase.get("stage_id", ""),
                    "phase_title": phase.get("phase_title", ""),
                    "facts": [f for f in facts if isinstance(f, dict)],
                    "findings": findings_sorted,
                    "skipped_pdfs": list(phase.get("skipped_pdfs") or []),
                    "failed_fetches": list(phase.get("failed_fetches") or []),
                    "status": phase.get("status", "completed"),
                    "_kept_findings": [],
                }
            )

        def estimate_tokens(obj: Any) -> int:
            text = json.dumps(obj, ensure_ascii=True)
            # ~4 chars per token heuristic (more stable than word*1.3)
            return max(1, (len(text) + 3) // 4)

        # Start with facts + metadata only
        accepted: list[dict[str, Any]] = []
        used = 0
        truncated_facts = 0
        truncated_findings = 0

        for phase in working:
            base = {
                "stage_id": phase["stage_id"],
                "phase_title": phase["phase_title"],
                "facts": [],
                "findings": [],
                "skipped_pdfs": phase["skipped_pdfs"][:10],
                "failed_fetches": phase["failed_fetches"][:10],
                "status": phase["status"],
            }
            # Add facts greedily
            kept_facts: list[dict] = []
            for fact in phase["facts"]:
                trial = {**base, "facts": kept_facts + [fact]}
                cost = estimate_tokens(trial) - estimate_tokens(base if not kept_facts else {**base, "facts": kept_facts})
                # simpler: recompute full package later; per-item approx
                item_cost = estimate_tokens(fact)
                if used + item_cost + 40 <= max_evidence_tokens:
                    kept_facts.append(fact)
                    used += item_cost
                else:
                    truncated_facts += 1
            base["facts"] = kept_facts
            accepted.append(base)
            used = estimate_tokens(accepted)

        # Round-robin findings across phases
        max_rounds = max((len(p["findings"]) for p in working), default=0)
        for round_i in range(max_rounds):
            for p_idx, phase in enumerate(working):
                if round_i >= len(phase["findings"]):
                    continue
                finding = phase["findings"][round_i]
                item_cost = estimate_tokens(finding)
                if used + item_cost > max_evidence_tokens:
                    truncated_findings += 1
                    continue
                accepted[p_idx]["findings"].append(finding)
                used += item_cost

        # Drop empty phases that contributed nothing (but keep at least one if any)
        non_empty = [
            p
            for p in accepted
            if p["facts"] or p["findings"] or p["skipped_pdfs"] or p["failed_fetches"]
        ]
        truncated_phases = 0
        if not non_empty and accepted:
            non_empty = [accepted[0]]
            truncated_phases = max(0, len(accepted) - 1)
        elif non_empty:
            truncated_phases = max(0, len(phases) - len(non_empty))

        content = json.dumps(non_empty, ensure_ascii=True, indent=2)
        return {
            "content": content,
            "token_estimate": estimate_tokens(non_empty),
            "truncated_facts": truncated_facts,
            "truncated_findings": truncated_findings,
            "truncated_phases": truncated_phases,
        }

    # ── Internal I/O ──────────────────────────────────────────────────

    def _read_temp(self) -> list[dict[str, Any]]:
        if not self.temp_path.exists():
            return []
        try:
            val = json.loads(self.temp_path.read_text(encoding="utf-8"))
            return val if isinstance(val, list) else []
        except Exception as e:
            logger.warning("Failed to read temp.json: %s", e)
            return []

    def _write_temp(self, payload: list[dict[str, Any]]) -> None:
        self._atomic_write(self.temp_path, payload)

    def _read_checkpoint(self) -> dict[str, Any]:
        if not self.checkpoint_path.exists():
            return RunCheckpoint().to_dict()
        try:
            val = json.loads(self.checkpoint_path.read_text(encoding="utf-8"))
            return RunCheckpoint.from_dict(val if isinstance(val, dict) else {}).to_dict()
        except Exception as e:
            logger.warning("Failed to read checkpoint.json: %s", e)
            return RunCheckpoint().to_dict()

    def _write_checkpoint(self, payload: dict[str, Any]) -> None:
        self._atomic_write(self.checkpoint_path, payload)

    def _atomic_write(self, path: Path, payload: Any) -> None:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            temp_file = path.with_suffix(path.suffix + ".tmp")
            temp_file.write_text(
                json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8"
            )
            temp_file.replace(path)
        except Exception as e:
            logger.error("Failed to write %s: %s", path, e)
