import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thrown when the native tools bridge cannot be reached at all (HTTP
/// unreachable, or the binary not found server-side). Per-call tool
/// failures are returned as result maps instead, so the LLM sees them and
/// can react -- this exception is for setup/connectivity errors only.
class NativeToolsException implements Exception {
  final String message;
  NativeToolsException(this.message);
  @override
  String toString() => message;
}

/// Native C++ tools bridge -- proxied over the Python bridge's HTTP server.
///
/// Nexon is a separate installed Android app (applicationId
/// com.termuxforge.app), sandboxed away from Termux's private storage, so
/// it can never see or execute the `tools` binary directly -- regardless of
/// whether the binary is present and healthy. The Python bridge runs
/// inside Termux and CAN see it, so it spawns `tools` as a subprocess
/// (NativeToolsManager) and this class talks to that subprocess over the
/// same loopback HTTP port (8390) already trusted for /mcp, via
/// GET /native/health and POST /native/call.
///
/// Mirrors `_checkBridgeAlive()`'s HttpClient pattern in
/// media_and_model_sheet.dart, including its `customUrl` override.
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

  static String _baseUrl(String? customUrl) {
    if (customUrl != null && customUrl.isNotEmpty) {
      // customUrl mirrors the /mcp override -- strip a trailing /mcp so
      // /native/* routes hang off the same host:port.
      return customUrl.endsWith('/mcp')
          ? customUrl.substring(0, customUrl.length - 4)
          : customUrl;
    }
    return 'http://127.0.0.1:8390';
  }

  /// GET /native/health -- is the tools binary found / running server-side?
  /// Never throws; connectivity failures come back as
  /// {'binary_found': false, 'running': false, 'reason': 'bridge_unreachable'}
  /// so callers can treat the map uniformly.
  static Future<Map<String, dynamic>> health({String? customUrl}) async {
    final endpoint = '${_baseUrl(customUrl)}/native/health';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 3));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
      return {
        'binary_found': false,
        'running': false,
        'reason': 'bridge_error',
      };
    } catch (_) {
      return {
        'binary_found': false,
        'running': false,
        'reason': 'bridge_unreachable',
      };
    } finally {
      client.close(force: true);
    }
  }

  /// POST /native/call -- proxy one tool call to the tools binary over the
  /// Python bridge. Honors the tool's own `to` (timeout seconds) argument.
  /// Throws [NativeToolsException] for connectivity/setup failures (bridge
  /// unreachable, binary not found server-side, HTTP 503) -- same role the
  /// old "binary not found"/"failed to start" exceptions played. A call
  /// that reaches the binary but times out returns an {'err': ...} map
  /// instead, matching the old per-call timeout behavior so callers don't
  /// need to change their catch logic.
  static Future<Map<String, dynamic>> call({
    required String workspace,
    required String tool,
    Map<String, dynamic> args = const {},
    String? customUrl,
  }) async {
    final int toSec = args['to'] is int
        ? args['to'] as int
        : int.tryParse(args['to']?.toString() ?? '') ?? 120;
    final Duration effective = Duration(seconds: toSec.clamp(5, 600) + 10);
    final endpoint = '${_baseUrl(customUrl)}/native/call';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'tool': tool,
        'workspace': workspace,
        'args': args,
      }));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(effective);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 503) {
        final decoded = jsonDecode(body);
        final msg = decoded is Map && decoded['err'] != null
            ? decoded['err'].toString()
            : 'native tools bridge unavailable';
        throw NativeToolsException(msg);
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        throw NativeToolsException(
            'malformed response from native tools bridge');
      }
      throw NativeToolsException(
          'native tools bridge returned HTTP ${response.statusCode}');
    } on TimeoutException {
      return {
        'err': 'native tools call timed out after ${effective.inSeconds}s',
        't': tool,
      };
    } on NativeToolsException {
      rethrow;
    } catch (e) {
      throw NativeToolsException('failed to reach native tools bridge: $e');
    } finally {
      client.close(force: true);
    }
  }
}
