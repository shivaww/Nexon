"""End-to-end validation of the plain sqlite3 BLOB + numpy cosine storage engine.

This test exercises the real ingestion (LightRAGBuilder), retrieval
(HybridRetriever, all three hierarchical routes) and agentic escalation
(agentic_loop.broader_search) paths against the numpy storage engine.

A deterministic lexical embedder stands in for the real embedding model
server (which cannot load its backends in this sandbox).  Because the
embedder is deterministic and content-addressed, it also validates the
ingestion dedup behaviour.

Run from the repository root:
    python3 python_bridge/deep_research/rag/test_numpy_storage.py
"""

from __future__ import annotations

import asyncio
import hashlib
import re
import tempfile
import time
from pathlib import Path

import numpy as np

from .store import ResearchStore
from .lightrag_builder import LightRAGBuilder, ChunkingConfig
from .hybrid_retriever import HybridRetriever
from .agentic_loop import agentic_retrieve


# ── Deterministic stand-in embedder ────────────────────────────────────
# Hashing-trick bag-of-words, L2-normalized.  Identical text -> identical
# vector, so dedup and re-ingest behave the same as with a real model.
class LexicalEmbedder:
    def __init__(self, dim: int = 512) -> None:
        self.dim = dim

    async def embed_texts(self, texts: list[str]) -> list[list[float]]:
        return [self._emb(t) for t in texts]

    def _emb(self, text: str) -> list[float]:
        vec = np.zeros(self.dim, dtype=np.float32)
        for w in re.findall(r"\w+", text.lower()):
            h = int(hashlib.md5(w.encode()).hexdigest(), 16) % self.dim
            vec[h] += 1.0
        n = np.linalg.norm(vec)
        if n > 0:
            vec /= n
        return vec.tolist()


# ── Synthetic corpus ───────────────────────────────────────────────────
THEMES = {
    "photosynthesis": [
        "Photosynthesis converts light energy into chemical energy in chloroplasts.",
        "Chlorophyll absorbs red and blue light to drive the Calvin cycle.",
        "Stomata regulate gas exchange of carbon dioxide during photosynthesis.",
        "The light-dependent reactions produce ATP and NADPH in the thylakoid membrane.",
    ],
    "neural_networks": [
        "Backpropagation computes gradients to train deep neural networks efficiently.",
        "Activation functions like ReLU introduce non-linearity into neural networks.",
        "Gradient descent optimizes the loss function of a neural network.",
        "Convolutional neural networks excel at image recognition tasks.",
    ],
    "blockchain": [
        "Blockchain uses cryptographic hashes to link immutable blocks of transactions.",
        "Proof of work requires miners to solve computational puzzles for consensus.",
        "Smart contracts execute automatically on a decentralized blockchain ledger.",
        "Public key cryptography secures ownership of blockchain assets.",
    ],
    "cooking": [
        "Maillard reaction browns meat and develops complex savory flavors.",
        "Emulsification combines oil and water into a stable sauce like mayonnaise.",
        "Fermentation uses yeast to leaven bread and develop sour flavors.",
        "Sous vide cooks food gently in a precise temperature water bath.",
    ],
}

DOC_TEMPLATE = """# {title}

## Introduction
{intro}

## Background
{body0}

## Details
{body1}

## Advanced
{body2}

## Summary
{body3}
"""


def build_corpus(n_docs_per_theme: int = 3) -> list[tuple[str, str]]:
    docs: list[tuple[str, str]] = []
    idx = 0
    for theme, bodies in THEMES.items():
        for v in range(n_docs_per_theme):
            intro = f"This document discusses {theme} with a focus on practical aspects."
            text = DOC_TEMPLATE.format(
                title=f"{theme} part {v + 1}",
                intro=intro,
                body0=bodies[0],
                body1=bodies[1],
                body2=bodies[2],
                body3=bodies[3],
            )
            docs.append((f"https://example.com/{theme}/{v}", text))
            idx += 1
    return docs


