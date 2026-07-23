import 'dart:convert';

/// Shared helpers for Deep Research JSON parsing, budget trimming, and stats.
class DeepResearchHelpers {
  DeepResearchHelpers._();

  /// Extract first JSON object from model output (strips fences / prose).
  static Map<String, dynamic>? parseJsonObject(String raw) {
    if (raw.trim().isEmpty) return null;
    var clean = raw
        .replaceAll(RegExp(r'```json', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(clean);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(0)!);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
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

  /// Whether this is a resume of a partially completed run.
  static bool isResume(Map<String, dynamic> stateMap) {
    final steps = normalizeSteps(stateMap['steps'] as List?);
    if (steps.isEmpty) return false;
    final anyDone = steps.any((s) => s['status'] == 'completed');
    final anyPending = steps.any(
      (s) =>
          s['status'] == 'pending' ||
          s['status'] == 'running' ||
          s['status'] == 'failed',
    );
    return anyDone && anyPending;
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

  /// Client-side budget trim (mirrors bridge export_for_writer logic).
  static Map<String, dynamic> trimEvidenceForWriter(
    List<dynamic> phases, {
    required int maxEvidenceTokens,
  }) {
    if (phases.isEmpty) {
      return {
        'phases': <dynamic>[],
        'token_estimate': 0,
        'truncated_facts': 0,
        'truncated_findings': 0,
        'truncated_phases': 0,
      };
    }

    final working = <Map<String, dynamic>>[];
    for (final phaseVal in phases) {
      if (phaseVal is! Map) continue;
      final phase = Map<String, dynamic>.from(phaseVal);
      final findings = List<Map<String, dynamic>>.from(
        (phase['findings'] is List ? phase['findings'] as List : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
      findings.sort((a, b) {
        int rank(String? c) {
          switch ((c ?? 'high').toLowerCase()) {
            case 'high':
              return 0;
            case 'medium':
              return 1;
            case 'low':
              return 2;
            default:
              return 1;
          }
        }

        return rank(a['confidence']?.toString())
            .compareTo(rank(b['confidence']?.toString()));
      });
      working.add({
        'stage_id': phase['stage_id'] ?? '',
        'phase_title': phase['phase_title'] ?? '',
        'facts': List<Map<String, dynamic>>.from(
          (phase['facts'] is List ? phase['facts'] as List : const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        ),
        'findings': findings,
        'skipped_pdfs': List<dynamic>.from(phase['skipped_pdfs'] ?? const []),
        'failed_fetches':
            List<dynamic>.from(phase['failed_fetches'] ?? const []),
        'status': phase['status'] ?? 'completed',
      });
    }

    var used = 0;
    var truncatedFacts = 0;
    var truncatedFindings = 0;
    final accepted = <Map<String, dynamic>>[];

    for (final phase in working) {
      final base = <String, dynamic>{
        'stage_id': phase['stage_id'],
        'phase_title': phase['phase_title'],
        'facts': <Map<String, dynamic>>[],
        'findings': <Map<String, dynamic>>[],
        'skipped_pdfs': (phase['skipped_pdfs'] as List).take(10).toList(),
        'failed_fetches': (phase['failed_fetches'] as List).take(10).toList(),
        'status': phase['status'],
      };
      final keptFacts = <Map<String, dynamic>>[];
      for (final fact in phase['facts'] as List<Map<String, dynamic>>) {
        final cost = estimateTokens(fact);
        if (used + cost + 40 <= maxEvidenceTokens) {
          keptFacts.add(fact);
          used += cost;
        } else {
          truncatedFacts++;
        }
      }
      base['facts'] = keptFacts;
      accepted.add(base);
    }
    used = estimateTokens(accepted);

    final maxRounds = working.fold<int>(
      0,
      (m, p) =>
          (p['findings'] as List).length > m ? (p['findings'] as List).length : m,
    );
    for (var round = 0; round < maxRounds; round++) {
      for (var pIdx = 0; pIdx < working.length; pIdx++) {
        final findings = working[pIdx]['findings'] as List<Map<String, dynamic>>;
        if (round >= findings.length) continue;
        final finding = findings[round];
        final cost = estimateTokens(finding);
        if (used + cost > maxEvidenceTokens) {
          truncatedFindings++;
          continue;
        }
        (accepted[pIdx]['findings'] as List).add(finding);
        used += cost;
      }
    }

    var nonEmpty = accepted
        .where(
          (p) =>
              (p['facts'] as List).isNotEmpty ||
              (p['findings'] as List).isNotEmpty ||
              (p['skipped_pdfs'] as List).isNotEmpty ||
              (p['failed_fetches'] as List).isNotEmpty,
        )
        .toList();
    var truncatedPhases = 0;
    if (nonEmpty.isEmpty && accepted.isNotEmpty) {
      nonEmpty = [accepted.first];
      truncatedPhases = accepted.length - 1;
    } else {
      truncatedPhases = (phases.length - nonEmpty.length).clamp(0, phases.length);
    }

    return {
      'phases': nonEmpty,
      'token_estimate': estimateTokens(nonEmpty),
      'truncated_facts': truncatedFacts,
      'truncated_findings': truncatedFindings,
      'truncated_phases': truncatedPhases,
    };
  }

  static String formatStatsFooter(Map<String, dynamic> stats) {
    final tokens = stats['estimated_tokens'] ?? 0;
    final searches = stats['searches'] ?? 0;
    final fetches = stats['fetches'] ?? 0;
    final llm = stats['llm_calls'] ?? 0;
    return 'Run stats: ~$tokens tokens · $llm LLM calls · $searches searches · $fetches fetches';
  }
}
