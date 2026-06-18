// ============================================================================
// TermuxForge — LLM Types
// Data models for multi-provider LLM routing and model management.
// ============================================================================

/// Capabilities that an LLM model may support.
enum ModelCapability {
  /// Deep chain-of-thought reasoning.
  reasoning,

  /// Specialized for code generation and editing.
  coding,

  /// Optimized for low-latency responses.
  fast,

  /// Low cost per token.
  cheap,

  /// Supports very long context windows (100k+).
  longContext,

  /// Accepts and generates images or other media.
  multimodal,

  /// Can invoke tools / function calling.
  toolUse,

  /// Can perform web searches.
  webSearch,

  /// Well-suited for MCP tool-use workflows.
  mcpFriendly,

  /// Can generate images from text prompts.
  imageGeneration,

  /// Can generate videos from text prompts.
  videoGeneration,
}

/// Represents a single LLM model available through a provider.
class LLMModel {
  /// Unique model identifier (e.g., 'gpt-4o', 'claude-sonnet-4-20250514').
  final String id;

  /// Human-readable display name.
  final String name;

  /// The provider that hosts this model.
  final String providerId;

  /// Maximum context window size in tokens.
  final int contextWindow;

  /// The capabilities this model supports.
  final List<ModelCapability> capabilities;

  /// Cost per input token in USD.
  final double costPerInputToken;

  /// Cost per output token in USD.
  final double costPerOutputToken;

  /// Relative speed rating (1 = slowest, 10 = fastest).
  final int speed;

  /// Whether this model is currently available.
  bool isAvailable;

  LLMModel({
    required this.id,
    required this.name,
    required this.providerId,
    this.contextWindow = 4096,
    this.capabilities = const [],
    this.costPerInputToken = 0.0,
    this.costPerOutputToken = 0.0,
    this.speed = 5,
    this.isAvailable = true,
  });

  /// Whether this model has the given [capability].
  bool hasCapability(ModelCapability capability) {
    return capabilities.contains(capability);
  }

  /// Estimated cost for a given input/output token count.
  double estimateCost(int inputTokens, int outputTokens) {
    return (inputTokens * costPerInputToken) +
        (outputTokens * costPerOutputToken);
  }

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerId': providerId,
        'contextWindow': contextWindow,
        'capabilities': capabilities.map((c) => c.name).toList(),
        'costPerInputToken': costPerInputToken,
        'costPerOutputToken': costPerOutputToken,
        'speed': speed,
        'isAvailable': isAvailable,
      };

  /// Deserializes from a JSON map.
  factory LLMModel.fromJson(Map<String, dynamic> json) {
    return LLMModel(
      id: json['id'] as String,
      name: json['name'] as String,
      providerId: json['providerId'] as String,
      contextWindow: (json['contextWindow'] as int?) ?? 4096,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((c) => ModelCapability.values.firstWhere(
                    (v) => v.name == c,
                    orElse: () => ModelCapability.coding,
                  ))
              .toList() ??
          [],
      costPerInputToken: (json['costPerInputToken'] as num?)?.toDouble() ?? 0,
      costPerOutputToken:
          (json['costPerOutputToken'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as int?) ?? 5,
      isAvailable: (json['isAvailable'] as bool?) ?? true,
    );
  }
}

/// Represents an LLM API provider (e.g., OpenAI, Anthropic, local Ollama).
class LLMProvider {
  /// Unique provider identifier.
  final String id;

  /// Human-readable display name.
  final String name;

  /// The base URL for the OpenAI-compatible API.
  final String baseUrl;

  /// API key for authentication. Stored securely via flutter_secure_storage.
  String apiKey;

  /// Models available from this provider.
  final List<LLMModel> models;

  /// Whether the provider is reachable.
  bool isAvailable;

  /// Priority for model selection (lower = higher priority).
  int priority;

  /// Capabilities supported at the provider level.
  final List<ModelCapability> capabilities;

  /// Optional custom headers to send with every request.
  final Map<String, String> customHeaders;

  LLMProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    List<LLMModel>? models,
    this.isAvailable = true,
    this.priority = 50,
    this.capabilities = const [],
    this.customHeaders = const {},
  }) : models = models ?? [];

  /// Converts to a JSON-serializable map.
  ///
  /// **Note:** The [apiKey] is intentionally excluded for security.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'models': models.map((m) => m.toJson()).toList(),
        'isAvailable': isAvailable,
        'priority': priority,
        'capabilities': capabilities.map((c) => c.name).toList(),
      };
}

/// A single message in a chat conversation.
class ChatMessage {
  /// The role: 'system', 'user', 'assistant', or 'tool'.
  final String role;

  /// The text content of the message.
  final String content;

  /// Optional tool call ID (for tool-result messages).
  final String? toolCallId;

  /// Optional tool calls requested by the assistant.
  final List<Map<String, dynamic>>? toolCalls;

  /// When this message was created.
  final DateTime createdAt;

  ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls != null) 'tool_calls': toolCalls,
      };
}

/// The result of a chat completion request.
class ChatResult {
  /// The model that produced this result.
  final String modelId;

  /// The response content.
  final String content;

  /// Number of input tokens consumed.
  final int inputTokens;

  /// Number of output tokens generated.
  final int outputTokens;

  /// Any tool calls the model wants to make.
  final List<Map<String, dynamic>>? toolCalls;

  /// The finish reason: 'stop', 'tool_calls', 'length', etc.
  final String finishReason;

  /// How long the request took.
  final Duration duration;

  /// Estimated cost for this request in USD.
  final double estimatedCostUsd;

  const ChatResult({
    required this.modelId,
    required this.content,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.toolCalls,
    this.finishReason = 'stop',
    this.duration = Duration.zero,
    this.estimatedCostUsd = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'content': content,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'finishReason': finishReason,
        'durationMs': duration.inMilliseconds,
        'estimatedCostUsd': estimatedCostUsd,
      };
}

/// The result of a battle-mode comparison.
class BattleResult {
  /// The prompt that was sent to all models.
  final String prompt;

  /// Results from each model, keyed by model ID.
  final Map<String, ChatResult> results;

  /// The model ID selected as the winner (null if not yet judged).
  String? winnerId;

  /// When the battle was started.
  final DateTime startedAt;

  /// Total wall-clock time for the battle.
  Duration totalDuration;

  BattleResult({
    required this.prompt,
    required this.results,
    this.winnerId,
    DateTime? startedAt,
    this.totalDuration = Duration.zero,
  }) : startedAt = startedAt ?? DateTime.now().toUtc();
}
