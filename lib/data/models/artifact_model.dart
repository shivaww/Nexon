/// Artifact data models for tracking generated outputs.
///
/// [ArtifactModel] represents any file or bundle produced by the system —
/// APKs, reports, images, test logs, etc. — with provenance tracking and
/// versioning.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// ArtifactType
// ---------------------------------------------------------------------------

/// The kind of output an [ArtifactModel] represents.
enum ArtifactType {
  /// Android APK package.
  apk,

  /// Compressed archive.
  zip,

  /// PDF document.
  pdf,

  /// Generated report.
  report,

  /// Image file (PNG, JPEG, SVG, etc.).
  image,

  /// Video file.
  video,

  /// Documentation bundle.
  documentation,

  /// Raw build output / logs.
  buildOutput,

  /// Test execution log.
  testLog,

  /// Screenshot capture.
  screenshot,

  /// System checkpoint snapshot.
  checkpoint,

  /// Full project bundle for sharing.
  projectBundle,
}

// ---------------------------------------------------------------------------
// ArtifactModel
// ---------------------------------------------------------------------------

/// A tracked artifact produced by the TermuxForge system.
///
/// Artifacts carry provenance information, version tags, and links
/// back to the task and workflow that generated them.
class ArtifactModel extends Equatable {
  /// Creates a new [ArtifactModel].
  const ArtifactModel({
    required this.id,
    required this.name,
    required this.type,
    required this.path,
    this.size = 0,
    this.taskId,
    this.workflowId,
    this.provenance = const {},
    required this.createdAt,
    this.version = '1.0.0',
    this.tags = const [],
  });

  /// Unique artifact identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// The category of this artifact.
  final ArtifactType type;

  /// Absolute filesystem path.
  final String path;

  /// Size in bytes.
  final int size;

  /// The task that produced this artifact (if any).
  final String? taskId;

  /// The workflow that produced this artifact (if any).
  final String? workflowId;

  /// Provenance metadata (tool, model, parameters used, etc.).
  final Map<String, dynamic> provenance;

  /// When this artifact was created.
  final DateTime createdAt;

  /// Semantic version string.
  final String version;

  /// Searchable tags.
  final List<String> tags;

  /// Returns a copy with the given fields replaced.
  ArtifactModel copyWith({
    String? id,
    String? name,
    ArtifactType? type,
    String? path,
    int? size,
    String? taskId,
    String? workflowId,
    Map<String, dynamic>? provenance,
    DateTime? createdAt,
    String? version,
    List<String>? tags,
  }) {
    return ArtifactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      path: path ?? this.path,
      size: size ?? this.size,
      taskId: taskId ?? this.taskId,
      workflowId: workflowId ?? this.workflowId,
      provenance: provenance ?? this.provenance,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      tags: tags ?? this.tags,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'path': path,
      'size': size,
      'taskId': taskId,
      'workflowId': workflowId,
      'provenance': provenance,
      'createdAt': createdAt.toIso8601String(),
      'version': version,
      'tags': tags,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory ArtifactModel.fromJson(Map<String, dynamic> json) {
    return ArtifactModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: ArtifactType.values.byName(json['type'] as String),
      path: json['path'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      taskId: json['taskId'] as String?,
      workflowId: json['workflowId'] as String?,
      provenance: Map<String, dynamic>.from(
        (json['provenance'] as Map?) ?? {},
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: (json['version'] as String?) ?? '1.0.0',
      tags: List<String>.from((json['tags'] as List?) ?? []),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        path,
        size,
        taskId,
        workflowId,
        provenance,
        createdAt,
        version,
        tags,
      ];
}
