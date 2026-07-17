"""Hierarchical RAG document builder.

Splits documents into sections and chunks, cleans incoming text using TextCleaner,
assesses chunk quality, embeds texts in batches, and saves results in SQLite.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any

from ..schemas import IngestResult
from .chunking import ChunkingConfig, split_into_sections, chunk_section
from .cleaner import TextCleaner
from .store import ResearchStore


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

    async def ingest(self, stage_id: str, query_id: str, source_url: str, text: str) -> IngestResult:
        # 1. Boilerplate cleaning
        cleaned_text = self.cleaner.clean(text)
        if not cleaned_text:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))

        # 2. Split document into sections
        sections_data = split_into_sections(cleaned_text)
        if not sections_data:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))

        # 3. Gather representations to embed and store structure
        all_texts_to_embed: list[str] = []

        # Document level representative text
        doc_words = re.findall(r"\S+", cleaned_text)
        doc_preview = " ".join(doc_words[:300])
        doc_embed_text = f"Document: {source_url}\n{doc_preview}"
        all_texts_to_embed.append(doc_embed_text)
        doc_emb_index = 0

        # Section and Chunk layout mapping
        parsed_sections = []
        current_text_index = 1

        for sec_idx, (sec_title, sec_content) in enumerate(sections_data):
            sec_words = re.findall(r"\S+", sec_content)
            sec_preview = " ".join(sec_words[:300])
            sec_embed_text = f"Section: {sec_title or f'Section {sec_idx+1}'}\n{sec_preview}"
            all_texts_to_embed.append(sec_embed_text)
            sec_emb_index = current_text_index
            current_text_index += 1

            # Generate chunks for this section
            sec_chunks = chunk_section(
                sec_content,
                chunk_words=self.config.chunk_words,
                overlap_words=self.config.overlap_words,
                min_chunk_words=self.config.min_chunk_words,
            )

            chunks_in_section = []
            for ch_idx, chunk_text_content in enumerate(sec_chunks):
                # Assess chunk quality: filter garbage/repetition
                quality = self._assess_chunk_quality(chunk_text_content)
                if quality < self.MIN_QUALITY_THRESHOLD:
                    continue

                # Prepend section heading context for better vector alignment and retrieval accuracy
                heading_context = f"[Section: {sec_title}] " if sec_title else ""
                enriched_chunk_text = f"{heading_context}{chunk_text_content}"

                all_texts_to_embed.append(enriched_chunk_text)
                chunk_emb_index = current_text_index
                current_text_index += 1
                chunks_in_section.append((ch_idx, enriched_chunk_text, chunk_emb_index))

            parsed_sections.append((sec_idx, sec_title, sec_content, sec_emb_index, chunks_in_section))

        # Check if we have any valid chunks left after quality filtering
        total_chunks = sum(len(sec[4]) for sec in parsed_sections)
        if total_chunks == 0:
            return IngestResult(0, 0.0, self.store.leaf_count(stage_id))

        # 4. Batch embed all gathered representations
        all_embeddings: list[list[float]] = []
        for i in range(0, len(all_texts_to_embed), self.embedding_batch_size):
            batch_texts = all_texts_to_embed[i : i + self.embedding_batch_size]
            batch_embs = await self.embedder.embed_texts(batch_texts)
            all_embeddings.extend(batch_embs)

        doc_embedding = all_embeddings[doc_emb_index]

        # 5. Novelty check against OTHER documents currently in this stage
        existing_chunks = self.store.all_chunks(stage_id)
        other_chunks = [ch for ch in existing_chunks if ch.source_url != source_url]
        other_vecs = [ch.embedding for ch in other_chunks]

        novel_chunks_count = 0

        # Calculate how many chunks are novel
        for _, _, _, _, chunks_in_section in parsed_sections:
            for _, _, chunk_emb_index in chunks_in_section:
                vector = all_embeddings[chunk_emb_index]
                is_novel = not other_vecs or all(
                    self._cosine(vector, ev) < self.DUPLICATE_THRESHOLD for ev in other_vecs
                )
                if is_novel:
                    novel_chunks_count += 1

        novelty_ratio = novel_chunks_count / total_chunks if total_chunks > 0 else 0.0

        # 6. Incremental Update: clear previous indexing for this document
        self.store.replace_source(stage_id, source_url)

        # 7. Add document
        self.store.add_document(stage_id, source_url, cleaned_text, doc_embedding, {})

        # 8. Add sections and their novel chunks
        new_chunks_added = 0
        for sec_idx, sec_title, sec_content, sec_emb_index, chunks_in_section in parsed_sections:
            sec_embedding = all_embeddings[sec_emb_index]
            sec_id = self.store.add_section(
                stage_id, source_url, sec_idx, sec_title, sec_content, sec_embedding, {}
            )

            for ch_idx, enriched_chunk_text, chunk_emb_index in chunks_in_section:
                vector = all_embeddings[chunk_emb_index]
                is_novel = not other_vecs or all(
                    self._cosine(vector, ev) < self.DUPLICATE_THRESHOLD for ev in other_vecs
                )
                if is_novel:
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

        return IngestResult(new_chunks_added, novelty_ratio, self.store.leaf_count(stage_id))

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
