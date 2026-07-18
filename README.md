# Nexon

An AI-powered mobile coding IDE and agentic workspace that runs entirely on your Android phone via Termux — no cloud, no laptop required.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-private%20%2F%20in%20development-red.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-TBD-lightgrey.svg)](https://github.com/shivaww/Nexon)
<!-- NOTE: Using a static badge since the repository is private and live GitHub Actions / Release API badge calls will fail. This will be updated to a live shields.io counter when/if the repository goes public. -->
[![Downloads](https://img.shields.io/badge/downloads-0--active--dev-blue.svg)](https://github.com/shivaww/Nexon)

*Note: A live download counter will be enabled once the repository becomes public.*

---

## Workspace Architecture

Nexon integrates a high-performance Flutter-based UI with a local Python Bridge Server that acts as a secure Model Context Protocol (MCP) gateway. The deep research pipeline utilizes a local `llama-server` instance to execute hierarchical retrieval and document ingestion directly on-device.

```text
=========================================================================================
                                NEXON MOBILE WORKSTATION
=========================================================================================

  +-----------------------------------------------------------------------------------+
  |                             Flutter UI (TermuxForge)                              |
  |                                                                                   |
  |  +--------------------+  +----------------------+  +---------------------------+  |
  |  |    IDE Toolsets    |  |     Visualizers      |  |    Artifact Renderer      |  |
  |  |                    |  |                      |  |                           |  |
  |  |  * Inline Chat     |  |  * SvgDiagramWidget  |  |  * HtmlArtifactWidget     |  |
  |  |  * Code Editor     |  |    (Pinch & Zoom /   |  |  * FileArtifactWidget     |  |
  |  |  * Termux Shell    |  |     Copy Code)       |  |  * DocxArtifactWidget     |  |
  |  |  * File Explorer   |  |  * Latex Math Equations|  |  * MdArtifactWidget       |  |
  |  |  * Todo Dashboard  |  |  * Interactive Charts|  |    (Native Android Save)  |  |
  |  |  * Observability   |  |                      |  |                           |  |
  |  +---------┬----------+  +----------------------+  +---------------------------+  |
  |            │                                                                      |
  |            │ Streams Chat Response (XML Tag Interception)                         |
  |            ▼                                                                      |
  |  +-----------------------------------------------------------------------------+  |
  |  |                        XML Parser & Safety circuit breakers                 |  |
  |  |    (detectMalformedTags, zeroNoveltyStreak, loopCount, globalTimeBudget)    |  |
  |  +-------------------------------------┬---------------------------------------+  |
  +────────────────────────────────────────┼──────────────────────────────────────────+
                                           │ WebSocket (:8765) / HTTP (:8390)
                                           ▼
  +───────────────────────────────────────────────────────────────────────────────────+
  |                           Python Bridge Server Gateway                            |
  |                         (termux_forge_bridge.py Main)                             |
  |                                                                                   |
  |  +-----------------------------------------------------------------------------+  |
  |  |                             XML Tool Tag Execution                          |  |
  |  |                                                                             |  |
  |  |   <tool_request>  ===>  Methods: file_read, file_write, str_replace,        |  |
  |  |                         find_paths, run_command, git_status, etc.           |  |
  |  +─────────────────────────────────────┬───────────────────────────────────────+  |
  |                                        │
  |                                        │ Coordinates
  |                                        ▼
  |  +─────────────────────────────────────────────────────────────────────────────+  |
  |  |                       Deep Research RAG Pipelines                           |  |
  |  |                                                                             |  |
  |  |   * LangGraphRAGOrchestrator: Linear pipeline controller                    |  |
  |  |   * Agentic Loop: Reflect / Reformulate / Ingest (Tavily search escalation) |  |
  |  |   * Hybrid Retriever: Dynamic Query Routing (doc -> section -> chunk)       |  |
  |  |   * ResearchStore: SQLite metadata and numpy matrix dot-product similarity   |  |
  |  |   * Ingestion Layer: Boilerplate text cleaning and novelty validation       |  |
  |  +─────────────────────────────────────┬───────────────────────────────────────+  |
  |                                        │
  |                                        │ Embeds Queries/Text Elements
  |                                        ▼
  |  +─────────────────────────────────────────────────────────────────────────────+  |
  |  |                         Managed Embedder Lifecycle                          |  |
  |  |                                                                             |  |
  |  |   * ServerLifecycleManager: flock concurrency locks, orphan reaping         |  |
  |  |   * Local Server: llama-server process (Port 8080) with 120s idle shutdown  |  |
  |  |   * Embeddings Model: EmbeddingGemma (embeddinggemma-300m-Q4_0.gguf)        |  |
  |  +─────────────────────────────────────────────────────────────────────────────+  |
  +────────────────────────────────────────┬──────────────────────────────────────────+
                                           │ Exports File
                                           ▼
                             +───────────────────────────+
                             |    Markdown / Word DOCX   |
                             | (Android Downloads folder)|
                             +───────────────────────────+
```

---

## Detailed Features

### 🎨 Fully Fullscreen SVGs & Interactive Visuals
*   **SvgDiagramWidget Rendering**: Intercepts ````svg ... ```` blocks from the chat stream, cleans and normalizes height/width constraints to `100%`, strips raw text surrounding the tags, and renders vector diagrams natively using `flutter_svg`.
*   **Pinch-to-Zoom & Pan Viewers**: Wraps rendered SVGs in a Flutter `InteractiveViewer` supporting multi-touch pinch-to-zoom scaling, scroll-panning, and fullscreen overlay view modes.
*   **Inline Code Inspection**: Provides copy-to-clipboard code tools directly on the visual panel to copy the raw SVG source code.
*   **Latex Equation Rendering**: Automatically compiles and renders complex math, statistical, and workflow formula diagrams in markdown blocks using LaTeX notation.

### 🗂️ Artifact Rendering & Management System
*   **HtmlArtifactWidget**: Renders sandboxed HTML, CSS, and Javascript previews in a local web view, enabling live design prototyping directly on the phone.
*   **FileArtifactWidget**: Displays proposed file additions or code edits with color syntax highlighting.
*   **DocxArtifactWidget & MdArtifactWidget**: Displays report drafts, code reviews, and project documentation. Clicking downloads transfers the output files directly to the Android `Downloads` directory.

### 🖥️ Core IDE Workstation Tools
*   **Inline Chat**: Stateful streaming assistant pane with provider routing (Anthropic, OpenAI, Google Gemini, OpenRouter) and custom model selections.
*   **Code Editor**: Clean file editor displaying text content, editing lines, saving changes locally, and integrating with git.
*   **Termux Shell & Command Terminal**: Collapsible console panel that launches safe bash processes inside Termux, displaying stdout/stderr in real-time.
*   **File Explorer**: Sidebar navigation rail supporting file and folder lookups, tree views, and creation/deletion.
*   **Todo Dashboard**: Track tasks by priority (Low, Medium, High, Critical) and status (Pending, In Progress, Completed, Blocked), progress bars per task based on completed subtasks, agent assignment dropdowns, and dynamic filter controls.
*   **Agent Observability**: Track active agents (Orchestrator, Coder, Architect, Debugger, Reviewer, Background Worker, Security), active models, total session API cost, tool count metrics, execution runtimes, and real-time execution logs.

---

## Operational Modes

Nexon maps the user interaction loop into 6 primary operational modes:

1.  **Code** (`code`): Write, edit, refactor, and generate code files with AI assistance.
2.  **Architect** (`architect`): Design software architecture, outline class diagrams, and structure folders.
3.  **Debug** (`debug`): Perform systematic trace logs analysis and provide fixes for errors.
4.  **Ask** (`ask`): General developer Q&A, documentation lookups, and conceptual questions.
5.  **Review** (`review`): Perform code reviews, detect bottlenecks, and suggest best practices.
6.  **Plan** (`plan`): Break down tasks, estimate effort, and create actionable plans.

---

## XML Tool Tag Protocol

Nexon uses structured XML tags inside standard LLM text completions to trigger local device tool executions. The model outputs exactly one tool request per turn, halts generation, and waits for results.

### Expected XML Syntax
```xml
<tool_request>
  <method>file_read</method>
  <path>lib/main.dart</path>
  <start_line>1</start_line>
  <end_line>50</end_line>
</tool_request>
```
Nexon's parser is highly robust and automatically extracts tags like `<method>`, `<path>`, `<query>`, `<start_line>`, `<end_line>`, `<pattern>`, and `<command>`. It also includes fallback parsers to capture `<PARAM name="key">value</PARAM>` and `<parameter name="key">value</parameter>` syntax if generated by older models.

Supported tool methods include:
*   `dir_list` — List folder contents.
*   `file_read` — View lines within a specific range.
*   `file_write` — Overwrite or write content to a file path.
*   `str_replace` — Find and replace contiguous string blocks.
*   `find_paths` — Case-insensitive search for files or directories by pattern.
*   `run_command` — Safely execute bash shell commands inside Termux.
*   `git_status` / `git_diff` — Version control state.

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
*   **Vectorized Numpy Similarity**: During retrieval, candidate vectors are loaded into memory, stacked into a 2D `numpy` array, and a vectorized batch dot product (`_cosine_batch()`) computes similarities instantly in one operation, avoiding per-row Python loop overhead.

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
