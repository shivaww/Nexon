// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// Shared type definitions for the TermuxForge agent system.
///
/// Contains all enums, data classes, and contracts used across
/// every agent in the system. This file is the single source of
/// truth for agent-related types and should be imported by every
/// agent implementation.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Classifies the specialisation of an agent.
enum AgentType {
  /// Orchestrator / team-lead agent.
  orchestrator,

  /// Flutter UI specialist.
  frontendExpert,

  /// Architecture & backend-logic specialist.
  backendExpert,

  /// Database specialist.
  databaseExpert,

  /// Research & documentation specialist.
  researcher,

  /// Testing specialist.
  tester,

  /// Debugging specialist.
  debugger,

  /// Code-review specialist.
  reviewer,

  /// Planning & roadmap specialist.
  planner,

  /// LLM routing & model-selection specialist.
  llmRouter,

  /// MCP server discovery specialist.
  mcpDiscovery,

  /// Workflow execution specialist.
  workflowAgent,

  /// Media generation specialist.
  mediaAgent,

  /// System observability & cost-tracking specialist.
  observability,
}

/// Current lifecycle status of an agent.
enum AgentStatus {
  /// Agent is created but not yet initialised.
  created,

  /// Agent is idle, waiting for tasks.
  idle,

  /// Agent is actively executing a task.
  busy,

  /// Agent is waiting on an external resource.
  waiting,

  /// Agent encountered an error and paused.
  error,

  /// Agent has been disposed.
  disposed,
}

/// Priority levels for tasks.
enum TaskPriority {
  /// Background / nice-to-have.
  low,

  /// Default priority.
  normal,

  /// Should be addressed soon.
  high,

  /// Drop everything and do this now.
  critical,
}

/// High-level classification of a task.
enum TaskType {
  /// Generating new code.
  codeGeneration,

  /// Fixing bugs.
  bugFix,

  /// Refactoring existing code.
  refactor,

  /// Adding or running tests.
  testing,

  /// Performing research.
  research,

  /// Reviewing code.
  review,

  /// Architectural planning.
  planning,

  /// Database operations.
  database,

  /// UI/UX work.
  ui,

  /// DevOps / build / deploy.
  devops,

  /// Debugging a runtime issue.
  debugging,

  /// Media generation.
  media,

  /// Workflow / automation.
  workflow,

  /// Observability / metrics.
  observability,

  /// General-purpose catch-all.
  general,
}

/// Types of inter-agent messages.
enum MessageType {
  /// A request for the recipient to do something.
  taskAssignment,

  /// A response containing results.
  taskResult,

  /// A progress update from a working agent.
  progressUpdate,

  /// An error report.
  errorReport,

  /// A request for context / information.
  contextRequest,

  /// A context response.
  contextResponse,

  /// A heartbeat / keep-alive.
  heartbeat,

  /// A system-level control message (shutdown, pause, etc.).
  systemControl,

  /// A chat message for human-in-the-loop.
  chat,
}

/// Capability tags that describe what a model is good at.
enum ModelCapability {
  /// Strong at code generation.
  coding,

  /// Strong at reasoning & planning.
  reasoning,

  /// Strong at creative / natural-language tasks.
  creative,

  /// Low latency – good for quick lookups.
  fast,

  /// Large context window.
  longContext,

  /// Supports vision / image input.
  vision,

  /// Supports tool / function calling.
  toolUse,

  /// Budget-friendly.
  cheap,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A task to be executed by an agent.
class AgentTask extends Equatable {
  /// Creates an [AgentTask].
  const AgentTask({
    required this.id,
    required this.description,
    required this.type,
    this.priority = TaskPriority.normal,
    this.context = const {},
    this.parentTaskId,
    this.deadline,
    this.tools = const [],
    this.model,
    this.subtaskIds = const [],
    this.createdAt,
  });

  /// Unique identifier for this task.
  final String id;

  /// Human-readable description of what needs to be done.
  final String description;

  /// Classification of this task.
  final TaskType type;

  /// Priority level.
  final TaskPriority priority;

  /// Arbitrary context data for the agent.
  final Map<String, dynamic> context;

  /// If this is a subtask, the ID of its parent.
  final String? parentTaskId;

  /// Optional deadline.
  final DateTime? deadline;

