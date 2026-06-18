/// Shared task system models for the TermuxForge agentic pipeline.
///
/// [TaskModel] represents a unit of work that can be assigned to agents,
/// decomposed into subtasks, and tracked through its lifecycle from creation
/// to completion or failure.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// TaskStatus
// ---------------------------------------------------------------------------

/// Lifecycle states of a [TaskModel].
enum TaskStatus {
  /// Task has been created but not yet assigned.
  created,

  /// Task has been assigned to an agent.
  assigned,

  /// An agent has claimed the task and will begin shortly.
  claimed,

  /// Work is actively underway.
  inProgress,

  /// Task is blocked on a dependency or external input.
  blocked,

  /// Task is ready for review.
  review,

  /// Task has been completed successfully.
  completed,

  /// Task failed during execution.
  failed,

  /// Task was cancelled before completion.
  cancelled,
}

// ---------------------------------------------------------------------------
// TaskPriority
// ---------------------------------------------------------------------------

/// Priority levels for task scheduling.
enum TaskPriority {
  /// Must be done immediately; blocks other work.
  critical,

  /// High importance; do next.
  high,

  /// Standard priority.
  medium,

  /// Low importance; do when nothing else is pending.
  low,
}

// ---------------------------------------------------------------------------
// TaskModel
// ---------------------------------------------------------------------------

/// A discrete unit of work within the TermuxForge system.
///
/// Tasks can form hierarchies via [parentTaskId] and [subtaskIds], declare
/// [dependencies] on other tasks, and cross-reference files, memory entries,
/// MCP tools, artifacts, and workflows.
class TaskModel extends Equatable {
  /// Creates a new [TaskModel].
  const TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.created,
    this.priority = TaskPriority.medium,
    this.assignedAgent,
    this.parentTaskId,
    this.subtaskIds = const [],
    this.dependencies = const [],
    this.linkedFiles = const [],
    this.linkedMemoryRefs = const [],
    this.linkedMcpTools = const [],
    this.linkedArtifacts = const [],
    this.linkedWorkflows = const [],
    this.completionPercentage = 0,
    this.progressNotes = const [],
    this.modelUsed,
    this.toolUsed,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
    this.completedAt,
  });

  /// Unique identifier.
  final String id;

  /// Short human-readable title.
  final String title;

  /// Detailed description of the work to be done.
  final String description;

  /// Current lifecycle status.
  final TaskStatus status;

  /// Scheduling priority.
  final TaskPriority priority;

  /// ID of the agent currently responsible for this task.
  final String? assignedAgent;

  /// Parent task ID (for subtask hierarchies).
  final String? parentTaskId;

  /// IDs of child subtasks.
  final List<String> subtaskIds;

  /// IDs of tasks that must complete before this one can start.
  final List<String> dependencies;

  /// File paths relevant to this task.
  final List<String> linkedFiles;

  /// Memory entry IDs referenced by this task.
  final List<String> linkedMemoryRefs;

  /// MCP tool identifiers used or needed by this task.
  final List<String> linkedMcpTools;

  /// Artifact IDs produced or consumed by this task.
  final List<String> linkedArtifacts;

  /// Workflow IDs associated with this task.
  final List<String> linkedWorkflows;

  /// Overall completion percentage (0–100).
  final int completionPercentage;

  /// Chronological notes about progress made.
  final List<String> progressNotes;

  /// The LLM model used for this task (if any).
  final String? modelUsed;

  /// The tool used for this task (if any).
  final String? toolUsed;

  /// When this task was created.
  final DateTime createdAt;

  /// When this task was last updated.
  final DateTime updatedAt;

  /// Optional due date.
  final DateTime? dueDate;

  /// When this task was completed or failed.
  final DateTime? completedAt;

  /// Returns a deep copy with the given fields replaced.
  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    String? assignedAgent,
    String? parentTaskId,
    List<String>? subtaskIds,
    List<String>? dependencies,
    List<String>? linkedFiles,
    List<String>? linkedMemoryRefs,
    List<String>? linkedMcpTools,
    List<String>? linkedArtifacts,
    List<String>? linkedWorkflows,
    int? completionPercentage,
    List<String>? progressNotes,
    String? modelUsed,
    String? toolUsed,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? dueDate,
    DateTime? completedAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      assignedAgent: assignedAgent ?? this.assignedAgent,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      subtaskIds: subtaskIds ?? this.subtaskIds,
      dependencies: dependencies ?? this.dependencies,
      linkedFiles: linkedFiles ?? this.linkedFiles,
      linkedMemoryRefs: linkedMemoryRefs ?? this.linkedMemoryRefs,
      linkedMcpTools: linkedMcpTools ?? this.linkedMcpTools,
      linkedArtifacts: linkedArtifacts ?? this.linkedArtifacts,
      linkedWorkflows: linkedWorkflows ?? this.linkedWorkflows,
      completionPercentage: completionPercentage ?? this.completionPercentage,
      progressNotes: progressNotes ?? this.progressNotes,
      modelUsed: modelUsed ?? this.modelUsed,
      toolUsed: toolUsed ?? this.toolUsed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.name,
      'priority': priority.name,
      'assignedAgent': assignedAgent,
      'parentTaskId': parentTaskId,
      'subtaskIds': subtaskIds,
      'dependencies': dependencies,
      'linkedFiles': linkedFiles,
      'linkedMemoryRefs': linkedMemoryRefs,
      'linkedMcpTools': linkedMcpTools,
      'linkedArtifacts': linkedArtifacts,
      'linkedWorkflows': linkedWorkflows,
      'completionPercentage': completionPercentage,
      'progressNotes': progressNotes,
      'modelUsed': modelUsed,
      'toolUsed': toolUsed,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      status: TaskStatus.values.byName(json['status'] as String),
      priority: TaskPriority.values.byName(json['priority'] as String),
      assignedAgent: json['assignedAgent'] as String?,
      parentTaskId: json['parentTaskId'] as String?,
      subtaskIds: List<String>.from((json['subtaskIds'] as List?) ?? []),
      dependencies: List<String>.from((json['dependencies'] as List?) ?? []),
      linkedFiles: List<String>.from((json['linkedFiles'] as List?) ?? []),
      linkedMemoryRefs:
          List<String>.from((json['linkedMemoryRefs'] as List?) ?? []),
      linkedMcpTools:
          List<String>.from((json['linkedMcpTools'] as List?) ?? []),
      linkedArtifacts:
          List<String>.from((json['linkedArtifacts'] as List?) ?? []),
      linkedWorkflows:
          List<String>.from((json['linkedWorkflows'] as List?) ?? []),
      completionPercentage:
          (json['completionPercentage'] as num?)?.toInt() ?? 0,
      progressNotes:
          List<String>.from((json['progressNotes'] as List?) ?? []),
      modelUsed: json['modelUsed'] as String?,
      toolUsed: json['toolUsed'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        status,
        priority,
        assignedAgent,
        parentTaskId,
        subtaskIds,
        dependencies,
        linkedFiles,
        linkedMemoryRefs,
        linkedMcpTools,
        linkedArtifacts,
        linkedWorkflows,
        completionPercentage,
        progressNotes,
        modelUsed,
        toolUsed,
        createdAt,
        updatedAt,
        dueDate,
        completedAt,
      ];
}
