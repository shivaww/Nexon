# Project Rules for Nexon Agent

Welcome, Agent! You are working on the **Nexon** repository. This is an agentic environment for Termux using Flutter/Dart that integrates LLMs with system tools.

## Critical Guidelines for Project Agents

### 1. Tool Call Format — JSON Only
- This app's tool-call protocol is JSON-only: every call is one fenced ```json block shaped {"t":"toolName","a":{...}}, enforced in lib/services/system_prompts.dart and lib/services/system_prompt_engine.dart.
- Do NOT instruct target LLMs to use XML tags (`<tool_request>`, `<command>`, `<path>...</path>`, etc.) in any system or agent prompt — this contradicted the app's own policy and was the confirmed root cause of a bug where models emitted XML instead of JSON tool calls.
- lib/widgets/message_bubble.dart and lib/widgets/mcp_tool_block.dart still contain XML-tag rendering as a dead safety net (the model is never taught these tags in the live prompts) — do not extend it; fix at the prompt/parsing layer instead.
- The C++ bridge (lib/services/termux_bridge/native_tools_service.dart) is JSON-only end to end. The Python bridge (python_bridge/termux_forge_bridge.py) still has a legacy `<command>` XML fallback parser — treat as legacy, not a pattern to extend.

### 2. Dart & Flutter Coding Standards
- Maintain all existing comments and docstrings.
- Ensure any modifications to [lib/main.dart](file:///data/data/com.termux/files/home/termux_forge/lib/main.dart) do not break the Flutter build.
- Do not introduce external packages unless they are explicitly added to `pubspec.yaml`.

### 3. File Actions
- Use `view_file` to read code. Always specify narrow line ranges (`StartLine` and `EndLine`) when reading files to preserve context and speed.
- Use `replace_file_content` for contiguous edits, and `multi_replace_file_content` for non-contiguous edits. Do not overwrite whole files if you are only changing a few lines.
