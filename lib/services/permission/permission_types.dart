// ============================================================================
// TermuxForge — Permission Types
// Data models for the permission gating system.
// ============================================================================

/// Defines the nine permission levels used throughout TermuxForge.
///
/// Every tool, shell command, or agent action is tagged with a level.
/// The [PermissionService] gates execution based on the current
/// auto-approve threshold and the user's explicit approvals.
enum PermissionLevel {
  /// Level 0 — No risk. Read-only metadata (e.g., list files, git status).
  none(0, 'No risk — read-only metadata'),

  /// Level 1 — Low risk. Read file contents, search.
  low(1, 'Low risk — read file contents'),

  /// Level 2 — Moderate. Write to project files.
  moderate(2, 'Moderate — write to project files'),

  /// Level 3 — Elevated. Run linters, static analyzers.
  elevated(3, 'Elevated — run linters and analyzers'),

  /// Level 4 — High. Run tests, build commands.
  high(4, 'High — run tests and builds'),

  /// Level 5 — Dangerous. Arbitrary shell execution.
  dangerous(5, 'Dangerous — arbitrary shell execution'),

  /// Level 6 — Critical. Git push, deploy, publish.
  critical(6, 'Critical — git push, deploy'),

  /// Level 7 — Destructive. Delete files, rm commands.
  destructive(7, 'Destructive — delete files'),

  /// Level 8 — System. Modify system-level configuration.
  system(8, 'System — modify system configuration');

  const PermissionLevel(this.level, this.description);

  /// The numeric level (0–8).
  final int level;

  /// A human-readable description of what this level allows.
  final String description;

  /// Returns the [PermissionLevel] matching the given numeric [level].
  ///
  /// Throws [ArgumentError] if [level] is out of range.
  static PermissionLevel fromLevel(int level) {
    return PermissionLevel.values.firstWhere(
      (p) => p.level == level,
      orElse: () => throw ArgumentError('Invalid permission level: $level'),
    );
  }
}

/// The outcome of a permission request.
enum PermissionDecision {
  /// The action was approved (auto or by user).
  approved,

  /// The action was denied by the user.
  denied,

  /// The request is still pending user review.
  pending,
}

/// A request for permission to invoke a tool or command.
class PermissionRequest {
  /// Unique request identifier.
  final String id;

  /// The tool that requires permission.
  final String toolId;

  /// The required permission level.
  final PermissionLevel level;

  /// Human-readable description of the action.
  final String description;

  /// A preview of the command that will be executed (if applicable).
  final String? commandPreview;

  /// The agent or component requesting permission.
  final String requester;

  /// When the request was created (UTC).
  final DateTime requestedAt;

  /// The decision, once made.
  PermissionDecision decision;

  /// When the decision was made (UTC).
  DateTime? decidedAt;

  /// Who or what made the decision ('auto', 'user', agent ID).
  String? decidedBy;

  PermissionRequest({
    required this.id,
    required this.toolId,
    required this.level,
    required this.description,
    this.commandPreview,
    required this.requester,
    DateTime? requestedAt,
    this.decision = PermissionDecision.pending,
    this.decidedAt,
    this.decidedBy,
  }) : requestedAt = requestedAt ?? DateTime.now().toUtc();

  /// Converts to a JSON-serializable map for logging.
  Map<String, dynamic> toJson() => {
        'id': id,
        'toolId': toolId,
        'level': level.level,
        'description': description,
        'commandPreview': commandPreview,
        'requester': requester,
        'requestedAt': requestedAt.toIso8601String(),
        'decision': decision.name,
        'decidedAt': decidedAt?.toIso8601String(),
        'decidedBy': decidedBy,
      };
}

/// A record of a permission decision for audit logging.
class PermissionAuditEntry {
  /// The original request.
  final PermissionRequest request;

  /// The decision that was made.
  final PermissionDecision decision;

  /// When the decision was recorded.
  final DateTime timestamp;

  const PermissionAuditEntry({
    required this.request,
    required this.decision,
    required this.timestamp,
  });
}
