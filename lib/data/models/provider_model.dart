/// LLM provider and model data models.
///
/// [ProviderModel] represents an LLM API provider (OpenAI, Anthropic, etc.),
/// [AIModelInfo] describes a specific model offered by a provider, and
/// [BattleResult] records the outcome of a head-to-head model comparison.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// AIModelInfo
// ---------------------------------------------------------------------------

/// Describes a specific AI / LLM model available through a provider.
class AIModelInfo extends Equatable {
  /// Creates a new [AIModelInfo].
  const AIModelInfo({
    required this.id,
    required this.name,
    required this.providerId,
    this.contextWindow = 0,
    this.capabilities = const [],
    this.costPerInputToken = 0.0,
    this.costPerOutputToken = 0.0,
    this.speed = 'medium',
    this.isAvailable = true,
  });

  /// Unique model identifier (e.g. "gpt-4o").
  final String id;

  /// Human-readable display name.
  final String name;

  /// ID of the [ProviderModel] that hosts this model.
  final String providerId;

  /// Maximum context window in tokens.
  final int contextWindow;

  /// List of capability tags (e.g. "vision", "function-calling").
  final List<String> capabilities;

  /// Cost per input token (USD).
  final double costPerInputToken;

  /// Cost per output token (USD).
  final double costPerOutputToken;

  /// Speed classification label (e.g. "fast", "medium", "slow").
  final String speed;

  /// Whether this model is currently available.
  final bool isAvailable;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'providerId': providerId,
      'contextWindow': contextWindow,
      'capabilities': capabilities,
      'costPerInputToken': costPerInputToken,
      'costPerOutputToken': costPerOutputToken,
      'speed': speed,
      'isAvailable': isAvailable,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory AIModelInfo.fromJson(Map<String, dynamic> json) {
    return AIModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      providerId: json['providerId'] as String,
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 0,
      capabilities: List<String>.from(
        (json['capabilities'] as List?) ?? [],
      ),
      costPerInputToken:
          (json['costPerInputToken'] as num?)?.toDouble() ?? 0.0,
      costPerOutputToken:
          (json['costPerOutputToken'] as num?)?.toDouble() ?? 0.0,
      speed: (json['speed'] as String?) ?? 'medium',
      isAvailable: (json['isAvailable'] as bool?) ?? true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        providerId,
        contextWindow,
        capabilities,
        costPerInputToken,
        costPerOutputToken,
        speed,
        isAvailable,
      ];
}

// ---------------------------------------------------------------------------
// ProviderModel
// ---------------------------------------------------------------------------

/// Represents an LLM API provider (e.g. OpenAI, Anthropic, Google).
///
/// API keys are **not** stored in this model — they are managed separately
/// via `flutter_secure_storage`. The [apiKeyRef] field holds a reference
/// key used to look up the secret at runtime.
class ProviderModel extends Equatable {
  /// Creates a new [ProviderModel].
  const ProviderModel({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKeyRef,
    this.models = const [],
    this.isAvailable = true,
    this.priority = 0,
    this.lastChecked,
    this.status = 'unknown',
  });

  /// Unique provider identifier.
  final String id;

  /// Human-readable name (e.g. "OpenAI").
  final String name;

  /// Base URL of the provider API.
  final String baseUrl;

  /// Reference key for looking up the API key in secure storage.
  ///
  /// The actual secret is never stored in plain-text models.
  final String? apiKeyRef;

  /// Models offered by this provider.
  final List<AIModelInfo> models;

  /// Whether the provider is currently reachable.
  final bool isAvailable;

  /// Priority for routing (lower = higher priority).
  final int priority;

  /// When the provider was last health-checked.
  final DateTime? lastChecked;

  /// Human-readable status label (e.g. "healthy", "degraded", "down").
  final String status;

  /// Returns a copy with the given fields replaced.
  ProviderModel copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKeyRef,
    List<AIModelInfo>? models,
    bool? isAvailable,
    int? priority,
    DateTime? lastChecked,
    String? status,
  }) {
    return ProviderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      models: models ?? this.models,
      isAvailable: isAvailable ?? this.isAvailable,
      priority: priority ?? this.priority,
      lastChecked: lastChecked ?? this.lastChecked,
      status: status ?? this.status,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKeyRef': apiKeyRef,
      'models': models.map((m) => m.toJson()).toList(),
      'isAvailable': isAvailable,
      'priority': priority,
      'lastChecked': lastChecked?.toIso8601String(),
      'status': status,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    return ProviderModel(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKeyRef: json['apiKeyRef'] as String?,
      models: (json['models'] as List?)
              ?.map((e) => AIModelInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isAvailable: (json['isAvailable'] as bool?) ?? true,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      lastChecked: json['lastChecked'] != null
          ? DateTime.parse(json['lastChecked'] as String)
          : null,
      status: (json['status'] as String?) ?? 'unknown',
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        baseUrl,
        apiKeyRef,
        models,
        isAvailable,
        priority,
        lastChecked,
        status,
      ];
}

// ---------------------------------------------------------------------------
// BattleResult
// ---------------------------------------------------------------------------

/// Records the outcome of a model "battle" — a head-to-head comparison
/// where the same prompt is sent to multiple models and results are scored.
class BattleResult extends Equatable {
  /// Creates a new [BattleResult].
  const BattleResult({
    required this.id,
    required this.taskId,
    required this.prompt,
    this.responses = const {},
    this.scores = const {},
    this.winner,
    this.analysis,
    required this.timestamp,
    this.cost = 0.0,
  });

  /// Unique battle identifier.
  final String id;

  /// The task this battle was conducted for.
  final String taskId;

  /// The prompt sent to all competing models.
  final String prompt;

  /// Model ID → response text.
  final Map<String, String> responses;

  /// Model ID → numeric score.
  final Map<String, double> scores;

  /// The model ID that won the battle (if determined).
  final String? winner;

  /// Free-form analysis of the results.
  final String? analysis;

  /// When the battle was conducted.
  final DateTime timestamp;

  /// Total cost of the battle across all models.
  final double cost;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'prompt': prompt,
      'responses': responses,
      'scores': scores,
      'winner': winner,
      'analysis': analysis,
      'timestamp': timestamp.toIso8601String(),
      'cost': cost,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory BattleResult.fromJson(Map<String, dynamic> json) {
    return BattleResult(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      prompt: json['prompt'] as String,
      responses: Map<String, String>.from(
        (json['responses'] as Map?) ?? {},
      ),
      scores: (json['scores'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          ) ??
          {},
      winner: json['winner'] as String?,
      analysis: json['analysis'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        taskId,
        prompt,
        responses,
        scores,
        winner,
        analysis,
        timestamp,
        cost,
      ];
}
