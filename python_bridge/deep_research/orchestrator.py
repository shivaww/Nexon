"""Bridge entrypoints for hierarchical deep-research ingestion and retrieval."""

from __future__ import annotations

import asyncio
import json
import logging
import os
from pathlib import Path

from .rag import HierarchicalRetriever, HierarchyBuilder, LlamaCppEmbedder, ResearchStore
from .schemas import IngestResult, RetrieveResult

logger = logging.getLogger("termux_forge.deep_research")


class DeepResearchOrchestrator:
    def __init__(self, data_dir: str | Path | None = None, embedder: object | None = None) -> None:
        self.data_dir = Path(data_dir or os.getenv("DEEP_RESEARCH_DIR", "~/.termux_forge/deep_research")).expanduser()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.store = ResearchStore(self.data_dir / "research.sqlite3")
        self.embedder = embedder or LlamaCppEmbedder()
        self.hierarchy = HierarchyBuilder(self.store, self.embedder)
        self.retriever = HierarchicalRetriever(self.store, self.embedder)
        self._lock = asyncio.Lock()

    @property
    def temp_path(self) -> Path:
        return Path(os.getenv("DEEP_RESEARCH_TEMP_PATH", self.data_dir / "temp.json")).expanduser()

    async def ingest(self, stage_id: str, query_id: str, source_url: str, text: str) -> dict[str, int | float]:
        if not all(isinstance(value, str) and value.strip() for value in (stage_id, query_id, source_url, text)):
            raise ValueError("stage_id, query_id, source_url, and text are required")
        async with self._lock:
            result: IngestResult = await self.hierarchy.ingest(stage_id, query_id, source_url, text)
        logger.info("Ingested deep-research source stage=%s added=%d", stage_id, result.new_chunks_added)
        return result.to_dict()

    async def retrieve(self, stage_id: str, query: str) -> dict[str, int | float]:
        if not stage_id.strip() or not query.strip():
            raise ValueError("stage_id and query are required")
        async with self._lock:
            ranked = await self.retriever.retrieve(stage_id, query)
            payload = self._read_temp()
            stage = payload.setdefault(stage_id, {})
            stage[query] = {f"chunk{index}": text for index, (text, _) in enumerate(ranked, 1)}
            self._write_temp(payload)
        average = sum(score for _, score in ranked) / len(ranked) if ranked else 0.0
        result = RetrieveResult(len(ranked), average)
        logger.info("Retrieved deep-research chunks stage=%s count=%d", stage_id, result.chunks_written)
        return result.to_dict()

    def _read_temp(self) -> dict[str, dict[str, dict[str, str]]]:
        if not self.temp_path.exists():
            return {}
        try:
            value = json.loads(self.temp_path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, json.JSONDecodeError) as exc:
            logger.warning("Ignoring unreadable deep-research temp file: %s", exc)
            return {}

    def _write_temp(self, payload: dict[str, object]) -> None:
        temporary = self.temp_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
        temporary.replace(self.temp_path)
