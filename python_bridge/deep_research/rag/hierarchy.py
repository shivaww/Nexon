"""Build Tier 0 leaves, Tier 1 source summaries, and Tier 2 stage summaries."""

from __future__ import annotations

import math
import re

from ..schemas import IndexNode, IngestResult
from .store import ResearchStore


def cosine(left: list[float], right: list[float]) -> float:
    numerator = sum(a * b for a, b in zip(left, right))
    denominator = math.sqrt(sum(a * a for a in left)) * math.sqrt(sum(b * b for b in right))
    return numerator / denominator if denominator else 0.0


class HierarchyBuilder:
    CHUNK_WORDS = 320
    OVERLAP_WORDS = 50
    DUPLICATE_THRESHOLD = 0.95

    def __init__(self, store: ResearchStore, embedder: object) -> None:
        self.store = store
        self.embedder = embedder

    @classmethod
    def chunk_text(cls, text: str) -> list[str]:
        words = re.findall(r"\S+", text)
        if not words:
            return []
        chunks: list[str] = []
        start = 0
        while start < len(words):
            chunks.append(" ".join(words[start:start + cls.CHUNK_WORDS]))
            if start + cls.CHUNK_WORDS >= len(words):
                break
            start += cls.CHUNK_WORDS - cls.OVERLAP_WORDS
        return chunks

    @staticmethod
    def _summary(parts: list[str], limit: int = 1800) -> str:
        """Deterministic extractive summary; generation remains outside the indexer."""
        text = " ".join(parts)
        sentences = re.split(r"(?<=[.!?])\s+", text)
        selected: list[str] = []
        length = 0
        for sentence in sentences:
            if not sentence:
                continue
            selected.append(sentence)
            length += len(sentence) + 1
            if length >= limit:
                break
        return " ".join(selected)[:limit] or text[:limit]

    async def ingest(self, stage_id: str, query_id: str, source_url: str, text: str) -> IngestResult:
        candidates = self.chunk_text(text)
        if not candidates:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))
        vectors = await self.embedder.embed_texts(candidates)
        existing = self.store.nodes(stage_id, 0)
        novel = [
            (chunk, vector) for chunk, vector in zip(candidates, vectors)
            if not existing or max(cosine(vector, node.embedding) for node in existing) < self.DUPLICATE_THRESHOLD
        ]
        self.store.replace_source(stage_id, source_url)
        leaves = [
            IndexNode(None, stage_id, source_url, query_id, 0, chunk, vector, {"chunk_index": index})
            for index, (chunk, vector) in enumerate(novel)
        ]
        if leaves:
            self.store.add_nodes(leaves)
            source_summary = self._summary([chunk for chunk, _ in novel])
            source_vector = (await self.embedder.embed_texts([source_summary]))[0]
            self.store.add_nodes([IndexNode(None, stage_id, source_url, query_id, 1, source_summary, source_vector, {})])
        await self._refresh_stage_summary(stage_id, query_id)
        return IngestResult(len(leaves), len(novel) / len(candidates), self.store.leaf_count(stage_id))

    async def _refresh_stage_summary(self, stage_id: str, query_id: str) -> None:
        source_nodes = self.store.nodes(stage_id, 1)
        self.store.replace_stage_summary(stage_id)
        if not source_nodes:
            return
        summary = self._summary([node.content for node in source_nodes], limit=2500)
        vector = (await self.embedder.embed_texts([summary]))[0]
        self.store.add_nodes([IndexNode(None, stage_id, None, query_id, 2, summary, vector, {"source_count": len(source_nodes)})])
