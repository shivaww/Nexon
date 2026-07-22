# Nexon

Nexon is a mobile AI coding workspace built with Flutter + Termux. It combines a chat-first IDE UI, multi-provider LLM access, and a local Python bridge that can run shell commands, edit files, manage workflows, and orchestrate research loops from your Android device.

> Internally, the app still uses the **TermuxForge** name in many modules.

---

## Table of Contents

- [1. What This Project Is](#1-what-this-project-is)
- [2. Architecture Overview](#2-architecture-overview)
- [3. How the App Works End-to-End](#3-how-the-app-works-end-to-end)
- [4. Core Features](#4-core-features)
- [5. Codebase Structure](#5-codebase-structure)
- [6. Runtime Services and Data Layers](#6-runtime-services-and-data-layers)
- [7. Setup and Installation](#7-setup-and-installation)
- [8. Development Commands](#8-development-commands)
- [9. CI/CD Pipeline](#9-cicd-pipeline)
- [10. Current Implementation Status](#10-current-implementation-status)
- [11. Troubleshooting](#11-troubleshooting)
- [12. Security and Safety Model](#12-security-and-safety-model)
- [13. License](#13-license)

---

## 1. What This Project Is

Nexon is designed to make an Android phone behave like an AI-assisted software workspace. The app provides:

- LLM chat with many OpenAI-compatible providers
- On-device tool execution through Termux + Python bridge
- File editing and shell operations from AI tool calls
- Deep research loops with search/fetch/summarize/write stages
- Artifact rendering (Markdown, HTML, SVG, DOCX-like output, charts)
- Session persistence and optional Google Drive backup/restore

---

## 2. Architecture Overview

Nexon has two major app layers and one bridge layer:

1. **Primary production runtime (currently used)**
   - `lib/main.dart` (large integrated runtime)
   - Handles chat, provider routing, tool XML parsing, research loop, artifact rendering, and settings persistence.

2. **Modular app architecture (present and evolving)**
   - `lib/app.dart`, `lib/core/*`, `lib/presentation/*`, `lib/services/*`, `lib/data/models/*`
   - Structured route-based IDE screens and service abstractions.

3. **Python bridge runtime**
   - `python_bridge/termux_forge_bridge.py`
   - WebSocket JSON-RPC server (`ws://127.0.0.1:8765`) + legacy HTTP endpoint (`http://127.0.0.1:8390/mcp`)
   - Executes shell/file/git/workflow/MCP/search/media/checkpoint operations.

---

## 3. How the App Works End-to-End

1. User sends a prompt from Flutter chat UI.
2. App builds system instructions based on enabled modes (agentic, artifacts, visuals, deep research).
3. LLM response is streamed and parsed.
4. If tool tags are emitted (e.g. `<search_request>`, `<read_url>`, `<mcp_request>`, `<tool_request>`), the app invokes bridge methods.
5. Bridge executes work with safety checks, returns structured output.
6. App appends result into chat, optionally continues tool loop.
7. Session/settings are persisted locally; optional auto-sync pushes backups to Google Drive.

---

## 4. Core Features

### 4.1 Multi-provider LLM Chat

- Provider catalog includes cloud + local endpoints (OpenAI, Google, Groq, OpenRouter, Ollama, LM Studio, vLLM, custom, and more).
- Per-provider model and token settings.
- Secure API key storage using `flutter_secure_storage` with shared-preferences fallback.
- Session-based chat history with branch support for edited prompts.

### 4.2 Agentic IDE Tool Execution

- Agentic mode instructs models to use structured tool calls.
- Bridge supports rich file operations (`read_file_rich`, `patch_file`, `replace_lines`, etc.).
- Shell commands run through a guarded executor with timeouts and process control.
- Auto-checkpoint hooks can snapshot before destructive edits.

### 4.3 Deep Research Pipeline

- Planner/Researcher/Writer style staged research flow.
- Tool-driven browsing through:
  - `<search_request>` → Tavily search (`web_search`)
  - `<read_url>` → page fetch + cleaner (`read_url`)
- Per-phase facts/findings persisted in bridge-owned `temp.json` via:
  - `deep_research.reset`
  - `deep_research.update_phase`
  - `deep_research.export_temp`
- Final research report can be saved as Markdown or exported to DOCX.

### 4.4 Artifacts and Rich Rendering

The app parses fenced code blocks and renders by type:

- `markdown` → rendered document cards
- `html` / `artifact` → embedded webview-style viewer
- `svg` → inline visual renderer + fullscreen viewer
- `docx` → markdown-to-docx export flow
- `chart` → custom chart parser + chart widgets
- code fences (`dart`, `py`, etc.) → syntax-highlighted code cards

### 4.5 Media Input and Output

- Image/file picking in chat composer.
- Camera/gallery permissions via `permission_handler`.
- Bridge media hooks include provider discovery and generation stubs/handlers (OpenAI + Stability implemented paths, additional providers discoverable).

### 4.6 Session Persistence + Backup

- Local persistence: chat sessions, settings, provider metadata, feature toggles.
- Drive sync service can backup:
  - chats
  - settings
  - provider key references / secure token flow
  - artifacts + media payloads
- OAuth handled through Supabase auth + Google provider token persistence.

### 4.7 MCP + Workflow + GitHub Integrations

Bridge includes runtime handlers for:

- MCP server lifecycle and tool routing (stdio/SSE/HTTP transport configs)
- Workflow execution engine (sequential/parallel/retry/conditional step model)
- GitHub hooks (`gh`-based workflow trigger/status/artifact actions)
- Background service manager for long-running server commands
- Checkpoint create/rollback operations

---

## 5. Codebase Structure

```text
/home/runner/work/Nexon/Nexon
├── lib/
│   ├── main.dart                     # Primary integrated runtime used by app startup
│   ├── app.dart                      # Modular app shell (router + theme)
│   ├── core/                         # Router + theming
│   ├── presentation/                 # Modular screens/widgets/layouts
│   ├── services/                     # Modular service layer abstractions
│   ├── data/models/                  # Domain/data models
│   └── widgets/                      # Shared widgets (chart, diff, table)
├── python_bridge/
│   ├── termux_forge_bridge.py        # Main bridge server (WS + HTTP)
│   ├── mcp_server.py                 # Legacy wrapper entrypoint
│   ├── hybrid_tools.py               # Rich file/shell tooling
│   ├── command_executor.py           # Guarded shell execution
│   ├── security.py                   # Command risk filtering
│   ├── mcp_manager.py                # MCP server management
│   ├── workflow_runner.py            # Workflow executor
│   ├── checkpoint_hooks.py           # Snapshot + rollback logic
│   ├── github_hooks.py               # GitHub CLI operations
│   ├── media_hooks.py                # Media provider integration
│   └── deep_research/                # Research orchestration helpers
├── test/                             # Widget/unit test files
├── .github/workflows/build.yml       # CI analyze/test/build APK pipeline
├── install_bridge.sh                 # Termux bridge setup script
└── pubspec.yaml                      # Flutter dependencies/config
```

---

## 6. Runtime Services and Data Layers

### Flutter-side persistence

- `SharedPreferences`: chat sessions, selected provider/model, feature toggles.
- `FlutterSecureStorage`: API keys and OAuth-related secure tokens.

### Bridge-side state

- Logs: `~/.termux_forge/logs`
- Command history: `~/.termux_forge/command_history.json`
- Checkpoints: `~/.termux_forge/checkpoints`
- MCP config/state: `~/.termux_forge/mcp`
- Background services registry: `~/.termux_forge/services/registry.json`
- Deep research temp state: `~/.termux_forge/deep_research/temp.json` (default)

---

## 7. Setup and Installation

### Prerequisites

- Flutter SDK (project expects Flutter 3.32.x in CI)
- Dart SDK 3.8+
- Android/Termux environment for bridge execution
- Python 3 in Termux

### 7.1 Install Flutter dependencies

```bash
flutter pub get
```

### 7.2 Install Python bridge dependencies (Termux)

From repository root:

```bash
chmod +x install_bridge.sh
./install_bridge.sh
```

### 7.3 Start bridge server

```bash
cd ~/nexon_bridge
python3 mcp_server.py
```

### 7.4 Run app

```bash
flutter run
```

---

## 8. Development Commands

```bash
# Static analysis
flutter analyze

# Tests
flutter test --coverage --reporter=expanded

# Generate launcher icons
dart run flutter_launcher_icons

# Build release APK
flutter build apk --release
```

---

## 9. CI/CD Pipeline

Defined in `.github/workflows/build.yml`:

1. **Analyze & Lint**: `flutter pub get`, `flutter analyze`
2. **Unit & Widget Tests**: `flutter test --coverage --reporter=expanded`
3. **Build APK**: release build + artifact upload

The workflow uploads coverage and generated APK artifacts.

---

## 10. Current Implementation Status

This repository contains both production runtime logic and in-progress modular architecture.

- **Actively wired runtime**: `lib/main.dart` + `python_bridge/*`
- **Modular screen/service system**: large portions are implemented, but several services/components still include placeholders/TODO stubs (for example in `tool_registry`, parts of `plugin`, `context_compression`, and some UI actions).

So the codebase is feature-rich but still under active consolidation/refinement.

---

## 11. Troubleshooting

### Bridge not reachable

- Ensure `python3 mcp_server.py` is running in Termux.
- Verify endpoint expected by app:
  - HTTP: `http://127.0.0.1:8390/mcp`
  - WS: `ws://127.0.0.1:8765`

### Deep Research fails immediately

- Confirm `TAVILY_API_KEY` is set in the bridge environment.
- `read_url` intentionally skips PDF URLs in current flow.

### No provider response

- Check provider API key in app settings.
- Validate base URL/model pair for the selected provider.

### Drive sync issues

- Re-authenticate with Google in onboarding/settings flow.
- Confirm backup toggle is enabled.

---

## 12. Security and Safety Model

- Shell execution is filtered by `python_bridge/security.py` risk patterns.
- Dangerous command classes are blocked; risky classes are flagged.
- File actions are path-validated against approved directories.
- Permission gates exist in Flutter for shell execution mode (`ask`, `session`, `always`, `never`).
- Backup/auth tokens are persisted in secure storage where possible.

---

## 13. License

License is currently **TBD** in repository metadata.

