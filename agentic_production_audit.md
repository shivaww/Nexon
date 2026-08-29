# Agentic File Access — Production-Readiness Audit

*Independent read-only evaluator. Evidence: read/search only over lib/main.dart, lib/services/system_prompts.dart, lib/services/system_prompt_engine.dart, lib/services/llm/chat_client.dart, lib/services/termux_bridge/native_tools_service.dart, lib/widgets/media_and_model_sheet.dart, cpp_bridge/tools.cpp. No production code modified. Line refs are to the current tree. Section 8 (remediation plan) added on owner request.*

---

## 1. Executive Verdict

**Grade: 6.5 / 10 — a genuinely solid beta, not yet production-grade.**

Can it ship real repo-level work today? **Yes, with caveats:** a single user, on their own local repo, shell permission set to "Allow this session", on small-to-medium tasks (roughly ≤ 15 tool rounds). The core loop works end-to-end: orientation (list/find/outline/recent), scoped multi-query search, paged reads, atomic multi-file patches with rollback, snapshot/undo/audit, checkpoint-at-loop-cap with `/restore`, auto `dart analyze` after `.dart` mutations on both execution paths, and a byte-stable cached system prompt. What holds it back from production tier: **(a)** context management is character-crude — no token budgeting, native ```json tool-call bodies are never stripped from history (only the extinct XML forms are), mid-loop compaction can elide reads a pending patch still depends on, and the 60k-char envelope cliff degrades a big read to a 2,000-char head; **(b)** `sh` has no OS-level jail — the deny-list is bypassable (`rm -r` without `-f`, `find -delete`, `python -c`) and "Always Allow" therefore spans the whole phone, not the workspace; **(c)** `git commit` runs `git add -A`, silently staging the user's unrelated WIP; **(d)** friction/latency mismatches (30s default `sh` timeout vs. `flutter test` on a phone; per-command dialogs with no per-prefix memory); **(e)** one prompt/implementation mismatch ("sparse anchors" promised; every line is numbered). None of these are architectural dead ends — the top five are each fixable in days. Versus opencode / Codex CLI / Claude Code: ahead on on-device tool latency and undo/checkpoint depth, behind on context intelligence, sandboxing, and repo-wide semantic understanding.

---

## 2. Repo-Level Task Walkthroughs (on paper, from code)

### Task A — "fix a failing test in this Flutter repo"

| Step | What happens (evidence) | Verdict |
|---|---|---|
| Orient | `list depth:2` + `search` test name + `outline` impl file batched in one `calls` block; one LLM turn, three results (system_prompts.dart:62–79; main.dart:4192–4200) | ✅ Excellent |
| Read | `read s/e`; 4,000-line cap/file (tools.cpp:1319); multi-file in one call | ✅ Works. ⚠️ Every line carries an `NNN: ` prefix — `ln` defaults **true** (tools.cpp:1364). The prompt's "sparse anchor roughly every 10 lines" (system_prompts.dart:43) **does not exist in the binary** (no `anchor` logic in tools.cpp). ~10–12% of read tokens are line-number overhead, and the model is mis-taught about its own output format. |
| Run tests | `sh {"cmd":"flutter test"}` — **C++ default timeout 30s** (tools.cpp:1161–1163); Dart bridge default 120s, clamp 5–600s +10s headroom (native_tools_service.dart:213–217) | 🔴 **Failure point 1:** a real `flutter test` on a phone routinely exceeds 30s → `err: timeout` → wasted round; the model must guess to pass `to:300`, and the prompt never states the default. Output spill to `.nexon_logs/` head+tail at 24k is good (tools.cpp:385, 1170). |
| Permission | `flutter test` is not in the readonly allow-list (main.dart:3205–3222) → dialog | ⚠️ **Failure point 2:** mid-loop dialog in `ask` mode. "Allow this session" fixes it but resets on app restart; no "remember this command" option. |
| Patch fix | `patch` with exact `o`; atomic batch, preflight + rollback (tools.cpp:1822–1934); auto-snapshot (515); audit entry (581) | ✅ Strong; `not found`/`ambiguous` + `occ` recovery is well-taught |
| Auto-verify | Native path auto-runs `dart analyze <file> | head -20` after patch/edit/create_file on `.dart` (main.dart:2673–2697); Python-bridge path runs full `dart_diagnostics` with PASSED/FAILED markers (3703–3772) | ✅ Runs ungated, no extra dialog. ⚠️ **Failure point 3:** `head -20` can cut off the actual error on multi-error files; single-file analyze misses cross-file breakage; native path emits nothing on success (silence = assumed pass), unlike the bridge path's explicit PASSED marker. |
| Re-run test | `sh` again | ⚠️ Same dialog/timeout dance; no structured test-result parsing — the model eyeballs spilled text |
| Commit | `git a:"commit" m:"..."` → `git add -A && git commit` (tools.cpp:2361) | 🔴 **Failure point 4:** stages **everything** in a dirty repo — the agent silently commits the user's unrelated WIP. No file-scoped add. |

### Task B — "add a feature touching 5 files"

Taught and enforced rhythm: batched read-only calls → one mutation per turn → batched verify → report; ~10–14 LLM round trips.

- ✅ Batching works: read-only calls share one block; execution is serialized through the bridge's FIFO queue but completes in one turn (native_tools_service.dart:61, 298).
- ⚠️ Mutations are strictly one-call-per-turn → 5 edits = 5 turns minimum, each re-sending the full system prompt + history.
- 🔴 **Failure point 5 (mid-loop compaction):** `_compactHistoryForApi` keeps only the **last 3 messages verbatim** (main.dart:3039–3048); a tool round produces 2 messages (assistant call + results), so results from round N−2 onward are "intermediate": >8,000-char reads are cut to 4,000 chars, other tool results to stubs (3054–3097). A 300-line read made two rounds ago can be **halved while its patch is still pending** → `o`-mismatch failures → the re-read the prompt explicitly forbids (system_prompts.dart:45). The harness causes the duplicate work the prompt bans. Worst loop-integrity bug found.
- 🔴 **Failure point 6 (envelope cliff):** a single read whose JSON exceeds 60k chars (≈1,100–1,300 lines — well under the advertised 4,000-line cap) is wrapped by `printResult` into a **2,000-char head** + `output_truncated` note (tools.cpp:3754–3762). Effective read ceiling ≈ 1,200 lines; exceeding it wastes the whole call plus a re-read turn. `read` has no spill-to-disk like `sh` does.
- ⚠️ **History duplication:** assistant messages keep full ```json tool-call bodies (patches with complete old+new text) forever — compaction strips only *legacy XML* `<content>/<patches>` forms (main.dart:3114–3134), never the native JSON calls. Every edit exists twice in history.
- ⚠️ **No input token budget:** nothing counts tokens before sending; `_historyLimit = 50` is UI pagination only (main.dart:371, 7531), not an API bound. Long sessions grow until a provider 400; no auto-summarization, no drop-oldest.
- ✅ Recoverability is excellent: pre-mutation checkpoints (main.dart:2590–2605), 20 snapshots/file with collision-proof names (tools.cpp:503–530), protected `.mpt_backups` with a self-test (`sandbox_escape_refused`, tools.cpp:4050), undo/redo, loop-cap checkpoint at 30 calls with `/restore` (main.dart:2250–2258).

