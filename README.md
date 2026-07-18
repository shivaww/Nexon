# Nexon

An AI-powered mobile coding IDE and agentic workspace that runs entirely on your Android phone via Termux — no cloud, no laptop required.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-private%20%2F%20in%20development-red.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-TBD-lightgrey.svg)](https://github.com/shivaww/Nexon)
<!-- NOTE: Using a static badge since the repository is private and live GitHub Actions / Release API badge calls will fail. This will be updated to a live shields.io counter when/if the repository goes public. -->
[![Downloads](https://img.shields.io/badge/downloads-0--active--dev-blue.svg)](https://github.com/shivaww/Nexon)

*Note: A live download counter will be enabled once the repository becomes public.*

---

## System Architecture

Nexon integrates a high-performance Flutter-based UI with a local Python Bridge Server that acts as a secure Model Context Protocol (MCP) gateway. The deep research pipeline utilizes a local `llama-server` instance to execute hierarchical retrieval and document ingestion directly on-device.

```text
+------------------------------------------------------------------------+
|                          Nexon Flutter App                             |
|                                                                        |
|  [Left Sidebar: File Explorer/Agents] [Right Sidebar: Context/Memory]  |
|                                                                        |
|  [Center Tabs: Chat Screen | Code Editor | Terminal Emulator | Todos]  |
|                                                                        |
|  [Specialized Widgets: ResearchPlanWidget (Deep Research Lifecycle)]   |
+───────────────────────────────────┬────────────────────────────────────+
                                    │
                                    │ Streams XML Tool Calls
                                    ▼
+────────────────────────────────────────────────────────────────────────+
|                   XML Tool Parser & Circuit Breakers                   |
|   (detectMalformedTags, zeroNoveltyStreak, getModelContextSize, etc.)  |
+───────────────────────────────────┬────────────────────────────────────+
                                    │
                                    │ HTTP (:8390) / WebSocket (:8765)
                                    ▼
+────────────────────────────────────────────────────────────────────────+
|                    Python Bridge Server Gateway                        |
|          (termux_forge_bridge.py / mcp_server.py wrapper)              |
+───────────────────────────────────┬────────────────────────────────────+
                                    │
                                    │ Coordinates
                                    ▼
+────────────────────────────────────────────────────────────────────────+
|                   Deep Research RAG Orchestration                      |
|                                                                        |
|    +───────────────────+   Tavily Web Search   +──────────────────+    |
|    |   Agentic Loop    |──────────────────────►| Document Ingest  |    |
|    |  (agentic_loop)   |                       | (lightrag_build) |    |
|    +─────────┬─────────+                       +────────┬─────────+    |
|              │ sufficiency                              │              |
|              │ check                                    │ splits &     |
|              ▼                                          ▼ filters      |
|    +───────────────────+                       +──────────────────+    |
|    | Hybrid Retriever  |◄──── Query/Fetch ────►| SQLite RAG Store |    |
|    | (document->       |                       | (store.py database|    |
|    |  section->chunk)  |                       | with WAL mode)   |    |
|    +─────────┬─────────+                       +──────────────────+    |
|              │                                                         |
|              │ Embeds Query & Chunk Texts                              |
|              ▼                                                         |
|    +──────────────────────────────────────────────────────────────+    |
|    |            Local Embedder Manager (llama-server)             |    |
|    |       (embedder_lifecycle.py - EmbeddingGemma - Port 8080)   |    |
|    +──────────────────────────────────────────────────────────────+    |
+───────────────────────────────────┬────────────────────────────────────+
                                    │
                                    │ Element Render & Export
                                    ▼
+────────────────────────────────────────────────────────────────────────+
|                     Word DOCX / Markdown Export                        |
|       (generate_docx.py -> Android native file download dialog)        |
+------------------------------------------------------------------------+
```

---

## Core IDE Workstation & UI Features

Nexon transforms a mobile screen into a multi-pane development environment using collapsible panels, responsive layouts, and glassmorphism styling:

*   **Multi-Pane collapsible IDE layout**: Collapsible left sidebar (File Explorer + active agents rail), collapsible right sidebar (Context panel / Active memory / Cost tracker / settings), center tabbed pane (Chat view and inline file editor), and collapsible bottom terminal emulator.
*   **Onboarding Setup Wizard**: A 5-step onboarding screen (`onboarding_screen.dart`) that handles API provider credentials, local bridge connectivity verification, default reasoning model configurations, and target workspace mapping.
*   **Agent Observability Dashboard**: A tabbed analytics dashboard (`agent_observability_screen.dart`) showing active/idle agent counts, runtime stopwatches, API call cost accumulation, and real-time execution activity logs per agent.
*   **Interactive Todo Dashboard**: A priority-coded dashboard (`todo_dashboard_screen.dart`) supporting subtask tracking, completion percentages, assigned agent indicators, and status filtering (Pending, In Progress, Completed, Blocked).
*   **Inline File Explorer & Code Editor**: Integrated workspace browser supporting directory expansions, code syntax styling, and floating quick-command triggers.
*   **Local Terminal Emulator**: Full shell interface with Termux access, executing builds, running compilers, and monitoring background scripts.

---

## The 11 Operational Modes

Nexon maps the user interaction loop into 11 specialized modes depending on the task:

| Mode | Key | Icon | Description |
| :--- | :--- | :--- | :--- |
| **Code** | `code` | `Icons.code_rounded` | Write, edit, refactor, and generate code files with AI assistance. |
| **Architect** | `architect` | `Icons.architecture_rounded` | Design software architecture, outline class diagrams, and structure folders. |
| **Debug** | `debug` | `Icons.bug_report_rounded` | Perform systematic trace logs analysis and provide fixes for errors. |
| **Ask** | `ask` | `Icons.question_answer_rounded` | General developer Q&A, documentation lookups, and conceptual questions. |
| **Review** | `review` | `Icons.rate_review_rounded` | Perform code reviews, detect bottlenecks, and suggest best practices. |
| **Deploy** | `deploy` | `Icons.rocket_launch_rounded` | Run builds, run tests, and execute release deployments (e.g. Firebase). |
| **Research** | `research` | `Icons.biotech_rounded` | Execute linear deep RAG pipelines over local project files and web sources. |
| **Test** | `test` | `Icons.science_rounded` | Generate, edit, execute, and verify unit and widget test suites. |
| **Document** | `document` | `Icons.description_rounded` | Document codebases, write READMEs, and generate comments. |
| **Security** | `security` | `Icons.shield_rounded` | Audit command permissions, check for destructive code, and scan dependencies. |
| **Battle** | `battle` | `Icons.compare_arrows_rounded` | Compare reasoning models side-by-side in real-time. |

---

## Deep Research & RAG Architecture

When operating in **Research** mode, Nexon triggers a linear, high-performance RAG pipeline on-device:

### 1. Hierarchical Narrowing Strategy
*   **Doc → Section → Chunk Tiers**: Instead of executing heavy global graph traversals, the system splits documents into sections and sections into chunks (`lightrag_builder.py`).
*   **Semantic Routing**: It uses a classifier (`classify_query()`) in `hybrid_retriever.py` to route queries:
    *   `document_first`: Tailored for broad synthesis and comparison queries.
    *   `section_first`: Tailored for procedural guides or implementation details.
    *   `direct`: Retrieves chunks directly across the store for exact factual matching (highest precision).

### 2. Pure On-Device Vector Store
*   **Plain SQLite BLOB storage**: Vector embeddings are stored as little-endian `float32` byte arrays in a local SQLite database (`store.py`).
*   **Vectorized Numpy Similarity**: During retrieval, candidate vectors are stacked into a 2D `numpy` array, and a vectorized batch dot product (`_cosine_batch()`) computes similarities instantly in one operation, avoiding per-row Python loop overhead.

### 3. Agentic Search & Reflection Loop
*   **Sufficiency checks**: The agentic controller wrapper (`agentic_loop.py`) evaluates retrieved chunks. If the context is insufficient, it reformulates the query (`_reflect()`) or triggers a Tavily search escalation.
*   **Ingestion Pipeline**: Web results are parsed, cleaned, and ingested back into the active stage database.
*   **OOM Safeguard**: Bypasses reflection if available virtual memory (`psutil`) falls below 300MB, protecting Android from OOM process termination.

### 4. Managed Embedder Process Manager
*   **Process Control**: The manager (`embedder_lifecycle.py`) launches `llama-server` with `EmbeddingGemma` (`embeddinggemma-300m-Q4_0.gguf`).
*   **Concurrency Guard**: Prevents concurrent spawn conflicts using file locking (`fcntl.flock`).
*   **Timeout Daemon**: Shuts down the local embedder after 120 seconds of inactivity to conserve phone battery.

---

## Safety & Execution Circuit Breakers

*   **Malformed Tag Interception**: Real-time parsing (`detectMalformedTags`) in the Flutter app intercepts malformed XML tool tags (unclosed or misaligned), halting generation to save token limits.
*   **Evidence Saturation Guard**: Triggers warning messages at 4 consecutive redundant fetches (evaluated via `0.95` similarity thresholds) and halts RAG ingestion completely at 8.
*   **Model Name Window Inference**: `getModelContextSize` extracts the model context sizes structurally (e.g. `llama3-8b-8192` → 8,192), avoiding hardcoded API vendor blocks.
*   **Hard Loop Ceilings**: Enforces an absolute ceiling of 30 tool calls per stage, alongside global time budget tracking (`globalTimeBudget`).

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
