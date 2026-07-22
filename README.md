# Nexon 🚀

An AI-powered Mobile Agentic IDE and Deep Research assistant that runs natively on Android via Termux. Nexon combines an interactive Flutter UI with a local Python bridge to orchestrate shell execution, file manipulation, live web search, and hierarchical RAG loops directly on your phone.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-orange.svg)](https://termux.dev/)
[![Status](https://img.shields.io/badge/status-Open%20Source-success.svg)](https://github.com/shivaww/Nexon)
[![License](https://img.shields.io/badge/license-Non--Commercial-orange.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.32%2B-blue.svg)](https://flutter.dev)

---

## 🏗️ System Architecture

Nexon split-processes operations between the Flutter application (visual IDE panels, state management, and rendering) and a Python Bridge background server running in the Termux userland environment.

```text
+----------------------------------------------------------------------+
|                        Flutter App (Android)                         |
|                                                                      |
| +-------------+ +--------------+ +-------------+ +-----------------+ |
| | Chat/IDE UI | |  Artifacts   | |Memory System| |Deep Research UI | |
| |(Tool routing) |(SVG/MD Render) | (JSON File) | |(3-State UI)     | |
| +------+------+ +--------------+ +-------------+ +-------+---------+ |
|        |                                                 |           |
|        |    +-------------------------------+            |           |
|        |    |      Google Drive Backup      |            |           |
|        |    | (Syncs Chats, Settings, Keys) |            |           |
|        |    +---------------+---------------+            |           |
+--------+--------------------+----------------------------+-----------+
         |                    |                            |
         | WebSocket :8765 /  | HTTP :8390                 |
         v                    |                            v
+-----------------------------+----------------------------------------+
|                             |    python_bridge Server                |
| +------------------------+  |  +-----------------------------------+ |
| | IDE / Shell Exec Layer |  |  | Deep Research Engine              | |
| | (hybrid_tools.py)      |  |  | - Embedder Lifecycle Management   | |
| | - File Read/Write/Edit |  |  | - Hierarchical RAG                | |
| | - Arbitrary Termux Cmds|  |  | - SQLite + Numpy Vector Store     | |
| +---------+--------------+  |  +-----------------+-----------------+ |
+-----------+-----------------+--------------------+-------------------+
            |                                      |
            v                                      v
+------------------------+         +-----------------------------------+
|     Termux Runtime     |         |      External Services & APIs     |
| - Bash shell           |         | - Google Drive API (OAuth Backup) |
| - GCC, git, python     |         | - Tavily Search API (Web Search)  |
| +----------------------+         | - LLM Providers (BYOK Keys)       |
                                   +-----------------------------------+
```

---

## ✨ Core Features

### 1. 🛠️ Agentic IDE & Termux Tool Integration
*   **Arbitrary Command Runner**: LLM agents execute commands directly inside the Termux shell via `shell_exec` through the Python bridge, supporting standard compilers, tests, and script runners.
*   **Rich File Manipulation**: Read, write, and patch files using specific line range indices. Supports granular tools like `patch_file`, `replace_lines`, and `diff_files`.
*   **Security Permission Control**: Grants users execution control via shell permission configurations natively in the Flutter UI (`ask`, `session`, `always`, or `never`).

### 2. 🌐 Standalone Web Search
*   **Live Web Context**: The app intercepts search requests during standard chat sessions and routes them natively to Tavily API for real-time web context.

### 3. 📄 Artifact Rendering & Export
*   **Markdown & Code Views**: Renders rich formatted documents and syntax-highlighted code directly in the chat feed.
*   **SVG Diagram Rendering**: Intercepts generated SVG markup and renders interactive visual diagrams natively via `flutter_svg`.
*   **Document Export**: Supports parsing and saving conversational artifacts locally as `.md` or `.docx` files.

### 4. 🧠 Memory & Persistent Context
*   **State Persistence**: Persists global context to `nexon_memory.json`, allowing user preferences, developer guidelines, and project specs to survive app restarts.

### 5. ☁️ Google Drive Backup & Sync
*   **Unified Sync**: Bundles conversation sessions, settings, AI memory, and credentials into `nexon_backup.json` on Google Drive.
*   **Non-Destructive Merge**: Smart syncing preserves local un-synced chats while restoring remote backups smoothly.

### 6. 🔬 Deep Research (Hierarchical RAG)
*   **Guided Pipeline**: Guided UI pipeline moving through Planner, Researcher, and Synthesizer phases.
*   **On-Device Vector Math**: Computes embeddings stored in SQLite using NumPy vector math (`float32`), operating smoothly on mobile hardware.

### 7. 🔔 Automatic Release Notifications
*   **Version Checker**: Integrated `UpdateService` notifies users when a new version or APK release is available.

---

## 🧰 Technical Specifications

| Layer | Technologies & Frameworks |
|---|---|
| **Frontend UI** | Flutter (Dart), Material 3 Design, `flutter_markdown`, `flutter_svg`, `fl_chart` |
| **Local Storage** | Flutter Secure Storage, SharedPreferences, local JSON |
| **Python Bridge** | Python 3, `aiohttp`, `websockets`, `numpy`, `python-docx` |
| **Vector & Search Engine** | SQLite + NumPy float32 Vector Math (Lightweight on-device math) |
| **Third-Party APIs**| Supabase Auth, Google Drive v3 REST API, Tavily Web Search API |

---

## 📌 Project Status

Nexon is an open-source Mobile Agentic IDE project actively developed for Android & Termux. All core infrastructure (Google Drive OAuth token refresh, structured file manipulation, and responsive UI rendering) has been fully stabilized.

---

## 🚀 Getting Started

### Prerequisites
*   An Android device running Android 7.0+ (API 24+)
*   **[Termux](https://f-droid.org/en/packages/com.termux/)** installed from F-Droid
*   Python 3.10+ installed inside Termux

### Installation

1.  **Configure Termux Environment**:
    Run the bridge setup script inside your repository directory:
    ```bash
    chmod +x install_bridge.sh
    ./install_bridge.sh
    ```
2.  **Start Python Bridge Server**:
    Launch the bridge gateway. This runs WebSocket communication on port `8765` and HTTP REST on port `8390`:
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

## 🤝 Contributing

Contributions, bug reports, and feature requests are open and welcome! Feel free to open an issue or submit a Pull Request.

---

## 📜 License & Usage

Distributed under the **Nexon Non-Commercial License**. Free strictly for personal, academic, and non-commercial usage. **Commercial use in any form (as-is, modified, or re-branded) is strictly prohibited.** Subscriptions are coming soon; commercial licensing options will open once subscriptions launch. See [`LICENSE`](LICENSE) for details.
