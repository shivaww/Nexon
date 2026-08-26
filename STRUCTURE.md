# Nexon Project Structure

This document describes the actual directory structure and layout of the Nexon codebase.

```
nexon/
├── .github/workflows/            # GitHub Actions CI/CD workflows
│   └── build.yml                 # Automation pipeline to build and test Nexon release APKs
├── .agents/                      # Agent customizations and guidelines
│   └── AGENTS.md                 # System instructions and behavior rules for AI coding partners
├── assets/                       # UI assets
│   └── icon_transparent.png      # Nexon app logo asset
├── android/                      # Native Android configuration
├── lib/                          # Flutter application codebase
│   ├── core/                     # Theme, configuration, design tokens, app router
│   ├── data/                     # Core data structures and session models
│   ├── domain/                   # Domain declarations (currently using unified data classes)
│   ├── presentation/             # App widgets, layouts, settings, and main screens
│   ├── services/                 # core integration classes (e.g. MCP, LLM clients, permissions)
│   ├── app.dart                  # Material App shell and initialization
│   └── main.dart                 # Application entry point, active chat interface, and tool execution loop
├── python_bridge/                # Zero-dependency Python tool execution server
│   ├── termux_forge_bridge.py     # Main bridge server (WebSocket :8765 + HTTP :8390)
│   ├── mcp_server.py              # Legacy wrapper for termux_forge_bridge.py
│   ├── protocol.py                # JSON-RPC 2.0 protocol, error codes, method router
│   ├── bridge_schema.py           # Cross-bridge schema constants (mirrors Dart side)
│   ├── command_executor.py        # Safe process command runner with filters
│   ├── security.py                # Destructive pattern command safety checks
│   ├── github_hooks.py            # GitHub CLI hooks for builds and releases
│   ├── checkpoint_hooks.py        # Checkpoint state snapshot/rollback helpers
│   ├── media_hooks.py             # AI image generation APIs integration
│   ├── workflow_runner.py         # Process workflow step engines
│   └── requirements.txt           # Production dependencies
├── cpp_bridge/                   # Native C++ tool execution bridge (agentic fast path)
│   ├── tools.cpp                  # Single-file JSON tool binary: file/shell/git ops, snapshots, sandbox
│   ├── py_tool.py                 # Stateless Python shim (chmod/dart_format/read_url) for the py tool
│   └── tools                      # Compiled binary (built by build.sh)
├── test/                         # Unit and Widget tests directory
├── pubspec.yaml                  # Flutter package definition and assets configuration
├── analysis_options.yaml         # Dart static analysis configuration
└── README.md                     # Nexon project documentation
```
