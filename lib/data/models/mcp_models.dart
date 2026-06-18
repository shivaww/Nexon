/// MCP (Model Context Protocol) data models.
///
/// These models capture MCP server connections, tool definitions, resource
/// descriptors, prompt templates, and tool invocation history — enabling
/// the agent system to discover, connect to, and track MCP servers.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// McpServerStatus
// ---------------------------------------------------------------------------

/// Connection status of an MCP server.
enum McpServerStatus {
  /// Not yet connected.
  disconnected,

  /// Connection attempt in progress.
  connecting,

  /// Connected and healthy.
  connected,

  /// Connection lost or server unreachable.
  error,

  /// Reconnecting after a failure.
  reconnecting,
}

// ---------------------------------------------------------------------------
// McpTransportType
// ---------------------------------------------------------------------------

/// Transport mechanism used to communicate with an MCP server.
enum McpTransportType {
  /// Standard I/O (stdin / stdout).
  stdio,

  /// Server-Sent Events over HTTP.
  sse,

  /// WebSocket connection.
  websocket,
}

// ---------------------------------------------------------------------------
// McpToolDefinition
// ---------------------------------------------------------------------------

/// A tool exposed by an MCP server.
class McpToolDefinition extends Equatable {
  /// Creates a new [McpToolDefinition].
  const McpToolDefinition({
    required this.name,
    this.description = '',
    this.inputSchema = const {},
    this.outputSchema = const {},
  });

  /// The tool name as registered on the MCP server.
  final String name;

  /// Human-readable description of what the tool does.
  final String description;

  /// JSON Schema describing the tool's input parameters.
  final Map<String, dynamic> inputSchema;

  /// JSON Schema describing the tool's output format.
  final Map<String, dynamic> outputSchema;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
      'outputSchema': outputSchema,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory McpToolDefinition.fromJson(Map<String, dynamic> json) {
    return McpToolDefinition(
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      inputSchema: Map<String, dynamic>.from(
        (json['inputSchema'] as Map?) ?? {},
      ),
      outputSchema: Map<String, dynamic>.from(
        (json['outputSchema'] as Map?) ?? {},
      ),
    );
  }

  @override
  List<Object?> get props => [name, description, inputSchema, outputSchema];
}

// ---------------------------------------------------------------------------
// McpResourceDescriptor
// ---------------------------------------------------------------------------

/// A resource exposed by an MCP server (e.g. a file, database, or API).
class McpResourceDescriptor extends Equatable {
  /// Creates a new [McpResourceDescriptor].
  const McpResourceDescriptor({
    required this.uri,
    this.name = '',
    this.description = '',
    this.mimeType,
  });

  /// Resource URI (e.g. "file:///path" or "db://table").
  final String uri;

  /// Human-readable name.
  final String name;

  /// Description of the resource.
  final String description;

  /// MIME type of the resource content (if applicable).
  final String? mimeType;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      'name': name,
      'description': description,
      'mimeType': mimeType,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory McpResourceDescriptor.fromJson(Map<String, dynamic> json) {
    return McpResourceDescriptor(
      uri: json['uri'] as String,
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      mimeType: json['mimeType'] as String?,
    );
  }

  @override
  List<Object?> get props => [uri, name, description, mimeType];
}

// ---------------------------------------------------------------------------
// McpPromptTemplate
// ---------------------------------------------------------------------------

/// A prompt template offered by an MCP server.
class McpPromptTemplate extends Equatable {
  /// Creates a new [McpPromptTemplate].
  const McpPromptTemplate({
    required this.name,
    this.description = '',
    this.arguments = const [],
    this.template = '',
  });

  /// Template name.
  final String name;

  /// Human-readable description.
  final String description;

  /// Required argument names for the template.
  final List<String> arguments;

