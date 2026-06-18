// ============================================================================
// TermuxForge — Event Bus
// Core pub/sub event system for decoupled inter-service communication.
// ============================================================================

import 'dart:async';

import 'package:uuid/uuid.dart';

/// The base class for every event that flows through the [EventBus].
///
/// All domain events must extend this class and populate [type] with a
/// human-readable discriminator (typically the subclass name).
///
/// ```dart
/// class MyEvent extends AppEvent {
///   MyEvent({required super.source}) : super(type: 'MyEvent');
/// }
/// ```
class AppEvent {
  /// A unique identifier for this event instance.
  final String id;

  /// UTC timestamp of when the event was created.
  final DateTime timestamp;

  /// The component or agent that emitted this event.
  final String source;

  /// A string discriminator for the event type.
  final String type;

  /// Creates an [AppEvent].
  ///
  /// [source] identifies the emitter. [type] is set by subclasses.
  AppEvent({
    required this.source,
    required this.type,
    String? id,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String toString() => 'AppEvent($type, id=$id, source=$source)';
}

/// A broadcast-capable, singleton event bus with history and tracing.
///
/// ## Usage
///
/// ```dart
/// final bus = EventBus.instance;
///
/// bus.subscribe<TaskCreated>((event) {
///   print('New task: ${event.taskId}');
/// });
///
/// bus.publish(TaskCreated(taskId: '1', description: 'Fix bug', source: 'ui'));
/// ```
///
/// Internally backed by a [StreamController.broadcast] so that multiple
/// listeners can subscribe to the same event type simultaneously.
class EventBus {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  EventBus._internal();

  /// The global [EventBus] instance.
  static final EventBus instance = EventBus._internal();

  /// Factory constructor that returns the singleton [instance].
  factory EventBus() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// The broadcast stream controller that all events pass through.
  final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast();

  /// Stores the last [_maxHistory] events for replay / debugging.
  final List<AppEvent> _history = [];

  /// Maximum number of events retained in [_history].
  static const int _maxHistory = 1000;

  /// Tracks active subscriptions for cleanup.
  final Map<String, StreamSubscription<AppEvent>> _subscriptions = {};

  /// Whether debug tracing is enabled.
  bool debugTracing = false;

  /// Counter used to generate deterministic subscription ids.
  int _subIdCounter = 0;

  // ---------------------------------------------------------------------------
  // Publishing
  // ---------------------------------------------------------------------------

  /// Publishes an [event] to all matching subscribers.
  ///
  /// The event is added to the internal history buffer (capped at
  /// [_maxHistory]) and then pushed into the broadcast stream.
  ///
  /// When [debugTracing] is enabled, a trace line is printed to the console.
  void publish(AppEvent event) {
    // Maintain bounded history.
    _history.add(event);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }

    if (debugTracing) {
      // ignore: avoid_print
      print('[EventBus] ${event.type} from ${event.source} (${event.id})');
    }

    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  // ---------------------------------------------------------------------------
  // Subscribing
  // ---------------------------------------------------------------------------

  /// Subscribes to events of type [T].
  ///
  /// Returns a subscription ID that can later be passed to [unsubscribe].
  ///
  /// ```dart
  /// final subId = bus.subscribe<TaskCreated>((e) => handleTask(e));
  /// ```
  String subscribe<T extends AppEvent>(void Function(T event) handler) {
    final id = 'sub_${_subIdCounter++}';
    final subscription = _controller.stream
        .where((event) => event is T)
        .cast<T>()
        .listen(handler);
    _subscriptions[id] = subscription;
    return id;
  }

  /// Subscribes to **all** events regardless of type.
  ///
  /// Useful for logging, metrics, or debug panels.
  String subscribeAll(void Function(AppEvent event) handler) {
    final id = 'sub_${_subIdCounter++}';
    final subscription = _controller.stream.listen(handler);
    _subscriptions[id] = subscription;
    return id;
  }

  /// Cancels the subscription identified by [subscriptionId].
  ///
  /// Returns `true` if the subscription existed and was cancelled.
  bool unsubscribe(String subscriptionId) {
    final sub = _subscriptions.remove(subscriptionId);
    if (sub != null) {
      sub.cancel();
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Stream access
  // ---------------------------------------------------------------------------

  /// Returns a filtered broadcast [Stream] of events of type [T].
  ///
  /// Callers are responsible for managing the subscription lifecycle.
  Stream<T> stream<T extends AppEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  /// Returns the raw broadcast stream of all events.
  Stream<AppEvent> get allEvents => _controller.stream;

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  /// Returns an unmodifiable view of the event history.
  ///
  /// Optionally filter by [type] string or limit to the last [limit] events.
  List<AppEvent> getHistory({String? type, int? limit}) {
    Iterable<AppEvent> result = _history;
    if (type != null) {
      result = result.where((e) => e.type == type);
    }
    final list = result.toList();
    if (limit != null && list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return List.unmodifiable(list);
  }

  /// Clears the entire event history buffer.
  void clearHistory() => _history.clear();

  /// The number of events currently in the history buffer.
  int get historyLength => _history.length;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Cancels all subscriptions and closes the event stream.
  ///
  /// After calling [dispose], the bus should not be used again. This is
  /// primarily for testing; in production the singleton lives for the app
  /// lifetime.
  Future<void> dispose() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _history.clear();
    await _controller.close();
  }
}
