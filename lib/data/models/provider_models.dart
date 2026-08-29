// Extracted from main.dart lines 18905-19798
// Extracted: 2026-08-26T13:37:38.520069

class ProviderDefinition {
  const ProviderDefinition({
    required this.id,
    required this.name,
    required this.shortName,
    required this.keyLabel,
    required this.baseUrl,
    required this.models,
    this.defaultMaxTokens = 4096,
    this.requiresKey = true,
    this.extraHeaders = const {},
    this.isKaggle = false,
  });

  final String id;
  final String name;
  final String shortName;
  final String keyLabel;
  final String baseUrl;
  final List<String> models;
  final int defaultMaxTokens;
  final bool requiresKey;
  final Map<String, String> extraHeaders;
  final bool isKaggle;
}

class ProviderSettings {
  const ProviderSettings({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.maxTokens,
    this.fallbackApiKeys = const [],
    this.reasoningEnabled = true,
    this.reasoningEffort = 'low',
    this.temperature = 1.0,
  });

  /// Default maximum output length used for fresh provider settings.
  static const int defaultMaxOutputTokens = 128000;

  factory ProviderSettings.defaults(ProviderDefinition provider) {
    return ProviderSettings(
      apiKey: '',
      baseUrl: provider.baseUrl,
      model: provider.models.first,
      maxTokens: defaultMaxOutputTokens,
      fallbackApiKeys: const [],
      reasoningEnabled: true,
      reasoningEffort: 'low',
      temperature: 1.0,
    );
  }

  factory ProviderSettings.fromJson(Map<String, dynamic> json) {
    return ProviderSettings(
      apiKey: json['apiKey']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      maxTokens: _readInt(json['maxTokens'], 0),
      fallbackApiKeys:
          (json['fallbackApiKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? true,
      reasoningEffort: _validEffort(json['reasoningEffort']?.toString()),
      temperature: _readDouble(json['temperature'], 1.0),
    );
  }

  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxTokens;
  final List<String> fallbackApiKeys;
  final bool reasoningEnabled;

  /// Thinking depth level: low | medium | high | extra | max. Mapped to
  /// each provider's reasoning knobs (reasoning_effort / thinking budget).
  final String reasoningEffort;

  /// Sampling temperature sent to the provider (0.0 – 2.0). Lower values
  /// are more deterministic, higher values more creative.
  final double temperature;

  ProviderSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? maxTokens,
    List<String>? fallbackApiKeys,
    bool? reasoningEnabled,
    String? reasoningEffort,
    double? temperature,
  }) {
    return ProviderSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      fallbackApiKeys: fallbackApiKeys ?? this.fallbackApiKeys,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      temperature: temperature ?? this.temperature,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'maxTokens': maxTokens,
      'fallbackApiKeys': fallbackApiKeys,
      'reasoningEnabled': reasoningEnabled,
      'reasoningEffort': reasoningEffort,
      'temperature': temperature,
    };
  }

  static double _readDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static const List<String> reasoningEfforts = [
    'low',
    'medium',
    'high',
    'extra',
    'max',
  ];

  static String _validEffort(String? raw) {
    final v = (raw ?? '').toLowerCase();
    return reasoningEfforts.contains(v) ? v : 'low';
  }
}

class CustomSearchProvider {
  final String id;
  final String name;
  final String endpoint;
  final String method;
  final String apiKeyHeader;
  final String apiKeyPrefix;
  final String queryParam;
  final String resultsPath;
  final String titleField;
  final String urlField;
  final String snippetField;
  final Map<String, String> extraParams;

  const CustomSearchProvider({
    required this.id,
    required this.name,
    required this.endpoint,
    this.method = 'POST',
    this.apiKeyHeader = 'Authorization',
    this.apiKeyPrefix = 'Bearer ',
    this.queryParam = 'query',
    this.resultsPath = 'results',
    this.titleField = 'title',
    this.urlField = 'url',
    this.snippetField = 'content',
    this.extraParams = const {},
  });

