# Nexon

An AI coding assistant and agentic workspace that runs entirely on your Android phone via Termux — no cloud, no laptop required.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-private%20%2F%20in%20development-red.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-TBD-lightgrey.svg)](https://github.com/shivaww/Nexon)
<!-- NOTE: Using a static badge since the repository is private and live GitHub Actions / Release API badge calls will fail. This will be updated to a live shields.io counter when/if the repository goes public. -->
[![Downloads](https://img.shields.io/badge/downloads-0--active--dev-blue.svg)](https://github.com/shivaww/Nexon)

*Note: A live download counter will be enabled once the repository becomes public.*

---

## Architecture

Nexon integrates a high-performance Flutter-based UI with a local Python Bridge Server that acts as a secure Model Context Protocol (MCP) gateway. The deep research pipeline utilizes a local `llama-server` instance to execute hierarchical retrieval and document ingestion directly on-device.

```text
┌────────────────────────────────────────────────────────────────────────┐
│                          Nexon Flutter App                             │
│                                                                        │
│   ┌────────────────────────┐          ┌────────────────────────────┐   │
│   │    Chat Interface      │          │     ResearchPlanWidget     │   │
│   │  (Active Chat View)    │          │  (Live Status / Edit Plan) │   │
│   └───────────┬────────────┘          └─────────────┬──────────────┘   │
│               │                                     │                  │
│               │ Streams XML Tool Calls              │ Streams Events   │
│               ▼                                     ▼                  │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                   XML Parser & Circuit Breakers                │   │
│   │     (detectMalformedTags, zeroNoveltyStreak, loopCount < 30)   │   │
│   └───────────────────────────────┬────────────────────────────────┘   │
└───────────────────────────────────┼────────────────────────────────────┘
                                    │ HTTP / WebSocket Requests
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Python Bridge Server                            │
│           (termux_forge_bridge.py / mcp_server.py gateway)             │
│                                                                        │
│   ┌───────────────────────────────────┬────────────────────────────┐   │
│   │         WebSocket Server          │        HTTP Server         │   │
│   │            (Port 8765)            │        (Port 8390)         │   │
│   └─────────────────┬─────────────────┴─────────────┬──────────────┘   │
│                     │                               │                  │
│                     ▼                               ▼                  │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                 Deep Research RAG Orchestrator                 │   │
│   │              (deep_research.orchestrator)                      │   │
│   └────────┬────────────────────────────────────────────────┬──────┘   │
│            │                                                │          │
│            ▼                                                ▼          │
│   ┌─────────────────┐                              ┌─────────────────┐ │
│   │  Agentic Loop   ├────── Tavily Search ────────►│  Document Ingest│ │
│   │  (agentic_loop) │    (Escalation / Web Search) │ (lightrag_ingest) │ │
│   └────────┬────────┘                              └────────┬────────┘ │
│            │                                                │          │
│            │ Evaluates Sufficiency                          │ Splits,  │
│            ▼ (reflect / reformulate)                        ▼ Filters  │
│   ┌────────────────────────┐                      ┌──────────────────┐ │
│   │   Hybrid Retriever     │                      │ SQLite RAG Store │ │
│   │   (hybrid_retriever)   │◄──── Query/Fetch ───►│    (store.py)    │ │
│   │ (document->section->   │                      │  (WAL Mode /     │ │
│   │  chunk narrowing &     │                      │  Cascade Delete) │ │
│   │  numpy cosine similarity)                     └────────┬─────────┘ │
│   └────────┬───────────────┘                               │           │
│            │                                               │           │
│            │ Embeds Query/Chunk Texts                      │           │
│            ▼                                               ▼           │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │             Local Embedder Process (llama-server)              │   │
│   │        (Managed via embedder_lifecycle.py - Port 8080)         │   │
│   │      [Model: EmbeddingGemma (embeddinggemma-300m-Q4_0.gguf)]   │   │
│   └────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Exports
                                    ▼
                      ┌───────────────────────────┐
                      │    Markdown / DOCX File   │
                      │ (MarkdownParser / python- │
                      │ docx / generate_docx.py)  │
                      └───────────────────────────┘
```

---

## Detailed Features List

### 🔍 On-Device Hierarchical RAG (Retrieval-Augmented Generation)
*   **Hierarchical Narrowing Strategy**: Rather than performing expensive global search traversals on low-resource mobile hardware, the system splits documents into sections and sections into chunks (`lightrag_builder.py`). Ingestion and retrieval (`hybrid_retriever.py`) first identify relevant document-level nodes, narrow search scopes down to sections within those documents, and finally fetch candidate chunk-level leaf nodes. This prevents context pollution and speeds up local operations.
*   **Dynamic Query Routing**: Features a rule-based query classifier (`classify_query()`) that analyzes keyword densities and query lengths to select the optimal retrieval path:
    *   `document_first`: Tailored for synthesis, history, or comparison queries (e.g. containing terms like *versus*, *compare*, *overview*), narrowing candidate documents before looking at contents.
    *   `section_first`: Ideal for structural, procedural, or implementation-oriented queries (e.g. *how to*, *guide*, *architecture*).
    *   `direct`: Retrieves chunks directly across the database for exact factual lookups (e.g. *what is*, *code*, *error logs*).
*   **Vectorized Numpy Cosine Similarity**: In place of heavy external C++ vector libraries (like `sqlite-vec`) which suffer compile-time and runtime wheel incompatibilities on ARM64 Termux, Nexon uses plain SQLite BLOBs to store raw `float32` vector arrays (`store.py`). Candidates are loaded into memory and compared in a single, high-performance vectorized operation using 2D `numpy` matrix-vector multiplications (`_cosine_batch()`), yielding desktop-level retrieval speeds on Android.
*   **Text Cleaning & Quality Heuristics**: Ingested content is sanitized through a regex-based `TextCleaner` pipeline. Chunks are evaluated using a custom heuristic function (`_assess_chunk_quality()`) that calculates a quality score from `0.0` (junk) to `1.0` (high quality). It penalizes word repetition (to filter spam) and checks boilerplate term densities (e.g. cookies, login details, copyright footers) to ensure only valuable evidence is indexed.

### 🤖 Agentic Search & Reflection Loop
*   **Sufficiency Reflection**: An autonomous agentic controller wrapper (`agentic_loop.py`) evaluates the relevance and completeness of retrieved chunks against the original request. The system makes a local LLM or API call (`_reflect()`) returning a structured JSON decision:
    *   `sufficient`: The current evidence is complete; it proceeds directly to answer synthesis.
    *   `reformulate`: The search query was too broad or off-target; it rewrites the query and queries the retriever again.
    *   `broader_search`: The local RAG database lacks relevant data; it triggers a search engine escalation.
*   **Web Search Ingestion Escalation**: Upon reaching a `broader_search` decision, the engine calls a web search API (Tavily search fallback), fetches the top matching page results, cleans and splits their text layers, extracts novel chunks, and writes them directly into the active SQLite stage database on-the-fly. The retrieval loop then queries the updated database to pull in fresh, grounded context.
*   **Resource Guardrails**: Built for mobile constraints, the reflection loop checks available RAM using `psutil`. If virtual memory falls below a strict safety threshold (`RAM_HEADROOM_MB_THRESHOLD = 300MB`), reflection is bypassed entirely to avoid Out-Of-Memory (OOM) terminations by the Android OS. The loop also tracks token budget usage and terminates after 3 iterations by default.

### 🛡️ Safety & Execution Circuit Breakers
*   **Malformed Tag Interception**: A parser check in the Flutter app (`detectMalformedTags`) monitors LLM output text in real-time. If the model outputs a tool tag (like `<search_request>` or `<read_url>`) but fails to close it or formats it improperly, the system halts generation, throws a recovery error, and prevents the model from generating trailing garbage.
*   **Evidence Saturation Guard**: To prevent the model from wasting network bandwidth on repetitive web queries, the system calculates a cosine novelty check against existing embeddings (with a similarity threshold of `0.95`). If subsequent fetches add no new information, a system warning is injected into the prompt at 4 consecutive zero-novelty fetches, and the step is aborted at 8 fetches.
*   **Context Window Auto-Inference**: Rather than hardcoding context size limits for specific models, `getModelContextSize` inspects model names using structural regex rules (e.g., extracting trailing numbers like `-8192` or k-suffixes like `32k`). If it cannot resolve the name, it provides a safe, generous default of `32768` tokens to avoid blocking the user.
*   **Turn and Time Ceilings**: Enforces an absolute limit of 30 tool calls per stage, alongside global time budget tracking (`globalTimeBudget`) that monitors elapsed execution time to prevent infinite runaways.

### 🔌 Single-Instance Embedder Process Manager
*   **Race-Free Process Spawning**: Spawning the background `llama-server` is synchronized using cooperative Unix file locking (`fcntl.flock` on `~/.termux_forge_embedder.lock`), preventing race conditions if multiple tasks try to wake the server at the same time.
*   **Stale Port Auditing & Reaping**: Prior to launching the embedder, the manager checks port 8080. If another process is holding the port, it reads the recorded PID from `~/.termux_forge_embedder.pid` and reaps any stale `llama-server` process using `psutil`.
*   **Zero-Polling Idle Timeout**: The manager maintains a daemon thread (`_idle_loop()`) that sleeps using a thread event wait. Any client activity triggers `touch()`, extending the server's lifespan. If no requests are received for 120 seconds, the server terminates the `llama-server` process, freeing up memory when the app is idle.

### 🖥️ Native Permission Dialogs & Workspace Sandboxing
*   **Granular Command Approval**: Offers four levels of permission persistence (Allow Once, Allow for Chat, Always Allow, Block) managed via Flutter `SharedPreferences` (`shell_permission_v1`), giving the user absolute control over shell commands.
*   **Workspace Constraints**: The Python bridge normalizes incoming paths (`resolve_path()`) and relative directories to prevent double-prefixing errors. It executes commands inside the designated workspace root (`_agenticWorkspace`) to ensure operations remain sandboxed.

### 🗂️ Interactive Research UI & Multi-Format Export
*   **Progressive Lifecycle UI**: Integrates a clean, event-driven timeline showing the research pipeline. Events pulse during execution and transition smoothly between states. Users can click individual event rows to inspect execution payloads, tool inputs, or system warnings.
*   **Export Pipeline**: Generates structured Markdown text from the completed research plan or converts it into a Word Document (`.docx`) using a markdown-to-element parser and the `python-docx` library. It triggers native Android save dialogs via the Flutter `file_picker` package.

---

## Tech Stack

*   **Frontend UI**: Flutter (Dart), Material 3, Google Fonts
*   **State Management**: Provider
*   **Local Storage**: Flutter Secure Storage (credentials) & SharedPreferences (permissions)
*   **Backend Bridge**: Python 3 (websockets, aiohttp, requests, psutil, pypdf, python-docx, numpy)
*   **Local Embeddings**: `llama.cpp` (`llama-server`) & `EmbeddingGemma` (`embeddinggemma-300m-Q4_0.gguf`)
*   **Vector Database**: SQLite persistence (`ResearchStore` WAL mode, Cascade Deletes) + numpy vector similarity comparison.
    *   *Note: `sqlite-vec` was intentionally migrated away due to Termux/ARM64 wheel compilation incompatibilities. Vector comparison uses SQLite for metadata filtering and raw float32 BLOB storage, paired with numpy matrix math.*

---

## Getting Started

### Prerequisites
*   Android device running Android 7.0+ (API 24+)
*   **[Termux](https://f-droid.org/en/packages/com.termux/)** installed from F-Droid
*   Python 3.10+ in Termux
*   Flutter SDK (if compiling the APK from source)

### Installation & Setup

#### 1. Install & Configure the Termux Environment
Run the deep research environment setup script. This script updates packages, downloads the pre-built `llama.cpp` Android arm64 binaries, configures wrapper execution scripts, verifies `numpy` matrix calculations, and pulls down the `EmbeddingGemma` GGUF model:

```bash
# Clone the repository and run locally:
cd Nexon
chmod +x install_bridge.sh
./install_bridge.sh
```

#### 2. Start the Python Bridge Server
Start the bridge gateway (runs the WebSocket protocol on port `8765` and legacy HTTP endpoint on port `8390` concurrently):

```bash
cd ~/nexon_bridge
python3 mcp_server.py
```

#### 3. Run the App
Build Nexon from source or load the pre-built release APK onto your Android device, configure your Workspace Path in settings, and connect to the bridge.

---

## Project Status & Roadmap

Nexon is currently in active private development by a solo developer.
Key upcoming roadmap items:
*   [ ] Memory footprint and speed optimizations for low-end Android hardware.
*   [ ] Integration of broader local model choices for on-device reasoning/reflection.
*   [ ] Enhanced terminal session sharing and persistent task runtimes.

---

## License

License: **TBD** (Undecided / Under evaluation for future open-source release)

---

## Contributing

Not currently accepting external contributions. The repository is private.
