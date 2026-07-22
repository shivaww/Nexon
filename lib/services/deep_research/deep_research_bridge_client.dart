import 'dart:convert';
import 'dart:io';

/// Thin HTTP client for Deep Research bridge methods (JSON-RPC style).
class DeepResearchBridgeClient {
  DeepResearchBridgeClient({
    this.endpoint = 'http://127.0.0.1:8390/mcp',
  });

  final String endpoint;

  Future<Map<String, dynamic>> call(
    String method, {
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'method': method,
        'params': params,
      }));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        throw HttpException(decoded['error'].toString());
      }
      final result = decoded is Map ? decoded['result'] : null;
      if (result is Map<String, dynamic>) return result;
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'raw': result};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> reset({bool keepCheckpoint = false}) async {
    await call(
      'deep_research.reset',
      params: {'keep_checkpoint': keepCheckpoint},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> updatePhase({
    required String stageId,
    required String phaseTitle,
    required List<dynamic> facts,
    required List<dynamic> findings,
    required List<dynamic> skippedPdfs,
    required List<dynamic> failedFetches,
    String status = 'running',
  }) async {
    await call(
      'deep_research.update_phase',
      params: {
        'stage_id': stageId,
        'phase_title': phaseTitle,
        'facts': facts,
        'findings': findings,
        'skipped_pdfs': skippedPdfs,
        'failed_fetches': failedFetches,
        'status': status,
      },
      timeout: const Duration(seconds: 30),
    );
  }

  Future<String> exportTemp() async {
    final result = await call(
      'deep_research.export_temp',
      timeout: const Duration(seconds: 120),
    );
    final content = result['content'];
    if (content is String) return content;
    throw const FormatException('Missing deep research export content');
  }

  Future<Map<String, dynamic>> exportForWriter({
    required int maxEvidenceTokens,
  }) async {
    return call(
      'deep_research.export_for_writer',
      params: {
        'max_evidence_tokens': maxEvidenceTokens,
        'prefer_facts': true,
      },
      timeout: const Duration(seconds: 120),
    );
  }

  Future<void> saveCheckpoint({
    required String runId,
    required String status,
    required int currentPhaseIndex,
    required List<dynamic> steps,
    required Map<String, dynamic> stats,
  }) async {
    await call(
      'deep_research.save_checkpoint',
      params: {
        'run_id': runId,
        'status': status,
        'current_phase_index': currentPhaseIndex,
        'steps': steps,
        'stats': stats,
      },
      timeout: const Duration(seconds: 20),
    );
  }

  Future<Map<String, dynamic>> loadCheckpoint() async {
    final result = await call(
      'deep_research.load_checkpoint',
      timeout: const Duration(seconds: 20),
    );
    final cp = result['checkpoint'];
    if (cp is Map<String, dynamic>) return cp;
    if (cp is Map) return Map<String, dynamic>.from(cp);
    return {};
  }

  Future<void> clearCheckpoint() async {
    await call(
      'deep_research.clear_checkpoint',
      timeout: const Duration(seconds: 15),
    );
  }

  /// Single I/O path for HTML fetch; the bridge always skips PDFs.
  Future<Map<String, dynamic>> readUrl(
    String url, {
    bool allowPdf = false,
  }) async {
    return call(
      'read_url',
      params: {
        'url': url,
        'allow_pdf': allowPdf,
      },
      timeout: const Duration(seconds: 90),
    );
  }

  Future<Map<String, dynamic>> webSearch(
    String query, {
    String? topic,
    String? timeRange,
    String? startDate,
    String? endDate,
    String searchDepth = 'basic',
  }) async {
    return call(
      'web_search',
      params: {
        'query': query,
        if (topic != null) 'topic': topic,
        if (timeRange != null) 'time_range': timeRange,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'search_depth': searchDepth,
      },
      timeout: const Duration(seconds: 60),
    );
  }
}
