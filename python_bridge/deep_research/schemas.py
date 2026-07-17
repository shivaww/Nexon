"""Data shapes shared by the deep-research pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class IndexNode:
    """A persisted node in the three-tier retrieval hierarchy (legacy/compatibility)."""

    id: int | None
    stage_id: str
    source_url: str | None
    query_id: str | None
    tier: int
    content: str
    embedding: list[float]
    metadata: dict[str, Any]


@dataclass(frozen=True)
class DocumentNode:
    """Represents a document/source in the Hierarchical RAG."""

    stage_id: str
    source_url: str
    content: str
    embedding: list[float]
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class SectionNode:
    """Represents a section or subsection within a document."""

    id: int | None
    stage_id: str
    source_url: str
    section_index: int
    title: str | None
    content: str
    embedding: list[float]
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class ChunkNode:
    """Represents a leaf chunk belonging to a section."""

    id: int | None
    stage_id: str
    source_url: str
    section_id: int
    chunk_index: int
    content: str
    embedding: list[float]
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class IngestResult:
    new_chunks_added: int
    novelty_ratio: float
    total_chunks_stage: int

    def to_dict(self) -> dict[str, int | float]:
        return {
            "new_chunks_added": self.new_chunks_added,
            "novelty_ratio": self.novelty_ratio,
            "total_chunks_stage": self.total_chunks_stage,
        }


@dataclass(frozen=True)
class RetrieveResult:
    chunks_written: int
    avg_score: float

    def to_dict(self) -> dict[str, int | float]:
        return {"chunks_written": self.chunks_written, "avg_score": self.avg_score}
