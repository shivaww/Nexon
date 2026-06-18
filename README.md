# TermuxForge

> **An AI-powered mobile development environment** that transforms your Android device into a full-featured coding workstation — powered by Flutter, Termux, and intelligent tooling.

[![Build](https://github.com/YOUR_USERNAME/termux_forge/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/termux_forge/actions/workflows/build.yml)
[![Tests](https://github.com/YOUR_USERNAME/termux_forge/actions/workflows/test.yml/badge.svg)](https://github.com/YOUR_USERNAME/termux_forge/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Overview

TermuxForge bridges the gap between mobile convenience and desktop-grade development. It provides a beautiful Flutter-based IDE interface that communicates with a Python bridge server running in Termux, giving you access to shell commands, git operations, Flutter builds, MCP servers, GitHub Actions workflows, and more — all from your phone or tablet.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                 Flutter App (UI)                      │
│  ┌─────────┐  ┌──────────┐  ┌──────────────────────┐ │
│  │ Screens │  │ Widgets  │  │ State (Riverpod 3.x) │ │
│  └────┬────┘  └─────┬────┘  └──────────┬───────────┘ │
│       └──────────────┴──────────────────┘             │
│                      │                                │
│              WebSocket Client                         │
└──────────────────────┬───────────────────────────────┘
                       │ JSON-RPC 2.0 over WebSocket
                       │ ws://127.0.0.1:8765
┌──────────────────────┴───────────────────────────────┐
│              Python Bridge (Termux)                   │
│  ┌────────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │  Security  │  │ Command  │  │ Tool Discovery   │  │
│  │  Manager   │  │ Executor │  │                  │  │
│  └────────────┘  └──────────┘  └──────────────────┘  │
│  ┌────────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │    MCP     │  │ Workflow │  │ GitHub Hooks     │  │
│  │  Manager   │  │  Runner  │  │                  │  │
│  └────────────┘  └──────────┘  └──────────────────┘  │
│  ┌────────────┐  ┌──────────┐                        │
│  │   Media    │  │Checkpoint│                        │
│  │   Hooks    │  │  Manager │                        │
│  └────────────┘  └──────────┘                        │
└──────────────────────────────────────────────────────┘
```

## Features

### 🖥️ Terminal & Shell
- Full shell command execution in Termux
- Command safety filtering (blocks destructive operations)
- Output streaming via WebSocket
- Command history with search
- Configurable timeouts and environment variables

### 📁 File Management
- Read, write, edit, list, and search files
- Path sandboxing to approved directories
- Recursive directory listing with depth control

### 🔀 Git Integration
- Status, diff, commit, push, pull
- GitHub CLI integration for workflows
- Build status monitoring
- Artifact downloading
- Release creation

### 🏗️ Flutter & Dart
- `flutter run`, `flutter test`, `flutter build`
- `dart analyze` with structured output
- Device selection and flavor support

### 🤖 MCP Server Management
- Start/stop MCP servers (stdio, SSE, HTTP transports)
- Built-in presets: GitHub, Filesystem, Brave Search, Tavily, Supabase, and more
- Tool discovery from running servers
- Request routing to specific servers
- Health monitoring

### ⚡ Workflow Engine
- Multi-step workflow execution
- Sequential and parallel step groups
- Conditional branching
- Retry logic with configurable delays
- Detailed status reporting

### 📸 Checkpoints
- Create file and git state snapshots
- Compare current state with checkpoints
- Rollback to any checkpoint
- Backup and restore individual files

### 🎨 Media Generation
- Discover configured media providers
- Generate images via OpenAI, Stability AI, Replicate, etc.
- Save outputs as artifacts

### 🔐 Security
- Blocked command pattern matching
- Path validation and sandboxing
- Risk level classification (safe → critical)
- Safety score calculation

## Getting Started

### Prerequisites

- Android device running **Android 7.0+** (API 24)
- [Termux](https://f-droid.org/en/packages/com.termux/) installed from F-Droid
- Python 3.10+ in Termux
- Flutter SDK (for building from source)

### Installation

#### 1. Setup Termux Environment

```bash
# Update packages
pkg update && pkg upgrade -y

# Install Python and essentials
pkg install python git nodejs -y

# Install bridge dependencies
cd ~/termux_forge/python_bridge
pip install -r requirements.txt
```

#### 2. Start the Bridge Server

```bash
python3 ~/termux_forge/python_bridge/termux_forge_bridge.py
```

The bridge server will start on `ws://127.0.0.1:8765`.

#### 3. Install the Flutter App

Download the latest release APK from the [Releases](https://github.com/YOUR_USERNAME/termux_forge/releases) page, or build from source:

```bash
cd ~/termux_forge
flutter pub get
flutter build apk --release
```

### Configuration

#### MCP Servers

Configure MCP servers by setting the appropriate environment variables:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
export TAVILY_API_KEY="tvly-..."
export BRAVE_API_KEY="BSA..."
```

#### Media Providers

```bash
export OPENAI_API_KEY="sk-..."
export STABILITY_API_KEY="sk-..."
```

## Project Structure

```
termux_forge/
├── lib/                          # Flutter app source
│   ├── core/                     # Core utilities, theme, routing
│   ├── data/                     # Data layer (repos, sources)
│   ├── domain/                   # Domain layer (models, interfaces)
│   └── presentation/             # UI layer (screens, widgets)
├── python_bridge/                # Python bridge server
│   ├── termux_forge_bridge.py    # Main WebSocket server
│   ├── command_executor.py       # Safe command execution
│   ├── security.py               # Command safety filtering
│   ├── protocol.py               # JSON-RPC 2.0 protocol
│   ├── tool_discovery.py         # Installed tool detection
│   ├── mcp_manager.py            # MCP server management
│   ├── workflow_runner.py        # Workflow execution engine
│   ├── github_hooks.py           # GitHub CLI integration
│   ├── media_hooks.py            # Media provider integration
│   ├── checkpoint_hooks.py       # Checkpoint management
│   └── requirements.txt          # Python dependencies
├── android/                      # Android platform
├── .github/workflows/            # CI/CD pipelines
│   ├── build.yml                 # Build & test workflow
│   ├── test.yml                  # Test-only workflow
│   └── release.yml               # Tagged release workflow
├── analysis_options.yaml         # Dart analysis config
├── pubspec.yaml                  # Flutter project config
└── README.md                     # This file
```

## JSON-RPC 2.0 API

The bridge uses JSON-RPC 2.0 over WebSocket. Example request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "execute_command",
  "params": {
    "command": "echo Hello, TermuxForge!",
    "cwd": "/data/data/com.termux/files/home",
    "timeout": 30
  }
}
```

### Available Methods

| Category | Methods |
|----------|---------|
| **Commands** | `execute_command`, `kill_command` |
| **Files** | `read_file`, `write_file`, `edit_file`, `list_files`, `search_files` |
| **Git** | `git_status`, `git_diff`, `git_commit`, `git_push`, `git_pull` |
| **Flutter** | `flutter_run`, `flutter_test`, `flutter_build`, `dart_analyze` |
| **Tools** | `check_tool`, `discover_tools`, `install_package` |
| **MCP** | `mcp_server_manage`, `mcp_tool_discover`, `mcp_transport_handle` |
| **Workflows** | `workflow_execute` |
| **Checkpoints** | `checkpoint_create`, `checkpoint_rollback` |
| **Media** | `media_discover` |
| **GitHub** | `github_workflow_trigger`, `github_build_status`, `github_download_artifact` |
| **System** | `version_check`, `workspace_validate`, `get_command_history` |

## CI/CD

TermuxForge uses GitHub Actions for automated builds and releases:

- **`build.yml`** — Triggered on push to `main`/`develop` and PRs. Runs analysis, tests, and builds a release APK.
- **`test.yml`** — Runs unit, widget, integration, and Python bridge tests with a summary report.
- **`release.yml`** — Triggered on version tags (`v*`). Builds a release APK and creates a GitHub Release.

### Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

This automatically triggers the release workflow, which builds the APK and publishes a GitHub Release.

## Development

### Flutter App

```bash
flutter pub get
flutter run
flutter test
```

### Python Bridge

```bash
cd python_bridge
pip install -r requirements.txt
python3 termux_forge_bridge.py
```

### Running Tests

```bash
# Flutter tests
flutter test

# Python tests
cd python_bridge && python -m pytest tests/ -v
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | Flutter 3.x, Material 3 |
| **State** | Riverpod 3.x |
| **Local DB** | Isar |
| **Secure Storage** | flutter_secure_storage |
| **Bridge** | Python 3.12+, websockets, aiohttp |
| **Protocol** | JSON-RPC 2.0 over WebSocket |
| **CI/CD** | GitHub Actions |
| **Platform** | Android (Termux) |

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ for mobile developers who refuse to be limited by their device.**
