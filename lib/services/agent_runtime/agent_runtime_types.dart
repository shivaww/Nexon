// ============================================================================
// TermuxForge — Agent Runtime Types
// Data models and enums for the agent lifecycle system.
// ============================================================================

/// The operational state of a registered agent.
enum AgentStatus {
  /// Agent is registered but has no active work.
  idle('Idle — waiting for tasks'),

  /// Agent is actively processing a task.
  working('Working — executing a task'),

  /// Agent is waiting on an external result (e.g., tool call, user input).
  waiting('Waiting — blocked on external result'),

  /// Agent encountered an unrecoverable error.
  error('Error — needs intervention'),

  /// Agent has been killed or finished all work.
  terminated('Terminated — no longer active');

  const AgentStatus(this.description);

  /// Human-readable description of this status.
  final String description;
}

/// The type/role of an agent within the system.
enum AgentType {
  /// Primary orchestrator that decomposes tasks.
  orchestrator,

  /// Handles code generation and editing.
  coder,

  /// Reviews code for quality and security.
  reviewer,

  /// Runs tests and analyzes results.
  tester,

  /// Performs research and web lookups.
  researcher,

  /// Runs long-lived background jobs (linting, watching).
  background,

  /// User-defined custom agent type.
  custom,
}

/// Represents a message sent between agents.
class AgentMessage {
  /// Unique message identifier.
  final String id;

  /// The sender agent's ID.
  final String fromAgentId;

  /// The recipient agent's ID.
  final String toAgentId;

  /// The message content.
  final String content;

  /// Optional structured payload.
  final Map<String, dynamic>? payload;

  /// When the message was sent (UTC).
  final DateTime sentAt;

  /// Whether the message has been read by the recipient.
  bool read;

  AgentMessage({
    required this.id,
    required this.fromAgentId,
    required this.toAgentId,
    required this.content,
    this.payload,
    DateTime? sentAt,
    this.read = false,
  }) : sentAt = sentAt ?? DateTime.now().toUtc();
}

/// Describes a task assigned to an agent.
class AgentTask {
  /// Unique task identifier.
  final String id;

  /// Human-readable task description.
  final String description;

  /// Task priority (1 = highest).
  final int priority;

  /// The agent currently assigned to this task.
  String? assignedAgentId;

  /// When the task was created (UTC).
  final DateTime createdAt;

  /// When the task started execution (UTC).
  DateTime? startedAt;

  /// When the task completed (UTC).
  DateTime? completedAt;

  /// Number of retry attempts so far.
  int retryCount;

  /// Maximum retries allowed.
  final int maxRetries;

  /// The task result, if complete.
  Map<String, dynamic>? result;

  /// Error message, if failed.
  String? errorMessage;

  AgentTask({
    required this.id,
    required this.description,
    this.priority = 3,
    this.assignedAgentId,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.result,
    this.errorMessage,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  /// Whether this task has failed and can be retried.
  bool get canRetry => errorMessage != null && retryCount < maxRetries;
}

/// Full registration record for an agent in the runtime.
class AgentRegistration {
  /// Unique agent identifier.
  final String id;

  /// The agent's role/type.
  final AgentType type;

  /// Human-readable display name.
  final String name;

  /// Current operational status.
  AgentStatus status;

  /// The task currently being worked on, if any.
  AgentTask? currentTask;

  /// The LLM model this agent uses.
  String model;

  /// Set of tool IDs this agent is allowed to invoke.
  final Set<String> toolAccess;

  /// When the agent was spawned (UTC).
  final DateTime spawnedAt;

  /// FIFO queue of messages for this agent.
  final List<AgentMessage> messageQueue;

  /// Complete execution trace for debugging.
  final List<String> executionTrace;

  /// The ID of the parent agent that spawned this one, if any.
  final String? parentAgentId;

  /// IDs of sub-agents spawned by this agent.
  final List<String> childAgentIds;

  AgentRegistration({
    required this.id,
    required this.type,
    required this.name,
    this.status = AgentStatus.idle,
    this.currentTask,
    this.model = 'default',
    Set<String>? toolAccess,
    DateTime? spawnedAt,
    List<AgentMessage>? messageQueue,
    List<String>? executionTrace,
    this.parentAgentId,
    List<String>? childAgentIds,
  })  : toolAccess = toolAccess ?? <String>{},
        spawnedAt = spawnedAt ?? DateTime.now().toUtc(),
        messageQueue = messageQueue ?? <AgentMessage>[],
        executionTrace = executionTrace ?? <String>[],
        childAgentIds = childAgentIds ?? <String>[];

  /// Adds a trace entry with timestamp.
  void trace(String entry) {
    final ts = DateTime.now().toUtc().toIso8601String();
    executionTrace.add('[$ts] $entry');
  }
}

/// Configuration for spawning a new agent.
class AgentSpawnConfig {
  /// The type of agent to spawn.
  final AgentType type;

  /// Display name for the agent.
  final String name;

  /// The LLM model the agent should use.
  final String model;

  /// Tool IDs the agent is allowed to use.
  final Set<String> toolAccess;

  /// Optional parent agent ID (for sub-agent spawning).
  final String? parentAgentId;

  const AgentSpawnConfig({
    required this.type,
    required this.name,
    this.model = 'default',
    this.toolAccess = const {},
    this.parentAgentId,
  });
}
