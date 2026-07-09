// ============================================================================
// TermuxForge — Tool Registry Types
// Data models and enums for the unified tool abstraction layer.
// ============================================================================

/// Categorizes tools by their operational domain.
enum ToolCategory {
  /// File system operations: read, write, edit, search, list.
  file,

  /// Git version control operations.
  git,

  /// Flutter CLI operations: run, test, build.
  flutter,

  /// Dart SDK operations: analyze, test.
  dart,

  /// Shell / terminal command execution.
  shell,

  /// Memory / knowledge-base operations.
  memory,

  /// Agent orchestration tools.
  agent,

  /// LLM model management tools.
  model,

  /// Model Context Protocol operations.
  mcp,

  /// Multi-step workflow orchestration.
  workflow,

  /// Checkpoint / rollback operations.
  checkpoint,

  /// Image and video generation tools.
  media,

  /// Background agent management.
  background,

  /// Token / cost tracking tools.
  cost,

  /// LLM provider inspection tools.
  provider,
}

/// Describes a single parameter expected by a tool.
class ToolParameter {
  /// Machine-readable parameter name.
  final String name;

  /// Human-readable description.
  final String description;

  /// The Dart type name (e.g., 'String', 'int', 'Map<String, dynamic>').
  final String type;

  /// Whether this parameter must be provided.
  final bool required;

  /// A default value serialized as a string, if any.
  final String? defaultValue;

  const ToolParameter({
    required this.name,
    required this.description,
    this.type = 'String',
    this.required = true,
    this.defaultValue,
  });

  /// Converts to a JSON-serializable map (for MCP / LLM tool schemas).
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'type': type,
    'required': required,
    if (defaultValue != null) 'default': defaultValue,
  };
}

/// The handler signature for tool execution.
///
/// Receives a map of parameter name → value and returns a [ToolResult].
typedef ToolHandler = Future<ToolResult> Function(Map<String, dynamic> params);

/// Full definition of a tool that can be registered and invoked.
class ToolDefinition {
  /// Unique tool identifier (e.g., 'read_file_rich').
  final String id;

  /// Human-readable display name.
  final String name;

  /// Detailed description of what this tool does.
  final String description;

  /// The category this tool belongs to.
  final ToolCategory category;

  /// Permission level required to invoke this tool (0–8).
  ///
  /// * 0 = no-risk (read-only metadata)
  /// * 1 = low-risk (read file contents)
  /// * 2 = moderate (write to project files)
  /// * 3 = elevated (run linters / analyzers)
  /// * 4 = high (run tests, build commands)
  /// * 5 = dangerous (arbitrary shell execution)
  /// * 6 = critical (git push, deploy)
  /// * 7 = destructive (delete files, rm commands)
  /// * 8 = system (modify system configuration)
  final int permissionLevel;

  /// The parameters this tool accepts.
  final List<ToolParameter> parameters;

  /// The async handler that executes this tool.
  final ToolHandler handler;

  /// Whether this tool supports streaming output.
  final bool supportsStreaming;

  const ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.permissionLevel,
    this.parameters = const [],
    required this.handler,
    this.supportsStreaming = false,
  });

  /// Converts the tool definition to a JSON-serializable map.
  ///
  /// Useful for exposing tool schemas to LLMs or MCP clients.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category.name,
    'permissionLevel': permissionLevel,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'supportsStreaming': supportsStreaming,
  };
}

/// The result returned by a tool invocation.
class ToolResult {
  /// Whether the tool executed successfully.
  final bool success;

  /// The result data (type depends on the tool).
  final dynamic data;

  /// An error message if [success] is `false`.
  final String? error;

  /// How long the tool took to execute.
  final Duration duration;

  /// The ID of the tool that produced this result.
  final String toolId;

  const ToolResult({
    required this.success,
    this.data,
    this.error,
    required this.duration,
    required this.toolId,
  });

  /// Creates a successful result.
  factory ToolResult.ok({
    required String toolId,
    dynamic data,
    Duration duration = Duration.zero,
  }) =>
      ToolResult(success: true, data: data, duration: duration, toolId: toolId);

  /// Creates a failed result.
  factory ToolResult.fail({
    required String toolId,
    required String error,
    Duration duration = Duration.zero,
  }) => ToolResult(
    success: false,
    error: error,
    duration: duration,
    toolId: toolId,
  );

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'success': success,
    'data': data,
    'error': error,
    'durationMs': duration.inMilliseconds,
    'toolId': toolId,
  };
}
