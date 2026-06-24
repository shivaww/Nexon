import 'dart:convert';
import 'package:uuid/uuid.dart';

enum TeamPhase {
  init,
  architect,
  implementing,
  critic,
  synthesizing,
  completed,
  failed
}

class TeamSessionState {
  final String sessionId;
  final String taskDescription;
  final TeamPhase currentPhase;
  final List<String> completedPhases;
  final String lastCheckpoint;
  final String? errorReason;

  TeamSessionState({
    required this.sessionId,
    required this.taskDescription,
    this.currentPhase = TeamPhase.init,
    this.completedPhases = const [],
    required this.lastCheckpoint,
    this.errorReason,
  });

  factory TeamSessionState.create(String task) {
    return TeamSessionState(
      sessionId: 'sess_${const Uuid().v4().replaceAll('-', '').substring(0, 8)}',
      taskDescription: task,
      lastCheckpoint: DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'task_description': taskDescription,
      'current_phase': currentPhase.name,
      'completed_phases': completedPhases,
      'last_checkpoint': lastCheckpoint,
      'error_reason': errorReason,
    };
  }

  factory TeamSessionState.fromJson(Map<String, dynamic> json) {
    return TeamSessionState(
      sessionId: json['session_id'],
      taskDescription: json['task_description'],
      currentPhase: TeamPhase.values.firstWhere((e) => e.name == json['current_phase'], orElse: () => TeamPhase.init),
      completedPhases: List<String>.from(json['completed_phases'] ?? []),
      lastCheckpoint: json['last_checkpoint'],
      errorReason: json['error_reason'],
    );
  }

  TeamSessionState copyWith({
    TeamPhase? currentPhase,
    List<String>? completedPhases,
    String? lastCheckpoint,
    String? errorReason,
  }) {
    return TeamSessionState(
      sessionId: sessionId,
      taskDescription: taskDescription,
      currentPhase: currentPhase ?? this.currentPhase,
      completedPhases: completedPhases ?? this.completedPhases,
      lastCheckpoint: lastCheckpoint ?? DateTime.now().toIso8601String(),
      errorReason: errorReason ?? this.errorReason,
    );
  }
}

class SessionManifest {
  final String sessionId;
  final String task;
  final Map<String, String> sharedSymbols;
  final String outputDir;
  final List<String> modules;

  SessionManifest({
    required this.sessionId,
    required this.task,
    this.sharedSymbols = const {},
    required this.outputDir,
    this.modules = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'task': task,
      'shared_symbols': sharedSymbols,
      'output_dir': outputDir,
      'modules': modules,
    };
  }

  factory SessionManifest.fromJson(Map<String, dynamic> json) {
    return SessionManifest(
      sessionId: json['session_id'],
      task: json['task'],
      sharedSymbols: Map<String, String>.from(json['shared_symbols'] ?? {}),
      outputDir: json['output_dir'] ?? '',
      modules: List<String>.from(json['modules'] ?? []),
    );
  }
}
