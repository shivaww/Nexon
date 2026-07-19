"""Hierarchical retrieval narrowing for deep-research sessions.

Replaces graph traversal with a lightweight, multi-stage retrieval narrowing
(document -> section -> chunk) guided by query classification.
Uses lexical-vector hybrid reranking and deduplication.
"""

from __future__ import annotations

from dataclasses import dataclass
import logging
import math
import re
import time
from typing import Any

import numpy as np

from .store import ResearchStore

logger = logging.getLogger(__name__)


@dataclass
class RetrievedEvidence:
    text: str
    source_url: str | None
    vector_score: float
    graph_score: float
    score: float
    route: str  # "direct" | "section_first" | "document_first"
    chunk_id: int = -1

    def to_payload(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "source": self.source_url,
            "score": round(self.score, 4),
            "route": self.route,
        }


class HybridRetriever:
    """Hierarchical RAG Retriever (named HybridRetriever for backwards compatibility)."""

    def __init__(
        self,
        store: ResearchStore,
        embedder: object,
        doc_top_k: int = 3,
        section_top_k: int = 5,
        chunk_top_k: int = 8,
        rerank_depth: int = 6,
        weak_evidence_threshold: float = 0.25,
        # Keep graph arguments as stubs for compatibility
        vector_top_k: int | None = None,
        graph_entity_k: int | None = None,
        graph_depth: int | None = None,
    ) -> None:
        self.store = store
        self.embedder = embedder
        self.doc_top_k = doc_top_k
        self.section_top_k = section_top_k
        self.chunk_top_k = chunk_top_k or vector_top_k or 8
        self.rerank_depth = rerank_depth
        self.weak_evidence_threshold = weak_evidence_threshold

    async def retrieve(self, stage_id: str, query: str) -> list[RetrievedEvidence]:
        """Full hierarchical retrieval: query routing -> narrowing -> reranking -> fusion."""
        # 1. Embed query
        query_vector = (await self.embedder.embed_texts([query]))[0]

        # 2. Classify query to select route
        route = self.classify_query(query)

        # 3. Retrieve candidates using hierarchy narrowing
        if route == "document_first":
            candidates = self._retrieve_document_first(stage_id, query_vector, query)
        elif route == "section_first":
            candidates = self._retrieve_section_first(stage_id, query_vector, query)
        else:
            candidates = self._retrieve_direct(stage_id, query_vector, query)

        # 4. Rerank and deduplicate
        reranked = self.rerank(candidates, query)
        fused = self._fuse(reranked, self.rerank_depth)
        return fused

    def classify_query(self, query: str) -> str:
        """Categorize the query to optimize precision vs. search breadth using structural rules."""
        trimmed = query.strip()
        lowered = trimmed.lower()
        words = lowered.split()

        # Rule 1: Very short queries (1-2 words) are typically broad topics
        if len(words) <= 2:
            # If contains comparison keywords, document-first, else section-first
            if any(w in lowered for w in ["vs", "compare", "diff", "or"]):
                return "document_first"
            return "section_first"

        # Broad comparison / synthesis indicators -> Document First
        doc_indicators = [
            r"\bcompare\b", r"\bcomparison\b", r"\bdifference between\b",
            r"\boverview\b", r"\bsummary\b", r"\bsummarize\b", r"\btheme\b",
            r"\bentire\b", r"\bwhole\b", r"\boverall\b", r"\bcomprehensive\b",
            r"\bsynthesize\b", r"\brelation(ship)?\b", r"\bconnection\b",
            r"\bhistory\b", r"\bevolution\b"
        ]

        # Structural / process / guide indicators -> Section First
        section_indicators = [
            r"\bsection\b", r"\bchapter\b", r"\bpart\b", r"\btopic\b",
            r"\bhow (?:to|do|does|can)\b", r"\bguide\b", r"\btutorial\b",
            r"\bprocess of\b", r"\bmethodology\b", r"\barchitecture\b",
            r"\bdesign\b", r"\bimplementation\b", r"\bwhy (?:is|are|does|do)\b",
            r"\bexplain\b", r"\bdetails\b"
        ]

        # Factual / exact keyword indicators -> Direct Chunk
        direct_indicators = [
            r"\bwhat is\b", r"\bwho is\b", r"\bwhen did\b", r"\bhow (?:many|much)\b",
            r"\bwhere (?:is|did|are)\b", r"\bexact\b", r"\bdefinition\b",
            r"\bcode\b", r"\bfunction\b", r"\bclass\b", r"\berror\b"
        ]

        # Evaluate matches using regex search
        if any(re.search(pat, lowered) for pat in doc_indicators):
            return "document_first"
        if any(re.search(pat, lowered) for pat in direct_indicators):
            return "direct"
        if any(re.search(pat, lowered) for pat in section_indicators):
            return "section_first"

        # Default fallback: direct chunk retrieval for high precision
        return "direct"

    def is_weak(self, evidence: list[RetrievedEvidence]) -> bool:
        if not evidence:
            return True
        return max(e.score for e in evidence) < self.weak_evidence_threshold

    # ── Retrieval Primitives ──────────────────────────────────────────

    def _retrieve_document_first(
        self, stage_id: str, query_vector: list[float], query: str
    ) -> list[RetrievedEvidence]:
        """Stage 1: Doc candidates -> Stage 2: Section candidates -> Stage 3: Chunks."""
        # 1. Select documents (candidate set is already scoped to this stage)
        docs = self.store.all_documents(stage_id)
        if not docs:
            return []
        doc_embs = [doc.embedding for doc in docs]
        stage_start = time.perf_counter()
        doc_scores = self._cosine_batch(query_vector, doc_embs)
        logger.debug(
            "retrieve[document_first] stage=doc candidates=%d latency=%.4fs",
            len(doc_embs), time.perf_counter() - stage_start,
        )
        scored_docs = sorted(zip(doc_scores, docs), key=lambda x: x[0], reverse=True)
        top_docs = [doc for _, doc in scored_docs[: self.doc_top_k]]

        # 2. Select sections within selected documents (scoped to top docs)
        sections = []
        for doc in top_docs:
            sections.extend(self.store.sections_for_document(stage_id, doc.source_url))
        if not sections:
            return []
        sec_embs = [sec.embedding for sec in sections]
        stage_start = time.perf_counter()
        sec_scores = self._cosine_batch(query_vector, sec_embs)
        logger.debug(
            "retrieve[document_first] stage=section candidates=%d latency=%.4fs",
            len(sec_embs), time.perf_counter() - stage_start,
        )
        scored_sections = sorted(zip(sec_scores, sections), key=lambda x: x[0], reverse=True)
        top_sections = [sec for _, sec in scored_sections[: self.section_top_k]]

        # 3. Select chunks within selected sections (scoped to top sections)
        chunks = []
        for sec in top_sections:
            chunks.extend(self.store.chunks_for_section(stage_id, sec.id))
        if not chunks:
            return []
        chunk_embs = [ch.embedding for ch in chunks]
        stage_start = time.perf_counter()
        chunk_scores = self._cosine_batch(query_vector, chunk_embs)
        logger.debug(
            "retrieve[document_first] stage=chunk candidates=%d latency=%.4fs",
            len(chunk_embs), time.perf_counter() - stage_start,
        )
        scored_chunks = sorted(zip(chunk_scores, chunks), key=lambda x: x[0], reverse=True)
        top_chunks = scored_chunks[: self.chunk_top_k]

        # Construct evidence payloads enriched with section context
        evidences = []
        for score, ch in top_chunks:
            sec_title = next((s.title for s in sections if s.id == ch.section_id), None)
            section_info = f" | Section: {sec_title}" if sec_title else ""
            enriched_text = f"Document: {ch.source_url}{section_info}\nContent: {ch.content}"
            evidences.append(
                RetrievedEvidence(
                    text=enriched_text,
                    source_url=ch.source_url,
                    vector_score=score,
                    graph_score=0.0,
                    score=score,
                    route="document_first",
                    chunk_id=ch.id if ch.id is not None else -1,
                )
            )
        return evidences

    def _retrieve_section_first(
        self, stage_id: str, query_vector: list[float], query: str
    ) -> list[RetrievedEvidence]:
        """Stage 2: Section candidates -> Stage 3: Chunks."""
        # 1. Select sections across all documents in stage
        sections = self.store.all_sections(stage_id)
        if not sections:
            return []
        sec_embs = [sec.embedding for sec in sections]
        stage_start = time.perf_counter()
        sec_scores = self._cosine_batch(query_vector, sec_embs)
        logger.debug(
            "retrieve[section_first] stage=section candidates=%d latency=%.4fs",
            len(sec_embs), time.perf_counter() - stage_start,
        )
        scored_sections = sorted(zip(sec_scores, sections), key=lambda x: x[0], reverse=True)
        top_sections = [sec for _, sec in scored_sections[: self.section_top_k]]

        # 2. Select chunks within selected sections
        chunks = []
        for sec in top_sections:
            chunks.extend(self.store.chunks_for_section(stage_id, sec.id))
        if not chunks:
            return []
        chunk_embs = [ch.embedding for ch in chunks]
        stage_start = time.perf_counter()
        chunk_scores = self._cosine_batch(query_vector, chunk_embs)
        logger.debug(
            "retrieve[section_first] stage=chunk candidates=%d latency=%.4fs",
            len(chunk_embs), time.perf_counter() - stage_start,
        )
        scored_chunks = sorted(zip(chunk_scores, chunks), key=lambda x: x[0], reverse=True)
        top_chunks = scored_chunks[: self.chunk_top_k]

        evidences = []
        for score, ch in top_chunks:
            sec_title = next((s.title for s in sections if s.id == ch.section_id), None)
            section_info = f" | Section: {sec_title}" if sec_title else ""
            enriched_text = f"Document: {ch.source_url}{section_info}\nContent: {ch.content}"
            evidences.append(
                RetrievedEvidence(
                    text=enriched_text,
                    source_url=ch.source_url,
                    vector_score=score,
                    graph_score=0.0,
                    score=score,
                    route="section_first",
                    chunk_id=ch.id if ch.id is not None else -1,
                )
            )
        return evidences

    def _retrieve_direct(
        self, stage_id: str, query_vector: list[float], query: str
    ) -> list[RetrievedEvidence]:
        """Stage 3: Retrieve chunks directly (highest precision fallback)."""
        chunks = self.store.all_chunks(stage_id)
        if not chunks:
            return []
        chunk_embs = [ch.embedding for ch in chunks]
        stage_start = time.perf_counter()
        chunk_scores = self._cosine_batch(query_vector, chunk_embs)
        logger.debug(
            "retrieve[direct] stage=chunk candidates=%d latency=%.4fs",
            len(chunk_embs), time.perf_counter() - stage_start,
        )
        scored_chunks = sorted(zip(chunk_scores, chunks), key=lambda x: x[0], reverse=True)
        top_chunks = scored_chunks[: self.chunk_top_k]

        sections = self.store.all_sections(stage_id)
        sec_map = {s.id: s.title for s in sections}

        evidences = []
        for score, ch in top_chunks:
            sec_title = sec_map.get(ch.section_id)
            section_info = f" | Section: {sec_title}" if sec_title else ""
            enriched_text = f"Document: {ch.source_url}{section_info}\nContent: {ch.content}"
            evidences.append(
                RetrievedEvidence(
                    text=enriched_text,
                    source_url=ch.source_url,
                    vector_score=score,
                    graph_score=0.0,
                    score=score,
                    route="direct",
                    chunk_id=ch.id if ch.id is not None else -1,
                )
            )
        return evidences

    # ── Reranking & Fusion ────────────────────────────────────────────

    def rerank(self, candidates: list[RetrievedEvidence], query: str) -> list[RetrievedEvidence]:
        """Perform lightweight lexical-vector hybrid reranking."""
        for ev in candidates:
            lex = self._lexical_score(query, ev.text)
            ev.score = 0.7 * ev.vector_score + 0.3 * lex
        candidates.sort(key=lambda e: e.score, reverse=True)
        return candidates

    def _lexical_score(self, query: str, text: str) -> float:
        query_words = set(re.findall(r"\w+", query.lower()))
        stopwords = {
            "what", "how", "why", "who", "where", "when", "the", "a", "an", "is", "are",
            "of", "in", "on", "at", "for", "to", "and", "or", "but", "with"
        }
        query_words = query_words - stopwords
        if not query_words:
            return 0.0
        text_words = set(re.findall(r"\w+", text.lower()))
        overlap = query_words.intersection(text_words)
        return len(overlap) / len(query_words)

    def _fuse(self, reranked: list[RetrievedEvidence], depth: int) -> list[RetrievedEvidence]:
        """Deduplicate near-identical chunks and slice to depth."""
        seen_text: set[str] = set()
        fused: list[RetrievedEvidence] = []
        for ev in reranked:
            # Strip whitespace & case for strict/fuzzy content comparison
            normalized = "".join(ev.text.lower().split())

            is_duplicate = False
            for seen in seen_text:
                if normalized in seen or seen in normalized:
                    is_duplicate = True
                    break

            if is_duplicate:
                continue

            seen_text.add(normalized)
            fused.append(ev)
            if len(fused) >= depth:
                break
        return fused

    @staticmethod
    def _cosine_batch(
        query_vector: list[float], embeddings: list[list[float] | None]
    ) -> list[float]:
        """Vectorized cosine similarity of one query against many candidates.

        Stacks the candidate embeddings into a single 2-D numpy array and
        computes every similarity in one matrix operation rather than a
        per-row Python loop.  Because the hierarchical narrowing stages
        always pass an already-scoped candidate set (never the full corpus),
        this brute-force comparison stays fast for realistic single-user
        corpus sizes.  Returns a list of scores aligned with ``embeddings``.
        """
        if not embeddings:
            return []
        q = np.asarray(query_vector, dtype=np.float32)
        q_norm = float(np.linalg.norm(q))
        if q_norm == 0.0:
            return [0.0] * len(embeddings)

        # Find the dimension of a valid embedding in the list
        dim = 0
        for emb in embeddings:
            if emb is not None and len(emb) > 0:
                dim = len(emb)
                break
        if dim == 0:
            return [0.0] * len(embeddings)

        # Construct safe list of embeddings where None or mismatching sizes are filled with zeros
        safe_embs = []
        for emb in embeddings:
            if emb is not None and len(emb) == dim:
                safe_embs.append(emb)
            else:
                safe_embs.append([0.0] * dim)

        matrix = np.asarray(safe_embs, dtype=np.float32)  # shape (n, d)
        norms = np.linalg.norm(matrix, axis=1)
        safe_norms = np.where(norms == 0.0, 1.0, norms)
        sims = (matrix @ q) / (safe_norms * q_norm)
        
        # Zero out similarity for candidates with missing embeddings
        sims_list = sims.tolist()
        for idx, emb in enumerate(embeddings):
            if emb is None or len(emb) != dim:
                sims_list[idx] = 0.0
                
        return sims_list

    @staticmethod
    def _cosine(left: list[float], right: list[float]) -> float:
        if not left or not right:
            return 0.0
        numerator = sum(a * b for a, b in zip(left, right))
        denominator = math.sqrt(sum(a * a for a in left)) * math.sqrt(sum(b * b for b in right))
        return numerator / denominator if denominator else 0.0

    # ── Compatibility interfaces ──────────────────────────────────────

    async def vector_evidence(self, stage_id: str, query: str) -> dict[int, RetrievedEvidence]:
        query_vector = (await self.embedder.embed_texts([query]))[0]
        candidates = self._retrieve_direct(stage_id, query_vector, query)
        return {c.chunk_id: c for c in candidates}

    async def graph_evidence(self, stage_id: str, query: str) -> dict[int, RetrievedEvidence]:
        query_vector = (await self.embedder.embed_texts([query]))[0]
        candidates = self._retrieve_section_first(stage_id, query_vector, query)
        return {c.chunk_id: c for c in candidates}

    def assemble(
        self,
        vector: dict[int, RetrievedEvidence],
        graph: dict[int, RetrievedEvidence],
        depth: int | None = None,
    ) -> list[RetrievedEvidence]:
        merged = {}
        for cid, ev in vector.items():
            merged[cid] = ev
        for cid, ev in graph.items():
            if cid not in merged:
                merged[cid] = ev
        candidates = list(merged.values())
        candidates.sort(key=lambda e: e.score, reverse=True)
        return self._fuse(candidates, depth if depth is not None else self.rerank_depth)
