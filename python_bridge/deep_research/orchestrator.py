"""Orchestrator for 3-agent Deep Research storing structured FACT/FINDING records.

No embedding model, no vector search, no SQLite tables.
"""

from __future__ import annotations

import json
import logging
import os
import hashlib
from pathlib import Path
from typing import Any

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
        self.run_ingested_urls: set[str] = set()

    def reset_run(self) -> dict[str, str]:
        """Clear temp.json and in-memory caches for a new research run."""
        self.run_ingested_urls.clear()
        self._write_temp([])
        logger.info("Deep Research run reset.")
        return {"status": "ok"}

    def update_phase(
        self,
        stage_id: str,
        phase_title: str,
        facts: list[dict[str, str]],
        findings: list[dict[str, str]],
        skipped_pdfs: list[dict[str, str]],
        failed_fetches: list[dict[str, str]],
    ) -> dict[str, str]:
        """Update or insert a phase record in temp.json."""
        payload = self._read_temp()

        # Look for existing phase record
        phase_idx = -1
        for idx, phase in enumerate(payload):
            if phase.get("stage_id") == stage_id:
                phase_idx = idx
                break

        new_phase = {
            "stage_id": stage_id,
            "phase_title": phase_title,
            "facts": facts,
            "findings": findings,
            "skipped_pdfs": skipped_pdfs,
            "failed_fetches": failed_fetches,
        }

        if phase_idx != -1:
            payload[phase_idx] = new_phase
        else:
            payload.append(new_phase)

        self._write_temp(payload)
        logger.info(f"Updated phase record for {stage_id} in temp.json.")
        return {"status": "ok"}

    def export_temp(self) -> str:
        """Return the raw JSON content of temp.json."""
        if not self.temp_path.exists():
            return "[]"
        try:
            return self.temp_path.read_text(encoding="utf-8")
        except Exception as e:
            logger.error(f"Failed to read temp.json: {e}")
            return "[]"



    def _read_temp(self) -> list[dict[str, Any]]:
        if not self.temp_path.exists():
            return []
        try:
            val = json.loads(self.temp_path.read_text(encoding="utf-8"))
            return val if isinstance(val, list) else []
        except Exception as e:
            logger.warning(f"Failed to read temp.json: {e}")
            return []

    def _write_temp(self, payload: list[dict[str, Any]]) -> None:
        try:
            temp_file = self.temp_path.with_suffix(".json.tmp")
            temp_file.write_text(
                json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8"
            )
            temp_file.replace(self.temp_path)
        except Exception as e:
            logger.error(f"Failed to write temp.json: {e}")
