/// Agent system models for the TermuxForge multi-agent orchestrator.
///
/// [AgentModel] represents a running or idle agent within the system, while
/// [AgentMessage] captures inter-agent communication including task
/// assignments, status updates, and review requests.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// AgentType
// ---------------------------------------------------------------------------

/// The specialisation / role of an agent.
enum AgentType {
  /// Central coordinator that decomposes work and dispatches to specialists.
  orchestrator,

  /// Specialist in frontend UI/UX implementation.
  frontendExpert,

  /// Specialist in backend / API implementation.
  backendExpert,

  /// Specialist in database schema and queries.
  databaseExpert,

  /// Conducts web research and information retrieval.
  researcher,

  /// Writes and executes tests.
  tester,

  /// Diagnoses and fixes bugs.
  debugger,

  /// Reviews code and provides feedback.
  reviewer,

  /// Creates plans and breaks down high-level goals.
  planner,

  /// Routes requests to the most appropriate LLM model.
  llmRouter,

  /// Discovers and manages MCP server connections.
  mcpDiscovery,

  /// Executes and manages workflow pipelines.
  workflowAgent,

  /// Generates and manages media assets.
  mediaAgent,

  /// Monitors system health, costs, and performance.
  observability,
}

// ---------------------------------------------------------------------------
// AgentMessageType
// ---------------------------------------------------------------------------

/// The purpose of an [AgentMessage].
enum AgentMessageType {
  /// Assigns a task to a receiving agent.
  taskAssignment,

  /// Reports status of an ongoing task.
  statusUpdate,

  /// Requests a code or design review.
  reviewRequest,

  /// Asks for clarification on requirements or approach.
  clarification,

  /// Delivers a result or output.
  result,

  /// System-wide broadcast (e.g. shutdown notice).
  broadcast,
}

// ---------------------------------------------------------------------------
// AgentMessage
// ---------------------------------------------------------------------------

/// A message exchanged between two agents.
class AgentMessage extends Equatable {
  /// Creates a new [AgentMessage].
  const AgentMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.content,
    required this.timestamp,
    this.taskId,
    required this.type,
  });

  /// Unique message identifier.
  final String id;

  /// Sender agent ID.
  final String from;

  /// Receiver agent ID.
  final String to;

  /// Message body.
  final String content;

  /// When the message was sent.
  final DateTime timestamp;

  /// Optional related task ID.
  final String? taskId;

  /// The purpose of this message.
  final AgentMessageType type;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': from,
      'to': to,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'taskId': taskId,
      'type': type.name,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    return AgentMessage(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      taskId: json['taskId'] as String?,
      type: AgentMessageType.values.byName(json['type'] as String),
    );
  }

  @override
  List<Object?> get props => [id, from, to, content, timestamp, taskId, type];
}

// ---------------------------------------------------------------------------
// AgentModel
// ---------------------------------------------------------------------------

/// Represents a single agent instance within the TermuxForge system.
///
/// Tracks the agent's type, status, currently assigned task, accumulated
/// cost, and a queue of pending messages.
class AgentModel extends Equatable {
  /// Creates a new [AgentModel].
  const AgentModel({
    required this.id,
    required this.type,
    required this.name,
    this.status = 'idle',
    this.currentTaskId,
    this.model,
    this.toolAccess = const [],
    required this.spawnedAt,
    this.messageQueue = const [],
    this.runtime = Duration.zero,
    this.costAccrued = 0.0,
    this.errors = const [],
  });

  /// Unique agent identifier.
  final String id;

  /// The specialisation of this agent.
  final AgentType type;

  /// Human-readable display name.
  final String name;

  /// Current status label (e.g. "idle", "working", "error").
  final String status;

  /// The task this agent is currently working on (if any).
  final String? currentTaskId;

  /// The LLM model this agent is configured to use.
  final String? model;

  /// List of tool / MCP capabilities this agent may invoke.
  final List<String> toolAccess;

  /// When this agent was spawned.
  final DateTime spawnedAt;

  /// Pending incoming messages.
  final List<AgentMessage> messageQueue;

  /// Total runtime since spawn.
  final Duration runtime;

  /// Total cost accrued by this agent (USD).
  final double costAccrued;

  /// Error messages encountered.
  final List<String> errors;

  /// Returns a copy with the given fields replaced.
  AgentModel copyWith({
    String? id,
    AgentType? type,
    String? name,
    String? status,
    String? currentTaskId,
    String? model,
    List<String>? toolAccess,
    DateTime? spawnedAt,
    List<AgentMessage>? messageQueue,
    Duration? runtime,
    double? costAccrued,
    List<String>? errors,
  }) {
    return AgentModel(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      status: status ?? this.status,
      currentTaskId: currentTaskId ?? this.currentTaskId,
      model: model ?? this.model,
      toolAccess: toolAccess ?? this.toolAccess,
      spawnedAt: spawnedAt ?? this.spawnedAt,
      messageQueue: messageQueue ?? this.messageQueue,
      runtime: runtime ?? this.runtime,
      costAccrued: costAccrued ?? this.costAccrued,
      errors: errors ?? this.errors,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'status': status,
      'currentTaskId': currentTaskId,
      'model': model,
      'toolAccess': toolAccess,
      'spawnedAt': spawnedAt.toIso8601String(),
      'messageQueue': messageQueue.map((m) => m.toJson()).toList(),
      'runtime': runtime.inMilliseconds,
      'costAccrued': costAccrued,
      'errors': errors,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory AgentModel.fromJson(Map<String, dynamic> json) {
    return AgentModel(
      id: json['id'] as String,
      type: AgentType.values.byName(json['type'] as String),
      name: json['name'] as String,
      status: (json['status'] as String?) ?? 'idle',
      currentTaskId: json['currentTaskId'] as String?,
      model: json['model'] as String?,
      toolAccess: List<String>.from((json['toolAccess'] as List?) ?? []),
      spawnedAt: DateTime.parse(json['spawnedAt'] as String),
      messageQueue: (json['messageQueue'] as List?)
              ?.map((e) => AgentMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      runtime: Duration(
        milliseconds: (json['runtime'] as num?)?.toInt() ?? 0,
      ),
      costAccrued: (json['costAccrued'] as num?)?.toDouble() ?? 0.0,
      errors: List<String>.from((json['errors'] as List?) ?? []),
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        name,
        status,
        currentTaskId,
        model,
        toolAccess,
        spawnedAt,
        messageQueue,
        runtime,
        costAccrued,
        errors,
      ];
}
