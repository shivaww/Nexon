# Nexon

An AI-powered mobile coding IDE, agentic development workspace, and deep research assistant that runs natively on your Android device via Termux. Nexon connects a highly interactive Flutter frontend with a local Python Bridge Server that manages shells, files, local vector databases, and Model Context Protocol (MCP) gateways.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-private%20%2F%20in%20development-red.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-TBD-lightgrey.svg)](https://github.com/shivaww/Nexon)
<!-- NOTE: Using a static badge since the repository is private and live GitHub Actions / Release API badge calls will fail. This will be updated to a live shields.io counter when/if the repository goes public. -->
[![Downloads](https://img.shields.io/badge/downloads-0--active--dev-blue.svg)](https://github.com/shivaww/Nexon)

---

## System Architecture

Nexon split-processes operations between the Dart/Flutter application (rendering the visual IDE panels and managing state) and a Python Bridge background server running in the Termux userland environment.

```text
       +-------------------------------------------------------+
       |               FLUTTER FRONTEND APPLICATION            |
       |  (Manages chat histories, renders rich UI/Artifacts)  |
       +---------------------------+---------------------------+
                                   |
                                   | JSON-RPC over WebSocket (Port 8765)
                                   | & REST API (Port 8390)
                                   v
       +-------------------------------------------------------+
       |                 PYTHON BRIDGE SERVER                  |
       |  (Terminal runner, file operator, and RAG gateway)    |
       +-------------+---------------------------+-------------+
                     |                           |
                     v                           v
       +---------------------------+ +---------------------------+
       |   Termux System Tools     | |     Deep Research Engine  |
       |                           | |                           |
       |  - Bash subprocess exec   | |  - LangGraph Orchestrator |
       |  - git, flutter, & npm    | |  - Hybrid Retrieval Store |
       |  - Tavily web search      | |  - NumPy Vector Engine    |
       +---------------------------+ +-----------+---------------+
                                                 |
                                                 | Manages Process
                                                 v
                                     +---------------------------+
                                     |    Local llama-server     |
                                     |  (EmbeddingGemma GGUF)    |
                                     +---------------------------+
```

---

## Core Subsystems & Features

### 1. IDE Workstation & Termux Tool Integration
*   **Arbitrary Command Runner**: LLM agents execute commands directly inside the Termux shell via `asyncio.create_subprocess_exec` through the Python bridge, supporting standard compilers, tests, and script runners.
*   **Rich File Manipulation**: Read, write, and patch files using specific line range indices. Supports `str_replace` for precise patch insertions without rewriting files.
*   **Git Controller**: Exposes a clean interface for source control tasks, including automated `git status`, `git diff`, `git commit`, `git push`, and `git pull` executions.
*   **Security Permission States**: Grants users execution control via `shell_permission` configurations:
    *   `ask`: Prompt the user for approval on every command.
    *   `session`: Automatically allow execution for the active app session after one approval.
    *   `always`: Bypass confirmation.
    *   `never`: Block command executions entirely.

### 2. Rich Artifact Renderer
Nexon intercepts code block delimiters in chat streams and renders them using specialized interactive widgets:
*   **`HtmlArtifactWidget`**: Runs generated HTML, JavaScript, and CSS code in a sandboxed, interactive local WebView.
*   **`SvgDiagramWidget`**: Intercepts ````svg```` fences, parses raw tags, cleans height/width styling constraints, and loads illustrations into a pinch-to-zoom interactive pan container.
*   **`NexonChartWidget`**: Renders custom charts (including bar, line, pie, and radar graphs) from JSON data blocks using `fl_chart`.
*   **File Generators**: Displays formatted reviews or documentation via `DocxArtifactWidget` and `MdArtifactWidget`, with native export to the Android `Downloads/` directory.

### 3. General-Purpose Web Search
*   **Standalone Search Tags**: Intercepts `<search_request>query</search_request>` and `<read_url>URL</read_url>` tags during standard chat sessions.
*   **Real-time Context Ingestion**: Uses a customized web search protocol prompt that commands LLM models to lookup live information when queries fall outside their training data cutoff.

### 4. AI Memory System
*   **Memory Tag Protocol**: Supports `<memory action="read|append|replace|clear">` blocks to save important developer guidelines or project specifications.
*   **State Persistence**: Persists memory states inside `nexon_memory.json` (max 10KB limit), injecting them into the system prompt across chat sessions.

### 5. Google Drive Backup & Sync
*   **Unified Backup Payload**: Bundles conversation sessions, SecureStorage keys, system configurations, AI memory, and media files into a serialized `nexon_backup.json` file.
*   **Supabase Google OAuth**: Resolves authentication using Supabase's Google provider tokens (`google_provider_token`), which are saved in the phone's secure keystore.
*   **Debounced Sync**: Features a 5-second debouncer to prevent concurrent backup writes during rapid edits.

### 6. Deep Research (Hierarchical RAG)
*   **Tiered Retrieval routing**: Employs document, section, and chunk divisions to optimize semantic database routes based on query scope.
*   **On-Device Vector Storage**: Vector embeddings are stored as little-endian `float32` byte arrays in a local SQLite database and computed via NumPy matrix dot-products, bypassing complex native library compilations on Android.
*   **Execution Safeguard**: Non-blocking warning dialogs alert users if their writer context budget is too low (e.g. $\le 8192$ tokens), but allow them to proceed with the best available evidence chunks.

---

## Technical Specifications

| Layer | Technologies & Frameworks |
|---|---|
| **Frontend UI** | Flutter (Dart), Material 3 Design, Google Fonts, `flutter_svg`, `fl_chart` |
| **Local Storage** | Flutter Secure Storage (OAuth tokens), SharedPreferences (local settings) |
| **Python Bridge** | Python 3, `aiohttp`, `websockets`, `numpy`, `python-docx`, `pypdf`, `psutil` |
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

Nexon is in **active private development** by a solo developer. 

*Known Limitations*: Google Drive backup requires an active Google OAuth session. If backup operations fail with authorization logs, please sign out and sign back in through the Account settings.

---

## License & Contributing

*   **License**: **TBD** (Undecided / Under evaluation for future open-source release)
*   **Contributing**: The repository is private; external pull requests and contributions are not accepted at this time.
