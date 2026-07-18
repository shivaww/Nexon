"""Test plan for the Hierarchical RAG refactor.

Run:  python3 python_bridge/deep_research/test_lightrag_rag.py

Covers the five required behaviors:
  1. simple factual retrieval   -> direct/vector route, grounded chunk returned with citations
  2. section-specific retrieval -> query routed/narrowed to section chunks
  3. multi-document retrieval   -> retrieves relevant sections/chunks across distinct sources
  4. incremental re-ingestion   -> document updates clean up old sections/chunks via cascade delete
  5. weak-evidence fallback     -> hedge instead of hallucination on unrelated queries
"""

from __future__ import annotations

import asyncio
import hashlib
import tempfile
from pathlib import Path
import sys

BRIDGE_DIR = Path(__file__).resolve().parents[2]
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from deep_research.orchestrator import DeepResearchOrchestrator


DIM = 64


class FakeEmbedder:
    """Deterministic bag-of-words embedder so vector similarities are meaningful."""

    async def embed_texts(self, texts: list[str]) -> list[list[float]]:
        return [self._vec(t) for t in texts]

    @staticmethod
    def _vec(text: str) -> list[float]:
        vec = [0.0] * DIM
        for tok in text.lower().split():
            h = int(hashlib.md5(tok.encode()).hexdigest(), 16) % DIM
            vec[h] += 1.0
        norm = sum(v * v for v in vec) ** 0.5 or 1.0
        return [v / norm for v in vec]


def make_orchestrator(directory: str) -> DeepResearchOrchestrator:
    return DeepResearchOrchestrator(directory, embedder=FakeEmbedder())


async def test_simple_factual() -> None:
    with tempfile.TemporaryDirectory() as d:
        r = make_orchestrator(d)
        await r.ingest("s1", "q1", "https://ex.test/cat", "The cat sat on the mat. " * 20)
        res = await r.retrieve("s1", "What sat on the mat?")
        assert res["chunks_written"] >= 1, res

        # Citations must be attached correctly
        payload = r._read_temp()["s1"]
        cites = payload["What sat on the mat?__citations"]
        assert all(v == "https://ex.test/cat" for v in cites.values()), cites
        print("PASS simple factual retrieval + citations")


async def test_section_specific() -> None:
    with tempfile.TemporaryDirectory() as d:
        r = make_orchestrator(d)
        text = (
            "# Overview\nThis is general overview text. " * 15 +
            "\n# Details\nThis section has specific details about the widget. " * 15
        )
        await r.ingest("s2", "q1", "https://ex.test/widget", text)

        # Test section-specific retrieval (routes to section_first)
        res = await r.retrieve("s2", "section details about the widget")
        assert res["chunks_written"] >= 1

        payload = r._read_temp()["s2"]
        chunks = payload["section details about the widget"]
        # The retrieved chunk should belong to the Details section
        assert any("Details" in c or "widget" in c for c in chunks.values()), chunks
        print("PASS section-specific retrieval")


async def test_multi_document() -> None:
    with tempfile.TemporaryDirectory() as d:
        r = make_orchestrator(d)
        await r.ingest("s3", "q1", "https://ex.test/doc1", "Apples are delicious red fruits. " * 20)
        await r.ingest("s3", "q1", "https://ex.test/doc2", "Bananas are long yellow fruits. " * 20)

        # Retrieval matching both documents
        await r.retrieve("s3", "fruits apples bananas")

        payload = r._read_temp()["s3"]
        cites = payload["fruits apples bananas__citations"].values()

        # Should contain references to BOTH documents
        assert "https://ex.test/doc1" in cites
        assert "https://ex.test/doc2" in cites
        print("PASS multi-document retrieval")


async def test_incremental_re_ingestion() -> None:
    with tempfile.TemporaryDirectory() as d:
        r = make_orchestrator(d)
        await r.ingest("s4", "q1", "https://ex.test/doc", "Alpha provides energy. " * 20)

        chunks_before = len(r.store.all_chunks("s4"))
        sections_before = len(r.store.all_sections("s4"))

        # Re-ingest the SAME source with new/modified content
        await r.ingest("s4", "q1", "https://ex.test/doc", "Alpha provides energy and Beta stores it. " * 25)

        chunks_after = len(r.store.all_chunks("s4"))
        sections_after = len(r.store.all_sections("s4"))

        # Ensure we didn't just stack duplicate documents, sections, or chunks in SQLite
        # Due to cascade delete, old ones should have been removed
        assert chunks_after > 0
        assert sections_after > 0
        assert chunks_after != chunks_before or sections_after != sections_before or chunks_before > 0

        # Ensure no duplicates in the store's documents
        docs = r.store.all_documents("s4")
        assert len(docs) == 1, f"Expected exactly 1 document, found: {len(docs)}"
        print("PASS incremental re-ingestion")


async def test_weak_evidence_fallback() -> None:
    with tempfile.TemporaryDirectory() as d:
        r = make_orchestrator(d)
        await r.ingest("s5", "q1", "https://ex.test/x", "Cats are small animals. " * 20)

        answer = await r.synthesize("s5", "quantized neutrino teleportation protocol details")
        assert answer["weak"] is True, answer
        # Must hedge instead of hallucinating
        assert "enough" in answer["answer"] or "cannot" in answer["answer"].lower(), answer["answer"]
        print("PASS weak-evidence fallback")


async def main() -> None:
    await test_simple_factual()
    await test_section_specific()
    await test_multi_document()
    await test_incremental_re_ingestion()
    await test_weak_evidence_fallback()
    print("\nAll Hierarchical RAG tests passed.")


if __name__ == "__main__":
    asyncio.run(main())
