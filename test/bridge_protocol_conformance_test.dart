// ============================================================================
// TermuxForge — Cross-Bridge Protocol Conformance Tests
// Verifies that the Flutter, Python, and C++ bridge layers agree on:
//   - JSON-RPC 2.0 error codes
//   - C++ bridge tool names and aliases
//   - Python bridge RPC method names
//   - Request/response serialization shapes
// ============================================================================

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexon/services/termux_bridge/bridge_protocol.dart';
import 'package:nexon/services/termux_bridge/bridge_schema.dart';

void main() {
  group('BridgeErrorCodes — JSON-RPC 2.0 standard codes', () {
    test('parse error is -32700', () {
      expect(BridgeErrorCodes.parseError, -32700);
    });
    test('invalid request is -32600', () {
      expect(BridgeErrorCodes.invalidRequest, -32600);
    });
    test('method not found is -32601', () {
      expect(BridgeErrorCodes.methodNotFound, -32601);
    });
    test('invalid params is -32602', () {
      expect(BridgeErrorCodes.invalidParams, -32602);
    });
    test('internal error is -32603', () {
      expect(BridgeErrorCodes.internalError, -32603);
    });
  });

  group('BridgeErrorCodes — custom TermuxForge codes (synced with Python)', () {
    test('commandBlocked is -32001 (Python: COMMAND_BLOCKED)', () {
      expect(BridgeErrorCodes.commandBlocked, -32001);
    });
    test('commandTimeout is -32002 (Python: COMMAND_TIMEOUT)', () {
      expect(BridgeErrorCodes.commandTimeout, -32002);
    });
    test('commandFailed is -32003 (Python: COMMAND_FAILED)', () {
      expect(BridgeErrorCodes.commandFailed, -32003);
    });
    test('fileNotFound is -32004 (Python: FILE_NOT_FOUND)', () {
      expect(BridgeErrorCodes.fileNotFound, -32004);
    });
    test('permissionDenied is -32005 (Python: PERMISSION_DENIED)', () {
      expect(BridgeErrorCodes.permissionDenied, -32005);
    });
    test('toolNotFound is -32006 (Python: TOOL_NOT_FOUND)', () {
      expect(BridgeErrorCodes.toolNotFound, -32006);
    });
    test('notConnected is -32000 (Flutter-local, not sent by Python)', () {
      expect(BridgeErrorCodes.notConnected, -32000);
    });
  });

  group('BridgeRequest — JSON-RPC 2.0 serialization', () {
    test('toJson includes jsonrpc, id, method, params', () {
      final req = BridgeRequest(
        id: 'req-1',
        method: 'execute_command',
        params: {'command': 'ls -la'},
      );
      final json = req.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 'req-1');
      expect(json['method'], 'execute_command');
      expect(json['params'], {'command': 'ls -la'});
    });

    test('toJson includes timeout when provided', () {
      final req = BridgeRequest(
        id: 'req-2',
        method: 'ping',
        timeout: 5,
      );
      expect(req.toJson()['timeout'], 5);
    });

    test('toJson omits timeout when null', () {
      final req = BridgeRequest(id: 'req-3', method: 'ping');
      expect(req.toJson().containsKey('timeout'), isFalse);
    });

    test('toJsonString produces valid JSON', () {
      final req = BridgeRequest(
        id: 'req-4',
        method: 'git_status',
        params: {'cwd': '/home'},
      );
      final decoded = jsonDecode(req.toJsonString());
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['jsonrpc'], '2.0');
    });

    test('fromJson round-trips correctly', () {
      final original = BridgeRequest(
        id: 'req-5',
        method: 'execute_shell',
        params: {'command': 'echo hi'},
        timeout: 10,
      );
      final restored = BridgeRequest.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.method, original.method);
      expect(restored.params, original.params);
      expect(restored.timeout, original.timeout);
    });
  });

  group('BridgeResponse — parsing robustness', () {
    test('parses top-level exitCode/stdout/stderr', () {
      final resp = BridgeResponse.fromJson({
        'jsonrpc': '2.0',
        'id': 'r1',
        'result': {'data': 'ok'},
        'exitCode': 0,
        'stdout': 'hello',
        'stderr': '',
        'durationMs': 150,
      });
      expect(resp.id, 'r1');
      expect(resp.isSuccess, isTrue);
      expect(resp.exitCode, 0);
      expect(resp.stdout, 'hello');
      expect(resp.stderr, '');
      expect(resp.duration.inMilliseconds, 150);
    });

    test('parses nested result with exitCode/stdout inside result', () {
      final resp = BridgeResponse.fromJson({
        'jsonrpc': '2.0',
        'id': 'r2',
        'result': {
          'exitCode': 1,
          'stdout': 'output',
          'stderr': 'error msg',
          'duration': 0.5,
        },
      });
      expect(resp.exitCode, 1);
      expect(resp.stdout, 'output');
      expect(resp.stderr, 'error msg');
      expect(resp.duration.inMilliseconds, 500);
    });

    test('parses error response', () {
      final resp = BridgeResponse.fromJson({
        'jsonrpc': '2.0',
        'id': 'r3',
        'error': {
          'code': -32002,
          'message': 'Command timed out',
        },
      });
      expect(resp.isError, isTrue);
      expect(resp.error!.code, -32002);
      expect(resp.error!.message, 'Command timed out');
    });

    test('parses error with snake_case exit_code fallback', () {
      final resp = BridgeResponse.fromJson({
        'jsonrpc': '2.0',
        'id': 'r4',
        'result': {
          'exit_code': 42,
          'rawStdout': 'raw output',
        },
      });
      expect(resp.exitCode, 42);
      expect(resp.stdout, 'raw output');
    });

    test('handles missing id gracefully', () {
      final resp = BridgeResponse.fromJson({
        'jsonrpc': '2.0',
        'result': {'ok': true},
      });
      expect(resp.id, '');
      expect(resp.isSuccess, isTrue);
    });

    test('handles null result', () {
      final resp = BridgeResponse.fromJson({
        'jsonrpc': '2.0',
        'id': 'r5',
        'result': null,
      });
      expect(resp.isSuccess, isTrue);
      expect(resp.result, isNull);
    });

    test('default error message matches known code', () {
      final error = BridgeError.fromJson({'code': -32005});
      expect(error.message, 'Permission denied');
    });
  });

  group('CppBridgeTools — tool name registry', () {
    test('shortNames contains all expected tools', () {
      expect(CppBridgeTools.shortNames.contains('sh'), isTrue);
      expect(CppBridgeTools.shortNames.contains('read'), isTrue);
      expect(CppBridgeTools.shortNames.contains('patch'), isTrue);
      expect(CppBridgeTools.shortNames.contains('search'), isTrue);
      expect(CppBridgeTools.shortNames.contains('git'), isTrue);
      expect(CppBridgeTools.shortNames.contains('edit'), isTrue);
      expect(CppBridgeTools.shortNames.contains('undo'), isTrue);
      expect(CppBridgeTools.shortNames.contains('create_file'), isTrue);
      expect(CppBridgeTools.shortNames.contains('version'), isTrue);
      expect(CppBridgeTools.shortNames.contains('py'), isTrue);
    });

    test('longNames maps short to long correctly', () {
      expect(CppBridgeTools.longNames['sh'], 'shell_command_tool');
      expect(CppBridgeTools.longNames['read'], 'multi_read_tool');
      expect(CppBridgeTools.longNames['patch'], 'multi_patch_tool');
      expect(CppBridgeTools.longNames['search'], 'multi_search_tool');
    });

    test('handles accepts both short and long names', () {
      expect(CppBridgeTools.handles('sh'), isTrue);
      expect(CppBridgeTools.handles('shell_command_tool'), isTrue);
      expect(CppBridgeTools.handles('read'), isTrue);
      expect(CppBridgeTools.handles('multi_read_tool'), isTrue);
      expect(CppBridgeTools.handles('nonexistent'), isFalse);
    });

    test('shortNames count matches expected tool count', () {
      expect(CppBridgeTools.shortNames.length, 20);
    });
  });

  group('PythonBridgeMethods — RPC method registry', () {
    test('command methods include execute_command', () {
      expect(PythonBridgeMethods.commandMethods.contains('execute_command'), isTrue);
      expect(PythonBridgeMethods.commandMethods.contains('execute_shell'), isTrue);
      expect(PythonBridgeMethods.commandMethods.contains('run_command'), isTrue);
    });

    test('git methods include git_status', () {
      expect(PythonBridgeMethods.gitMethods.contains('git_status'), isTrue);
      expect(PythonBridgeMethods.gitMethods.contains('git_commit'), isTrue);
    });

    test('handles returns true for registered methods', () {
      expect(PythonBridgeMethods.handles('execute_command'), isTrue);
      expect(PythonBridgeMethods.handles('git_status'), isTrue);
      expect(PythonBridgeMethods.handles('ping'), isTrue);
      expect(PythonBridgeMethods.handles('nonexistent_method'), isFalse);
    });

    test('all contains every method category', () {
      expect(PythonBridgeMethods.all.contains('ping'), isTrue);
      expect(PythonBridgeMethods.all.contains('web_search'), isTrue);
      expect(PythonBridgeMethods.all.contains('run_background'), isTrue);
      expect(PythonBridgeMethods.all.contains('checkpoint_create'), isTrue);
    });
  });

  group('BridgeEndpoints — transport configuration', () {
    test('default host is localhost', () {
      expect(BridgeEndpoints.defaultHost, '127.0.0.1');
    });
    test('WebSocket port is 8765', () {
      expect(BridgeEndpoints.webSocketPort, 8765);
    });
    test('HTTP port is 8390', () {
      expect(BridgeEndpoints.httpPort, 8390);
    });
    test('HTTP path is /mcp', () {
      expect(BridgeEndpoints.httpPath, '/mcp');
    });
    test('webSocketUrl constructs correct URL', () {
      expect(BridgeEndpoints.webSocketUrl(), 'ws://127.0.0.1:8765');
    });
    test('httpUrl constructs correct URL', () {
      expect(BridgeEndpoints.httpUrl(), 'http://127.0.0.1:8390/mcp');
    });
  });

  group('CppBridgeProtocol — JSON key constants', () {
    test('tool key is "t"', () {
      expect(CppBridgeProtocol.toolKey, 't');
    });
    test('args key is "a"', () {
      expect(CppBridgeProtocol.argsKey, 'a');
    });
    test('error key is "err"', () {
      expect(CppBridgeProtocol.errorKey, 'err');
    });
    test('output key is "out"', () {
      expect(CppBridgeProtocol.outputKey, 'out');
    });
  });
}
