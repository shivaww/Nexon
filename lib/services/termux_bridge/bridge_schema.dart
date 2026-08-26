// ============================================================================
// TermuxForge — Cross-Bridge Schema Constants
// Single source of truth for tool names, method names, and JSON protocol
// shapes across the three execution layers:
//   1. Flutter app (Dart)
//   2. Python bridge (JSON-RPC 2.0 over WebSocket :8765 / HTTP :8390)
//   3. C++ native tools bridge (stdin/stdout JSON line protocol)
//
// When adding or renaming a tool, update this file first, then propagate
// to the corresponding bridge implementation.
// ============================================================================

/// Canonical set of tool names handled by the C++ native tools bridge.
///
/// The C++ binary accepts both short aliases and long `*_tool` names.
/// The short aliases are what the system prompt emits and what
/// [NativeToolsService.cppTools] checks against.
class CppBridgeTools {
  CppBridgeTools._();

  static const Set<String> shortNames = {
    'sh', 'search', 'read', 'patch', 'edit', 'git', 'list', 'find',
    'outline', 'recent', 'undo', 'create_file', 'create_directory', 'mkdir',
    'cut', 'extract', 'fileops', 'diagnostics', 'version', 'py',
  };

  static const Map<String, String> longNames = {
    'sh': 'shell_command_tool',
    'search': 'multi_search_tool',
    'read': 'multi_read_tool',
    'patch': 'multi_patch_tool',
    'edit': 'file_edit_tool',
    'git': 'git_tool',
    'list': 'list_tool',
    'find': 'find_tool',
    'outline': 'outline_tool',
    'recent': 'recent_tool',
    'undo': 'undo_tool',
    'create_file': 'create_file_tool',
    'create_directory': 'create_directory_tool',
    'cut': 'cut_tool',
    'extract': 'extract_tool',
    'fileops': 'fileops_tool',
    'diagnostics': 'diagnostics_tool',
    'version': 'version',
    'py': 'py_tool',
  };

  static bool handles(String name) =>
      shortNames.contains(name) || longNames.values.contains(name);
}

/// Canonical set of RPC method names handled by the Python bridge.
///
/// These are registered in `termux_forge_bridge.py::_register_methods()`.
class PythonBridgeMethods {
  PythonBridgeMethods._();

  static const Set<String> commandMethods = {
    'execute_command', 'execute_shell', 'run_command', 'kill_command',
  };

  static const Set<String> gitMethods = {
    'git_status', 'git_diff', 'git_commit', 'git_push', 'git_pull',
  };

  static const Set<String> flutterMethods = {
    'flutter_run', 'flutter_test', 'flutter_build',
  };

  static const Set<String> dartMethods = {
    'dart_analyze', 'dart_diagnostics', 'dart_format',
  };

  static const Set<String> workspaceMethods = {
    'workspace_validate', 'workspace_list', 'workspace_search',
    'workspace_ingest', 'workspace_read_page', 'workspace_get_outline',
    'workspace_check_deps', 'workspace_cross_compare',
  };

  static const Set<String> mcpMethods = {
    'mcp_server_manage', 'mcp_tool_discover', 'mcp_transport_handle',
    'mcp_request', 'mcp_call',
  };

  static const Set<String> deepResearchMethods = {
    'deep_research.export_temp', 'deep_research.export_for_writer',
    'deep_research.reset', 'deep_research.update_phase',
    'deep_research.save_checkpoint', 'deep_research.load_checkpoint',
    'deep_research.clear_checkpoint', 'web_search', 'read_url',
  };

  static const Set<String> serviceMethods = {
    'run_background', 'list_services', 'service_status',
    'service_logs', 'stop_service', 'wait_for_background',
    'background_time_limit',
  };

  static const Set<String> envMethods = {
    'env_status', 'system_ram_headroom', 'project_health',
    'ping', 'version_check', 'tool_stats', 'tool_help',
    'install_package', 'check_tool', 'discover_tools',
    'get_command_history',
  };

  static const Set<String> checkpointMethods = {
    'checkpoint_create', 'checkpoint_rollback',
  };

  static const Set<String> githubMethods = {
    'github_workflow_trigger', 'github_build_status',
    'github_download_artifact',
  };

  static const Set<String> mediaMethods = {
    'media_discover',
  };

  static const Set<String> workflowMethods = {
    'workflow_execute',
  };

  static Set<String> get all => {
    ...commandMethods,
    ...gitMethods,
    ...flutterMethods,
    ...dartMethods,
    ...workspaceMethods,
    ...mcpMethods,
    ...deepResearchMethods,
    ...serviceMethods,
    ...envMethods,
    ...checkpointMethods,
    ...githubMethods,
    ...mediaMethods,
    ...workflowMethods,
  };

  static bool handles(String method) => all.contains(method);
}

/// JSON protocol shape constants for the C++ bridge (stdin/stdout pipe).
///
/// Request line:  `{"t":"<toolName>","a":{...args}}`
/// Response line: `{"t":"<toolName>","err":"...","out":"...",...}`
class CppBridgeProtocol {
  CppBridgeProtocol._();

  static const String toolKey = 't';
  static const String argsKey = 'a';
  static const String errorKey = 'err';
  static const String outputKey = 'out';
  static const String returnCodeKey = 'rc';
  static const String resultKey = 'r';
  static const String fileKey = 'f';
  static const String statusKey = 'st';
}

/// Transport endpoints for the Python bridge.
class BridgeEndpoints {
  BridgeEndpoints._();

  static const String defaultHost = '127.0.0.1';
  static const int webSocketPort = 8765;
  static const int httpPort = 8390;
  static const String httpPath = '/mcp';

  static String webSocketUrl({String host = defaultHost}) =>
      'ws://$host:$webSocketPort';
  static String httpUrl({String host = defaultHost}) =>
      'http://$host:$httpPort$httpPath';
}
