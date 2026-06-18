/// Knowledge Base service for curated reference material.
///
/// [KnowledgeBaseService] manages a separate knowledge store from
/// [MemoryService] — this is for imported PDFs, web pages, research notes,
/// and other reference material that agents and users can query with RAG
/// indexing and citation tracking.
library;

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// KnowledgeEntry
// ---------------------------------------------------------------------------

/// A single entry in the knowledge base.
class KnowledgeEntry {
  const KnowledgeEntry({
    required this.id,
    required this.title,
    required this.content,
    this.source,
    this.sourceType = KnowledgeSourceType.note,
    this.tags = const [],
    this.citations = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique entry identifier.
  final String id;

  /// Human-readable title.
  final String title;

  /// Text content.
  final String content;

  /// Original source (file path, URL, etc.).
  final String? source;

  /// Type of the source material.
  final KnowledgeSourceType sourceType;

  /// Searchable tags.
  final List<String> tags;

  /// Citation references.
  final List<String> citations;

  /// Arbitrary metadata.
  final Map<String, dynamic> metadata;

  /// When this entry was created.
  final DateTime createdAt;

  /// When this entry was last updated.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  KnowledgeEntry copyWith({
    String? id,
    String? title,
    String? content,
    String? source,
    KnowledgeSourceType? sourceType,
    List<String>? tags,
    List<String>? citations,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KnowledgeEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      source: source ?? this.source,
      sourceType: sourceType ?? this.sourceType,
      tags: tags ?? this.tags,
      citations: citations ?? this.citations,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'source': source,
      'sourceType': sourceType.name,
      'tags': tags,
      'citations': citations,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory KnowledgeEntry.fromJson(Map<String, dynamic> json) {
    return KnowledgeEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      source: json['source'] as String?,
      sourceType: KnowledgeSourceType.values.byName(
        (json['sourceType'] as String?) ?? 'note',
      ),
      tags: List<String>.from((json['tags'] as List?) ?? []),
      citations: List<String>.from((json['citations'] as List?) ?? []),
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? {},
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// Type of source material for a knowledge entry.
enum KnowledgeSourceType {
  /// A user-written note.
  note,

  /// Imported PDF document.
  pdf,

  /// Imported web page.
  website,

  /// API documentation.
  apiDoc,

  /// Code snippet / example.
  codeExample,

  /// Research paper / article.
  research,
}

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for the knowledge base persistence layer.
abstract class KnowledgeBaseRepository {
  Future<void> save(KnowledgeEntry entry);
  Future<KnowledgeEntry?> get(String id);
  Future<List<KnowledgeEntry>> getAll();
  Future<void> delete(String id);
  Future<List<KnowledgeEntry>> query(
    bool Function(KnowledgeEntry) predicate,
  );
}

/// In-memory [KnowledgeBaseRepository] for development.
class InMemoryKnowledgeBaseRepository implements KnowledgeBaseRepository {
  final Map<String, KnowledgeEntry> _store = {};

  @override
  Future<void> save(KnowledgeEntry entry) async => _store[entry.id] = entry;

  @override
  Future<KnowledgeEntry?> get(String id) async => _store[id];

  @override
  Future<List<KnowledgeEntry>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<KnowledgeEntry>> query(
    bool Function(KnowledgeEntry) predicate,
  ) async {
    return _store.values.where(predicate).toList();
  }
}

// ---------------------------------------------------------------------------
// KnowledgeBaseService
// ---------------------------------------------------------------------------

/// Service for managing the curated knowledge base.
class KnowledgeBaseService {
  /// Creates a [KnowledgeBaseService] backed by the given [repository].
  KnowledgeBaseService({KnowledgeBaseRepository? repository})
      : _repo = repository ?? InMemoryKnowledgeBaseRepository();

  final KnowledgeBaseRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// Add a new knowledge entry.
  Future<KnowledgeEntry> add({
    required String title,
    required String content,
    String? source,
    KnowledgeSourceType sourceType = KnowledgeSourceType.note,
    List<String> tags = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    final now = DateTime.now();
    final entry = KnowledgeEntry(
      id: _uuid.v4(),
      title: title,
      content: content,
      source: source,
      sourceType: sourceType,
      tags: tags,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(entry);
    _log.d('Knowledge added: ${entry.id} — $title');
    return entry;
  }

  /// Search entries by keyword across title, content, and tags.
  Future<List<KnowledgeEntry>> search(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    final lower = keyword.toLowerCase();
    return _repo.query((e) {
      return e.title.toLowerCase().contains(lower) ||
          e.content.toLowerCase().contains(lower) ||
          e.tags.any((t) => t.toLowerCase().contains(lower));
    });
  }

  /// List all entries.
  Future<List<KnowledgeEntry>> listEntries() => _repo.getAll();

  /// Import a PDF by path. Extracts text and stores it.
  ///
  /// Text extraction is a placeholder — integrate a real PDF parser in
  /// production.
  Future<KnowledgeEntry> importPDF(String path) async {
    _log.i('Importing PDF: $path');
    // Placeholder: in production, use a PDF extraction library.
    return add(
      title: path.split('/').last,
      content: '[PDF content from $path — extraction pending]',
      source: path,
      sourceType: KnowledgeSourceType.pdf,
      tags: ['pdf', 'imported'],
    );
  }

  /// Import content from a website URL.
  ///
  /// Web scraping is a placeholder — integrate an HTTP client in production.
  Future<KnowledgeEntry> importWebsite(String url) async {
    _log.i('Importing website: $url');
    return add(
      title: 'Web: $url',
      content: '[Web content from $url — scraping pending]',
      source: url,
      sourceType: KnowledgeSourceType.website,
      tags: ['web', 'imported'],
    );
  }

  /// Add a free-form note.
  Future<KnowledgeEntry> addNote({
    required String title,
    required String content,
    List<String> tags = const [],
  }) async {
    return add(
      title: title,
      content: content,
      sourceType: KnowledgeSourceType.note,
      tags: tags,
    );
  }

  /// Add tags to an existing entry.
  Future<KnowledgeEntry?> tag(String id, List<String> newTags) async {
    final existing = await _repo.get(id);
    if (existing == null) return null;
    final merged = {...existing.tags, ...newTags}.toList();
    final updated = existing.copyWith(
      tags: merged,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    return updated;
  }

  /// Export all entries as JSON.
  Future<List<Map<String, dynamic>>> export() async {
    final all = await _repo.getAll();
    return all.map((e) => e.toJson()).toList();
  }
}
