"""SQLite persistence for Hierarchical RAG deep-research sessions.

Acts as the lightweight local metadata and vector store.
Defines a three-tier schema (documents, sections, chunks) with cascade deletes
and appropriate indices for fast hierarchical narrowing.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sqlite3
from typing import Iterable, Any

import numpy as np

from ..schemas import DocumentNode, SectionNode, ChunkNode

# Embeddings are persisted as a plain SQLite BLOB holding a contiguous
# float32 (little-endian) buffer.  The dtype is fixed (float32) and the
# dimension is recovered from the BLOB length (len // 4), so no extra
# columns are required for safe deserialization.  This layout is byte-for-
# byte compatible with the previous ``array('f')`` serialization, which
# means databases written before this change keep loading without any
# migration step.
EMBEDDING_DTYPE = np.float32


def normalize_stage_id(stage_id: str) -> str:
    """Keep numbered research stages in one SQLite namespace.

    Historical callers used both ``stage1`` and ``stage_1``.  Only numbered
    stage identifiers are rewritten; named stages such as ``stage_live`` are
    preserved verbatim apart from surrounding whitespace.
    """
    normalized = stage_id.strip()
    match = re.fullmatch(r"stage[_\-\s]*(\d+)", normalized, re.IGNORECASE)
    return f"stage{int(match.group(1))}" if match else normalized


def stage_id_variants(stage_id: str) -> tuple[str, ...]:
    """Return the canonical stage key plus legacy numbered spellings.

    Existing databases may already contain ``stage_1`` records.  Reading both
    forms keeps that evidence available until it is naturally replaced by a
    subsequent ingestion under the canonical ``stage1`` key.
    """
    canonical = normalize_stage_id(stage_id)
    match = re.fullmatch(r"stage(\d+)", canonical, re.IGNORECASE)
    if not match:
        return (canonical,)
    number = str(int(match.group(1)))
    return (canonical, f"stage_{number}", f"stage-{number}")


class ResearchStore:
    """SQLite metadata and vector store optimized for Hierarchical RAG on Termux."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path).expanduser()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA foreign_keys = ON")

        # 1. Document Level Table
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS documents (
                stage_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                content TEXT NOT NULL,
                embedding BLOB NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                PRIMARY KEY (stage_id, source_url)
            )
            """
        )

        # 2. Section Level Table
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS sections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stage_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                section_index INTEGER NOT NULL,
                title TEXT,
                content TEXT NOT NULL,
                embedding BLOB NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY (stage_id, source_url) REFERENCES documents(stage_id, source_url) ON DELETE CASCADE
            )
            """
        )

        # 3. Chunk Level Table
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stage_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                section_id INTEGER NOT NULL,
                chunk_index INTEGER NOT NULL,
                content TEXT NOT NULL,
                embedding BLOB NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY (section_id) REFERENCES sections(id) ON DELETE CASCADE
            )
            """
        )

        # Indexes for fast lookup and cascade delete performance
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_documents_stage ON documents(stage_id)"
        )
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_sections_stage_source ON sections(stage_id, source_url)"
        )
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_chunks_stage_section ON chunks(stage_id, section_id)"
        )
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_chunks_stage_source ON chunks(stage_id, source_url)"
        )

        # 4. Embedding Cache Table (survives across runs)
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS embedding_cache (
                content_hash TEXT NOT NULL,
                model_name TEXT NOT NULL,
                text_length INTEGER NOT NULL,
                embedding BLOB NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                PRIMARY KEY (content_hash, model_name)
            )
            """
        )
        self.connection.commit()

    @staticmethod
    def _encode_vector(vector: list[float]) -> bytes:
        return np.asarray(vector, dtype=EMBEDDING_DTYPE).tobytes()

    @staticmethod
    def _decode_vector(value: bytes) -> list[float]:
        return np.frombuffer(value, dtype=EMBEDDING_DTYPE).tolist()

    @staticmethod
    def _stage_predicate(stage_id: str) -> tuple[str, tuple[str, ...]]:
        variants = stage_id_variants(stage_id)
        return ",".join("?" for _ in variants), variants

    def get_cached_embedding(self, content_hash: str, model_name: str) -> list[float] | None:
        """Retrieve a cached embedding by SHA-256 hash and model name."""
        row = self.connection.execute(
            "SELECT embedding FROM embedding_cache WHERE content_hash = ? AND model_name = ?",
            (content_hash, model_name),
        ).fetchone()
        if row is not None:
            return self._decode_vector(row[0])
        return None

    def save_cached_embedding(
        self,
        content_hash: str,
        model_name: str,
        text_length: int,
        embedding: list[float],
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Save a generated embedding vector into the persistent SQLite cache."""
        self.connection.execute(
            """
            INSERT OR REPLACE INTO embedding_cache (content_hash, model_name, text_length, embedding, metadata)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                content_hash,
                model_name,
                text_length,
                self._encode_vector(embedding),
                json.dumps(metadata or {}, separators=(",", ":")),
            ),
        )
        self.connection.commit()

    def replace_source(self, stage_id: str, source_url: str) -> None:
        """Remove a source's old document, sections, and chunks (via Cascade Delete)."""
        placeholders, stage_ids = self._stage_predicate(stage_id)
        self.connection.execute(
            f"DELETE FROM documents WHERE stage_id IN ({placeholders}) AND source_url = ?",
            (*stage_ids, source_url),
        )
        self.connection.commit()

    def replace_stage_summary(self, stage_id: str) -> None:
        """Compatibility stub."""
        pass

    def add_document(
        self,
        stage_id: str,
        source_url: str,
        content: str,
        embedding: list[float],
        metadata: dict[str, Any] | None = None,
    ) -> None:
        stage_id = normalize_stage_id(stage_id)
        self.connection.execute(
            """
            INSERT OR REPLACE INTO documents (stage_id, source_url, content, embedding, metadata)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                stage_id,
                source_url,
                content,
                self._encode_vector(embedding),
                json.dumps(metadata or {}, separators=(",", ":")),
            ),
        )
        self.connection.commit()

    def add_section(
        self,
        stage_id: str,
        source_url: str,
        section_index: int,
        title: str | None,
        content: str,
        embedding: list[float],
        metadata: dict[str, Any] | None = None,
    ) -> int:
        stage_id = normalize_stage_id(stage_id)
        cursor = self.connection.execute(
            """
            INSERT INTO sections (stage_id, source_url, section_index, title, content, embedding, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                stage_id,
                source_url,
                section_index,
                title,
                content,
                self._encode_vector(embedding),
                json.dumps(metadata or {}, separators=(",", ":")),
            ),
        )
        self.connection.commit()
        return int(cursor.lastrowid)

    def add_chunk(
        self,
        stage_id: str,
        source_url: str,
        section_id: int,
        chunk_index: int,
        content: str,
        embedding: list[float],
        metadata: dict[str, Any] | None = None,
    ) -> int:
        stage_id = normalize_stage_id(stage_id)
        cursor = self.connection.execute(
            """
            INSERT INTO chunks (stage_id, source_url, section_id, chunk_index, content, embedding, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                stage_id,
                source_url,
                section_id,
                chunk_index,
                content,
                self._encode_vector(embedding),
                json.dumps(metadata or {}, separators=(",", ":")),
            ),
        )
        self.connection.commit()
        return int(cursor.lastrowid)

    def all_documents(self, stage_id: str) -> list[DocumentNode]:
        canonical_stage_id = normalize_stage_id(stage_id)
        placeholders, stage_ids = self._stage_predicate(stage_id)
        rows = self.connection.execute(
            f"SELECT source_url, content, embedding, metadata FROM documents "
            f"WHERE stage_id IN ({placeholders})",
            stage_ids,
        ).fetchall()
        return [
            DocumentNode(
                stage_id=canonical_stage_id,
                source_url=row[0],
                content=row[1],
                embedding=self._decode_vector(row[2]),
                metadata=json.loads(row[3]),
            )
            for row in rows
        ]

    def sections_for_document(self, stage_id: str, source_url: str) -> list[SectionNode]:
        canonical_stage_id = normalize_stage_id(stage_id)
        placeholders, stage_ids = self._stage_predicate(stage_id)
        rows = self.connection.execute(
            "SELECT id, section_index, title, content, embedding, metadata "
            f"FROM sections WHERE stage_id IN ({placeholders}) AND source_url = ?",
            (*stage_ids, source_url),
        ).fetchall()
        return [
            SectionNode(
                id=row[0],
                stage_id=canonical_stage_id,
                source_url=source_url,
                section_index=row[1],
                title=row[2],
                content=row[3],
                embedding=self._decode_vector(row[4]),
                metadata=json.loads(row[5]),
            )
            for row in rows
        ]

    def chunks_for_section(self, stage_id: str, section_id: int) -> list[ChunkNode]:
        canonical_stage_id = normalize_stage_id(stage_id)
        placeholders, stage_ids = self._stage_predicate(stage_id)
        rows = self.connection.execute(
            "SELECT id, source_url, chunk_index, content, embedding, metadata "
            f"FROM chunks WHERE stage_id IN ({placeholders}) AND section_id = ?",
            (*stage_ids, section_id),
        ).fetchall()
        return [
            ChunkNode(
                id=row[0],
                stage_id=canonical_stage_id,
                source_url=row[1],
                section_id=section_id,
                chunk_index=row[2],
                content=row[3],
                embedding=self._decode_vector(row[4]),
                metadata=json.loads(row[5]),
            )
            for row in rows
        ]

    def all_sections(self, stage_id: str) -> list[SectionNode]:
        canonical_stage_id = normalize_stage_id(stage_id)
        placeholders, stage_ids = self._stage_predicate(stage_id)
        rows = self.connection.execute(
            "SELECT id, source_url, section_index, title, content, embedding, metadata "
            f"FROM sections WHERE stage_id IN ({placeholders})",
            stage_ids,
        ).fetchall()
        return [
            SectionNode(
                id=row[0],
                stage_id=canonical_stage_id,
                source_url=row[1],
                section_index=row[2],
                title=row[3],
                content=row[4],
                embedding=self._decode_vector(row[5]),
                metadata=json.loads(row[6]),
            )
            for row in rows
        ]

    def all_chunks(self, stage_id: str) -> list[ChunkNode]:
        canonical_stage_id = normalize_stage_id(stage_id)
        placeholders, stage_ids = self._stage_predicate(stage_id)
        rows = self.connection.execute(
            "SELECT id, source_url, section_id, chunk_index, content, embedding, metadata "
            f"FROM chunks WHERE stage_id IN ({placeholders})",
            stage_ids,
        ).fetchall()
        return [
            ChunkNode(
                id=row[0],
                stage_id=canonical_stage_id,
                source_url=row[1],
                section_id=row[2],
                chunk_index=row[3],
                content=row[4],
                embedding=self._decode_vector(row[5]),
                metadata=json.loads(row[6]),
            )
            for row in rows
        ]

    def leaf_count(self, stage_id: str) -> int:
        placeholders, stage_ids = self._stage_predicate(stage_id)
        return int(
            self.connection.execute(
                f"SELECT COUNT(*) FROM chunks WHERE stage_id IN ({placeholders})", stage_ids
            ).fetchone()[0]
        )

    # ── Compatibility methods ─────────────────────────────────────────

    def chunk_rows(self, stage_id: str) -> list[tuple[int, str, str | None, list[float]]]:
        """All leaf chunks with ids, content, source url and embedding for legacy vector ranking."""
        placeholders, stage_ids = self._stage_predicate(stage_id)
        rows = self.connection.execute(
            f"SELECT id, content, source_url, embedding FROM chunks "
            f"WHERE stage_id IN ({placeholders})",
            stage_ids,
        ).fetchall()
        return [
            (row[0], row[1], row[2], self._decode_vector(row[3])) for row in rows
        ]

    def chunks_by_ids(self, stage_id: str, ids: list[int]) -> list[tuple[str, str | None]]:
        if not ids:
            return []
        stage_placeholders, stage_ids = self._stage_predicate(stage_id)
        id_placeholders = ",".join("?" for _ in ids)
        rows = self.connection.execute(
            f"SELECT content, source_url FROM chunks "
            f"WHERE stage_id IN ({stage_placeholders}) AND id IN ({id_placeholders})",
            (*stage_ids, *ids),
        ).fetchall()
        return [(row[0], row[1]) for row in rows]

    def graph_stats(self, stage_id: str) -> dict[str, int]:
        """Compatibility/legacy graph stats stub."""
        return {"entities": 0, "relations": 0}

    def close(self) -> None:
        self.connection.close()
