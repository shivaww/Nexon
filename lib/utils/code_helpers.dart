// Extracted from main.dart lines 21310-21580
// Extracted: 2026-08-26T13:41:08.257754

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nexon/services/termux_bridge/native_tools_service.dart';

Map<String, dynamic>? findFenceWithKeys(String text, List<String> keys) {
  int from = 0;
  while (true) {
    final open = text.indexOf('```', from);
    if (open == -1) return null;
    final nl = text.indexOf('\n', open);
    if (nl == -1) return null;
    int depth = 0;
    bool inStr = false;
    bool esc = false;
    int close = -1;
    for (int i = nl + 1; i < text.length; i++) {
      final c = text[i];
      if (inStr) {
        if (esc) { esc = false; }
        else if (c == '\\') { esc = true; }
        else if (c == '"') { inStr = false; }
      } else {
        if (c == '"') { inStr = true; }
        else if (c == '{' || c == '[') { depth++; }
        else if (c == '}' || c == ']') {
          depth--;
          if (depth == 0) {
            final fenceEnd = text.indexOf('```', i + 1);
            if (fenceEnd != -1) { close = fenceEnd; }
            break;
          }
        }
      }
    }
    if (close == -1) {
      close = text.indexOf('```', nl + 1);
      if (close == -1) return null;
    }
    final inner = text.substring(nl + 1, close).trim();
    try {
      final dynamic d = jsonDecode(inner);
      if (d is Map<String, dynamic> && keys.any((k) => d[k] != null)) {
        return {'start': open, 'end': close + 3, 'json': d};
      }
    } catch (_) {}
    from = close + 3;
  }
}

/// Returns the tool name when the text contains a fenced ```json tool
/// block ({"t": ...}), else null. Drives the streaming avatar state.
/// Top-level (not a class method): called from ChatSurface and MessageBubble.
String formatTokenUsage(int tokens, int maxTokens) {
  if (tokens <= 0) return '';
  String countStr;
  if (tokens >= 1000000) {
    countStr = '${(tokens / 1000000).toStringAsFixed(1)}M';
  } else if (tokens >= 1000) {
    countStr = '${(tokens / 1000).toStringAsFixed(1)}K';
  } else {
    countStr = '$tokens';
  }
  if (maxTokens > 0) {
    final pct = ((tokens / maxTokens) * 100).round();
    return '$countStr ($pct%)';
  }
  return countStr;
}

bool isKnownToolNameGlobal(String t) {
  const extra = {
    'web_search', 'search_web', 'read_url',
    'quiz', 'quiz_request', 'step_complete',
    'run_background',
    'todo_create', 'todo_done',
  };
  if (NativeToolsService.cppTools.contains(t) || extra.contains(t)) return true;
  if (t.startsWith('workspace_') || t.startsWith('service_') || t.startsWith('dart_')) return true;
  if (t.startsWith('deep_research.') || t.startsWith('mcp_') || t.startsWith('github_') ||
      t.startsWith('checkpoint_') || t.startsWith('workflow_') || t.startsWith('media_')) return true;
  return false;
}

/// General-purpose tools — web search, study/quiz, workspace browsing —
/// whose call and result rows are folded into the assistant's Thought
/// Process block instead of rendering as standalone chat capsules.
/// Agentic file-access tools and deep-research calls stay visible so the
/// user can audit what actually touched their machine.
bool isQuietToolName(String t) {
  const quiet = {
    'web_search',
    'search_web',
    'read_url',
    'quiz',
    'quiz_request',
    'step_complete',
    'todo_create',
    'todo_done',
  };
  if (quiet.contains(t)) return true;
  if (t.startsWith('workspace_')) return true;
  return false;
}

String? detectNativeToolCall(String text) {
  if (!text.contains('```')) return null;
  final m = RegExp(r'"t"\s*:\s*"([a-z_][a-zA-Z0-9_]*)"').firstMatch(text);
  return m?.group(1);
}

