# Hierarchical RAG Architecture for Termux

The deep-research retrieval system is structured as an optimized, lightweight **Hierarchical RAG** designed for native Android/Termux environments. It replaces the graph-heavy approach with a structured, multi-stage retrieval flow that is fast, robust, and memory-efficient.

---

## Why Hierarchical RAG is the Best Default for Termux

1. **Minimal Memory footprint**: Graph-based approaches require large in-memory graphs or complex databases (e.g., Neo4j, networkx) that exceed Android's strict RAM guidelines. Hierarchical RAG operates entirely on **SQLite**, consuming less than 5MB of RAM.
2. **Speed & Efficiency**: Instead of slow entity/relation extraction prompts, Hierarchical RAG indexes documents, sections, and chunks in parallel. Embeddings are generated in batch, reducing startup and indexing time by up to 10x.
3. **Zero Heavy Dependencies**: Graph-aware packages (like LightRAG or NetworkX) often require complex compilation of C++ extensions, which routinely fails under Termux due to architecture and toolchain mismatches. This architecture relies only on pure Python, SQLite, and a standard fallback embedding pipeline.
4. **Context-Saving Precision**: Mobile LLMs (like Gemma-2B/9B running locally) have limited context windows. Standard retrieval yields brute-force chunks that waste tokens. Hierarchical RAG routes queries to focus on documents, sections, or individual chunks, ensuring only the highest-precision evidence is passed to the model.

---

## 1. Structured Database Tier (`rag/store.py`)
Metadata, structures, and vectors are persisted in SQLite using a strict three-tier hierarchy:
- **Documents Table**: Tracks global metadata, original source text, and document-level embeddings.
- **Sections Table**: Stores parsed semantic document sections (e.g. markdown headers, logical paragraphs) linked back to their parent document.
- **Chunks Table**: Contains the leaf chunks (overlapping word windows) mapped directly to their parent section.

*Incremental Re-ingestion*: Because tables enforce `ON DELETE CASCADE` constraints, updating a document simply requires deleting its row in the `documents` table. SQLite automatically cleans up all associated sections and chunks instantly, preventing database bloat and duplicates.

---

## 2. Section-Aware Chunking (`rag/chunking.py`)
Documents are split using a two-stage approach:
- **Semantic Sections**: The parser divides documents along markdown headers (e.g., `# Heading`). If markdown headings are missing or sparse, it falls back to paragraph grouping (grouping paragraphs to a target of ~600 words).
- **Overlapping Chunks**: Individual sections are split into overlapping word windows (e.g., target 220 words with 30 words overlap). This ensures context continuity across boundaries while avoiding overly large chunks.

---

## 3. Query Router and Multi-Stage Narrowing (`rag/hybrid_retriever.py`)
Queries are classified by a deterministic router into one of three modes:
- `document_first` (Broad/Synthesizing queries):
  - **Stage 1**: Ranks and selects candidate documents (`doc_top_k`).
  - **Stage 2**: Filters and selects candidate sections within those documents (`section_top_k`).
  - **Stage 3**: Selects candidate chunks from the best sections (`chunk_top_k`).
- `section_first` (Topic-focused queries):
  - **Stage 1**: Ranks and selects candidate sections across all documents (`section_top_k`).
  - **Stage 2**: Retrieves chunks within those sections (`chunk_top_k`).
- `direct` (Specific factual/keyword queries):
  - Ranks and retrieves chunks directly across the entire stage for high recall (`chunk_top_k`).

---

## 4. Reranking & Fusion
- **Hybrid Scorer**: Retrieved candidates are scored using a combination of vector similarity (70% weight) and query term lexical overlap (30% weight) to maintain precision.
- **Deduplication**: Chunks are deduplicated using fuzzy content matching (ignoring capitalization and spacing) to eliminate duplicate information.
- **Context Enrichment**: Retrieved chunks are enriched with document and section titles prior to presentation (e.g. `Document: <url> | Section: <title>`), providing the model with vital grounding cues.

---

## Configuration Knobs
Configure the orchestrator via constructor parameters or the following environment variables:
- `DR_CHUNK_WORDS`: Chunk word limit (default: 220)
- `DR_OVERLAP_WORDS`: Overlap word limit (default: 30)
- `DR_EMBEDDING_BATCH_SIZE`: Batch size for embedding generation (default: 16)
- `DR_DOCUMENT_TOP_K`: Document selection depth (default: 3)
- `DR_SECTION_TOP_K`: Section selection depth (default: 5)
- `DR_CHUNK_TOP_K` (or `DR_VECTOR_TOP_K`): Leaf chunk selection depth (default: 8)
- `DR_RERANK_DEPTH`: final evidence slice depth (default: 6)
- `DR_WEAK_THRESHOLD`: similarity threshold for weak evidence warning (default: 0.25)
- `DR_MAX_REVISIONS`: revision loop cap (default: 2)

---

## Public API (Unchanged)
- `ingest(stage_id, query_id, source_url, text) -> IngestResult`
- `retrieve(stage_id, query) -> RetrieveResult` (saves results & citations to `temp.json`)
- `synthesize(stage_id, query) -> {answer, evidence, sources, weak, revisions}`
- `config() -> dict[str, object]`
