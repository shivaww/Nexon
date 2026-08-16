import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thrown when the native tools bridge cannot start at all (binary missing,
/// spawn failed). Per-call failures are returned as result maps instead, so
/// the LLM sees them and can react — this exception is for setup errors only.
class NativeToolsException implements Exception {
  final String message;
  NativeToolsException(this.message);
  @override
  String toString() => message;
}

class _PendingCall {
  final Completer<Map<String, dynamic>> completer;
  final String tool;
  _PendingCall(this.completer, this.tool);
}

/// Native C++ tools bridge — the low-latency fast path for agentic file ops.
///
/// Spawns ONE persistent `tools --plain --max-output=N <workspace>` process
/// and pipes one compact JSON command per line into its stdin, reading one
/// JSON result per line back from stdout. No Python interpreter, no HTTP
/// hop, no XML anywhere in the chain.
///
/// Routing contract (kept in sync with the AGENTIC IDE system prompt):
///   * tools listed in [cppTools] execute here;
///   * everything else (background services, MCP, deep research, dart
///     tooling) keeps using the Python bridge over HTTP, exactly as before.
///
/// The process is restarted automatically when the workspace changes or the
/// binary dies. Calls are serialized through an in-order queue: the tools
/// binary answers commands strictly in the order they are received.
class NativeToolsService {
  NativeToolsService._();
  static final NativeToolsService instance = NativeToolsService._();
  factory NativeToolsService() => instance;

  /// Tool names the C++ binary implements (short aliases; the binary also
  /// accepts the long *_tool names, but the prompt only emits these).
  static const Set<String> cppTools = {
    'sh', 'search', 'read', 'patch', 'edit', 'git', 'list', 'find',
    'outline', 'recent', 'undo', 'create_file', 'create_directory', 'mkdir',
    'cut', 'extract', 'fileops', 'diagnostics', 'version', 'py',
  };

  static bool handles(String toolName) => cppTools.contains(toolName);

  /// Result cap per tool call. Mirrors the paging guidance in tools.cpp:
  /// anything bigger comes back wrapped with a truncation note instead of
  /// flooding the model context.
  static const int _maxOutputChars = 60000;

  Process? _process;
  String _workspace = '';
  String _binaryPath = '';
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final List<_PendingCall> _queue = [];
  final List<String> _stderrTail = [];

  bool get isRunning => _process != null;
  String get workspace => _workspace;
  String get binaryPath => _binaryPath;

  /// Locate the tools binary. Order: explicit override, then known install
  /// spots. Returns null when nothing is found.
  static Future<String?> findBinary({String? preferred}) async {
    final home =
        Platform.environment['HOME'] ?? '/data/data/com.termux/files/home';
    final candidates = <String>[
      if (preferred != null && preferred.trim().isNotEmpty) preferred.trim(),
      '$home/nexon_bridge/tools',
      '$home/projects/termux_forge/cpp_bridge/tools',
      '$home/codetools/tools',
    ];
    for (final candidate in candidates) {
      try {
        if (await File(candidate).exists()) return candidate;
      } catch (_) {}
    }
    return null;
  }

  /// Start (or restart, when the workspace changed) the tools process.
  Future<void> ensureRunning({
    required String workspace,
    String? binaryPath,
  }) async {
    if (_process != null && _workspace == workspace) return;
    await _teardown();
    final bin = binaryPath ?? await findBinary();
    if (bin == null) {
      throw NativeToolsException(
        'tools binary not found. Compile cpp_bridge/tools.cpp or set the '
        'native tools binary path in settings.');
    }
    try {
      _process = await Process.start(bin, [
        '--plain',
        '--max-output=$_maxOutputChars',
        workspace,
      ]);
    } catch (e) {
      _process = null;
      throw NativeToolsException('failed to start tools binary: $e');
    }
    _binaryPath = bin;
    _workspace = workspace;
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdoutLine);
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStderrLine);
    _process!.exitCode.then((_) => _handleExit()).ignore();
  }

  /// Execute one tool call and return the parsed JSON result. Never throws
  /// for tool-level failures — those come back as {'err': ...} maps the LLM
  /// can read. Setup failures rethrow [NativeToolsException].
  Future<Map<String, dynamic>> call({
    required String workspace,
    required String tool,
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 120),
    String? binaryPath,
  }) async {
    await ensureRunning(workspace: workspace, binaryPath: binaryPath);
    final completer = Completer<Map<String, dynamic>>();
    _queue.add(_PendingCall(completer, tool));
    final line = jsonEncode({'t': tool, 'a': args});
    try {
      _process!.stdin.writeln(line);
      await _process!.stdin.flush();
    } catch (e) {
      _queue.removeWhere((p) => p.completer == completer);
      await _teardown();
      return {
        'err': 'failed to write to tools process: $e',
        't': tool,
      };
    }
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _queue.removeWhere((p) => p.completer == completer);
      await _teardown();
      return {
        'err':
            'native tools call timed out after ${timeout.inSeconds}s; the bridge was restarted',
        't': tool,
      };
    }
  }

  // ------------------------------------------------------------------ stdout

  void _onStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || _queue.isEmpty) return;
    Map<String, dynamic>? parsed;
    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } catch (_) {
      return; // non-JSON noise; keep waiting for the real result line
    }
    final pending = _queue.removeAt(0);
    if (!pending.completer.isCompleted) pending.completer.complete(parsed);
  }

  void _onStderrLine(String line) {
    _stderrTail.add(line);
    while (_stderrTail.length > 40) {
      _stderrTail.removeAt(0);
    }
  }

  void _handleExit() {
    final message =
        'tools process exited unexpectedly; stderr tail: ${_stderrTail.isEmpty ? "(none)" : _stderrTail.join(" | ")}';
    for (final pending in _queue) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete({'err': message, 't': pending.tool});
      }
    }
    _queue.clear();
    _process = null;
  }

  Future<void> _teardown() async {
    final proc = _process;
    _process = null;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    for (final pending in _queue) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete({
          'err': 'tools bridge restarted before this call completed',
          't': pending.tool,
        });
      }
    }
    _queue.clear();
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
      try {
        await proc.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<void> dispose() => _teardown();
}