---

## 3. Token-Efficiency Ledger

### Per-turn cost estimate (agentic mode, mid-task, round ~8)

| Component | Chars | ≈ Tokens | Notes |
|---|---|---|---|
| System prompt (identity ~240 + narration ~470 + context ~160 + features ~12.9k + engine scaffold ~0.8k) | ~14,600 | **~3,650** | Sent on **every** call incl. every tool round. Byte-stable → cache-read cheap; full price on first call / cache miss. |
| Assistant message (prose + one tool call) | 400–4,000 | 100–1,000 | Patch calls carry full old+new text |
| Tool result — read 300 lines | ~14,000 | ~3,500 | ~11% is `NNN: ` line-number overhead |
| Tool result — search 100 matches, ctx 3 | 12k–20k | 3,000–5,000 | Well-capped; scoping taught |
| Tool result — sh (spilled) | ≤24,000 | ≤6,000 | Head+tail+disk path |
| Result envelope hard cap | 60,000 | 15,000 | Cliff behavior (§2 Task B) |
| History input at round 8 (compacted) | 60–120k | **15,000–30,000** | Dominant; grows every round |
| Cumulative input, 12-round task | — | **~180–260k** | ~35% reducible |

### Ranked waste cuts

1. **Strip native ```json tool-call bodies from intermediate assistant messages** (keep a one-line `tool + file + n_lines` stub; keep last 2 rounds verbatim). Compaction already does exactly this for the extinct XML format — native JSON was never added. *Code, ~30 lines in `_compactHistoryForApi` (main.dart:3111–3166).* **Saves 500–1,500 tok/edit-round compounding → 20–35% of history in edit-heavy sessions.**
2. **Token-budget the payload** (chars/4 estimate; degrade oldest rounds to stubs before provider 400s). *Code.* Converts hard failures into graceful degradation; bounds worst-case cost.
3. **Fix mid-loop compaction:** while a tool loop is active, keep the last ~8 messages verbatim (or all reads made in the current loop). *Code, ~10 lines.* Eliminates patch-mismatch/re-read cascades — the biggest hidden sink.
4. **Give `read` spill-to-disk head+tail (~24k) like `sh`** instead of the 2,000-char envelope cliff. *Code ~15 lines in toolMultiRead + 1 prompt line.* Saves a wasted truncated call + re-read per occurrence.
5. **Implement sparse anchors or default `ln:false`.** *Code + prompt (prompt text already written).* ~10% off every read; fixes a documented-behavior lie.
6. **Suppress duplicate verification:** teach "verify OR batch diagnostics, not both" (auto-verify already ran; a batched `diagnostics` in the same reply re-pays the analyzer output). *Prompt, 1 line.*
7. **Compress the three worked examples** in `<examples>` (~2.6k chars → ~1.5k). *Prompt.* Low priority — cached prefix.

### Structure notes
- ✅ Byte-stable prompt; variable `user_info` (incl. date) last (system_prompt_engine.dart:125–198) — correct for KV-cache reuse; verified.
- ✅ Reasoning text is stored per-message but **not** re-sent (chat_client.dart:280–308 maps only `message.text`).
- ✅ Streaming for UX; tool extraction runs after full text — no token penalty.
- ⚠️ Compaction triggers at >4 messages / 8,000-char threshold — fine across user turns, harmful inside tool loops (cut #3).

---

## 4. Environment-Usage Scorecard

| Capability | Taught? | Implemented? | Grade |
|---|---|---|---|
| outline-before-read | ✅ | ✅ C++ outline | A |
| search-before-read, scoped paths | ✅ | ✅ multi-query single walk; ctx 0–20; max 100 (ceiling 10k) | A |
| Paged reads (s/e) | ✅ | ✅ but envelope cliff | B |
| Head+tail log discipline + spill to disk | ✅ | ✅ spillOutput, `.nexon_logs/` | A |
| Batched read-only calls | ✅ | ✅ one turn, serial FIFO exec | B+ |
| Mutation rhythm (one per turn, verify after) | ✅ | ✅ | A |
| Background services vs polling | ✅ run_background + DONE/FAILED | ✅ python bridge | A− |
| Todos / plan | ✅ auto-trigger 2+ tasks, /plan | ✅ | B+ |
| py shim | ✅ | ✅ chmod/dart_format/read_url via shim (tools.cpp:3679) | B |
| MCP extensibility | mentioned | ✅ passthrough incl. remote URL override (main.dart:2744–2748) | B |
| Auto-verify after .dart edits | implied | ✅ both paths (native inline; bridge `_autoVerifyMutation`) | B |
| Structured test-runner results | ❌ | ❌ text only | D |
| LSP / cross-file references | ❌ | ❌ regex search + single-file outline | D |
| Context pruning / summarization | ❌ | ❌ char truncation only | D |
| Sub-agents | ❌ | ❌ | F (n/a) |
| Interrupted-loop resume | partial | ✅ checkpoint + `/restore`, but loop state dies with the app | C |

---

## 5. Parity Gap List vs opencode / Codex CLI / Claude Code

| # | Gap | Impact | Effort | Side | Design sketch |
|---|---|---|---|---|---|
| 1 | Input token budgeting + summarizing compaction (all three have context mgmt) | High | Med | code | Estimate chars/4 per message; when over budget, replace oldest rounds with a generated summary ("files read: X@lines; edits: …"), keep last N verbatim. |
| 2 | Shell sandbox (Codex: seatbelt/landlock; claude-code: sandboxed exec) | High | High | code+infra | No landlock on Android/Termux. Ladder: (a) `proot`-confined exec inside workspace; (b) env-strip HOME/PATH + cwd jail for spawned cmds; (c) minimum: per-prefix permission memory and drop persistent "Always Allow". Today's deny-list (rm −rf, chmod 777, dd if=, force-push — main.dart:3190–3196) is bypassable by `rm -r`, `find -delete`, `python -c`: it's friction, not security. |
| 3 | `git commit` staging scope | High | Low | code | Track agent-written paths from patch/edit/create_file results; commit accepts `f:[paths]` and stages only those; fall back to warn + `git status --short` when the repo was dirty pre-task. |
| 4 | Structured test/analyze results | Med | Low | code+prompt | `diagnostics` already parses `file:line:col` (tools.cpp:3599); add `flutter test --reporter json` parsing → `{failed:[names], passed:n}`. |
| 5 | Cross-file symbol index (opencode LSP, claude references) | Med | Med | code (C++) | Build `symbol → file:line` map during list/search walks; cache in `.nexon_logs/`; add `refs` tool. Unlocks "change signature across 5 files". |
| 6 | Permission memory / patterns (claude "don't ask again for `npm test`") | Med | Low | code | Store approved command prefixes per workspace; match by first-2-segments prefix. |
| 7 | True parallel read-only execution | Low-Med | Med | code (C++) | `calls` batch → 3–4-thread pool for read/search/outline with a mutex on the output queue; phone SoCs are 8-core. |
| 8 | Diff preview UI for patches (all three render diffs) | Med | Low | UI | `_fileMutationPreview` plumbing exists; render unified o-vs-n diff in the permission dialog — also builds trust for trusted-path silent edits. |
| 9 | Session/loop resume (codex session resume, claude continue) | Med | Med | code | Persist loop transcript + todo state; on restart offer "resume from checkpoint". |
| 10 | Plan mode as first-class mode (claude plan/acceptEdits/bypass) | Low | Low | prompt+code | `/plan` exists; add read-only mode that hard-filters mutations at dispatch, and plan→todos confirmation. |

**Mobile/Termux context:** single device, local bridges, no cloud sandbox — every gap in #2 lands on the user's phone; conversely the persistent C++ process gives ms-level tool latency no networked harness matches, and everything but the LLM API works offline. Battery/thermal argue for modest parallelism (#7). One supply-chain note: binary discovery scans `$HOME/storage/shared/Download/tools` (native_tools_service.dart:96) — any file named `tools` in Downloads gets executed; prefer explicit path + checksum pin.

---

## 6. Quick Wins (smallest change → largest gain)

1. **Strip native tool-call JSON from intermediate assistant history** — ~30 lines in main.dart:3111–3166. Biggest token win; removes edit-text duplication.
2. **`sh` default timeout 30s → 120s** (tools.cpp:1161) + one prompt line: "builds/tests: pass `to:300`". Kills the most common wasted round.
3. **Scoped `git commit`** — track agent-written files; `f` param (tools.cpp:2353–2361). ~20 lines; prevents silently committing user WIP.
4. **`read` spill-to-disk head+tail (~24k) like `sh`** instead of the 60k envelope cliff (tools.cpp:1315–1380 + 3754). Saves a full wasted call + re-read per big file.
5. **Permission memory:** "Always allow commands starting with `flutter test`" option in the shell dialog (main.dart:3339–3363). Removes the dominant mid-loop friction.

---

## 7. What Is Already Genuinely Strong

- **Transport:** one persistent C++ process, one-line JSON protocol, no HTTP/Python hop for file ops (native_tools_service.dart:21–35); the C++ reader even tolerates multi-line JSON via a brace accumulator with 64MB overflow and unbalanced-EOF guards (tools.cpp:4340–4391).
- **Edit safety:** atomic multi-file patches with preflight + write-phase rollback (tools.cpp:1822–1934); auto-snapshot before every mutation with 20/file retention, collision-proof names, protected `.mpt_backups`; append-only `audit.jsonl`; `undo`/redo; base64 escape hatch for patch text (getTextOrB64) sidestepping JSON-escaping corruption.
- **Loop safety net:** 30-call cap triggers a checkpoint + `/restore` message rather than a hard stop (main.dart:2250–2258); bridge restart cap (5) with 30s cooldown; no-retry policy for backgrounded/sleep commands; malformed-truncation detection on the Dart side (native_tools_service.dart:283–295).
- **Self-testing binary:** tools.cpp ships built-in checks including `sandbox_escape_refused` and JSON depth caps (tools.cpp:4048–4052).
- **Prompt engineering:** decision guide, SOPs, batching examples, forbidden-format list, and paging guidance are unusually good; caps documented in the prompt match the implementation (verified).
- **KV-cache discipline:** byte-stable system prompt on every send, variable `user_info` (date/model) last; reasoning text never re-sent.
- **Shell gating:** deny-wins segment classification with a readonly auto-approve list — the right shape even if the lists need hardening.
- **Mode hygiene:** exclusivity enforced at load and toggle time; agentic gated on binary presence; blank-workspace guard (verified, not re-flagged).

---

## 8. Remediation Plan (added on owner request)

Three independently shippable phases. All sketches target the exact lines cited above; none applied by this audit.

### Phase 1 — Token efficiency & loop integrity (~1 weekend, biggest payoff)

**1.1 Strip native JSON tool calls from intermediate history** (~30 lines, main.dart:3111–3166)

```dart
if (newText.length > 2500) {
  newText = newText.replaceAllMapped(
    RegExp(r'```json\s*\n([\s\S]*?)\n```'),
    (m) {
      try {
        final d = jsonDecode(m.group(1)!);
        if (d is Map && (d['t'] != null || d['calls'] != null)) {
          final names = d['calls'] is List
              ? (d['calls'] as List).map((c) => c['t']).join(',')
              : d['t'];
          return '[tool call: $names — body omitted for context space]';
        }
      } catch (_) {}
      return m.group(0)!; // not a tool call (prose JSON) — keep verbatim
    },
  );
  // existing XML stripping stays
}
```

Only intermediates are touched (the verbatim tail bypasses this branch). **Saves 20–35% of history in edit-heavy sessions.**

**1.2 Widen the verbatim tail inside tool loops** (~10 lines, main.dart:3039–3048)

```dart
final bool inToolLoop = rawHistory.reversed.take(12).any(
  (m) => m.role == MessageRole.system && m.text.startsWith('Tool Result ['));
