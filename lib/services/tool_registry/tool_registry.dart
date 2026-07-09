// ============================================================================
// TermuxForge — Tool Registry
// Unified abstraction layer for all 48+ tools available in the system.
// Handles registration, permission gating, invocation, and discovery.
// ============================================================================

import 'dart:async';

import 'package:nexon/services/tool_registry/tool_registry_types.dart';
import 'package:nexon/services/event_bus/event_bus.dart';
import 'package:nexon/services/event_bus/event_types.dart';

/// Central registry for all tools available in TermuxForge.
///
/// Every tool — whether built-in (file ops, git, shell), MCP-sourced, or
/// user-contributed — is registered here with a [ToolDefinition].
///
/// The registry enforces permission gating before any tool execution:
/// tools with a permission level above the caller's clearance are blocked.
///
/// ## Example
///
/// ```dart
/// final registry = ToolRegistry.instance;
///
/// final result = await registry.invokeTool(
///   'read_file_rich',
///   {'path': '/home/project/lib/main.dart'},
///   callerPermissionLevel: 1,
/// );
/// print(result.data); // rich file block
/// ```
class ToolRegistry {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  ToolRegistry._internal() {
    _registerBuiltInTools();
  }

  /// The global [ToolRegistry] instance.
  static final ToolRegistry instance = ToolRegistry._internal();

  /// Factory constructor that returns the singleton [instance].
  factory ToolRegistry() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// All registered tools keyed by ID.
  final Map<String, ToolDefinition> _tools = {};

  /// Reference to the event bus.
  final EventBus _eventBus = EventBus.instance;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Registers a [tool] definition.
  ///
  /// If a tool with the same ID already exists, it is overwritten.
  void registerTool(ToolDefinition tool) {
    _tools[tool.id] = tool;
  }

  /// Unregisters the tool with the given [toolId].
  ///
  /// Returns `true` if the tool existed.
  bool unregisterTool(String toolId) => _tools.remove(toolId) != null;

  // ---------------------------------------------------------------------------
  // Invocation
  // ---------------------------------------------------------------------------

