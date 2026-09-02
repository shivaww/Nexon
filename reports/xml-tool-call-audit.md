# XML vs JSON Tool-Call Audit — Nexon/TermuxForge

Status: in progress (orienting pass 2)

## Confirmed findings

### 1. JSON-only instructions are present and consistent
lib/services/system_prompts.dart (~54-58, ~464-468, ~554-558) and lib/services/system_prompt_engine.dart (~33-36) both forbid <invoke>, <tool_call>, <function_call>, <tool_use>, <function>, <parameter> and mandate the {t,a} JSON shape inside a json fence. Not a missing-instruction problem.

### 2. Execution-side XML fallback covers 6 dialects, display-side re-fencing covers only 1
lib/main.dart _findXmlToolCalls() (~4333-4484) recognizes and converts to executable form: invoke/parameter, tool_call, function_call, tool_use, function/param, and a generic tag==toolname format. But _fenceBareToolCalls() (~4547-4622), whose doc comment says it exists so the renderer shows tool cards instead of raw text, only re-wraps the invoke/tool_calls dialect into a json fence for display. The other five dialects get executed via _findXmlToolCalls (called ~4313) but their raw XML text is never converted for rendering. Likely root cause of the reported symptom: the call may still run, but the user sees raw XML on screen for any model whose native format is tool_call/function_call/tool_use style (common on Hermes/Qwen/GLM/Kimi-tuned models). Needs confirming against the actual render call site.

### 3. Bridge tooling bug: outline returns empty for Dart files
outline on llm_service.dart, llm_types.dart, system_prompts.dart, system_prompt_engine.dart all returned zero symbols despite each file clearly containing classes/functions (confirmed via direct read/search). The Dart symbol detector in cpp_bridge/tools.cpp looks broken or incomplete for this codebase — worth a dedicated look once the main audit is done.

## Open questions
- Where is _fenceBareToolCalls() actually called relative to the stream/render pipeline?
- Do content_parser.dart / mcp_tool_block.dart / message_bubble.dart have their own separate XML handling, or do they rely entirely on main.dart pre-processing?
- Is a tools/functions param being sent to any provider (native function-calling), which would make the model default to its own XML dialect regardless of prompt instructions?

## Confirmed: render path
_fenceBareToolCalls(fullText) is exactly what's stored as rendered message text (lib/main.dart ~2142, ~2205-2207). Confirms finding #2: only invoke/tool_calls gets re-fenced for display; the other 5 XML dialects execute via _findXmlToolCalls (called from _findNativeToolCalls ~4313) but are never cleaned up for display — user sees raw XML even when the call succeeds.

## New: parallel/legacy tag-parsing systems not covered by system_prompts.dart's forbidden list
- lib/widgets/mcp_tool_block.dart: McpToolBlock widget has its own independent isXml-gated regex parser (<method>, generic tag).
- lib/widgets/message_bubble.dart (~562-570): tag table for <search_request>, <read_url>, <mcp_request>, <tool_request> (isXml:true), <command> (isXml:true), <workspace_list>, <workspace_search>, <workspace_cross_compare> — none appear in system_prompts.dart's forbidden list or _findXmlToolCalls's 6 dialects. Investigating whether python_bridge/ or another prompt path still teaches the model this format.

## Root cause theory: XML is a first-class parallel format, not filtered noise
- .agents/AGENTS.md explicitly instructs AI assistants working on this codebase to keep using <tool_request>-style tags when designing agent prompts — directly contradicts system_prompts.dart's JSON-only policy. This is a live risk: any AI-assisted edit that reads AGENTS.md could reintroduce XML instructions.
- lib/widgets/message_bubble.dart (~561-798, current code) has full production rendering for <tool_request>, <command>, <mcp_request>, <search_request>, <workspace_*> — mirrors main.dart.bak ~11558-11800 almost exactly, meaning it was deliberately carried forward, not dead legacy.
- python_bridge/protocol.py (~378-384) docstring: "Flutter's XML tool format sends every value as a string" — confirms Flutter itself still emits XML tool calls on some path to the Python bridge.
- python_bridge/termux_forge_bridge.py (~1769-1774): live <command> XML fallback parsing.
- Contradicts lib/services/termux_bridge/native_tools_service.dart (~24-26) which describes the newer C++ bridge as JSON-only, "no XML anywhere in the chain."
- Conclusion: two parallel bridges exist (C++/JSON-only vs Python/XML-capable). If any routing path still uses or falls back to the Python bridge, that subsystem is XML-native regardless of the main system prompt's JSON instructions.
- test/circuit_breakers_test.dart has detectMalformedTags() checking for raw <search_request>/<read_url>/<mcp_request> leaking to users — confirms team already knew of leakage; checking if wired into production or test-only.

## Confirmed: dead safety-net code
Project-wide search for <tool_request>, <mcp_request>, <workspace_*> etc. across system_prompts.dart / system_prompt_engine.dart / deep_research_prompts.dart returned 0 hits — the model is never taught these tags. The rendering/parsing code for them, and detectMalformedTags() in test/circuit_breakers_test.dart, are a dead safety net: if a model drifts into this XML on its own, nothing in production flags it.

## Root cause A (confirmed): native provider tool-calling is live
lib/services/llm/llm_service.dart:230 sends 'tools': sortedTools in the request body when non-null. For any provider/model with native function-calling support, the model's own fine-tuned tool-call scaffold governs output shape — the app's JSON-only system-prompt text cannot override a provider's native calling convention. Pending: sortedTools definition / which providers this reaches.

## Root cause B (confirmed via static analysis): system prompt is itself XML, and the cleanup step can strip the very examples it needs
lib/services/system_prompt_engine.dart assemble() wraps the whole prompt in literal <identity>/<context>/<narration>/<safety>/<conduct>/<features>/<skills>/<user_info> tags. The anti-XML rule lives inside <conduct>, i.e. the 'no XML' instruction is delivered inside an XML-structured document — conflicting signal, since models weight surrounding structure heavily.
Worse: assembleClean()'s _stripXml() regex (</?[a-zA-Z][a-zA-Z0-9_:-]*>) does not distinguish structural wrapper tags from literal quoted examples inside the text. The _conduct string's own examples '<invoke>' and '<tool_call>' match this regex and would be silently deleted if assembleClean() is the path actually used — turning the instruction into 'no , , or similar tags', destroying the examples the model needs. Confirmed correct via regex analysis; pending confirmation of which method (assemble vs assembleClean) is wired into the actual request path.

## This round: fixes applied + .bak investigation
- Patched lib/main.dart _fenceBareToolCalls to also re-fence <tool_call>, <function_call>, <tool_use>, <function name=...> (previously only <invoke>/<tool_calls> got re-fenced for display — finding #2).
- Patched .agents/AGENTS.md section 1 to state the JSON-only policy correctly, so future AI-assisted edits stop reintroducing XML tag instructions (finding #4).
- Investigating whether lib/main.dart.bak is referenced by build/extraction tooling (batch_extract.py, extraction_manifest.json) or git history before deleting — not deleted yet, pending this round's results.
- Still open: #1 (native 'tools' param sent alongside the JSON-text protocol — needs tracing sortedTools/tools origin per model/provider before a safe fix), #3 (prompt itself is XML-structured while instructing the model not to emit XML — needs a delimiter-format decision, not a blind patch).
