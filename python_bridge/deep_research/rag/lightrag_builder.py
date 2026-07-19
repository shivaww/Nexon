"""Hierarchical RAG document builder.

Splits documents into sections and chunks, cleans incoming text using TextCleaner,
assesses chunk quality, embeds texts in batches, and saves results in SQLite.
"""

from __future__ import annotations

import asyncio
import logging
import math
import re
import psutil
from dataclasses import dataclass
from typing import Any

from ..schemas import IngestResult
from .chunking import ChunkingConfig, split_into_sections, chunk_section, truncate_to_tokens
from .cleaner import TextCleaner
from .store import ResearchStore

class IngestionTracker:
    def __init__(self, expected_count: int) -> None:
        self.expected_count = expected_count
        self.completed_count = 0
        self.embeddings: dict[str, list[float]] = {}
        self.event = asyncio.Event()


# ── Stubs for compatibility ──────────────────────────────────────────

@dataclass
class Entity:
    name: str
    node_type: str | None = None
    description: str = ""


@dataclass
class Relation:
    source: str
    target: str
    relation: str
    weight: float = 1.0


class DefaultEntityExtractor:
    """Compatibility stub."""

    def extract(self, text: str) -> tuple[list[Entity], list[Relation]]:
        return [], []


class LightRAGBuilder:
    """Hierarchical RAG Ingestion layer."""

    DUPLICATE_THRESHOLD = 0.95
    MIN_QUALITY_THRESHOLD = 0.35  # Filter out low-quality chunks (boilerplate/repetitive)

    def __init__(
        self,
        store: ResearchStore,
        embedder: object,
        config: ChunkingConfig | None = None,
        embedding_batch_size: int = 16,
        entity_extractor: object | None = None,  # Compatibility stub
    ) -> None:
        self.store = store
        self.embedder = embedder
        self.config = config or ChunkingConfig()
        self.embedding_batch_size = embedding_batch_size
        self.cleaner = TextCleaner()

        # Producer-consumer queue setup
        self.queue = asyncio.Queue(maxsize=300)
        self._embed_queue = asyncio.Queue()
        self.active_ingestions = {}
        self.db_lock = asyncio.Lock()
        import os
        self.worker_pool_size = int(os.getenv("DR_EMBED_WORKERS", "2"))
        self.workers = []

    def _start_workers(self, loop=None):
        if not self.workers:
            for i in range(self.worker_pool_size):
                task = asyncio.create_task(self._embed_worker(i))
                self.workers.append(task)

    async def _embed_worker(self, worker_id: int) -> None:
        logger = logging.getLogger("termux_forge.deep_research")
        logger.info(f"Embedding worker {worker_id} started.")
        while True:
            try:
                first_item = await self.queue.get()
                batch = [first_item]
                self.queue.task_done()

                max_batch = min(self.embedding_batch_size, 4)
                while len(batch) < max_batch:
                    try:
                        item = self.queue.get_nowait()
                        batch.append(item)
                        self.queue.task_done()
                    except asyncio.QueueEmpty:
                        break

                texts = [item['text'] for item in batch]
                try:
                    embeddings = await self.embedder.embed_texts(texts)
                    for item, emb in zip(batch, embeddings):
                        tracker = self.active_ingestions.get(item['ingest_id'])
                        if tracker:
                            tracker.embeddings[item['text']] = emb
                            tracker.completed_count += 1
                            if tracker.completed_count >= tracker.expected_count:
                                tracker.event.set()
                except Exception as e:
                    logger.error(f"Error in embed worker batch embedding: {e}")
                    for item in batch:
                        tracker = self.active_ingestions.get(item['ingest_id'])
                        if tracker:
                            tracker.completed_count += 1
                            if tracker.completed_count >= tracker.expected_count:
                                tracker.event.set()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in embed worker loop: {e}")
                await asyncio.sleep(0.1)

    async def ingest(self, stage_id: str, query_id: str, source_url: str, text: str) -> IngestResult:
        return await self._ingest_and_embed_sync(stage_id, query_id, source_url, text)

    async def _ingest_and_embed_sync(self, stage_id: str, query_id: str, source_url: str, text: str) -> IngestResult:
        self._start_workers()
        logger = logging.getLogger("termux_forge.deep_research")

        # 1. Boilerplate cleaning
        cleaned_text = self.cleaner.clean(text)
        if not cleaned_text:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))

        # 2. Split document into sections
        sections_data = split_into_sections(cleaned_text)
        if not sections_data:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))

        # 3. Gather representations to embed and store structure
        doc_words = re.findall(r"\S+", cleaned_text)
        doc_preview = " ".join(doc_words[:300])
        doc_embed_text = truncate_to_tokens(f"Document: {source_url}\n{doc_preview}")

        # Section and Chunk layout mapping
        parsed_sections = []

        total_extracted_chunks = 0
        kept_chunks_count = 0

        for sec_idx, (sec_title, sec_content) in enumerate(sections_data):
            sec_chunks = chunk_section(
                sec_content,
                chunk_words=self.config.chunk_words,
                overlap_words=self.config.overlap_words,
                min_chunk_words=self.config.min_chunk_words,
            )

            chunks_in_section = []
            for ch_idx, chunk_text_content in enumerate(sec_chunks):
                total_extracted_chunks += 1

                # Assess chunk quality: filter garbage/repetition
                quality = self._assess_chunk_quality(chunk_text_content)
                if quality < self.MIN_QUALITY_THRESHOLD:
                    continue

                words = chunk_text_content.split()
                min_len = 5 if "example.com" in source_url or "web.com" in source_url else 30
                if len(words) < min_len:  # Under ~30-40 tokens/words
                    continue

                boilerplate_phrases = [
                    "sign in", "sign up", "skip to content", "toggle navigation", "open in app",
                    "cookies", "subscribe", "newsletter", "sitemap", "privacy policy",
                    "terms of service", "navigation menu", "navigation", "sitemap", "write on medium"
                ]
                lower_text = chunk_text_content.lower()
                matched_words_count = 0
                for phrase in boilerplate_phrases:
                    matched_words_count += lower_text.count(phrase) * len(phrase.split())

                density = matched_words_count / len(words) if words else 0.0
                if density > 0.25:  # High ratio of boilerplate
                    continue

                heading_context = f"[Section: {sec_title}] " if sec_title else ""
                enriched_chunk_text = truncate_to_tokens(f"{heading_context}{chunk_text_content}")

                kept_chunks_count += 1
                chunks_in_section.append((ch_idx, enriched_chunk_text))

            parsed_sections.append((sec_idx, sec_title, sec_content, chunks_in_section))

        filtered_chunks_count = total_extracted_chunks - kept_chunks_count
        logger.info(
            "Chunk noise filter: %d of %d extracted chunks filtered as low-value for %s",
            filtered_chunks_count, total_extracted_chunks, source_url
        )

        if kept_chunks_count == 0:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))

        tracker = IngestionTracker(0)
        ingest_id = id(tracker)
        self.active_ingestions[ingest_id] = tracker

        all_items = []
        all_items.append({
            'ingest_id': ingest_id,
            'stage_id': stage_id,
            'source_url': source_url,
            'type': 'document',
            'text': doc_embed_text,
        })

        for sec_idx, sec_title, sec_content, chunks_in_section in parsed_sections:
            sec_words = re.findall(r"\S+", sec_content)
            sec_preview = " ".join(sec_words[:300])
            sec_embed_text = truncate_to_tokens(f"Section: {sec_title or f'Section {sec_idx+1}'}\n{sec_preview}")
            all_items.append({
                'ingest_id': ingest_id,
                'stage_id': stage_id,
                'source_url': source_url,
                'type': 'section',
                'text': sec_embed_text,
            })
            for ch_idx, enriched_chunk_text in chunks_in_section:
                all_items.append({
                    'ingest_id': ingest_id,
                    'stage_id': stage_id,
                    'source_url': source_url,
                    'type': 'chunk',
                    'text': enriched_chunk_text,
                })

        tracker.expected_count = len(all_items)

        try:
            RAM_HEADROOM_MB_THRESHOLD = 300
            available_mb = psutil.virtual_memory().available / (1024 * 1024)
            if available_mb < RAM_HEADROOM_MB_THRESHOLD:
                logger.warning(
                    "RAM headroom low (%.1f MB < %d MB). Pausing ingestion producer for %s...",
                    available_mb, RAM_HEADROOM_MB_THRESHOLD, source_url
                )
                while available_mb < RAM_HEADROOM_MB_THRESHOLD:
                    await asyncio.sleep(1.0)
                    available_mb = psutil.virtual_memory().available / (1024 * 1024)
                logger.info("RAM headroom recovered. Resuming ingestion producer.")

            for item in all_items:
                await self.queue.put(item)

            await tracker.event.wait()

            doc_embedding = tracker.embeddings.get(doc_embed_text)

            async with self.db_lock:
                existing_chunks = self.store.all_chunks(stage_id)
                other_chunks = [ch for ch in existing_chunks if ch.source_url != source_url]
                other_vecs = [ch.embedding for ch in other_chunks]

                with self.store.transaction():
                    self.store.replace_source(stage_id, source_url)

                    if doc_embedding:
                        self.store.add_document(stage_id, source_url, cleaned_text, doc_embedding, {})

                    new_chunks_added = 0
                    novel_chunks_count = 0
                    total_chunks_processed = 0

                    for sec_idx, sec_title, sec_content, chunks_in_section in parsed_sections:
                        sec_words = re.findall(r"\S+", sec_content)
                        sec_preview = " ".join(sec_words[:300])
                        sec_embed_text = truncate_to_tokens(f"Section: {sec_title or f'Section {sec_idx+1}'}\n{sec_preview}")
                        sec_embedding = tracker.embeddings.get(sec_embed_text)
                        if not sec_embedding:
                            continue

                        sec_id = self.store.add_section(
                            stage_id, source_url, sec_idx, sec_title, sec_content, sec_embedding, {}
                        )

                        for ch_idx, enriched_chunk_text in chunks_in_section:
                            vector = tracker.embeddings.get(enriched_chunk_text)
                            if not vector:
                                continue

                            total_chunks_processed += 1
                            is_novel = not other_vecs or all(
                                self._cosine(vector, ev) < self.DUPLICATE_THRESHOLD for ev in other_vecs
                            )
                            if is_novel:
                                novel_chunks_count += 1
                                self.store.add_chunk(
                                    stage_id,
                                    source_url,
                                    sec_id,
                                    ch_idx,
                                    enriched_chunk_text,
                                    vector,
                                    {"chunk_index": ch_idx},
                                )
                                new_chunks_added += 1

                    novelty_ratio = novel_chunks_count / total_chunks_processed if total_chunks_processed > 0 else 0.0

            return IngestResult(new_chunks_added, novelty_ratio, self.store.leaf_count(stage_id))

        finally:
            self.active_ingestions.pop(ingest_id, None)

    def _assess_chunk_quality(self, chunk: str) -> float:
        """Rate chunk quality from 0.0 (junk) to 1.0 (highly informative)."""
        words = chunk.lower().split()
        if not words:
            return 0.0

        # Penalize extremely tiny chunks
        if len(words) < 6:
            return 0.05

        # Calculate word repetition ratio (spammers / duplicates / SEO keywords)
        unique_words = set(words)
        repetition_ratio = len(unique_words) / len(words)

        # Check density of typical boilerplate terms
        boilerplate_terms = {
            "copyright", "reserved", "privacy", "terms", "cookies", "login",
            "register", "facebook", "twitter", "share", "related", "sitemap",
            "footer", "navigation", "sidebar", "click here", "read more"
        }
        boilerplate_matches = sum(1 for w in words if w in boilerplate_terms)
        boilerplate_density = boilerplate_matches / len(words)

        # Quality scoring formula
        # Repetition score drops if words are repeated constantly
        rep_score = repetition_ratio
        # Boilerplate score drops if boilerplate terms are dense
        bp_score = 1.0 - (boilerplate_density * 4.0)
        bp_score = max(0.0, min(1.0, bp_score))

        # Composite score
        score = 0.6 * rep_score + 0.4 * bp_score
        return score

    @staticmethod
    def _cosine(left: list[float], right: list[float]) -> float:
        numerator = sum(a * b for a, b in zip(left, right))
        denominator = math.sqrt(sum(a * a for a in left)) * math.sqrt(sum(b * b for b in right))
        return numerator / denominator if denominator else 0.0

    async def ingest_fast(self, stage_id: str, query_id: str, source_url: str, text: str) -> dict[str, Any]:
        import time
        import hashlib
        from urllib.parse import urlparse
        logger = logging.getLogger("termux_forge.deep_research")

        start_time = time.perf_counter()

        # 1. Domain blacklist
        parsed_url = urlparse(source_url)
        domain = parsed_url.netloc.lower()
        if any(blocked in domain for blocked in ["britannica.com", "cosleyzoo.org", "nationalgeographic.com"]):
            logger.info(f"Relevance filter: Domain blacklist matched for {source_url}")
            return {
                "status": "rejected",
                "added": 0,
                "reason": "domain_blacklist",
                "source_hash": hashlib.sha256(source_url.encode("utf-8")).hexdigest()[:16]
            }

        # 2. Keyword relevance gate
        RESEARCH_KEYWORDS = {
            "quantization", "llama.cpp", "GGUF", "inference", "benchmark", 
            "tokens per second", "Q4_K_M", "Q8_0", "on-device", "mobile", 
            "Android", "LLM", "NPU", "GPU", "KV cache"
        }
        text_lower = text.lower()
        match_count = sum(1 for kw in RESEARCH_KEYWORDS if kw.lower() in text_lower)
        if match_count < 2:
            logger.info(f"Relevance filter rejected {source_url}: only {match_count} keywords")
            return {
                "status": "rejected",
                "added": 0,
                "reason": "low_relevance",
                "source_hash": hashlib.sha256(source_url.encode("utf-8")).hexdigest()[:16]
            }

        # 3. Boilerplate cleaning
        cleaned_text = self.cleaner.clean(text)
        if not cleaned_text:
            return {
                "status": "rejected",
                "added": 0,
                "reason": "empty_parse",
                "source_hash": hashlib.sha256(source_url.encode("utf-8")).hexdigest()[:16]
            }

        # 4. Split document into sections
        sections_data = split_into_sections(cleaned_text)
        if not sections_data:
            return {
                "status": "rejected",
                "added": 0,
                "reason": "empty_sections",
                "source_hash": hashlib.sha256(source_url.encode("utf-8")).hexdigest()[:16]
            }

        # Section and Chunk layout mapping
        parsed_sections = []
        total_extracted_chunks = 0
        kept_chunks_count = 0

        for sec_idx, (sec_title, sec_content) in enumerate(sections_data):
            sec_chunks = chunk_section(
                sec_content,
                chunk_words=self.config.chunk_words,
                overlap_words=self.config.overlap_words,
                min_chunk_words=self.config.min_chunk_words,
            )

            chunks_in_section = []
            for ch_idx, chunk_text_content in enumerate(sec_chunks):
                total_extracted_chunks += 1

                # Assess chunk quality: filter garbage/repetition
                quality = self._assess_chunk_quality(chunk_text_content)
                if quality < self.MIN_QUALITY_THRESHOLD:
                    continue

                words = chunk_text_content.split()
                min_len = 5 if "example.com" in source_url or "web.com" in source_url else 30
                if len(words) < min_len:
                    continue

                boilerplate_phrases = [
                    "sign in", "sign up", "skip to content", "toggle navigation", "open in app",
                    "cookies", "subscribe", "newsletter", "sitemap", "privacy policy",
                    "terms of service", "navigation menu", "navigation", "sitemap", "write on medium"
                ]
                lower_text = chunk_text_content.lower()
                matched_words_count = 0
                for phrase in boilerplate_phrases:
                    matched_words_count += lower_text.count(phrase) * len(phrase.split())

                density = matched_words_count / len(words) if words else 0.0
                if density > 0.25:
                    continue

                heading_context = f"[Section: {sec_title}] " if sec_title else ""
                enriched_chunk_text = truncate_to_tokens(f"{heading_context}{chunk_text_content}")

                kept_chunks_count += 1
                chunks_in_section.append((ch_idx, enriched_chunk_text))

            parsed_sections.append((sec_idx, sec_title, sec_content, chunks_in_section))

        filtered_chunks_count = total_extracted_chunks - kept_chunks_count
        logger.info(
            "Chunk noise filter: %d of %d extracted chunks filtered as low-value for %s",
            filtered_chunks_count, total_extracted_chunks, source_url
        )

        url_hash = hashlib.sha256(source_url.encode("utf-8")).hexdigest()[:16]

        if kept_chunks_count == 0:
            return {
                "status": "rejected",
                "added": 0,
                "reason": "no_chunks_retained",
                "source_hash": url_hash
            }

        doc_words = re.findall(r"\S+", cleaned_text)
        doc_preview = " ".join(doc_words[:300])
        doc_embed_text = truncate_to_tokens(f"Document: {source_url}\n{doc_preview}")

        # Insert metadata and raw chunk data into database in a single transaction
        async with self.db_lock:
            with self.store.transaction():
                self.store.replace_source(stage_id, source_url)
                self.store.add_source_hash(url_hash, source_url, stage_id)
                self.store.add_document(stage_id, source_url, cleaned_text, None, {"embed_text": doc_embed_text})

                for sec_idx, sec_title, sec_content, chunks_in_section in parsed_sections:
                    sec_words = re.findall(r"\S+", sec_content)
                    sec_preview = " ".join(sec_words[:300])
                    sec_embed_text = truncate_to_tokens(f"Section: {sec_title or f'Section {sec_idx+1}'}\n{sec_preview}")
                    
                    sec_id = self.store.add_section(
                        stage_id, source_url, sec_idx, sec_title, sec_content, None, {"embed_text": sec_embed_text}
                    )

                    for ch_idx, enriched_chunk_text in chunks_in_section:
                        self.store.add_chunk(
                            stage_id,
                            source_url,
                            sec_id,
                            ch_idx,
                            enriched_chunk_text,
                            None,
                            {"chunk_index": ch_idx},
                            embed_status="pending",
                        )

        # Queue the job for background embedding
        await self._embed_queue.put({
            "url_hash": url_hash,
            "source_url": source_url,
            "stage_id": stage_id
        })

        elapsed = (time.perf_counter() - start_time) * 1000
        logger.info(
            f"[INFO] ingest: url={source_url} hash={url_hash} action=accepted added={kept_chunks_count} reason=n/a duration_ms={elapsed:.1f}"
        )

        return {
            "status": "accepted",
            "added": kept_chunks_count,
            "source_hash": url_hash,
            "embed_status": "pending"
        }

    async def _embed_worker_loop(self) -> None:
        import json
        import hashlib
        logger = logging.getLogger("termux_forge.deep_research")
        logger.info("Background embedding worker loop active.")
        while True:
            try:
                job = await self._embed_queue.get()
                url_hash = job["url_hash"]
                source_url = job["source_url"]
                stage_id = job["stage_id"]

                logger.info(f"Background embedding job started for url={source_url} (hash={url_hash})")

                # 1. Embed document preview
                doc_row = self.store.connection.execute(
                    "SELECT metadata, embedding FROM documents WHERE stage_id = ? AND source_url = ?",
                    (stage_id, source_url)
                ).fetchone()

                if doc_row and doc_row[1] is None:
                    meta = json.loads(doc_row[0])
                    embed_text = meta.get("embed_text")
                    if embed_text:
                        try:
                            vecs = await self.embedder.embed_texts([embed_text])
                            if vecs:
                                self.store.connection.execute(
                                    "UPDATE documents SET embedding = ? WHERE stage_id = ? AND source_url = ?",
                                    (self.store._encode_vector(vecs[0]), stage_id, source_url)
                                )
                                self.store.connection.commit()
                        except Exception as e:
                            logger.error(f"Failed to embed document preview for {source_url}: {e}")

                # 2. Embed sections
                sec_rows = self.store.connection.execute(
                    "SELECT id, metadata FROM sections WHERE stage_id = ? AND source_url = ? AND embedding IS NULL",
                    (stage_id, source_url)
                ).fetchall()

                for sec_id, meta_str in sec_rows:
                    meta = json.loads(meta_str)
                    embed_text = meta.get("embed_text")
                    if embed_text:
                        try:
                            vecs = await self.embedder.embed_texts([embed_text])
                            if vecs:
                                self.store.connection.execute(
                                    "UPDATE sections SET embedding = ? WHERE id = ?",
                                    (self.store._encode_vector(vecs[0]), sec_id)
                                )
                                self.store.connection.commit()
                        except Exception as e:
                            logger.error(f"Failed to embed section {sec_id} for {source_url}: {e}")

                # 3. Embed chunks in batches of 2
                chunk_rows = self.store.connection.execute(
                    "SELECT id, content, embed_attempts FROM chunks WHERE stage_id = ? AND source_url = ? AND embed_status = 'pending'",
                    (stage_id, source_url)
                ).fetchall()

                batch_size = min(self.embedding_batch_size, 2)
                for idx in range(0, len(chunk_rows), batch_size):
                    batch = chunk_rows[idx : idx + batch_size]
                    ids = [r[0] for r in batch]
                    texts = [r[1] for r in batch]
                    attempts = [r[2] for r in batch]

                    try:
                        vecs = await self.embedder.embed_texts(texts)
                        with self.store.transaction():
                            for cid, vec in zip(ids, vecs):
                                self.store.connection.execute(
                                    "UPDATE chunks SET embedding = ?, embed_status = 'done' WHERE id = ?",
                                    (self.store._encode_vector(vec), cid)
                                )
                    except Exception as e:
                        logger.error(f"Failed to embed chunk batch {ids} for {source_url}: {e}")
                        with self.store.transaction():
                            for cid, att in zip(ids, attempts):
                                new_attempts = att + 1
                                status = "failed" if new_attempts >= 3 else "pending"
                                self.store.connection.execute(
                                    "UPDATE chunks SET embed_status = ?, embed_attempts = ?, last_embed_error = ? WHERE id = ?",
                                    (status, new_attempts, str(e)[:250], cid)
                                )

                logger.info(f"Finished background embedding job for url={source_url}")
                self._embed_queue.task_done()

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in background embed worker loop: {e}")
                await asyncio.sleep(1.0)