  /// Invokes the tool identified by [toolId] with the given [params].
  ///
  /// [callerPermissionLevel] is the maximum permission level the caller is
  /// cleared for. If the tool's level exceeds it, a failed [ToolResult] is
  /// returned without executing the handler.
  ///
  /// Publishes [ToolInvoked] and [ToolResultReceived] events.
  Future<ToolResult> invokeTool(
    String toolId,
    Map<String, dynamic> params, {
    int callerPermissionLevel = 0,
    String? invokingAgentId,
  }) async {
    final tool = _tools[toolId];
    if (tool == null) {
      return ToolResult.fail(
        toolId: toolId,
        error: 'Tool "$toolId" not found in registry',
      );
    }

    // Permission gate.
    if (!isToolAllowed(toolId, callerPermissionLevel)) {
      return ToolResult.fail(
        toolId: toolId,
        error:
            'Permission denied: tool "$toolId" requires level '
            '${tool.permissionLevel}, caller has $callerPermissionLevel',
      );
    }

    _eventBus.publish(
      ToolInvoked(
        toolId: toolId,
        parameters: params,
        invokingAgentId: invokingAgentId,
        source: 'ToolRegistry',
      ),
    );

    final stopwatch = Stopwatch()..start();
    try {
      final result = await tool.handler(params);
      stopwatch.stop();

      _eventBus.publish(
        ToolResultReceived(
          toolId: toolId,
          success: result.success,
          duration: stopwatch.elapsed,
          source: 'ToolRegistry',
        ),
      );

      return ToolResult(
        success: result.success,
        data: result.data,
        error: result.error,
        duration: stopwatch.elapsed,
        toolId: toolId,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();

      _eventBus.publish(
        ToolResultReceived(
          toolId: toolId,
          success: false,
          duration: stopwatch.elapsed,
          source: 'ToolRegistry',
        ),
      );

      return ToolResult.fail(
        toolId: toolId,
        error: 'Tool execution error: $e\n$stackTrace',
        duration: stopwatch.elapsed,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the [ToolDefinition] for [toolId], or `null`.
  ToolDefinition? getTool(String toolId) => _tools[toolId];

  /// Returns all registered tools.
  List<ToolDefinition> listTools() => List.unmodifiable(_tools.values.toList());

  /// Returns tools belonging to the given [category].
  List<ToolDefinition> getToolsByCategory(ToolCategory category) {
    return _tools.values.where((t) => t.category == category).toList();
  }

  /// Whether the tool [toolId] is allowed for a caller with the given
  /// [callerLevel].
  bool isToolAllowed(String toolId, int callerLevel) {
    final tool = _tools[toolId];
    if (tool == null) return false;
    return callerLevel >= tool.permissionLevel;
  }

  /// Returns the permission level of the tool [toolId], or `-1` if not found.
  int getToolPermissionLevel(String toolId) {
    return _tools[toolId]?.permissionLevel ?? -1;
  }

  /// Total number of registered tools.
  int get toolCount => _tools.length;

  /// Returns all tool definitions as JSON-serializable maps.
  ///
  /// Useful for exposing the tool schema to LLMs.
  List<Map<String, dynamic>> toJsonSchema() {
    return _tools.values.map((t) => t.toJson()).toList();
  }

  // ---------------------------------------------------------------------------
  // Built-in Tool Registration
  // ---------------------------------------------------------------------------

  /// Registers all 48 built-in tools with placeholder handlers.
  ///
  /// Each handler is a stub that returns a TODO result. The actual
  /// implementations are wired in by the respective service modules
  /// during app initialization.
  void _registerBuiltInTools() {
    // -- Rich IDE file tools (category: file) -------------------------------
    _reg(
      'read_file_rich',
      'Read File Rich',
      'Read a bounded text range with line numbers, metadata, binary guards, and navigation hints.',
      ToolCategory.file,
      1,
      [
        const ToolParameter(name: 'path', description: 'File path'),
        const ToolParameter(
          name: 'start_line',
          description: 'First line to read',
          type: 'int',
          required: false,
          defaultValue: '1',
        ),
        const ToolParameter(
          name: 'end_line',
          description: 'Last line to read',
          type: 'int',
          required: false,
        ),
        const ToolParameter(
          name: 'max_lines',
          description: 'Maximum lines to return',
          type: 'int',
          required: false,
          defaultValue: '120',
        ),
      ],
    );
    _reg(
      'multi_read_rich',
      'Multi Read Rich',
      'Read multiple files or multiple line ranges in a single bridge call.',
      ToolCategory.file,
      1,
      [
        const ToolParameter(
          name: 'reads',
          description: 'List of {path,start_line,end_line}',
          type: 'List<Map>',
        ),
        const ToolParameter(
          name: 'max_lines_per_file',
          description: 'Max lines per file',
          type: 'int',
          required: false,
          defaultValue: '120',
        ),
      ],
    );
    _reg(
      'write_file_rich',
      'Write File Rich',
      'Atomically create or overwrite a text file with checkpoint and conflict guards.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Target file path'),
        const ToolParameter(name: 'content', description: 'Full file content'),
        const ToolParameter(
          name: 'expected_sha256',
          description: 'Optional pre-edit SHA-256 guard',
          required: false,
        ),
        const ToolParameter(
          name: 'expected_mtime',
          description: 'Optional pre-edit mtime guard',
          type: 'double',
          required: false,
        ),
      ],
    );
    _reg(
      'patch_file',
      'Patch File',
      'Apply exact search/replace patches atomically and return a unified diff.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Target file path'),
        const ToolParameter(
          name: 'patches',
          description: 'List of {search,replace,count,label}',
          type: 'List<Map>',
        ),
        const ToolParameter(
          name: 'expected_sha256',
          description: 'Optional pre-edit SHA-256 guard',
          required: false,
        ),
      ],
    );
    _reg(
      'replace_lines',
      'Replace Lines',
      'Replace a specific 1-indexed line range and return a diff.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Target file path'),
        const ToolParameter(
          name: 'start_line',
          description: 'First line to replace',
          type: 'int',
        ),
        const ToolParameter(
          name: 'end_line',
          description: 'Last line to replace',
          type: 'int',
        ),
        const ToolParameter(
          name: 'new_content',
          description: 'Replacement text',
        ),
      ],
    );
    _reg(
      'insert_lines',
      'Insert Lines',
      'Insert text after a specific 1-indexed line number.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Target file path'),
        const ToolParameter(
          name: 'after_line',
          description: 'Insert after this line; 0 means file start',
          type: 'int',
        ),
        const ToolParameter(name: 'content', description: 'Text to insert'),
      ],
    );
    _reg(
      'delete_lines',
      'Delete Lines',
      'Delete a specific 1-indexed line range.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Target file path'),
        const ToolParameter(
          name: 'start_line',
          description: 'First line to delete',
          type: 'int',
        ),
        const ToolParameter(
          name: 'end_line',
          description: 'Last line to delete',
          type: 'int',
        ),
      ],
    );
    _reg(
      'append_file',
      'Append File',
      'Append text to a file, optionally creating it.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Target file path'),
        const ToolParameter(name: 'content', description: 'Text to append'),
        const ToolParameter(
          name: 'create_if_missing',
          description: 'Create missing file',
          type: 'bool',
          required: false,
          defaultValue: 'true',
        ),
      ],
    );
    _reg(
      'search_rich',
      'Search Rich',
      'Search code using ripgrep/grep with context and extension filters.',
      ToolCategory.file,
      1,
      [
        const ToolParameter(name: 'query', description: 'Text or regex query'),
        const ToolParameter(
          name: 'path',
          description: 'Directory or file to search',
          required: false,
        ),
        const ToolParameter(
          name: 'extensions',
          description: 'Extension filters',
          type: 'List<String>',
          required: false,
        ),
        const ToolParameter(
          name: 'case_sensitive',
          description: 'Use case-sensitive search',
          type: 'bool',
          required: false,
          defaultValue: 'false',
        ),
      ],
    );
    _reg(
      'file_outline',
      'File Outline',
      'Extract classes, functions, methods, and line numbers from a source file.',
      ToolCategory.file,
      1,
      [const ToolParameter(name: 'path', description: 'Source file path')],
    );
    _reg(
      'symbol_references',
      'Symbol References',
      'Find likely references to a symbol across source files.',
      ToolCategory.file,
      1,
      [
        const ToolParameter(name: 'symbol', description: 'Symbol to find'),
        const ToolParameter(
          name: 'path',
          description: 'Search root',
          required: false,
        ),
      ],
    );
    _reg(
      'tree',
      'Directory Tree',
      'Return an annotated project tree with sizes and smart skip rules.',
      ToolCategory.file,
      0,
      [
        const ToolParameter(
          name: 'path',
          description: 'Directory path',
          required: false,
        ),
        const ToolParameter(
          name: 'max_depth',
          description: 'Maximum recursion depth',
          type: 'int',
          required: false,
          defaultValue: '4',
        ),
      ],
    );
    _reg(
      'diff_files',
      'Diff Files',
      'Compute a unified diff between two files.',
      ToolCategory.file,
      1,
      [
        const ToolParameter(name: 'path_a', description: 'First file path'),
        const ToolParameter(name: 'path_b', description: 'Second file path'),
      ],
    );
    _reg(
      'delete_path',
      'Delete Path',
      'Delete a file or directory with protected-path and checkpoint guards.',
      ToolCategory.file,
      7,
      [
        const ToolParameter(name: 'path', description: 'Target path'),
        const ToolParameter(
          name: 'recursive',
          description: 'Allow deleting non-empty directories',
          type: 'bool',
          required: false,
          defaultValue: 'false',
        ),
      ],
    );
    _reg(
      'move_path',
      'Move Path',
      'Move or rename a file/directory with checkpoint guards.',
      ToolCategory.file,
      3,
      [
        const ToolParameter(name: 'src', description: 'Source path'),
        const ToolParameter(name: 'dest', description: 'Destination path'),
        const ToolParameter(
          name: 'overwrite',
          description: 'Overwrite destination',
          type: 'bool',
          required: false,
          defaultValue: 'false',
        ),
      ],
    );
    _reg(
      'copy_path',
      'Copy Path',
      'Copy a file or directory; directory copies are recursive.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'src', description: 'Source path'),
        const ToolParameter(name: 'dest', description: 'Destination path'),
        const ToolParameter(
          name: 'overwrite',
          description: 'Overwrite destination',
          type: 'bool',
          required: false,
          defaultValue: 'false',
        ),
      ],
    );
    _reg(
      'mkdir_path',
      'Create Directory',
      'Create a directory, including parents by default.',
      ToolCategory.file,
      2,
      [
        const ToolParameter(name: 'path', description: 'Directory path'),
        const ToolParameter(
          name: 'parents',
          description: 'Create parents',
          type: 'bool',
          required: false,
          defaultValue: 'true',
        ),
      ],
    );
    _reg(
      'stat_path',
      'Stat Path',
      'Return detailed file/directory metadata including hash-relevant timestamps.',
      ToolCategory.file,
      0,
      [const ToolParameter(name: 'path', description: 'Target path')],
    );
    _reg(
      'chmod_path',
      'Chmod Path',
      'Change permissions for a file or directory.',
      ToolCategory.file,
      5,
      [
        const ToolParameter(name: 'path', description: 'Target path'),
        const ToolParameter(
          name: 'mode',
          description: 'Octal mode, e.g. 755 or 644',
        ),
        const ToolParameter(
          name: 'recursive',
          description: 'Apply recursively',
          type: 'bool',
          required: false,
          defaultValue: 'false',
        ),
      ],
    );

    // -- Git tools (category: git) ------------------------------------------
    _reg(
      'git_status',
      'Git Status',
      'Show the working tree status.',
      ToolCategory.git,
      0,
      [],
    );
    _reg(
      'git_diff',
      'Git Diff',
      'Show changes between commits, working tree, etc.',
      ToolCategory.git,
      0,
      [
        const ToolParameter(
          name: 'ref',
          description: 'Git ref to diff against',
          required: false,
        ),
      ],
    );
    _reg(
      'git_commit',
      'Git Commit',
      'Create a new commit with staged changes.',
      ToolCategory.git,
      4,
      [const ToolParameter(name: 'message', description: 'Commit message')],
    );

    // -- Flutter tools (category: flutter) ----------------------------------
    _reg(
      'flutter_run',
      'Flutter Run',
      'Run the Flutter application.',
      ToolCategory.flutter,
      4,
      [
        const ToolParameter(
          name: 'device',
          description: 'Target device ID',
          required: false,
        ),
      ],
    );
    _reg(
      'flutter_test',
      'Flutter Test',
      'Run Flutter tests.',
      ToolCategory.flutter,
      4,
      [
        const ToolParameter(
          name: 'target',
          description: 'Test file or directory',
          required: false,
        ),
      ],
    );
    _reg(
      'flutter_build',
      'Flutter Build',
      'Build the Flutter application.',
      ToolCategory.flutter,
      4,
      [
        const ToolParameter(
          name: 'target',
          description: 'Build target: apk, aab, ios, web',
        ),
      ],
    );

    // -- Dart tools (category: dart) ----------------------------------------
    _reg(
      'dart_analyze',
      'Dart Analyze',
      'Compatibility alias for dart_diagnostics.',
      ToolCategory.dart,
      3,
      [
        const ToolParameter(
          name: 'path',
          description: 'Path to analyze',
          required: false,
        ),
      ],
    );
    _reg(
      'dart_diagnostics',
      'Dart Diagnostics',
      'Run Dart analyzer and return structured diagnostics where supported.',
      ToolCategory.dart,
      3,
      [
        const ToolParameter(
          name: 'path',
          description: 'File or directory to analyze',
          required: false,
        ),
        const ToolParameter(
          name: 'cwd',
          description: 'Workspace directory',
          required: false,
        ),
      ],
    );
    _reg(
      'dart_format',
      'Dart Format',
      'Format a Dart file or directory using dart format.',
      ToolCategory.dart,
      3,
      [
        const ToolParameter(
          name: 'path',
          description: 'File or directory to format',
          required: false,
        ),
        const ToolParameter(
          name: 'output',
          description: 'write, none, show, or json',
          required: false,
          defaultValue: 'write',
        ),
      ],
    );
    _reg(
      'dart_test',
      'Dart Test',
      'Run Dart unit tests.',
      ToolCategory.dart,
      4,
      [
        const ToolParameter(
          name: 'path',
          description: 'Test path',
          required: false,
        ),
      ],
    );

    // -- Shell tools (category: shell) --------------------------------------
    _reg(
      'run_command',
      'Run Command',
      'Execute a shell command with rich IDE output.',
      ToolCategory.shell,
      5,
      [
        const ToolParameter(
          name: 'command',
          description: 'The shell command to execute',
        ),
        const ToolParameter(
          name: 'cwd',
          description: 'Working directory',
          required: false,
        ),
        const ToolParameter(
          name: 'timeout',
          description: 'Timeout in seconds',
          type: 'int',
          required: false,
          defaultValue: '30',
        ),
      ],
    );
    _reg(
      'shell_rich',
      'Shell Rich',
      'Execute a shell command through the rich output engine.',
      ToolCategory.shell,
      5,
      [
        const ToolParameter(
          name: 'command',
          description: 'The shell command to execute',
        ),
        const ToolParameter(
          name: 'cwd',
          description: 'Working directory',
          required: false,
        ),
        const ToolParameter(
          name: 'timeout',
          description: 'Timeout in seconds',
          type: 'int',
          required: false,
          defaultValue: '30',
        ),
      ],
    );
    _reg(
      'run_background',
      'Run Background Service',
      'Start a long-running server/dev process and return PID, logs, and URLs.',
      ToolCategory.shell,
      5,
      [
        const ToolParameter(
          name: 'command',
          description: 'Server command to run',
        ),
        const ToolParameter(
          name: 'name',
          description: 'Service name',
          required: false,
        ),
        const ToolParameter(
          name: 'cwd',
          description: 'Working directory',
          required: false,
        ),
      ],
    );
    _reg(
      'list_services',
      'List Services',
      'List tracked background services.',
      ToolCategory.shell,
      0,
      [],
    );
    _reg(
      'service_status',
      'Service Status',
      'Get status for a background service.',
      ToolCategory.shell,
      0,
      [
        const ToolParameter(
          name: 'id',
          description: 'Service PID, name, or command substring',
        ),
      ],
    );
    _reg(
      'service_logs',
      'Service Logs',
      'Tail logs for a background service.',
      ToolCategory.shell,
      0,
      [
        const ToolParameter(
          name: 'id',
          description: 'Service PID, name, or command substring',
        ),
        const ToolParameter(
          name: 'lines',
          description: 'Number of lines',
          type: 'int',
          required: false,
          defaultValue: '60',
        ),
      ],
    );
    _reg(
      'stop_service',
      'Stop Service',
      'Stop a tracked background service.',
      ToolCategory.shell,
      5,
      [
        const ToolParameter(
          name: 'id',
          description: 'Service PID, name, or command substring',
        ),
        const ToolParameter(
          name: 'force',
          description: 'Force kill',
          type: 'bool',
          required: false,
          defaultValue: 'false',
        ),
      ],
    );
    _reg(
      'install_package',
      'Install Package',
      'Install a system package via pkg.',
      ToolCategory.shell,
      5,
      [
        const ToolParameter(
          name: 'package',
          description: 'Package name to install',
        ),
      ],
    );
    _reg(
      'query_tool_status',
      'Query Tool Status',
      'Check if a CLI tool is installed and its version.',
      ToolCategory.shell,
      0,
      [const ToolParameter(name: 'tool', description: 'Tool name to check')],
    );
    _reg(
      'env_status',
      'Environment Status',
      'Return OS, PATH, runtimes, and installed CLI status.',
      ToolCategory.shell,
      0,
      [],
    );
    _reg(
      'project_health',
      'Project Health',
      'Summarize project files, git state, TODOs, and Flutter readiness.',
      ToolCategory.shell,
      1,
      [
        const ToolParameter(
          name: 'path',
          description: 'Project root',
          required: false,
        ),
      ],
    );

    // -- Memory tools (category: memory) ------------------------------------
    _reg(
      'fetch_memory',
      'Fetch Memory',
      'Retrieve a value from the project memory store.',
      ToolCategory.memory,
      0,
      [
        const ToolParameter(name: 'key', description: 'Memory key'),
        const ToolParameter(
          name: 'namespace',
          description: 'Memory namespace',
          required: false,
          defaultValue: 'project',
        ),
      ],
    );
    _reg(
      'save_memory',
      'Save Memory',
      'Store a value in the project memory.',
      ToolCategory.memory,
      1,
      [
        const ToolParameter(name: 'key', description: 'Memory key'),
        const ToolParameter(name: 'value', description: 'Value to store'),
        const ToolParameter(
          name: 'namespace',
          description: 'Memory namespace',
          required: false,
          defaultValue: 'project',
        ),
      ],
    );
    _reg(
      'semantic_search',
      'Semantic Search',
      'Search memory using semantic similarity.',
      ToolCategory.memory,
      1,
      [
        const ToolParameter(
          name: 'query',
          description: 'Natural language search query',
        ),
        const ToolParameter(
          name: 'limit',
          description: 'Max results',
          type: 'int',
          required: false,
          defaultValue: '10',
        ),
      ],
    );

    // -- Model tools (category: model) --------------------------------------
    _reg(
      'compare_models',
      'Compare Models',
      'Run a prompt against multiple models and compare.',
      ToolCategory.model,
      1,
      [
        const ToolParameter(name: 'prompt', description: 'The prompt to send'),
        const ToolParameter(
          name: 'modelIds',
          description: 'Model IDs to compare',
          type: 'List<String>',
        ),
      ],
    );
    _reg(
      'list_available_models',
      'List Models',
      'List all available LLM models across providers.',
      ToolCategory.model,
      0,
      [],
    );
    _reg(
      'select_model_for_mode',
      'Select Model',
      'Select the best model for a given task mode.',
      ToolCategory.model,
      1,
      [
        const ToolParameter(
          name: 'mode',
          description: 'Task mode: code, reason, fast, cheap',
        ),
      ],
    );

    // -- MCP tools (category: mcp) ------------------------------------------
    _reg(
      'list_mcp_servers',
      'List MCP Servers',
      'List all registered MCP servers.',
      ToolCategory.mcp,
      0,
      [],
    );
    _reg(
      'add_mcp_server',
      'Add MCP Server',
      'Register a new MCP server.',
      ToolCategory.mcp,
      3,
      [
        const ToolParameter(name: 'name', description: 'Server display name'),
        const ToolParameter(name: 'uri', description: 'Server URI'),
        const ToolParameter(
          name: 'transport',
          description: 'Transport: stdio, sse, http',
        ),
      ],
    );
    _reg(
      'remove_mcp_server',
      'Remove MCP Server',
      'Unregister an MCP server.',
      ToolCategory.mcp,
      3,
      [
        const ToolParameter(
          name: 'serverId',
          description: 'Server ID to remove',
        ),
      ],
    );
    _reg(
      'discover_mcp_tools',
      'Discover MCP Tools',
      'Discover tools offered by an MCP server.',
      ToolCategory.mcp,
      1,
      [
        const ToolParameter(
          name: 'serverId',
          description: 'Server ID to query',
        ),
      ],
    );
    _reg(
      'invoke_mcp_tool',
      'Invoke MCP Tool',
      'Invoke a tool on an MCP server.',
      ToolCategory.mcp,
      3,
      [
        const ToolParameter(name: 'serverId', description: 'Server ID'),
        const ToolParameter(name: 'toolName', description: 'Tool name'),
        const ToolParameter(
          name: 'params',
          description: 'Tool parameters',
          type: 'Map<String, dynamic>',
          required: false,
        ),
      ],
    );
    _reg(
      'sync_mcp_tool_registry',
      'Sync MCP Registry',
      'Sync all MCP tools into the local registry.',
      ToolCategory.mcp,
      2,
      [],
    );
    _reg(
      'search_web_via_mcp',
      'Web Search (MCP)',
      'Search the web via an MCP web-search server.',
      ToolCategory.mcp,
      2,
      [const ToolParameter(name: 'query', description: 'Search query')],
    );
    _reg(
      'research_query_via_mcp',
      'Research (MCP)',
      'Deep research via MCP research server.',
      ToolCategory.mcp,
      2,
      [const ToolParameter(name: 'query', description: 'Research query')],
    );
    _reg(
      'check_mcp_server_health',
      'MCP Health',
      'Check the health of an MCP server.',
      ToolCategory.mcp,
      0,
      [const ToolParameter(name: 'serverId', description: 'Server ID')],
    );

    // -- Workflow tools (category: workflow) --------------------------------
    _reg(
      'start_workflow',
      'Start Workflow',
      'Start a multi-step workflow.',
      ToolCategory.workflow,
      3,
      [
        const ToolParameter(name: 'workflowName', description: 'Workflow name'),
        const ToolParameter(
          name: 'steps',
          description: 'Ordered workflow steps',
          type: 'List<Map>',
        ),
      ],
    );
    _reg(
      'stop_workflow',
      'Stop Workflow',
      'Stop a running workflow.',
      ToolCategory.workflow,
      3,
      [const ToolParameter(name: 'workflowId', description: 'Workflow ID')],
    );
    _reg(
      'inspect_workflow',
      'Inspect Workflow',
      'Get the status of a running workflow.',
      ToolCategory.workflow,
      0,
      [const ToolParameter(name: 'workflowId', description: 'Workflow ID')],
    );

    // -- Checkpoint tools (category: checkpoint) ----------------------------
    _reg(
      'create_checkpoint',
      'Create Checkpoint',
      'Create a project snapshot checkpoint.',
      ToolCategory.checkpoint,
      2,
      [
        const ToolParameter(
          name: 'label',
          description: 'Human-readable checkpoint label',
        ),
      ],
    );
    _reg(
      'rollback_checkpoint',
      'Rollback Checkpoint',
      'Rollback to a previous checkpoint.',
      ToolCategory.checkpoint,
      6,
      [
        const ToolParameter(
          name: 'checkpointId',
          description: 'Checkpoint ID to rollback to',
        ),
      ],
    );

    // -- Cost tools (category: cost) ----------------------------------------
    _reg(
      'get_cost_dashboard',
      'Cost Dashboard',
      'Get current token/cost usage data.',
      ToolCategory.cost,
      0,
      [],
    );

    // -- Media tools (category: media) --------------------------------------
    _reg(
      'generate_image',
      'Generate Image',
      'Generate an image from a text prompt.',
      ToolCategory.media,
      3,
      [
        const ToolParameter(
          name: 'prompt',
          description: 'Image generation prompt',
        ),
        const ToolParameter(
          name: 'model',
          description: 'Model to use',
          required: false,
        ),
      ],
    );
    _reg(
      'generate_video',
      'Generate Video',
      'Generate a video from a text prompt.',
      ToolCategory.media,
      3,
      [
        const ToolParameter(
          name: 'prompt',
          description: 'Video generation prompt',
        ),
        const ToolParameter(
          name: 'model',
          description: 'Model to use',
          required: false,
        ),
      ],
    );
    _reg(
      'list_media_models',
      'List Media Models',
      'List available image/video generation models.',
      ToolCategory.media,
      0,
      [],
    );
    _reg(
      'select_media_model',
      'Select Media Model',
      'Select a media generation model.',
      ToolCategory.media,
      1,
      [const ToolParameter(name: 'modelId', description: 'Model ID')],
    );

    // -- Provider tools (category: provider) --------------------------------
    _reg(
      'inspect_provider_models',
      'Inspect Provider',
      'Inspect models available from a provider.',
      ToolCategory.provider,
      0,
      [const ToolParameter(name: 'providerId', description: 'Provider ID')],
    );
  }

  /// Internal helper to register a tool with a placeholder handler.
  void _reg(
    String id,
    String name,
    String description,
    ToolCategory category,
    int permissionLevel,
    List<ToolParameter> params,
  ) {
    registerTool(
      ToolDefinition(
        id: id,
        name: name,
        description: description,
        category: category,
        permissionLevel: permissionLevel,
        parameters: params,
        // TODO: Replace placeholder handlers with real implementations
        // during service initialization. Each domain service (FileService,
        // GitService, etc.) should call ToolRegistry.registerTool() with
        // a concrete handler.
        handler: (p) async => ToolResult.fail(
          toolId: id,
          error:
              'Tool "$id" handler not yet implemented. '
              'Wire the concrete implementation during app init.',
        ),
      ),
    );
  }
}