/// Locate the first fenced ```json block in [text] whose content parses as
/// a native tool call ({"t":...} or {"calls":[...]}). Returns null when no
/// tool fence exists (plain code fences are skipped). Offsets are relative
/// to [text]. Top-level: called from MessageBubble's rich-content parser.
NativeToolFence? findNativeToolFence(String text) {
  int searchFrom = 0;
  while (true) {
    final openIdx = text.indexOf('```', searchFrom);
    if (openIdx == -1) return null;
    final contentStart = text.indexOf('\n', openIdx);
    if (contentStart == -1) return null;
    final closeIdx = text.indexOf('```', contentStart + 1);
    if (closeIdx == -1) return null;
    final inner = text.substring(contentStart + 1, closeIdx).trim();
    Map<String, dynamic>? parsed;
    try {
      final dynamic decoded = jsonDecode(inner);
      if (decoded is Map<String, dynamic>) {
        final t = decoded['t']?.toString() ?? '';
        final calls = decoded['calls'];
        if (calls is List) {
          bool allKnown = calls.every((c) =>
              c is Map<String, dynamic> &&
              isKnownToolNameGlobal(c['t']?.toString() ?? ''));
          if (allKnown && calls.isNotEmpty) parsed = decoded;
        } else if (t.isNotEmpty && isKnownToolNameGlobal(t)) {
          parsed = decoded;
        } else if (decoded['method'] != null) {
          parsed = decoded;
        }
      }
    } catch (_) {
      parsed = null;
    }
    if (parsed != null) {
      return NativeToolFence(openIdx, closeIdx + 3, parsed);
    }
    searchFrom = closeIdx + 3;
  }
}

class NativeToolFence {
  final int start;
  final int end;
  final Map<String, dynamic> json;
  NativeToolFence(this.start, this.end, this.json);
}

class TodoItem {
  final int n;
  final String title;
  bool done;
  TodoItem({required this.n, required this.title, this.done = false});
}

class TodoListPanel extends StatelessWidget {
  final List<TodoItem> todos;
  final VoidCallback? onClose;
  const TodoListPanel({required this.todos, this.onClose});

  @override
  Widget build(BuildContext context) {
    final done = todos.where((t) => t.done).length;
    final total = todos.length;
    final progress = total > 0 ? done / total : 0.0;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
      color: const Color(0xFFFBF9F4),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5DDD3), width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.checklist, size: 18, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 8),
                  Text('Tasks $done/$total', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D241C))),
                  const Spacer(),
                  if (onClose != null)
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: progress, backgroundColor: const Color(0xFFE5DDD3), valueColor: const AlwaysStoppedAnimation(Color(0xFF059669)), minHeight: 4),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: todos.length,
                itemBuilder: (context, i) {
                  final t = todos[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: t.done ? const Color(0xFFF0FDF4) : const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.done ? const Color(0xFFBBF7D0) : const Color(0xFFE5DDD3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22, height: 22, alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: t.done ? const Color(0xFF059669) : const Color(0xFFE5DDD3)),
                          child: t.done
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : Text('${t.n}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6C5946))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t.title, style: TextStyle(fontSize: 13, color: t.done ? const Color(0xFF86EFAC) : const Color(0xFF2D241C), decoration: t.done ? TextDecoration.lineThrough : TextDecoration.none))),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleSemaphore {
  int _maxConcurrency;
  int _running = 0;
  final List<Completer<void>> _queue = [];

  SimpleSemaphore(this._maxConcurrency);

  int get maxConcurrency => _maxConcurrency;

  set maxConcurrency(int value) {
    if (value == _maxConcurrency) return;
    _maxConcurrency = value;
    _triggerQueue();
  }

  void _triggerQueue() {
    while (_queue.isNotEmpty && _running < _maxConcurrency) {
      _running++;
      final completer = _queue.removeAt(0);
      completer.complete();
    }
  }

  Future<void> acquire() async {
    if (_running < _maxConcurrency) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final completer = _queue.removeAt(0);
      completer.complete();
    } else {
      _running--;
    }
  }

  Future<T> run<T>(Future<T> Function() task) async {
    await acquire();
    try {
      return await task();
    } finally {
      release();
    }
  }
}
