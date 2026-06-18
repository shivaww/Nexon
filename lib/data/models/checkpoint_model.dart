/// Checkpoint data model for project snapshots and rollback.
///
/// [CheckpointModel] captures a point-in-time snapshot of a project's
/// state — git hash, file snapshots, and memory state — enabling the
/// system to roll back to a known-good configuration.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// CheckpointModel
// ---------------------------------------------------------------------------

/// A saved project state checkpoint.
class CheckpointModel extends Equatable {
  /// Creates a new [CheckpointModel].
  const CheckpointModel({
    required this.id,
    required this.name,
    required this.projectId,
    this.gitHash,
    this.fileSnapshots = const {},
    this.memorySnapshot = const {},
    required this.createdAt,
    this.autoCreated = false,
    this.linkedTaskId,
  });

  /// Unique checkpoint identifier.
  final String id;

  /// Human-readable checkpoint name (e.g. "pre-refactor", "v0.2.0").
  final String name;

  /// The project this checkpoint belongs to.
  final String projectId;

  /// Git commit hash at the time of the checkpoint.
  final String? gitHash;

  /// Map of relative file paths → content hashes (SHA-256).
  final Map<String, String> fileSnapshots;

  /// Serialised snapshot of the project's memory state.
  final Map<String, dynamic> memorySnapshot;

  /// When this checkpoint was created.
  final DateTime createdAt;

  /// Whether this checkpoint was created automatically by the system.
  final bool autoCreated;

  /// The task that triggered this checkpoint (if any).
  final String? linkedTaskId;

  /// Returns a copy with the given fields replaced.
  CheckpointModel copyWith({
    String? id,
    String? name,
    String? projectId,
    String? gitHash,
    Map<String, String>? fileSnapshots,
    Map<String, dynamic>? memorySnapshot,
    DateTime? createdAt,
    bool? autoCreated,
    String? linkedTaskId,
  }) {
    return CheckpointModel(
      id: id ?? this.id,
      name: name ?? this.name,
      projectId: projectId ?? this.projectId,
      gitHash: gitHash ?? this.gitHash,
      fileSnapshots: fileSnapshots ?? this.fileSnapshots,
      memorySnapshot: memorySnapshot ?? this.memorySnapshot,
      createdAt: createdAt ?? this.createdAt,
      autoCreated: autoCreated ?? this.autoCreated,
      linkedTaskId: linkedTaskId ?? this.linkedTaskId,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'projectId': projectId,
      'gitHash': gitHash,
      'fileSnapshots': fileSnapshots,
      'memorySnapshot': memorySnapshot,
      'createdAt': createdAt.toIso8601String(),
      'autoCreated': autoCreated,
      'linkedTaskId': linkedTaskId,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory CheckpointModel.fromJson(Map<String, dynamic> json) {
    return CheckpointModel(
      id: json['id'] as String,
      name: json['name'] as String,
      projectId: json['projectId'] as String,
      gitHash: json['gitHash'] as String?,
      fileSnapshots: Map<String, String>.from(
        (json['fileSnapshots'] as Map?) ?? {},
      ),
      memorySnapshot: Map<String, dynamic>.from(
        (json['memorySnapshot'] as Map?) ?? {},
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      autoCreated: (json['autoCreated'] as bool?) ?? false,
      linkedTaskId: json['linkedTaskId'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        projectId,
        gitHash,
        fileSnapshots,
        memorySnapshot,
        createdAt,
        autoCreated,
        linkedTaskId,
      ];
}