  /// The template string with placeholder markers.
  final String template;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'arguments': arguments,
      'template': template,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory McpPromptTemplate.fromJson(Map<String, dynamic> json) {
    return McpPromptTemplate(
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      arguments: List<String>.from((json['arguments'] as List?) ?? []),
      template: (json['template'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [name, description, arguments, template];
}

// ---------------------------------------------------------------------------
// McpToolInvocation
// ---------------------------------------------------------------------------

/// Record of a single MCP tool invocation for history / auditing.
class McpToolInvocation extends Equatable {
  /// Creates a new [McpToolInvocation].
  const McpToolInvocation({
    required this.id,
    required this.serverId,
    required this.toolName,
    required this.input,
    this.output,
    this.error,
    this.durationMs = 0,
    required this.timestamp,
    this.agentId,
    this.taskId,
  });

  /// Unique invocation identifier.
  final String id;

  /// The MCP server that handled the call.
  final String serverId;

  /// The tool that was invoked.
  final String toolName;

  /// Input parameters sent to the tool.
  final Map<String, dynamic> input;

  /// Output returned by the tool (null if the call failed).
  final Map<String, dynamic>? output;

  /// Error message (null if the call succeeded).
  final String? error;

  /// Wall-clock duration in milliseconds.
  final int durationMs;

  /// When the invocation occurred.
  final DateTime timestamp;

  /// Agent that requested the invocation (if any).
  final String? agentId;

  /// Task context (if any).
  final String? taskId;

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serverId': serverId,
      'toolName': toolName,
      'input': input,
      'output': output,
      'error': error,
      'durationMs': durationMs,
      'timestamp': timestamp.toIso8601String(),
      'agentId': agentId,
      'taskId': taskId,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory McpToolInvocation.fromJson(Map<String, dynamic> json) {
    return McpToolInvocation(
      id: json['id'] as String,
      serverId: json['serverId'] as String,
      toolName: json['toolName'] as String,
      input: Map<String, dynamic>.from((json['input'] as Map?) ?? {}),
      output: json['output'] != null
          ? Map<String, dynamic>.from(json['output'] as Map)
          : null,
      error: json['error'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.parse(json['timestamp'] as String),
      agentId: json['agentId'] as String?,
      taskId: json['taskId'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serverId,
        toolName,
        input,
        output,
        error,
        durationMs,
        timestamp,
        agentId,
        taskId,
      ];
}

// ---------------------------------------------------------------------------
// McpServerConfig
// ---------------------------------------------------------------------------

/// Configuration and runtime state for an MCP server connection.
class McpServerConfig extends Equatable {
  /// Creates a new [McpServerConfig].
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.transport,
    required this.command,
    this.args = const [],
    this.env = const {},
    this.url,
    this.status = McpServerStatus.disconnected,
    this.tools = const [],
    this.resources = const [],
    this.prompts = const [],
    this.lastConnected,
    this.errorMessage,
    this.autoConnect = true,
  });

  /// Unique server identifier.
  final String id;

  /// Human-readable server name.
  final String name;

  /// Transport mechanism.
  final McpTransportType transport;

  /// Shell command to start the server (for stdio transport).
  final String command;

  /// Command arguments.
  final List<String> args;

  /// Environment variables passed to the server process.
  final Map<String, String> env;

  /// URL for SSE or WebSocket transports.
  final String? url;

  /// Current connection status.
  final McpServerStatus status;

  /// Tools discovered on this server.
  final List<McpToolDefinition> tools;

  /// Resources discovered on this server.
  final List<McpResourceDescriptor> resources;

  /// Prompt templates discovered on this server.
  final List<McpPromptTemplate> prompts;

  /// When the server was last successfully connected.
  final DateTime? lastConnected;

  /// Most recent error message (if any).
  final String? errorMessage;

  /// Whether to automatically connect on startup.
  final bool autoConnect;

  /// Returns a copy with the given fields replaced.
  McpServerConfig copyWith({
    String? id,
    String? name,
    McpTransportType? transport,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? url,
    McpServerStatus? status,
    List<McpToolDefinition>? tools,
    List<McpResourceDescriptor>? resources,
    List<McpPromptTemplate>? prompts,
    DateTime? lastConnected,
    String? errorMessage,
    bool? autoConnect,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      url: url ?? this.url,
      status: status ?? this.status,
      tools: tools ?? this.tools,
      resources: resources ?? this.resources,
      prompts: prompts ?? this.prompts,
      lastConnected: lastConnected ?? this.lastConnected,
      errorMessage: errorMessage ?? this.errorMessage,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'transport': transport.name,
      'command': command,
      'args': args,
      'env': env,
      'url': url,
      'status': status.name,
      'tools': tools.map((t) => t.toJson()).toList(),
      'resources': resources.map((r) => r.toJson()).toList(),
      'prompts': prompts.map((p) => p.toJson()).toList(),
      'lastConnected': lastConnected?.toIso8601String(),
      'errorMessage': errorMessage,
      'autoConnect': autoConnect,
    };
  }

  /// Deserialise from a JSON-compatible map.
  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      transport: McpTransportType.values.byName(json['transport'] as String),
      command: json['command'] as String,
      args: List<String>.from((json['args'] as List?) ?? []),
      env: Map<String, String>.from((json['env'] as Map?) ?? {}),
      url: json['url'] as String?,
      status: McpServerStatus.values.byName(
        (json['status'] as String?) ?? 'disconnected',
      ),
      tools: (json['tools'] as List?)
              ?.map(
                (e) => McpToolDefinition.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      resources: (json['resources'] as List?)
              ?.map(
                (e) =>
                    McpResourceDescriptor.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      prompts: (json['prompts'] as List?)
              ?.map(
                (e) => McpPromptTemplate.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
      autoConnect: (json['autoConnect'] as bool?) ?? true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        transport,
        command,
        args,
        env,
        url,
        status,
        tools,
        resources,
        prompts,
        lastConnected,
        errorMessage,
        autoConnect,
      ];
}