  /// IDs of tools the agent is allowed to use for this task.
  final List<String> tools;

  /// Preferred model identifier (e.g. `'gpt-4o'`, `'claude-sonnet'`).
  final String? model;

  /// IDs of decomposed subtasks.
  final List<String> subtaskIds;

  /// When this task was created.
  final DateTime? createdAt;

  @override
  List<Object?> get props => [id];

  /// Creates a copy with the given fields replaced.
  AgentTask copyWith({
    String? id,
    String? description,
    TaskType? type,
    TaskPriority? priority,
    Map<String, dynamic>? context,
    String? parentTaskId,
    DateTime? deadline,
    List<String>? tools,
    String? model,
    List<String>? subtaskIds,
    DateTime? createdAt,
  }) {
    return AgentTask(
      id: id ?? this.id,
      description: description ?? this.description,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      context: context ?? this.context,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      deadline: deadline ?? this.deadline,
      tools: tools ?? this.tools,
      model: model ?? this.model,
      subtaskIds: subtaskIds ?? this.subtaskIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'type': type.name,
        'priority': priority.name,
        'context': context,
        'parentTaskId': parentTaskId,
        'deadline': deadline?.toIso8601String(),
        'tools': tools,
        'model': model,
        'subtaskIds': subtaskIds,
        'createdAt': createdAt?.toIso8601String(),
      };

  /// Deserialises from a JSON-compatible map.
  factory AgentTask.fromJson(Map<String, dynamic> json) {
    return AgentTask(
      id: json['id'] as String,
      description: json['description'] as String,
      type: TaskType.values.byName(json['type'] as String),
      priority: TaskPriority.values.byName(
        json['priority'] as String? ?? 'normal',
      ),
      context: (json['context'] as Map<String, dynamic>?) ?? const {},
      parentTaskId: json['parentTaskId'] as String?,
      deadline: json['deadline'] != null
          ? DateTime.parse(json['deadline'] as String)
          : null,
      tools: (json['tools'] as List<dynamic>?)?.cast<String>() ?? const [],
      model: json['model'] as String?,
      subtaskIds:
          (json['subtaskIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }
}

/// The result produced by an agent after executing a task.
class AgentResult extends Equatable {
  /// Creates an [AgentResult].
  const AgentResult({
    required this.taskId,
    required this.success,
    this.output = '',
    this.artifacts = const [],
    this.memoryEntries = const [],
    this.nextSteps = const [],
    this.cost = 0.0,
    this.duration = Duration.zero,
    this.error,
    this.metadata = const {},
  });

  /// The task ID this result corresponds to.
  final String taskId;

  /// Whether the task succeeded.
  final bool success;

  /// Human-readable output / summary.
  final String output;

  /// Paths to generated artifacts (files, images, etc.).
  final List<String> artifacts;

  /// Memory entries created during execution.
  final List<MemoryEntry> memoryEntries;

  /// Suggested follow-up actions.
  final List<String> nextSteps;

  /// Estimated cost in USD.
  final double cost;

  /// How long the task took.
  final Duration duration;

  /// Error message if [success] is false.
  final String? error;

  /// Extra metadata.
  final Map<String, dynamic> metadata;

  @override
  List<Object?> get props => [taskId, success];

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'success': success,
        'output': output,
        'artifacts': artifacts,
        'memoryEntries': memoryEntries.map((e) => e.toJson()).toList(),
        'nextSteps': nextSteps,
        'cost': cost,
        'duration': duration.inMilliseconds,
        'error': error,
        'metadata': metadata,
      };
}

/// An inter-agent message.
class AgentMessage extends Equatable {
  /// Creates an [AgentMessage].
  const AgentMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.correlationId,
    this.priority = TaskPriority.normal,
  });

  /// Unique message ID.
  final String id;

  /// Agent ID of the sender.
  final String senderId;

  /// Agent ID of the recipient.
  final String recipientId;

  /// Message type.
  final MessageType type;

  /// Arbitrary message payload.
  final Map<String, dynamic> payload;

  /// When the message was created.
  final DateTime timestamp;

  /// Optional correlation ID (to tie request ↔ response).
  final String? correlationId;

  /// Priority.
  final TaskPriority priority;

  @override
  List<Object?> get props => [id];

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'recipientId': recipientId,
        'type': type.name,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'correlationId': correlationId,
        'priority': priority.name,
      };

  /// Deserialises from a JSON-compatible map.
  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    return AgentMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      recipientId: json['recipientId'] as String,
      type: MessageType.values.byName(json['type'] as String),
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      timestamp: DateTime.parse(json['timestamp'] as String),
      correlationId: json['correlationId'] as String?,
      priority: TaskPriority.values.byName(
        json['priority'] as String? ?? 'normal',
      ),
    );
  }
}

