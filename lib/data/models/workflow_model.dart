/// Workflow engine data models.
///
/// [WorkflowModel] represents an automatable pipeline of [WorkflowStep]s that
/// can be triggered manually, on a schedule, or in response to events.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// WorkflowType
// ---------------------------------------------------------------------------

/// Execution strategy for a [WorkflowModel].
enum WorkflowType {
  /// Steps run one after another.
  sequential,

  /// Steps run concurrently.
  parallel,

  /// Step execution depends on conditional logic.
  conditional,

  /// Triggered by a cron-like schedule.
  scheduled,

  /// Triggered by a system or user event.
  eventTriggered,
}

// ---------------------------------------------------------------------------
// WorkflowTrigger
// ---------------------------------------------------------------------------

/// Describes what initiates a workflow run.
class WorkflowTrigger extends Equatable {
  /// Creates a new [WorkflowTrigger].
  const WorkflowTrigger({
    this.event,
    this.schedule,
    this.manual = false,
  });

  /// Event name that triggers the workflow (e.g. "git:push").
  final String? event;

  /// Cron expression for scheduled triggers.
  final String? schedule;

  /// Whether the workflow can be triggered manually.
  final bool manual;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'event': event,
      'schedule': schedule,
      'manual': manual,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory WorkflowTrigger.fromJson(Map<String, dynamic> json) {
    return WorkflowTrigger(
      event: json['event'] as String?,
      schedule: json['schedule'] as String?,
      manual: (json['manual'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [event, schedule, manual];
}

// ---------------------------------------------------------------------------
// WorkflowStep
// ---------------------------------------------------------------------------

/// A single step within a [WorkflowModel].
class WorkflowStep extends Equatable {
  /// Creates a new [WorkflowStep].
  const WorkflowStep({
    required this.id,
    required this.name,
    required this.action,
    this.status = 'pending',
    this.input = const {},
    this.output = const {},
    this.retries = 0,
    this.fallback,
  });

  /// Unique step identifier.
  final String id;

  /// Human-readable step name.
  final String name;

  /// The action to execute (tool call, agent dispatch, shell command, etc.).
  final String action;

  /// Current step status (e.g. "pending", "running", "completed", "failed").
  final String status;

  /// Input parameters for this step.
  final Map<String, dynamic> input;

  /// Output produced by this step.
  final Map<String, dynamic> output;

  /// Number of retry attempts allowed on failure.
  final int retries;

  /// Fallback action identifier if all retries fail.
  final String? fallback;

  /// Returns a copy with the given fields replaced.
  WorkflowStep copyWith({
    String? id,
    String? name,
    String? action,
    String? status,
    Map<String, dynamic>? input,
    Map<String, dynamic>? output,
    int? retries,
    String? fallback,
  }) {
    return WorkflowStep(
      id: id ?? this.id,
      name: name ?? this.name,
      action: action ?? this.action,
      status: status ?? this.status,
      input: input ?? this.input,
      output: output ?? this.output,
      retries: retries ?? this.retries,
      fallback: fallback ?? this.fallback,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'action': action,
      'status': status,
      'input': input,
      'output': output,
      'retries': retries,
      'fallback': fallback,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory WorkflowStep.fromJson(Map<String, dynamic> json) {
    return WorkflowStep(
      id: json['id'] as String,
      name: json['name'] as String,
      action: json['action'] as String,
      status: (json['status'] as String?) ?? 'pending',
      input: Map<String, dynamic>.from((json['input'] as Map?) ?? {}),
      output: Map<String, dynamic>.from((json['output'] as Map?) ?? {}),
      retries: (json['retries'] as num?)?.toInt() ?? 0,
      fallback: json['fallback'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        action,
        status,
        input,
        output,
        retries,
        fallback,
      ];
}

// ---------------------------------------------------------------------------
// WorkflowModel
// ---------------------------------------------------------------------------

/// A full workflow pipeline that orchestrates a sequence of steps.
class WorkflowModel extends Equatable {
  /// Creates a new [WorkflowModel].
  const WorkflowModel({
    required this.id,
    required this.name,
    required this.type,
    this.steps = const [],
    this.status = 'idle',
    this.triggers = const [],
    this.schedule,
    this.logs = const [],
    this.startedAt,
    this.completedAt,
  });

  /// Unique workflow identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Execution strategy.
  final WorkflowType type;

  /// Ordered list of steps.
  final List<WorkflowStep> steps;

  /// Current workflow status (e.g. "idle", "running", "completed", "failed").
  final String status;

  /// Triggers that can initiate this workflow.
  final List<WorkflowTrigger> triggers;

  /// Cron expression for scheduled workflows.
  final String? schedule;

  /// Chronological execution logs.
  final List<String> logs;

  /// When the workflow started executing.
  final DateTime? startedAt;

  /// When the workflow finished executing.
  final DateTime? completedAt;

  /// Returns a copy with the given fields replaced.
  WorkflowModel copyWith({
    String? id,
    String? name,
    WorkflowType? type,
    List<WorkflowStep>? steps,
    String? status,
    List<WorkflowTrigger>? triggers,
    String? schedule,
    List<String>? logs,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return WorkflowModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      triggers: triggers ?? this.triggers,
      schedule: schedule ?? this.schedule,
      logs: logs ?? this.logs,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'steps': steps.map((s) => s.toJson()).toList(),
      'status': status,
      'triggers': triggers.map((t) => t.toJson()).toList(),
      'schedule': schedule,
      'logs': logs,
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory WorkflowModel.fromJson(Map<String, dynamic> json) {
    return WorkflowModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: WorkflowType.values.byName(json['type'] as String),
      steps: (json['steps'] as List?)
              ?.map((e) => WorkflowStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: (json['status'] as String?) ?? 'idle',
      triggers: (json['triggers'] as List?)
              ?.map(
                (e) => WorkflowTrigger.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      schedule: json['schedule'] as String?,
      logs: List<String>.from((json['logs'] as List?) ?? []),
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        steps,
        status,
        triggers,
        schedule,
        logs,
        startedAt,
        completedAt,
      ];
}
