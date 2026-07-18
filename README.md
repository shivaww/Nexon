# Nexon

An AI-powered IDE and research assistant that runs natively on your Android phone via Termux. Nexon combines an interactive Flutter UI with a local Python bridge to orchestrate shell execution, file manipulation, and agentic research loops directly on-device.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-private%20%2F%20in%20development-red.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-TBD-lightgrey.svg)](https://github.com/shivaww/Nexon)
<!-- NOTE: Using a static badge since the repository is private and live GitHub API badge calls will fail. This will switch to a live shields.io counter if/when the repository goes public. -->
[![Downloads](https://img.shields.io/badge/downloads-0--active--dev-blue.svg)](https://github.com/shivaww/Nexon)

---

## System Architecture

Nexon split-processes operations between the Dart/Flutter application (which renders the visual IDE panels and manages state) and a Python Bridge background server running in the Termux userland environment.

```text
┌──────────────────────────────────────────────────────────────────────┐
│                        Flutter App (Android)                         │
│                                                                      │
│ ┌─────────────┐ ┌──────────────┐ ┌─────────────┐ ┌─────────────────┐ │
│ │ Chat/IDE UI │ │  Artifacts   │ │Memory System│ │Deep Research UI │ │
│ │(Tool routing) │(SVG/MD Render) │ (JSON File) │ │(3-State UI)     │ │
│ └──────┬──────┘ └──────────────┘ └─────────────┘ └───────┬─────────┘ │
│        │                                                 │           │
│        │    ┌───────────────────────────────┐            │           │
│        │    │      Google Drive Backup      │            │           │
│        │    │ (Syncs Chats, Settings, Keys) │            │           │
│        │    └──────────────┬────────────────┘            │           │
└────────┼───────────────────┼─────────────────────────────┼───────────┘
         │                   │                             │
         │ WebSocket :8765 / │ HTTP :8390                  │
         v                   │                             v
┌────────────────────────────┼─────────────────────────────────────────┐
│                            │    python_bridge Server                 │
│ ┌────────────────────────┐ │  ┌────────────────────────────────────┐ │
│ │ IDE / Shell Exec Layer │ │  │ Deep Research Engine               │ │
│ │ (hybrid_tools.py)      │ │  │ - Embedder Lifecycle Management    │ │
│ │ - File Read/Write/Edit │ │  │ - Hierarchical RAG                 │ │
│ │ - Arbitrary Termux Cmds│ │  │ - SQLite + Numpy Vector Store      │ │
│ └─────────┬──────────────┘ │  └──────────────────┬─────────────────┘ │
└───────────┼────────────────┴─────────────────────┼───────────────────┘
            │                                      │
            v                                      v
┌────────────────────────┐         ┌───────────────────────────────────┐
│     Termux Runtime     │         │      External Services & APIs     │
│ - Bash shell           │         │ - Google Drive API (OAuth Backup) │
│ - GCC, git, python     │         │ - Tavily Search API (Web Search)  │
└────────────────────────┘         │ - LLM Providers (OpenAI, Anthropic)│
                                   └───────────────────────────────────┘
```

---

## Core Features

### 1. IDE Workstation & Termux Tool Integration
*   **Arbitrary Command Runner**: LLM agents execute commands directly inside the Termux shell via `shell_exec` through the Python bridge, supporting standard compilers, tests, and script runners.
*   **Rich File Manipulation**: Read, write, and patch files using specific line range indices. Supports granular tools like `patch_file_rich` and `diff_files_rich`.
*   **Security Permission States**: Grants users execution control via `shell_permission` configurations natively in the Flutter UI (`ask`, `session`, `always`, or `never`).

### 2. Standalone Web Search
*   **General-Purpose Search**: Outside of Deep Research mode, the app intercepts `<search_request>` tags during standard chat sessions.
*   **Tavily Integration**: The Python bridge natively routes these requests to the Tavily API, providing LLMs with real-time web context on demand.

### 3. Artifact Rendering
*   **Markdown & Code Views**: Renders rich formatted documents and syntax-highlighted code directly in the chat feed using `flutter_markdown`.
*   **SVG Visual Rendering**: Intercepts generated SVG files and renders them cleanly using `flutter_svg` (`SvgPicture.string`), turning XML markup into actual on-device visual diagrams.
*   **Document Export**: Supports parsing and saving conversational artifacts locally as `.md` or `.docx` files.

### 4. AI Memory System
*   **State Persistence**: Persists a global context state to `nexon_memory.json`, allowing user preferences, developer guidelines, or project specifications to survive app restarts.

### 5. Google Drive Backup & Sync
*   **Unified Backup Payload**: Bundles conversation sessions, secure API keys, system settings, AI memory, and media files into a serialized `nexon_backup.json` file.
*   **OAuth & Silent Refresh**: Implemented in Dart via `googleapis/drive/v3.dart`. It uses a custom HTTP client (`GoogleAuthClient`) capable of silently refreshing expired access tokens to keep sync running smoothly in the background.

### 6. Deep Research (Hierarchical RAG)
*   **Three-State Lifecycle**: A guided UI pipeline that moves through Planner, Researcher, and Synthesizer phases.
*   **On-Device Vector Storage**: Embeddings are stored in SQLite and computed using NumPy vector math (`float32` byte arrays), fully migrating away from complex C-extensions like `sqlite-vec`.
*   **Configurable Budget**: Includes a user-configurable `_writerContextBudget` setting to throttle how many tokens of retrieved evidence are injected into the final synthesizing phase.

---

## Technical Specifications

| Layer | Technologies & Frameworks |
|---|---|
| **Frontend UI** | Flutter (Dart), Material 3 Design, `flutter_markdown`, `flutter_svg` |
| **Local Storage** | Flutter Secure Storage (OAuth tokens), SharedPreferences, local JSON |
| **Python Bridge** | Python 3, `aiohttp`, `websockets`, `numpy`, `docx_creator` |
| **Local Embedder** | `llama.cpp` (`llama-server`) & `EmbeddingGemma` (`embeddinggemma-300m-Q4_0.gguf`) |
| **Third-Party APIs**| Supabase Google Auth, Google Drive v3 REST API, Tavily Search API |

---

## Getting Started

### Prerequisites
*   An Android device running Android 7.0+ (API 24+)
*   **[Termux](https://f-droid.org/en/packages/com.termux/)** installed from F-Droid
*   Python 3.10+ installed inside the Termux container

### Installation

1.  **Configure Termux Environment**:
    Navigate to your local repository directory and run the bridge installation script:
    ```bash
    cd termux_forge
    chmod +x install_bridge.sh
    ./install_bridge.sh
    ```
2.  **Start Python Bridge Server**:
    Launch the bridge gateway. This runs the websocket protocol on port `8765` and HTTP REST on port `8390` concurrently:
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

Nexon is currently a private project actively developed by a solo developer. 
*Known Limitations*: None currently tracked for core infrastructure; the Google Drive backup token refresh logic has been stabilized.

---

## License & Contributing

*   **License**: TBD — currently private, license will be finalized before any public release.
*   **Contributing**: The repository is private and not currently accepting external contributions.
