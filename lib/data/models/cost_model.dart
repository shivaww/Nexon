/// Cost tracking data model.
///
/// [CostEntry] records a single billable event — tokens consumed, provider
/// and model used, and the dollar cost — linked to the project, agent,
/// task, or workflow that incurred the charge.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// CostEntry
// ---------------------------------------------------------------------------

/// A single cost record for token / API usage.
class CostEntry extends Equatable {
  /// Creates a new [CostEntry].
  const CostEntry({
    required this.id,
    required this.provider,
    required this.model,
    this.project,
    this.agent,
    this.task,
    this.workflow,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost = 0.0,
    required this.timestamp,
  });

  /// Unique cost entry identifier.
  final String id;

  /// Provider that was billed (e.g. "openai").
  final String provider;

  /// Model that processed the request (e.g. "gpt-4o").
  final String model;

  /// Project ID that incurred the cost (if any).
  final String? project;

  /// Agent ID that incurred the cost (if any).
  final String? agent;

  /// Task ID that incurred the cost (if any).
  final String? task;

  /// Workflow ID that incurred the cost (if any).
  final String? workflow;

  /// Number of input tokens consumed.
  final int inputTokens;

  /// Number of output tokens consumed.
  final int outputTokens;

  /// Dollar cost for this entry.
  final double cost;

  /// When this cost was incurred.
  final DateTime timestamp;

  /// Total tokens (input + output) for this entry.
  int get totalTokens => inputTokens + outputTokens;

  /// Returns a copy with the given fields replaced.
  CostEntry copyWith({
    String? id,
    String? provider,
    String? model,
    String? project,
    String? agent,
    String? task,
    String? workflow,
    int? inputTokens,
    int? outputTokens,
    double? cost,
    DateTime? timestamp,
  }) {
    return CostEntry(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      project: project ?? this.project,
      agent: agent ?? this.agent,
      task: task ?? this.task,
      workflow: workflow ?? this.workflow,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cost: cost ?? this.cost,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider,
      'model': model,
      'project': project,
      'agent': agent,
      'task': task,
      'workflow': workflow,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'cost': cost,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory CostEntry.fromJson(Map<String, dynamic> json) {
    return CostEntry(
      id: json['id'] as String,
      provider: json['provider'] as String,
      model: json['model'] as String,
      project: json['project'] as String?,
      agent: json['agent'] as String?,
      task: json['task'] as String?,
      workflow: json['workflow'] as String?,
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        provider,
        model,
        project,
        agent,
        task,
        workflow,
        inputTokens,
        outputTokens,
        cost,
        timestamp,
      ];
}
