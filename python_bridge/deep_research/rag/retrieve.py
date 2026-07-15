"""Stage-scoped Tier 1 then Tier 0 hierarchical retrieval."""

from __future__ import annotations

from .hierarchy import cosine
from .store import ResearchStore


class HierarchicalRetriever:
    def __init__(self, store: ResearchStore, embedder: object, source_limit: int = 5, chunk_limit: int = 8) -> None:
        self.store = store
        self.embedder = embedder
        self.source_limit = source_limit
        self.chunk_limit = chunk_limit

    async def retrieve(self, stage_id: str, query: str) -> list[tuple[str, float]]:
        query_vector = (await self.embedder.embed_texts([query]))[0]
        sources = self.store.nodes(stage_id, 1)
        ranked_sources = sorted(
            ((node, cosine(query_vector, node.embedding)) for node in sources), key=lambda item: item[1], reverse=True
        )[:self.source_limit]
        source_urls = [node.source_url for node, _ in ranked_sources if node.source_url]
        leaves = self.store.nodes(stage_id, 0, source_urls)
        ranked_leaves = sorted(
            ((node.content, cosine(query_vector, node.embedding)) for node in leaves), key=lambda item: item[1], reverse=True
        )[:self.chunk_limit]
        return ranked_leaves