final tailKeep = inToolLoop ? 8 : 3; // 8 ≈ last 4 rounds
final intermediateEndIndex = rawHistory.length - tailKeep - 1;
```

Combined with 1.1 the wider tail is nearly free (calls are already stubbed). Kills the patch-mismatch failures where a pending edit's source read got halved.

**1.3 Token budget before send** (~25 lines, before sendChatStream at main.dart:2027)

```dart
int estTokens(List<ChatMessage> l) => l.fold(0, (s, m) => s + m.text.length ~/ 4);
const kHistoryBudget = 90000; // expose per-model in settings later

var est = estTokens(historyForApi);
for (var i = 1; i < historyForApi.length - 8 && est > kHistoryBudget; i++) {
  final m = historyForApi[i];
  if (m.text.length > 200) {
    final stub = '[context space: turn ${i} omitted]';
    est -= (m.text.length - stub.length) ~/ 4;
    historyForApi[i] = ChatMessage(role: m.role, text: stub);
  }
}
```

Drop-oldest-to-stub is v1; an LLM-generated summary is the v2 upgrade. Converts provider 400s into graceful degradation.

**1.4 `sh` timeout 30s → 120s** (one constant, tools.cpp:1161) + prompt line at system_prompts.dart:129:
`sh: default timeout 120s; on-device builds/tests need "to":300.`

### Phase 2 — Safety correctness (second weekend)

**2.1 Scoped `git commit`** (tools.cpp:2353–2361) — make `git add -A` opt-in:

```cpp
const std::vector<Json>* files = args.getArr2("f", "files");
std::string ensureX = "mkdir -p .git/info && { grep -qxF '.mpt_backups/' "
                      ".git/info/exclude 2>/dev/null || echo '.mpt_backups/' >> .git/info/exclude; }";
