"""Bridge entrypoints for LightRAG + LangGraph deep-research ingestion/retrieval.

Public API preserved from the old hierarchical design:
  * ``ingest(stage_id, query_id, source_url, text)`` -> IngestResult dict
  * ``retrieve(stage_id, query)`` -> {chunks_written, avg_score} (+ temp.json)

Internally the pipeline is now:
  * LightRAG graph layer (LightRAGBuilder) extracts entities/relations/chunks
    into a lightweight incremental local graph store.
  * LangGraph agentic orchestrator routes the query and runs hybrid retrieval
    (vector + graph traversal), merge, rerank, evidence fusion, and (when an
    LLM is wired) grounded answer synthesis with verification / weak-evidence
    hedging.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from pathlib import Path

from .rag import HybridRetriever, LangGraphRAGOrchestrator, LightRAGBuilder, LlamaCppEmbedder, ResearchStore
from .rag.store import normalize_stage_id
from .rag.chunking import ChunkingConfig
from .schemas import IngestResult, RetrieveResult

logger = logging.getLogger("termux_forge.deep_research")
DEFAULT_INGEST_CONCURRENCY = 6


class DeepResearchOrchestrator:
    def __init__(self, data_dir: str | Path | None = None, embedder: object | None = None) -> None:
        self.data_dir = Path(data_dir or os.getenv("DEEP_RESEARCH_DIR", "~/.termux_forge/deep_research")).expanduser()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.store = ResearchStore(self.data_dir / "research.sqlite3")
        self.embedder = embedder or LlamaCppEmbedder(store=self.store)

        # Config knobs (chunk size / top-k / batch size / rerank depth).
        self.chunk_words = int(os.getenv("DR_CHUNK_WORDS", "220"))
        self.overlap_words = int(os.getenv("DR_OVERLAP_WORDS", "30"))
        # Batch size: amortise per-request HTTP overhead across multiple chunks.
        # Default of 2 is safe for mobile hardware to prevent OOM/timeouts.
        self.embedding_batch_size = int(os.getenv("DR_EMBEDDING_BATCH_SIZE", "2"))
        self.doc_top_k = int(os.getenv("DR_DOCUMENT_TOP_K", "3"))
        self.section_top_k = int(os.getenv("DR_SECTION_TOP_K", "5"))
        self.chunk_top_k = int(os.getenv("DR_CHUNK_TOP_K", os.getenv("DR_VECTOR_TOP_K", "8")))
        self.rerank_depth = int(os.getenv("DR_RERANK_DEPTH", "6"))
        self.weak_evidence_threshold = float(os.getenv("DR_WEAK_THRESHOLD", "0.25"))
        self.max_revisions = int(os.getenv("DR_MAX_REVISIONS", "2"))
        self.ingest_concurrency = max(
            1,
            int(os.getenv("DR_INGEST_CONCURRENCY", str(DEFAULT_INGEST_CONCURRENCY))),
        )

        chunk_cfg = ChunkingConfig(self.chunk_words, self.overlap_words)
        self.lightrag = LightRAGBuilder(
            self.store,
            self.embedder,
            config=chunk_cfg,
            embedding_batch_size=self.embedding_batch_size,
        )
        self.hybrid = HybridRetriever(
            self.store,
            self.embedder,
            doc_top_k=self.doc_top_k,
            section_top_k=self.section_top_k,
            chunk_top_k=self.chunk_top_k,
            rerank_depth=self.rerank_depth,
            weak_evidence_threshold=self.weak_evidence_threshold,
        )
        self.agent = LangGraphRAGOrchestrator(
            self.store, self.embedder, hybrid=self.hybrid, llm=None, max_revisions=self.max_revisions,
        )
        self.agent.lightrag = self.lightrag
        self._lock = asyncio.Lock()
        self._ingest_gate = asyncio.Semaphore(self.ingest_concurrency)
        self.run_ingested_urls = set()
        self._last_stage = None

    def _normalize_url(self, url: str) -> str:
        import re
        url = url.strip().lower()
        url = re.sub(r'^https?://', '', url)
        url = re.sub(r'^www\.', '', url)
        url = url.rstrip('/')
        return url

    @property
    def temp_path(self) -> Path:
        return Path(os.getenv("DEEP_RESEARCH_TEMP_PATH", self.data_dir / "temp.json")).expanduser()

    def config(self) -> dict[str, object]:
        return {
            "chunk_words": self.chunk_words,
            "overlap_words": self.overlap_words,
            "embedding_batch_size": self.embedding_batch_size,
            "doc_top_k": self.doc_top_k,
            "section_top_k": self.section_top_k,
            "chunk_top_k": self.chunk_top_k,
            "rerank_depth": self.rerank_depth,
            "weak_evidence_threshold": self.weak_evidence_threshold,
            "max_revisions": self.max_revisions,
            "ingest_concurrency": self.ingest_concurrency,
        }

    async def acquire_ingest_slot(self) -> None:
        """Acquire the ingestion semaphore slot without starting a timeout clock.

        Callers that want to apply a timeout only to *real work* (not queue
        wait time) should:

            await orchestrator.acquire_ingest_slot()          # wait indefinitely
            try:
                async with asyncio.timeout(N):                # time real work
                    result = await orchestrator.ingest_work(...)
            finally:
                orchestrator.release_ingest_slot()
        """
        await self._ingest_gate.acquire()

    def release_ingest_slot(self) -> None:
        """Release the ingestion semaphore slot."""
        self._ingest_gate.release()

    async def ingest(self, stage_id: str, query_id: str, source_url: str, text: str) -> dict[str, int | float]:
        if not all(isinstance(value, str) and value.strip() for value in (stage_id, query_id, source_url, text)):
            raise ValueError("stage_id, query_id, source_url, and text are required")
        stage_id = normalize_stage_id(stage_id)

        import time
        import hashlib

        norm_url = self._normalize_url(source_url)
        if stage_id == "stage1":
            if getattr(self, "_last_stage", None) != "stage1":
                self.run_ingested_urls.clear()
        self._last_stage = stage_id

        if norm_url in self.run_ingested_urls:
            logger.info("URL already ingested in this run: %s. Short-circuiting.", source_url)
            return {
                "new_chunks_added": 0,
                "novelty_ratio": 0.0,
                "total_chunks_stage": self.store.leaf_count(stage_id),
                "already_attempted": True
            }

        source_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
        start_time = time.perf_counter()

        try:
            async with self._ingest_gate:
                result: IngestResult = await self.lightrag._ingest_and_embed_sync(stage_id, query_id, source_url, text)

            if result and getattr(result, "new_chunks_added", 0) >= 0:
                self.run_ingested_urls.add(norm_url)

            elapsed = time.perf_counter() - start_time
            logger.info(
                "Ingested deep-research source successfully in %.3fs | stage=%s | added=%d | url=%s | hash=%s",
                elapsed, stage_id, result.new_chunks_added, source_url, source_hash
            )
            return result.to_dict()

        except Exception as e:
            elapsed = time.perf_counter() - start_time
            error_preview = str(e)[:100] + "..." if len(str(e)) > 100 else str(e)
            logger.error(
                "Ingestion CIRCUIT BREAKER triggered after %.3fs | stage=%s | url=%s | hash=%s | error=%s",
                elapsed, stage_id, source_url, source_hash, error_preview
            )
            # Return graceful failure response to allow the overall process to proceed
            return {
                "new_chunks_added": 0,
                "novelty_ratio": 0.0,
                "total_chunks_stage": self.store.leaf_count(stage_id),
                "failed": True,
                "error": error_preview
            }

    async def ingest_work(self, stage_id: str, query_id: str, source_url: str, text: str) -> dict[str, int | float]:
        """Run the actual ingest work *without* acquiring the gate.

        Must only be called while the caller already holds a gate slot obtained
        via ``acquire_ingest_slot()``.  This separation lets the bridge apply a
        processing-only timeout, independent of how long the request waited in
        queue.
        """
        if not all(isinstance(value, str) and value.strip() for value in (stage_id, query_id, source_url, text)):
            raise ValueError("stage_id, query_id, source_url, and text are required")
        stage_id = normalize_stage_id(stage_id)

        import time
        import hashlib

        norm_url = self._normalize_url(source_url)
        if stage_id == "stage1":
            if getattr(self, "_last_stage", None) != "stage1":
                self.run_ingested_urls.clear()
        self._last_stage = stage_id

        if norm_url in self.run_ingested_urls:
            logger.info("URL already ingested in this run: %s. Short-circuiting.", source_url)
            return {
                "new_chunks_added": 0,
                "novelty_ratio": 0.0,
                "total_chunks_stage": self.store.leaf_count(stage_id),
                "already_attempted": True
            }

        source_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
        start_time = time.perf_counter()

        try:
            result: IngestResult = await self.lightrag._ingest_and_embed_sync(stage_id, query_id, source_url, text)

            if result and getattr(result, "new_chunks_added", 0) >= 0:
                self.run_ingested_urls.add(norm_url)

            elapsed = time.perf_counter() - start_time
            logger.info(
                "Ingested deep-research source successfully in %.3fs | stage=%s | added=%d | url=%s | hash=%s",
                elapsed, stage_id, result.new_chunks_added, source_url, source_hash
            )
            return result.to_dict()

        except Exception as e:
            elapsed = time.perf_counter() - start_time
            error_preview = str(e)[:100] + "..." if len(str(e)) > 100 else str(e)
            logger.error(
                "Ingestion CIRCUIT BREAKER triggered after %.3fs | stage=%s | url=%s | hash=%s | error=%s",
                elapsed, stage_id, source_url, source_hash, error_preview
            )
            return {
                "new_chunks_added": 0,
                "novelty_ratio": 0.0,
                "total_chunks_stage": self.store.leaf_count(stage_id),
                "failed": True,
                "error": error_preview
            }

    async def ingest_fast(self, stage_id: str, query_id: str, source_url: str, text: str) -> dict[str, Any]:
        """Index content lazily and perform background embedding."""
        if not all(isinstance(value, str) and value.strip() for value in (stage_id, query_id, source_url, text)):
            raise ValueError("stage_id, query_id, source_url, and text are required")
        stage_id = normalize_stage_id(stage_id)
        return await self.lightrag.ingest_fast(stage_id, query_id, source_url, text)

    async def retrieve(self, stage_id: str, query: str) -> dict[str, int | float]:
        if not stage_id.strip() or not query.strip():
            raise ValueError("stage_id and query are required")
        stage_id = normalize_stage_id(stage_id)

        import time
        start_time = time.perf_counter()

        async with self._lock:
            evidence = await self.agent.run_retrieval(stage_id, query)
            payload = self._read_temp()
            stage = payload.setdefault(stage_id, {})
            stage[query] = {
                f"chunk{index}": ev.text
                for index, ev in enumerate(evidence, 1)
            }
            stage[f"{query}__citations"] = {f"chunk{index}": ev.source_url for index, ev in enumerate(evidence, 1)}
            stage[f"{query}__routes"] = {f"chunk{index}": ev.route for index, ev in enumerate(evidence, 1)}
            self._write_temp(payload)

        elapsed = time.perf_counter() - start_time
        average = sum(ev.score for ev in evidence) / len(evidence) if evidence else 0.0
        result = RetrieveResult(len(evidence), average)

        logger.info(
            "Retrieved deep-research chunks in %.3fs | stage=%s | count=%d | query=%s",
            elapsed, stage_id, result.chunks_written, query[:60]
        )
        return result.to_dict()

    async def synthesize(self, stage_id: str, query: str) -> dict[str, object]:
        """Full agentic answer path with timing instrumentation."""
        stage_id = normalize_stage_id(stage_id)
        import time
        start_time = time.perf_counter()

        async with self._lock:
            res = await self.agent.run_answer(stage_id, query)

        elapsed = time.perf_counter() - start_time
        logger.info(
            "Synthesized deep-research answer in %.3fs | stage=%s | weak=%s",
            elapsed, stage_id, res.get("weak", False)
        )
        return res

    def set_llm(self, llm: object) -> None:
        """Inject an LLM hook (rewrite / synthesize / verify) for answer synthesis."""
        self.agent.llm = llm

    def _read_temp(self) -> dict[str, dict[str, dict[str, str]]]:
        if not self.temp_path.exists():
            return {}
        try:
            value = json.loads(self.temp_path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, json.JSONDecodeError) as exc:
            logger.warning("Ignoring unreadable deep-research temp file: %s", exc)
            return {}

    def _write_temp(self, payload: dict[str, object]) -> None:
        temporary = self.temp_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
        temporary.replace(self.temp_path)