/// A single entry in the agent's memory store.
class MemoryEntry extends Equatable {
  /// Creates a [MemoryEntry].
  const MemoryEntry({
    required this.id,
    required this.content,
    required this.source,
    required this.timestamp,
    this.tags = const [],
    this.embedding,
    this.metadata = const {},
  });

  /// Unique ID.
  final String id;

  /// The text content being remembered.
  final String content;

  /// Where this entry came from (agent ID, file path, etc.).
  final String source;

  /// When it was created.
  final DateTime timestamp;

  /// Searchable tags.
  final List<String> tags;

  /// Optional vector embedding for semantic search.
  final List<double>? embedding;

  /// Extra metadata.
  final Map<String, dynamic> metadata;

  @override
  List<Object?> get props => [id];

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'source': source,
        'timestamp': timestamp.toIso8601String(),
        'tags': tags,
        'metadata': metadata,
      };

  /// Deserialises from a JSON-compatible map.
  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    return MemoryEntry(
      id: json['id'] as String,
      content: json['content'] as String,
      source: json['source'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// Result of using a tool.
class ToolResult extends Equatable {
  /// Creates a [ToolResult].
  const ToolResult({
    required this.toolId,
    required this.success,
    this.output = '',
    this.error,
    this.duration = Duration.zero,
    this.metadata = const {},
  });

  /// Which tool was used.
  final String toolId;

  /// Whether the tool call succeeded.
  final bool success;

  /// Output from the tool.
  final String output;

  /// Error message if [success] is false.
  final String? error;

  /// How long the tool call took.
  final Duration duration;

  /// Extra metadata.
  final Map<String, dynamic> metadata;

  @override
  List<Object?> get props => [toolId, success];

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'success': success,
        'output': output,
        'error': error,
        'duration': duration.inMilliseconds,
        'metadata': metadata,
      };
}

/// Describes a model's suitability for a task.
class ModelScore extends Equatable {
  /// Creates a [ModelScore].
  const ModelScore({
    required this.modelId,
    required this.provider,
    this.qualityScore = 0.0,
    this.speedScore = 0.0,
    this.costScore = 0.0,
    this.overallScore = 0.0,
    this.capabilities = const [],
  });

  /// Model identifier (e.g. `'gpt-4o'`).
  final String modelId;

  /// Provider name (e.g. `'openai'`, `'anthropic'`).
  final String provider;

  /// Quality rating [0.0 – 1.0].
  final double qualityScore;

  /// Speed rating [0.0 – 1.0].
  final double speedScore;

  /// Cost efficiency rating [0.0 – 1.0].
  final double costScore;

  /// Weighted overall score.
  final double overallScore;

  /// Capability tags this model supports.
  final List<ModelCapability> capabilities;

  @override
  List<Object?> get props => [modelId, provider];

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'provider': provider,
        'qualityScore': qualityScore,
        'speedScore': speedScore,
        'costScore': costScore,
        'overallScore': overallScore,
        'capabilities': capabilities.map((c) => c.name).toList(),
      };
}

/// An event published onto the agent event bus.
class AgentEvent extends Equatable {
  /// Creates an [AgentEvent].
  const AgentEvent({
    required this.type,
    required this.agentId,
    required this.timestamp,
    this.taskId,
    this.data = const {},
  });

  /// Type key, e.g. `'task.started'`, `'agent.error'`.
  final String type;

  /// The agent that emitted this event.
  final String agentId;

  /// When the event was emitted.
  final DateTime timestamp;

  /// Related task ID (if any).
  final String? taskId;

  /// Arbitrary event data.
  final Map<String, dynamic> data;

  @override
  List<Object?> get props => [type, agentId, timestamp];

  /// Serialises to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'type': type,
        'agentId': agentId,
        'timestamp': timestamp.toIso8601String(),
        'taskId': taskId,
        'data': data,
      };
}
