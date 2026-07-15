"""SQLite persistence for short-lived deep-research sessions."""

from __future__ import annotations

from array import array
import json
from pathlib import Path
import sqlite3
from typing import Iterable

from ..schemas import IndexNode


class ResearchStore:
    """Small SQLite store; vector ranking intentionally remains in Python."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path).expanduser()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS research_nodes (
                id INTEGER PRIMARY KEY,
                stage_id TEXT NOT NULL,
                source_url TEXT,
                query_id TEXT,
                tier INTEGER NOT NULL CHECK(tier IN (0, 1, 2)),
                content TEXT NOT NULL,
                embedding BLOB NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}'
            )
            """
        )
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_research_nodes_scope "
            "ON research_nodes(stage_id, tier, source_url)"
        )
        self.connection.commit()

    @staticmethod
    def _encode_vector(vector: list[float]) -> bytes:
        return array("f", vector).tobytes()

    @staticmethod
    def _decode_vector(value: bytes) -> list[float]:
        vector = array("f")
        vector.frombytes(value)
        return vector.tolist()

    def replace_source(self, stage_id: str, source_url: str) -> None:
        """Remove a source's old leaf and page nodes before re-indexing it."""
        self.connection.execute(
            "DELETE FROM research_nodes WHERE stage_id = ? AND source_url = ? AND tier IN (0, 1)",
            (stage_id, source_url),
        )
        self.connection.commit()

    def replace_stage_summary(self, stage_id: str) -> None:
        self.connection.execute(
            "DELETE FROM research_nodes WHERE stage_id = ? AND tier = 2", (stage_id,)
        )
        self.connection.commit()

    def add_nodes(self, nodes: Iterable[IndexNode]) -> None:
        rows = [
            (
                node.stage_id,
                node.source_url,
                node.query_id,
                node.tier,
                node.content,
                self._encode_vector(node.embedding),
                json.dumps(node.metadata, separators=(",", ":")),
            )
            for node in nodes
        ]
        self.connection.executemany(
            """INSERT INTO research_nodes
               (stage_id, source_url, query_id, tier, content, embedding, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            rows,
        )
        self.connection.commit()

    def nodes(self, stage_id: str, tier: int, source_urls: list[str] | None = None) -> list[IndexNode]:
        query = (
            "SELECT id, stage_id, source_url, query_id, tier, content, embedding, metadata "
            "FROM research_nodes WHERE stage_id = ? AND tier = ?"
        )
        values: list[object] = [stage_id, tier]
        if source_urls is not None:
            if not source_urls:
                return []
            query += " AND source_url IN (" + ",".join("?" for _ in source_urls) + ")"
            values.extend(source_urls)
        rows = self.connection.execute(query, values).fetchall()
        return [
            IndexNode(
                id=row[0], stage_id=row[1], source_url=row[2], query_id=row[3], tier=row[4],
                content=row[5], embedding=self._decode_vector(row[6]), metadata=json.loads(row[7]),
            )
            for row in rows
        ]

    def leaf_count(self, stage_id: str) -> int:
        return int(self.connection.execute(
            "SELECT COUNT(*) FROM research_nodes WHERE stage_id = ? AND tier = 0", (stage_id,)
        ).fetchone()[0])

    def close(self) -> None:
        self.connection.close()
