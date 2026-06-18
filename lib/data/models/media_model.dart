/// Media generation data models.
///
/// [MediaJob] tracks image and video generation requests including the
/// prompt, provider, model, status, output path, and cost.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// MediaType
// ---------------------------------------------------------------------------

/// The type of media being generated.
enum MediaType {
  /// Static image (PNG, JPEG, WebP, etc.).
  image,

  /// Video file (MP4, WebM, etc.).
  video,
}

// ---------------------------------------------------------------------------
// MediaJobStatus
// ---------------------------------------------------------------------------

/// Lifecycle states of a [MediaJob].
enum MediaJobStatus {
  /// Job has been queued.
  queued,

  /// Generation is in progress.
  processing,

  /// Generation completed successfully.
  completed,

  /// Generation failed.
  failed,

  /// Job was cancelled.
  cancelled,
}

// ---------------------------------------------------------------------------
// MediaJob
// ---------------------------------------------------------------------------

/// A media generation request and its lifecycle state.
class MediaJob extends Equatable {
  /// Creates a new [MediaJob].
  const MediaJob({
    required this.id,
    required this.type,
    required this.prompt,
    required this.provider,
    required this.model,
    this.status = MediaJobStatus.queued,
    this.outputPath,
    this.cost = 0.0,
    required this.createdAt,
    this.completedAt,
    this.error,
    this.metadata = const {},
  });

  /// Unique job identifier.
  final String id;

  /// The type of media being generated.
  final MediaType type;

  /// The generation prompt.
  final String prompt;

  /// Provider used for generation.
  final String provider;

  /// Model used for generation.
  final String model;

  /// Current job status.
  final MediaJobStatus status;

  /// Filesystem path of the generated output (when completed).
  final String? outputPath;

  /// Cost in USD for this generation.
  final double cost;

  /// When the job was created.
  final DateTime createdAt;

  /// When the job completed (or failed).
  final DateTime? completedAt;

  /// Error message (if failed).
  final String? error;

  /// Additional parameters / metadata for the generation request.
  final Map<String, dynamic> metadata;

  /// Returns a copy with the given fields replaced.
  MediaJob copyWith({
    String? id,
    MediaType? type,
    String? prompt,
    String? provider,
    String? model,
    MediaJobStatus? status,
    String? outputPath,
    double? cost,
    DateTime? createdAt,
    DateTime? completedAt,
    String? error,
    Map<String, dynamic>? metadata,
  }) {
    return MediaJob(
      id: id ?? this.id,
      type: type ?? this.type,
      prompt: prompt ?? this.prompt,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      status: status ?? this.status,
      outputPath: outputPath ?? this.outputPath,
      cost: cost ?? this.cost,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'prompt': prompt,
      'provider': provider,
      'model': model,
      'status': status.name,
      'outputPath': outputPath,
      'cost': cost,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'error': error,
      'metadata': metadata,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory MediaJob.fromJson(Map<String, dynamic> json) {
    return MediaJob(
      id: json['id'] as String,
      type: MediaType.values.byName(json['type'] as String),
      prompt: json['prompt'] as String,
      provider: json['provider'] as String,
      model: json['model'] as String,
      status: MediaJobStatus.values.byName(
        (json['status'] as String?) ?? 'queued',
      ),
      outputPath: json['outputPath'] as String?,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      error: json['error'] as String?,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? {},
      ),
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        prompt,
        provider,
        model,
        status,
        outputPath,
        cost,
        createdAt,
        completedAt,
        error,
        metadata,
      ];
}
