"""Orchestrator for 3-agent Deep Research storing structured FACT/FINDING records.

No embedding model, no vector search. Evidence lives in temp.json; run progress
lives in checkpoint.json so Resume can continue without re-planning.
"""

from __future__ import annotations

import asyncio
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
        # Serialize atomic writes across concurrent bridge RPC handlers.
        self._lock = asyncio.Lock()

    # ── Run lifecycle ─────────────────────────────────────────────────

    async def reset_run(self, keep_checkpoint: bool = False) -> dict[str, str]:
        """Clear temp.json and in-memory caches for a new research run."""
        self.run_ingested_urls.clear()
        await self._write_temp([])
        if not keep_checkpoint:
            await self._write_checkpoint(RunCheckpoint().to_dict())
        logger.info("Deep Research run reset (keep_checkpoint=%s).", keep_checkpoint)
        return {"status": "ok"}

    async def update_phase(
        self,
        stage_id: str,
        phase_title: str,
        summary: str = "",
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
            "summary": summary or "",
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

        await self._write_temp(payload)
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

    async def save_checkpoint(
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
        await self._write_checkpoint(data)
        return {"status": "ok", "checkpoint": data}

    def load_checkpoint(self) -> dict[str, Any]:
        data = self._read_checkpoint()
        return {"status": "ok", "checkpoint": data}

    async def clear_checkpoint(self) -> dict[str, str]:
        await self._write_checkpoint(RunCheckpoint().to_dict())
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
        2. When prefer_facts (default): process FACT records first, then findings.
           When False: process FINDING records first, then facts.
        3. Round-robin secondary records across phases.
        4. Drop low-confidence records first.
        5. After each add, recompute used = estimate_tokens(accepted).
        6. If still over budget, truncate the primary record type as well.
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
                    "summary": phase.get("summary", ""),
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
            return max(1, (len(text) + 3) // 4) if text else 0

        # Start with metadata + primary records (facts if prefer_facts, else findings)
        accepted: list[dict[str, Any]] = []
        used = 0
        truncated_facts = 0
        truncated_findings = 0

        primary_key = "facts" if prefer_facts else "findings"
        secondary_key = "findings" if prefer_facts else "facts"

        for phase in working:
            base = {
                "stage_id": phase["stage_id"],
                "phase_title": phase["phase_title"],
                "summary": phase["summary"],
                "facts": [],
                "findings": [],
                "skipped_pdfs": phase["skipped_pdfs"][:10],
                "failed_fetches": phase["failed_fetches"][:10],
                "status": phase["status"],
            }
            accepted.append(base)
            used = estimate_tokens(accepted)

            # Add primary records greedily; full recompute after each add.
            kept_primary: list[dict] = []
            for record in phase[primary_key]:
                kept_primary.append(record)
                base[primary_key] = kept_primary
                used = estimate_tokens(accepted)
                if used > max_evidence_tokens:
                    kept_primary.pop()
                    base[primary_key] = list(kept_primary)
                    used = estimate_tokens(accepted)
                    if prefer_facts:
                        truncated_facts += 1
                    else:
                        truncated_findings += 1
            base[primary_key] = kept_primary

        # Round-robin secondary records across phases; full recompute after each add.
        max_rounds = max((len(p[secondary_key]) for p in working), default=0)
        for round_i in range(max_rounds):
            for p_idx, phase in enumerate(working):
                if round_i >= len(phase[secondary_key]):
                    continue
                record = phase[secondary_key][round_i]
                accepted[p_idx][secondary_key].append(record)
                used = estimate_tokens(accepted)
                if used > max_evidence_tokens:
                    accepted[p_idx][secondary_key].pop()
                    used = estimate_tokens(accepted)
                    if prefer_facts:
                        truncated_findings += 1
                    else:
                        truncated_facts += 1

        # If still over budget (headers alone can overshoot), drop facts too.
        used = estimate_tokens(accepted)
        if used > max_evidence_tokens:
            # Drop lowest-priority facts from the end of each phase, round-robin.
            while used > max_evidence_tokens:
                dropped_any = False
                for p in reversed(accepted):
                    facts_list = p.get("facts") or []
                    if facts_list:
                        facts_list.pop()
                        truncated_facts += 1
                        dropped_any = True
                        used = estimate_tokens(accepted)
                        if used <= max_evidence_tokens:
                            break
                if not dropped_any:
                    # Last resort: strip findings then summaries.
                    for p in reversed(accepted):
                        findings_list = p.get("findings") or []
                        if findings_list:
                            findings_list.pop()
                            truncated_findings += 1
                            used = estimate_tokens(accepted)
                            dropped_any = True
                            if used <= max_evidence_tokens:
                                break
                    if not dropped_any:
                        break

        # Drop empty phases that contributed nothing (but keep at least one if any)
        non_empty = [
            p
            for p in accepted
            if p["summary"] or p["facts"] or p["findings"] or p["skipped_pdfs"] or p["failed_fetches"]
        ]
        truncated_phases = 0
        if not non_empty and accepted:
            non_empty = [accepted[0]]
            truncated_phases = max(0, len(accepted) - 1)
        elif non_empty:
            truncated_phases = max(0, len(phases) - len(non_empty))

        # Final safety: if still over, shrink non_empty further.
        while non_empty and estimate_tokens(non_empty) > max_evidence_tokens and len(non_empty) > 1:
            non_empty.pop()
            truncated_phases += 1

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

    async def _write_temp(self, payload: list[dict[str, Any]]) -> None:
        await self._atomic_write(self.temp_path, payload)

    def _read_checkpoint(self) -> dict[str, Any]:
        if not self.checkpoint_path.exists():
            return RunCheckpoint().to_dict()
        try:
            val = json.loads(self.checkpoint_path.read_text(encoding="utf-8"))
            return RunCheckpoint.from_dict(val if isinstance(val, dict) else {}).to_dict()
        except Exception as e:
            logger.warning("Failed to read checkpoint.json: %s", e)
            return RunCheckpoint().to_dict()

    async def _write_checkpoint(self, payload: dict[str, Any]) -> None:
        await self._atomic_write(self.checkpoint_path, payload)

    async def _atomic_write(self, path: Path, payload: Any) -> None:
        async with self._lock:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                temp_file = path.with_suffix(path.suffix + ".tmp")
                temp_file.write_text(
                    json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8"
                )
                temp_file.replace(path)
            except Exception as e:
                logger.error("Failed to write %s: %s", path, e)
                raise
