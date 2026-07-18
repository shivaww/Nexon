"""Automated evaluation and regression harness for Deep Research Hierarchical RAG."""

from __future__ import annotations

import asyncio
import hashlib
import tempfile
import time
from pathlib import Path
import sys

# Ensure parent directory is on the path
BRIDGE_DIR = Path(__file__).resolve().parents[2]
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from deep_research.orchestrator import DeepResearchOrchestrator
from deep_research.rag.embedder import LlamaCppEmbedder


class FakeEmbedder(LlamaCppEmbedder):
    """Deterministic embedding provider that overrides generator fallbacks with mock values."""

    def __init__(self, store=None) -> None:
        super().__init__(endpoint=None, model_path=None, store=store)
        self.total_requests = 0

    async def _embed_http(self, texts: list[str]) -> list[list[float]]:
        # Mock generator
        self.total_requests += len(texts)
        results = []
        for text in texts:
            lowered = text.lower()
            if "soccer" in lowered or "world cup" in lowered:
                # Return vector completely orthogonal to standard doc vectors (last element is 1.0, others 0)
                results.append([0.0] * 63 + [1.0])
            else:
                h = int(hashlib.md5(text.encode("utf-8")).hexdigest(), 16)
                vec = [0.0] * 64
                for i in range(63):
                    vec[i] = float((h >> i) & 1)
                vec[63] = 0.0  # Force last element to 0 to ensure orthogonality with unrelated queries
                norm = sum(v * v for v in vec) ** 0.5 or 1.0
                results.append([v / norm for v in vec])
        return results

    async def _embed_cli_batched(self, texts: list[str]) -> list[list[float]]:
        return await self._embed_http(texts)

    async def _embed_remote(self, texts: list[str]) -> list[list[float]] | None:
        return await self._embed_http(texts)


