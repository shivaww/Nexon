"""Dependency-free smoke test matching the bridge's script-based test style."""

from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path
import sys

BRIDGE_DIR = Path(__file__).resolve().parents[2]
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from deep_research.orchestrator import DeepResearchOrchestrator


class FakeEmbedder:
    async def embed_texts(self, texts: list[str]) -> list[list[float]]:
        return [[float(len(text) % 11 + 1), float(sum(map(ord, text)) % 17 + 1), 1.0] for text in texts]


async def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        research = DeepResearchOrchestrator(directory, embedder=FakeEmbedder())
        text = "Alpha research is useful. " * 260 + "Beta evidence is independent. " * 260
        ingested = await research.ingest("stage1", "query1", "https://example.test/a", text)
        assert ingested["new_chunks_added"] >= 2
        retrieved = await research.retrieve("stage1", "What is the alpha evidence?")
        assert retrieved["chunks_written"] >= 1
        assert (Path(directory) / "temp.json").is_file()
        print("deep_research smoke test passed")


if __name__ == "__main__":
    asyncio.run(main())
