/// Background agent management service.
///
/// [BackgroundAgentService] manages long-running background watchers that
/// monitor git changes, file modifications, build status, MCP health,
/// API usage, todos, artifacts, and costs. Each watcher runs as an
/// independent background isolate or timer-driven loop.
library;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// BackgroundWatcher
// ---------------------------------------------------------------------------

/// A registered background watcher with its lifecycle state.
class BackgroundWatcher {
  BackgroundWatcher({
    required this.id,
    required this.name,
    required this.type,
    this.status = BackgroundWatcherStatus.stopped,
    this.intervalSeconds = 60,
    this.lastRun,
    this.error,
  });

  /// Unique watcher identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// The kind of resource being watched.
  final BackgroundWatcherType type;

  /// Current status.
  BackgroundWatcherStatus status;

  /// Polling interval in seconds.
  final int intervalSeconds;

  /// When this watcher last ran.
  DateTime? lastRun;

  /// Most recent error message (if any).
  String? error;

  /// The active timer (if running).
  Timer? _timer;
}

/// Types of background watchers.
enum BackgroundWatcherType {
  /// Monitors git repository for changes.
  git,

  /// Watches filesystem for modifications.
  files,

  /// Monitors build pipeline status.
  builds,

  /// Checks MCP server health.
  mcpHealth,

  /// Tracks API usage and rate limits.
  apiUsage,

  /// Watches todo list for overdue / blocked items.
  todos,

  /// Monitors artifact storage.
  artifacts,

  /// Tracks cost accumulation against budgets.
  costs,
}

/// Lifecycle status of a background watcher.
enum BackgroundWatcherStatus {
  /// Not running.
  stopped,

  /// Running and polling.
  running,

  /// Encountered an error; will retry.
  error,

  /// Paused by user.
  paused,
}

// ---------------------------------------------------------------------------
// BackgroundAgentEvent
// ---------------------------------------------------------------------------

/// An event emitted by a background watcher.
class BackgroundAgentEvent {
  const BackgroundAgentEvent({
    required this.watcherId,
    required this.type,
    required this.message,
    required this.timestamp,
    this.data = const {},
  });

  /// The watcher that emitted this event.
  final String watcherId;

  /// The watcher type.
  final BackgroundWatcherType type;

  /// Human-readable message.
  final String message;

  /// When the event occurred.
  final DateTime timestamp;

  /// Optional structured data.
  final Map<String, dynamic> data;
}

// ---------------------------------------------------------------------------
// BackgroundAgentService
// ---------------------------------------------------------------------------

/// Service for managing background monitoring agents.
class BackgroundAgentService {
  BackgroundAgentService();

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  final Map<String, BackgroundWatcher> _watchers = {};
  final StreamController<BackgroundAgentEvent> _eventController =
      StreamController<BackgroundAgentEvent>.broadcast();

  /// Stream of events from all background watchers.
  Stream<BackgroundAgentEvent> get events => _eventController.stream;

  /// Start a new background watcher.
  ///
  /// The [handler] callback is invoked on each polling interval and should
  /// return a map of data to include in the emitted event.
  Future<BackgroundWatcher> start({
    required String name,
    required BackgroundWatcherType type,
    int intervalSeconds = 60,
    Future<Map<String, dynamic>> Function()? handler,
  }) async {
    final watcher = BackgroundWatcher(
      id: _uuid.v4(),
      name: name,
      type: type,
      intervalSeconds: intervalSeconds,
      status: BackgroundWatcherStatus.running,
    );

    watcher._timer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) async {
        try {
          final data = await handler?.call() ?? {};
          watcher.lastRun = DateTime.now();
          _eventController.add(BackgroundAgentEvent(
            watcherId: watcher.id,
            type: type,
            message: '${watcher.name} check completed',
            timestamp: DateTime.now(),
            data: data,
          ));
        } catch (e) {
          watcher.status = BackgroundWatcherStatus.error;
          watcher.error = e.toString();
          _log.e('Watcher ${watcher.name} error', error: e);
        }
      },
    );

    _watchers[watcher.id] = watcher;
    _log.i('Background watcher started: ${watcher.name} (${watcher.id})');
    return watcher;
  }

  /// Stop a running watcher.
  Future<void> stop(String id) async {
    final watcher = _watchers[id];
    if (watcher == null) return;
    watcher._timer?.cancel();
    watcher._timer = null;
    watcher.status = BackgroundWatcherStatus.stopped;
    _log.i('Background watcher stopped: ${watcher.name}');
  }

  /// List all registered watchers.
  List<BackgroundWatcher> list() => _watchers.values.toList();

  /// Get the status of a specific watcher.
  BackgroundWatcherStatus? getStatus(String id) => _watchers[id]?.status;

  /// Listen for events matching a specific [type].
  Stream<BackgroundAgentEvent> onEvent(BackgroundWatcherType type) {
    return _eventController.stream.where((e) => e.type == type);
  }

  /// Stop all watchers and close the event stream.
  Future<void> dispose() async {
    for (final watcher in _watchers.values) {
      watcher._timer?.cancel();
    }
    _watchers.clear();
    await _eventController.close();
    _log.i('BackgroundAgentService disposed');
  }
}
