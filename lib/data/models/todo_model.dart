/// Todo system models for lightweight task tracking.
///
/// [TodoModel] is a simpler, user-facing counterpart to [TaskModel].
/// It tracks individual to-do items with percentage completion, priority,
/// and links to the broader memory and artifact systems.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// TodoStatus
// ---------------------------------------------------------------------------

/// Lifecycle states for a [TodoModel].
enum TodoStatus {
  /// Work has not started.
  notStarted,

  /// Work is underway.
  inProgress,

  /// Blocked on an external dependency.
  blocked,

  /// Successfully completed.
  completed,

  /// Cancelled and will not be completed.
  cancelled,
}

// ---------------------------------------------------------------------------
// TodoModel
// ---------------------------------------------------------------------------

/// A lightweight todo item that can be owned by an agent or a user.
///
/// Tracks completion as a percentage (0–100) and maintains a history of
/// progress notes. Linked to files, memory entries, artifacts, and optionally
/// to a workflow template.
class TodoModel extends Equatable {
  /// Creates a new [TodoModel].
  const TodoModel({
    required this.id,
    required this.title,
    this.description = '',
    this.percentage = 0,
    this.priority = 'medium',
    this.agentOwner,
    this.dueDate,
    this.linkedFiles = const [],
    this.linkedMemoryRefs = const [],
    this.progressNotes = const [],
    required this.createdAt,
    required this.updatedAt,
    this.completionHistory = const [],
    this.modelUsed,
    this.toolUsed,
    this.artifactLinks = const [],
    this.workflowTemplateId,
    this.status = TodoStatus.notStarted,
  });

  /// Unique identifier.
  final String id;

  /// Short human-readable title.
  final String title;

  /// Detailed description.
  final String description;

  /// Completion percentage (0–100).
  final int percentage;

  /// Priority label (e.g. "critical", "high", "medium", "low").
  final String priority;

  /// The agent that owns this todo (if any).
  final String? agentOwner;

  /// Optional due date.
  final DateTime? dueDate;

  /// File paths linked to this todo.
  final List<String> linkedFiles;

  /// Memory entry IDs linked to this todo.
  final List<String> linkedMemoryRefs;

  /// Chronological progress notes.
  final List<String> progressNotes;

  /// When this todo was created.
  final DateTime createdAt;

  /// When this todo was last updated.
  final DateTime updatedAt;

  /// History of completion percentage changes with timestamps.
  final List<Map<String, dynamic>> completionHistory;

  /// The LLM model used (if applicable).
  final String? modelUsed;

  /// The tool used (if applicable).
  final String? toolUsed;

  /// Artifact IDs linked to this todo.
  final List<String> artifactLinks;

  /// Optional workflow template this todo was generated from.
  final String? workflowTemplateId;

  /// Current lifecycle status.
  final TodoStatus status;

  /// Returns a copy with the given fields replaced.
  TodoModel copyWith({
    String? id,
    String? title,
    String? description,
    int? percentage,
    String? priority,
    String? agentOwner,
    DateTime? dueDate,
    List<String>? linkedFiles,
    List<String>? linkedMemoryRefs,
    List<String>? progressNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, dynamic>>? completionHistory,
    String? modelUsed,
    String? toolUsed,
    List<String>? artifactLinks,
    String? workflowTemplateId,
    TodoStatus? status,
  }) {
    return TodoModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      percentage: percentage ?? this.percentage,
      priority: priority ?? this.priority,
      agentOwner: agentOwner ?? this.agentOwner,
      dueDate: dueDate ?? this.dueDate,
      linkedFiles: linkedFiles ?? this.linkedFiles,
      linkedMemoryRefs: linkedMemoryRefs ?? this.linkedMemoryRefs,
      progressNotes: progressNotes ?? this.progressNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completionHistory: completionHistory ?? this.completionHistory,
      modelUsed: modelUsed ?? this.modelUsed,
      toolUsed: toolUsed ?? this.toolUsed,
      artifactLinks: artifactLinks ?? this.artifactLinks,
      workflowTemplateId: workflowTemplateId ?? this.workflowTemplateId,
      status: status ?? this.status,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'percentage': percentage,
      'priority': priority,
      'agentOwner': agentOwner,
      'dueDate': dueDate?.toIso8601String(),
      'linkedFiles': linkedFiles,
      'linkedMemoryRefs': linkedMemoryRefs,
      'progressNotes': progressNotes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completionHistory': completionHistory,
      'modelUsed': modelUsed,
      'toolUsed': toolUsed,
      'artifactLinks': artifactLinks,
      'workflowTemplateId': workflowTemplateId,
      'status': status.name,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory TodoModel.fromJson(Map<String, dynamic> json) {
    return TodoModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      percentage: (json['percentage'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as String?) ?? 'medium',
      agentOwner: json['agentOwner'] as String?,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      linkedFiles: List<String>.from((json['linkedFiles'] as List?) ?? []),
      linkedMemoryRefs:
          List<String>.from((json['linkedMemoryRefs'] as List?) ?? []),
      progressNotes:
          List<String>.from((json['progressNotes'] as List?) ?? []),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completionHistory: (json['completionHistory'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      modelUsed: json['modelUsed'] as String?,
      toolUsed: json['toolUsed'] as String?,
      artifactLinks:
          List<String>.from((json['artifactLinks'] as List?) ?? []),
      workflowTemplateId: json['workflowTemplateId'] as String?,
      status: TodoStatus.values.byName(
        (json['status'] as String?) ?? 'notStarted',
      ),
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        percentage,
        priority,
        agentOwner,
        dueDate,
        linkedFiles,
        linkedMemoryRefs,
        progressNotes,
        createdAt,
        updatedAt,
        completionHistory,
        modelUsed,
        toolUsed,
        artifactLinks,
        workflowTemplateId,
        status,
      ];
}