if (files && !files->empty()) {
    std::string adds;
    for (auto& fj : *files) adds += "git add -- " + shellQuote(fj.str()) + " && ";
    cmd = ensureX + " && " + adds + "git commit -m " + shellQuote(m);
} else if (args.getBool2("all", "stage_all")) {
    cmd = ensureX + " && git add -A && git commit -m " + shellQuote(m);
} else {
    r.set("err", "'f' (files to stage) or \"all\":true required — refusing to stage unrelated changes");
    return r;
}
```

Model drives it via prompt: `git commit: {"a":"commit","m":"...","f":["lib/a.dart"]}`; `"all":true` stages everything explicitly. `audit.jsonl` already records every agent-written file, so the app can auto-suggest the `f` list later. No app-side interception — keeps "tool results are ground truth".

**2.2 `read` spill-to-disk instead of the envelope cliff** (~15 lines, tools.cpp:1378) — reuse the existing primitive:

```cpp
std::string content = out.str();
const long kReadCap = 24000; // per-file parity with sh
if ((long)content.size() > kReadCap) {
    entry.set("c", Json::Str(spillOutput(content, kReadCap, baseDir, "read")));
    entry.set("spilled", Json::Bool(true));
} else entry.set("c", Json::Str(content));
```

Prompt gains: "read: a slice over ~24k chars returns head+tail + disk path — re-request a narrower s/e."

**2.3 Sparse anchors** (~10 lines, tools.cpp:1367–1372) — implement what system_prompts.dart:43 already promises:

```cpp
for (long i = start; i <= end && i <= (long)lines.size(); ++i) {
    const bool anchor = (i == start) || (i == end) || (i % 10 == 0);
    if (anchor) { char b[32]; snprintf(b, 32, "%*ld: ", width, i); out << b; }
    else out << "   ";
    out << lines[i-1] << "\n";
}
```

Safe for patching (`o` matches text, never line numbers). ~10% off every read; fixes the documented-behavior lie with zero prompt change.

**2.4 Shell hardening: expanded deny-list + prefix permission memory.** Interim additions to main.dart:3190–3196 until a real jail:

```dart
RegExp(r'\brm\s+-[a-zA-Z]*[rf]'),          // any rm with -r or -f
RegExp(r'\bfind\b.*(-delete|-exec\s+rm)'),
RegExp(r'\b(shred|truncate)\b'),
RegExp(r'>\s*/dev/(sd|block)'),
RegExp(r'\b(curl|wget)\b[^|]*\|\s*(ba)?sh'),
```

Prompt line: "Delete files with `fileops` (snapshotted, undoable) — never `rm`." Drop the persistent global "Always Allow" button (keep session + prefix memory):

```dart
final Map<String, bool> _shellPrefixAllowed = {}; // persisted per workspace
bool _prefixAllowed(String cmd) {
  final s = cmd.trim().split(RegExp(r'\s+'));
  return s.length >= 2 && _shellPrefixAllowed['${s[0]} ${s[1]}'] == true;
}
// In _askShellPermission, after the readonly check:
if (_prefixAllowed(command)) return true;
```

Dialog gains "Always allow `flutter test`" → stores the two-segment prefix. Removes the dominant mid-loop friction without opening the whole phone.

**2.5 Native auto-verify parity** (~5 lines, main.dart:2684–2697): drop `| head -20` (spillOutput handles size) and emit the PASSED marker the bridge path already has:

```dart
if (!(diagResult['out'] as String).contains('error')) {
  toolOutputs.add('Tool Result [auto_verify]: PASSED (dart analyze, 0 errors)');
}
```

### Phase 3 — Parity features (later, by value/effort)

1. **Structured test results** — new `test` tool in tools.cpp parsing `flutter test --reporter json` → `{passed:n, failed:[{name,reason}]}`; the model stops eyeballing spilled logs.
2. **Cross-file symbol index** — build `symbol → file:line` during search/list walks, cache in `.nexon_logs/`, add `refs` tool. Unlocks "rename symbol across 5 files" without LSP.
3. **Diff preview in the permission dialog** — `_fileMutationPreview` plumbing exists; render `o` vs `n` unified diff.
4. **Loop/session resume** — persist tool-loop transcript + todos; "resume from checkpoint" on restart.
5. **Parallel read-only batch** — 3–4 threads for read/search/outline in the `calls` path.
6. **Real sandbox** — `proot`-confined `sh` inside the workspace; the only genuinely hard item.

### What NOT to do

- **Don't intercept/rewrite tool calls app-side** (e.g., silently injecting the file list into `git commit`) — it breaks the "tool results are ground truth" contract and adds a second brain. Keep logic in the tool + prompt.
- **Don't build LSP yet** — the symbol index delivers ~80% of the value at ~10% of the effort on-device.
- **Don't chase parallel mutations** — one-mutation-per-turn is a correctness feature; keep it.

### Expected outcome

Phase 1+2 ≈ 200 lines of Dart, ~80 of C++, a handful of prompt lines → audit grade moves from **6.5 to roughly 8**: history cost down 25–35%, zero provider-400 sessions, no silently-committed WIP, no bypassable `rm`, no envelope cliffs, friction-free `flutter test` loops. Remaining gap to opencode/Codex/Claude Code after that is the sandbox and repo-wide semantics (Phase 3).

**Suggested implementation order:** 1.1 → 2.1 → 1.4 → 1.2 → 2.4 → 1.3 → 2.2 → 2.3 → 2.5. Each step is independently shippable and testable via the binary's built-in self-tests plus a scripted 5-file feature task.
