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
        self._lock = asyncio.Lock()
        self._rebuild_ingested_cache()

    # ── Run lifecycle ─────────────────────────────────────────────────

    async def reset_run(self, keep_checkpoint: bool = False) -> dict[str, str]:
        """Clear temp.json and in-memory caches for a new research run."""
        async with self._lock:
            self.run_ingested_urls.clear()
            self._atomic_write_unlocked(self.temp_path, [])
            if not keep_checkpoint:
                self._atomic_write_unlocked(
                    self.checkpoint_path, RunCheckpoint().to_dict()
                )
        logger.info("Deep Research run reset (keep_checkpoint=%s).", keep_checkpoint)
        return {"status": "ok"}

    @classmethod
    def _fact_dedup_key(cls, fact: dict[str, Any]) -> tuple[str, str, str, str]:
        norm = cls._normalize_url(str(fact.get("source") or ""))
        metric = str(fact.get("metric") or "").strip().lower()
        subject = str(fact.get("subject") or "").strip().lower()
        value = str(fact.get("value") or "").strip().lower()
        return (norm, metric, subject, value)

    @classmethod
    def _finding_dedup_key(cls, finding: dict[str, Any]) -> tuple[str, str]:
        norm = cls._normalize_url(str(finding.get("source") or ""))
        text = " ".join(str(finding.get("text") or "").strip().lower().split())
        return (norm, text)

    @classmethod
    def _dedup_url_items(
        cls, existing: list[dict[str, Any]], incoming: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        seen: set[str] = set()
        merged: list[dict[str, Any]] = []
        for item in list(existing) + list(incoming):
            if not isinstance(item, dict):
                continue
            url = str(item.get("url") or "")
            key = cls._normalize_url(url) or url.strip().lower()
            if key and key in seen:
                continue
            if key:
                seen.add(key)
            merged.append(item)
        return merged

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
        """Update or insert a phase record in temp.json atomically."""
        async with self._lock:
            payload = self._read_temp()

            phase_idx = -1
            for idx, phase in enumerate(payload):
                if phase.get("stage_id") == stage_id:
                    phase_idx = idx
                    break

            existing = payload[phase_idx] if phase_idx != -1 else {}
            existing_facts = [
                f for f in (existing.get("facts") or []) if isinstance(f, dict)
            ]
            existing_findings = [
                f for f in (existing.get("findings") or []) if isinstance(f, dict)
            ]

            # Deduplicate facts and findings independently by content+source
            # (never sharing a bare-URL set across facts and findings), and
            # deduplicate against existing records so cumulative calls never duplicate.
            seen_facts: set[tuple[str, str, str, str]] = set()
            merged_facts: list[dict[str, Any]] = []
            for fact in existing_facts + [
                f for f in (facts or []) if isinstance(f, dict)
            ]:
                key = self._fact_dedup_key(fact)
                if key in seen_facts:
                    continue
                seen_facts.add(key)
                norm = self._normalize_url(str(fact.get("source") or ""))
                if norm:
                    self.run_ingested_urls.add(norm)
                merged_facts.append(fact)

            seen_findings: set[tuple[str, str]] = set()
            merged_findings: list[dict[str, Any]] = []
            for finding in existing_findings + [
                f for f in (findings or []) if isinstance(f, dict)
            ]:
                key = self._finding_dedup_key(finding)
                if key in seen_findings:
                    continue
                seen_findings.add(key)
                norm = self._normalize_url(str(finding.get("source") or ""))
                if norm:
                    self.run_ingested_urls.add(norm)
                merged_findings.append(finding)

            merged_facts = self._cap_evidence(merged_facts, 30)
            merged_findings = self._cap_evidence(merged_findings, 30)
            merged_skipped_pdfs = self._dedup_url_items(
                existing.get("skipped_pdfs") or [], skipped_pdfs or []
            )
            merged_failed_fetches = self._dedup_url_items(
                existing.get("failed_fetches") or [], failed_fetches or []
            )

            new_phase = {
                "stage_id": stage_id,
                "phase_title": phase_title or existing.get("phase_title") or "",
                "summary": summary or existing.get("summary") or "",
                "facts": merged_facts,
                "findings": merged_findings,
                "skipped_pdfs": merged_skipped_pdfs,
                "failed_fetches": merged_failed_fetches,
                "status": status or existing.get("status") or "running",
            }

            if phase_idx != -1:
                payload[phase_idx] = new_phase
            else:
                payload.append(new_phase)

            self._atomic_write_unlocked(self.temp_path, payload)
        logger.info("Updated phase record for %s in temp.json.", stage_id)
        return {"status": "ok"}

    def _rebuild_ingested_cache(self) -> None:
        """Rebuild run_ingested_urls from temp.json so dedup survives restarts."""
        try:
            for phase in self._read_temp():
                for fact in phase.get("facts") or []:
                    norm = self._normalize_url(str(fact.get("source") or ""))
                    if norm:
                        self.run_ingested_urls.add(norm)
                for finding in phase.get("findings") or []:
                    norm = self._normalize_url(str(finding.get("source") or ""))
                    if norm:
                        self.run_ingested_urls.add(norm)
        except Exception as e:
            logger.warning("Failed to rebuild ingested cache: %s", e)

    @staticmethod
    def _cap_evidence(items: list, cap: int) -> list:
        """Keep the highest-confidence items, drop the rest above cap."""
        if len(items) <= cap:
            return items
        order = {"high": 0, "medium": 1, "low": 2}
        return sorted(items, key=lambda x: order.get(str(x.get("confidence", "")).lower(), 3))[:cap]

    @staticmethod
    def _normalize_url(url: str) -> str:
        """Normalize a URL for dedup: strip scheme, www, trailing slash, query, and fragment."""
        if not url:
            return ""

        from urllib.parse import urlparse

        try:
            raw = url.strip()
            parsed = urlparse(raw)
            if not parsed.netloc:
                parsed = urlparse("http://" + raw)
            host = (parsed.hostname or "").lower()
            if not host:
                path_like = raw.lower().split("?", 1)[0].split("#", 1)[0].rstrip("/")
                return path_like.removeprefix("www.").removeprefix("http://").removeprefix("https://")
            host = host.removeprefix("www.")
            path = (parsed.path or "").rstrip("/").lower()
            return f"{host}{path}"
        except Exception:
            return ""

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

        def chars_to_tokens(char_count: int) -> int:
            return max(1, (char_count + 3) // 4) if char_count > 0 else 0

        def serialized_len(obj: Any) -> int:
            return len(json.dumps(obj, ensure_ascii=True, indent=2))

        def record_delta_chars(record: dict[str, Any]) -> int:
            # Indent-2 serialized record nested 3 levels deep inside a phase list.
            dumped = json.dumps(record, ensure_ascii=True, indent=2)
            line_count = dumped.count("\n") + 1
            return len(dumped) + (line_count * 6) + 2

        # Start with metadata + primary records (facts if prefer_facts, else findings)
        accepted: list[dict[str, Any]] = []
        used_chars = 2  # "[]"
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
            used_chars += serialized_len(base) + 4

            # Add primary records greedily using incremental char accounting.
            kept_primary: list[dict] = []
            for record in phase[primary_key]:
                delta = record_delta_chars(record)
                if chars_to_tokens(used_chars + delta) > max_evidence_tokens:
                    if prefer_facts:
                        truncated_facts += 1
                    else:
                        truncated_findings += 1
                    continue
                kept_primary.append(record)
                used_chars += delta
            base[primary_key] = kept_primary

        # Round-robin secondary records across phases using incremental char accounting.
        max_rounds = max((len(p[secondary_key]) for p in working), default=0)
        for round_i in range(max_rounds):
            for p_idx, phase in enumerate(working):
                if round_i >= len(phase[secondary_key]):
                    continue
                record = phase[secondary_key][round_i]
                delta = record_delta_chars(record)
                if chars_to_tokens(used_chars + delta) > max_evidence_tokens:
                    if prefer_facts:
                        truncated_findings += 1
                    else:
                        truncated_facts += 1
                    continue
                accepted[p_idx][secondary_key].append(record)
                used_chars += delta

        # Verify against exact indent=2 serialization and trim if still over budget.
        used_chars = serialized_len(accepted)
        if chars_to_tokens(used_chars) > max_evidence_tokens:
            while chars_to_tokens(used_chars) > max_evidence_tokens:
                dropped_any = False
                for p in reversed(accepted):
                    facts_list = p.get("facts") or []
                    if facts_list:
                        popped = facts_list.pop()
                        truncated_facts += 1
                        dropped_any = True
                        used_chars = max(0, used_chars - record_delta_chars(popped))
                        if chars_to_tokens(used_chars) <= max_evidence_tokens:
                            break
                if not dropped_any:
                    for p in reversed(accepted):
                        findings_list = p.get("findings") or []
                        if findings_list:
                            popped = findings_list.pop()
                            truncated_findings += 1
                            dropped_any = True
                            used_chars = max(0, used_chars - record_delta_chars(popped))
                            if chars_to_tokens(used_chars) <= max_evidence_tokens:
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

        # Final safety against exact indent=2 output.
        content = json.dumps(non_empty, ensure_ascii=True, indent=2)
        while non_empty and chars_to_tokens(len(content)) > max_evidence_tokens and len(non_empty) > 1:
            non_empty.pop()
            truncated_phases += 1
            content = json.dumps(non_empty, ensure_ascii=True, indent=2)

        return {
            "content": content,
            "token_estimate": chars_to_tokens(len(content)),
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

    def _atomic_write_unlocked(self, path: Path, payload: Any) -> None:
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

    async def _atomic_write(self, path: Path, payload: Any) -> None:
        async with self._lock:
            self._atomic_write_unlocked(path, payload)
