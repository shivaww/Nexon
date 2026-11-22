import 'dart:convert';

/// Shared helpers for Deep Research JSON parsing, budget trimming, and stats.
class DeepResearchHelpers {
  DeepResearchHelpers._();

  /// Strip `<think>`, `<reasoning>`, and `<thought>` blocks (closed or unclosed).
  static String stripReasoningTags(String raw) {
    var text = raw.replaceAll(
      RegExp(
        r'<(think|reasoning|thought)\b[^>]*>[\s\S]*?</\1>',
        caseSensitive: false,
      ),
      '',
    );
    // If a reasoning model truncated inside an unclosed thinking block, strip it.
    text = text.replaceAll(
      RegExp(
        r'<(think|reasoning|thought)\b[^>]*>[\s\S]*$',
        caseSensitive: false,
      ),
      '',
    );
    return text.trim();
  }

  /// Extract a valid JSON object from model output (strips reasoning blocks,
  /// code fences, and prose; uses balanced-brace scanning instead of greedy regex).
  static Map<String, dynamic>? parseJsonObject(String raw) {
    if (raw.trim().isEmpty) return null;
    final stripped = stripReasoningTags(raw)
        .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();
    if (stripped.isEmpty) return null;

    // Fast path: entire response is valid JSON.
    try {
      final direct = jsonDecode(stripped);
      if (direct is Map<String, dynamic>) return direct;
      if (direct is Map) return Map<String, dynamic>.from(direct);
    } catch (_) {}

    // Balanced-brace scan: try each top-level `{...}` candidate in order.
    int i = 0;
    while (i < stripped.length) {
      final start = stripped.indexOf('{', i);
      if (start == -1) break;
      int depth = 0;
      bool inStr = false;
      bool esc = false;
      int end = -1;
      for (int j = start; j < stripped.length; j++) {
        final c = stripped[j];
        if (inStr) {
          if (esc) {
            esc = false;
          } else if (c == '\\') {
            esc = true;
          } else if (c == '"') {
            inStr = false;
          }
        } else if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            end = j + 1;
            break;
          }
        }
      }
      if (end == -1) break;
      try {
        final decoded = jsonDecode(stripped.substring(start, end));
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      i = start + 1;
    }
    return null;
  }

  /// Rough token estimate (~4 chars/token).
  static int estimateTokens(Object? value) {
    final text = value is String ? value : jsonEncode(value);
    if (text.isEmpty) return 0;
    return (text.length + 3) ~/ 4;
  }

  /// Normalize chat-plan steps and loop steps into a common shape.
  static List<Map<String, dynamic>> normalizeSteps(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return [];
    final out = <Map<String, dynamic>>[];
    var i = 1;
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final query = (m['query_text'] ?? m['prompt'] ?? m['title'] ?? '')
          .toString()
          .trim();
      if (query.isEmpty) continue;
      final id = (m['id'] ?? 'step_$i').toString();
      final title = (m['title'] ?? 'Phase $i').toString();
      out.add({
        'id': id,
        'title': title,
        'query_text': query,
        'prompt': query,
        'status': (m['status'] ?? 'pending').toString(),
        'content': m['content']?.toString() ?? '',
        'events': m['events'] is List
            ? List<Map<String, dynamic>>.from(
                (m['events'] as List).whereType<Map>().map(
                      (e) => Map<String, dynamic>.from(e),
                    ),
              )
            : <Map<String, dynamic>>[],
        if (m['error'] != null) 'error': m['error'].toString(),
        if (m['reasoning'] != null) 'reasoning': m['reasoning'].toString(),
      });
      i++;
    }
    return out;
  }

  /// True when the UI already has a usable research plan (skip re-plan).
  static bool hasUsablePlan(Map<String, dynamic> stateMap) {
    if (stateMap['regenerate_plan'] == true) return false;
    final steps = normalizeSteps(stateMap['steps'] as List?);
    if (steps.isEmpty) return false;
    // Require at least one non-empty query distinct from a bare title fallback.
    return steps.any((s) => (s['query_text'] as String).trim().isNotEmpty);
  }

  static Map<String, dynamic> emptyStats() => {
        'llm_calls': 0,
        'searches': 0,
        'fetches': 0,
        'summaries': 0,
        'reflections': 0,
        'estimated_prompt_chars': 0,
        'estimated_completion_chars': 0,
        'estimated_tokens': 0,
      };

  static void bumpStat(Map<String, dynamic> stats, String key, [int by = 1]) {
    stats[key] = ((stats[key] as num?)?.toInt() ?? 0) + by;
    _recomputeTokens(stats);
  }

  static void addCharUsage(
    Map<String, dynamic> stats, {
    int promptChars = 0,
    int completionChars = 0,
  }) {
    stats['estimated_prompt_chars'] =
        ((stats['estimated_prompt_chars'] as num?)?.toInt() ?? 0) + promptChars;
    stats['estimated_completion_chars'] =
        ((stats['estimated_completion_chars'] as num?)?.toInt() ?? 0) +
            completionChars;
    _recomputeTokens(stats);
  }

  static void _recomputeTokens(Map<String, dynamic> stats) {
    final p = (stats['estimated_prompt_chars'] as num?)?.toInt() ?? 0;
    final c = (stats['estimated_completion_chars'] as num?)?.toInt() ?? 0;
    stats['estimated_tokens'] = estimateTokens('x' * (p + c));
  }

  /// Normalize summarizer output into facts/findings with confidence.
  static Map<String, List<Map<String, dynamic>>> normalizeEvidence(
    Map<String, dynamic>? parsed, {
    required String sourceUrl,
    String confidence = 'high',
  }) {
    final facts = <Map<String, dynamic>>[];
    final findings = <Map<String, dynamic>>[];
    if (parsed == null) {
      return {'facts': facts, 'findings': findings};
    }
    final rawFacts = parsed['facts'] is List ? parsed['facts'] as List : const [];
    final rawFindings =
        parsed['findings'] is List ? parsed['findings'] as List : const [];
    for (final item in rawFacts) {
      if (item is! Map) continue;
      facts.add({
        'metric': item['metric']?.toString() ?? '',
        'subject': item['subject']?.toString() ?? '',
        'value': item['value']?.toString() ?? '',
        'date': item['date']?.toString() ?? '',
        'source': sourceUrl,
        'confidence': item['confidence']?.toString() ?? confidence,
      });
    }
    for (final item in rawFindings) {
      if (item is! Map) continue;
      findings.add({
        'text': item['text']?.toString() ?? '',
        'source': sourceUrl,
        'confidence': item['confidence']?.toString() ?? confidence,
      });
    }
    return {'facts': facts, 'findings': findings};
  }

  static String formatStatsFooter(Map<String, dynamic> stats) {
    final tokens = stats['estimated_tokens'] ?? 0;
    final searches = stats['searches'] ?? 0;
    final fetches = stats['fetches'] ?? 0;
    final llm = stats['llm_calls'] ?? 0;
    return 'Run stats: ~$tokens tokens · $llm LLM calls · $searches searches · $fetches fetches';
  }
}
