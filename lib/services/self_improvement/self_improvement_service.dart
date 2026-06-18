/// Self-improvement service for TermuxForge.
///
/// Stores and retrieves historical outcomes to make future tasks smarter.
/// Tracks successful/failed workflows, preferred tools, effective models,
/// useful MCP servers, common fixes, benchmarked approaches, and
/// cost-efficient choices.
library;

import 'package:uuid/uuid.dart';

/// Types of improvement insights.
enum InsightType {
  /// A workflow pattern that succeeded.
  successfulWorkflow,

  /// A workflow pattern that failed.
  failedWorkflow,

  /// A tool that proved effective for a task type.
  preferredTool,

  /// A model that performed well for a task type.
  effectiveModel,

  /// An MCP server that provided good results.
  usefulMcpServer,

  /// A common fix pattern for recurring issues.
  commonFix,

  /// A benchmarked approach with measured results.
  benchmarkedApproach,

  /// A reusable code or workflow pattern.
  reusablePattern,

  /// A media generation result with quality metrics.
  mediaResult,

  /// A cost-efficient choice that saved resources.
  costEfficientChoice,
}

/// A single improvement insight learned from past experience.
class ImprovementInsight {
  /// Unique identifier.
  final String id;

  /// Type of insight.
  final InsightType type;

  /// Human-readable title.
  final String title;

  /// Detailed description of the insight.
  final String description;

  /// The context in which this insight was learned.
  final Map<String, dynamic> context;

  /// How many times this insight has been applied.
  int timesApplied;

  /// Success rate when this insight was applied (0.0 to 1.0).
  double successRate;

  /// Tags for categorization.
  final List<String> tags;

  /// When this insight was first learned.
  final DateTime learnedAt;

  /// When this insight was last applied.
  DateTime? lastAppliedAt;

  /// Relevance score (0.0 to 1.0), decays over time if not used.
  double relevanceScore;

  ImprovementInsight({
    String? id,
    required this.type,
    required this.title,
    required this.description,
    this.context = const {},
    this.timesApplied = 0,
    this.successRate = 1.0,
    this.tags = const [],
    DateTime? learnedAt,
    this.lastAppliedAt,
    this.relevanceScore = 1.0,
  })  : id = id ?? const Uuid().v4(),
        learnedAt = learnedAt ?? DateTime.now();

  /// Record that this insight was applied successfully.
  void recordSuccess() {
    timesApplied++;
    final total = timesApplied;
    successRate = ((successRate * (total - 1)) + 1.0) / total;
    lastAppliedAt = DateTime.now();
    relevanceScore = (relevanceScore + 0.1).clamp(0.0, 1.0);
  }

  /// Record that this insight was applied but failed.
  void recordFailure() {
    timesApplied++;
    final total = timesApplied;
    successRate = ((successRate * (total - 1)) + 0.0) / total;
    lastAppliedAt = DateTime.now();
    relevanceScore = (relevanceScore - 0.15).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description,
        'context': context,
        'timesApplied': timesApplied,
        'successRate': successRate,
        'tags': tags,
        'learnedAt': learnedAt.toIso8601String(),
        'lastAppliedAt': lastAppliedAt?.toIso8601String(),
        'relevanceScore': relevanceScore,
      };
}

/// Self-improvement service.
///
/// Learns from past outcomes and provides recommendations for
/// future decisions about tools, models, workflows, and approaches.
class SelfImprovementService {
  // Singleton
  static final SelfImprovementService _instance =
      SelfImprovementService._internal();
  factory SelfImprovementService() => _instance;
  SelfImprovementService._internal();

  /// All stored insights.
  final List<ImprovementInsight> _insights = [];

  /// Record a new insight from a completed task.
  void learnFromOutcome({
    required InsightType type,
    required String title,
    required String description,
    Map<String, dynamic> context = const {},
    List<String> tags = const [],
    bool wasSuccessful = true,
  }) {
    // Check if similar insight already exists
    final existing = _insights.where(
      (i) => i.type == type && i.title == title,
    );

    if (existing.isNotEmpty) {
      final insight = existing.first;
      if (wasSuccessful) {
        insight.recordSuccess();
      } else {
        insight.recordFailure();
      }
      return;
    }

    _insights.add(ImprovementInsight(
      type: type,
      title: title,
      description: description,
      context: context,
      tags: tags,
      timesApplied: 1,
      successRate: wasSuccessful ? 1.0 : 0.0,
    ));
  }

  /// Get insights relevant to a given task context.
  List<ImprovementInsight> getRelevantInsights({
    InsightType? type,
    List<String>? tags,
    double minRelevance = 0.3,
    int limit = 10,
  }) {
    var filtered = _insights.where((i) => i.relevanceScore >= minRelevance);

    if (type != null) {
      filtered = filtered.where((i) => i.type == type);
    }

    if (tags != null && tags.isNotEmpty) {
      filtered = filtered.where(
        (i) => i.tags.any((t) => tags.contains(t)),
      );
    }

    final sorted = filtered.toList()
      ..sort((a, b) {
        // Sort by relevance * success rate
        final scoreA = a.relevanceScore * a.successRate;
        final scoreB = b.relevanceScore * b.successRate;
        return scoreB.compareTo(scoreA);
      });

    return sorted.take(limit).toList();
  }

  /// Get the best model recommendation for a task type.
  String? getBestModelForTask(String taskType) {
    final insights = getRelevantInsights(
      type: InsightType.effectiveModel,
      tags: [taskType],
    );
    return insights.isNotEmpty
        ? insights.first.context['modelId'] as String?
        : null;
  }

  /// Get the best tool recommendation for a task type.
  String? getBestToolForTask(String taskType) {
    final insights = getRelevantInsights(
      type: InsightType.preferredTool,
      tags: [taskType],
    );
    return insights.isNotEmpty
        ? insights.first.context['toolId'] as String?
        : null;
  }

  /// Decay relevance scores for old, unused insights.
  void decayRelevance({Duration maxAge = const Duration(days: 30)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    for (final insight in _insights) {
      final lastUsed = insight.lastAppliedAt ?? insight.learnedAt;
      if (lastUsed.isBefore(cutoff)) {
        insight.relevanceScore =
            (insight.relevanceScore * 0.9).clamp(0.0, 1.0);
      }
    }
  }

  /// Get all insights.
  List<ImprovementInsight> getAllInsights() => List.unmodifiable(_insights);

  /// Get improvement statistics.
  Map<String, dynamic> getStats() {
    return {
      'totalInsights': _insights.length,
      'byType': InsightType.values
          .map((t) => {
                'type': t.name,
                'count': _insights.where((i) => i.type == t).length,
              })
          .toList(),
      'avgSuccessRate': _insights.isEmpty
          ? 0.0
          : _insights.map((i) => i.successRate).reduce((a, b) => a + b) /
              _insights.length,
      'totalApplications':
          _insights.map((i) => i.timesApplied).fold(0, (a, b) => a + b),
    };
  }

  /// Export all insights as JSON.
  List<Map<String, dynamic>> exportInsights() =>
      _insights.map((i) => i.toJson()).toList();

  /// Clear all insights.
  void clear() => _insights.clear();
}