async def run_evaluation() -> None:
    print("=== Hierarchical RAG Evaluation Loop ===")
    
    # 1. Setup mock document content
    doc1_url = "https://example.com/gemma"
    doc1_text = (
        "# Gemma Model Architecture\n"
        "Gemma is a family of lightweight, state-of-the-art open models built by Google.\n"
        "It is built on the same research, technology, and infrastructure as Gemini.\n"
        "Gemma utilizes multi-query attention (MQA) to reduce memory bandwidth requirements.\n"
        "Additionally, it leverages GeGLU activation functions instead of standard ReLU.\n"
        "This architecture is highly optimized for mobile devices and local deployment."
    )

    doc2_url = "https://example.com/rag"
    doc2_text = (
        "# RAG Implementation and Reranking\n"
        "Retrieval-Augmented Generation (RAG) is a technique that combines search with generation.\n"
        "The current retrieval system routes queries dynamically through a query classifier.\n"
        "A hybrid reranker combines vector similarity with lexical keyword overlap to refine scores.\n"
        "Finally, citations are preserved for every retrieved chunk to guarantee grounded answers.\n"
        "This prevents hallucinations and provides direct verification links."
    )

    # We will test three scenarios:
    # 1. Baseline Ingestion (fresh database)
    # 2. Cached Ingestion (repeated identical ingestion - checks cache hits and subprocess count)
    # 3. Retrieval precision and query routing validation
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # Scenario 1: fresh run
        print("\n[Scenario 1: Fresh Ingestion & Baseline Retrieval]")
        # We initialize orchestrator first to get its store reference
        r = DeepResearchOrchestrator(temp_dir)
        embedder = FakeEmbedder(store=r.store)
        r.embedder = embedder
        r.lightrag.embedder = embedder
        r.hybrid.embedder = embedder
        r.agent.embedder = embedder
        
        # Measure Ingestion Latency
        start_ingest = time.perf_counter()
        res1 = await r.ingest("stage_eval", "q1", doc1_url, doc1_text)
        res2 = await r.ingest("stage_eval", "q1", doc2_url, doc2_text)
        ingest_latency = time.perf_counter() - start_ingest
        
        print(f"Fresh Ingestion Latency: {ingest_latency:.4f}s")
        print(f"Chunks Added: {res1['new_chunks_added'] + res2['new_chunks_added']}")
        print(f"Embeddings requested: {embedder.total_requests}")
        assert embedder.total_requests > 0, "No embeddings requested during fresh ingestion."

        # Scenario 2: Cached Ingestion
        print("\n[Scenario 2: Cached Ingestion (Re-ingesting same docs)]")
        # Reset total requests counter to measure scenario 2 separately
        embedder.total_requests = 0
        
        start_cached_ingest = time.perf_counter()
        res1_cached = await r.ingest("stage_eval", "q1", doc1_url, doc1_text)
        res2_cached = await r.ingest("stage_eval", "q1", doc2_url, doc2_text)
        cached_ingest_latency = time.perf_counter() - start_cached_ingest
        
        print(f"Cached Ingestion Latency: {cached_ingest_latency:.4f}s")
        # The underlying embedder should have spent ZERO calls to the mock generator because SQLite cache resolves them
        print(f"New Embeddings computed: {embedder.total_requests}")
        assert embedder.total_requests == 0, f"Expected 0 embeddings computed, got {embedder.total_requests}"
        print("SUCCESS: 100% Cache hit rate for identical document re-ingestion.")
        
        # Scenario 3: Retrieval Evaluation (Precision, Recall, Routing)
        print("\n[Scenario 3: Retrieval Accuracy & Query Routing]")
        
        # Test Query A: specific factual query (expected route: direct)
        query_a = "what is Gemma model architecture attention mechanism?"
        start_ret = time.perf_counter()
        await r.retrieve("stage_eval", query_a)
        ret_latency = time.perf_counter() - start_ret
        
        # Read temp.json to inspect route & content
        payload = r._read_temp()["stage_eval"]
        routes_a = payload.get(f"{query_a}__routes", {})
        citations_a = payload.get(f"{query_a}__citations", {})
        
        print(f"Query A ('{query_a[:40]}...'):")
        print(f"  Latency: {ret_latency:.4f}s")
        print(f"  Routes: {list(routes_a.values())}")
        print(f"  Citations: {list(citations_a.values())}")
        
        # Verify route and citations
        assert "direct" in routes_a.values(), f"Expected direct route for factual query, got {routes_a.values()}"
        assert doc1_url in citations_a.values(), "Expected citation to Gemma doc."
        
        # Test Query B: section-specific structural query (expected route: section_first)
        query_b = "explain the process of reranking and hybrid implementation in RAG"
        await r.retrieve("stage_eval", query_b)
        
        # Reload payload to get Query B updates!
        payload = r._read_temp()["stage_eval"]
        routes_b = payload.get(f"{query_b}__routes", {})
        citations_b = payload.get(f"{query_b}__citations", {})
        
        print(f"\nQuery B ('{query_b[:40]}...'):")
        print(f"  Routes: {list(routes_b.values())}")
        print(f"  Citations: {list(citations_b.values())}")
        
        assert "section_first" in routes_b.values(), f"Expected section_first route, got {routes_b.values()}"
        assert doc2_url in citations_b.values(), "Expected citation to RAG doc."

        # Test Scenario 4: Weak evidence fallback
        print("\n[Scenario 4: Weak Evidence Fallback]")
        unrelated_query = "who won the soccer world cup in 2022?"
        ans = await r.synthesize("stage_eval", unrelated_query)
        print(f"Unrelated query answer: '{ans['answer'][:80]}...'")
        print(f"Unrelated query weak-evidence flag: {ans['weak']}")
        
        assert ans["weak"] is True, "Expected weak evidence flag to be True."
        assert "cannot" in ans["answer"].lower() or "enough" in ans["answer"].lower(), "Expected hedge warning in answer."

    print("\n=== All Evaluation and Regression Assertions Passed ===")


if __name__ == "__main__":
    asyncio.run(run_evaluation())
