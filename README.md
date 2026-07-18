# Nexon

An AI-powered mobile coding IDE, agentic workspace, and deep research assistant that runs natively on your Android phone via Termux — no laptop or cloud VM required.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-private%20%2F%20in%20development-red.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-TBD-lightgrey.svg)](https://github.com/shivaww/Nexon)
<!-- NOTE: Using a static badge since the repository is private and live GitHub Actions / Release API badge calls will fail. This will be updated to a live shields.io counter when/if the repository goes public. -->
[![Downloads](https://img.shields.io/badge/downloads-0--active--dev-blue.svg)](https://github.com/shivaww/Nexon)

*Note: A live download counter will be enabled once the repository becomes public.*

---

## Workspace Architecture

Nexon integrates a high-performance Flutter-based UI with a local Python Bridge Server that acts as a secure Model Context Protocol (MCP) gateway and terminal runner. The deep research pipeline utilizes a local `llama-server` instance to execute hierarchical retrieval and document ingestion directly on-device.

```text
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            FLUTTER APP (ANDROID UI)                             │
│                                                                                 │
│  ┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────────────┐  │
│  │   Chat & IDE Panels   │ │   Artifact Renderer   │ │     Memory System     │  │
│  │                       │ │                       │ │                       │  │
│  │ * Inline Chat Panel   │ │ * HtmlArtifactWidget  │ │ * memory_tool Parser  │  │
│  │ * Code Editor View    │ │ * FileArtifactWidget  │ │ * nexon_memory.json   │  │
│  │ * Sidebar Explorer    │ │ * SvgDiagramWidget    │ │   (10KB Local Limit)  │  │
│  │ * Todo Dashboard      │ │ * NexonChartWidget    │ │                       │  │
│  └───────────┬───────────┘ └───────────────────────┘ └───────────────────────┘  │
│              │                                                                  │
│              │ XML Tag Interception & Parse (tool_request / search_request)     │
│              ▼                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                     Google Drive Backup & Auth Flow                       │  │
│  │     * DriveSyncService (nexon_backup.json: chats, keys, artifacts, RAM)   │  │
│  │     * Supabase OAuth Client (google_provider_token secure persistence)    │  │
│  └───────────┬───────────────────────────────────────────────────────────────┘  │
└──────────────┼──────────────────────────────────────────────────────────────────┘
               │ WebSocket (:8765) / HTTP (:8390)
               ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          PYTHON BRIDGE GATEWAY (Termux)                         │
│                                                                                 │
│  ┌─────────────────────────────────┐   ┌─────────────────────────────────────┐  │
│  │       Termux Shell & IDE        │   │        Deep Research RAG            │  │
│  │                                 │   │                                     │  │
│  │ * asyncio Command Execution     │   │ * LangGraphRAGOrchestrator          │  │
│  │ * File System operations        │   │ * Agentic Search Reflection Loop    │  │
│  │ * git, flutter & package tools  │   │ * Hybrid Routing (vector + graph)   │  │
│  │ * Tavily Web Search Wrapper     │   │ * SQLite + Numpy Cosine similarity  │  │
│  └─────────────────────────────────┘   └───────────┬─────────────────────────┘  │
│                                                    │                            │
│                                                    │ Coordinates                │
│                                                    ▼                            │
│                                        ┌─────────────────────────────────────┐  │
│                                        │     Managed Embedder Lifecycle      │  │
│                                        │                                     │  │
│                                        │ * ServerLifecycleManager (flock)    │  │
│                                        │ * Local llama-server (Port 8080)     │  │
│                                        │ * EmbeddingGemma GGUF model         │  │
│                                        └─────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────────┬───────────────┘
                       │                                          │
                       ▼                                          ▼
           ┌──────────────────────┐                   ┌───────────────────────┐
           │   External LLMs      │                   │   Google Drive API    │
           │ (Anthropic, Gemini,  │                   │ (Google Backup Cloud) │
           │  OpenAI, OpenRouter) │                   │                       │
           └──────────────────────┘                   └───────────────────────┘
```

---

## Detailed Features

### 💻 IDE & Termux Integration
*   **Arbitrary Command Execution**: Execute shell scripts, compilers, tests, and standard package managers via a secure Python terminal bridge.
*   **File System Operations**: Read, write, edit, and recursively list project files directly from the chat interface using structured XML block operations.
*   **Interactive Shell Terminal**: Run compiler targets (`flutter run`, `flutter build`, `dart analyze`) and check local system status through interactive logs.
*   **Version Control**: Full Git helper suite exposing `git status`, `git diff` (staged/unstaged), `git commit`, `git push`, and `git pull` directly to the LLM agent.
*   **Workspace Configurations**: Define working directories (`_agenticWorkspace`) and customize command confirmation prompts (`shell_permission` configurations: `ask`, `session`, `always`, `never`) for granular safety control.

### 🎨 Artifact Renderer & SVG Visualizer
*   **Interactive Web Previews**: Sandboxes generated HTML, JS, and CSS code in a local `HtmlArtifactWidget` to render interactive widgets, prototypes, and web layouts.
*   **SVG Diagram Viewer**: Intercepts ````svg ... ```` blocks, cleans markup margins, normalizes aspect ratios to `100%`, and renders vector flowcharts/illustrations inside a pinch-to-zoom, pan-enabled `SvgDiagramWidget`.
*   **Nexon Charting**: Renders complex data visualizations (bar, line, pie, radar, scatter charts, and mindmaps) from plain data blocks using `NexonChartWidget` backed by `fl_chart`.
*   **Document Generators**: Preview text documents or edit files through `FileArtifactWidget`, and export formatted documents to the Android device `Downloads` directory via `DocxArtifactWidget` and `MdArtifactWidget`.

### 🔍 General-Purpose Web Search
*   **Standalone Web Lookup**: Enables web queries inside normal chats (separate from Deep Research) via Tavily search endpoints.
*   **Dynamic Tag Interception**: Intercepts `<search_request>` and `<read_url>` tags during streaming LLM output to fetch live search summaries, crawl pages, and convert HTML to clean markdown context on-the-fly.

### 🧠 Persistent AI Memory
*   **Session-Cross Context**: Saves long-term user configurations, coding style guidelines, and project context across sessions.
*   **Tag Protocol**: Exposes `<memory action="...">` tool calls (`read`, `append`, `replace`, `clear`) allowing models to maintain up to 10KB of state inside `nexon_memory.json`.

### ☁️ Google Drive Backup
*   **Full Workspace Backup**: Packs active chats, custom API keys, settings configurations, RAG metadata, and compiled document artifacts into a unified `nexon_backup.json` (max 2MB per file).
*   **Supabase OAuth Integration**: Signs in securely using Google OAuth flow, persisting provider access and refresh tokens to Android secure storage (`google_provider_token`).
*   **Auto-Sync**: Background auto-sync daemon keeps local files mirrored to a dedicated cloud backup folder.

### 🔬 Deep Research & RAG
*   **Hierarchical RAG Strategy**: Divides documents into Document, Section, and Chunk tiers for granular semantic query routing.
*   **NumPy Similarity Engine**: Bypasses heavy native libraries using `numpy` dot-products on floating-point vector arrays stored in a standard SQLite WAL database.
*   **Managed Local Embedder**: Handles `llama-server` life cycles for `EmbeddingGemma` GGUF local model execution, including file locks and a 120s auto-shutdown battery saver.
*   **Soft Warning Circuit Breaker**: Warns users if their writer context budget is too low, but never restricts execution.

---

## Tech Stack

*   **Frontend UI**: Flutter (Dart), Material 3, Google Fonts, `flutter_svg`, `fl_chart`.
*   **State & Storage**: Provider, Flutter Secure Storage (auth tokens), SharedPreferences (local settings).
*   **Backend Bridge**: Python 3 (`aiohttp`, `websockets`, `requests`, `numpy`, `python-docx`, `pypdf`, `psutil`).
*   **Local Inference**: `llama.cpp` + `EmbeddingGemma` (`embeddinggemma-300m-Q4_0.gguf`).
*   **Cloud Integrations**: Supabase Google OAuth API, Google Drive v3 API, Tavily Search API.

---

## Getting Started

### Prerequisites
*   Android device running Android 7.0+ (API 24+)
*   **[Termux](https://f-droid.org/en/packages/com.termux/)** installed from F-Droid
*   Python 3.10+ in Termux
*   Flutter SDK (if compiling from source)

### Installation & Setup

1.  **Configure Termux Environment**:
    Navigate to the Nexon directory and run the bridge installation script:
    ```bash
    cd termux_forge
    chmod +x install_bridge.sh
    ./install_bridge.sh
    ```
2.  **Start Python Bridge Server**:
    Launch the bridge gateway. This runs the websocket protocol on port `8765` and HTTP REST on port `8390`:
    ```bash
    cd ~/nexon_bridge
    python3 mcp_server.py
    ```
3.  **Compile & Run App**:
    Build or run the Flutter application:
    ```bash
    flutter run
    ```

---

## Project Status

Nexon is in **active private development** by a solo developer. 

*Known Limitations*: Supabase Google OAuth tokens must be refreshed periodically by signing in again if background sync logs mention authorization errors.

---

## License

License: **TBD** (Undecided / Under evaluation for future open-source release)

---

## Contributing

Not currently accepting external contributions. The repository is private.
