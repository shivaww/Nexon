/// Workspace data model for multi-project management.
///
/// [WorkspaceModel] represents a collection of projects and their shared
/// configuration — model preferences, MCP servers, knowledge bases, etc.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// WorkspaceModel
// ---------------------------------------------------------------------------

/// A workspace that groups related projects and shared configuration.
class WorkspaceModel extends Equatable {
  /// Creates a new [WorkspaceModel].
  const WorkspaceModel({
    required this.id,
    required this.name,
    this.projects = const [],
    this.taskSets = const [],
    this.modelConfigs = const {},
    this.mcpServers = const [],
    this.knowledgeBases = const [],
    this.activePath,
    required this.createdAt,
  });

  /// Unique workspace identifier.
  final String id;

  /// Human-readable workspace name.
  final String name;

  /// Project IDs contained within this workspace.
  final List<String> projects;

  /// Task set IDs grouped under this workspace.
  final List<String> taskSets;

  /// Model configuration overrides keyed by scope (e.g. "default", project ID).
  final Map<String, dynamic> modelConfigs;

  /// MCP server identifiers registered for this workspace.
  final List<String> mcpServers;

  /// Knowledge base IDs associated with this workspace.
  final List<String> knowledgeBases;

  /// Filesystem path of the currently active project within the workspace.
  final String? activePath;

  /// When this workspace was created.
  final DateTime createdAt;

  /// Returns a copy with the given fields replaced.
  WorkspaceModel copyWith({
    String? id,
    String? name,
    List<String>? projects,
    List<String>? taskSets,
    Map<String, dynamic>? modelConfigs,
    List<String>? mcpServers,
    List<String>? knowledgeBases,
    String? activePath,
    DateTime? createdAt,
  }) {
    return WorkspaceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      projects: projects ?? this.projects,
      taskSets: taskSets ?? this.taskSets,
      modelConfigs: modelConfigs ?? this.modelConfigs,
      mcpServers: mcpServers ?? this.mcpServers,
      knowledgeBases: knowledgeBases ?? this.knowledgeBases,
      activePath: activePath ?? this.activePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'projects': projects,
      'taskSets': taskSets,
      'modelConfigs': modelConfigs,
      'mcpServers': mcpServers,
      'knowledgeBases': knowledgeBases,
      'activePath': activePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory WorkspaceModel.fromJson(Map<String, dynamic> json) {
    return WorkspaceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      projects: List<String>.from((json['projects'] as List?) ?? []),
      taskSets: List<String>.from((json['taskSets'] as List?) ?? []),
      modelConfigs: Map<String, dynamic>.from(
        (json['modelConfigs'] as Map?) ?? {},
      ),
      mcpServers: List<String>.from((json['mcpServers'] as List?) ?? []),
      knowledgeBases:
          List<String>.from((json['knowledgeBases'] as List?) ?? []),
      activePath: json['activePath'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        projects,
        taskSets,
        modelConfigs,
        mcpServers,
        knowledgeBases,
        activePath,
        createdAt,
      ];
}
