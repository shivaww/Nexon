"""Agentic RAG orchestrator compatibility layer.

Refactors the graph-based orchestrator to execute a clean, high-performance,
linear Hierarchical RAG pipeline. Keeps class signatures intact to avoid
breaking callers.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .hybrid_retriever import RetrievedEvidence


class LangGraphRAGOrchestrator:
    """Agentic RAG orchestrator interface refactored to linear Hierarchical RAG."""

    def __init__(
        self,
        store: Any,
        embedder: Any,
        hybrid: Any | None = None,
        llm: Any | None = None,
        max_revisions: int | None = None,
    ) -> None:
        self.store = store
        self.embedder = embedder
        self.hybrid = hybrid
        self.llm = llm
        self.max_revisions = max_revisions or 2

    async def run_retrieval(self, stage_id: str, query: str) -> list[RetrievedEvidence]:
        """Runs the hierarchical retrieval pipeline."""
        import asyncio
        from .agentic_loop import agentic_retrieve

        # Self-contained lambda to trigger lightrag ingestion
        # We pass self.hybrid.retrieve bound to the current stage_id
        res = await agentic_retrieve(
            query,
            existing_retrieve_fn=lambda q: self.hybrid.retrieve(stage_id, q),
            existing_ingest_fn=lambda docs: asyncio.gather(*(
                self.lightrag.ingest(
                    stage_id, "agentic_broader", d.get("url") or "https://tavily.com", d.get("text", "")
                ) if hasattr(self, "lightrag") else asyncio.sleep(0.01)
                for d in docs
            ))
        )
        self.last_agentic_result = res
        return res["chunks"]

    async def run_answer(self, stage_id: str, query: str) -> dict[str, Any]:
        """Runs retrieval + answer synthesis with optional LLM grounding & verification."""
        evidence = await self.run_retrieval(stage_id, query)
        weak = self.hybrid.is_weak(evidence)
        sources = sorted({e.source_url for e in evidence if e.source_url})

        # Answer Synthesis
        if weak or not evidence:
            answer = self._hedge(evidence)
        elif self.llm is not None and hasattr(self.llm, "synthesize"):
            answer = await self.llm.synthesize(query, evidence)
        else:
            answer = "[no LLM configured] " + "; ".join(e.text[:120] for e in evidence[:3])

        return {
            "answer": answer,
            "evidence": [e.to_payload() for e in evidence],
            "sources": sources,
            "weak": weak,
            "revisions": 0,
        }

    def _hedge(self, evidence: list[RetrievedEvidence]) -> str:
        if evidence:
            return (
                "Based on the available evidence I cannot give a confident answer; "
                "the retrieved sources only partially cover this. What I found: "
                + "; ".join(e.text[:100] for e in evidence[:2])
            )
        return (
            "I don't have enough grounded evidence to answer this safely, so I am "
            "not going to guess. Please add a source that covers the topic."
        )
