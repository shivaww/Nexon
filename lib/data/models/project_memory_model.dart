/// Project Memory data models for the TermuxForge agentic memory system.
///
/// These models represent the core memory entries that agents create,
/// reference, and query throughout the lifecycle of a project. Each
/// [MemoryEntry] captures a discrete piece of knowledge — from architecture
/// decisions to bug history to MCP tool usage — and can optionally carry
/// a vector embedding for semantic search.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// MemoryType
// ---------------------------------------------------------------------------

/// Categorises the kind of knowledge stored in a [MemoryEntry].
enum MemoryType {
  /// A user or system requirement captured for the project.
  requirement,

  /// A recorded architecture / design decision.
  architectureDecision,

  /// A reference to a file path relevant to context.
  fileReference,

  /// A chunk of source code stored for retrieval.
  codeChunk,

  /// Historical record of a bug and its resolution.
  bugHistory,

  /// Free-form note left by an agent.
  agentNote,

  /// Record of a tool invocation and its outcome.
  toolUsage,

  /// Persisted user preference (theme, model, etc.).
  userPreference,

  /// Output / result produced by a task or agent.
  output,

  /// Snapshot of the current todo list state.
  todoSnapshot,

  /// Usage statistics for a specific LLM provider.
  providerUsage,

  /// Preferred model selection for a given task type.
  modelPreference,

  /// Status record of an MCP server connection.
  mcpStatus,

  /// History of MCP tool invocations.
  mcpToolHistory,

  /// Results from a web research action.
  webResearch,

  /// A complete workflow execution record.
  workflowRun,

  /// Background watcher event or alert.
  backgroundWatch,

  /// Historical cost data point.
  costHistory,

  /// A system or user-initiated checkpoint.
  checkpoint,

  /// Metadata for a rollback operation.
  rollbackMeta,

  /// Metadata about a generated / stored artifact.
  artifactMeta,

  /// Record of a media generation job.
  mediaGeneration,

  /// Metadata for a locally-hosted model.
  localModelMeta,

  /// Result from a model battle / comparison.
  battleResult,
}

// ---------------------------------------------------------------------------
// MemoryEntry
// ---------------------------------------------------------------------------

/// A single entry in the project memory system.
///
/// Each entry has a [type] that categorises it, free-form [content], optional
/// structured [metadata], searchable [tags], and cross-references to the
/// project, agent, and task that produced it.
///
/// An optional [embedding] vector enables semantic (RAG) search via
/// [VectorMemoryService].
class MemoryEntry extends Equatable {
  /// Creates a new [MemoryEntry].
  const MemoryEntry({
    required this.id,
    required this.type,
    required this.content,
    this.metadata = const {},
    this.tags = const [],
    this.projectId,
    this.agentId,
    this.taskId,
    this.fileRefs = const [],
    this.embedding,
    this.relevanceScore = 0.0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique identifier for this memory entry.
  final String id;

  /// The category of knowledge this entry represents.
  final MemoryType type;

  /// Human-readable content / description.
  final String content;

  /// Arbitrary key-value metadata for downstream consumers.
  final Map<String, dynamic> metadata;

  /// Searchable tags for fast keyword filtering.
  final List<String> tags;

  /// The project this entry belongs to (if any).
  final String? projectId;

  /// The agent that created this entry (if any).
  final String? agentId;

  /// The task that produced this entry (if any).
  final String? taskId;

  /// File paths referenced by this memory entry.
  final List<String> fileRefs;

  /// Optional vector embedding for semantic search.
  ///
  /// Populated by the vector memory service when the entry is indexed.
  final List<double>? embedding;

  /// Relevance score assigned during search (0.0 – 1.0).
  final double relevanceScore;

  /// When this entry was first created.
  final DateTime createdAt;

  /// When this entry was last modified.
  final DateTime updatedAt;

  /// Returns a deep copy with the given fields replaced.
  MemoryEntry copyWith({
    String? id,
    MemoryType? type,
    String? content,
    Map<String, dynamic>? metadata,
    List<String>? tags,
    String? projectId,
    String? agentId,
    String? taskId,
    List<String>? fileRefs,
    List<double>? embedding,
    double? relevanceScore,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MemoryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      tags: tags ?? this.tags,
      projectId: projectId ?? this.projectId,
      agentId: agentId ?? this.agentId,
      taskId: taskId ?? this.taskId,
      fileRefs: fileRefs ?? this.fileRefs,
      embedding: embedding ?? this.embedding,
      relevanceScore: relevanceScore ?? this.relevanceScore,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'metadata': metadata,
      'tags': tags,
      'projectId': projectId,
      'agentId': agentId,
      'taskId': taskId,
      'fileRefs': fileRefs,
      'embedding': embedding,
      'relevanceScore': relevanceScore,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    return MemoryEntry(
      id: json['id'] as String,
      type: MemoryType.values.byName(json['type'] as String),
      content: json['content'] as String,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? {},
      ),
      tags: List<String>.from((json['tags'] as List?) ?? []),
      projectId: json['projectId'] as String?,
      agentId: json['agentId'] as String?,
      taskId: json['taskId'] as String?,
      fileRefs: List<String>.from((json['fileRefs'] as List?) ?? []),
      embedding: (json['embedding'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      relevanceScore: (json['relevanceScore'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        content,
        metadata,
        tags,
        projectId,
        agentId,
        taskId,
        fileRefs,
        embedding,
        relevanceScore,
        createdAt,
        updatedAt,
      ];
}