  factory CustomSearchProvider.fromJson(Map<String, dynamic> json) {
    return CustomSearchProvider(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      endpoint: json['endpoint']?.toString() ?? '',
      method: json['method']?.toString() ?? 'POST',
      apiKeyHeader: json['apiKeyHeader']?.toString() ?? 'Authorization',
      apiKeyPrefix: json['apiKeyPrefix']?.toString() ?? 'Bearer ',
      queryParam: json['queryParam']?.toString() ?? 'query',
      resultsPath: json['resultsPath']?.toString() ?? 'results',
      titleField: json['titleField']?.toString() ?? 'title',
      urlField: json['urlField']?.toString() ?? 'url',
      snippetField: json['snippetField']?.toString() ?? 'content',
      extraParams: Map<String, String>.from(
        (json['extraParams'] as Map?) ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'method': method,
    'apiKeyHeader': apiKeyHeader,
    'apiKeyPrefix': apiKeyPrefix,
    'queryParam': queryParam,
    'resultsPath': resultsPath,
    'titleField': titleField,
    'urlField': urlField,
    'snippetField': snippetField,
    'extraParams': extraParams,
  };
}

class SearchSettings {
  final bool enabled;
  final String provider;
  final String apiKey;
  final List<String> fallbackApiKeys;
  final String googleCx;
  final List<CustomSearchProvider> customProviders;

  const SearchSettings({
    required this.enabled,
    required this.provider,
    required this.apiKey,
    required this.fallbackApiKeys,
    required this.googleCx,
    this.customProviders = const [],
  });

  factory SearchSettings.defaults() {
    return const SearchSettings(
      enabled: false,
      provider: 'tavily',
      apiKey: '',
      fallbackApiKeys: [],
      googleCx: '',
    );
  }

  factory SearchSettings.fromJson(Map<String, dynamic> json) {
    return SearchSettings(
      enabled: json['enabled'] as bool? ?? false,
      provider: json['provider']?.toString() ?? 'tavily',
      apiKey: json['apiKey']?.toString() ?? '',
      fallbackApiKeys:
          (json['fallbackApiKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      googleCx: json['googleCx']?.toString() ?? '',
      customProviders: (json['customProviders'] as List<dynamic>?)
              ?.map((e) => CustomSearchProvider.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'provider': provider,
    'apiKey': apiKey,
    'fallbackApiKeys': fallbackApiKeys,
    'googleCx': googleCx,
    'customProviders': customProviders.map((p) => p.toJson()).toList(),
  };

  SearchSettings copyWith({
    bool? enabled,
    String? provider,
    String? apiKey,
    List<String>? fallbackApiKeys,
    String? googleCx,
    List<CustomSearchProvider>? customProviders,
  }) {
    return SearchSettings(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      fallbackApiKeys: fallbackApiKeys ?? this.fallbackApiKeys,
      googleCx: googleCx ?? this.googleCx,
      customProviders: customProviders ?? this.customProviders,
    );
  }
}

enum MessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const MessageRole(this.apiName);
  final String apiName;
}

class AttachedFile {
  final String name;
  final String content;
  final String? workspacePath;

  const AttachedFile({
    required this.name,
    required this.content,
    this.workspacePath,
  });

  bool get isWorkspaceFile => workspacePath != null;

  Map<String, dynamic> toJson() => {
    'name': name,
    'content': content,
    if (workspacePath != null) 'workspacePath': workspacePath,
  };
  factory AttachedFile.fromJson(Map<String, dynamic> json) => AttachedFile(
    name: json['name']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    workspacePath: json['workspacePath']?.toString(),
  );
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
    this.reasoning = '',
    this.images = const [],
    this.videos = const [],
    this.files = const [],
    this.tokensPerSec = '',
    this.tokenUsage = '',
  });

  final MessageRole role;
  final String text;
  final bool isError;
  final String reasoning;
  final String tokensPerSec;
  final String tokenUsage;

  /// Base64-encoded image data attached to this message.
  final List<String> images;

  /// Base64-encoded video data attached to this message.
  final List<String> videos;
  final List<AttachedFile> files;

  ChatMessage copyWith({
    MessageRole? role,
    String? text,
    bool? isError,
    String? reasoning,
    List<String>? images,
    List<String>? videos,
    List<AttachedFile>? files,
    String? tokensPerSec,
    String? tokenUsage,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      text: text ?? this.text,
      isError: isError ?? this.isError,
      reasoning: reasoning ?? this.reasoning,
      images: images ?? this.images,
      videos: videos ?? this.videos,
      files: files ?? this.files,
      tokensPerSec: tokensPerSec ?? this.tokensPerSec,
      tokenUsage: tokenUsage ?? this.tokenUsage,
    );
  }
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final String providerId;
  final String model;
  final int? maxTokens;
  final List<String> attachedImagesBase64;
  final List<AttachedFile> attachedFiles;
  final bool isPinned;
  final List<List<ChatMessage>>? branches;
  final int? activeBranchIndex;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.providerId,
    required this.model,
    this.maxTokens,
    this.attachedImagesBase64 = const [],
    this.attachedFiles = const [],
    this.isPinned = false,
    this.branches,
    this.activeBranchIndex,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? _parseIdDate(id);

  static DateTime _parseIdDate(String id) {
    final ms = int.tryParse(id);
    if (ms != null && ms > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.now();
  }

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    String? providerId,
    String? model,
    int? maxTokens,
    List<String>? attachedImagesBase64,
    List<AttachedFile>? attachedFiles,
    bool? isPinned,
    List<List<ChatMessage>>? branches,
    int? activeBranchIndex,
    DateTime? updatedAt,
  }) {
    List<List<ChatMessage>>? updatedBranches = branches ?? this.branches;
    int? updatedActiveIndex = activeBranchIndex ?? this.activeBranchIndex;

    if (messages != null) {
      final activeIdx = updatedActiveIndex ?? 0;
      final currentBranches = updatedBranches ?? [this.messages];
      final newBranches = List<List<ChatMessage>>.from(currentBranches);
      if (activeIdx >= 0 && activeIdx < newBranches.length) {
        newBranches[activeIdx] = messages;
      } else {
        newBranches.add(messages);
      }
      updatedBranches = newBranches;
      updatedActiveIndex = activeIdx;
    }

    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      attachedImagesBase64: attachedImagesBase64 ?? this.attachedImagesBase64,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      isPinned: isPinned ?? this.isPinned,
      branches: updatedBranches,
      activeBranchIndex: updatedActiveIndex,
      updatedAt:
          updatedAt ?? (messages != null ? DateTime.now() : this.updatedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages
        .map(
          (m) => {
            'role': m.role.apiName,
            'text': m.text,
            'isError': m.isError,
            'reasoning': m.reasoning,
            'images': m.images,
            'videos': m.videos,
            'files': m.files.map((f) => f.toJson()).toList(),
          },
        )
        .toList(),
    'providerId': providerId,
    'model': model,
    'maxTokens': maxTokens,
    'attachedImagesBase64': attachedImagesBase64,
    'attachedFiles': attachedFiles.map((f) => f.toJson()).toList(),
    'isPinned': isPinned,
    'branches': branches
        ?.map(
          (branch) => branch
              .map(
                (m) => {
                  'role': m.role.apiName,
                  'text': m.text,
                  'isError': m.isError,
                  'reasoning': m.reasoning,
                  'images': m.images,
                  'videos': m.videos,
                  'files': m.files.map((f) => f.toJson()).toList(),
                },
              )
              .toList(),
        )
        .toList(),
    'activeBranchIndex': activeBranchIndex,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final messagesList =
        (json['messages'] as List?)
            ?.map(
              (m) => ChatMessage(
                role: MessageRole.values.firstWhere(
                  (v) => v.apiName == m['role'],
                  orElse: () => MessageRole.user,
                ),
                text: m['text']?.toString() ?? '',
                isError: m['isError'] as bool? ?? false,
                reasoning: m['reasoning']?.toString() ?? '',
                images:
                    (m['images'] as List?)?.map((e) => e.toString()).toList() ??
                    const [],
                videos:
                    (m['videos'] as List?)?.map((e) => e.toString()).toList() ??
                    const [],
                files:
                    (m['files'] as List?)
                        ?.map(
                          (e) => AttachedFile.fromJson(
                            Map<String, dynamic>.from(e as Map),
                          ),
                        )
                        .toList() ??
                    const [],
              ),
            )
            .toList() ??
        [];
    final branchesList = (json['branches'] as List?)
        ?.map(
          (branch) => (branch as List)
              .map(
                (m) => ChatMessage(
                  role: MessageRole.values.firstWhere(
                    (v) => v.apiName == m['role'],
                    orElse: () => MessageRole.user,
                  ),
                  text: m['text']?.toString() ?? '',
                  isError: m['isError'] as bool? ?? false,
                  reasoning: m['reasoning']?.toString() ?? '',
                  images:
                      (m['images'] as List?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const [],
                  videos:
                      (m['videos'] as List?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const [],
                  files:
                      (m['files'] as List?)
                          ?.map(
                            (e) => AttachedFile.fromJson(
                              Map<String, dynamic>.from(e as Map),
                            ),
                          )
                          .toList() ??
                      const [],
                ),
              )
              .toList(),
        )
        .toList();

    final rawDate = json['updatedAt']?.toString();
    final parsedDate = (rawDate != null && rawDate.isNotEmpty)
        ? (DateTime.tryParse(rawDate) ??
              _parseIdDate(json['id']?.toString() ?? ''))
        : _parseIdDate(json['id']?.toString() ?? '');

    return ChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      messages: messagesList,
      providerId: json['providerId']?.toString() ?? providerCatalog.first.id,
      model: json['model']?.toString() ?? '',
      maxTokens: json['maxTokens'] as int?,
      attachedImagesBase64:
          (json['attachedImagesBase64'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      attachedFiles:
          (json['attachedFiles'] as List?)
              ?.map(
                (e) =>
                    AttachedFile.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
      isPinned: json['isPinned'] as bool? ?? false,
      branches: branchesList,
      activeBranchIndex: json['activeBranchIndex'] as int?,
      updatedAt: parsedDate,
    );
  }
}

const providerCatalog = <ProviderDefinition>[
  ProviderDefinition(
    id: 'nexon',
    name: 'Nexon Pro Subscription',
    shortName: 'NX',
    keyLabel: 'NEXON_MANAGED_KEY',
    baseUrl: 'https://nexon-jyp1.onrender.com',
    models: ['deepseek-v4-flash', 'llama-4-maverick', 'glm-5.2'],
    defaultMaxTokens: 8192,
  ),
  ProviderDefinition(
    id: 'nvidia',
    name: 'NVIDIA NIM',
    shortName: 'NV',
    keyLabel: 'NVIDIA_API_KEY',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    models: [
      'minimaxai/minimax-m3',
      'meta/llama-3.1-405b-instruct',
      'nvidia/llama-3.1-nemotron-ultra-253b-v1',
      'deepseek-ai/deepseek-r1',
    ],
    defaultMaxTokens: 8192,
  ),
  ProviderDefinition(
    id: 'openai',
    name: 'OpenAI',
    shortName: 'OA',
    keyLabel: 'OPENAI_API_KEY',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o', 'o4-mini'],
  ),
  ProviderDefinition(
    id: 'openrouter',
    name: 'OpenRouter',
    shortName: 'OR',
    keyLabel: 'OPENROUTER_API_KEY',
    baseUrl: 'https://openrouter.ai/api/v1',
    models: [
      'anthropic/claude-3.5-sonnet',
      'openai/gpt-4o',
      'google/gemini-2.5-pro',
    ],
    defaultMaxTokens: 2048,
    extraHeaders: {
      'HTTP-Referer': 'https://termuxforge.local',
      'X-Title': 'Forge Chat',
    },
  ),
  ProviderDefinition(
    id: 'google',
    name: 'Google Gemini',
    shortName: 'GG',
    keyLabel: 'GEMINI_API_KEY',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash'],
  ),
  ProviderDefinition(
    id: 'groq',
    name: 'Groq',
    shortName: 'GQ',
    keyLabel: 'GROQ_API_KEY',
    baseUrl: 'https://api.groq.com/openai/v1',
    models: ['llama-3.3-70b-versatile', 'deepseek-r1-distill-llama-70b'],
  ),
  ProviderDefinition(
    id: 'together',
    name: 'Together AI',
    shortName: 'TG',
    keyLabel: 'TOGETHER_API_KEY',
    baseUrl: 'https://api.together.xyz/v1',
    models: [
      'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      'deepseek-ai/DeepSeek-R1',
    ],
  ),
  ProviderDefinition(
    id: 'fireworks',
    name: 'Fireworks AI',
    shortName: 'FW',
    keyLabel: 'FIREWORKS_API_KEY',
    baseUrl: 'https://api.fireworks.ai/inference/v1',
    models: ['accounts/fireworks/models/llama-v3p1-405b-instruct'],
  ),
  ProviderDefinition(
    id: 'deepinfra',
    name: 'DeepInfra',
    shortName: 'DI',
    keyLabel: 'DEEPINFRA_API_KEY',
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    models: [
      'meta-llama/Meta-Llama-3.1-70B-Instruct',
      'deepseek-ai/DeepSeek-R1',
    ],
  ),
  ProviderDefinition(
    id: 'mistral',
    name: 'Mistral AI',
    shortName: 'MI',
    keyLabel: 'MISTRAL_API_KEY',
    baseUrl: 'https://api.mistral.ai/v1',
    models: ['mistral-large-latest', 'codestral-latest', 'ministral-8b-latest'],
  ),
  ProviderDefinition(
    id: 'xai',
    name: 'xAI',
    shortName: 'xA',
    keyLabel: 'XAI_API_KEY',
    baseUrl: 'https://api.x.ai/v1',
    models: ['grok-4', 'grok-3', 'grok-3-mini'],
  ),
  ProviderDefinition(
    id: 'perplexity',
    name: 'Perplexity',
    shortName: 'PX',
    keyLabel: 'PERPLEXITY_API_KEY',
    baseUrl: 'https://api.perplexity.ai',
    models: ['sonar', 'sonar-pro', 'sonar-reasoning-pro'],
  ),
  ProviderDefinition(
    id: 'deepseek',
    name: 'DeepSeek',
    shortName: 'DS',
    keyLabel: 'DEEPSEEK_API_KEY',
    baseUrl: 'https://api.deepseek.com',
    models: ['deepseek-chat', 'deepseek-reasoner'],
  ),
  ProviderDefinition(
    id: 'cohere',
    name: 'Cohere',
    shortName: 'CO',
    keyLabel: 'COHERE_API_KEY',
    baseUrl: 'https://api.cohere.com/compatibility/v1',
    models: ['command-a-03-2025', 'command-r-plus', 'command-r'],
  ),
  ProviderDefinition(
    id: 'cerebras',
    name: 'Cerebras',
    shortName: 'CB',
    keyLabel: 'CEREBRAS_API_KEY',
    baseUrl: 'https://api.cerebras.ai/v1',
    models: ['llama-4-scout-17b-16e-instruct', 'llama3.1-70b'],
  ),
  ProviderDefinition(
    id: 'sarvam',
    name: 'Sarvam AI',
    shortName: 'SV',
    keyLabel: 'SARVAM_API_KEY',
    baseUrl: 'https://api.sarvam.ai/v1',
    models: ['sarvam-105b', 'sarvam-30b', 'sarvam-2b', 'sarvam-m'],
  ),
  ProviderDefinition(
    id: 'sambanova',
    name: 'SambaNova',
    shortName: 'SN',
    keyLabel: 'SAMBANOVA_API_KEY',
    baseUrl: 'https://api.sambanova.ai/v1',
    models: ['Meta-Llama-3.1-405B-Instruct', 'DeepSeek-R1'],
  ),
  ProviderDefinition(
    id: 'novita',
    name: 'Novita AI',
    shortName: 'NO',
    keyLabel: 'NOVITA_API_KEY',
    baseUrl: 'https://api.novita.ai/v3/openai',
    models: ['meta-llama/llama-3.1-8b-instruct', 'deepseek/deepseek-r1'],
  ),
  ProviderDefinition(
    id: 'hyperbolic',
    name: 'Hyperbolic',
    shortName: 'HB',
    keyLabel: 'HYPERBOLIC_API_KEY',
    baseUrl: 'https://api.hyperbolic.xyz/v1',
    models: [
      'meta-llama/Meta-Llama-3.1-405B-Instruct',
      'deepseek-ai/DeepSeek-R1',
    ],
  ),
  ProviderDefinition(
    id: 'aimlapi',
    name: 'AI/ML API',
    shortName: 'AI',
    keyLabel: 'AIMLAPI_KEY',
    baseUrl: 'https://api.aimlapi.com/v1',
    models: [
      'gpt-4o',
      'claude-3-5-sonnet',
      'meta-llama/Meta-Llama-3.1-70B-Instruct',
    ],
  ),
  ProviderDefinition(
    id: 'nebius',
    name: 'Nebius AI Studio',
    shortName: 'NB',
    keyLabel: 'NEBIUS_API_KEY',
    baseUrl: 'https://api.studio.nebius.com/v1',
    models: [
      'meta-llama/Meta-Llama-3.1-70B-Instruct',
      'deepseek-ai/DeepSeek-R1',
    ],
  ),
  ProviderDefinition(
    id: 'moonshot',
    name: 'Moonshot Kimi',
    shortName: 'KM',
    keyLabel: 'MOONSHOT_API_KEY',
    baseUrl: 'https://api.moonshot.ai/v1',
    models: ['kimi-k2-0711-preview', 'moonshot-v1-128k'],
  ),
  ProviderDefinition(
    id: 'zhipu',
    name: 'Zhipu GLM',
    shortName: 'GL',
    keyLabel: 'ZHIPU_API_KEY',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4-plus', 'glm-4-air', 'glm-z1-air'],
  ),
  ProviderDefinition(
    id: 'dashscope',
    name: 'Alibaba DashScope',
    shortName: 'DS',
    keyLabel: 'DASHSCOPE_API_KEY',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
    models: ['qwen-plus', 'qwen-max', 'qwen-turbo'],
  ),
  ProviderDefinition(
    id: 'siliconflow',
    name: 'SiliconFlow',
    shortName: 'SF',
    keyLabel: 'SILICONFLOW_API_KEY',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: ['deepseek-ai/DeepSeek-R1', 'Qwen/Qwen2.5-72B-Instruct'],
  ),
  ProviderDefinition(
    id: 'minimax',
    name: 'MiniMax',
    shortName: 'MM',
    keyLabel: 'MINIMAX_API_KEY',
    baseUrl: 'https://api.minimax.chat/v1',
    models: ['MiniMax-M1', 'MiniMax-Text-01'],
  ),
  ProviderDefinition(
    id: 'yi',
    name: '01.AI Yi',
    shortName: 'YI',
    keyLabel: 'YI_API_KEY',
    baseUrl: 'https://api.01.ai/v1',
    models: ['yi-large', 'yi-lightning'],
  ),
  ProviderDefinition(
    id: 'baichuan',
    name: 'Baichuan',
    shortName: 'BC',
    keyLabel: 'BAICHUAN_API_KEY',
    baseUrl: 'https://api.baichuan-ai.com/v1',
    models: ['Baichuan4', 'Baichuan3-Turbo'],
  ),
  ProviderDefinition(
    id: 'qianfan',
    name: 'Baidu Qianfan',
    shortName: 'BD',
    keyLabel: 'QIANFAN_API_KEY',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    models: ['ernie-4.0-turbo-8k', 'ernie-3.5-8k'],
  ),
  ProviderDefinition(
    id: 'volcengine',
    name: 'Volcengine Ark',
    shortName: 'VK',
    keyLabel: 'ARK_API_KEY',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    models: ['doubao-1-5-pro-32k', 'deepseek-r1-250120'],
  ),
  ProviderDefinition(
    id: 'lepton',
    name: 'Lepton AI',
    shortName: 'LP',
    keyLabel: 'LEPTON_API_KEY',
    baseUrl: 'https://api.lepton.ai/v1',
    models: ['llama3.1-70b', 'deepseek-r1'],
  ),
  ProviderDefinition(
    id: 'lambda',
    name: 'Lambda Inference',
    shortName: 'LA',
    keyLabel: 'LAMBDA_API_KEY',
    baseUrl: 'https://api.lambdalabs.com/v1',
    models: ['llama3.1-405b-instruct-fp8', 'hermes3-405b'],
  ),
  ProviderDefinition(
    id: 'ollama',
    name: 'Ollama Local',
    shortName: 'OL',
    keyLabel: 'OLLAMA_API_KEY',
    baseUrl: 'http://127.0.0.1:11434/v1',
    models: ['llama3.2', 'qwen2.5', 'mistral'],
    requiresKey: false,
  ),
  ProviderDefinition(
    id: 'lmstudio',
    name: 'LM Studio Local',
    shortName: 'LM',
    keyLabel: 'LMSTUDIO_API_KEY',
    baseUrl: 'http://127.0.0.1:1234/v1',
    models: ['local-model'],
    requiresKey: false,
  ),
  ProviderDefinition(
    id: 'vllm',
    name: 'vLLM Server',
    shortName: 'VL',
    keyLabel: 'VLLM_API_KEY',
    baseUrl: 'http://127.0.0.1:8000/v1',
    models: ['served-model'],
    requiresKey: false,
  ),
  ProviderDefinition(
    id: 'custom',
    name: 'Custom OpenAI-Compatible',
    shortName: 'CU',
    keyLabel: 'CUSTOM_API_KEY',
    baseUrl: 'https://example.com/v1',
    models: ['custom-model'],
  ),
  ProviderDefinition(
    id: 'kaggle',
    name: 'Kaggle (Free GPU) [If you don\'t have API key]',
    shortName: 'KG',
    keyLabel: 'KAGGLE_API_KEY',
    baseUrl: 'https://your-kaggle-tunnel.trycloudflare.com/v1',
    models: ['Qwen3.8-27B'],
    requiresKey: true,
    isKaggle: true,
  ),
];
