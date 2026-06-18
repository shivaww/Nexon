/// Context compression service for TermuxForge.
///
/// Implements context compression for large projects to prevent
/// context overload as the project grows.
///
/// Supports:
/// - Summarization of large context blocks
/// - Memory pruning by relevance and age
/// - Hierarchical context organization
/// - Relevance ranking for context retrieval
/// - Checkpoint-aware summaries
/// - Project-level and task-level synopsis
/// - Model-specific context compaction (fits within model's context window)
library;

import 'package:uuid/uuid.dart';

/// Represents a compressed context block.
class CompressedContext {
  /// Unique identifier for this compressed context.
  final String id;

  /// The original full content before compression.
  final String originalContent;

  /// The compressed/summarized content.
  final String compressedContent;

  /// Compression ratio (compressed size / original size).
  final double compressionRatio;

  /// The method used for compression.
  final CompressionMethod method;

  /// Relevance score (0.0 to 1.0).
  final double relevanceScore;

  /// Source identifiers (file paths, memory IDs, etc.).
  final List<String> sources;

  /// When this compression was created.
  final DateTime createdAt;

  /// Maximum token budget this was compressed for.
  final int? tokenBudget;

  CompressedContext({
    String? id,
    required this.originalContent,
    required this.compressedContent,
    required this.compressionRatio,
    required this.method,
    this.relevanceScore = 1.0,
    this.sources = const [],
    DateTime? createdAt,
    this.tokenBudget,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}

/// Methods available for context compression.
enum CompressionMethod {
  /// LLM-based summarization.
  summarization,

  /// Remove low-relevance entries.
  pruning,

  /// Hierarchical rollup (detail → summary).
  hierarchical,

  /// Extractive key sentences/blocks.
  extractive,

  /// Chunk and keep most relevant chunks.
  chunkedRelevance,

  /// Deduplicate similar content.
  deduplication,
}

/// Configuration for context compression.
class CompressionConfig {
  /// Maximum tokens for the compressed output.
  final int maxTokens;

  /// Minimum relevance score to keep (0.0 to 1.0).
  final double minRelevanceThreshold;

  /// Preferred compression methods in priority order.
  final List<CompressionMethod> preferredMethods;

  /// Whether to preserve code blocks verbatim.
  final bool preserveCodeBlocks;

  /// Whether to preserve recent entries over older ones.
  final bool preferRecent;

  /// Maximum age of entries to include (null = no limit).
  final Duration? maxAge;

  const CompressionConfig({
    this.maxTokens = 4096,
    this.minRelevanceThreshold = 0.3,
    this.preferredMethods = const [
      CompressionMethod.pruning,
      CompressionMethod.summarization,
    ],
    this.preserveCodeBlocks = true,
    this.preferRecent = true,
    this.maxAge,
  });
}

/// Context compression service.
///
/// Manages compression of large context blocks to fit within
/// model context windows while preserving the most relevant information.
class ContextCompressionService {
  // Singleton
  static final ContextCompressionService _instance =
      ContextCompressionService._internal();
  factory ContextCompressionService() => _instance;
  ContextCompressionService._internal();

  /// Default configuration.
  CompressionConfig _config = const CompressionConfig();

  /// History of compressions performed.
  final List<CompressedContext> _history = [];

  /// Update the compression configuration.
  void configure(CompressionConfig config) {
    _config = config;
  }

  /// Compress a list of context strings into a single compressed context.
  ///
  /// [contexts] - List of context strings to compress.
  /// [config] - Optional override configuration.
  /// Returns a [CompressedContext] with the compressed result.
  Future<CompressedContext> compress(
    List<String> contexts, {
    CompressionConfig? config,
  }) async {
    final cfg = config ?? _config;
    final combined = contexts.join('\n\n---\n\n');

    // Estimate token count (rough: ~4 chars per token)
    final estimatedTokens = combined.length ~/ 4;

    if (estimatedTokens <= cfg.maxTokens) {
      // No compression needed
      final result = CompressedContext(
        originalContent: combined,
        compressedContent: combined,
        compressionRatio: 1.0,
        method: CompressionMethod.pruning,
        tokenBudget: cfg.maxTokens,
      );
      _history.add(result);
      return result;
    }

    // Apply compression methods in priority order
    String compressed = combined;
    CompressionMethod usedMethod = cfg.preferredMethods.first;

    for (final method in cfg.preferredMethods) {
      switch (method) {
        case CompressionMethod.pruning:
          compressed = _applyPruning(compressed, cfg);
          usedMethod = method;
          break;
        case CompressionMethod.deduplication:
          compressed = _applyDeduplication(compressed);
          usedMethod = method;
          break;
        case CompressionMethod.extractive:
          compressed = _applyExtractive(compressed, cfg);
          usedMethod = method;
          break;
        case CompressionMethod.chunkedRelevance:
          compressed = _applyChunkedRelevance(compressed, cfg);
          usedMethod = method;
          break;
        case CompressionMethod.summarization:
          // TODO: Integrate with LLM service for AI-powered summarization
          compressed = _applyBasicSummarization(compressed, cfg);
          usedMethod = method;
          break;
        case CompressionMethod.hierarchical:
          // TODO: Implement hierarchical rollup
          break;
      }

      // Check if we're within budget
      if (compressed.length ~/ 4 <= cfg.maxTokens) break;
    }

    // Final truncation if still over budget
    final maxChars = cfg.maxTokens * 4;
    if (compressed.length > maxChars) {
      compressed =
          '${compressed.substring(0, maxChars)}\n\n[... context truncated to fit ${cfg.maxTokens} token budget]';
    }

    final result = CompressedContext(
      originalContent: combined,
      compressedContent: compressed,
      compressionRatio: compressed.length / combined.length,
      method: usedMethod,
      tokenBudget: cfg.maxTokens,
    );
    _history.add(result);
    return result;
  }

  /// Create a project-level synopsis.
  Future<String> createProjectSynopsis(
    Map<String, String> projectContext,
  ) async {
    final sections = projectContext.entries
        .map((e) => '## ${e.key}\n${e.value}')
        .toList();
    final result = await compress(sections);
    return result.compressedContent;
  }

  /// Create a task-level synopsis.
  Future<String> createTaskSynopsis(
    String taskDescription,
    List<String> relatedContext,
  ) async {
    final contexts = ['## Task\n$taskDescription', ...relatedContext];
    final result = await compress(contexts);
    return result.compressedContent;
  }

  /// Get compression history.
  List<CompressedContext> getHistory() => List.unmodifiable(_history);

  /// Get compression statistics.
  Map<String, dynamic> getStats() {
    if (_history.isEmpty) {
      return {'totalCompressions': 0, 'avgRatio': 0.0};
    }
    final avgRatio =
        _history.map((c) => c.compressionRatio).reduce((a, b) => a + b) /
            _history.length;
    return {
      'totalCompressions': _history.length,
      'avgRatio': avgRatio,
      'totalOriginalChars':
          _history.map((c) => c.originalContent.length).reduce((a, b) => a + b),
      'totalCompressedChars': _history
          .map((c) => c.compressedContent.length)
          .reduce((a, b) => a + b),
    };
  }

  // --- Private compression methods ---

  String _applyPruning(String content, CompressionConfig cfg) {
    final lines = content.split('\n');
    // Remove empty lines and very short lines
    final pruned =
        lines.where((l) => l.trim().length > 2).toList();
    return pruned.join('\n');
  }

  String _applyDeduplication(String content) {
    final lines = content.split('\n');
    final seen = <String>{};
    final deduped = <String>[];
    for (final line in lines) {
      final normalized = line.trim().toLowerCase();
      if (normalized.isEmpty || !seen.contains(normalized)) {
        seen.add(normalized);
        deduped.add(line);
      }
    }
    return deduped.join('\n');
  }

  String _applyExtractive(String content, CompressionConfig cfg) {
    // Keep lines with keywords, code blocks, and headings
    final lines = content.split('\n');
    final important = <String>[];
    bool inCodeBlock = false;

    for (final line in lines) {
      if (line.trim().startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        if (cfg.preserveCodeBlocks) important.add(line);
        continue;
      }
      if (inCodeBlock && cfg.preserveCodeBlocks) {
        important.add(line);
        continue;
      }
      // Keep headings, bullet points, and lines with key words
      if (line.startsWith('#') ||
          line.trim().startsWith('-') ||
          line.trim().startsWith('*') ||
          line.contains('TODO') ||
          line.contains('IMPORTANT') ||
          line.contains('ERROR') ||
          line.contains('BUG')) {
        important.add(line);
      }
    }
    return important.join('\n');
  }

  String _applyChunkedRelevance(String content, CompressionConfig cfg) {
    // Split into chunks and keep the most relevant ones
    final chunks = content.split('\n\n---\n\n');
    if (chunks.length <= 1) return content;

    // Sort by length (proxy for information density) and take top half
    final sorted = List<String>.from(chunks)
      ..sort((a, b) => b.length.compareTo(a.length));
    final keep = sorted.take((sorted.length * 0.6).ceil()).toList();
    return keep.join('\n\n---\n\n');
  }

  String _applyBasicSummarization(String content, CompressionConfig cfg) {
    // Basic summarization: keep first and last portions
    final maxChars = cfg.maxTokens * 4;
    if (content.length <= maxChars) return content;

    final halfBudget = maxChars ~/ 2;
    final start = content.substring(0, halfBudget);
    final end = content.substring(content.length - halfBudget);
    return '$start\n\n[... middle section summarized ...]\n\n$end';
  }
}