async def main() -> None:
    tmp = Path(tempfile.mkdtemp()) / "rag_test.db"
    store = ResearchStore(tmp)
    embedder = LexicalEmbedder()
    builder = LightRAGBuilder(store, embedder, config=ChunkingConfig())

    corpus = build_corpus(n_docs_per_theme=3)
    print(f"\n[ingest] ingesting {len(corpus)} documents across {len(THEMES)} themes")
    total_chunks = 0
    for url, text in corpus:
        result = await builder.ingest("stage1", "q1", url, text)
        total_chunks += result.new_chunks_added
    print(f"[ingest] total new chunks added: {total_chunks}")
    print(f"[ingest] leaf count: {store.leaf_count('stage1')}")

    retriever = HybridRetriever(store, embedder)

    # ── Correctness: each themed query should surface that theme's doc ──
    print("\n[retrieve] semantic relevance spot-checks (top source per query):")
    query_map = {
        "how does backpropagation train neural networks": "neural_networks",
        "what is the role of chlorophyll in photosynthesis": "photosynthesis",
        "how does proof of work secure a blockchain": "blockchain",
        "why does the maillard reaction brown meat": "cooking",
    }
    all_ok = True
    for query, expected_theme in query_map.items():
        evidences = await retriever.retrieve("stage1", query)
        assert evidences, f"no evidence returned for {query!r}"
        top = evidences[0]
        ok = expected_theme in top.source_url
        all_ok = all_ok and ok
        print(f"  - q={query!r}")
        print(f"      top_source={top.source_url} score={top.score:.3f} route={top.route} -> {'OK' if ok else 'MISMATCH'}")

    # ── Latency measurement (realistic single query) ──
    print("\n[latency] measuring retrieve() over full corpus (3 routes):")
    queries = list(query_map.keys())
    for route_q, _ in query_map.items():
        # warm
        await retriever.retrieve("stage1", route_q)
        runs = 20
        t0 = time.perf_counter()
        for _ in range(runs):
            await retriever.retrieve("stage1", route_q)
        elapsed = (time.perf_counter() - t0) / runs * 1000
        print(f"  - q={route_q[:40]!r}: avg {elapsed:.2f} ms/query")

    # ── Dedup: re-ingest identical CONTENT under a different URL -> added == 0 ──
    # LightRAGBuilder's novelty check (unchanged by this task) compares the new
    # document's chunk vectors against existing chunks from OTHER urls; identical
    # content scores >= DUPLICATE_THRESHOLD (0.95) and is skipped.
    print("\n[dedup] re-ingesting identical content under a NEW url:")
    _, text0 = corpus[0]
    dup_url = "https://example.com/duplicate-of-doc0"
    result = await builder.ingest("stage1", "q1", dup_url, text0)
    print(f"  - new_chunks_added={result.new_chunks_added} novelty_ratio={result.novelty_ratio:.2f}")
    assert result.new_chunks_added == 0, "dedup failed: identical content added chunks"
    print("  - OK: identical content re-ingest produced 0 new chunks (novelty dedup works)")

    # ── Backward-compat: a BLOB written by the OLD array('f') codec decodes ──
    print("\n[backward-compat] old array('f') BLOB format still decodes:")
    import array
    legacy_blob = array.array("f", [0.1, 0.2, 0.3, 0.4]).tobytes()
    decoded = store._decode_vector(legacy_blob)
    print(f"  - decoded legacy blob -> {[round(x, 4) for x in decoded]}")
    assert abs(decoded[0] - 0.1) < 1e-5
    # and numpy-encoded blobs load through the old-style reader path too
    np_blob = np.asarray([0.5, 0.6], dtype=np.float32).tobytes()
    assert abs(store._decode_vector(np_blob)[1] - 0.6) < 1e-5
    print("  - OK: float32 BLOB round-trips both directions")

    # ── agentic_loop broader_search escalation ──
    print("\n[agentic] broader_search escalation (Tavily ingest -> re-retrieve):")
    calls = {"retrieve": 0, "ingest": 0}

    async def fake_retrieve(q: str):
        calls["retrieve"] += 1
        return await retriever.retrieve("stage1", q)

    async def fake_ingest(docs):
        calls["ingest"] += 1
        for d in docs:
            await builder.ingest("stage1", "q1", d["url"], d["text"])

    def fake_tavily(q: str):
        # simulate web results that add a brand-new themed doc
        return [{
            "url": "https://web.com/quantum",
            "text": DOC_TEMPLATE.format(
                title="quantum computing",
                intro="This document discusses quantum computing.",
                body0="Quantum superposition lets qubits represent many states at once.",
                body1="Quantum entanglement correlates distant qubits instantly.",
                body2="Quantum gates manipulate qubits in a quantum circuit.",
                body3="Quantum error correction protects fragile quantum states.",
            ),
        }]

    out = await agentic_retrieve(
        "how do quantum gates manipulate qubits",
        existing_retrieve_fn=fake_retrieve,
        existing_ingest_fn=fake_ingest,
        tavily_search_fn=fake_tavily,
    )
    print(f"  - escalated={out['escalated']} iterations={out['iterations_used']} chunks={len(out['chunks'])}")
    print(f"  - calls: retrieve={calls['retrieve']} ingest={calls['ingest']}")
    assert out["escalated"] is True, "agentic broader_search should have escalated"
    assert calls["ingest"] == 1, "broader_search should have ingested once"
    assert any("quantum" in (c.source_url if hasattr(c, 'source_url') else str(c)) for c in out["chunks"]), \
        "escalated results should include the newly ingested quantum doc"
    print("  - OK: broader_search escalated, ingested web doc, and re-retrieved it")

    store.close()

    print("\n=== SUMMARY ===")
    print(f"  semantic relevance all correct: {all_ok}")
    print(f"  dedup correct: True")
    print(f"  backward-compat BLOB decode: True")
    print(f"  agentic broader_search correct: True")
    assert all_ok, "semantic relevance spot-checks failed"
    print("\nALL CHECKS PASSED")


if __name__ == "__main__":
    asyncio.run(main())
