// ============================================================================
// TermuxForge — MCP Types
// Data models for Model Context Protocol integration.
// ============================================================================

/// The transport mechanism used to communicate with an MCP server.
enum MCPTransport {
  /// Standard I/O (stdin/stdout) transport.
  stdio,

  /// Server-Sent Events (SSE) transport.
  sse,

  /// HTTP request/response transport.
  http,
}

/// The operational status of an MCP server.
enum MCPServerStatus {
  /// Server is reachable and operational.
  online,

  /// Server is not reachable.
  offline,

  /// Server health is unknown (not yet checked).
  unknown,

  /// Server is responding but reporting errors.
  degraded,
}

/// Represents a registered MCP server.
class MCPServer {
  /// Unique server identifier.
  final String id;

  /// Human-readable display name.
  final String name;

  /// The transport protocol used.
  final MCPTransport transport;

  /// The URI or command to reach the server.
  ///
  /// * For [MCPTransport.stdio]: the command to spawn the server process.
  /// * For [MCPTransport.sse] / [MCPTransport.http]: the HTTP(S) endpoint.
  final String uri;

  /// Current server status.
  MCPServerStatus status;

  /// Tools discovered on this server.
  final List<MCPTool> tools;

  /// When the last health check was performed (UTC).
  DateTime? lastHealthCheck;

  /// Latency of the last health check in milliseconds.
  int? lastHealthLatencyMs;

  /// Optional environment variables for stdio servers.
  final Map<String, String> environment;

  /// Optional arguments for stdio servers.
  final List<String> arguments;

  MCPServer({
    required this.id,
    required this.name,
    required this.transport,
    required this.uri,
    this.status = MCPServerStatus.unknown,
    List<MCPTool>? tools,
    this.lastHealthCheck,
    this.lastHealthLatencyMs,
    this.environment = const {},
    this.arguments = const [],
  }) : tools = tools ?? [];

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.name,
        'uri': uri,
        'status': status.name,
        'tools': tools.map((t) => t.toJson()).toList(),
        'lastHealthCheck': lastHealthCheck?.toIso8601String(),
        'lastHealthLatencyMs': lastHealthLatencyMs,
      };

  /// Deserializes from a JSON map.
  factory MCPServer.fromJson(Map<String, dynamic> json) {
    return MCPServer(
      id: json['id'] as String,
      name: json['name'] as String,
      transport: MCPTransport.values.firstWhere(
        (t) => t.name == json['transport'],
        orElse: () => MCPTransport.http,
      ),
      uri: json['uri'] as String,
      status: MCPServerStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MCPServerStatus.unknown,
      ),
      tools: (json['tools'] as List<dynamic>?)
              ?.map((t) => MCPTool.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Represents a tool exposed by an MCP server.
class MCPTool {
  /// Unique tool identifier.
  final String id;

  /// Tool name as reported by the server.
  final String name;

  /// Description of what the tool does.
  final String description;

  /// JSON Schema describing the tool's input parameters.
  final Map<String, dynamic> inputSchema;

  /// The MCP server that provides this tool.
  final String serverId;

  /// The permission level required to invoke this tool (0–8).
  int permissionLevel;

  MCPTool({
    required this.id,
    required this.name,
    required this.description,
    this.inputSchema = const {},
    required this.serverId,
    this.permissionLevel = 3,
  });

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'serverId': serverId,
        'permissionLevel': permissionLevel,
      };

  /// Deserializes from a JSON map.
  factory MCPTool.fromJson(Map<String, dynamic> json) {
    return MCPTool(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      inputSchema:
          (json['inputSchema'] as Map<String, dynamic>?) ?? {},
      serverId: json['serverId'] as String,
      permissionLevel: (json['permissionLevel'] as int?) ?? 3,
    );
  }
}

/// The result of an MCP tool invocation.
class MCPToolResult {
  /// Whether the invocation succeeded.
  final bool success;

  /// The result content (may be text, JSON, etc.).
  final dynamic content;

  /// Error message if the invocation failed.
  final String? error;

  /// The server that processed the request.
  final String serverId;

  /// The tool that was invoked.
  final String toolName;

  /// Duration of the invocation.
  final Duration duration;

  const MCPToolResult({
    required this.success,
    this.content,
    this.error,
    required this.serverId,
    required this.toolName,
    this.duration = Duration.zero,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'content': content,
        'error': error,
        'serverId': serverId,
        'toolName': toolName,
        'durationMs': duration.inMilliseconds,
      };
}
