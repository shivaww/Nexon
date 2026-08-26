// Extracted from main.dart lines 17860-18813
// Extracted on: 2026-08-26T18:20:45.699661

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nexon/main.dart';
import 'package:nexon/data/models/provider_models.dart';

class ChatClient {
  /// Shared keep-alive HTTP client: reuses TCP/TLS connections across
  /// chat turns so each request skips a full handshake.
  static final HttpClient _sharedHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 60)
    ..autoUncompress = true;

  /// Models that accept image input (multimodal/vision).
  static final Set<String> modelsWithVision = {};

  /// Models that can generate images from text (text-to-image).
  static final Set<String> modelsWithImageGeneration = {};

  /// Models that can generate videos from text (text-to-video).
  static final Set<String> modelsWithVideoGeneration = {};

  static final liveDailyPool = ValueNotifier<int?>(null);
  static final liveSubscriptionCredits = ValueNotifier<int?>(null);
  static final liveTopupCredits = ValueNotifier<int?>(null);

  /// Translates raw HTTP status codes into user-friendly error messages.
  static String _friendlyLlmError(int statusCode, String body) {
    switch (statusCode) {
      case 401:
      case 403:
        return 'Authentication failed. Check your API key for this provider.';
      case 404:
        return 'Model not found. This model may not be available on the selected provider. Try another model.';
      case 402:
        return 'Insufficient credits or quota exceeded for this provider.';
      case 429:
        return 'Rate limited. The provider is temporarily busy — try again in a moment.';
      case 500:
      case 502:
      case 503:
      case 529:
        return 'Temporarily unavailable from provider. Try another model or wait a moment.';
      default:
        return 'Provider error (HTTP $statusCode). Try another model or check your connection.';
    }
  }

  static Future<void> fetchLiveWallet() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final response = await Supabase.instance.client
          .from('user_wallets')
          .select('current_daily_pool, subscription_credits, topup_credits')
          .eq('user_id', session.user.id)
          .maybeSingle();
      if (response != null) {
        liveDailyPool.value = response['current_daily_pool'] as int?;
        liveSubscriptionCredits.value =
            response['subscription_credits'] as int?;
        liveTopupCredits.value = response['topup_credits'] as int?;
      }
    } catch (e) {
      // Ignored
    }
  }

  Future<List<String>> fetchModels(
    ProviderDefinition provider,
    ProviderSettings settings,
  ) async {
    final client = _sharedHttpClient;
    try {
      final uri = Uri.parse('${_baseUrl(provider, settings)}/models');
      final request = await client.getUrl(uri);
      _setHeaders(request, provider, settings, settings.apiKey, stream: false);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_friendlyLlmError(response.statusCode, body));
      }
      final decoded = jsonDecode(body);

      // ── OpenAI-compatible /v1/models → {"data": [...]} ──
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is List) {
        final names = <String>[];
        for (final item in data) {
          if (item is String) {
            names.add(item);
            continue;
          }
          if (item is! Map) continue;
          final id = item['id']?.toString() ?? '';
          if (id.isEmpty) continue;

          // OpenRouter-style architecture.modality field.
          // Format: "<inputs>-><outputs>" e.g. "text+image->text"
          // or "text->image" for image generators.
          final arch = item['architecture'];
          if (arch is Map) {
            final modality = arch['modality']?.toString().toLowerCase() ?? '';
            if (modality.isNotEmpty) {
              final parts = modality.split('->');
              final inputPart = parts.first.trim();
              final outputPart = parts.length > 1
                  ? parts.last.trim()
                  : modality;

              // Detect text-to-image generation models
              if (outputPart.contains('image') &&
                  !outputPart.contains('text')) {
                ChatClient.modelsWithImageGeneration.add(id);
                // Don't add to text list — these are pure image generators
                continue;
              }

              // Detect text-to-video generation models
              if (outputPart.contains('video') &&
                  !outputPart.contains('text')) {
                ChatClient.modelsWithVideoGeneration.add(id);
                // Don't add to text list — these are pure video generators
                continue;
              }

              // Skip models that produce neither text, image, nor video
              if (!outputPart.contains('text') &&
                  !outputPart.contains('image') &&
                  !outputPart.contains('video')) {
                continue;
              }

              // Detect vision input (image-in + text-out)
              if (inputPart.contains('image') || inputPart.contains('vision')) {
                ChatClient.modelsWithVision.add(id);
              }
            }
          }

          // Some providers expose capabilities/input_modalities/output_modalities arrays
          final inputCaps = item['input_modalities'] ?? item['capabilities'];
          if (inputCaps is List) {
            for (final cap in inputCaps) {
              final capStr = cap.toString().toLowerCase();
              if (capStr.contains('image') || capStr.contains('vision')) {
                ChatClient.modelsWithVision.add(id);
              }
            }
          }
          final outputCaps = item['output_modalities'];
          if (outputCaps is List) {
            for (final cap in outputCaps) {
              final capStr = cap.toString().toLowerCase();
              if (capStr.contains('image') && !capStr.contains('text')) {
                ChatClient.modelsWithImageGeneration.add(id);
              }
              if (capStr.contains('video') && !capStr.contains('text')) {
                ChatClient.modelsWithVideoGeneration.add(id);
              }
            }
          }

          names.add(id);
        }
        return names.where((m) => m.trim().isNotEmpty).toSet().toList();
      }

      // ── Ollama /api/tags → {"models": [{"name":..., "details":{...}}]} ──
      if (decoded is Map<String, dynamic> && decoded['models'] is List) {
        final names = <String>[];
        for (final item in (decoded['models'] as List)) {
          String name = '';
          if (item is String) {
            name = item;
          } else if (item is Map) {
            name = (item['name'] ?? item['id'] ?? '').toString();
            // Ollama exposes model families in details.families
            // Models with 'clip' family support image input (LLaVA, Gemma3, etc.)
            final details = item['details'];
            if (details is Map) {
              final families = details['families'];
              if (families is List) {
                for (final fam in families) {
                  final famStr = fam.toString().toLowerCase();
                  if (famStr == 'clip' ||
                      famStr.contains('vision') ||
                      famStr.contains('vl')) {
                    ChatClient.modelsWithVision.add(name);
                  }
                }
              }
            }
            // Also check model info capabilities if available
            final caps = item['capabilities'];
            if (caps is List) {
              for (final cap in caps) {
                final capStr = cap.toString().toLowerCase();
                if (capStr == 'vision' ||
                    capStr.contains('image') ||
                    capStr.contains('vision')) {
                  ChatClient.modelsWithVision.add(name);
                }
              }
            }
          }
          if (name.trim().isNotEmpty) names.add(name);
        }
        return names.where((m) => m.trim().isNotEmpty).toSet().toList();
      }

      return provider.models;
    } finally {
      // Shared keep-alive client — intentionally not closed.
    }
  }

  Future<String> sendChat({
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    required List<ChatMessage> messages,
    bool studyModeEnabled = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isManagedMode = provider.id == 'nexon';
    final managedUrl =
        prefs.getString('nexon_managed_backend_url') ??
        'https://nexon-jyp1.onrender.com';
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken ?? '';

    final client = _sharedHttpClient;
    try {
      final allKeys = isManagedMode
          ? [token]
          : [
              settings.apiKey,
              ...settings.fallbackApiKeys,
            ].map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
      if (allKeys.isEmpty) allKeys.add('');

      for (int i = 0; i < allKeys.length; i++) {
        final currentKey = allKeys[i];

        bool success = false;
        Exception? lastException;
        String? responseText;

        for (int retry = 0; retry < 3; retry++) {
          try {
            final baseUrl = isManagedMode
                ? managedUrl
                : _baseUrl(provider, settings);
            final urlString = baseUrl.endsWith('/v1')
                ? '$baseUrl/chat/completions'
                : '$baseUrl/v1/chat/completions';
            final uri = Uri.parse(urlString);
            final request = await client.postUrl(uri);
            _setHeaders(
              request,
              provider,
              settings,
              currentKey,
              stream: false,
              isManaged: isManagedMode,
            );
            request.headers.contentType = ContentType.json;

            final payload = <String, dynamic>{
              'model': model,
              'messages': messages.map((message) {
                String finalText = message.text;
                // In study mode, workspace files are NOT inlined — LLM queries them via tools.
                final inlineFiles = studyModeEnabled
                    ? message.files.where((f) => !f.isWorkspaceFile).toList()
                    : message.files;
                if (inlineFiles.isNotEmpty) {
                  finalText += '\n\n';
                  for (final file in inlineFiles) {
                    finalText +=
                        '--- File: ${file.name} ---\n${file.content}\n\n';
                  }
                }

                if (message.images.isNotEmpty) {
                  return {
                    'role': message.role.apiName,
                    'content': [
                      {'type': 'text', 'text': finalText},
                      ...message.images.map(
                        (img) => {
                          'type': 'image_url',
                          'image_url': {'url': 'data:image/jpeg;base64,$img'},
                        },
                      ),
                    ],
                  };
                }
                return {'role': message.role.apiName, 'content': finalText};
              }).toList(),
              'max_tokens': settings.maxTokens,
              'temperature': 1.0,
              'top_p': 0.95,
              'stream': false,
            };
            // IMPROVEMENT: Enable thinking/reasoning for all capable models/providers
            _applyReasoningParams(payload, provider, settings, model);

            final payloadBytes = utf8.encode(jsonEncode(payload));
            request.headers.contentLength = payloadBytes.length;
            request.add(payloadBytes);
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();

            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic> &&
                decoded.containsKey('credits_status')) {
              final status = decoded['credits_status'];
              liveDailyPool.value = status['daily'] as int?;
              liveSubscriptionCredits.value = status['subscription'] as int?;
              liveTopupCredits.value = status['topup'] as int?;
            }
            responseText = _extractAnswer(decoded);
            success = true;
            break;
          } catch (e) {
            lastException = e is Exception ? e : Exception(e.toString());
            final errorStr = e.toString().toLowerCase();
            if (errorStr.contains('402')) {
              throw lastException ?? Exception('Payment Required (402)');
            }
            final isRateLimit =
                errorStr.contains('429') ||
                errorStr.contains('500') ||
                errorStr.contains('503');
            if (!isRateLimit) break;
            if (retry < 2) await Future.delayed(const Duration(seconds: 20));
          }
        }

        if (success && responseText != null) return responseText;

        final errorStr = lastException.toString().toLowerCase();
        if (errorStr.contains('402')) {
          throw lastException ?? Exception('Payment Required (402)');
        }
        final isRateLimit =
            errorStr.contains('429') ||
            errorStr.contains('500') ||
            errorStr.contains('503');
        if (!isRateLimit || i == allKeys.length - 1) {
          throw lastException ?? Exception('Unknown error');
        }
      }
      throw const HttpException(
        'Failed to send request with any provided API key',
      );
    } finally {
      // Shared keep-alive client — intentionally not closed.
    }
  }

  Stream<String> sendChatStream({
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    required List<ChatMessage> messages,
    bool studyModeEnabled = false,
  }) async* {
    final prefs = await SharedPreferences.getInstance();
    final isManagedMode = provider.id == 'nexon';
    final managedUrl =
        prefs.getString('nexon_managed_backend_url') ??
        'https://nexon-jyp1.onrender.com';
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken ?? '';

    final client = _sharedHttpClient;
    try {
      final allKeys = isManagedMode
          ? [token]
          : [
              settings.apiKey,
              ...settings.fallbackApiKeys,
            ].map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
      if (allKeys.isEmpty) allKeys.add('');

      for (int i = 0; i < allKeys.length; i++) {
        final currentKey = allKeys[i];

        HttpClientResponse? response;
        bool success = false;
        Exception? lastException;

        for (int retry = 0; retry < 3; retry++) {
          try {
            final baseUrl = isManagedMode
                ? managedUrl
                : _baseUrl(provider, settings);
            final urlString = baseUrl.endsWith('/v1')
                ? '$baseUrl/chat/completions'
                : '$baseUrl/v1/chat/completions';
            final uri = Uri.parse(urlString);
            final request = await client.postUrl(uri);
            _setHeaders(
              request,
              provider,
              settings,
              currentKey,
              stream: true,
              isManaged: isManagedMode,
            );
            request.headers.contentType = ContentType.json;

            final payload = <String, dynamic>{
              'model': model,
              'messages': messages.map((message) {
                String finalText = message.text;
                // In study mode, workspace files are NOT inlined — LLM queries them via tools.
                final inlineFiles = studyModeEnabled
                    ? message.files.where((f) => !f.isWorkspaceFile).toList()
                    : message.files;
                if (inlineFiles.isNotEmpty) {
                  finalText += '\n\n';
                  for (final file in inlineFiles) {
                    finalText +=
                        '--- File: ${file.name} ---\n${file.content}\n\n';
                  }
                }

                if (message.images.isNotEmpty) {
                  return {
                    'role': message.role.apiName,
                    'content': [
                      {'type': 'text', 'text': finalText},
                      ...message.images.map(
                        (img) => {
                          'type': 'image_url',
                          'image_url': {'url': 'data:image/jpeg;base64,$img'},
                        },
                      ),
                    ],
                  };
                }
                return {'role': message.role.apiName, 'content': finalText};
              }).toList(),
              'max_tokens': settings.maxTokens,
              'temperature': 1.0,
              'top_p': 0.95,
              'stream': true,
            };
            // IMPROVEMENT: Enable thinking/reasoning for all capable models/providers
            _applyReasoningParams(payload, provider, settings, model);

            final payloadBytes = utf8.encode(jsonEncode(payload));
            request.headers.contentLength = payloadBytes.length;
            request.add(payloadBytes);
            response = await request.close();

            if (response.statusCode < 200 || response.statusCode >= 300) {
              final body = await response.transform(utf8.decoder).join();
              throw HttpException(_friendlyLlmError(response.statusCode, body));
            }
            success = true;
            break;
          } catch (e) {
            lastException = e is Exception ? e : Exception(e.toString());
            final errorStr = e.toString().toLowerCase();
            if (errorStr.contains('402')) {
              throw lastException ?? Exception('Payment Required (402)');
            }
            final isRateLimit =
                errorStr.contains('429') ||
                errorStr.contains('500') ||
                errorStr.contains('503');
            if (!isRateLimit) break;
            if (retry < 2) await Future.delayed(const Duration(seconds: 20));
          }
        }

        if (!success || response == null) {
          final errorStr = lastException.toString().toLowerCase();
          if (errorStr.contains('402')) {
            throw lastException ?? Exception('Payment Required (402)');
          }
          final isRateLimit =
              errorStr.contains('429') ||
              errorStr.contains('500') ||
              errorStr.contains('503');
          if (!isRateLimit || i == allKeys.length - 1) {
            throw lastException ?? Exception('Unknown error');
          }
          continue; // Try next key
        }

        // If we reach here, the response was successful
        final lines = response
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty) continue;
          if (trimmedLine.startsWith('data:')) {
            final dataStr = trimmedLine.substring(5).trim();
            if (dataStr == '[DONE]') {
              break;
            }
            try {
              final decoded = jsonDecode(dataStr);
              if (decoded is Map<String, dynamic>) {
                if (decoded.containsKey('credits_status')) {
                  final status = decoded['credits_status'];
                  liveDailyPool.value = status['daily'] as int?;
                  liveSubscriptionCredits.value =
                      status['subscription'] as int?;
                  liveTopupCredits.value = status['topup'] as int?;
                  continue;
                }
                final choices = decoded['choices'];
                if (choices is List && choices.isNotEmpty) {
                  final first = choices.first;
                  if (first is Map) {
                    final delta = first['delta'];
                    if (delta is Map) {
                      if (delta['reasoning_content'] != null) {
                        yield '[REASONING]${delta['reasoning_content']}';
                      } else if (delta['content'] != null) {
                        yield delta['content'].toString();
                      } else if (first['text'] != null) {
                        yield first['text'].toString();
                      }
                    }
                  }
                }
              }
            } catch (_) {}
          }
        }
        break; // Successfully streamed, do not try next key
      }
    } finally {
      // Shared keep-alive client — intentionally not closed.
    }
  }

  Future<String> searchWeb(
    String query,
    String provider,
    List<String> apiKeys, {
    String? googleCx,
    String? topic,
    String? timeRange,
    String? startDate,
    String? endDate,
    String? searchDepth,
    List<CustomSearchProvider> customProviders = const [],
  }) async {
    final client = HttpClient()
      ..findProxy = ((uri) => "DIRECT")
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final keys = apiKeys.where((k) => k.trim().isNotEmpty).toList();
      if (keys.isEmpty) keys.add('');

      for (int i = 0; i < keys.length; i++) {
        final currentKey = keys[i];
        try {
          if (provider == 'tavily') {
            final uri = Uri.parse('https://api.tavily.com/search');
            final request = await client.postUrl(uri);
            request.headers.contentType = ContentType.json;

            // Map timeRange aliases
            String? trVal = timeRange;
            if (trVal != null) {
              final tr = trVal.trim().toLowerCase();
              if (tr == 'd')
                trVal = 'day';
              else if (tr == 'w')
                trVal = 'week';
              else if (tr == 'm')
                trVal = 'month';
              else if (tr == 'y')
                trVal = 'year';
              else
                trVal = tr;
            }

            // Give current-events queries a current, thorough result set even
            // if the model omitted optional search attributes.
            final isFreshQuery = RegExp(
              r'\b(latest|recent|current|today|news|update|updated|release|price|pricing|202\d)\b',
              caseSensitive: false,
            ).hasMatch(query);
            final effectiveTopic = topic ?? (isFreshQuery ? 'news' : null);
            final effectiveTimeRange = trVal ?? (isFreshQuery ? 'month' : null);
            final effectiveDepth =
                searchDepth == 'advanced' || searchDepth == 'basic'
                ? searchDepth!
                : (isFreshQuery ? 'advanced' : 'basic');

            final Map<String, dynamic> payload = {
              'api_key': currentKey,
              'query': query,
              'max_results': 6,
              'search_depth': effectiveDepth,
            };
            if (effectiveTopic != null) payload['topic'] = effectiveTopic;
            if (effectiveTimeRange != null)
              payload['time_range'] = effectiveTimeRange;
            if (startDate != null) payload['start_date'] = startDate;
            if (endDate != null) payload['end_date'] = endDate;

            request.write(jsonEncode(payload));
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['results'] is List) {
              final results = decoded['results'] as List;
              return results
                  .map((r) {
                    final publishedDate = r is Map
                        ? r['published_date']?.toString()
                        : null;
                    final datePrefix =
                        publishedDate == null || publishedDate.isEmpty
                        ? ''
                        : 'Published $publishedDate — ';
                    return '- [${r['title']}](${r['url']}): $datePrefix${r['content']}';
                  })
                  .join('\n\n');
            }
          } else if (provider == 'exa') {
            final uri = Uri.parse('https://api.exa.ai/search');
            final request = await client.postUrl(uri);
            request.headers.set('x-api-key', currentKey);
            request.headers.contentType = ContentType.json;
            request.write(
              jsonEncode({'query': query, 'numResults': 4, 'text': true}),
            );
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['results'] is List) {
              final results = decoded['results'] as List;
              return results
                  .map(
                    (r) =>
                        '- [${r['title']}](${r['url']}): ${r['text'] ?? r['highlights']?.first ?? ''}',
                  )
                  .join('\n\n');
            }
          } else if (provider == 'firecrawl') {
            final uri = Uri.parse('https://api.firecrawl.dev/v1/search');
            final request = await client.postUrl(uri);
            request.headers.set('Authorization', 'Bearer $currentKey');
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode({'query': query, 'limit': 4}));
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['data'] is List) {
              final results = decoded['data'] as List;
              return results
                  .map(
                    (r) =>
                        '- [${r['title'] ?? r['metadata']?['title']}](${r['url'] ?? r['metadata']?['source']}): ${r['markdown'] ?? r['snippet'] ?? ''}',
                  )
                  .join('\n\n');
            }
          } else if (provider == 'google') {
            final uri = Uri.parse(
              'https://www.googleapis.com/customsearch/v1?key=$currentKey&cx=${googleCx ?? ''}&q=${Uri.encodeComponent(query)}',
            );
            final request = await client.getUrl(uri);
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['items'] is List) {
              final results = decoded['items'] as List;
              return results
                  .map(
                    (r) => '- [${r['title']}](${r['link']}): ${r['snippet']}',
                  )
                  .join('\n\n');
            }
          } else if (provider.startsWith('custom:')) {
            final customId = provider.substring(7);
            final cp = customProviders.firstWhere(
              (p) => p.id == customId,
              orElse: () => throw Exception('Unknown custom search provider: $customId'),
            );
            final uri = Uri.parse(cp.endpoint);
            final request = cp.method.toUpperCase() == 'GET'
                ? await client.getUrl(Uri.parse(
                    '$cp.endpoint?${cp.queryParam}=${Uri.encodeComponent(query)}'
                    '${cp.extraParams.entries.map((e) => '&${e.key}=${Uri.encodeComponent(e.value)}').join('')}'
                  ))
                : await client.postUrl(uri);
            if (cp.method.toUpperCase() == 'GET') {
              if (currentKey.isNotEmpty) {
                request.headers.set(cp.apiKeyHeader, '$cp.apiKeyPrefix$currentKey');
              }
            } else {
              request.headers.contentType = ContentType.json;
              if (currentKey.isNotEmpty) {
                request.headers.set(cp.apiKeyHeader, '$cp.apiKeyPrefix$currentKey');
              }
              final payload = <String, dynamic>{
                cp.queryParam: query,
                ...cp.extraParams,
              };
              request.write(jsonEncode(payload));
            }
            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }
            final decoded = jsonDecode(body);
            List<dynamic> rawResults;
            if (cp.resultsPath.contains('.')) {
              dynamic node = decoded;
              for (final part in cp.resultsPath.split('.')) {
                node = (node as Map)?[part];
              }
              rawResults = node is List ? node : [];
            } else {
              rawResults = (decoded is Map ? decoded[cp.resultsPath] : null) as List? ?? [];
            }
            return rawResults.map((r) {
              final item = r as Map;
              return '- [${item[cp.titleField] ?? ""}](${item[cp.urlField] ?? ""}): ${item[cp.snippetField] ?? ""}';
            }).take(6).join('\n\n');
          } else if (provider == 'duckduckgo') {
            final uri = Uri.parse('https://lite.duckduckgo.com/lite/');
            final request = await client.postUrl(uri);
            request.headers.contentType = ContentType(
              'application',
              'x-www-form-urlencoded',
            );
            request.headers.set(
              'User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            );
            final bodyBytes = utf8.encode(
              'q=${Uri.encodeQueryComponent(query)}',
            );
            request.headers.contentLength = bodyBytes.length;
            request.add(bodyBytes);

            final response = await request.close();
            final body = await response.transform(utf8.decoder).join();

            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('HTTP ${response.statusCode}: $body');
            }

            final results = <String>[];
            final resultRegex = RegExp(
              r"""<a\s+rel="nofollow"\s+href="([^"]+)"\s+class='result-link'>([\s\S]*?)</a>[\s\S]*?<td\s+class='result-snippet'>([\s\S]*?)</td>""",
              caseSensitive: false,
            );
            final matches = resultRegex.allMatches(body);
            for (final match in matches) {
              var rawUrl = match.group(1) ?? '';
              var title = match.group(2) ?? '';
              var snippet = match.group(3) ?? '';

              title = title
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&amp;', '&')
                  .trim();
              snippet = snippet
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&amp;', '&')
                  .trim();

              var decodedUrl = rawUrl;
              if (rawUrl.contains('uddg=')) {
                final uddgIndex = rawUrl.indexOf('uddg=') + 5;
                final ampIndex = rawUrl.indexOf('&', uddgIndex);
                final encodedUrl = (ampIndex != -1)
                    ? rawUrl.substring(uddgIndex, ampIndex)
                    : rawUrl.substring(uddgIndex);
                decodedUrl = Uri.decodeComponent(encodedUrl);
              } else if (rawUrl.startsWith('//')) {
                decodedUrl = 'https:$rawUrl';
              }

              if (decodedUrl.isNotEmpty && title.isNotEmpty) {
                results.add('- [$title]($decodedUrl): $snippet');
              }
              if (results.length >= 4) break;
            }

            if (results.isNotEmpty) {
              return results.join('\n\n');
            } else {
              throw Exception('No search results found on DuckDuckGo');
            }
          }
        } catch (e) {
          if (i < keys.length - 1) {
            debugPrint(
              'Search failed with key index $i: $e. Trying fallback key.',
            );
            continue;
          }
          rethrow;
        }
      }
      return 'No search results found.';
    } catch (e) {
      if (provider == 'tavily') {
        debugPrint('Tavily search failed: $e. Falling back to DuckDuckGo...');
        try {
          return await searchWeb(query, 'duckduckgo', ['']);
        } catch (fallbackError) {
          return 'Web search failed: $fallbackError';
        }
      }
      return 'Web search failed: $e';
    } finally {
      client.close(force: true);
    }
  }

  /// IMPROVEMENT: Applies provider/model-specific reasoning parameters.
  /// Detects thinking-capable models by name pattern and adds the correct
  /// API parameters for each provider's reasoning format.
  void _applyReasoningParams(
    Map<String, dynamic> payload,
    ProviderDefinition provider,
    ProviderSettings settings,
    String model,
  ) {
    if (!settings.reasoningEnabled) return;
    final modelLower = model.toLowerCase();

    // OpenAI o-series reasoning models: no temperature, use reasoning_effort
    if (modelLower.contains('o1') ||
        modelLower.contains('o3') ||
        modelLower.contains('o4')) {
      payload.remove('temperature');
      payload.remove('top_p');
      payload['reasoning_effort'] = 'high';
      return;
    }

    // DeepSeek reasoning models
    if (modelLower.contains('deepseek-r1') ||
        modelLower.contains('deepseek-reasoner') ||
        modelLower.contains('r1-')) {
      payload['enable_thinking'] = true;
      return;
    }

    // Anthropic Claude with extended thinking (via OpenAI-compatible proxy)
    if (modelLower.contains('claude') &&
        (modelLower.contains('thinking') || provider.id == 'anthropic')) {
      payload['thinking'] = {
        'type': 'enabled',
        'budget_tokens': (settings.maxTokens * 0.6).round().clamp(1024, 32768),
      };
      payload.remove('temperature');
      return;
    }

    // OpenRouter: include_reasoning flag
    if (provider.id == 'openrouter') {
      payload['include_reasoning'] = true;
      return;
    }

    // Generic OpenAI-compatible endpoints that support enable_thinking
    // (e.g., Together AI, Groq with reasoning models, local llama.cpp)
    if (modelLower.contains('think') ||
        modelLower.contains('reason') ||
        modelLower.contains('qwq') ||
        modelLower.contains('qwen3')) {
      payload['enable_thinking'] = true;
    }
  }

  String _baseUrl(ProviderDefinition provider, ProviderSettings settings) {
    final raw = settings.baseUrl.trim().isEmpty
        ? provider.baseUrl
        : settings.baseUrl.trim();
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  void _setHeaders(
    HttpClientRequest request,
    ProviderDefinition provider,
    ProviderSettings settings,
    String activeApiKey, {
    required bool stream,
    bool isManaged = false,
  }) {
    request.headers.set(
      'Accept',
      stream ? 'text/event-stream' : 'application/json',
    );
    if (stream) {
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set('Connection', 'keep-alive');
    }
    if (activeApiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $activeApiKey');
      if (provider.id == 'sarvam') {
        request.headers.set('api-subscription-key', activeApiKey);
      }
    }
    if (!isManaged) {
      for (final entry in provider.extraHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
    }
  }

  String _extractAnswer(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return decoded.toString();
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] != null) {
          final content = message['content'];
          if (content is String) return content;
          return jsonEncode(content);
        }
        if (first['text'] != null) return first['text'].toString();
      }
    }
    if (decoded['output_text'] != null)
      return decoded['output_text'].toString();
    if (decoded['content'] != null) return decoded['content'].toString();
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }
}
