import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:nexon/widgets/scrollable_table_builder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/widgets/diff_viewer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:path_provider/path_provider.dart';
import 'package:docx_creator/docx_creator.dart' hide PdfDocument;

import 'package:nexon/widgets/nexon_chart.dart';
import 'package:nexon/services/drive_sync_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nexon/screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tvrqxugomnjthqrcdaih.supabase.co',
    anonKey: 'sb_publishable_AmHw2HDm_ZpxRt4jOlb-EA_vaVRTSG_',
  );

  final prefs = await SharedPreferences.getInstance();
  bool hasCompletedOnboarding =
      prefs.getBool('has_completed_onboarding_v2') ?? false;

  final session = Supabase.instance.client.auth.currentSession;
  if (hasCompletedOnboarding && session == null) {
    hasCompletedOnboarding = false;
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF7F2E8),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(ForgeChatApp(hasCompletedOnboarding: hasCompletedOnboarding));
}

class ForgeChatApp extends StatefulWidget {
  final bool hasCompletedOnboarding;
  const ForgeChatApp({super.key, required this.hasCompletedOnboarding});

  @override
  State<ForgeChatApp> createState() => _ForgeChatAppState();
}

class _ForgeChatAppState extends State<ForgeChatApp> {
  late bool _showOnboarding;

  @override
  void initState() {
    super.initState();
    _showOnboarding = !widget.hasCompletedOnboarding;
  }

  void _completeOnboarding() {
    setState(() {
      _showOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseText = GoogleFonts.manropeTextTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nexon',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B4E2E),
          brightness: Brightness.light,
          surface: const Color(0xFFFFFBF2),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F2E8),
        textTheme: baseText,
      ),
      home: _showOnboarding
          ? OnboardingScreen(onComplete: _completeOnboarding)
          : const ChatHomePage(),
    );
  }
}

class DeepResearchPrompts {
  static const String plannerSystemPrompt = """ROLE: Planner. No searching, no fetching. Output XML only.
Decide: complexity (STANDARD/COMPLEX), stage_count (5-15) based on user query.
Generate a phase-by-phase research plan.
Output format:
<research_plan>
  <phase1>Stage Title - Detailed goal and instructions for this phase</phase1>
  <phase2>Stage Title - Detailed goal and instructions for this phase</phase2>
  ...
</research_plan>
No text outside the XML tags. Each phase tag MUST match the phase number, e.g. <phase1>...</phase1>, <phase2>...</phase2>. Do not include reasoning or preamble outside the XML.""";

  static const String researchSystemPrompt = """ROLE: Research agent. You are running one phase of a multi-step research plan.
Your task is to gather enough relevant information to fully address the phase's prompt.
You have the following tools available:
1. Web Search: Output <search_request>your query</search_request> to get a list of search results.
   To configure search parameters, you can add optional XML attributes:
   - topic: "general" (default) or "news" (specifically for news articles, applying recency-weighted ranking).
   - time_range: "day" / "d", "week" / "w", "month" / "m", or "year" / "y" to limit search results to a specific timeframe.
   - start_date / end_date: specific date bounds (e.g. YYYY-MM-DD).
   - search_depth: "basic" (default, fast/credit-friendly) or "advanced" (thorough/expensive).
   Examples:
   - Recent query: <search_request time_range="month" topic="news">latest SWE-bench scores 2026</search_request>
   - Date-bounded query: <search_request start_date="2026-07-01" end_date="2026-07-15">termux release issues</search_request>
   - Foundational query: <search_request>how does symlink work in android termux</search_request>
2. Fetch Page: Output <read_url>URL</read_url> to fetch page content in depth.
   Example: <read_url>https://example.com/git-guide</read_url>

TOOL LIMITS PER PHASE:
1. You may call web_search up to 20 times and read_url up to 5 times within a single research phase. These are hard limits enforced by the system — once reached, further calls will be rejected with a limit-reached message.
2. Functional Difference:
   - web_search returns short snippets across many sources cheaply. Use it for breadth/surveying to find candidate sources.
   - read_url fetches and summarizes one full page in depth. It is expensive and capped low, so use it selectively for depth on your best 5 leads only. Do not treat them interchangeably.
3. PDF Exclusions: PDFs are not supported by read_url and will be automatically skipped — prefer HTML sources when a choice exists.

CRITICAL DIRECTIVES:
1. You MUST invoke web_search and read_url tools using the dedicated <search_request> and <read_url> tags.
2. Do NOT invent alternative tool-call syntaxes. Use ONLY the exact XML tag formats shown above.
3. You must run searches and fetches iteratively.
4. Selection of Search parameters:
   - For recent/current-events-flavored queries (product releases, benchmark results, pricing, "latest", "current", "2026"), default to time_range="month" or topic="news".
   - For general/foundational/definitional queries (explaining a concept, historical background), omit time_range entirely to avoid artificially excluding older-but-still-correct foundational sources.
5. Once you have collected enough info for this phase, output <step_complete/> to finish the phase.
6. You can output multiple `<search_request>` tags (or multiple `<read_url>` tags) in a single response to execute them in parallel. Do not mix search and read url tags in the same message. Wait for the user response after each action.""";

  static const String summarizerSystemPrompt = """ROLE: Summarization agent.
Extract information from the provided source. Output ONLY a valid JSON object matching the schema below.
Rules:
1. Extract only FACT records for numeric/named/comparable claims (such as benchmark scores, dates, prices, version numbers, named comparisons).
   Format of each FACT record:
   {
     "metric": "<name>",
     "subject": "<entity>",
     "value": "<value>",
     "date": "<date or null>",
     "source": "<url>"
   }
2. Extract FINDING records for qualitative content (arguments, explanations, context). Each FINDING must be capped at 1-2 sentences, tightly compressed, citing the source URL.
   Format of each FINDING record:
   {
     "text": "<1-2 sentences qualitative content>",
     "source": "<url>"
   }
3. NEVER include a comparative claim ("better than", "outperforms", "leading", "the best", etc.) inside a single-source summary. Comparisons are only valid across multiple records sharing the exact same metric, and will be compiled later.
4. Be strictly literal to what the source actually states — no inference, no filling gaps, no adding context.
5. If the source is empty or has no relevant info, return empty arrays.

Expected JSON output format:
{
  "facts": [ ... ],
  "findings": [ ... ]
}
No other text, explanations, or Markdown code blocks outside the JSON.""";

  static const String reflectorSystemPrompt = """ROLE: Research Sufficiency Judger.
You are given a research phase goal and the facts & findings gathered so far in this phase.
Your task is to judge if the gathered information is sufficient to fully address the phase goal.
Output ONLY a JSON object:
{
  "sufficient": true | false,
  "reason": "<short explanation>"
}
Do not include any other text or Markdown code blocks.""";

  static const String writerSystemPrompt = """ROLE: Writer.
Input: full temp.json content (all phases containing phase_title, facts, findings, skipped_pdfs, failed_fetches).
Read all facts and findings. Decide a hierarchical document structure: Chapter per stage, subsections (1.1, 1.2, ...) per sub-topic. Write the final research document as Markdown with proper chapter/subsection headers.

CRITICAL GUARDRAIL:
You may only state a comparison between two subjects if two or more FACT records in the evidence share the exact same metric name. In that case, state only the numeric comparison as given by the records (e.g. 'X scored 92% vs Y's 88% on SWE-bench-Verified') — do not add qualitative judgment language ('significantly better', 'clearly superior') beyond what the numbers themselves show. Never invent a comparison, ranking, or superiority claim not directly supported by two or more matching FACT records. If only one data point exists for a metric, state it standalone without comparison.

Ensure you write detailed paragraphs for each section, citing the URLs in brackets (e.g. [https://example.com]). List all sources at the end. Output plain Markdown only: do not generate SVG, HTML, Mermaid, or image-based visuals.""";
}

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  static final _secureStorage = const FlutterSecureStorage();
  static const _settingsKey = 'provider_settings_v1';
  static const _selectedProviderKey = 'selected_provider_id';

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatClient = ChatClient();

  SharedPreferences? _prefs;
  Map<String, ProviderSettings> _settings = {};
  final Map<String, List<String>> _modelCache = {};
  var _selectedProviderId = providerCatalog.first.id;
  final Set<String> _sendingSessionIds = {};
  var _isFetchingModels = false;
  SearchSettings _searchSettings = SearchSettings.defaults();
  bool _agenticEnabled = true;
  bool _artifactsEnabled = true;
  bool _svgVisualsEnabled = true;
  // Shell command permission: 'ask', 'session', 'always', 'never'
  String _shellPermission = 'ask';
  // Per-session always-allow flag (reset when app restarts)
  bool _shellSessionAllow = false;
  String _agenticWorkspace = '/data/data/com.termux/files/home';
  String _customMcpUrl = '';
  final Map<String, StreamSubscription<String>> _activeSubscriptions = {};
  final Map<String, Completer<void>> _activeCompleters = {};
  bool _deepResearchEnabled = false;
  /// User-configured token budget for writer-phase evidence (set in settings).
  int _writerContextBudget = 32000;
  static const int maxConcurrentFetchCalls = 6;
  // Bounded by fetch limit since backend is now decoupled and parallelised
  static const int maxConcurrentIngestCalls = 6;
  final SimpleSemaphore _ingestSemaphore = SimpleSemaphore(maxConcurrentIngestCalls);
  final Map<String, Map<String, dynamic>> _runUrlCache = {};

  String _normalizeQueryOrUrl(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\-\.\:\/]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<int> _getSystemAvailableRamBytes() async {
    final endpoint = _customMcpUrl.isNotEmpty ? _customMcpUrl : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 4));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'method': 'system_ram_headroom',
        'params': {},
      }));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 4));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['result'] is Map) {
        final result = decoded['result'] as Map;
        if (result.containsKey('available_bytes')) {
          return result['available_bytes'] as int;
        }
      }
    } catch (e) {
      debugPrint('Failed to query system RAM headroom: $e');
    } finally {
      client.close(force: true);
    }
    return 1024 * 1024 * 1024;
  }

  String _toolStatus = ''; // live tool status shown in UI banner

  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  int? _editingMessageIndex;

  List<ChatMessage> get _messages {
    if (_sessions.isEmpty) {
      _initDefaultSession();
    }
    final active = _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => _sessions.first,
    );
    return active.messages;
  }

  void _initDefaultSession() {
    final nextId = DateTime.now().millisecondsSinceEpoch.toString();
    final newSession = ChatSession(
      id: nextId,
      title: 'Welcome Chat',
      messages: [
        const ChatMessage(
          role: MessageRole.assistant,
          text:
              'Select a provider, add its API key, fetch or type a model, then start chatting.',
        ),
      ],
      providerId: _selectedProviderId,
      model: _activeModel,
    );
    _sessions = [newSession];
    _activeSessionId = newSession.id;
    _agenticEnabled = false;        // Default off for new chat
    _deepResearchEnabled = false;   // Default off for new chat
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_sessions_v1');
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final loadedSessions = decoded.map((s) => ChatSession.fromJson(s as Map<String, dynamic>)).toList();
        setState(() {
          _sessions = loadedSessions;

          // Check if the most recent session is already an empty new/welcome chat
          bool hasEmptySession = false;
          if (_sessions.isNotEmpty) {
            final first = _sessions.first;
            final userMsgs = first.messages.where((m) => m.role == MessageRole.user);
            if (userMsgs.isEmpty && (first.title == 'New Chat' || first.title == 'Welcome Chat')) {
              _activeSessionId = first.id;
              _agenticEnabled = false;        // Default off for new chat
              _deepResearchEnabled = false;   // Default off for new chat
              hasEmptySession = true;
            }
          }

          if (!hasEmptySession) {
            // Create a new fresh chat session on startup
            final newId = DateTime.now().millisecondsSinceEpoch.toString();
            final newSession = ChatSession(
              id: newId,
              title: 'New Chat',
              messages: [
                const ChatMessage(
                  role: MessageRole.assistant,
                  text: 'New chat ready. Choose any configured provider and model.',
                ),
              ],
              providerId: _selectedProviderId,
              model: _activeModel,
            );
            _sessions.insert(0, newSession);
            _activeSessionId = newId;
            _agenticEnabled = false;        // Default off for new chat
            _deepResearchEnabled = false;   // Default off for new chat
          }
          _editingMessageIndex = null;
        });
        _saveSessions(); // Save the new session layout
      } catch (_) {
        setState(() {
          _initDefaultSession();
        });
      }
    } else {
      setState(() {
        _initDefaultSession();
      });
    }
  }

  Future<void> _saveSessions() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final serialized = _sessions.map((s) => s.toJson()).toList();
    await prefs.setString('chat_sessions_v1', jsonEncode(serialized));
    if (_activeSessionId != null) {
      await prefs.setString('active_session_id_v1', _activeSessionId!);
    }

    // Fire and forget auto-sync to Google Drive
    DriveSyncService.syncToDrive(_sessions);
  }



  Future<void> _resetDeepResearch() async {
    final endpoint = _customMcpUrl.isNotEmpty ? _customMcpUrl : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'method': 'deep_research.reset',
        'params': <String, dynamic>{},
      }));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 15));
      await response.transform(utf8.decoder).join();
    } catch (e) {
      debugPrint("Failed to reset deep research on bridge: $e");
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _updateDeepResearchPhase({
    required String stageId,
    required String phaseTitle,
    required List<dynamic> facts,
    required List<dynamic> findings,
    required List<dynamic> skippedPdfs,
    required List<dynamic> failedFetches,
  }) async {
    final endpoint = _customMcpUrl.isNotEmpty ? _customMcpUrl : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.postUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 30));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'method': 'deep_research.update_phase',
        'params': {
          'stage_id': stageId,
          'phase_title': phaseTitle,
          'facts': facts,
          'findings': findings,
          'skipped_pdfs': skippedPdfs,
          'failed_fetches': failedFetches,
        },
      }));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 30));
      await response.transform(utf8.decoder).join();
    } catch (e) {
      debugPrint("Failed to update deep research phase on bridge: $e");
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _summarizeSourceInline({
    required String sourceUrl,
    required String content,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    final truncatedContent = content.length > 12000
        ? content.substring(0, 12000) + "\n...[content truncated]"
        : content;
    final summarizerMessages = [
      const ChatMessage(
        role: MessageRole.system,
        text: DeepResearchPrompts.summarizerSystemPrompt,
      ),
      ChatMessage(
        role: MessageRole.user,
        text: "Source URL: $sourceUrl\n\nSource Content:\n$truncatedContent",
      ),
    ];
    try {
      final responseText = await _chatClient.sendChat(
        provider: provider,
        settings: settings,
        model: model,
        messages: summarizerMessages,
      );
      final cleanResp = responseText.replaceAll(RegExp(r"```json"), "").replaceAll("```", "").trim();
      final jsonMatch = RegExp(r"\{[\s\S]*\}").firstMatch(cleanResp);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final List<dynamic> rawFacts = parsed["facts"] is List ? parsed["facts"] as List<dynamic> : [];
        final List<dynamic> rawFindings = parsed["findings"] is List ? parsed["findings"] as List<dynamic> : [];
        final List<Map<String, dynamic>> facts = [];
        for (final item in rawFacts) {
          if (item is Map) {
            facts.add({
              'metric': item['metric']?.toString() ?? '',
              'subject': item['subject']?.toString() ?? '',
              'value': item['value']?.toString() ?? '',
              'date': item['date']?.toString() ?? '',
              'source': sourceUrl,
            });
          }
        }
        final List<Map<String, dynamic>> findings = [];
        for (final item in rawFindings) {
          if (item is Map) {
            findings.add({
              'text': item['text']?.toString() ?? '',
              'source': sourceUrl,
            });
          }
        }
        return {'facts': facts, 'findings': findings};
      }
    } catch (e) {
      debugPrint("Inline summarization failed for $sourceUrl: $e");
    }
    return {'facts': [], 'findings': []};
  }

  Future<bool> _checkResearchSufficiency({
    required String phaseGoal,
    required List<Map<String, dynamic>> facts,
    required List<Map<String, dynamic>> findings,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    if (facts.isEmpty && findings.isEmpty) return false;
    final factsText = facts.map((f) => "Fact: metric=${f['metric']} | subject=${f['subject']} | value=${f['value']} | source=${f['source']}").join("\n");
    final findingsText = findings.map((f) => "Finding: ${f['text']} (source=${f['source']})").join("\n");
    final prompt = "Phase Goal/Prompt: $phaseGoal\n\n"
        "Facts gathered so far:\n$factsText\n\n"
        "Findings gathered so far:\n$findingsText\n\n"
        "Based ONLY on the facts and findings above, have we gathered sufficient information to address the phase goal/prompt?\n"
        "Respond with a JSON object: {\"sufficient\": true | false, \"reason\": \"<short explanation>\"}";
    final messages = [
      const ChatMessage(
        role: MessageRole.system,
        text: DeepResearchPrompts.reflectorSystemPrompt,
      ),
      ChatMessage(
        role: MessageRole.user,
        text: prompt,
      ),
    ];
    try {
      final responseText = await _chatClient.sendChat(
        provider: provider,
        settings: settings,
        model: model,
        messages: messages,
      );
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(responseText);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        return parsed['sufficient'] == true;
      }
    } catch (e) {
      debugPrint("Sufficiency reflection check failed: $e");
    }
    return false;
  }

  Future<String> _exportDeepResearchTemp() async {
    final endpoint = _customMcpUrl.isNotEmpty
        ? _customMcpUrl
        : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 120);
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 120));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({
        'method': 'deep_research.export_temp',
        'params': <String, dynamic>{},
      }));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 120),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 120));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body);
      final result = decoded is Map ? decoded['result'] : null;
      if (result is Map && result['content'] is String) {
        return result['content'] as String;
      }
      throw const FormatException('Missing deep research export content');
    } finally {
      client.close(force: true);
    }
  }

  void _switchSession(String sessionId) {
    setState(() {
      _activeSessionId = sessionId;
      _editingMessageIndex = null;
      final session = _sessions.firstWhere((s) => s.id == sessionId);
      _selectedProviderId = session.providerId;
      final settings =
          _settings[_selectedProviderId] ??
          ProviderSettings.defaults(_provider);
      if (session.model.isNotEmpty) {
        _settings[_selectedProviderId] = settings.copyWith(
          model: session.model,
        );
      }

      // Turn off agentic file access and deep research modes if switching to an empty new/welcome chat
      final userMsgs = session.messages.where((m) => m.role == MessageRole.user);
      if (userMsgs.isEmpty && (session.title == 'New Chat' || session.title == 'Welcome Chat')) {
        _agenticEnabled = false;
        _deepResearchEnabled = false;
      }
    });
    _saveSettings();
    _saveSessions();
    if (MediaQuery.sizeOf(context).width < 840 && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _deleteSession(String sessionId) {
    if (_sessions.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the last remaining chat.')),
      );
      return;
    }

    final deletedIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (deletedIndex == -1) return;
    final deletedSession = _sessions[deletedIndex];

    setState(() {
      _sessions.removeAt(deletedIndex);
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.first.id;
      }
      _editingMessageIndex = null;
    });
    _saveSessions();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Chat "${deletedSession.title}" deleted.'),
        duration: const Duration(seconds: 15),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFFEADCC9),
          onPressed: () {
            setState(() {
              _sessions.insert(deletedIndex, deletedSession);
              _activeSessionId = deletedSession.id;
            });
            _saveSessions();
          },
        ),
      ),
    );
  }

  void _renameSession(String sessionId, String newTitle) {
    setState(() {
      final idx = _sessions.indexWhere((s) => s.id == sessionId);
      if (idx != -1) {
        _sessions[idx] = _sessions[idx].copyWith(title: newTitle);
      }
    });
    _saveSessions();
  }

  void _togglePinSession(String sessionId) {
    setState(() {
      final idx = _sessions.indexWhere((s) => s.id == sessionId);
      if (idx != -1) {
        _sessions[idx] = _sessions[idx].copyWith(
          isPinned: !_sessions[idx].isPinned,
        );
      }
    });
    _saveSessions();
  }

  ProviderDefinition get _provider =>
      providerCatalog.firstWhere((item) => item.id == _selectedProviderId);

  ProviderSettings get _activeSettings =>
      _settings[_selectedProviderId] ?? ProviderSettings.defaults(_provider);

  String get _activeModel {
    final settings = _activeSettings;
    if (settings.model.trim().isNotEmpty) return settings.model.trim();
    return _provider.models.first;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    final selected = prefs.getString(_selectedProviderKey);
    final searchRaw = prefs.getString('search_settings_v1');
    final nextSettings = <String, ProviderSettings>{};

    SearchSettings loadedSearchSettings = SearchSettings.defaults();
    if (searchRaw != null && searchRaw.trim().isNotEmpty) {
      try {
        loadedSearchSettings = SearchSettings.fromJson(jsonDecode(searchRaw) as Map<String, dynamic>);
      } catch (_) {}
    }

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          nextSettings[entry.key] = ProviderSettings.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      } catch (_) {
        nextSettings.clear();
      }
    }

    for (final provider in providerCatalog) {
      String? key;
      try {
        key = await _secureStorage.read(key: _keyStorageName(provider.id));
      } catch (e) {
        key = prefs.getString('fallback_api_key_${provider.id}');
        debugPrint('Secure storage read failed for ${provider.id}: $e');
      }
      final current =
          nextSettings[provider.id] ?? ProviderSettings.defaults(provider);
      final normalized = current.maxTokens < 1
          ? current.copyWith(maxTokens: provider.defaultMaxTokens)
          : current;
      nextSettings[provider.id] = normalized.copyWith(apiKey: key ?? '');
    }

    final agenticRaw = prefs.getBool('agentic_enabled_v1');
    final artifactsRaw = prefs.getBool('artifacts_enabled_v1');
    final svgVisualsRaw = prefs.getBool('svg_visuals_enabled_v1');
    final agenticWorkspaceRaw = prefs.getString('agentic_workspace_v1');
    final customMcpUrlRaw = prefs.getString('custom_mcp_url_v1');
    final deepResearchRaw = prefs.getBool('deep_research_enabled_v1');
    final writerContextBudgetRaw = prefs.getInt('writer_context_budget_v1');

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _settings = nextSettings;
      _searchSettings = loadedSearchSettings;
      _agenticEnabled = agenticRaw ?? true;
      _artifactsEnabled = artifactsRaw ?? true;
      _svgVisualsEnabled = svgVisualsRaw ?? true;
      _shellPermission = prefs.getString('shell_permission_v1') ?? 'ask';
      _agenticWorkspace =
          agenticWorkspaceRaw ?? '/data/data/com.termux/files/home';
      _customMcpUrl = customMcpUrlRaw ?? '';
      _deepResearchEnabled = deepResearchRaw ?? false;
      _writerContextBudget = writerContextBudgetRaw ?? 32000;
      if (selected != null &&
          providerCatalog.any((provider) => provider.id == selected)) {
        _selectedProviderId = selected;
      }
    });

    await _loadSessions();
  }

  Future<void> _saveSettings() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final metadata = <String, Map<String, dynamic>>{};
    for (final entry in _settings.entries) {
      metadata[entry.key] = entry.value.copyWith(apiKey: '').toJson();
      final key = entry.value.apiKey.trim();
      try {
        if (key.isEmpty) {
          await _secureStorage.delete(key: _keyStorageName(entry.key));
        } else {
          await _secureStorage.write(
            key: _keyStorageName(entry.key),
            value: key,
          );
        }
      } catch (e) {
        debugPrint('Secure storage write failed for ${entry.key}: $e');
        if (key.isEmpty) {
          await prefs.remove('fallback_api_key_${entry.key}');
        } else {
          await prefs.setString('fallback_api_key_${entry.key}', key);
        }
      }
    }
    await prefs.setString(_settingsKey, jsonEncode(metadata));
    await prefs.setString(_selectedProviderKey, _selectedProviderId);
    await prefs.setString(
      'search_settings_v1',
      jsonEncode(_searchSettings.toJson()),
    );
    await prefs.setBool('agentic_enabled_v1', _agenticEnabled);
    await prefs.setBool('artifacts_enabled_v1', _artifactsEnabled);
    await prefs.setBool('svg_visuals_enabled_v1', _svgVisualsEnabled);
    await prefs.setString('shell_permission_v1', _shellPermission);
    await prefs.setBool('deep_research_enabled_v1', _deepResearchEnabled);
    await prefs.setInt('writer_context_budget_v1', _writerContextBudget);
    await prefs.setString('agentic_workspace_v1', _agenticWorkspace);
    await prefs.setString('custom_mcp_url_v1', _customMcpUrl);
    // Auto-generate GitHub Actions workflow if Flutter project detected
    _ensureFlutterWorkflow(_agenticWorkspace);
  }

  /// Auto-generates .github/workflows/build.yml for Flutter projects.
  /// Safe: never overwrites an existing workflow file.
  Future<void> _ensureFlutterWorkflow(String workspace) async {
    try {
      final dir = Directory(workspace);
      if (!dir.existsSync()) return;
      // Detect Flutter project
      final pubspec = File('$workspace/pubspec.yaml');
      if (!pubspec.existsSync()) return;
      final pubContent = pubspec.readAsStringSync();
      if (!pubContent.contains('flutter:')) return;

      final workflowDir = Directory('$workspace/.github/workflows');
      final workflowFile = File('${workflowDir.path}/build.yml');
      if (workflowFile.existsSync()) return; // never overwrite

      workflowDir.createSync(recursive: true);

      // Extract app name from pubspec
      String appName = 'app';
      final nameMatch = RegExp(
        r'^name:\s*(.+)$',
        multiLine: true,
      ).firstMatch(pubContent);
      if (nameMatch != null) appName = nameMatch.group(1)!.trim();

      const workflow = '''name: Build Flutter APK

on:
  push:
    branches: [main, master]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: 'stable'
          channel: 'stable'
          cache: true

      - name: Get dependencies
        run: flutter pub get

      - name: Analyze
        run: dart analyze --fatal-infos || true

      - name: Build APK (release)
        run: flutter build apk --release --split-per-abi

      - name: Upload APKs
        uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/app/outputs/flutter-apk/*.apk
          retention-days: 7
''';
      workflowFile.writeAsStringSync(workflow);
      debugPrint(
        '[Forge] Auto-generated .github/workflows/build.yml for $appName',
      );
    } catch (e) {
      debugPrint('[Forge] Workflow auto-gen failed: $e');
    }
  }

  Future<void> _selectProvider(String providerId) async {
    setState(() {
      _selectedProviderId = providerId;
      final sessionIndex = _sessions.indexWhere(
        (s) => s.id == _activeSessionId,
      );
      if (sessionIndex != -1) {
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
          providerId: providerId,
        );
      }
    });
    await _saveSettings();
    await _saveSessions();
    if (MediaQuery.sizeOf(context).width < 840 && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openProviderSheet([String? providerId]) async {
    final provider = providerCatalog.firstWhere(
      (item) => item.id == (providerId ?? _selectedProviderId),
    );
    final current =
        _settings[provider.id] ?? ProviderSettings.defaults(provider);
    final result = await showModalBottomSheet<ProviderSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ProviderSettingsSheet(
          provider: provider,
          settings: current,
          cachedModels: _modelCache[provider.id] ?? provider.models,
          onFetchModels: () => _fetchModels(provider),
        );
      },
    );

    if (result == null) return;
    setState(() {
      _settings = {..._settings, provider.id: result};
      _selectedProviderId = provider.id;

      final targetSessionId = _activeSessionId;
      if (targetSessionId != null) {
        final sessionIndex = _sessions.indexWhere(
          (s) => s.id == targetSessionId,
        );
        if (sessionIndex != -1) {
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            providerId: provider.id,
            model: result.model,
            maxTokens: result.maxTokens,
          );
        }
      }
    });
    await _saveSettings();
    await _saveSessions();
  }

  Future<List<String>> _fetchModels(ProviderDefinition provider) async {
    final settings =
        _settings[provider.id] ?? ProviderSettings.defaults(provider);
    setState(() => _isFetchingModels = true);
    try {
      final models = await _chatClient.fetchModels(provider, settings);
      final uniqueModels = {
        ...models,
        ...provider.models,
      }.where((model) => model.trim().isNotEmpty).toList()..sort();
      setState(() => _modelCache[provider.id] = uniqueModels);
      return uniqueModels;
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  Future<void> _openModelSheet() async {
    final provider = _provider;
    final settings = _activeSettings;
    final models = _modelCache[provider.id] ?? provider.models;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ModelPickerSheet(
          provider: provider,
          models: models,
          selectedModel: _activeModel,
          isFetching: _isFetchingModels,
          onFetchModels: () => _fetchModels(provider),
        );
      },
    );

    if (selected == null || selected.trim().isEmpty) return;
    setState(() {
      _settings = {
        ..._settings,
        provider.id: settings.copyWith(model: selected.trim()),
      };

      final targetSessionId = _activeSessionId;
      if (targetSessionId != null) {
        final sessionIndex = _sessions.indexWhere(
          (s) => s.id == targetSessionId,
        );
        if (sessionIndex != -1) {
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            model: selected.trim(),
          );
        }
      }
    });
    await _saveSettings();
    await _saveSessions();
  }

  static const String mcpAndSearchSystemPrompt =
      "Tools available: web search + Termux shell.\n\n"
      "Web search: emit exactly one line then stop:\n"
      "<search_request>query</search_request>\n\n"
      "Run command: emit ONE block then stop:\n"
      "<command>COMMAND</command>\n\n"
      "Resume after results arrive.";

  void _stopResponse(String sessionId) {
    if (sessionId.isEmpty) return;
    final subscription = _activeSubscriptions[sessionId];
    if (subscription != null) {
      subscription.cancel();
      _activeSubscriptions.remove(sessionId);
    }
    final completer = _activeCompleters[sessionId];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
      _activeCompleters.remove(sessionId);
    }
    setState(() {
      _sendingSessionIds.remove(sessionId);
    });
  }

  Future<void> _sendMessage() async {
    final prompt = _messageController.text.trim();
    if (prompt.isEmpty) return;

    final targetSessionId = _activeSessionId;
    if (targetSessionId == null) return;
    if (_sendingSessionIds.contains(targetSessionId)) return;

    final sessionIndex = _sessions.indexWhere((s) => s.id == targetSessionId);
    if (sessionIndex == -1) return;

    final session = _sessions[sessionIndex];
    final provider = providerCatalog.firstWhere(
      (p) => p.id == session.providerId,
    );
    final baseSettings =
        _settings[session.providerId] ?? ProviderSettings.defaults(provider);
    final settings = baseSettings.copyWith(
      model: session.model.isNotEmpty ? session.model : baseSettings.model,
      maxTokens: session.maxTokens ?? baseSettings.maxTokens,
    );
    final activeModel = session.model.isNotEmpty
        ? session.model
        : settings.model;

    if (provider.requiresKey && settings.apiKey.trim().isEmpty) {
      await _openProviderSheet(provider.id);
      return;
    }

    final isEditing = _editingMessageIndex != null;
    final editIndex = _editingMessageIndex;

    if (targetSessionId == _activeSessionId) {
      _messageController.clear();
    }

    final userMessage = ChatMessage(
      role: MessageRole.user,
      text: prompt,
      images: List<String>.from(session.attachedImagesBase64),
      files: List<AttachedFile>.from(session.attachedFiles),
    );

    String updatedTitle = session.title;
    if (session.title == 'Welcome Chat' || session.title == 'New Chat') {
      updatedTitle = prompt.length > 25
          ? '${prompt.substring(0, 25)}...'
          : prompt;
    }

    setState(() {
      _sendingSessionIds.add(targetSessionId);
      List<ChatMessage> baseMessages = List<ChatMessage>.from(session.messages);

      List<List<ChatMessage>> updatedBranches = session.branches != null
          ? List<List<ChatMessage>>.from(session.branches!)
          : [List<ChatMessage>.from(session.messages)];

      int newActiveBranchIndex = session.activeBranchIndex ?? 0;

      if (isEditing &&
          editIndex != null &&
          editIndex >= 0 &&
          editIndex < baseMessages.length) {
        final prefix = baseMessages.sublist(0, editIndex);
        final newBranchMessages = [...prefix, userMessage];
        updatedBranches.add(newBranchMessages);
        newActiveBranchIndex = updatedBranches.length - 1;
        baseMessages = newBranchMessages;
      } else {
        baseMessages.add(userMessage);
        if (newActiveBranchIndex >= 0 &&
            newActiveBranchIndex < updatedBranches.length) {
          updatedBranches[newActiveBranchIndex] = baseMessages;
        }
      }

      _editingMessageIndex = null;
      final curIdx = _sessions.indexWhere((s) => s.id == targetSessionId);
      if (curIdx != -1) {
        _sessions[curIdx] = session.copyWith(
          messages: baseMessages,
          branches: updatedBranches,
          activeBranchIndex: newActiveBranchIndex,
          title: updatedTitle,
          attachedImagesBase64: const [],
          attachedFiles: const [],
        );
      }
    });

    if (targetSessionId == _activeSessionId) {
      _scrollToBottom(force: true);
    }

    int toolCallCount = 0;
    bool shouldContinue = true;

    try {
      while (shouldContinue && toolCallCount < 10) {
        final curIdx = _sessions.indexWhere((s) => s.id == targetSessionId);
        if (curIdx == -1) {
          shouldContinue = false;
          break;
        }
        final currentSession = _sessions[curIdx];
        final assistantMessageIndex = currentSession.messages.length;

        setState(() {
          final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
          if (idx != -1) {
            _sessions[idx] = _sessions[idx].copyWith(
              messages: [
                ..._sessions[idx].messages,
                const ChatMessage(role: MessageRole.assistant, text: ''),
              ],
            );
          }
        });

        if (targetSessionId == _activeSessionId) {
          _scrollToBottom(force: true);
        }

        final List<ChatMessage> historyForApi = [];
        final currentDateStr = DateTime.now().toString().substring(0, 10);
        String systemPromptText = "";

        if (_deepResearchEnabled && !currentSession.messages.any((m) => m.text.contains('<research_state>'))) {
          systemPromptText = DeepResearchPrompts.plannerSystemPrompt;
        } else {
          systemPromptText =
              "Date: $currentDateStr. Use current-year data unless asked otherwise.\n\n"
              "Render via markdown code blocks:\n"
              "- LaTeX: \\[ ... \\] or \\( ... \\)\n";

          if (_svgVisualsEnabled) {
            systemPromptText +=
                "- SVG (ONLY for non-graph diagrams like flowcharts, architecture, illustrations): ```svg\n"
                "  Root: width=\"100%\" viewBox=\"0 0 800 450\" preserveAspectRatio=\"xMidYMid meet\"\n"
                "  IMPORTANT: SVGs MUST be strictly enclosed with `<svg>` and `</svg>` tags.\n"
                "  NEVER use SVG for charts, graphs, or mind maps. Use ```chart instead.\n\n";
          }

        systemPromptText +=
            "- CHARTS (bar, line, pie, scatter, area, radar, histogram, heatmap, bubble, gantt, gauge, donut, stacked, cartesian, mindmap): ```chart\n"
            "  Simple line-based format. LLM passes only values. Examples:\n\n"
            "  BAR/GROUPED BAR:\n"
            "  type: bar\n"
            "  title: Revenue by Quarter\n"
            "  range: 0-100\n"
            "  labels: Q1, Q2, Q3, Q4\n"
            "  series: Revenue = 45, 67, 89, 52\n"
            "  series: Costs = 30, 45, 60, 40\n\n"
            "  STACKED BAR:\n"
            "  type: stacked\n"
            "  title: Stack Example\n"
            "  labels: Q1, Q2, Q3\n"
            "  series: A = 30, 40, 50\n"
            "  series: B = 20, 30, 10\n\n"
            "  LINE/CURVE (single or multi-series):\n"
            "  type: line\n"
            "  title: Growth Trend\n"
            "  labels: Jan, Feb, Mar, Apr\n"
            "  series: Users = 100, 250, 400, 800\n\n"
            "  AREA CHART:\n"
            "  type: area\n"
            "  title: Traffic\n"
            "  labels: Mon, Tue, Wed\n"
            "  series: Visits = 500, 800, 650\n\n"
            "  PIE/DONUT (shorthand — just label: value):\n"
            "  type: pie\n"
            "  title: Market Share\n"
            "  Android: 45\n"
            "  iOS: 30\n"
            "  Web: 25\n\n"
            "  SCATTER:\n"
            "  type: scatter\n"
            "  title: Distribution\n"
            "  labels: A, B, C, D, E\n"
            "  series: Points = 10, 25, 15, 40, 30\n\n"
            "  RADAR/SPIDER:\n"
            "  type: radar\n"
            "  title: Skills\n"
            "  labels: Speed, Power, Defense, Agility, Stamina\n"
            "  series: Player A = 80, 65, 90, 70, 85\n"
            "  series: Player B = 60, 80, 70, 90, 75\n\n"
            "  HISTOGRAM:\n"
            "  type: histogram\n"
            "  title: Score Distribution\n"
            "  labels: 0-20, 21-40, 41-60, 61-80, 81-100\n"
            "  series: Frequency = 5, 12, 25, 18, 8\n\n"
            "  HEATMAP:\n"
            "  type: heatmap\n"
            "  title: Activity\n"
            "  xlabels: Mon, Tue, Wed\n"
            "  ylabels: Morning, Afternoon, Evening\n"
            "  row: 3, 7, 5\n"
            "  row: 8, 4, 9\n"
            "  row: 2, 6, 1\n\n"
            "  BUBBLE:\n"
            "  type: bubble\n"
            "  title: Market Size\n"
            "  labels: Tech, Health, Finance\n"
            "  series: Size = 80, 45, 120\n\n"
            "  GANTT/TIMELINE:\n"
            "  type: gantt\n"
            "  title: Project Plan\n"
            "  task: Design = 0, 3\n"
            "  task: Develop = 2, 7\n"
            "  task: Test = 6, 9\n"
            "  task: Deploy = 8, 10\n\n"
            "  GAUGE/PROGRESS:\n"
            "  type: gauge\n"
            "  title: CPU Usage\n"
            "  value: 73\n"
            "  max: 100\n"
            "  label: percent\n\n"
            "  CARTESIAN/GEOMETRY (for drawing shapes, polygons, points on a coordinate plane):\n"
            "  type: cartesian\n"
            "  title: Triangle ABC\n"
            "  range: -10-10\n"
            "  series: Triangle = 2,3, 6,7, 4,1, 2,3\n"
            "  series: Point A = 2,3\n\n"
            "  MINDMAP/TREE:\n"
            "  type: mindmap\n"
            "  title: Project Plan\n"
            "  node: 1 = Root\n"
            "  node: 2 = Branch A\n"
            "  node: 3 = Branch B\n"
            "  edge: 1 -> 2\n"
            "  edge: 1 -> 3\n\n"
            "  RULES: Use ```chart for ALL graphs/charts. Use simple format above. range: min-max is optional. Keep it simple. Never write full code for charts.\n";

        if (_artifactsEnabled) {
          systemPromptText +=
              "- Artifacts for complete/long outputs: use fenced blocks so the app renders them as files.\n"
              "  Use ```html for complete HTML pages, ```markdown for essays/guides/reports, ```docx for Word-style documents, and language fences like ```python/```dart/```js for complete scripts or files.\n"
              "  If the answer is long, a complete file, an essay, a guide, a report, or a full runnable script, put it in one artifact block instead of inline chat text. Use inline code only for small snippets.\n"
              "- Interactive: ```html / ```javascript / ```react / ```artifact\n"
              "- Microsoft Word Document: ```docx\n"
              "  title: Document Title\n"
              "  subtitle: Optional Subtitle\n"
              "  # Content in clean markdown\n"
              "  ## Section Heading\n"
              "  This is a paragraph.\n"
              "  - Bullet item\n"
              "  > Callout block\n"
              "  | Table Header | Col |\n"
              "  |---|---|\n"
              "  | Cell | Cell |\n"
              "  ```\n\n";
        }

        if (_svgVisualsEnabled) {
          systemPromptText +=
              "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. Use ```svg ONLY for non-graph diagrams (flowcharts, mind maps, architecture, illustrations). NEVER use SVG for charts. ALWAYS include the closing </svg> tag for SVGs.\n";
        } else {
          systemPromptText +=
              "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. NEVER use SVG for charts.\n";
        }

        if (_agenticEnabled) {
          systemPromptText += r"""
AGENTIC IDE — You are the AI engine of a real, production-grade mobile IDE powered by Termux on Android.
You have full shell access AND a suite of structured file tools via the Python bridge.

━━ CORE RULE ━━
Emit ONE tool call per turn, then STOP. Wait for result. Then decide the next step.
NEVER chain multiple tool calls in one response.

━━ CODE NAVIGATION PROTOCOL (STRICT EXECUTION) ━━
NEVER read an entire file blindly. You must follow this workflow:
1. GET THE MAP: Use `<tool_request><method>file_outline</method><path>path/to/file.dart</path></tool_request>` first. This returns a structured list of all classes, functions, and their exact line numbers.
2. READ SPECIFIC LINES: Using the line numbers from the outline, use `<tool_request><method>read_file_rich</method><path>path/to/file.dart</path><start_line>45</start_line><end_line>80</end_line></tool_request>` to read ONLY that specific function.
3. SEARCH: To find specific code across the project, use `<tool_request><method>search_rich</method><query>RegExp('TODO.*')</query><path>lib/</path><context_lines>2</context_lines></tool_request>`.
4. EDIT: NEVER rewrite a whole file. Use `<tool_request><method>patch_file</method><path>path/to/file.dart</path><patches>[{"search": "old code", "replace": "new code"}]</patches></tool_request>` for atomic search-and-replace.

━━ STRUCTURED FILE TOOLS (ALWAYS PREFER OVER SHELL FOR FILE OPS) ━━
Use XML format: <tool_request><method>NAME</method><param>value</param>...</tool_request>
CRITICAL: Always use direct tag format like <path>/foo</path>. Do NOT use <PARAM name="path">/foo</PARAM> to maximize parser cleanliness.

── READ FILE (with line numbers, metadata, navigation hints) ──
<tool_request>
  <method>read_file_rich</method>
  <path>/absolute/path/to/file.dart</path>
  <start_line>1</start_line>
  <end_line>120</end_line>
</tool_request>
Returns: numbered lines ("  42 │ code here"), total line count, size, language, nav hints.
Max 600 lines per call. Use start_line/end_line to navigate large files.

── MULTI-READ (read multiple files or ranges in ONE call) ──
<tool_request>
  <method>multi_read_rich</method>
  <reads>[{"path":"/lib/main.dart","start_line":45,"end_line":80},{"path":"/lib/widget.dart","start_line":1,"end_line":50}]</reads>
</tool_request>
Use when you need to read non-adjacent sections or multiple files at once.

── PATCH FILE (multi search-replace, atomic, with diff output) ──
<tool_request>
  <method>patch_file</method>
  <path>/absolute/path/to/file.dart</path>
  <patches>[{"search":"exact old code here","replace":"new code here","label":"fix pie chart"}]</patches>
</tool_request>
Returns: unified diff of all changes. Fails safely if search text not found.
For multiple non-adjacent edits: add multiple objects to the patches array.
CRITICAL: search text must EXACTLY match including whitespace and indentation.

── REPLACE LINES (replace a specific line range) ──
<tool_request>
  <method>replace_lines</method>
  <path>/absolute/path/to/file.dart</path>
  <start_line>45</start_line>
  <end_line>52</end_line>
  <new_content>  Widget build(BuildContext context) {
    return Scaffold();
  }</new_content>
</tool_request>
Use when you know exact line numbers (after reading the file first).

── INSERT LINES (insert after a line) ──
<tool_request>
  <method>insert_lines</method>
  <path>/absolute/path/to/file.dart</path>
  <after_line>120</after_line>
  <content>  // New code here</content>
</tool_request>

── DELETE LINES ──
<tool_request>
  <method>delete_lines</method>
  <path>/absolute/path/to/file.dart</path>
  <start_line>45</start_line>
  <end_line>52</end_line>
</tool_request>

── WRITE FILE (create or overwrite entire file, atomic) ──
<tool_request>
  <method>write_file_rich</method>
  <path>/absolute/path/to/newfile.dart</path>
  <content>full file content here</content>
  <create_dirs>true</create_dirs>
</tool_request>
For existing files, prefer passing <expected_sha256> from stat_path/read metadata when available. Mutating file tools create an automatic safety checkpoint before changing existing content.

── SEARCH FILES (grep across codebase) ──
<tool_request>
  <method>search_rich</method>
  <path>/lib</path>
  <query>_buildPieChart</query>
  <include>*.dart</include>
  <case_insensitive>false</case_insensitive>
</tool_request>
Returns: file:line:content for each match. Max 50 results.

── FILE OUTLINE (class/function structure of a file) ──
<tool_request>
  <method>file_outline</method>
  <path>/lib/main.dart</path>
</tool_request>
Returns: all class/function/widget definitions with line numbers.

── SYMBOL REFERENCES ──
<tool_request>
  <method>symbol_references</method>
  <symbol>MyClass</symbol>
  <path>/projects/myapp/lib</path>
</tool_request>
Use this before renames or cross-file edits.

── DIRECTORY TREE ──
<tool_request>
  <method>tree</method>
  <path>/projects/myapp</path>
  <max_depth>3</max_depth>
</tool_request>

── DIFF TWO FILES ──
<tool_request>
  <method>diff_files</method>
  <path_a>/lib/main.dart</path_a>
  <path_b>/lib/old_main.dart</path_b>
</tool_request>

── SHELL COMMAND (for build tools, git, installs — NOT for file reading/editing) ──
<tool_request>
  <method>run_command</method>
  <command>dart analyze lib/</command>
  <cwd>/projects/myapp</cwd>
</tool_request>
Also supported: <command>shell command here</command> shorthand.

── APPEND FILE (append to file, creates if missing) ──
<tool_request>
  <method>append_file</method>
  <path>/absolute/path/to/file.log</path>
  <content>New line to append here</content>
</tool_request>
Use for log files, cumulative writes, config additions.

── DELETE PATH (file or directory with safety guards) ──
<tool_request>
  <method>delete_path</method>
  <path>/absolute/path/to/old_file.dart</path>
  <recursive>false</recursive>
</tool_request>
Set recursive=true to delete non-empty directories. Protected system dirs are hard-blocked.

── MOVE / RENAME ──
<tool_request>
  <method>move_path</method>
  <src>/old/path/file.dart</src>
  <dest>/new/path/file.dart</dest>
  <overwrite>false</overwrite>
</tool_request>
Cross-filesystem safe. Set overwrite=true to replace existing destination.

── COPY (file or directory, recursive for dirs) ──
<tool_request>
  <method>copy_path</method>
  <src>/path/to/source</src>
  <dest>/path/to/destination</dest>
  <overwrite>false</overwrite>
</tool_request>

── MKDIR (create directory, parents by default) ──
<tool_request>
  <method>mkdir_path</method>
  <path>/projects/myapp/lib/models</path>
  <parents>true</parents>
</tool_request>

── STAT (detailed file/dir metadata) ──
<tool_request>
  <method>stat_path</method>
  <path>/lib/main.dart</path>
</tool_request>
Returns: size, permissions, timestamps, type, language, symlink info.

── CHMOD (change permissions) ──
<tool_request>
  <method>chmod_path</method>
  <path>/scripts/deploy.sh</path>
  <mode>755</mode>
  <recursive>false</recursive>
</tool_request>
Use octal mode strings (e.g., 755, 644). Set recursive=true for directories.

── BACKGROUND SERVICES (for web servers, dev servers, long-running processes) ──
<tool_request>
  <method>run_background</method>
  <command>npm run dev</command>
  <name>web-frontend</name>
  <cwd>/projects/myapp</cwd>
</tool_request>
Starts process detached. Returns: PID, URL(s), startup log, management commands.
Other tools: list_services, service_status (pass <id>), service_logs (pass <id>), stop_service (pass <id>).

── BACKGROUND TIME LIMIT (wait while a background service continues running) ──
<tool_request>
  <method>wait_for_background</method>
  <pid>12345</pid>
  <time_limit_seconds>30</time_limit_seconds>
  <poll_interval_seconds>2</poll_interval_seconds>
</tool_request>
Supported alias method: <method>background_time_limit</method>.
Pauses ONLY the agent for up to 90 seconds (time_limit_seconds); it never stops the background process. Use it after run_background or during background tasks when a build, server, or watcher needs time to run. It returns whether the service finished or is still running, its latest status, and recent logs. Then use service_status or service_logs as needed.

── DART IDE TOOLS ──
<tool_request>
  <method>dart_diagnostics</method>
  <path>/projects/myapp</path>
</tool_request>
Returns structured analyzer diagnostics when the Dart SDK supports JSON output.

<tool_request>
  <method>dart_format</method>
  <path>/projects/myapp/lib/main.dart</path>
  <output>none</output>
</tool_request>
Use output=none to check formatting without writing, output=write to apply formatting.

━━ DECISION GUIDE: WHEN TO USE WHICH ━━
| Task                    | Use                                         | NOT                    |
|-------------------------|---------------------------------------------|------------------------|
| Read file / check code  | read_file_rich                              | cat, head, tail        |
| Edit 1-3 code sections  | patch_file                                  | sed -i, heredoc        |
| Edit by line number     | replace_lines                               | sed -i                 |
| Create new file         | write_file_rich                             | cat > file << 'EOF'    |
| Append to file / log    | append_file                                 | echo >>                |
| Search codebase         | search_rich                                 | grep -rn               |
| List project structure  | tree                                        | ls -la                 |
| Delete file / dir       | delete_path                                 | rm -rf                 |
| Move / rename           | move_path                                   | mv                     |
| Copy file / dir         | copy_path                                   | cp -r                  |
| Create directory        | mkdir_path                                  | mkdir -p               |
| File metadata           | stat_path                                   | stat, ls -la           |
| Change permissions      | chmod_path                                  | chmod                  |
| Dart diagnostics        | dart_diagnostics                            | raw dart analyze       |
| Dart formatting         | dart_format                                 | raw dart format        |
| Symbol references       | symbol_references                           | ad-hoc grep            |
| Build / git / installs  | run_command                                 | N/A                    |
| Long-running server     | run_background                              | run_command            |
| Wait for background job | wait_for_background / background_time_limit | arbitrary sleep command|

━━ WORKFLOW FOR EDITING CODE ━━
1. read_file_rich (confirm exact content and line numbers)
2. patch_file or replace_lines (precise edit)
3. dart_diagnostics (verify no analyzer errors)
4. Report result to user

━━ QUALITY STANDARDS ━━
- ALWAYS read_file_rich before editing — never edit from memory
- search text in patch_file must match EXACTLY (copy from read output)
- Always verify edits with dart_diagnostics, flutter analyze, or the relevant project test
- Write clean, production-grade code — no placeholders, no TODOs
- Handle errors explicitly; never silently ignore failures

━━ PROJECT DOCUMENTATION ━━
For every project, maintain a README.md at the project root.
""";
        }

        if (_customMcpUrl.isNotEmpty) {
          systemPromptText +=
              "Remote MCP at $_customMcpUrl — add \"server\":\"remote\" to params to use it.\n";
        }

        if (_searchSettings.enabled) {
          systemPromptText +=
              "\n━━ WEB SEARCH PROTOCOL ━━\nIf a user asks about recent events, unknown facts, or requires live data out of your knowledge cutoff, you MUST use the web.\n1. First, output <search_request>query</search_request> to get search results.\n2. After viewing the search results, you MUST use <read_url>URL</read_url> to fetch the full content of the most relevant page to ensure maximum accuracy.\nCRITICAL: Only output ONE tool tag per turn, then stop and wait for the result.\n";
        }

        systemPromptText +=
            "\nMemory Tool: Use <memory action=\"read\"></memory>, <memory action=\"append\">text</memory>, or <memory action=\"replace\">text</memory> to save/read personal details across sessions. Limit 10KB. Use only when essential.\n";
        }

        if (systemPromptText.isNotEmpty) {
          historyForApi.add(
            ChatMessage(role: MessageRole.system, text: systemPromptText),
          );
        }

        final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
        if (idx == -1) {
          shouldContinue = false;
          break;
        }
        historyForApi.addAll(
          _compactHistoryForApi(_sessions[idx].messages, assistantMessageIndex),
        );

        final stream = _chatClient.sendChatStream(
          provider: provider,
          settings: settings,
          model: activeModel,
          messages: historyForApi,
        );

        final completer = Completer<void>();
        var fullText = '';
        var reasoningText = '';
        var isThinking = false;
        final updateStopwatch = Stopwatch()..start();

        final subscription = stream.listen(
          (chunk) {
            if (!mounted) return;
            if (chunk.startsWith('[REASONING]')) {
              reasoningText += chunk.substring(11);
            } else {
              var textChunk = chunk;

              // Start of <think> or <reasoning> or <thought>
              if (!isThinking &&
                  (textChunk.contains('<think>') ||
                      textChunk.contains('<reasoning>') ||
                      textChunk.contains('<thought>'))) {
                final tag = textChunk.contains('<think>')
                    ? '<think>'
                    : textChunk.contains('<thought>')
                    ? '<thought>'
                    : '<reasoning>';
                final parts = textChunk.split(tag);
                fullText += parts[0];
                isThinking = true;
                textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
              }

              // End of </think> or </reasoning> or </thought>
              if (isThinking &&
                  (textChunk.contains('</think>') ||
                      textChunk.contains('</reasoning>') ||
                      textChunk.contains('</thought>'))) {
                final tag = textChunk.contains('</think>')
                    ? '</think>'
                    : textChunk.contains('</thought>')
                    ? '</thought>'
                    : '</reasoning>';
                final parts = textChunk.split(tag);
                reasoningText += parts[0];
                isThinking = false;
                textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
                fullText += textChunk;
              } else if (isThinking) {
                reasoningText += textChunk;
              } else {
                fullText += textChunk;
              }
            }

            if (updateStopwatch.elapsedMilliseconds > 250) {
              setState(() {
                final idx = _sessions.indexWhere(
                  (s) => s.id == targetSessionId,
                );
                if (idx != -1) {
                  final msgs = List<ChatMessage>.from(_sessions[idx].messages);
                  if (assistantMessageIndex < msgs.length) {
                    msgs[assistantMessageIndex] = ChatMessage(
                      role: MessageRole.assistant,
                      text: fullText,
                      reasoning: reasoningText,
                    );
                    _sessions[idx] = _sessions[idx].copyWith(messages: msgs);
                  }
                }
              });
              updateStopwatch.reset();
              if (targetSessionId == _activeSessionId) {
                _scrollToBottom();
              }
            }
          },
          onError: (Object err) {
            if (!completer.isCompleted) completer.completeError(err);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        _activeSubscriptions[targetSessionId] = subscription;
        _activeCompleters[targetSessionId] = completer;

        try {
          await completer.future;
        } finally {
          _activeSubscriptions.remove(targetSessionId);
          _activeCompleters.remove(targetSessionId);
          await subscription.cancel();
        }

        if (!_sendingSessionIds.contains(targetSessionId)) {
          shouldContinue = false;
          break;
        }

        // Final state update after stream completes
        setState(() {
          final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
          if (idx != -1) {
            final msgs = List<ChatMessage>.from(_sessions[idx].messages);
            if (assistantMessageIndex < msgs.length) {
              msgs[assistantMessageIndex] = ChatMessage(
                role: MessageRole.assistant,
                text: fullText,
                reasoning: reasoningText,
              );
              _sessions[idx] = _sessions[idx].copyWith(messages: msgs);
            }
          }
        });
        if (targetSessionId == _activeSessionId) {
          _scrollToBottom();
        }

        final searchRegex = RegExp(
          r'<search_request>\s*([\s\S]*?)\s*</search_request>',
          caseSensitive: false,
          dotAll: true,
        );
        final readUrlRegex = RegExp(
          r'<read_url>\s*([\s\S]*?)\s*</read_url>',
          caseSensitive: false,
          dotAll: true,
        );
        final mcpRegex = RegExp(
          r'<mcp_request>\s*(\{[\s\S]*?\})\s*</mcp_request>',
          caseSensitive: false,
        );
        final memoryRegex = RegExp(
          r'<memory\s+action="([^"]+)">\s*([\s\S]*?)\s*</memory>',
          caseSensitive: false,
          dotAll: true,
        );

        final searchMatch = searchRegex.firstMatch(fullText);
        final readUrlMatch = readUrlRegex.firstMatch(fullText);
        final mcpMatch = _findMcpMatch(fullText);
        final memoryMatch = memoryRegex.firstMatch(fullText);

        if (_deepResearchEnabled && fullText.contains('<research_plan>')) {
          final planStart = fullText.indexOf('<research_plan>');
          var planEnd = fullText.indexOf('</research_plan>', planStart);
          if (planEnd == -1) {
            planEnd = fullText.length;
          }
          final planContent = fullText
              .substring(planStart + 15, planEnd)
              .trim();
          final phaseRegex = RegExp(
            r'<phase\s*(\d+)\s*>(.*?)</phase\s*\1\s*>',
            caseSensitive: false,
            dotAll: true,
          );
          final matches = phaseRegex.allMatches(planContent);
          if (matches.isNotEmpty) {
            final List<Map<String, dynamic>> stepsList = [];
            for (final match in matches) {
              final phaseNum = int.tryParse(match.group(1) ?? '') ?? 0;
              final textContent = match.group(2)?.trim() ?? '';

              String title = 'Phase $phaseNum';
              String prompt = textContent;
              final separatorIndex = textContent.indexOf(RegExp(r'[:\-]'));
              if (separatorIndex != -1 && separatorIndex < 35) {
                title = textContent.substring(0, separatorIndex).trim();
                prompt = textContent.substring(separatorIndex + 1).trim();
              }
              stepsList.add({
                "title": title,
                "prompt": prompt,
                "status": "pending",
                "content": "",
              });
            }

            final stateMap = {"status": "pending", "steps": stepsList};

            setState(() {
              final msgs = List<ChatMessage>.from(
                _sessions[sessionIndex].messages,
              );
              msgs[assistantMessageIndex] = ChatMessage(
                role: MessageRole.assistant,
                text:
                    fullText +
                    '\n\n<research_state>${jsonEncode(stateMap)}</research_state>',
                reasoning: reasoningText,
              );
              _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                messages: msgs,
              );
              _sendingSessionIds.remove(targetSessionId);
            });
            await _saveSessions();
            return;
          }
        }

        if (toolCallCount >= 10) {
          shouldContinue = false;
          continue;
        }

        List<String> toolOutputs = [];
        bool executedTools = false;

        if (_searchSettings.enabled && searchMatch != null) {
          final searchMatches = searchRegex.allMatches(fullText);
          for (final match in searchMatches) {
            executedTools = true;
            final query = match.group(1)?.trim() ?? '';
            if (mounted) setState(() => _toolStatus = '🔍 Searching: "$query"');
            final searchResultRaw = await _chatClient.searchWeb(
              query,
              _searchSettings.provider,
              [_searchSettings.apiKey, ..._searchSettings.fallbackApiKeys],
              googleCx: _searchSettings.googleCx,
            );
            if (mounted) setState(() => _toolStatus = '');

            String searchResult = searchResultRaw;
            if (searchResult.length > 4000) {
              searchResult =
                  searchResult.substring(0, 4000) +
                  '\n\n...[truncated due to length]';
            }
            toolOutputs.add(
              "Web Search results for '$query':\n\n$searchResult",
            );
          }
        }

        if (_searchSettings.enabled && readUrlMatch != null) {
          final readUrlMatches = readUrlRegex.allMatches(fullText);
          for (final match in readUrlMatches) {
            executedTools = true;
            final url = match.group(1)?.trim() ?? '';
            final shortUrl = url.length > 50 ? '${url.substring(0, 47)}…' : url;
            if (mounted) setState(() => _toolStatus = '🌐 Fetching: $shortUrl');
            String urlResult = '';
            try {
              var targetUrl = url;
              if (!targetUrl.startsWith('http'))
                targetUrl = 'https://$targetUrl';
              final client = HttpClient()
                ..findProxy = ((uri) => "DIRECT")
                ..connectionTimeout = const Duration(seconds: 15);
              final request = await client
                  .getUrl(Uri.parse(targetUrl))
                  .timeout(const Duration(seconds: 60));
              final response = await request.close().timeout(
                const Duration(seconds: 60),
              );

              if (response.statusCode < 200 || response.statusCode >= 300) {
                await response.drain<void>();
                throw HttpException('HTTP ${response.statusCode}');
              }

              final isPdf = targetUrl.toLowerCase().endsWith('.pdf') ||
                  (response.headers.contentType?.mimeType == 'application/pdf');

              String text = '';
              if (isPdf) {
                try {
                  final bytesBuilder = BytesBuilder();
                  await for (final chunk in response.timeout(const Duration(seconds: 60))) {
                    bytesBuilder.add(chunk);
                  }
                  final bytes = bytesBuilder.takeBytes();
                  if (bytes.isEmpty) {
                    throw const FormatException('Empty PDF bytes');
                  }
                  final PdfDocument document = PdfDocument(inputBytes: bytes);
                  text = PdfTextExtractor(document).extractText();
                  document.dispose();
                  if (text.trim().isEmpty) {
                    throw const FormatException('No extractable text in PDF (possibly scanned/image-only)');
                  }
                } catch (e) {
                  throw FormatException('PDF extraction failed: $e');
                }
              } else {
                final body = await response
                    .transform(utf8.decoder)
                    .join()
                    .timeout(const Duration(seconds: 60));

                var htmlBody = body;
                final bodyMatch = RegExp(
                  r'<body[^>]*>(.*?)</body>',
                  caseSensitive: false,
                  dotAll: true,
                ).firstMatch(body);
                if (bodyMatch != null) {
                  htmlBody = bodyMatch.group(1) ?? htmlBody;
                }

                htmlBody = htmlBody.replaceAll(
                  RegExp(
                    r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>',
                    caseSensitive: false,
                    dotAll: true,
                  ),
                  '',
                );
                htmlBody = htmlBody.replaceAll(
                  RegExp(
                    r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>',
                    caseSensitive: false,
                    dotAll: true,
                  ),
                  '',
                );
                htmlBody = htmlBody.replaceAll(
                  RegExp(r'<img[^>]*>', caseSensitive: false),
                  '',
                );
                htmlBody = htmlBody.replaceAll(
                  RegExp(
                    r'<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>',
                    caseSensitive: false,
                    dotAll: true,
                  ),
                  '',
                );
                htmlBody = htmlBody.replaceAll(
                  RegExp(r'<!--.*?-->', dotAll: true),
                  '',
                );

                text = htmlBody.replaceAll(RegExp(r'<[^>]*>'), ' ');
                text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
              }

              urlResult = text;
              if (urlResult.length > 8000) {
                urlResult =
                    urlResult.substring(0, 8000) +
                    '\n\n...[truncated due to length]';
              }
            } catch (e) {
              urlResult = 'Error fetching URL: $e';
            }
            if (mounted) setState(() => _toolStatus = '');
            toolOutputs.add(
              "Content of URL '$url':\n\n$urlResult",
            );
          }
        }
        if (memoryMatch != null) {
          final memoryMatches = memoryRegex.allMatches(fullText);
          for (final match in memoryMatches) {
            executedTools = true;
            final action = match.group(1)?.toLowerCase().trim() ?? '';
            final content = match.group(2)?.trim() ?? '';
            if (mounted)
              setState(() => _toolStatus = '🧠 Memory Tool: $action');

            final result = await _handleMemoryTool(action, content);

            if (mounted) setState(() => _toolStatus = '');
            toolOutputs.add("Memory Tool [$action] Result:\n$result");
          }
        }

        if (_agenticEnabled && mcpMatch != null) {
          final mcpMatches = [mcpMatch];
          for (final match in mcpMatches) {
            executedTools = true;
            String jsonString = match.group(1)?.trim() ?? '';
            jsonString = jsonString
                .replaceAll(RegExp(r'^```json\s*'), '')
                .replaceAll(RegExp(r'^```\s*'), '')
                .replaceAll(RegExp(r'\s*```$'), '');

            String mcpEndpoint = 'http://127.0.0.1:8390/mcp';
            String toolMethod = 'tool';
            Map<String, dynamic> toolParams = {};
           try {
             final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
              toolMethod = parsed['method']?.toString() ?? 'tool';
              toolParams = parsed['params'] as Map<String, dynamic>? ?? {};

              if (toolParams['server'] == 'remote' &&
                  _customMcpUrl.isNotEmpty) {
                mcpEndpoint = _customMcpUrl;
                toolParams.remove('server');
              }

              toolParams['workspace_dir'] = _agenticWorkspace;
              // Always set cwd to workspace so relative paths work
              if (!toolParams.containsKey('cwd') ||
                  (toolParams['cwd'] as String?)?.isEmpty == true) {
                toolParams['cwd'] = _agenticWorkspace;
              }
              _resolveToolPaths(toolParams, _agenticWorkspace);
              parsed['params'] = toolParams;
              jsonString = jsonEncode(parsed);
            } catch (_) {}

            // Permission check before running shell commands
            if (toolMethod == 'run_command' ||
                toolMethod == 'shell_exec' ||
                toolMethod == 'execute_command' ||
                toolMethod == 'execute_shell' ||
                toolMethod == 'shell_rich' ||
                toolMethod == 'run_background') {
              final cmd = toolParams['command']?.toString() ?? '';
              final allowed = await _askShellPermission(cmd);
              if (!allowed) {
                toolOutputs.add(
                  'Tool Result [${toolMethod}]:\n\n{"error": "User denied shell command execution."}',
                );
                continue;
              }
            }
            if (_requiresFileMutationPermission(toolMethod, toolParams)) {
              final allowed = await _askFileMutationPermission(
                toolMethod,
                toolParams,
              );
              if (!allowed) {
                toolOutputs.add(
                  'Tool Result [${toolMethod}]:\n\n{"error": "User denied file operation."}',
                );
                continue;
              }
            }

            // Show live status banner
            if (mounted)
              setState(
                () => _toolStatus = _toolStatusLabel(toolMethod, toolParams),
              );

            String mcpResult = '';
            int maxRetries = 3;
            int attempt = 0;
            while (attempt < maxRetries) {
              attempt++;
              HttpClient? client;
              try {
                client = HttpClient()
                  ..connectionTimeout = const Duration(seconds: 120);
                final request = await client.postUrl(Uri.parse(mcpEndpoint))
                    .timeout(const Duration(seconds: 120));
                request.headers.contentType = ContentType.json;

                final bytes = utf8.encode(jsonString);
                request.headers.contentLength = bytes.length;
                request.add(bytes);

                final response = await request.close()
                    .timeout(const Duration(seconds: 120));
                final body = await response.transform(utf8.decoder).join()
                    .timeout(const Duration(seconds: 120));
                
                String cleanResult = body;
                try {
                  final parsed = jsonDecode(body) as Map<String, dynamic>;
                  final resultData =
                      parsed['result'] as Map<String, dynamic>? ?? parsed;

                  if (resultData.containsKey('aiBlock')) {
                    cleanResult = resultData['aiBlock'].toString();
                  } else if (resultData.containsKey('stdout')) {
                    cleanResult = resultData['stdout'].toString();
                    if (resultData.containsKey('diff') &&
                        resultData['diff'].toString().isNotEmpty) {
                      cleanResult +=
                          '\n\n--- DIFF ---\n' + resultData['diff'].toString();
                    }
                    if (resultData.containsKey('stderr') &&
                        resultData['stderr'].toString().trim().isNotEmpty) {
                      cleanResult +=
                          '\n\n--- STDERR ---\n' +
                          resultData['stderr'].toString();
                    }
                  } else if (resultData.containsKey('error')) {
                    cleanResult = 'Error: ' + resultData['error'].toString();
                  }
                } catch (_) {
                  // Fallback to raw body if not JSON
                }
                
                mcpResult = cleanResult;
                if (mcpResult.length > 32000) {
                  mcpResult =
                      mcpResult.substring(0, 16000) +
                      '\n\n...[middle truncated — ${mcpResult.length - 22000} chars removed]...\n\n' +
                      mcpResult.substring(mcpResult.length - 6000);
                }
                break; // Success, break out of retry loop.
              } catch (e) {
                if (attempt >= maxRetries) {
                  mcpResult = '{"error": "MCP bridge connection failed after $maxRetries attempts: $e"}';
                } else {
                  // Wait a short time before retrying
                  await Future.delayed(Duration(milliseconds: 500 * attempt));
                }
              } finally {
                client?.close(force: true);
              }
            }
            if (mounted) setState(() => _toolStatus = '');
            toolOutputs.add("Tool Result [${toolMethod}]:\n\n$mcpResult");
          }
        }

        if (executedTools) {
          toolCallCount++;
          final resultsMessage = ChatMessage(
            role: MessageRole.system,
            text: toolOutputs.join("\n\n---\n\n"),
          );

          setState(() {
            final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
            if (idx != -1) {
              _sessions[idx] = _sessions[idx].copyWith(
                messages: [..._sessions[idx].messages, resultsMessage],
              );
            }
          });

          if (targetSessionId == _activeSessionId) {
            _scrollToBottom();
          }
          await Future.delayed(const Duration(seconds: 2));
        } else {
          shouldContinue = false;
        }
      }
      await _saveSessions();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
        if (idx != -1) {
          final currentMessages = List<ChatMessage>.from(
            _sessions[idx].messages,
          );
          if (currentMessages.isNotEmpty) {
            // Find the last user message to see if it had attachments
            ChatMessage? lastUserMsg;
            for (int i = currentMessages.length - 1; i >= 0; i--) {
              if (currentMessages[i].role == MessageRole.user) {
                lastUserMsg = currentMessages[i];
                break;
              }
            }
            String attachmentInfo = '';
            if (lastUserMsg != null) {
              if (lastUserMsg.images.isNotEmpty) {
                attachmentInfo = 'image';
              } else if (lastUserMsg.videos.isNotEmpty) {
                attachmentInfo = 'video';
              } else if (lastUserMsg.files.isNotEmpty) {
                attachmentInfo = 'file';
              }
            }

            final lastIdx = currentMessages.length - 1;
            final currentText = currentMessages[lastIdx].text;

            String errorMsg = error.toString();
            if (attachmentInfo.isNotEmpty) {
              errorMsg = 'This model does not support $attachmentInfo attachments. ($error)';
            }

            currentMessages[lastIdx] = ChatMessage(
              role: MessageRole.assistant,
              text: currentText.isNotEmpty
                  ? '$currentText\n\n[Error: $errorMsg]'
                  : 'Request failed: $errorMsg',
              isError: true,
            );
            _sessions[idx] = _sessions[idx].copyWith(messages: currentMessages);
          }
        }
      });
      await _saveSessions();
    } finally {
      if (mounted) {
        setState(() {
          _sendingSessionIds.remove(targetSessionId);
        });
        if (targetSessionId == _activeSessionId) {
          _scrollToBottom();
        }
        ChatClient.fetchLiveWallet();
      }
    }
  }

  List<ChatMessage> _compactHistoryForApi(List<ChatMessage> messages, int assistantMessageIndex) {
    final List<ChatMessage> rawHistory = messages.take(assistantMessageIndex).toList();
    if (rawHistory.length <= 4) {
      return rawHistory;
    }

    final List<ChatMessage> compacted = [];
    
    // Always keep the first message (initial instruction/goal)
    compacted.add(rawHistory.first);

    // Preserve the last 3 messages fully to maintain immediate conversation flow
    final intermediateEndIndex = rawHistory.length - 4;

    for (int i = 1; i < rawHistory.length; i++) {
      final msg = rawHistory[i];
      
      if (i > intermediateEndIndex) {
        compacted.add(msg);
        continue;
      }

      // Compact intermediate messages to reduce token footprint
      if (msg.role == MessageRole.system) {
        String newText = msg.text;
        
        if (newText.length > 8000) {
          final toolResultMatch = RegExp(r'Tool Result \[(\w+)\]').firstMatch(newText);
          final mcpMatch = newText.contains('MCP Result:\n');
          
          if (toolResultMatch != null) {
            final method = toolResultMatch.group(1);
            newText = 'Tool Result [$method]:\n\n'
                '[System: Detailed tool output (${newText.length} characters) omitted for context space. Operation completed successfully.]';
          } else if (mcpMatch) {
            newText = 'MCP Result:\n\n'
                '[System: Detailed MCP tool output (${newText.length} characters) omitted for context space. Operation completed successfully.]';
          } else if (newText.startsWith('Search results:\n') || newText.startsWith('Web Search results')) {
            newText = '🔍 Web Search Results:\n\n'
                '[System: Search results omitted for context space.]';
          } else if (newText.startsWith('URL Content:\n') || newText.startsWith('Content of URL')) {
            newText = '🌐 URL Content:\n\n'
                '[System: Webpage content omitted for context space.]';
          } else {
            // General truncation for very long intermediate system messages
            newText = newText.substring(0, 500) +
                '\n\n... [${newText.length - 1000} characters omitted for context space] ...\n\n' +
                newText.substring(newText.length - 500);
          }
        }
        
        compacted.add(ChatMessage(
          role: msg.role,
          text: newText,
          isError: msg.isError,
          reasoning: msg.reasoning,
          images: msg.images,
          videos: msg.videos,
          files: const [], // Strip files from intermediate system messages
        ));
      } else if (msg.role == MessageRole.assistant) {
        String newText = msg.text;
        
        if (newText.length > 2500) {
          newText = newText.replaceAllMapped(
            RegExp(r'<content>([\s\S]{1000,})</content>'),
            (match) => '<content>... [Code content of length ${match.group(1)!.length} characters omitted for context space] ...</content>',
          );
          newText = newText.replaceAllMapped(
            RegExp(r'<new_content>([\s\S]{1000,})</new_content>'),
            (match) => '<new_content>... [New code content of length ${match.group(1)!.length} characters omitted for context space] ...</new_content>',
          );
          newText = newText.replaceAllMapped(
            RegExp(r'<patches>([\s\S]{1000,})</patches>'),
            (match) => '<patches>... [Patches data of length ${match.group(1)!.length} characters omitted] ...</patches>',
          );
        }
        
        compacted.add(ChatMessage(
          role: msg.role,
          text: newText,
          isError: msg.isError,
          reasoning: msg.reasoning,
          images: msg.images,
          videos: msg.videos,
          files: const [],
        ));
      } else if (msg.role == MessageRole.user) {
        compacted.add(ChatMessage(
          role: msg.role,
          text: msg.text,
          isError: msg.isError,
          reasoning: msg.reasoning,
          images: msg.images,
          videos: msg.videos,
          files: const [], // Strip attached files from intermediate user messages to avoid re-sending large base64 contents
        ));
      }
    }

    return compacted;
  }

  /// Show permission dialog before executing a shell command.
  /// Returns true if the command should proceed.
  Future<bool> _askShellPermission(String command) async {
    // Already allowed globally
    if (_shellPermission == 'always') return true;
    // Already allowed for this session
    if (_shellSessionAllow) return true;
    // User previously denied always
    if (_shellPermission == 'never') return false;

    if (!mounted) return false;

    final short = command.length > 80
        ? command.substring(0, 77) + '…'
        : command;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5DDD3), width: 1),
        ),
        title: Row(
          children: const [
            Icon(Icons.gpp_maybe_outlined, color: Color(0xFF7B4E2E), size: 24),
            SizedBox(width: 10),
            Text(
              'Run Shell Command?',
              style: TextStyle(
                color: Color(0xFF2D241C),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'An AI agent is requesting permission to execute the following command in your Termux environment:',
              style: TextStyle(
                color: Color(0xFF6C5946),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1915),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCCBB8), width: 1),
              ),
              child: SelectableText(
                short,
                style: const TextStyle(
                  color: Color(0xFFFFF7EC),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                Icon(Icons.info_outline, color: Color(0xFF8A7765), size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Executing commands can modify files or interact with the system.',
                    style: TextStyle(
                      color: Color(0xFF8A7765),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(
                      Icons.all_inclusive,
                      size: 14,
                      color: Color(0xFF7B4E2E),
                    ),
                    onPressed: () => Navigator.pop(ctx, 'always'),
                    label: const Text(
                      'Always Allow',
                      style: TextStyle(color: Color(0xFF7B4E2E), fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.forum_outlined,
                      size: 14,
                      color: Color(0xFF7B4E2E),
                    ),
                    onPressed: () => Navigator.pop(ctx, 'session'),
                    label: const Text(
                      'Allow this session',
                      style: TextStyle(color: Color(0xFF7B4E2E), fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5DDD3)),
                        foregroundColor: Colors.red[700],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx, 'no'),
                      child: const Text(
                        'Block',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B4E2E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(ctx, 'yes'),
                      child: const Text(
                        'Allow Once',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (result == null || result == 'no') return false;
    if (result == 'always') {
      setState(() => _shellPermission = 'always');
      await _saveSettings();
      return true;
    }
    if (result == 'session') {
      setState(() => _shellSessionAllow = true);
      return true;
    }
    return true; // 'yes'
  }

  bool _requiresFileMutationPermission(
    String method,
    Map<String, dynamic> params,
  ) {
    const mutatingFileTools = {
      'write_file',
      'write_file_rich',
      'edit_file',
      'patch_file',
      'replace_lines',
      'insert_lines',
      'delete_lines',
      'append_file',
      'delete_path',
      'move_path',
      'copy_path',
      'mkdir_path',
      'chmod_path',
      'file_write',
      'file_edit',
      'file_delete',
      'dir_create',
    };
    if (method == 'dart_format') {
      final output = params['output']?.toString().toLowerCase().trim();
      return output == null || output.isEmpty || output == 'write';
    }
    return mutatingFileTools.contains(method);
  }

  String _fileMutationTarget(String method, Map<String, dynamic> params) {
    String value(String key) => params[key]?.toString().trim() ?? '';
    final src = value('src');
    final dest = value('dest');
    if (src.isNotEmpty && dest.isNotEmpty) return '$src → $dest';
    for (final key in ['path', 'file', 'directory', 'dir', 'cwd']) {
      final candidate = value(key);
      if (candidate.isNotEmpty) return candidate;
    }
    return _agenticWorkspace;
  }

  String _fileMutationPreview(Map<String, dynamic> params) {
    for (final key in ['content', 'new_content', 'patches', 'mode']) {
      final value = params[key]?.toString() ?? '';
      if (value.trim().isNotEmpty) {
        return value.length > 600 ? '${value.substring(0, 600)}…' : value;
      }
    }
    return '';
  }

  Future<bool> _askFileMutationPermission(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!mounted) return false;
    final target = _fileMutationTarget(method, params);
    final preview = _fileMutationPreview(params);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5DDD3), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.edit_document, color: Color(0xFF9B4D39), size: 23),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Allow File Change?',
                style: TextStyle(
                  color: Color(0xFF2D241C),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The AI wants to modify files in your workspace. Review the target before allowing this operation.',
                  style: TextStyle(
                    color: Color(0xFF6C5946),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _PermissionInfoRow(label: 'Tool', value: method),
                const SizedBox(height: 8),
                _PermissionInfoRow(label: 'Target', value: target),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Preview',
                    style: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1915),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      preview,
                      style: const TextStyle(
                        color: Color(0xFFFFF7EC),
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5DDD3)),
                    foregroundColor: const Color(0xFFB3261E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Block',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B4E2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Allow Once',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result == true;
  }

  Match? _findMcpMatch(String fullText) {
    // 0. Try direct command format: <command>...</command> (case-insensitive with spacing support & unclosed fallback)
    final cmdStartMatch = RegExp(r'<command\s*>', caseSensitive: false).firstMatch(fullText);
    if (cmdStartMatch != null) {
      final cmdEndMatch = RegExp(r'</command\s*>', caseSensitive: false).firstMatch(fullText);
      final String commandVal;
      if (cmdEndMatch != null) {
        commandVal = fullText.substring(cmdStartMatch.end, cmdEndMatch.start).trim();
      } else {
        commandVal = fullText.substring(cmdStartMatch.end).trim();
      }
      final jsonStr = jsonEncode({
        'method': 'run_command',
        'params': {
          'command': commandVal,
          'cwd': '', // will be set to _agenticWorkspace in dispatch block
        },
      });
      return RegExp(r'([\s\S]*)').firstMatch(jsonStr);
    }

    // 1. Try XML format: <tool_request>...<method>x</method>...<param>val</param>...</tool_request> (case-insensitive & unclosed fallback)
    final xmlStartMatch = RegExp(r'<tool_request\s*>', caseSensitive: false).firstMatch(fullText);
    String? xmlContent;
    if (xmlStartMatch != null) {
      final xmlEndMatch = RegExp(r'</tool_request\s*>', caseSensitive: false).firstMatch(fullText);
      if (xmlEndMatch != null) {
        xmlContent = fullText.substring(xmlStartMatch.end, xmlEndMatch.start);
      } else {
        xmlContent = fullText.substring(xmlStartMatch.end);
      }
    } else {
      // Robustness: If <tool_request> is missing but <method> is present, parse the whole text as XML content
      final hasMethod = RegExp(r'<method\s*>', caseSensitive: false).hasMatch(fullText);
      if (hasMethod) {
        xmlContent = fullText;
      }
    }

    if (xmlContent != null) {
      final Map<String, dynamic> result = {};

      const preserveWhitespaceKeys = {
        'content',
        'new_content',
        'patches',
        'reads',
      };

      String cleanToolValue(String key, String value) {
        if (preserveWhitespaceKeys.contains(key)) {
          var result = value;
          if (result.startsWith('\n')) result = result.substring(1);
          if (result.endsWith('\n'))
            result = result.substring(0, result.length - 1);
          return result;
        }
        return value.trim();
      }

      // Primary: <tagname attr="...">value</tagname> case-insensitively with tag spacing
      final regex = RegExp(
        r'<([a-zA-Z0-9_]+)(?:\s+[^>]*?)?>([\s\S]*?)</\1\s*>',
        caseSensitive: false,
      );
      for (final match in regex.allMatches(xmlContent)) {
        final key = match.group(1)!.toLowerCase();
        result[key] = cleanToolValue(key, match.group(2)!);
      }

      // Fallback: <PARAM name="key">value</PARAM>
      final paramRegex = RegExp(
        r'''<[Pp][Aa][Rr][Aa][Mm]\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp][Aa][Rr][Aa][Mm]>''',
      );
      for (final m in paramRegex.allMatches(xmlContent)) {
        final key = m.group(1)!.toLowerCase();
        result[key] = cleanToolValue(key, m.group(2)!);
      }

      // Also try <parameter name="key">value</parameter>
      final paramRegex2 = RegExp(
        r'''<[Pp]arameter\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp]arameter>''',
        caseSensitive: false,
      );
      for (final m in paramRegex2.allMatches(xmlContent)) {
        final key = m.group(1)!.toLowerCase();
        result[key] = cleanToolValue(key, m.group(2)!);
      }

      if (result.containsKey('method')) {
        for (final key in [
          'method',
          'path',
          'query',
          'start_line',
          'end_line',
          'pattern',
          'command',
        ]) {
          if (result.containsKey(key) && result[key] is String) {
            result[key] = (result[key] as String).trim();
          }
        }
        final method = result['method'];
        result.remove('method');
        final jsonStr = jsonEncode({'method': method, 'params': result});
        return RegExp(r'([\s\S]*)').firstMatch(jsonStr);
      }
    }

    // 2. Fallback to old JSON format
    final mcpStart = fullText.indexOf('<mcp_request>');
    if (mcpStart == -1) return null;

    final jsonStart = fullText.indexOf('{', mcpStart);
    if (jsonStart == -1) return null;

    final jsonEnd = _findMatchingBracket(fullText, jsonStart);
    if (jsonEnd == -1) return null;

    final jsonStr = fullText.substring(jsonStart, jsonEnd + 1);

    return RegExp(
      r'<mcp_request>\s*(\{[\s\S]*?\})\s*</mcp_request>',
      caseSensitive: false,
    ).firstMatch('<mcp_request>$jsonStr</mcp_request>');
  }

  int _findMatchingBracket(String text, int startIndex) {
    int count = 0;
    bool inString = false;
    bool escape = false;

    for (int i = startIndex; i < text.length; i++) {
      final c = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (c == '{' || c == '[')
        count++;
      else if (c == '}' || c == ']') {
        count--;
        if (count == 0) return i;
      }
    }
    return -1;
  }

  String _getResearchFileName(String title) {
    var cleanTitle = title.trim();
    if (cleanTitle.endsWith('...')) {
      cleanTitle = cleanTitle.substring(0, cleanTitle.length - 3).trim();
    }
    final lowerTitle = cleanTitle.toLowerCase();
    if (lowerTitle.startsWith('research ')) {
      cleanTitle = cleanTitle.substring(9).trim();
    } else if (lowerTitle.startsWith('research:')) {
      cleanTitle = cleanTitle.substring(9).trim();
    } else if (lowerTitle.startsWith('research')) {
      cleanTitle = cleanTitle.substring(8).trim();
    }

    final slug = cleanTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'[\s-]+'), '_');
    final normalizedSlug = slug.replaceAll(RegExp(r'^_+|_+$'), '');
    return 'research_${normalizedSlug.isEmpty ? 'report' : normalizedSlug}.md';
  }

  String _stripSvgVisuals(String markdown) {
    return markdown
        .replaceAll(
          RegExp(r'<svg\b[^>]*(?:/>|>[\s\S]*?</svg>)', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'!\[[^\]]*\]\([^)]*\.svg(?:\?[^)]*)?\)', caseSensitive: false),
          '',
        );
  }

  Future<String> _persistResearchReport(String fileName, String content) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  String _updateResearchStateInText(String oldText, Map<String, dynamic> stateMap) {
    final newStateStr = '<research_state>${jsonEncode(stateMap)}</research_state>';
    final startIdx = oldText.indexOf('<research_state>');
    if (startIdx == -1) {
      return oldText.isEmpty ? newStateStr : '$oldText\n\n$newStateStr';
    }
    final endIdx = oldText.indexOf('</research_state>', startIdx);
    if (endIdx == -1) {
      return oldText.substring(0, startIdx) + newStateStr;
    }
    return oldText.substring(0, startIdx) + newStateStr + oldText.substring(endIdx + 17);
  }

  String _preprocessUnrecognizedToolCalls(String text, List<Map<String, dynamic>> unrecognizedErrors) {
    final pattern = RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_\.:]*)\s*\{');
    var offset = 0;
    var result = text;
    while (true) {
      if (offset >= result.length) break;
      final match = pattern.firstMatch(result.substring(offset));
      if (match == null) break;
      final matchStart = offset + match.start;
      final name = match.group(1)!.trim();
      final braceStart = offset + match.end - 1;
      int braceEnd = -1;
      int depth = 1;
      for (int j = braceStart + 1; j < result.length; j++) {
        if (result[j] == '{') {
          depth++;
        } else if (result[j] == '}') {
          depth--;
          if (depth == 0) {
            braceEnd = j;
            break;
          }
        }
      }
      if (braceEnd == -1) {
        offset = braceStart + 1;
        continue;
      }
      final paramsText = result.substring(braceStart + 1, braceEnd).trim();
      final fullMatchText = result.substring(matchStart, braceEnd + 1);
      final nameLower = name.toLowerCase();
      bool isKnownTool = false;
      String? mappedTool;
      if (nameLower.contains('read_url') || nameLower.contains('readurl') || nameLower.contains('fetch')) {
        isKnownTool = true;
        mappedTool = 'read_url';
      } else if (nameLower.contains('web_search') || nameLower.contains('search_web') || nameLower.contains('search_request') || (nameLower.contains('search') && !nameLower.contains('research'))) {
        isKnownTool = true;
        mappedTool = 'search_request';
      } else if (nameLower.contains('mcp_request') || nameLower.contains('mcp_call') || (nameLower.contains('mcp') && !nameLower.contains('mcp_server'))) {
        isKnownTool = true;
        mappedTool = 'mcp_request';
      }
      if (isKnownTool) {
        bool reinterpreted = false;
        String replacement = '';
        if (mappedTool == 'read_url') {
          final urlRegex = RegExp('https?://[^\\s"\'\\}]+');
          final urlMatch = urlRegex.firstMatch(paramsText);
          if (urlMatch != null) {
            final url = urlMatch.group(0)!;
            replacement = '<read_url>$url</read_url>';
            reinterpreted = true;
          }
        } else if (mappedTool == 'search_request') {
          final queryRegex1 = RegExp('(?:query|q)[:\\s="\']+\\s*["\']([^"\']+)["\']');
          final queryRegex2 = RegExp('(?:query|q)[:\\s="\']+\\s*([^\\s"\'\\}]+)');
          final quotedRegex = RegExp('["\']([^"\']+)["\']');
          String? query;
          final mq1 = queryRegex1.firstMatch(paramsText);
          if (mq1 != null) {
            query = mq1.group(1);
          } else {
            final mq2 = queryRegex2.firstMatch(paramsText);
            if (mq2 != null) {
              query = mq2.group(1);
            } else {
              final mqQuoted = quotedRegex.firstMatch(paramsText);
              if (mqQuoted != null) {
                query = mqQuoted.group(1);
              } else if (paramsText.isNotEmpty) {
                query = paramsText;
              }
            }
          }
          if (query != null && query.trim().isNotEmpty) {
            replacement = '<search_request>${query.trim()}</search_request>';
            reinterpreted = true;
          }
        } else if (mappedTool == 'mcp_request') {
          String finalJson = paramsText;
          if (!paramsText.startsWith('{')) {
            finalJson = '{$paramsText}';
          }
          try {
            jsonDecode(finalJson);
            replacement = '<mcp_request>$finalJson</mcp_request>';
            reinterpreted = true;
          } catch (_) {
            replacement = '<mcp_request>$finalJson</mcp_request>';
            reinterpreted = true;
          }
        }
        if (reinterpreted) {
          result = result.substring(0, matchStart) + replacement + result.substring(braceEnd + 1);
          offset = matchStart + replacement.length;
        } else {
          unrecognizedErrors.add({
            'tool': name,
            'error': 'Unrecognized tool call syntax with unparseable parameters: $fullMatchText',
          });
          offset = braceEnd + 1;
        }
      } else {
        final isGenericCallShape = name.contains(':') || nameLower.startsWith('call') || nameLower.startsWith('tool') || nameLower.startsWith('request');
        if (isGenericCallShape) {
          unrecognizedErrors.add({
            'tool': name,
            'error': 'Generic tool call attempt in unrecognized format: $fullMatchText',
          });
        }
        offset = braceEnd + 1;
      }
    }
    return result;
  }



  /// Returns a human-readable status label for a tool call, e.g.:
  ///   "📖 Reading main.dart lines 10–50"
  ///   "✏️ Writing /home/project/lib/main.dart"
  ///   "🚀 Deploying to Firebase"
  ///   "🔧 Running: git status"
  String _toolStatusLabel(String method, Map<String, dynamic> params) {
    String p(String key) => params[key]?.toString() ?? '';
    String shortPath(String path) {
      if (path.isEmpty) return '';
      final parts = path.split('/');
      return parts.length > 2 ? '…/${parts.last}' : path;
    }

    switch (method) {
      case 'read_file_rich':
      case 'file_read':
        final path = shortPath(p('path'));
        final start = p('start_line');
        final end = p('end_line');
        if (start.isNotEmpty && end.isNotEmpty) {
          return '📖 Reading $path lines $start–$end';
        }
        return '📖 Reading $path';
      case 'multi_read_rich':
      case 'multi_read':
        return '📖 Batch reading files…';
      case 'patch_file':
        return '✏️  Patching ${shortPath(p('path'))}';
      case 'replace_lines':
        return '✏️  Replacing lines ${p('start_line')}–${p('end_line')} in ${shortPath(p('path'))}';
      case 'insert_lines':
        return '✏️  Inserting after line ${p('after_line')} in ${shortPath(p('path'))}';
      case 'delete_lines':
        return '🗑️  Deleting lines ${p('start_line')}–${p('end_line')} in ${shortPath(p('path'))}';
      case 'write_file_rich':
      case 'file_write':
        return '✏️  Writing ${shortPath(p('path'))}';
      case 'search_rich':
      case 'file_search':
      case 'code_search':
        return '🔎 Searching: "${p('query')}${p('pattern')}" in ${shortPath(p('path'))}';
      case 'file_outline':
        return '🗂️  Outline: ${shortPath(p('path'))}';
      case 'tree':
        return '📂 Tree: ${shortPath(p('path'))}';
      case 'diff_files':
        return '🔍 Diffing files…';
      case 'file_edit':
        final path2 = shortPath(p('path'));
        final start2 = p('start_line');
        final end2 = p('end_line');
        if (start2.isNotEmpty && end2.isNotEmpty) {
          return '✏️  Editing $path2 lines $start2–$end2';
        }
        return '✏️  Editing $path2';
      case 'file_delete':
        return '🗑️  Deleting ${shortPath(p('path'))}';
      case 'dir_list':
        return '📂 Listing ${shortPath(p('path'))}';
      case 'dir_create':
        return '📁 Creating dir ${shortPath(p('path'))}';
      case 'find_paths':
        return '🔎 Finding paths matching: ${p('pattern')}';
      case 'symbol_search':
        return '🔎 Symbol search: ${p('symbol')}';
      case 'file_info':
        return '📋 File info: ${shortPath(p('path'))}';
      case 'run_command':
      case 'shell_rich':
        final cmd = p('command');
        final short = cmd.length > 45 ? '${cmd.substring(0, 42)}…' : cmd;
        if (cmd.contains('firebase deploy')) return '🚀 Deploying to Firebase…';
        if (cmd.contains('gh workflow run'))
          return '⚙️  Triggering GitHub Actions…';
        if (cmd.contains('gh run watch'))
          return '⏳ Watching GitHub Actions build…';
        if (cmd.contains('gh run download'))
          return '⬇️  Downloading build artifact…';
        if (cmd.contains('git commit')) return '📦 Committing to Git…';
        if (cmd.contains('git push')) return '📤 Pushing to GitHub…';
        if (cmd.contains('git status')) return '📊 Checking git status…';
        if (cmd.contains('git diff')) return '🔍 Checking git diff…';
        if (cmd.contains('flutter build')) return '🔨 Building Flutter app…';
        if (cmd.contains('flutter test')) return '🧪 Running Flutter tests…';
        if (cmd.contains('dart analyze')) return '🧹 Running Dart analysis…';
        if (cmd.contains('pkg install')) return '📦 Installing package…';
        return '🔧 Running: $short';
      case 'dart_diagnostics':
      case 'dart_analyze':
        return '🧹 Running Dart diagnostics…';
      case 'dart_format':
        return '🎯 Formatting Dart: ${shortPath(p('path'))}';
      case 'symbol_references':
        return '🔎 Finding references: ${p('symbol')}';
      case 'git_status':
        return '📊 Checking git status…';
      case 'git_diff':
        return '🔍 Checking git diff…';
      case 'append_file':
        return '📝 Appending to ${shortPath(p('path'))}';
      case 'delete_path':
        return '🗑️  Deleting ${shortPath(p('path'))}${p('recursive') == 'true' ? ' (recursive)' : ''}';
      case 'move_path':
        return '📦 Moving ${shortPath(p('src'))} → ${shortPath(p('dest'))}';
      case 'copy_path':
        return '📋 Copying ${shortPath(p('src'))} → ${shortPath(p('dest'))}';
      case 'mkdir_path':
        return '📁 Creating dir ${shortPath(p('path'))}';
      case 'stat_path':
        return '📊 Getting info: ${shortPath(p('path'))}';
      case 'chmod_path':
        return '🔒 Chmod ${p('mode')} on ${shortPath(p('path'))}';
      case 'run_background':
        return '🚀 Starting background service: ${shortPath(p('command'))}';
      case 'list_services':
        return '📋 Listing background services…';
      case 'service_status':
        return 'ℹ️ Checking service status: ${p('id')}';
      case 'service_logs':
        return '📄 Fetching service logs: ${p('id')}';
      case 'stop_service':
        return '⏹️ Stopping service: ${p('id')}';
      case 'wait_for_background':
      case 'background_time_limit':
        final target = p('pid') ?? p('id') ?? '';
        final secs = p('time_limit_seconds') ?? '15';
        return '⏳ Waiting for background process $target (${secs}s limit)';
      default:
        return '⚙️  Tool: $method';
    }
  }

  void _startResearchLoop(
    int messageIndex, [
    Map<String, dynamic>? editedStateMap,
  ]) {
    final activeSession = _sessions.firstWhere((s) => s.id == _activeSessionId);
    final sessionIndex = _sessions.indexOf(activeSession);
    if (sessionIndex == -1) return;

    final message = activeSession.messages[messageIndex];
    if (!message.text.contains('<research_state>')) return;

    final stateStr = message.text
        .substring(
          message.text.indexOf('<research_state>') + 16,
          message.text.indexOf('</research_state>'),
        )
        .trim();
    try {
      final stateMap = editedStateMap ??
          (jsonDecode(stateStr) as Map<String, dynamic>);
      stateMap['status'] = 'running';

      setState(() {
        _sendingSessionIds.add(_sessions[sessionIndex].id);
        final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
        msgs[messageIndex] = ChatMessage(
          role: MessageRole.assistant,
          text: message.text.replaceRange(
            message.text.indexOf('<research_state>'),
            message.text.indexOf('</research_state>') + 17,
            '<research_state>${jsonEncode(stateMap)}</research_state>',
          ),
          reasoning: message.reasoning,
        );
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
          messages: msgs,
        );
      });

      _runResearchLoop(
        sessionIndex: sessionIndex,
        messageIndex: messageIndex,
        stateMap: stateMap,
        provider: _provider,
        settings: _activeSettings,
        model: _activeModel,
      );
    } catch (e) {
      debugPrint('Error parsing state map on start: $e');
    }
  }

  void _publishResearchState(
    int sessionIndex,
    int messageIndex,
    Map<String, dynamic> stateMap,
  ) {
    if (!mounted) return;
    setState(() {
      final messages = List<ChatMessage>.from(_sessions[sessionIndex].messages);
      messages[messageIndex] = ChatMessage(
        role: MessageRole.assistant,
        text: _updateResearchStateInText(messages[messageIndex].text, stateMap),
        reasoning: messages[messageIndex].reasoning,
      );
      _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
        messages: messages,
      );
    });
  }

  // Bound state persisted into <research_state>; all limits are UTF-8 bytes.
  String _truncateEventText(String value, int maxBytes) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxBytes) return value;
    const ellipsis = '…';
    final budget = maxBytes - utf8.encode(ellipsis).length;
    final buffer = StringBuffer();
    var usedBytes = 0;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (usedBytes + characterBytes > budget) break;
      buffer.write(character);
      usedBytes += characterBytes;
    }
    return '${buffer.toString()}$ellipsis';
  }

  String _eventPlainText(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Map<String, dynamic> _compactSearchPayload(Iterable<Map> results) {
    return {
      'results': results.take(6).map((result) {
        return {
          'title': _truncateEventText(result['title']?.toString() ?? '', 120),
          'url': _truncateEventText(result['url']?.toString() ?? '', 300),
          'snippet': _truncateEventText(
            result['snippet']?.toString() ??
                result['description']?.toString() ??
                '',
            150,
          ),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _compactReadUrlPayload({
    required String url,
    required String content,
  }) {
    return {
      'url': _truncateEventText(url, 300),
      'content_preview': _truncateEventText(_eventPlainText(content), 200),
    };
  }

  Map<String, dynamic> _compactMcpPayload({
    required String kind,
    required Map<String, dynamic> params,
    required Map<String, dynamic>? resultData,
    required String rawResult,
  }) {
    final nestedData = resultData?['data'];
    final data = nestedData is Map
        ? Map<String, dynamic>.from(nestedData)
        : resultData;
    if (kind == 'search') {
      final results = resultData?['results'] ?? data?['results'];
      if (results is List) {
        return _compactSearchPayload(
          results.whereType<Map>().map(Map<String, dynamic>.from),
        );
      }
    } else if (kind == 'fetch') {
      final content = data?['content'] ??
          data?['text'] ??
          data?['body'] ??
          data?['markdown'] ??
          rawResult;
      return _compactReadUrlPayload(
        url: (data?['url'] ?? params['url'] ?? params['uri'] ?? '').toString(),
        content: content.toString(),
      );
    }
    return {'summary': _truncateEventText(_eventPlainText(rawResult), 150)};
  }

  // _getModelContextSize removed: writer evidence budget is now controlled
  // exclusively by the user-configured _writerContextBudget setting.

  Future<void> _runResearchLoop({
    required int sessionIndex,
    required int messageIndex,
    required Map<String, dynamic> stateMap,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    _runUrlCache.clear();
    final Set<String> runFetchedUrls = {};
    final Map<String, Map<String, dynamic>> runUrlSummaries = {};

    try {
      await _resetDeepResearch();

      final activeSession = _sessions[sessionIndex];
      final prompt = activeSession.messages[messageIndex - 1].text;

      // ── STAGE 1: PLANNING ──
      stateMap['status'] = 'planning';
      stateMap['plan_start_ms'] = DateTime.now().millisecondsSinceEpoch;
      _publishResearchState(sessionIndex, messageIndex, stateMap);

      final List<ChatMessage> plannerMessages = [
        const ChatMessage(
          role: MessageRole.system,
          text: DeepResearchPrompts.plannerSystemPrompt,
        ),
        ChatMessage(
          role: MessageRole.user,
          text: "Analyze the user's research request and output a detailed research plan. "
              "Research Request: \"$prompt\"",
        ),
      ];

      String planText = '';
      String plannerReasoning = '';
      final plannerStream = _chatClient.sendChatStream(
        provider: provider,
        settings: settings,
        model: model,
        messages: _compactHistoryForApi(plannerMessages, plannerMessages.length),
      );

      await for (final chunk in plannerStream) {
        if (chunk.startsWith('[REASONING]')) {
          plannerReasoning += chunk.substring(11);
        } else {
          var textChunk = chunk;
          if (textChunk.contains('<think>') || textChunk.contains('<reasoning>') || textChunk.contains('<thought>')) {
            textChunk = textChunk.replaceAll(RegExp(r'<think>|<reasoning>|<thought>|</think>|</reasoning>|</thought>'), '');
          }
          planText += textChunk;
        }
      }

      final List<Map<String, dynamic>> steps = [];
      final stepMatches = RegExp(r"<phase\s*(\d+)\s*>(.*?)</phase\s*\1\s*>", caseSensitive: false, dotAll: true).allMatches(planText);
      
      int stepIdx = 1;
      for (final match in stepMatches) {
        final title = "Phase $stepIdx";
        final queryText = match.group(2)?.trim() ?? '';
        steps.add({
          'id': 'step_$stepIdx',
          'title': title,
          'query_text': queryText,
          'status': 'pending',
          'content': '',
          'events': <Map<String, dynamic>>[],
        });
        stepIdx++;
      }

      if (steps.isEmpty) {
        steps.add({
          'id': 'step_1',
          'title': 'General Research',
          'query_text': prompt,
          'status': 'pending',
          'content': '',
          'events': <Map<String, dynamic>>[],
        });
      }

      stateMap['steps'] = steps;
      stateMap['status'] = 'running';
      _publishResearchState(sessionIndex, messageIndex, stateMap);

      // ── STAGE 2: MULTI-AGENT EXECUTION ──
      final int maxConcurrentFetchCalls = 6;
      final Duration globalTimeBudget = const Duration(minutes: 60);
      final DateTime startTime = DateTime.now();

      DateTime getGlobalElapsed() {
        return DateTime.now();
      }

      final List<Map<String, dynamic>> phaseFacts = [];
      final List<Map<String, dynamic>> phaseFindings = [];
      final List<Map<String, dynamic>> phaseSkippedPdfs = [];
      final List<Map<String, dynamic>> phaseFailedFetches = [];

      for (int i = 0; i < steps.length; i++) {
        final stageId = steps[i]['id'] as String;
        final phaseTitle = steps[i]['title'] as String;
        final queryText = steps[i]['query_text'] as String;
        // Keep each temp.json phase scoped to evidence gathered for that phase.
        phaseFacts.clear();
        phaseFindings.clear();
        phaseSkippedPdfs.clear();
        phaseFailedFetches.clear();

        if (startTime.add(globalTimeBudget).isBefore(DateTime.now())) {
          steps[i]['status'] = 'failed';
          steps[i]['error'] = 'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
          _publishResearchState(sessionIndex, messageIndex, stateMap);
          continue;
        }

        steps[i]['status'] = 'running';
        _publishResearchState(sessionIndex, messageIndex, stateMap);

        final String Function({
          required String kind,
          required String tool,
          String? query,
          String? url,
        }) beginResearchEvent = ({
          required String kind,
          required String tool,
          String? query,
          String? url,
        }) {
          final eventId = 'evt_${DateTime.now().millisecondsSinceEpoch}_${StackTrace.current.hashCode}';
          final newEvent = {
            'id': eventId,
            'kind': kind,
            'tool': tool,
            'status': 'running',
            if (query != null) 'query': query,
            if (url != null) 'url': url,
            'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
          };
          
          setState(() {
            final idx = (stateMap['steps'] as List).indexWhere((s) => s['id'] == stageId);
            if (idx != -1) {
              final evts = List<Map<String, dynamic>>.from(stateMap['steps'][idx]['events'] ?? []);
              evts.add(newEvent);
              stateMap['steps'][idx]['events'] = evts;
            }
          });
          _publishResearchState(sessionIndex, messageIndex, stateMap);
          return eventId;
        };

        final void Function(
          String eventId, {
          required String status,
          required Stopwatch stopwatch,
          Map<String, dynamic>? details,
          String? error,
        }) finishResearchEvent = (
          String eventId, {
          required String status,
          required Stopwatch stopwatch,
          Map<String, dynamic>? details,
          String? error,
        }) {
          stopwatch.stop();
          setState(() {
            final idx = (stateMap['steps'] as List).indexWhere((s) => s['id'] == stageId);
            if (idx != -1) {
              final evts = List<Map<String, dynamic>>.from(stateMap['steps'][idx]['events'] ?? []);
              final eIdx = evts.indexWhere((e) => e['id'] == eventId);
              if (eIdx != -1) {
                final updated = Map<String, dynamic>.from(evts[eIdx]);
                updated['status'] = status;
                updated['latency_ms'] = stopwatch.elapsedMilliseconds;
                if (details != null) {
                  updated.addAll(details);
                }
                if (error != null) {
                  updated['error'] = error;
                }
                evts[eIdx] = updated;
                stateMap['steps'][idx]['events'] = evts;
              }
            }
          });
          _publishResearchState(sessionIndex, messageIndex, stateMap);
        };

        final void Function(
          String eventId,
          String status, {
          Map<String, dynamic>? details,
        }) updateResearchEventStatus = (
          String eventId,
          String status, {
          Map<String, dynamic>? details,
        }) {
          setState(() {
            final idx = (stateMap['steps'] as List).indexWhere((s) => s['id'] == stageId);
            if (idx != -1) {
              final evts = List<Map<String, dynamic>>.from(stateMap['steps'][idx]['events'] ?? []);
              final eIdx = evts.indexWhere((e) => e['id'] == eventId);
              if (eIdx != -1) {
                final updated = Map<String, dynamic>.from(evts[eIdx]);
                updated['status'] = status;
                if (details != null) {
                  updated.addAll(details);
                }
                evts[eIdx] = updated;
                stateMap['steps'][idx]['events'] = evts;
              }
            }
          });
          _publishResearchState(sessionIndex, messageIndex, stateMap);
        };

        final List<ChatMessage> stepMessages = [
          const ChatMessage(
            role: MessageRole.system,
            text: DeepResearchPrompts.researchSystemPrompt,
          ),
          ChatMessage(
            role: MessageRole.user,
            text: "Your current research stage is: \"$phaseTitle\"\n"
                "Focus Area Instructions: $queryText\n\n"
                "Please formulate search queries or read specific URLs to gather evidence. "
                "Citing specific metrics, comparisons, and sources in your final response. "
                "When you are finished, write a concise summary of your findings and emit <step_complete/>.",
          ),
        ];

        bool stepDone = false;
        bool stepFailed = false;
        String? stepFailure;
        int loopCount = 0;
        int webSearchCount = 0;
        int readUrlCount = 0;
        int consecutiveMalformedTags = 0;
        final Map<String, String> stepSearchCache = {};
        String stepContent = '';

        while (!stepDone && loopCount < 30) {
          if (startTime.add(globalTimeBudget).isBefore(DateTime.now())) {
            stepDone = true;
            stepFailed = true;
            stepFailure = 'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
            break;
          }
          if (!mounted) return;
          loopCount++;

          final turnWatch = Stopwatch()..start();
          String responseText = '';
          String reasoningText = '';
          var isThinking = false;

          try {
            final stream = _chatClient.sendChatStream(
              provider: provider,
              settings: settings,
              model: model,
              messages: _compactHistoryForApi(stepMessages, stepMessages.length),
            );

            await for (final chunk in stream) {
              if (chunk.startsWith('[REASONING]')) {
                reasoningText += chunk.substring(11);
              } else {
                var textChunk = chunk;
                if (!isThinking &&
                    (textChunk.contains('<think>') ||
                        textChunk.contains('<reasoning>') ||
                        textChunk.contains('<thought>'))) {
                  final tag = textChunk.contains('<think>')
                      ? '<think>'
                      : textChunk.contains('<thought>')
                      ? '<thought>'
                      : '<reasoning>';
                  final parts = textChunk.split(tag);
                  responseText += parts[0];
                  isThinking = true;
                  textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
                }

                if (isThinking &&
                    (textChunk.contains('</think>') ||
                        textChunk.contains('</reasoning>') ||
                        textChunk.contains('</thought>'))) {
                  final tag = textChunk.contains('</think>')
                      ? '</think>'
                      : textChunk.contains('</thought>')
                      ? '</thought>'
                      : '</reasoning>';
                  final parts = textChunk.split(tag);
                  reasoningText += parts[0];
                  isThinking = false;
                  textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
                  responseText += textChunk;
                } else if (isThinking) {
                  reasoningText += textChunk;
                } else {
                  responseText += textChunk;
                }
              }
            }

            stepMessages.add(
              ChatMessage(
                role: MessageRole.assistant,
                text: responseText,
                reasoning: reasoningText,
              ),
            );
            turnWatch.stop();

            final unrecognizedErrors = <Map<String, dynamic>>[];
            final preprocessedText = _preprocessUnrecognizedToolCalls(responseText, unrecognizedErrors);

            Map<String, String> parseSearchAttributes(String attrStr) {
              final Map<String, String> attrs = {};
              final matches = RegExp(r'(\w+)="([^"]*)"').allMatches(attrStr);
              for (final m in matches) {
                attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
              }
              return attrs;
            }

            final searchMatches = RegExp(
              r'<search_request\b([^>]*)>\s*([\s\S]*?)\s*</search_request>',
              caseSensitive: false,
              dotAll: true,
            ).allMatches(preprocessedText).toList();

            final readUrlMatches = RegExp(
              r'<read_url>\s*([\s\S]*?)\s*</read_url>',
              caseSensitive: false,
              dotAll: true,
            ).allMatches(preprocessedText).toList();

            bool isMalformed = unrecognizedErrors.isNotEmpty;
            final hasRawSearchTag = preprocessedText.contains('<search_request') || preprocessedText.contains('</search_request');
            final hasRawReadTag = preprocessedText.contains('<read_url') || preprocessedText.contains('</read_url');

            if ((hasRawSearchTag && searchMatches.isEmpty) || (hasRawReadTag && readUrlMatches.isEmpty)) {
              isMalformed = true;
            }

            if (isMalformed) {
              consecutiveMalformedTags++;
              final eventWatch = Stopwatch()..start();
              final eventId = beginResearchEvent(kind: 'error', tool: 'malformed_tag');
              final String errMessage = unrecognizedErrors.isNotEmpty
                  ? unrecognizedErrors.map((e) => e['error']?.toString() ?? '').join('; ')
                  : 'Malformed tool call tag syntax detected in assistant response.';
              
              finishResearchEvent(
                eventId,
                status: 'error',
                stopwatch: eventWatch,
                error: errMessage,
              );

              if (consecutiveMalformedTags >= 3) {
                stepDone = true;
                stepFailed = true;
                stepFailure = 'Step failed after $consecutiveMalformedTags consecutive malformed tool calls.';
                break;
              }
              stepMessages.add(
                const ChatMessage(
                  role: MessageRole.user,
                  text: 'Error: Malformed or unclosed tool call tags detected. Please check tag syntax.',
                ),
              );
              continue;
            } else {
              consecutiveMalformedTags = 0;
            }

            final completeMatch = RegExp(r'<step_complete/?>', caseSensitive: false).firstMatch(responseText);

            if (completeMatch != null) {
              final contentClean = responseText.replaceAll(RegExp(r'<step_complete/?>', caseSensitive: false), '').trim();
              stepContent = stepContent.isEmpty ? contentClean : '$stepContent\n\n$contentClean';
              stepDone = true;
            } else if (searchMatches.isNotEmpty) {
              final List<Future<String>> searchFutures = [];
              final List<String> eventIds = [];
              final List<Stopwatch> stopwatches = [];
              final List<String> queries = [];
              final List<Map<String, String>> searchAttrsList = [];

              for (final match in searchMatches) {
                final attrsStr = match.group(1) ?? '';
                final query = match.group(2)?.trim() ?? '';
                queries.add(query);
                final attrs = parseSearchAttributes(attrsStr);
                searchAttrsList.add(attrs);

                final eventWatch = Stopwatch()..start();
                stopwatches.add(eventWatch);
                final eventId = beginResearchEvent(
                  kind: 'search',
                  tool: 'web_search',
                  query: query,
                );
                eventIds.add(eventId);
                stepContent = stepContent.isEmpty
                    ? '<search_request>$query</search_request>'
                    : '$stepContent\n\n<search_request>$query</search_request>';
              }

              steps[i]['content'] = stepContent;
              _publishResearchState(sessionIndex, messageIndex, stateMap);

              bool searchCapHit = false;
              for (var k = 0; k < searchMatches.length; k++) {
                final query = queries[k];
                final attrs = searchAttrsList[k];
                final normQuery = _normalizeQueryOrUrl(query);

                // TOOL LIMITS PER PHASE:
                // Capped at 20 web_search calls per research phase to focus the agent on high-relevance
                // Tavily search queries rather than infinite querying loops. This matches the accuracy-over-depth
                // priority of this project. If this limit is exceeded, we return a clear feedback message.
                if (webSearchCount >= 20) {
                  searchCapHit = true;
                  final limitMsg = 'Search limit reached for this phase (20/20 used). No further web_search calls are available this phase — proceed to reflection/summary with what has been gathered, or move to the next phase.';
                  searchFutures.add(Future.value('Error: $limitMsg'));
                  finishResearchEvent(eventIds[k], status: 'error', stopwatch: stopwatches[k], error: 'Web search limit exceeded.');
                  continue;
                }

                webSearchCount++;
                if (stepSearchCache.containsKey(normQuery)) {
                  searchFutures.add(Future.value('Web search already attempted in this phase.\n\n${stepSearchCache[normQuery]}'));
                } else {
                  searchFutures.add(() async {
                    try {
                      final res = await _chatClient.searchWeb(
                        query,
                        _searchSettings.provider,
                        [_searchSettings.apiKey, ..._searchSettings.fallbackApiKeys],
                        googleCx: _searchSettings.googleCx,
                        topic: attrs['topic'],
                        timeRange: attrs['time_range'] ?? attrs['time-range'],
                        startDate: attrs['start_date'] ?? attrs['start-date'],
                        endDate: attrs['end_date'] ?? attrs['end-date'],
                        searchDepth: attrs['search_depth'] ?? attrs['search-depth'] ?? 'basic',
                      ).timeout(const Duration(seconds: 60));
                      stepSearchCache[normQuery] = res;
                      return res;
                    } catch (e) {
                      return 'Web search failed: $e';
                    }
                  }());
                }
              }

              final searchResults = await Future.wait(searchFutures);
              final List<String> allUrls = [];
              final StringBuffer combinedResults = StringBuffer();

              for (var k = 0; k < searchMatches.length; k++) {
                final query = queries[k];
                final eventId = eventIds[k];
                final eventWatch = stopwatches[k];
                final searchResultRaw = searchResults[k];
                final bool isCapError = searchResultRaw.startsWith('Error: Web search cap');
                final bool isDup = searchResultRaw.startsWith('Web search already attempted');

                String searchResult = searchResultRaw;
                if (searchResult.length > 4000) {
                  searchResult = searchResult.substring(0, 4000) + '\n\n...[truncated]';
                }
                final searchError = (searchResult.startsWith('Web search failed:') || isCapError) ? searchResult : null;
                final resultMatches = RegExp(r'- \[([^\]]+)\]\(([^)]+)\):\s*(.*)', multiLine: true).allMatches(searchResult);

                if (!isCapError) {
                  finishResearchEvent(
                    eventId,
                    status: searchError == null ? 'done' : 'error',
                    stopwatch: isDup ? Stopwatch() : eventWatch,
                    details: {
                      'result_count': resultMatches.length,
                      if (isDup) 'already_attempted': true,
                      'result_payload': _compactSearchPayload(
                        resultMatches.map((match) => {
                          'title': match.group(1) ?? '',
                          'url': match.group(2) ?? '',
                          'snippet': match.group(3) ?? '',
                        }),
                      ),
                    },
                    error: searchError,
                  );
                }

                final List<String> urls = resultMatches
                    .map((match) => match.group(2)?.trim() ?? '')
                    .where((url) => url.isNotEmpty)
                    .toList();
                allUrls.addAll(urls);
                combinedResults.writeln("Search results for '$query':\n$searchResult\n");

if (searchError == null && !isDup && !isCapError && searchResult.isNotEmpty) {
  updateResearchEventStatus(eventId, 'ingesting');
  final summariesByResult = <int, Map<String, dynamic>>{};
  await Future.wait(Iterable<int>.generate(resultMatches.length).map((idx) async {
    final m = resultMatches.elementAt(idx);
    final individualUrl = m.group(2)?.trim() ?? '';
    if (individualUrl.isEmpty) return;
    try {
      final individualSummaries = await _summarizeSourceInline(
        sourceUrl: individualUrl,
        content: m.group(3) ?? "",
        provider: provider,
        settings: settings,
        model: model,
      );
      summariesByResult[idx] = {
        'facts': individualSummaries['facts'] ?? [],
        'findings': individualSummaries['findings'] ?? [],
      };
    } catch (e) {
      debugPrint('Inline summarization failed for result $idx: $e');
    }
  }));
  for (final entry in summariesByResult.entries) {
    final facts = List<Map<String, dynamic>>.from(entry.value['facts']);
    final findings = List<Map<String, dynamic>>.from(entry.value['findings']);
    phaseFacts.addAll(facts);
    phaseFindings.addAll(findings);
  }
  await _updateDeepResearchPhase(
    stageId: stageId,
    phaseTitle: phaseTitle,
    facts: phaseFacts,
    findings: phaseFindings,
    skippedPdfs: phaseSkippedPdfs,
    failedFetches: phaseFailedFetches,
  );
  finishResearchEvent(
    eventId,
    status: 'done',
    stopwatch: eventWatch,
    details: {
      'result_count': resultMatches.length,
      'facts_count': phaseFacts.length,
      'findings_count': phaseFindings.length,
      'result_payload': _compactSearchPayload(resultMatches.map((match) {
        return {
          'title': match.group(1) ?? '',
          'url': match.group(2) ?? '',
          'snippet': match.group(3) ?? '',
        };
      })),
    },
  );
}
              }

              stepMessages.add(
                ChatMessage(
                  role: MessageRole.user,
                  text: combinedResults.toString().trim(),
                ),
              );
            } else if (readUrlMatches.isNotEmpty) {
              final availableRam = await _getSystemAvailableRamBytes();
              final bool lowMemory = availableRam < 300 * 1024 * 1024;
              final int activeFetchConcurrency = lowMemory ? 1 : maxConcurrentFetchCalls;

              final List<String> eventIds = [];
              final List<Stopwatch> stopwatches = [];
              final List<String> urls = [];

              for (final match in readUrlMatches) {
                final url = match.group(1)?.trim() ?? '';
                urls.add(url);
                final eventWatch = Stopwatch()..start();
                stopwatches.add(eventWatch);
                final eventId = beginResearchEvent(
                  kind: 'fetch',
                  tool: 'read_url',
                  url: url,
                );
                eventIds.add(eventId);
                stepContent = stepContent.isEmpty
                    ? '<read_url>$url</read_url>'
                    : '$stepContent\n\n<read_url>$url</read_url>';
              }
              steps[i]['content'] = stepContent;
              _publishResearchState(sessionIndex, messageIndex, stateMap);

              final List<String> urlResults = List.filled(urls.length, '');
              final fetchSemaphore = SimpleSemaphore(activeFetchConcurrency);

              await Future.wait(Iterable<int>.generate(urls.length).map((idx) async {
                final url = urls[idx];
                final eventId = eventIds[idx];
                final eventWatch = stopwatches[idx];
                var targetUrl = url.trim();
                if (!targetUrl.startsWith('http')) {
                  targetUrl = 'https://$targetUrl';
                }
                final normUrl = _normalizeQueryOrUrl(url);

                if (targetUrl.toLowerCase().endsWith('.pdf')) {
                   final skipMsg = 'Skipped PDF URL: $targetUrl (PDFs are excluded from Deep Research)';
                   phaseSkippedPdfs.add({'url': targetUrl, 'reason': 'PDF files are excluded (by extension)'});
                   runFetchedUrls.add(normUrl);
                   runUrlSummaries[normUrl] = {'facts': [], 'findings': [], 'isPdf': true, 'skipped': true};

                  await _updateDeepResearchPhase(
                    stageId: stageId,
                    phaseTitle: phaseTitle,
                    facts: phaseFacts,
                    findings: phaseFindings,
                    skippedPdfs: phaseSkippedPdfs,
                    failedFetches: phaseFailedFetches,
                  );

                  finishResearchEvent(
                    eventId,
                    status: 'done',
                    stopwatch: eventWatch,
                    details: {
                      'url': targetUrl,
                      'parse_format': 'skipped_pdf',
                      'result_payload': { 'summary': 'Skipped PDF URL' }
                    }
                  );
                  urlResults[idx] = skipMsg;
                  return;
                }

                // TOOL LIMITS PER PHASE:
                // Capped at 5 read_url calls per phase because read_url downloads and processes complete
                // page content, which is expensive in tokens/concurrency. It should only be used to read
                // the most high-value resources discovered via web_search. If exceeded, return a clear feedback.
                if (readUrlCount >= 5) {
                  final capMsg = 'Read URL limit reached for this phase (5/5 used). No further read_url calls are available this phase — proceed to reflection/summary with what has been gathered, or move to the next phase.';
                  finishResearchEvent(eventId, status: 'error', stopwatch: eventWatch, error: 'read_url limit exceeded.');
                  urlResults[idx] = 'Error: $capMsg';
                  return;
                }

                if (runFetchedUrls.contains(normUrl)) {
                  final cached = runUrlSummaries[normUrl]!;
                  if (cached['skipped'] == true) {
                    phaseSkippedPdfs.add({'url': targetUrl, 'reason': 'PDF files are excluded (cache hit)'});
                  } else {
                    final cachedFacts = List<Map<String, dynamic>>.from(cached['facts'] ?? []);
                    final cachedFindings = List<Map<String, dynamic>>.from(cached['findings'] ?? []);
                    phaseFacts.addAll(cachedFacts);
                    phaseFindings.addAll(cachedFindings);
                  }

                  await _updateDeepResearchPhase(
                    stageId: stageId,
                    phaseTitle: phaseTitle,
                    facts: phaseFacts,
                    findings: phaseFindings,
                    skippedPdfs: phaseSkippedPdfs,
                    failedFetches: phaseFailedFetches,
                  );

                  finishResearchEvent(
                    eventId,
                    status: 'done',
                    stopwatch: eventWatch,
                    details: {
                      'url': targetUrl,
                      'parse_format': cached['isPdf'] == true ? 'skipped_pdf' : 'html',
                      'already_attempted': true,
                      'facts_count': cached['facts']?.length ?? 0,
                      'findings_count': cached['findings']?.length ?? 0,
                      'result_payload': { 'summary': 'Already read & summarized (cache hit)' }
                    }
                  );
                  urlResults[idx] = 'Already read & summarized (cache hit).';
                  return;
                }

                readUrlCount++;
                String text = '';
                bool isPdfResponse = false;
                bool fetchFailed = false;

                try {
                  await fetchSemaphore.run(() async {
                    try {
                      final client = HttpClient()
                        ..findProxy = ((uri) => "DIRECT")
                        ..connectionTimeout = const Duration(seconds: 15);
                      final request = await client.getUrl(Uri.parse(targetUrl)).timeout(const Duration(seconds: 60));
                      request.headers.set(
                        HttpHeaders.userAgentHeader,
                        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Safari/537.36',
                      );
                      request.headers.set(
                        HttpHeaders.acceptHeader,
                        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                      );
                      final response = await request.close().timeout(const Duration(seconds: 60));

                      if (response.statusCode < 200 || response.statusCode >= 300) {
                        throw HttpException('HTTP ${response.statusCode}');
                      }

                      isPdfResponse = response.headers.contentType?.mimeType == 'application/pdf';
                      if (isPdfResponse) {
                        final skipMsg = 'Skipped PDF URL (Content-Type): $targetUrl';
                        phaseSkippedPdfs.add({'url': targetUrl, 'reason': 'PDF files are excluded (by Content-Type)'});
                        runFetchedUrls.add(normUrl);
                        runUrlSummaries[normUrl] = {'facts': [], 'findings': [], 'isPdf': true, 'skipped': true};

                        await _updateDeepResearchPhase(
                          stageId: stageId,
                          phaseTitle: phaseTitle,
                          facts: phaseFacts,
                          findings: phaseFindings,
                          skippedPdfs: phaseSkippedPdfs,
                          failedFetches: phaseFailedFetches,
                        );

                        finishResearchEvent(
                          eventId,
                          status: 'done',
                          stopwatch: eventWatch,
                          details: {
                            'url': targetUrl,
                            'parse_format': 'skipped_pdf',
                            'result_payload': { 'summary': 'Skipped PDF URL (Content-Type)' }
                          }
                        );
                        urlResults[idx] = skipMsg;
                        fetchFailed = true;
                        return;
                      }

                      final body = await response
                          .transform(const Utf8Decoder(allowMalformed: true))
                          .join()
                          .timeout(const Duration(seconds: 60));
                      var htmlBody = body;
                      final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', caseSensitive: false, dotAll: true).firstMatch(body);
                      if (bodyMatch != null) {
                        htmlBody = bodyMatch.group(1) ?? htmlBody;
                      }
                      htmlBody = htmlBody.replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', caseSensitive: false, dotAll: true), '');
                      htmlBody = htmlBody.replaceAll(RegExp(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', caseSensitive: false, dotAll: true), '');
                      htmlBody = htmlBody.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '');
                      htmlBody = htmlBody.replaceAll(RegExp(r'<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>', caseSensitive: false, dotAll: true), '');
                      htmlBody = htmlBody.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
                      text = htmlBody.replaceAll(RegExp(r'<[^>]*>'), ' ');
                      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
                    } catch (e) {
                      fetchFailed = true;
                      final errStr = 'Fetch failed: $e';
                      phaseFailedFetches.add({'url': targetUrl, 'error': errStr});
                      finishResearchEvent(
                        eventId,
                        status: 'error',
                        stopwatch: eventWatch,
                        details: {'url': targetUrl, 'parse_format': 'html'},
                        error: errStr,
                      );
                      urlResults[idx] = errStr;
                    }
                  });
                } catch (e) {
                  fetchFailed = true;
                  final errStr = 'Error running fetch: $e';
                  phaseFailedFetches.add({'url': targetUrl, 'error': errStr});
                  finishResearchEvent(
                    eventId,
                    status: 'error',
                    stopwatch: eventWatch,
                    details: {'url': targetUrl},
                    error: errStr,
                  );
                  urlResults[idx] = errStr;
                }

                if (fetchFailed) return;

                updateResearchEventStatus(
                  eventId,
                  'ingesting',
                  details: {'url': targetUrl, 'parse_format': 'html'},
                );

                try {
                  final summaries = await _summarizeSourceInline(
                    sourceUrl: targetUrl,
                    content: text,
                    provider: provider,
                    settings: settings,
                    model: model,
                  );
                  final List<dynamic> facts = summaries['facts'] ?? [];
                  final List<dynamic> findings = summaries['findings'] ?? [];

                  phaseFacts.addAll(List<Map<String, dynamic>>.from(facts));
                  phaseFindings.addAll(List<Map<String, dynamic>>.from(findings));

                  runFetchedUrls.add(normUrl);
                  runUrlSummaries[normUrl] = {'facts': facts, 'findings': findings, 'isPdf': false, 'skipped': false};

                  await _updateDeepResearchPhase(
                    stageId: stageId,
                    phaseTitle: phaseTitle,
                    facts: phaseFacts,
                    findings: phaseFindings,
                    skippedPdfs: phaseSkippedPdfs,
                    failedFetches: phaseFailedFetches,
                  );

                  finishResearchEvent(
                    eventId,
                    status: 'done',
                    stopwatch: eventWatch,
                    details: {
                      'url': targetUrl,
                      'parse_format': 'html',
                      'facts_count': facts.length,
                      'findings_count': findings.length,
                      'result_payload': { 'summary': '${facts.length} facts, ${findings.length} findings extracted' }
                    },
                  );
                  urlResults[idx] = 'Successfully summarized: ${facts.length} facts, ${findings.length} findings.';
                } catch (e) {
                  final errStr = 'Summarization failed: $e';
                  finishResearchEvent(
                    eventId,
                    status: 'error',
                    stopwatch: eventWatch,
                    details: {'url': targetUrl, 'parse_format': 'html'},
                    error: errStr,
                  );
                  urlResults[idx] = errStr;
                }
              }));

              final StringBuffer combinedResults = StringBuffer();
              for (var k = 0; k < urls.length; k++) {
                combinedResults.writeln("URL: ${urls[k]}");
                combinedResults.writeln("Summarization Result:\n${urlResults[k]}");
                combinedResults.writeln();
              }

              stepMessages.add(
                ChatMessage(
                  role: MessageRole.user,
                  text: combinedResults.toString().trim(),
                ),
              );
            } else {
              stepContent = stepContent.isEmpty ? responseText : '$stepContent\n\n$responseText';
              stepDone = true;
            }

            if (!stepDone && (phaseFacts.isNotEmpty || phaseFindings.isNotEmpty)) {
              final stepReflectMessages = [
                const ChatMessage(
                  role: MessageRole.system,
                  text: "You are a reflection assistant. Read the current facts and findings of the research run and decide if the researcher should do further search or read other URLs, or if the current step is complete. Answer in structured JSON format with keys 'should_continue' (bool) and 'reason' (string).",
                ),
                ChatMessage(
                  role: MessageRole.user,
                  text: "Current facts extracted: ${jsonEncode(phaseFacts)}\n"
                      "Current findings extracted: ${jsonEncode(phaseFindings)}\n"
                      "Does this sufficiently answer the query \"$queryText\"? If yes, answer should_continue: false.",
                ),
              ];
              try {
                final reflectResp = await _chatClient.sendChat(
                  provider: provider,
                  settings: settings,
                  model: model,
                  messages: _compactHistoryForApi(stepReflectMessages, stepReflectMessages.length),
                );
                final cleanReflectResp = reflectResp.replaceAll(RegExp(r"```json\s*|\s*```"), "").trim();
                final reflectJson = jsonDecode(cleanReflectResp) as Map<String, dynamic>;
                if (reflectJson['should_continue'] == false) {
                  stepDone = true;
                }
              } catch (_) {}
            }
          } catch (e) {
            stepDone = true;
            stepFailed = true;
            stepFailure = e.toString();
            break;
          }
        }

        steps[i]['status'] = stepFailed ? 'failed' : 'completed';
        if (stepFailed) {
          steps[i]['error'] = stepFailure;
        }
        steps[i]['content'] = stepContent;
        _publishResearchState(sessionIndex, messageIndex, stateMap);
        await _saveSessions();
      }

      // ── STAGE 3: WRITING THE REPORT ──
      final executionIssues = <Map<String, dynamic>>[];
      for (final stepValue in steps) {
        final step = stepValue as Map;
        final eventErrors = (step['events'] as List? ?? [])
            .whereType<Map>()
            .where((event) => event['status'] == 'error')
            .map((event) => _truncateEventText(event['error']?.toString() ?? 'Tool call failed.', 300))
            .toList();
        if (step['status'] == 'failed' || eventErrors.isNotEmpty) {
          executionIssues.add({
            'step': step['title']?.toString() ?? 'Research step',
            'status': step['status']?.toString() ?? 'completed_with_tool_errors',
            'error': _truncateEventText(step['error']?.toString() ?? (eventErrors.isNotEmpty ? eventErrors.join('; ') : 'Step completed with issues.'), 500),
          });
        }
      }

      stateMap['status'] = 'generating_report';
      _publishResearchState(sessionIndex, messageIndex, stateMap);

      String tempJsonContent = '[]';
      try {
        tempJsonContent = await _exportDeepResearchTemp();

        final int userBudget = _writerContextBudget;
        final int reserve = (userBudget * 0.18).round();
        final int maxEvidenceTokens = userBudget - reserve;

        final List<dynamic> parsedJson = jsonDecode(tempJsonContent) as List<dynamic>;
        
        final List<dynamic> acceptedPhases = [];
        int currentTokenCount = 0;
        int truncatedPhasesCount = 0;

        for (final phaseVal in parsedJson) {
          if (phaseVal is Map<String, dynamic>) {
            final phaseStr = jsonEncode(phaseVal);
            final wordCount = phaseStr.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
            final tokenEst = (wordCount * 1.3).ceil();
            
            if (currentTokenCount + tokenEst <= maxEvidenceTokens) {
              acceptedPhases.add(phaseVal);
              currentTokenCount += tokenEst;
            } else {
              truncatedPhasesCount++;
            }
          }
        }

        if (parsedJson.isNotEmpty && acceptedPhases.isEmpty) {
          final firstPhase = parsedJson.first;
          final phaseStr = jsonEncode(firstPhase);
          final wordCount = phaseStr.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          final tokenEst = (wordCount * 1.3).ceil();
          
          executionIssues.add({
            'step': 'Evidence budget',
            'status': 'warning',
            'error': '⚠️ Context budget ($userBudget tokens) is very small. Proceeding with the first phase summary only.',
          });
          acceptedPhases.add(firstPhase);
          currentTokenCount += tokenEst;
        }

        if (truncatedPhasesCount > 0) {
          executionIssues.add({
            'step': 'Evidence budget',
            'status': 'warning',
            'error': 'Evidence trimmed to fit your configured context budget of $userBudget tokens; $truncatedPhasesCount phase summaries were excluded from the final report.',
          });
        }

        tempJsonContent = jsonEncode(acceptedPhases);
      } catch (e) {
        debugPrint("Error exporting/processing deep-research temp.json: $e");
        executionIssues.add({
          'step': 'Writer input export',
          'status': 'failed',
          'error': 'The writer could not load the bridge-owned retrieval data: ${_truncateEventText(e.toString(), 300)}',
        });
      }

      List<ChatMessage> writerMessages = [
        const ChatMessage(
          role: MessageRole.system,
          text: DeepResearchPrompts.writerSystemPrompt,
        ),
        ChatMessage(
          role: MessageRole.user,
          text: "Here is the retrieved facts and findings (temp.json):\n$tempJsonContent\n\n"
              "Execution issues that must be disclosed in the report:\n"
              "${jsonEncode(executionIssues)}\n\n"
              "Please write the final, comprehensive research report in Markdown format. "
              "Use clear headings, detailed paragraphs, and tables. Do not use SVG, HTML, Mermaid, "
              "or image-based visuals. List all sources at the end.",
        ),
      ];

      String finalReportText = '';
      String finalReasoningText = '';
      bool finalReportDone = false;
      int writerRetries = 0;
      String? writerFailure;

      while (!finalReportDone && writerRetries < 3) {
        if (!mounted) return;
        if (!_sendingSessionIds.contains(_sessions[sessionIndex].id)) {
          break;
        }
        final turnWatch = Stopwatch()..start();
        try {
          String responseText = '';
          String reasoningText = '';
          var isThinking = false;

          final stream = _chatClient.sendChatStream(
            provider: provider,
            settings: settings,
            model: model,
            messages: _compactHistoryForApi(writerMessages, writerMessages.length),
          );

          await for (final chunk in stream) {
            if (chunk.startsWith('[REASONING]')) {
              reasoningText += chunk.substring(11);
            } else {
              var textChunk = chunk;
              if (!isThinking &&
                  (textChunk.contains('<think>') ||
                      textChunk.contains('<reasoning>') ||
                      textChunk.contains('<thought>'))) {
                final tag = textChunk.contains('<think>')
                    ? '<think>'
                    : textChunk.contains('<thought>')
                    ? '<thought>'
                    : '<reasoning>';
                final parts = textChunk.split(tag);
                responseText += parts[0];
                isThinking = true;
                textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
              }

              if (isThinking &&
                  (textChunk.contains('</think>') ||
                      textChunk.contains('</reasoning>') ||
                      textChunk.contains('</thought>'))) {
                final tag = textChunk.contains('</think>')
                    ? '</think>'
                    : textChunk.contains('</thought>')
                    ? '</thought>'
                    : '</reasoning>';
                final parts = textChunk.split(tag);
                reasoningText += parts[0];
                isThinking = false;
                textChunk = parts.length > 1 ? parts.sublist(1).join(tag) : '';
                responseText += textChunk;
              } else if (isThinking) {
                reasoningText += textChunk;
              } else {
                responseText += textChunk;
              }
            }
          }

          finalReportText = responseText;
          finalReasoningText = reasoningText;
          finalReportDone = true;
        } catch (e) {
          writerRetries++;
          writerFailure = e.toString();
        }
      }

      if (!finalReportDone && writerFailure == null) {
        writerFailure = 'Writer stopped before producing a report.';
      }
      if (writerFailure == null) {
        finalReportText = _stripSvgVisuals(finalReportText).trim();
        if (finalReportText.isEmpty) {
          writerFailure = 'Writer returned an empty report.';
        } else {
          stateMap['final_report'] = finalReportText;
          try {
            stateMap['report_path'] = await _persistResearchReport(
              _getResearchFileName(_sessions[sessionIndex].title),
              finalReportText,
            );
          } catch (e) {
            stateMap['report_save_error'] = 'Could not save the Markdown report: $e';
          }
        }
      }
      stateMap['status'] = writerFailure == null ? 'completed' : 'failed';
      if (writerFailure != null) {
        stateMap['error'] = 'Writer agent failed: $writerFailure';
      }
      stateMap['plan_end_ms'] = DateTime.now().millisecondsSinceEpoch;

      if (mounted) {
        setState(() {
          final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
          _sendingSessionIds.remove(_sessions[sessionIndex].id);
          
          String text = _updateResearchStateInText(msgs[messageIndex].text, stateMap);
          if (writerFailure == null) {
            text += "\n\n$finalReportText";
          } else {
            text += "\n\n⚠️ Writer agent failed: $writerFailure";
          }

          msgs[messageIndex] = ChatMessage(
            role: MessageRole.assistant,
            text: text,
            reasoning: finalReasoningText.isNotEmpty ? finalReasoningText : msgs[messageIndex].reasoning,
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
        });
        await _saveSessions();
      }

    } catch (globalError) {
      debugPrint("Global Deep Research Loop error: $globalError");
      stateMap['status'] = 'failed';
      stateMap['error'] = globalError.toString();
      stateMap['plan_end_ms'] = DateTime.now().millisecondsSinceEpoch;
      if (mounted) {
        setState(() {
          final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
          _sendingSessionIds.remove(_sessions[sessionIndex].id);
          msgs[messageIndex] = ChatMessage(
            role: MessageRole.assistant,
            text: _updateResearchStateInText(msgs[messageIndex].text, stateMap) +
                '\n\n⚠️ Deep Research stopped before completion. Reason: $globalError',
            reasoning: msgs[messageIndex].reasoning,
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
        });
        await _saveSessions();
      }
    }
  }

  void _newChat() {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newSession = ChatSession(
      id: newId,
      title: 'New Chat',
      messages: [
        const ChatMessage(
          role: MessageRole.assistant,
          text: 'New chat ready. Choose any configured provider and model.',
        ),
      ],
      providerId: _selectedProviderId,
      model: _activeModel,
    );
    setState(() {
      _sessions.insert(0, newSession);
      _activeSessionId = newId;
      _editingMessageIndex = null;
      _agenticEnabled = false;        // Default off for new chat
      _deepResearchEnabled = false;   // Default off for new chat
    });
    _saveSessions();
  }

  Future<void> _openPlusBottomSheet() async {
    final provider = _provider;
    final settings = _activeSettings;
    final models = _modelCache[provider.id] ?? provider.models;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return MediaAndModelSheet(
          sessions: _sessions,
          onRestoreCompleted: _loadSessions,
          provider: provider,
          settings: settings,
          cachedModels: models,
          searchSettings: _searchSettings,
          agenticEnabled: _agenticEnabled,
          artifactsEnabled: _artifactsEnabled,
          svgVisualsEnabled: _svgVisualsEnabled,
          deepResearchEnabled: _deepResearchEnabled,
          writerContextBudget: _writerContextBudget,
          agenticWorkspace: _agenticWorkspace,
          customMcpUrl: _customMcpUrl,
          onSearchSettingsChanged: (nextSearchSettings) async {
            setState(() {
              _searchSettings = nextSearchSettings;
            });
            await _saveSettings();
          },
          onAgenticEnabledChanged: (val) async {
            setState(() {
              _agenticEnabled = val;
            });
            await _saveSettings();
          },
          onArtifactsEnabledChanged: (val) async {
            setState(() {
              _artifactsEnabled = val;
            });
            await _saveSettings();
          },
          onSvgVisualsEnabledChanged: (val) async {
            setState(() {
              _svgVisualsEnabled = val;
            });
            await _saveSettings();
          },
          onDeepResearchEnabledChanged: (val) async {
            setState(() {
              _deepResearchEnabled = val;
            });
            await _saveSettings();
          },
          onWriterContextBudgetChanged: (val) async {
            setState(() {
              _writerContextBudget = val;
            });
            await _saveSettings();
          },
          onAgenticWorkspaceChanged: (val) async {
            setState(() {
              _agenticWorkspace = val;
            });
            await _saveSettings();
          },
          onCustomMcpUrlChanged: (val) async {
            setState(() {
              _customMcpUrl = val;
            });
            await _saveSettings();
          },
          onImageAttached: (base64Content) {
            setState(() {
              final sessionIndex = _sessions.indexWhere(
                (s) => s.id == _activeSessionId,
              );
              if (sessionIndex != -1) {
                final list = List<String>.from(
                  _sessions[sessionIndex].attachedImagesBase64,
                )..add(base64Content);
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  attachedImagesBase64: list,
                );
              }
            });
            _saveSessions();
          },
          onFileAttached: (file) {
            setState(() {
              final sessionIndex = _sessions.indexWhere(
                (s) => s.id == _activeSessionId,
              );
              if (sessionIndex != -1) {
                final list = List<AttachedFile>.from(
                  _sessions[sessionIndex].attachedFiles,
                )..add(file);
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  attachedFiles: list,
                );
              }
            });
            _saveSessions();
          },
          onProviderChanged: (newProviderId) async {
            final nextProvider = providerCatalog.firstWhere(
              (p) => p.id == newProviderId,
            );
            final nextSettings =
                _settings[newProviderId] ??
                ProviderSettings.defaults(nextProvider);
            final nextModel = nextSettings.model.isNotEmpty
                ? nextSettings.model
                : nextProvider.models.first;
            setState(() {
              _selectedProviderId = newProviderId;
              _settings[newProviderId] = nextSettings.copyWith(
                model: nextModel,
              );

              final sessionIndex = _sessions.indexWhere(
                (s) => s.id == _activeSessionId,
              );
              if (sessionIndex != -1) {
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  providerId: newProviderId,
                  model: nextModel,
                  maxTokens: nextSettings.maxTokens,
                );
              }
            });
            await _saveSettings();
            await _saveSessions();
          },
          onModelChanged: (newModel) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings =
                  _settings[currentProv] ??
                  ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(
                model: newModel,
              );

              final sessionIndex = _sessions.indexWhere(
                (s) => s.id == _activeSessionId,
              );
              if (sessionIndex != -1) {
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  model: newModel,
                );
              }
            });
            await _saveSettings();
            await _saveSessions();
          },
          onMaxTokensChanged: (newMaxTokens) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings =
                  _settings[currentProv] ??
                  ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(
                maxTokens: newMaxTokens,
              );

              final sessionIndex = _sessions.indexWhere(
                (s) => s.id == _activeSessionId,
              );
              if (sessionIndex != -1) {
                _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
                  maxTokens: newMaxTokens,
                );
              }
            });
            await _saveSettings();
            await _saveSessions();
          },
          onReasoningEnabledChanged: (enabled) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings =
                  _settings[currentProv] ??
                  ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(
                reasoningEnabled: enabled,
              );
            });
            await _saveSettings();
          },
          onFetchModels: () => _fetchModels(provider),
          onConfigureKey: (selectedProvId) {
            _openProviderSheet(selectedProvId);
          },
        );
      },
    );
  }

  void _removeImage(int index) {
    setState(() {
      final sessionIndex = _sessions.indexWhere(
        (s) => s.id == _activeSessionId,
      );
      if (sessionIndex != -1) {
        final list = List<String>.from(
          _sessions[sessionIndex].attachedImagesBase64,
        );
        if (index >= 0 && index < list.length) {
          list.removeAt(index);
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            attachedImagesBase64: list,
          );
        }
      }
    });
    _saveSessions();
  }

  void _removeFile(int index) {
    setState(() {
      final sessionIndex = _sessions.indexWhere(
        (s) => s.id == _activeSessionId,
      );
      if (sessionIndex != -1) {
        final list = List<AttachedFile>.from(
          _sessions[sessionIndex].attachedFiles,
        );
        if (index >= 0 && index < list.length) {
          list.removeAt(index);
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            attachedFiles: list,
          );
        }
      }
    });
    _saveSessions();
  }

  void _editUserMessage(int index) {
    setState(() {
      final sessionIndex = _sessions.indexWhere(
        (s) => s.id == _activeSessionId,
      );
      if (sessionIndex != -1) {
        final session = _sessions[sessionIndex];
        final messages = List<ChatMessage>.from(session.messages);
        if (index >= 0 && index < messages.length) {
          final targetMessage = messages[index];
          _messageController.text = targetMessage.text;
          _editingMessageIndex = index;
        }
      }
    });
  }

  void _cancelEditMessage() {
    setState(() {
      _editingMessageIndex = null;
      _messageController.clear();
    });
  }

  void _switchBranch(int branchIndex) {
    setState(() {
      final sessionIndex = _sessions.indexWhere(
        (s) => s.id == _activeSessionId,
      );
      if (sessionIndex != -1) {
        final session = _sessions[sessionIndex];
        final branches = session.branches ?? [session.messages];
        if (branchIndex >= 0 && branchIndex < branches.length) {
          _sessions[sessionIndex] = session.copyWith(
            messages: branches[branchIndex],
            activeBranchIndex: branchIndex,
          );
        }
      }
    });
    _saveSessions();
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;

      if (force || (maxScroll - currentScroll) <= 150.0) {
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  ChatSession get _activeSession {
    if (_sessions.isEmpty) {
      _initDefaultSession();
    }
    return _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => _sessions.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final activeSession = _activeSession;

    final chatHistoryPanel = ChatHistoryPanel(
      sessions: _sessions,
      activeSessionId: _activeSessionId,
      onSessionTap: _switchSession,
      onSessionDelete: _deleteSession,
      onSessionRename: _renameSession,
      onSessionPinToggle: _togglePinSession,
      onNewChat: _newChat,
    );

    return Scaffold(
      drawer: wide ? null : Drawer(width: 330, child: chatHistoryPanel),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 330, child: chatHistoryPanel),
            Expanded(
              child: ChatSurface(
                provider: _provider,
                settings: _activeSettings,
                model: _activeModel,
                messages: _messages,
                messageController: _messageController,
                scrollController: _scrollController,
                isSending: _sendingSessionIds.contains(_activeSessionId),
                toolStatus: _toolStatus,
                onOpenProvider: () => _openProviderSheet(_selectedProviderId),
                onOpenModel: _openModelSheet,
                onSend: _sendMessage,
                onStop: () => _stopResponse(_activeSessionId ?? ''),
                onPlusPressed: _openPlusBottomSheet,
                attachedImages: activeSession.attachedImagesBase64,
                onRemoveImage: _removeImage,
                attachedFiles: activeSession.attachedFiles,
                onRemoveFile: _removeFile,
                onEditUserMessage: _editUserMessage,
                isEditing: _editingMessageIndex != null,
                onCancelEdit: _cancelEditMessage,
                branches: activeSession.branches,
                activeBranchIndex: activeSession.activeBranchIndex,
                onBranchChanged: _switchBranch,
                agenticWorkspace: _agenticWorkspace,
                deepResearchEnabled: _deepResearchEnabled,
                onStartResearch: _startResearchLoop,
                fileName: _getResearchFileName(activeSession.title),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _keyStorageName(String providerId) =>
      'provider_api_key_$providerId';
}

class ChatHistoryPanel extends StatelessWidget {
  const ChatHistoryPanel({
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionTap,
    required this.onSessionDelete,
    required this.onSessionRename,
    required this.onSessionPinToggle,
    required this.onNewChat,
    super.key,
  });

  final List<ChatSession> sessions;
  final String? activeSessionId;
  final ValueChanged<String> onSessionTap;
  final ValueChanged<String> onSessionDelete;
  final void Function(String sessionId, String newTitle) onSessionRename;
  final ValueChanged<String> onSessionPinToggle;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    // Sort pinned chats to the top
    final sortedSessions = List<ChatSession>.from(sessions)
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return 0; // Maintain original relative order
      });

    return Container(
      color: const Color(0xFFEFE6D6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                const AppMark(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nexon',
                    style: GoogleFonts.notoSerif(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D241C),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New chat',
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFDCCBB8), height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
              itemCount: sortedSessions.length,
              itemBuilder: (context, index) {
                final session = sortedSessions[index];
                final selected = session.id == activeSessionId;
                final messageCount = session.messages.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFFFF8EA)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFD8B98D)
                          : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    selected: selected,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (session.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 4.0),
                            child: Icon(
                              Icons.push_pin,
                              size: 12,
                              color: Color(0xFF7B4E2E),
                            ),
                          ),
                        const Icon(Icons.chat_bubble_outline, size: 20),
                      ],
                    ),
                    title: Text(
                      session.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: const Color(0xFF33291F),
                      ),
                    ),
                    subtitle: Text(
                      '$messageCount message${messageCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Color(0xFF6C5946),
                        fontSize: 11,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: const Color(0xFF9B4D39),
                      onPressed: () => onSessionDelete(session.id),
                    ),
                    onTap: () => onSessionTap(session.id),
                    onLongPress: () {
                      _showOptionsSheet(context, session);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showOptionsSheet(BuildContext context, ChatSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFFBF2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  session.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D241C),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: Color(0xFFE7D8C4), height: 1),
              ListTile(
                leading: Icon(
                  session.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: const Color(0xFF7B4E2E),
                ),
                title: Text(
                  session.isPinned ? 'Unpin chat' : 'Pin chat to top',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onSessionPinToggle(session.id);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF7B4E2E),
                ),
                title: const Text(
                  'Rename chat',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showRenameDialog(context, session);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        title: const Text(
          'Rename Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Chat Title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                onSessionRename(session.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

class ChatSurface extends StatelessWidget {
  const ChatSurface({
    required this.provider,
    required this.settings,
    required this.model,
    required this.messages,
    required this.messageController,
    required this.scrollController,
    required this.isSending,
    required this.toolStatus,
    required this.onOpenProvider,
    required this.onOpenModel,
    required this.onSend,
    required this.onPlusPressed,
    required this.attachedImages,
    required this.onRemoveImage,
    required this.attachedFiles,
    required this.onRemoveFile,
    required this.onEditUserMessage,
    required this.isEditing,
    required this.onCancelEdit,
    required this.agenticWorkspace,
    required this.deepResearchEnabled,
    required this.onStartResearch,
    required this.fileName,
    this.branches,
    this.activeBranchIndex,
    this.onBranchChanged,
    this.onStop,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final List<ChatMessage> messages;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final bool isSending;
  final String toolStatus;
  final String fileName;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final ValueChanged<int> onEditUserMessage;
  final bool isEditing;
  final VoidCallback onCancelEdit;
  final String agenticWorkspace;
  final bool deepResearchEnabled;
  final void Function(int, [Map<String, dynamic>? editedStateMap])
      onStartResearch;
  final VoidCallback? onStop;
  final List<List<ChatMessage>>? branches;
  final int? activeBranchIndex;
  final ValueChanged<int>? onBranchChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF6EC), Color(0xFFF5EFE4), Color(0xFFEFE5D5)],
        ),
      ),
      child: Column(
        children: [
          ChatHeader(
            provider: provider,
            settings: settings,
            model: model,
            onOpenProvider: onOpenProvider,
            onOpenModel: onOpenModel,
          ),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                  itemCount: messages.length,
                  itemBuilder: (context, int index) {
                    AvatarAnimationState state = AvatarAnimationState.idle;
                    if (isSending && index == messages.length - 1) {
                      final msg = messages[index];
                      if (msg.text.contains('<mcp_request>') ||
                          msg.text.contains('<tool_request>') ||
                          msg.text.contains('<command>')) {
                        state = AvatarAnimationState.mcp;
                      } else if (msg.text.contains('<search_request>')) {
                        state = AvatarAnimationState.searching;
                      } else if ((msg.reasoning?.isNotEmpty ?? false) &&
                          msg.text.isEmpty) {
                        state = AvatarAnimationState.reasoning;
                      } else {
                        state = AvatarAnimationState.typing;
                      }
                    }
                    final isUser = messages[index].role == MessageRole.user;
                    List<int> branchIndicesForVersions = [];
                    int currentVersionIndex = 0;

                    if (isUser && branches != null && branches!.isNotEmpty) {
                      final activeMsgs = messages;
                      final prefix = activeMsgs.sublist(0, index);
                      final seenTexts = <String>{};

                      for (int b = 0; b < branches!.length; b++) {
                        final branchMsgs = branches![b];
                        if (branchMsgs.length > index) {
                          bool matches = true;
                          for (int j = 0; j < index; j++) {
                            if (branchMsgs[j].text != prefix[j].text ||
                                branchMsgs[j].role != prefix[j].role) {
                              matches = false;
                              break;
                            }
                          }
                          if (matches) {
                            final msgText = branchMsgs[index].text;
                            if (!seenTexts.contains(msgText)) {
                              seenTexts.add(msgText);
                              branchIndicesForVersions.add(b);
                            }
                          }
                        }
                      }

                      currentVersionIndex = branchIndicesForVersions.indexWhere(
                        (bIdx) =>
                            branches![bIdx][index].text == messages[index].text,
                      );
                      if (currentVersionIndex == -1) currentVersionIndex = 0;
                    }

                    return MessageBubble(
                      message: messages[index],
                      index: index,
                      providerShortName: provider.shortName,
                      providerName: provider.name,
                      reasoningEnabled: settings.reasoningEnabled,
                      animationState: state,
                      agenticWorkspace: agenticWorkspace,
                      fileName: fileName,
                      isSending: isSending,
                      onEditUserMessage: () => onEditUserMessage(index),
                      onStartResearch: ([editedStateMap]) =>
                          onStartResearch(index, editedStateMap),
                      versionsCount: branchIndicesForVersions.length,
                      currentVersionIndex: currentVersionIndex,
                      onVersionChanged: branchIndicesForVersions.isEmpty
                          ? null
                          : (int vIdx) {
                              onBranchChanged?.call(branchIndicesForVersions[vIdx]);
                            },
                    );
                  },
                ),
                if (messages.isEmpty && deepResearchEnabled)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9F2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFEADCC9), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B4E2E).withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFBF6EC),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.psychology,
                              color: Color(0xFF7B4E2E),
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Deep Research Mode Active',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D241C),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please select a model which is good at reasoning and make sure you are using at least 32k context model.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6C5946),
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Live tool status banner
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: toolStatus.isNotEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF4FF),
                      border: Border(
                        top: BorderSide(
                          color: const Color(0xFFBDD3F8),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            toolStatus,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1D4ED8),
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Composer(
            controller: messageController,
            isSending: isSending,
            onSend: onSend,
            onStop: onStop,
            onPlusPressed: onPlusPressed,
            attachedImages: attachedImages,
            onRemoveImage: onRemoveImage,
            attachedFiles: attachedFiles,
            onRemoveFile: onRemoveFile,
            deepResearchEnabled: deepResearchEnabled,
            isEditing: isEditing,
            onCancelEdit: onCancelEdit,
          ),
        ],
      ),
    );
  }
}

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    required this.provider,
    required this.settings,
    required this.model,
    required this.onOpenProvider,
    required this.onOpenModel,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;

  @override
  Widget build(BuildContext context) {
    final hasKey = settings.apiKey.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Builder(
            builder: (context) {
              final hasDrawer = Scaffold.hasDrawer(context);
              if (!hasDrawer) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Chats',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onOpenProvider,
            child: Tooltip(
              message: '${provider.name} settings',
              child: ProviderAvatar(label: provider.shortName, small: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onOpenModel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7D8C4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.tune,
                            size: 16,
                            color: Color(0xFF7B4E2E),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              model,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D241C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  hasKey || !provider.requiresKey
                      ? Icons.lock_outline
                      : Icons.lock_open_outlined,
                  size: 18,
                  color: hasKey || !provider.requiresKey
                      ? const Color(0xFF36764D)
                      : const Color(0xFF9B4D39),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String formatMathText(String text) {
  var formatted = text;

  // Replace double dollar sign math blocks with markdown code block
  final blockMathRegex = RegExp(r'\$\$(.*?)\$\$', dotAll: true);
  formatted = formatted.replaceAllMapped(blockMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return '\n```math\n$eq\n```\n';
  });

  // Replace \[ ... \] with code blocks
  final bracketMathRegex = RegExp(r'\\\[(.*?)\\\]', dotAll: true);
  formatted = formatted.replaceAllMapped(bracketMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return '\n```math\n$eq\n```\n';
  });

  // Replace \( ... \) with inline code blocks
  final parenMathRegex = RegExp(r'\\\((.*?)\\\)', dotAll: true);
  formatted = formatted.replaceAllMapped(parenMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return ' `$eq` ';
  });

  return formatted;
}

class ThoughtBlock extends StatefulWidget {
  const ThoughtBlock({required this.thought, super.key});
  final String thought;

  @override
  State<ThoughtBlock> createState() => _ThoughtBlockState();
}

class _ThoughtBlockState extends State<ThoughtBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCCBB8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_outlined,
                    size: 18,
                    color: Color(0xFF7B4E2E),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Thought Process',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF6C5946),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                widget.thought,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF5C4E40),
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class McpToolBlock extends StatefulWidget {
  const McpToolBlock({required this.mcpJson, this.isXml = false, super.key});
  final String mcpJson;
  final bool isXml;

  @override
  State<McpToolBlock> createState() => _McpToolBlockState();
}

class _McpToolBlockState extends State<McpToolBlock> {
  bool _expanded = false;

  /// Returns (icon, label, subtitle) for a method + params.
  (IconData, Color, String, String?) _describe(
    String method,
    Map<String, dynamic> params,
  ) {
    String p(String key) => params[key]?.toString() ?? '';
    String shortPath(String path) {
      if (path.isEmpty) return '';
      final parts = path.split('/');
      return parts.length > 2 ? '…/${parts.last}' : path;
    }

    switch (method) {
      case 'read_file_rich':
      case 'file_read':
        {
          final path = shortPath(p('path'));
          final start = p('start_line');
          final end = p('end_line');
          final sub = (start.isNotEmpty && end.isNotEmpty)
              ? 'lines $start–$end'
              : null;
          return (
            Icons.menu_book_outlined,
            const Color(0xFF0369A1),
            'Read  $path',
            sub,
          );
        }
      case 'multi_read_rich':
      case 'multi_read':
        return (
          Icons.library_books_outlined,
          const Color(0xFF0369A1),
          'Batch read files',
          null,
        );
      case 'patch_file':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Patch  ${shortPath(p('path'))}',
          'search-replace',
        );
      case 'replace_lines':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Replace lines  ${p('start_line')}–${p('end_line')}',
          shortPath(p('path')),
        );
      case 'insert_lines':
        return (
          Icons.playlist_add,
          const Color(0xFF059669),
          'Insert after line ${p('after_line')}',
          shortPath(p('path')),
        );
      case 'delete_lines':
        return (
          Icons.delete_sweep_outlined,
          const Color(0xFFDC2626),
          'Delete lines ${p('start_line')}–${p('end_line')}',
          shortPath(p('path')),
        );
      case 'write_file_rich':
      case 'file_write':
        return (
          Icons.edit_document,
          const Color(0xFF059669),
          'Write  ${shortPath(p('path'))}',
          null,
        );
      case 'search_rich':
      case 'file_search':
        return (
          Icons.search,
          const Color(0xFF0369A1),
          'Search files',
          p('query').isNotEmpty
              ? '"${p('query')}"'
              : p('pattern').isNotEmpty
              ? '"${p('pattern')}"'
              : null,
        );
      case 'file_outline':
        return (
          Icons.account_tree_outlined,
          const Color(0xFF0369A1),
          'Outline  ${shortPath(p('path'))}',
          null,
        );
      case 'tree':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'Tree  ${shortPath(p('path'))}',
          null,
        );
      case 'diff_files':
        return (
          Icons.difference_outlined,
          const Color(0xFF475569),
          'Diff files',
          null,
        );
      case 'symbol_references':
        return (
          Icons.functions,
          const Color(0xFF7C3AED),
          'References',
          p('symbol'),
        );
      case 'append_file':
        return (
          Icons.note_add_outlined,
          const Color(0xFF059669),
          'Append  ${shortPath(p('path'))}',
          null,
        );
      case 'delete_path':
        return (
          Icons.delete_outline,
          const Color(0xFFDC2626),
          'Delete  ${shortPath(p('path'))}',
          p('recursive') == 'true' ? 'recursive' : null,
        );
      case 'move_path':
        return (
          Icons.drive_file_move_outlined,
          const Color(0xFF475569),
          'Move  ${shortPath(p('src'))}',
          shortPath(p('dest')),
        );
      case 'copy_path':
        return (
          Icons.copy_outlined,
          const Color(0xFF475569),
          'Copy  ${shortPath(p('src'))}',
          shortPath(p('dest')),
        );
      case 'mkdir_path':
        return (
          Icons.create_new_folder_outlined,
          const Color(0xFFD97706),
          'Create dir  ${shortPath(p('path'))}',
          null,
        );
      case 'stat_path':
        return (
          Icons.info_outline,
          const Color(0xFF475569),
          'Stat  ${shortPath(p('path'))}',
          null,
        );
      case 'chmod_path':
        return (
          Icons.lock_outline,
          const Color(0xFF475569),
          'Chmod ${p('mode')}',
          shortPath(p('path')),
        );
      case 'file_edit':
        {
          final path = shortPath(p('path'));
          final start = p('start_line');
          final end = p('end_line');
          final sub = (start.isNotEmpty && end.isNotEmpty)
              ? 'lines $start–$end'
              : null;
          return (
            Icons.edit_outlined,
            const Color(0xFF7C3AED),
            'Edit  $path',
            sub,
          );
        }
      case 'file_delete':
        return (
          Icons.delete_outline,
          const Color(0xFFDC2626),
          'Delete  ${shortPath(p('path'))}',
          null,
        );
      case 'dir_list':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'List  ${shortPath(p('path'))}',
          null,
        );
      case 'dir_create':
        return (
          Icons.create_new_folder_outlined,
          const Color(0xFFD97706),
          'Create dir  ${shortPath(p('path'))}',
          null,
        );
      case 'find_paths':
        return (
          Icons.find_in_page_outlined,
          const Color(0xFF0369A1),
          'Find paths',
          p('pattern').isNotEmpty ? '"${p('pattern')}"' : null,
        );
      case 'code_search':
        return (
          Icons.manage_search,
          const Color(0xFF0369A1),
          'Code search',
          '"${p('query')}" in ${shortPath(p('path'))}',
        );
      case 'symbol_search':
        return (
          Icons.functions,
          const Color(0xFF7C3AED),
          'Symbol search',
          p('symbol'),
        );
      case 'file_info':
        return (
          Icons.info_outline,
          const Color(0xFF475569),
          'File info',
          shortPath(p('path')),
        );
      case 'run_command':
      case 'shell_rich':
        {
          final cmd = p('command');
          final short = cmd.length > 55 ? '${cmd.substring(0, 52)}…' : cmd;
          if (cmd.contains('firebase deploy'))
            return (
              Icons.cloud_upload_outlined,
              const Color(0xFFEA4335),
              '🚀 Deploy to Firebase',
              null,
            );
          if (cmd.contains('gh workflow run'))
            return (
              Icons.play_circle_outline,
              const Color(0xFF24292E),
              '⚙️ Trigger GitHub Actions',
              null,
            );
          if (cmd.contains('gh run watch'))
            return (
              Icons.timelapse,
              const Color(0xFF24292E),
              '⏳ Watch Actions build',
              null,
            );
          if (cmd.contains('gh run download'))
            return (
              Icons.download_outlined,
              const Color(0xFF24292E),
              '⬇️ Download artifact',
              null,
            );
          if (cmd.contains('git commit'))
            return (
              Icons.commit,
              const Color(0xFFF05032),
              '📦 Git commit',
              null,
            );
          if (cmd.contains('git push'))
            return (
              Icons.upload_outlined,
              const Color(0xFFF05032),
              '📤 Git push',
              null,
            );
          if (cmd.contains('git status'))
            return (
              Icons.info_outline,
              const Color(0xFFF05032),
              '📊 Git status',
              null,
            );
          if (cmd.contains('git diff'))
            return (
              Icons.difference_outlined,
              const Color(0xFFF05032),
              '🔍 Git diff',
              null,
            );
          if (cmd.contains('flutter build'))
            return (
              Icons.build_outlined,
              const Color(0xFF0175C2),
              '🔨 Flutter build',
              null,
            );
          if (cmd.contains('flutter test'))
            return (
              Icons.science_outlined,
              const Color(0xFF0175C2),
              '🧪 Flutter test',
              null,
            );
          if (cmd.contains('dart analyze'))
            return (
              Icons.analytics_outlined,
              const Color(0xFF0175C2),
              '🧹 Dart analyze',
              null,
            );
          if (cmd.contains('pkg install'))
            return (
              Icons.install_desktop_outlined,
              const Color(0xFF475569),
              '📦 Install package',
              null,
            );
          return (
            Icons.terminal,
            const Color(0xFF1E293B),
            short,
            p('cwd').isNotEmpty ? 'cwd: ${shortPath(p('cwd'))}' : null,
          );
        }
      case 'run_background':
        return (
          Icons.play_circle_outline,
          const Color(0xFF059669),
          'Background service',
          p('command'),
        );
      case 'list_services':
        return (
          Icons.list_alt_outlined,
          const Color(0xFF475569),
          'List services',
          null,
        );
      case 'service_status':
        return (
          Icons.info_outline,
          const Color(0xFF475569),
          'Service status',
          p('id'),
        );
      case 'service_logs':
        return (
          Icons.article_outlined,
          const Color(0xFF475569),
          'Service logs',
          p('id'),
        );
      case 'stop_service':
        return (
          Icons.stop_circle_outlined,
          const Color(0xFFDC2626),
          'Stop service',
          p('id'),
        );
      case 'wait_for_background':
      case 'background_time_limit':
        return (
          Icons.timer_outlined,
          const Color(0xFFD97706),
          'Wait for background job',
          p('pid') ?? p('id'),
        );
      case 'dart_diagnostics':
      case 'dart_analyze':
        return (
          Icons.analytics_outlined,
          const Color(0xFF0175C2),
          'Dart diagnostics',
          shortPath(p('path')),
        );
      case 'dart_format':
        return (
          Icons.format_align_left,
          const Color(0xFF0175C2),
          'Dart format',
          shortPath(p('path')),
        );
      case 'git_status':
        return (
          Icons.info_outline,
          const Color(0xFFF05032),
          'Git status',
          null,
        );
      case 'git_diff':
        return (
          Icons.difference_outlined,
          const Color(0xFFF05032),
          'Git diff',
          null,
        );
      default:
        return (
          Icons.build_circle_outlined,
          const Color(0xFF2B6CB0),
          method,
          null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    String method = 'unknown';
    Map<String, dynamic> params = {};
    String formattedContent = widget.mcpJson;

    if (widget.isXml) {
      final methodMatch = RegExp(
        r'<method[^>]*?>([\s\S]*?)</method\s*>',
        caseSensitive: false,
      ).firstMatch(widget.mcpJson);
      if (methodMatch != null) {
        method = methodMatch.group(1)?.trim() ?? method;
      }
      
      // Parse XML params for description (direct tags)
      final regex = RegExp(
        r'<([a-zA-Z0-9_]+)(?:\s+[^>]*?)?>([\s\S]*?)</\1\s*>',
        caseSensitive: false,
      );
      for (final match in regex.allMatches(widget.mcpJson)) {
        final key = match.group(1)!.toLowerCase();
        if (key != 'method') {
          params[key] = match.group(2)?.trim() ?? '';
        }
      }

      // Fallback: <PARAM name="key">value</PARAM>
      final paramRegex = RegExp(
        r'''<[Pp][Aa][Rr][Aa][Mm]\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp][Aa][Rr][Aa][Mm]>''',
      );
      for (final m in paramRegex.allMatches(widget.mcpJson)) {
        final key = m.group(1)!.toLowerCase();
        if (key != 'method') {
          params[key] = m.group(2)?.trim() ?? '';
        }
      }

      // Fallback: <parameter name="key">value</parameter>
      final paramRegex2 = RegExp(
        r'''<[Pp]arameter\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp]arameter>''',
        caseSensitive: false,
      );
      for (final m in paramRegex2.allMatches(widget.mcpJson)) {
        final key = m.group(1)!.toLowerCase();
        if (key != 'method') {
          params[key] = m.group(2)?.trim() ?? '';
        }
      }
      formattedContent = widget.mcpJson.trim();
    } else {
      try {
        final decoded = jsonDecode(widget.mcpJson) as Map<String, dynamic>;
        method = decoded['method']?.toString() ?? method;
        params = (decoded['params'] as Map<String, dynamic>?) ?? {};
        formattedContent = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {}
    }

    final (icon, color, label, subtitle) = _describe(method, params);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: color.withOpacity(0.75),
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: color.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                formattedContent,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: Color(0xFFCDD6F4),
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionInfoRow extends StatelessWidget {
  const _PermissionInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8A7765),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

TextSpan _highlightCode(String code, String language) {
  final lang = language.toLowerCase();
  
  final List<String> keywords;
  if (lang == 'python' || lang == 'py') {
    keywords = ['def', 'class', 'import', 'from', 'as', 'return', 'if', 'elif', 'else', 'for', 'while', 'in', 'is', 'not', 'and', 'or', 'try', 'except', 'finally', 'pass', 'lambda', 'with', 'assert', 'global', 'nonlocal', 'del', 'yield', 'None', 'True', 'False'];
  } else if (lang == 'dart' || lang == 'java' || lang == 'kotlin' || lang == 'go' || lang == 'rust' || lang == 'rs') {
    keywords = ['class', 'import', 'package', 'void', 'return', 'if', 'else', 'for', 'while', 'in', 'try', 'catch', 'finally', 'final', 'const', 'var', 'let', 'static', 'extends', 'implements', 'interface', 'mixin', 'with', 'as', 'is', 'new', 'this', 'super', 'switch', 'case', 'default', 'break', 'continue', 'async', 'await', 'yield', 'fn', 'pub', 'use', 'impl', 'struct', 'enum', 'mut', 'let'];
  } else if (lang == 'javascript' || lang == 'js' || lang == 'typescript' || lang == 'ts') {
    keywords = ['class', 'import', 'export', 'from', 'function', 'return', 'if', 'else', 'for', 'while', 'in', 'of', 'try', 'catch', 'finally', 'const', 'let', 'var', 'new', 'this', 'super', 'switch', 'case', 'default', 'break', 'continue', 'async', 'await', 'yield', 'type', 'interface', 'namespace', 'typeof', 'instanceof', 'true', 'false', 'null', 'undefined'];
  } else {
    keywords = ['class', 'import', 'export', 'void', 'function', 'return', 'if', 'else', 'for', 'while', 'try', 'catch', 'finally', 'const', 'let', 'var', 'final', 'def', 'fn', 'true', 'false', 'null'];
  }

  final keywordSet = keywords.toSet();

  // Regex tokenization groups:
  // 1. Block comments
  // 2. Line comments
  // 3. Strings (double, single, or backtick quotes)
  // 4. Numbers
  // 5. Identifiers/Words
  final pattern = RegExp(
    r'''(/\*[\s\S]*?\*/)|(//.*|#.*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(\b\d+(?:\.\d+)?\b)|(\b[a-zA-Z_][a-zA-Z0-9_]*\b)|([\s\S])''',
  );

  final spans = <TextSpan>[];
  final matches = pattern.allMatches(code);

  for (final m in matches) {
    final text = m.group(0)!;
    if (m.group(1) != null || m.group(2) != null) {
      // Comments
      spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFF7A828F))));
    } else if (m.group(3) != null) {
      // Strings
      spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFF98C379))));
    } else if (m.group(4) != null) {
      // Numbers
      spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFFD19A66))));
    } else if (m.group(5) != null) {
      // Words
      if (keywordSet.contains(text)) {
        spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFFC678DD), fontWeight: FontWeight.bold)));
      } else if (RegExp(r'^[A-Z]').hasMatch(text)) {
        // Classes/Types
        spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFFE5C07B))));
      } else if (text == 'void' || text == 'int' || text == 'double' || text == 'num' || text == 'bool' || text == 'dynamic') {
        spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFFE5C07B))));
      } else {
        spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFFABB2BF))));
      }
    } else {
      // Operators, braces, spaces
      spans.add(TextSpan(text: text, style: const TextStyle(color: Color(0xFFABB2BF))));
    }
  }

  return TextSpan(children: spans);
}

class CodeBlockWidget extends StatelessWidget {
  const CodeBlockWidget({
    required this.code,
    required this.language,
    required this.onSave,
    super.key,
  });

  final String code;
  final String language;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 16, color: Color(0xFFDCCBB8)),
                const SizedBox(width: 8),
                Text(
                  language.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFDCCBB8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(
                    Icons.copy_all_outlined,
                    size: 18,
                    color: Color(0xFFDCCBB8),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied to clipboard')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save file',
                  icon: const Icon(
                    Icons.download_rounded,
                    size: 18,
                    color: Color(0xFFDCCBB8),
                  ),
                  onPressed: onSave,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText.rich(
              _highlightCode(code, language),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FileArtifactWidget extends StatelessWidget {
  const FileArtifactWidget({
    required this.content,
    required this.language,
    super.key,
  });

  final String content;
  final String language;

  String get filename => 'artifact.${getExtension(language)}';

  Future<void> _save(BuildContext context) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Artifact',
      fileName: filename,
      bytes: bytes,
    );
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $filename')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: Color(0xFF7B4E2E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filename,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF2D241C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Artifact copied')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save',
                  icon: const Icon(Icons.download_rounded, size: 18),
                  onPressed: () => _save(context),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1E1E1E),
            child: SingleChildScrollView(
              child: SelectableText.rich(
                _highlightCode(content, language),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String getExtension(String lang) {
  switch (lang.toLowerCase()) {
    case 'python':
    case 'py':
      return 'py';
    case 'dart':
      return 'dart';
    case 'javascript':
    case 'js':
      return 'js';
    case 'typescript':
    case 'ts':
      return 'ts';
    case 'html':
      return 'html';
    case 'css':
      return 'css';
    case 'json':
      return 'json';
    case 'bash':
    case 'sh':
    case 'shell':
      return 'sh';
    case 'rust':
    case 'rs':
      return 'rs';
    case 'go':
      return 'go';
    case 'cpp':
    case 'c++':
      return 'cpp';
    case 'c':
      return 'c';
    case 'java':
      return 'java';
    case 'kotlin':
    case 'kt':
      return 'kt';
    default:
      return 'txt';
  }
}

Future<void> _saveCodeBlock(
  BuildContext context,
  String code,
  String language,
) async {
  try {
    final ext = getExtension(language);
    final filename = 'code_${DateTime.now().millisecondsSinceEpoch}.$ext';

    if (Platform.isAndroid) {
      await Permission.storage.request();
    }

    final bytes = Uint8List.fromList(utf8.encode(code));
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Code Block',
      fileName: filename,
      bytes: bytes,
    );

    if (path == null) {
      return; // User cancelled
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      final file = File(path);
      await file.writeAsBytes(bytes);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved: ${path.split('/').last}'),
          backgroundColor: const Color(0xFF36764D),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save file: $e'),
          backgroundColor: const Color(0xFF9B4D39),
        ),
      );
    }
  }
}

class ContentBlock {
  final bool isCode;
  final String content;
  final String language;

  ContentBlock({
    required this.isCode,
    required this.content,
    this.language = '',
  });
}

List<ContentBlock> parseContentBlocks(String text) {
  final blocks = <ContentBlock>[];
  final parts = text.split('```');

  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (i % 2 == 0) {
      if (part.isNotEmpty) {
        blocks.add(ContentBlock(isCode: false, content: part));
      }
    } else {
      final lines = part.split('\n');
      final firstLine = lines.first.trim();
      
      bool isValidLanguageIdentifier(String lang) {
        if (lang.isEmpty) return true;
        // A valid language prefix shouldn't contain spaces, quotes, brackets, or math operators, and shouldn't be too long.
        final invalidChars = RegExp(r"[\s\(\)\{\}\[\]\=\+\-\*\/\\;,'\.]");
        return !invalidChars.hasMatch(lang) && lang.length <= 20;
      }

      if (isValidLanguageIdentifier(firstLine)) {
        final codeContent = lines.skip(1).join('\n');
        blocks.add(
          ContentBlock(isCode: true, content: codeContent, language: firstLine),
        );
      } else {
        blocks.add(
          ContentBlock(isCode: true, content: part, language: ''),
        );
      }
    }
  }
  return blocks;
}

String convertLatexToUnicode(String text) {
  var formatted = text;

  final replacements = {
    r'\alpha': 'α',
    r'\beta': 'β',
    r'\gamma': 'γ',
    r'\delta': 'δ',
    r'\epsilon': 'ε',
    r'\zeta': 'ζ',
    r'\eta': 'η',
    r'\theta': 'θ',
    r'\iota': 'ι',
    r'\kappa': 'κ',
    r'\lambda': 'λ',
    r'\mu': 'μ',
    r'\nu': 'ν',
    r'\xi': 'ξ',
    r'\pi': 'π',
    r'\rho': 'ρ',
    r'\sigma': 'σ',
    r'\tau': 'τ',
    r'\upsilon': 'υ',
    r'\phi': 'φ',
    r'\chi': 'χ',
    r'\psi': 'ψ',
    r'\omega': 'ω',
    r'\Gamma': 'Γ',
    r'\Delta': 'Δ',
    r'\Theta': 'Θ',
    r'\Lambda': 'Λ',
    r'\Xi': 'Ξ',
    r'\Pi': 'Π',
    r'\Sigma': 'Σ',
    r'\Phi': 'Φ',
    r'\Psi': 'Ψ',
    r'\Omega': 'Ω',
    r'\pm': '±',
    r'\times': '×',
    r'\div': '÷',
    r'\cdot': '·',
    r'\le': '≤',
    r'\ge': '≥',
    r'\ne': '≠',
    r'\approx': '≈',
    r'\in': '∈',
    r'\notin': '∉',
    r'\ni': '∋',
    r'\propto': '∝',
    r'\infty': '∞',
    r'\partial': '∂',
    r'\nabla': '∇',
    r'\sum': '∑',
    r'\prod': '∏',
    r'\coprod': '∐',
    r'\int': '∫',
    r'\iint': '∬',
    r'\iiint': '∌',
    r'\oint': '∮',
    r'\therefore': '∴',
    r'\because': '∌',
    r'\forall': '∀',
    r'\exists': '∃',
    r'\empty': '∅',
    r'\emptyset': '∅',
    r'\cap': '∩',
    r'\cup': '∪',
    r'\subset': '⊂',
    r'\supset': '⊃',
    r'\subseteq': '⊆',
    r'\supseteq': '⊇',
    r'\leftrightarrow': '↔',
    r'\Leftarrow': '⇐',
    r'\Rightarrow': '⇒',
    r'\Leftrightarrow': '⇔',
    r'\to': '→',
    r'\rightarrow': '→',
    r'\gets': '←',
    r'\leftarrow': '←',
    r'\uparrow': '↑',
    r'\downarrow': '↓',
    r'\neq': '≠',
    r'\leq': '≤',
    r'\geq': '≥',
  };

  final sqrtRegex = RegExp(r'\\sqrt\s*\{\s*(.*?)\s*\}', dotAll: true);
  formatted = formatted.replaceAllMapped(sqrtRegex, (match) {
    final inside = match.group(1) ?? '';
    return '√($inside)';
  });

  final fracRegex = RegExp(
    r'\\frac\s*\{\s*(.*?)\s*\}\s*\{\s*(.*?)\s*\}',
    dotAll: true,
  );
  formatted = formatted.replaceAllMapped(fracRegex, (match) {
    final num = match.group(1) ?? '';
    final den = match.group(2) ?? '';
    return '($num)/($den)';
  });

  formatted = formatted.replaceAll(r'\left(', '(');
  formatted = formatted.replaceAll(r'\right)', ')');
  formatted = formatted.replaceAll(r'\left[', '[');
  formatted = formatted.replaceAll(r'\right]', ']');
  formatted = formatted.replaceAll(r'\left\{', '{');
  formatted = formatted.replaceAll(r'\right\}', '}');
  formatted = formatted.replaceAll(r'\langle', '⟨');
  formatted = formatted.replaceAll(r'\rangle', '⟩');

  replacements.forEach((key, val) {
    formatted = formatted.replaceAll(key, val);
  });

  final superscriptMap = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '+': '⁺',
    '-': '⁻',
    '=': '⁼',
    '(': '⁽',
    ')': '⁾',
    'n': 'ⁿ',
    'i': 'ⁱ',
    'x': 'ˣ',
    'y': 'ʸ',
  };
  final superRegex = RegExp(r'\^([0-9a-nixy\+\-\=\(\)])');
  formatted = formatted.replaceAllMapped(superRegex, (match) {
    final char = match.group(1) ?? '';
    return superscriptMap[char] ?? '^$char';
  });

  final subscriptMap = {
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
    '+': '₊',
    '-': '₋',
    '=': '₌',
    '(': '₍',
    ')': '₎',
    'x': 'ₓ',
    'y': 'y',
    'i': 'ᵢ',
    'j': 'ⱼ',
  };
  final subRegex = RegExp(r'_([0-9\+\-\=\(\)xyij])');
  formatted = formatted.replaceAllMapped(subRegex, (match) {
    final char = match.group(1) ?? '';
    return subscriptMap[char] ?? '_$char';
  });

  formatted = formatted.replaceAllMapped(
    RegExp(r'\\text\s*\{\s*(.*?)\s*\}'),
    (m) => m.group(1) ?? '',
  );

  return formatted;
}

// ══════════════════════════════════════════════════════════════════════════════
// Rich chat media display system
// ══════════════════════════════════════════════════════════════════════════════

/// Animated shimmer placeholder — shown while media decodes or loads.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({required this.width, required this.height, this.radius = 12});
  final double width;
  final double height;
  final double radius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              const Color(0xFFE8DDD0),
              Color.lerp(
                const Color(0xFFE8DDD0),
                const Color(0xFFF5EDE0),
                _anim.value,
              )!,
              const Color(0xFFE8DDD0),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of image + video tiles in a chat bubble.
class _ChatMediaGrid extends StatelessWidget {
  const _ChatMediaGrid({required this.images, required this.videos});
  final List<String> images;
  final List<String> videos;

  @override
  Widget build(BuildContext context) {
    final allImages = images;
    final allVideos = videos;
    final total = allImages.length + allVideos.length;

    // Build combined tile list: images first, then videos
    final tiles = <Widget>[
      for (int i = 0; i < allImages.length; i++)
        _ImageChatTile(
          heroTag: 'chat_img_${allImages[i].hashCode}_$i',
          base64Data: allImages[i],
          allImages: allImages,
          initialIndex: i,
        ),
      for (int i = 0; i < allVideos.length; i++)
        _VideoChatTile(base64Data: allVideos[i], index: i),
    ];

    if (total == 1) {
      // Single item — show larger
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 260,
          height: 180,
          child: tiles.first,
        ),
      );
    }

    if (total == 2) {
      return SizedBox(
        height: 140,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: tiles[0]),
            const SizedBox(width: 6),
            Flexible(child: tiles[1]),
          ],
        ),
      );
    }

    // 3+ items — wrap grid
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tiles.map((t) {
        return SizedBox(width: 140, height: 140, child: t);
      }).toList(),
    );
  }
}

/// A single image tile with shimmer loading, error state, hero + fullscreen viewer.
class _ImageChatTile extends StatefulWidget {
  const _ImageChatTile({
    required this.heroTag,
    required this.base64Data,
    required this.allImages,
    required this.initialIndex,
  });
  final String heroTag;
  final String base64Data;
  final List<String> allImages;
  final int initialIndex;

  @override
  State<_ImageChatTile> createState() => _ImageChatTileState();
}

class _ImageChatTileState extends State<_ImageChatTile> {
  Uint8List? _bytes;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  void _decode() {
    try {
      final bytes = base64Decode(widget.base64Data);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _ChatMediaViewer(
          images: widget.allImages,
          initialIndex: widget.initialIndex,
          heroTag: widget.heroTag,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _errorTile();
    }
    if (_bytes == null) {
      return _ShimmerBox(width: double.infinity, height: double.infinity);
    }

    return GestureDetector(
      onTap: () => _openViewer(context),
      child: Hero(
        tag: widget.heroTag,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  _bytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
                // Subtle gradient overlay at bottom
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.25),
                        ],
                      ),
                    ),
                  ),
                ),
                // Tap-to-expand hint icon
                Positioned(
                  bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.fullscreen_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorTile() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF5EDE0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDCCBB8)),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, color: Color(0xFFB08060), size: 32),
        SizedBox(height: 4),
        Text(
          'Image unavailable',
          style: TextStyle(fontSize: 10, color: Color(0xFFB08060)),
        ),
      ],
    ),
  );
}

/// A single video tile backed by VideoPlayerController.
/// Shows thumbnail (first decoded frame via controller) with play overlay.
class _VideoChatTile extends StatefulWidget {
  const _VideoChatTile({required this.base64Data, required this.index});
  final String base64Data;
  final int index;

  @override
  State<_VideoChatTile> createState() => _VideoChatTileState();
}

class _VideoChatTileState extends State<_VideoChatTile> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final bytes = base64Decode(widget.base64Data);
      // Write to temp file so VideoPlayerController can load it
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/nexon_video_${widget.index}_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await file.writeAsBytes(bytes);
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      ctrl.addListener(() {
        if (mounted) setState(() => _isPlaying = ctrl.value.isPlaying);
      });
      if (mounted) {
        setState(() {
          _ctrl = ctrl;
          _initialized = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _errorTile();
    }

    if (!_initialized || _ctrl == null) {
      return _ShimmerBox(width: double.infinity, height: double.infinity);
    }

    return GestureDetector(
      onTap: () {
        if (_expanded) {
          _isPlaying ? _ctrl!.pause() : _ctrl!.play();
        } else {
          setState(() => _expanded = true);
          _ctrl!.play();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _expanded ? _buildPlayer() : _buildThumbnail(),
      ),
    );
  }

  Widget _buildThumbnail() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // First frame as thumbnail
        AspectRatio(
          aspectRatio: _ctrl!.value.aspectRatio,
          child: VideoPlayer(_ctrl!),
        ),
        // Dark overlay
        Container(color: Colors.black54),
        // Play icon
        const Center(
          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44),
        ),
        // Duration badge
        Positioned(
          bottom: 6, right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xB2000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _fmtDuration(_ctrl!.value.duration),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        // Video badge
        Positioned(
          top: 6, left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xB2000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_rounded, color: Color(0xFF67E8A0), size: 12),
                SizedBox(width: 3),
                Text('VIDEO', style: TextStyle(color: Color(0xFF67E8A0), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _ctrl!.value.aspectRatio,
            child: VideoPlayer(_ctrl!),
          ),
        ),
        // Play/Pause overlay
        Center(
          child: AnimatedOpacity(
            opacity: _isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
        ),
        // Progress bar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _ctrl!,
            builder: (_, val, __) {
              final total = val.duration.inMilliseconds;
              final pos = val.position.inMilliseconds;
              final progress = total == 0 ? 0.0 : pos / total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF67E8A0)),
                    minHeight: 3,
                  ),
                  Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmtDuration(val.position),
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Text(
                          _fmtDuration(val.duration),
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Buffering spinner
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _ctrl!,
          builder: (_, val, __) => val.isBuffering
              ? const Center(
                  child: SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF67E8A0)),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _errorTile() => Container(
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.videocam_off_rounded, color: Color(0xFF67E8A0), size: 32),
        SizedBox(height: 6),
        Text('Video unavailable', style: TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    ),
  );
}

/// Full-screen media viewer with:
///  - Hero transition from chat bubble
///  - InteractiveViewer pinch-to-zoom for images
///  - VideoPlayer with controls for videos
///  - Swipe-down to dismiss
///  - Thumbnail strip for navigating multiple images
class _ChatMediaViewer extends StatefulWidget {
  const _ChatMediaViewer({
    required this.images,
    required this.initialIndex,
    required this.heroTag,
  });
  final List<String> images;
  final int initialIndex;
  final String heroTag;

  @override
  State<_ChatMediaViewer> createState() => _ChatMediaViewerState();
}

class _ChatMediaViewerState extends State<_ChatMediaViewer> {
  late int _current;
  late final PageController _pageCtrl;
  final _transformKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 600) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            // Blurred dark background
            Container(color: Colors.black.withOpacity(0.92)),

            // Image pager
            PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                Uint8List? bytes;
                try {
                  bytes = base64Decode(widget.images[i]);
                } catch (_) {}

                if (bytes == null) {
                  return const Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 60),
                  );
                }

                final heroTag = i == widget.initialIndex
                    ? widget.heroTag
                    : 'viewer_img_$i';

                return Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 6.0,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                );
              },
            ),

            // Top bar — image counter + close
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.images.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_current + 1} / ${widget.images.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hint: swipe down to dismiss
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              left: 0, right: 0,
              child: const Center(
                child: Text(
                  'Swipe down to dismiss · Pinch to zoom',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),

            // Thumbnail strip (multiple images)
            if (widget.images.length > 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 12,
                left: 0, right: 0,
                child: SizedBox(
                  height: 56,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.images.length,
                    itemBuilder: (context, i) {
                      Uint8List? bytes;
                      try {
                        bytes = base64Decode(widget.images[i]);
                      } catch (_) {}
                      final isSelected = i == _current;
                      return GestureDetector(
                        onTap: () => _pageCtrl.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white30,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          child: bytes == null
                              ? const Icon(Icons.broken_image_outlined, color: Colors.white38)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(bytes, fit: BoxFit.cover),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════

class MessageBubble extends StatelessWidget {

  const MessageBubble({
    required this.message,
    required this.index,
    required this.providerShortName,
    required this.providerName,
    required this.reasoningEnabled,
    required this.onEditUserMessage,
    required this.agenticWorkspace,
    required this.fileName,
    required this.isSending,
    this.animationState = AvatarAnimationState.idle,
    this.onStartResearch,
    this.versionsCount = 0,
    this.currentVersionIndex = 0,
    this.onVersionChanged,
    super.key,
  });

  final ChatMessage message;
  final int index;
  final String providerShortName;
  final String providerName;
  final bool reasoningEnabled;
  final String agenticWorkspace;
  final String fileName;
  final AvatarAnimationState animationState;
  final VoidCallback onEditUserMessage;
  final void Function([Map<String, dynamic>? editedStateMap])?
      onStartResearch;
  final int versionsCount;
  final int currentVersionIndex;
  final ValueChanged<int>? onVersionChanged;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final text = message.text;
    final isToolOutput =
        message.role == MessageRole.system ||
        text.startsWith('Tool Result [') ||
        text.startsWith('Search results:\n') ||
        text.startsWith('URL Content:\n') ||
        text.startsWith('MCP Result:\n') ||
        text.startsWith('Web Search results') ||
        text.startsWith('Content of URL');
    final isUser = message.role == MessageRole.user;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 240 + (index % 5) * 24),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isToolOutput) ...[
              Row(
                children: [
                  if (isUser) ...[
                    const Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Color(0xFF7B4E2E),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'You',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF7B4E2E),
                      ),
                    ),
                    if (versionsCount > 1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5EFE4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFDCCBB8),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: currentVersionIndex > 0
                                  ? () => onVersionChanged?.call(
                                      currentVersionIndex - 1,
                                    )
                                  : null,
                              child: Icon(
                                Icons.chevron_left,
                                size: 14,
                                color: currentVersionIndex > 0
                                    ? const Color(0xFF7B4E2E)
                                    : const Color(0xFFCBBBA4),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '${currentVersionIndex + 1}/$versionsCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7B4E2E),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: currentVersionIndex < versionsCount - 1
                                  ? () => onVersionChanged?.call(
                                      currentVersionIndex + 1,
                                    )
                                  : null,
                              child: Icon(
                                Icons.chevron_right,
                                size: 14,
                                color: currentVersionIndex < versionsCount - 1
                                    ? const Color(0xFF7B4E2E)
                                    : const Color(0xFFCBBBA4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    ProviderAvatar(
                      label: providerShortName,
                      small: true,
                      animationState: animationState,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      providerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy text',
                    icon: const Icon(
                      Icons.content_copy_rounded,
                      size: 14,
                      color: Color(0xFF6C5946),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied to clipboard'),
                        ),
                      );
                    },
                  ),
                  if (isUser)
                    IconButton(
                      tooltip: 'Edit message',
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Color(0xFF6C5946),
                      ),
                      onPressed: onEditUserMessage,
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (message.images.isNotEmpty || message.videos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: _ChatMediaGrid(
                  images: message.images,
                  videos: message.videos,
                ),
              ),
            if (isToolOutput)
              Builder(
                builder: (context) {

                  // Parse a smart header for tool results
                  final text = message.text;
                  String header;
                  IconData headerIcon;
                  Color headerColor;
                  final hasError =
                      text.contains('"error"') || text.contains('Error:');
                  if (hasError) {
                    headerIcon = Icons.error_outline;
                    headerColor = const Color(0xFFDC2626);
                  } else {
                    headerIcon = Icons.check_circle_outline;
                    headerColor = const Color(0xFF059669);
                  }

                  // Extract tool name from "Tool Result [method]:" or "Web Search results" etc.
                  final toolResultMatch = RegExp(
                    r'Tool Result \[(\w+)\]',
                  ).firstMatch(text);
                  final webSearchMatch =
                      text.startsWith('Web Search results') ||
                      text.startsWith('Search results:\n');
                  final urlMatch =
                      text.startsWith("Content of URL") ||
                      text.startsWith("URL Content:\n");
                  final mcpMatch = text.startsWith("MCP Result:\n");
                  if (toolResultMatch != null) {
                    final method = toolResultMatch.group(1) ?? 'tool';
                    final sizeKb = (text.length / 1024).toStringAsFixed(1);
                    header = hasError
                        ? '❌ Failed: $method'
                        : '✅ Tool Result [$method]  ·  ${sizeKb} KB';
                    headerIcon = hasError
                        ? Icons.error_outline
                        : Icons.check_circle_outline;
                  } else if (webSearchMatch) {
                    header = '🔍 Web Search Results';
                    headerIcon = Icons.search;
                    headerColor = const Color(0xFF0369A1);
                  } else if (urlMatch) {
                    header = '🌐 URL Content Fetched';
                    headerIcon = Icons.language;
                    headerColor = const Color(0xFF0369A1);
                  } else if (mcpMatch) {
                    header = '⚙️ MCP Tool Result';
                    headerIcon = Icons.settings;
                    headerColor = const Color(0xFF059669);
                  } else {
                    header = text.split('\n').first;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: headerColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: headerColor.withOpacity(0.2)),
                    ),
                    child: ExpansionTile(
                      title: Text(
                        header,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: headerColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                      leading: Icon(headerIcon, color: headerColor, size: 17),
                      collapsedBackgroundColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _buildToolResultDetails(
                                context,
                                message.text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            else if (isUser)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7D8C4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: message.files
                              .map(
                                (f) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0EBE1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFDCCBB8),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.insert_drive_file,
                                        size: 13,
                                        color: Color(0xFF7B4E2E),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        f.name,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF4A3424),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    SelectableText(
                      message.text,
                      style: const TextStyle(
                        height: 1.45,
                        color: Color(0xFF2D241C),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (message.reasoning.isNotEmpty && reasoningEnabled)
                ThoughtBlock(thought: message.reasoning),
              ..._parseRichMessageContent(context, message.text),
            ],
            const SizedBox(height: 4),
            const Divider(color: Color(0xFFE7D8C4), height: 1),
          ],
        ),
      ),
    );
  }

  List<Widget> _parseRichMessageContent(BuildContext context, String text) {
    final widgets = <Widget>[];
    int currentIndex = 0;

    final tags = [
      (tag: '<research_plan>', isXml: false),
      (tag: '<research_state>', isXml: false),
      (tag: '<search_request>', isXml: false),
      (tag: '<read_url>', isXml: false),
      (tag: '<mcp_request>', isXml: false),
      (tag: '<tool_request>', isXml: true),
      (tag: '<command>', isXml: true),
    ];

    while (currentIndex < text.length) {
      final substring = text.substring(currentIndex);
      int earliestIndex = -1;
      var matchedTag = tags.first;

      for (final tagInfo in tags) {
        final idx = substring.indexOf(tagInfo.tag);
        if (idx != -1) {
          if (earliestIndex == -1 || idx < earliestIndex) {
            earliestIndex = idx;
            matchedTag = tagInfo;
          }
        }
      }

      if (earliestIndex == -1) {
        final remaining = substring.trim();
        if (remaining.isNotEmpty) {
          widgets.addAll(_buildBlocks(context, remaining));
        }
        break;
      }

      final textBefore = substring.substring(0, earliestIndex).trim();
      if (textBefore.isNotEmpty) {
        widgets.addAll(_buildBlocks(context, textBefore));
      }

      final tagStartIndex = currentIndex + earliestIndex;
      final openTag = matchedTag.tag;
      final closeTag = openTag.replaceFirst('<', '</');

      final tagContentStartIndex = tagStartIndex + openTag.length;
      final closeTagIndexInFull = text.indexOf(closeTag, tagContentStartIndex);

      if (closeTagIndexInFull == -1) {
        // Unclosed tag (streaming fallback)
        final contentStr = text.substring(tagContentStartIndex).trim();
        widgets.add(_buildSpecializedWidget(openTag, contentStr, matchedTag.isXml));
        break;
      }

      final contentStr = text.substring(tagContentStartIndex, closeTagIndexInFull).trim();
      widgets.add(_buildSpecializedWidget(openTag, contentStr, matchedTag.isXml));

      currentIndex = closeTagIndexInFull + closeTag.length;
    }

    return widgets;
  }

  Widget _buildSpecializedWidget(String openTag, String content, bool isXml) {
    try {
      switch (openTag) {
        case '<research_plan>':
          return const SizedBox.shrink();
        case '<research_state>':
          {
            var cleanContent = content;
            if (cleanContent.contains('<research_plan>')) {
              final planIndex = cleanContent.indexOf('<research_plan>');
              final planEndIndex = cleanContent.indexOf('</research_plan>', planIndex);
              if (planEndIndex != -1) {
                cleanContent = (cleanContent.substring(0, planIndex) +
                    cleanContent.substring(planEndIndex + 16)).trim();
              } else {
                cleanContent = cleanContent.substring(0, planIndex).trim();
              }
            }
            final stateMap = jsonDecode(cleanContent) as Map<String, dynamic>;
            return ResearchPlanWidget(
              stateMap: stateMap,
              workspaceDir: agenticWorkspace,
              fileName: fileName,
              isSending: isSending,
              onStartResearch: onStartResearch,
            );
          }
        case '<search_request>':
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD0E0F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF2B6CB0), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tool Use: Searched the web for "$content"',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                ),
              ],
            ),
          );
        case '<read_url>':
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD0E0F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: Color(0xFF2B6CB0), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tool Use: Reading webpage at "$content"',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                ),
              ],
            ),
          );
        case '<command>':
          final contentStr = '<method>run_command</method><command>$content</command>';
          return McpToolBlock(mcpJson: contentStr, isXml: true);
        default: // <mcp_request>, <tool_request>
          return McpToolBlock(mcpJson: content, isXml: isXml);
      }
    } catch (e) {
      return Text(
        'Error rendering $openTag: $e',
        style: const TextStyle(color: Colors.red),
      );
    }
  }

  List<Widget> _buildToolResultDetails(BuildContext context, String text) {
    final sections = text.split(RegExp(r'\n\n---\n\n'));
    return sections
        .where((section) => section.trim().isNotEmpty)
        .map((section) => _buildToolResultSection(context, section.trim()))
        .toList();
  }

  Widget _buildToolResultSection(BuildContext context, String section) {
    var body = section;
    final firstBreak = body.indexOf('\n\n');
    if (body.startsWith('Tool Result [') && firstBreak != -1) {
      body = body.substring(firstBreak + 2);
    } else if (body.startsWith('MCP Result:\n')) {
      body = body.substring('MCP Result:\n'.length);
    }

    String? diff;
    if (body.contains('--- DIFF ---')) {
      final parts = body.split('--- DIFF ---');
      body = parts.first.trim();
      diff = parts.skip(1).join('--- DIFF ---').trim();
    }

    final embeddedDiffIndex = body.indexOf('\nDIFF:\n');
    if (embeddedDiffIndex != -1 && diff != null) {
      body = body.substring(0, embeddedDiffIndex).trim();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (body.trim().isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1915),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              body.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.35,
                color: Color(0xFFFFF7EC),
              ),
            ),
          ),
        if (diff != null && diff.trim().isNotEmpty)
          DiffViewerWidget(content: diff.trim()),
      ],
    );
  }

  List<Widget> _buildBlocks(BuildContext context, String text) {
    if (text.startsWith("Tool Result [") && text.contains("\n\n")) {
      final resultContent = text.substring(text.indexOf("\n\n") + 2);
      if (resultContent.contains("--- DIFF ---")) {
        final parts = resultContent.split("--- DIFF ---");
        return [
          ...parseContentBlocks(parts[0].trim()).map((block) {
            return _buildSingleBlock(context, block);
          }).toList(),
          if (parts.length > 1 && parts[1].trim().isNotEmpty)
            DiffViewerWidget(content: parts[1].trim()),
        ];
      }
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: SelectableText(
            resultContent,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Color(0xFFD4D4D4),
            ),
          ),
        ),
      ];
    }
    return parseContentBlocks(
      text,
    ).map((block) => _buildSingleBlock(context, block)).toList();
  }

  Widget _buildSingleBlock(BuildContext context, ContentBlock block) {
    if (block.isCode) {
      if (block.language.toLowerCase() == 'math') {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE7D8C4)),
          ),
          child: SelectableText(
            convertLatexToUnicode(block.content),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D241C),
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }
      if (block.language.toLowerCase() == 'svg') {
        return SvgDiagramWidget(svgString: block.content);
      }
      if (block.language.toLowerCase() == 'chart' ||
          block.language.toLowerCase() == 'json-chart') {
        return NexonChartWidget(chartBlock: block.content);
      }
      final lang = block.language.toLowerCase();
      final contentLower = block.content.toLowerCase();
      final isCompleteWebpage =
          contentLower.contains('<html') || contentLower.contains('<!doctype');
      final lineCount = '\n'.allMatches(block.content).length + 1;
      final isCompleteCodeFile =
          lineCount >= 35 ||
          contentLower.contains('void main(') ||
          contentLower.contains('def main(') ||
          contentLower.contains('if __name__') ||
          contentLower.contains('class ') ||
          contentLower.contains('function ');
      final isArtifact =
          lang == 'artifact' ||
          ((lang == 'html' || lang == 'react' || lang == 'javascript') &&
              isCompleteWebpage);
      if (isArtifact) {
        return HtmlArtifactWidget(htmlContent: block.content);
      }
      if (isCompleteCodeFile &&
          {
            'python',
            'py',
            'dart',
            'javascript',
            'js',
            'typescript',
            'ts',
            'html',
            'css',
            'json',
            'yaml',
            'yml',
            'bash',
            'sh',
            'java',
            'kotlin',
            'go',
            'rust',
            'rs',
          }.contains(lang)) {
        return FileArtifactWidget(content: block.content, language: lang);
      }
      if (block.language.toLowerCase() == 'docx') {
        return DocxArtifactWidget(
          docxContent: block.content,
          workspacePath: agenticWorkspace,
        );
      }
      if (block.language.toLowerCase() == 'md' ||
          block.language.toLowerCase() == 'markdown') {
        return MdArtifactWidget(
          mdContent: block.content,
          workspacePath: agenticWorkspace,
        );
      }
      return CodeBlockWidget(
        code: block.content,
        language: block.language,
        onSave: () => _saveCodeBlock(context, block.content, block.language),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: MarkdownBody(
          data: block.content
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;')
              .replaceAllMapped(
                RegExp(r'\\\[([\s\S]*?)\\\]'),
                (m) => '\$\$' + (m.group(1) ?? '') + '\$\$',
              )
              .replaceAllMapped(
                RegExp(r'\\\(([\s\S]*?)\\\)'),
                (m) => '\$' + (m.group(1) ?? '') + '\$',
              )
              .replaceAll(r'\boldsymbol', r'\mathbf'),
          selectable: true,
          builders: {
            'latex': LatexElementBuilder(
              textStyle: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 15.5,
                fontWeight: FontWeight.w400,
              ),
              textScaleFactor: 1.15,
            ),
            'table': ScrollableTableBuilder(),
          },
          extensionSet: md.ExtensionSet(
            [
              LatexBlockSyntax(),
              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            ],
            [
              LatexInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: const TextStyle(
              height: 1.48,
              color: Color(0xFF1E1E1E),
              fontSize: 15.5,
              fontWeight: FontWeight.w400,
            ),
            h1: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            h2: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            h3: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            listBullet: const TextStyle(
              color: Color(0xFF7B4E2E),
              fontSize: 15.5,
            ),
            tableBorder: TableBorder.all(
              color: const Color(0xFFDCCBB8),
              width: 1,
            ),
            tableBody: const TextStyle(color: Color(0xFF1E1E1E), fontSize: 14),
            tableHead: const TextStyle(
              color: Color(0xFF2D241C),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      );
    }
  }
}

class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7D8C4)),
        ),
        child: const SizedBox(
          width: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PulseDot(delay: 0),
              PulseDot(delay: 110),
              PulseDot(delay: 220),
            ],
          ),
        ),
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({required this.delay, super.key});

  final int delay;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.32,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: const CircleAvatar(radius: 4, backgroundColor: Color(0xFF8A6A4F)),
    );
  }
}

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onPlusPressed,
    required this.attachedImages,
    required this.onRemoveImage,
    required this.attachedFiles,
    required this.onRemoveFile,
    required this.deepResearchEnabled,
    required this.isEditing,
    required this.onCancelEdit,
    this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback onPlusPressed;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final bool deepResearchEnabled;
  final bool isEditing;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 920),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F6EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7D8C4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: Color(0xFF7B4E2E),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Editing message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onCancelEdit,
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Color(0xFF7B4E2E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (attachedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachedFiles.length,
                  itemBuilder: (context, idx) {
                    final file = attachedFiles[idx];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBE1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCCBB8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.insert_drive_file,
                            size: 14,
                            color: Color(0xFF7B4E2E),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            file.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A3424),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => onRemoveFile(idx),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Color(0xFF7B4E2E),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          if (attachedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachedImages.length,
                  itemBuilder: (context, idx) {
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDCCBB8)),
                            image: DecorationImage(
                              image: MemoryImage(
                                base64Decode(attachedImages[idx]),
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => onRemoveImage(idx),
                            child: const CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 920),
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFDCCBB8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onPlusPressed,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2, right: 8),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFF8EA),
                      border: Border.all(
                        color: const Color(0xFFD8B98D),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Color(0xFF7B4E2E),
                      size: 20,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message any provider...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: isSending
                        ? const Color(0xFFCBBBA4)
                        : const Color(0xFF2E241C),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    tooltip: isSending ? 'Stop response' : 'Send',
                    onPressed: isSending ? onStop : onSend,
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns true if [modelName] supports image/vision input.
///
/// Detection priority:
/// 1. Runtime set populated from API modality metadata during [fetchModels].
/// 2. Keyword heuristics — catches models with capability keywords in their
///    name regardless of provider-specific naming conventions.
bool modelHasVision(String modelName) {
  // 1. Runtime API-detected set (most reliable)
  if (ChatClient.modelsWithVision.contains(modelName)) return true;

  final lower = modelName.toLowerCase();

  // 2. Generic capability keywords in model name
  //    These reliably indicate vision regardless of model family.
  if (lower.contains('vision') ||
      lower.contains('-vl') ||
      lower.contains('vlm') ||
      lower.contains('visual') ||
      lower.contains('multimodal') ||
      lower.contains('omni') ||
      lower.contains('llava') ||
      lower.contains('moondream') ||
      lower.contains('pixtral') ||
      lower.contains('minicpm-v') ||
      lower.contains('internvl') ||
      lower.contains('smolvlm') ||
      lower.contains('cogvlm') ||
      lower.contains('idefics') ||
      lower.contains('bakllava')) {
    return true;
  }

  // 3. Well-known model families where vision is a standard feature.
  //    Kept minimal — only cover broad families, not specific version numbers,
  //    so new models in these families are automatically detected.

  // OpenAI gpt-4 class (gpt-4o, gpt-4-turbo, gpt-4.1, gpt-4.5, etc.)
  if (lower.startsWith('gpt-4') || lower.startsWith('chatgpt-4o')) return true;

  // OpenAI o-series (o1, o3, o4 etc. — all support vision)
  if (RegExp(r'^o\d').hasMatch(lower)) return true;

  // Anthropic Claude 3+ family (all claude-3, claude-4+ support vision)
  if (RegExp(r'claude-[3-9]').hasMatch(lower)) return true;

  // Google Gemini 1.5+ and Gemini 2+ (all support vision)
  if (RegExp(r'gemini-(1\.[5-9]|[2-9])').hasMatch(lower) ||
      lower.contains('gemini-flash') ||
      lower.contains('gemini-pro')) {
    return true;
  }

  // Google Gemma 3+ (has vision)
  if (RegExp(r'gemma-?[3-9]').hasMatch(lower)) return true;

  // Qwen VL / Qwen 2.x VL
  if (lower.contains('qwen') && lower.contains('-vl')) return true;

  // Llama 3.2+ vision variants
  if (lower.contains('llama-3.2') && lower.contains('vision')) return true;

  // Microsoft Phi vision variants
  if (lower.contains('phi') && lower.contains('vision')) return true;
  if (lower.contains('phi-4-multimodal')) return true;

  // Mistral vision (pixtral already caught above; mistral-medium-3+)
  if (lower.contains('mistral') && lower.contains('medium')) return true;

  // Molmo, Aria (always multimodal)
  if (lower.contains('molmo') || lower.contains('aria')) return true;

  return false;
}

/// Returns true if [modelName] can generate images from text (text-to-image).
///
/// Detection priority:
/// 1. Runtime set populated from API output-modality metadata during [fetchModels].
/// 2. Keyword heuristics — catches models whose names indicate image generation.
bool modelCanGenerateImages(String modelName) {
  // 1. Runtime API-detected set
  if (ChatClient.modelsWithImageGeneration.contains(modelName)) return true;

  final lower = modelName.toLowerCase();

  // 2. Generic image-generation keywords
  if (lower.contains('dall-e') ||
      lower.contains('dalle') ||
      lower.contains('flux') ||
      lower.contains('stable-diffusion') ||
      lower.contains('stable diffusion') ||
      lower.contains('qwen-image') ||
      lower.contains('trellis') ||
      lower.contains('sdxl') ||
      lower.contains('imagen') ||
      lower.contains('midjourney') ||
      lower.contains('ideogram') ||
      lower.contains('kandinsky') ||
      lower.contains('wuerstchen') ||
      lower.contains('aura-flow') ||
      lower.contains('kolors') ||
      lower.contains('playgroundai') ||
      lower.contains('text-to-image') ||
      lower.contains('img-gen') ||
      lower.contains('image-gen') ||
      lower.contains('image-generation')) {
    return true;
  }

  // Gemini image-gen models
  if (lower.contains('gemini') && lower.contains('image')) return true;

  return false;
}

/// Returns true if [modelName] can generate videos from text (text-to-video).
///
/// Detection priority:
/// 1. Runtime set populated from API output-modality metadata during [fetchModels].
/// 2. Keyword heuristics — catches models whose names indicate video generation.
bool modelCanGenerateVideos(String modelName) {
  // 1. Runtime API-detected set
  if (ChatClient.modelsWithVideoGeneration.contains(modelName)) return true;

  final lower = modelName.toLowerCase();

  // 2. Generic video-generation keywords
  if (lower.contains('video') ||
      lower.contains('cosmos') ||
      lower.contains('sora') ||
      lower.contains('runway') ||
      lower.contains('kling') ||
      lower.contains('pika') ||
      lower.contains('luma') ||
      lower.contains('veo') ||
      lower.contains('minimax-video') ||
      lower.contains('cogvideo') ||
      lower.contains('wan') ||
      lower.contains('text-to-video') ||
      lower.contains('vid-gen') ||
      lower.contains('video-gen') ||
      lower.contains('video-generation')) {
    return true;
  }

  return false;
}

/// Returns true if [modelName] is a dedicated reasoning / coding model.
///
/// Detection uses keyword heuristics. Runtime metadata from providers that
/// expose capability fields (e.g. OpenRouter's `reasoning` flag) is NOT yet
/// parsed, so this relies solely on name patterns.
bool modelIsReasoningOrCoding(String modelName) {
  final lower = modelName.toLowerCase();

  // Reasoning keywords
  if (lower.contains('reason') ||
      lower.contains('think') ||
      lower.contains('reflect') ||
      lower.contains('qwq') ||
      lower.contains('marco-o') ||
      lower.contains('skywork-o') ||
      lower.contains('deepseek-r') ||
      lower.contains('-r1') ||
      lower.contains('-r2') ||
      lower.contains('aya-expanse')) {
    return true;
  }

  // OpenAI o-series reasoning models (o1, o3, o4 …)
  // BUT NOT other "o" models like "olmo", "ollama" etc.
  if (RegExp(r'\bo[1-9]\b').hasMatch(lower)) return true;

  // Coding-specialist keywords
  if (lower.contains('coder') ||
      lower.contains('codex') ||
      lower.contains('starcoder') ||
      lower.contains('deepseek-coder') ||
      lower.contains('qwen-coder') ||
      lower.contains('qwen2.5-coder') ||
      lower.contains('yi-coder') ||
      lower.contains('wizardcoder') ||
      lower.contains('phind-code') ||
      lower.contains('code-llama') ||
      lower.contains('codellama') ||
      lower.contains('granite-code') ||
      lower.contains('-code-') ||
      lower.contains('instruct-code') ||
      lower.contains('code-instruct')) {
    return true;
  }

  return false;
}

/// Classifies [modelName] into a category string.
///
/// Priority order (a model can only have one category here):
/// image > video > vision > reasoning > normal
String modelCategoryOf(String modelName) {
  if (modelCanGenerateImages(modelName)) return 'image';
  if (modelCanGenerateVideos(modelName)) return 'video';
  if (modelHasVision(modelName)) return 'vision';
  if (modelIsReasoningOrCoding(modelName)) return 'reasoning';
  return 'normal';
}

/// Counts of models per category for a given model list.
class _ModelCounts {
  const _ModelCounts({
    required this.total,
    required this.normal,
    required this.reasoning,
    required this.vision,
    required this.image,
    required this.video,
  });

  final int total;
  final int normal;
  final int reasoning;
  final int vision;
  final int image;
  final int video;

  factory _ModelCounts.of(List<String> models) {
    int normal = 0, reasoning = 0, vision = 0, image = 0, video = 0;
    for (final m in models) {
      switch (modelCategoryOf(m)) {
        case 'image':
          image++;
        case 'video':
          video++;
        case 'vision':
          vision++;
        case 'reasoning':
          reasoning++;
        default:
          normal++;
      }
    }
    return _ModelCounts(
      total: models.length,
      normal: normal,
      reasoning: reasoning,
      vision: vision,
      image: image,
      video: video,
    );
  }
}

class MediaAndModelSheet extends StatefulWidget {

  const MediaAndModelSheet({
    super.key,
    required this.sessions,
    required this.onRestoreCompleted,
    required this.provider,
    required this.settings,
    required this.cachedModels,
    required this.searchSettings,
    required this.agenticEnabled,
    required this.artifactsEnabled,
    required this.svgVisualsEnabled,
    required this.deepResearchEnabled,
    required this.writerContextBudget,
    required this.agenticWorkspace,
    required this.customMcpUrl,
    required this.onSearchSettingsChanged,
    required this.onAgenticEnabledChanged,
    required this.onArtifactsEnabledChanged,
    required this.onSvgVisualsEnabledChanged,
    required this.onDeepResearchEnabledChanged,
    required this.onWriterContextBudgetChanged,
    required this.onAgenticWorkspaceChanged,
    required this.onCustomMcpUrlChanged,
    required this.onImageAttached,
    required this.onFileAttached,

    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onMaxTokensChanged,
    required this.onReasoningEnabledChanged,
    required this.onFetchModels,
    required this.onConfigureKey,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final SearchSettings searchSettings;
  final bool agenticEnabled;
  final bool artifactsEnabled;
  final bool svgVisualsEnabled;
  final bool deepResearchEnabled;
  final int writerContextBudget;
  final String agenticWorkspace;
  final String customMcpUrl;
  final List<ChatSession> sessions;
  final Future<void> Function() onRestoreCompleted;
  final ValueChanged<SearchSettings> onSearchSettingsChanged;
  final ValueChanged<bool> onAgenticEnabledChanged;
  final ValueChanged<bool> onArtifactsEnabledChanged;
  final ValueChanged<bool> onSvgVisualsEnabledChanged;
  final ValueChanged<bool> onDeepResearchEnabledChanged;
  final ValueChanged<int> onWriterContextBudgetChanged;
  final ValueChanged<String> onAgenticWorkspaceChanged;
  final ValueChanged<String> onCustomMcpUrlChanged;
  final ValueChanged<String> onImageAttached;
  final ValueChanged<AttachedFile> onFileAttached;

  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<int> onMaxTokensChanged;
  final ValueChanged<bool> onReasoningEnabledChanged;
  final Future<List<String>> Function() onFetchModels;
  final ValueChanged<String> onConfigureKey;

  @override
  State<MediaAndModelSheet> createState() => _MediaAndModelSheetState();
}

class _MediaAndModelSheetState extends State<MediaAndModelSheet> {
  int _activeTab = 0;
  bool _isFetchingModels = false;
  bool _managedSubscriptionEnabled = false;
  late int _maxTokens;
  var _fetching = false;
  late String _selectedProviderId;
  late String _selectedModel;
  late bool _reasoningEnabled;
  late bool _searchEnabled;
  late bool _agenticEnabled;
  late bool _artifactsEnabled;
  late bool _svgVisualsEnabled;
  late bool _deepResearchEnabled;
  late int _writerContextBudget;
  late TextEditingController _writerContextBudgetController;
  late String _searchProvider;
  late final TextEditingController _searchKeyController;
  late final TextEditingController _searchCxController;
  late final TextEditingController _agenticWorkspaceController;
  late final TextEditingController _customMcpUrlController;
  bool _driveBackupEnabled = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  String _syncProgressStatus = '';
  String _activePlanTier = '';
  int? _liveDailyPool;
  int? _liveSubscriptionCredits;
  int? _liveTopupCredits;
  Timer? _walletSyncTimer;

  @override
  void initState() {
    super.initState();
    _maxTokens = widget.settings.maxTokens;
    _selectedProviderId = widget.provider.id;
    _selectedModel = widget.settings.model.isNotEmpty
        ? widget.settings.model
        : widget.provider.models.first;
    _reasoningEnabled = widget.settings.reasoningEnabled;
    _searchEnabled = widget.searchSettings.enabled;
    _agenticEnabled = widget.agenticEnabled;
    _artifactsEnabled = widget.artifactsEnabled;
    _svgVisualsEnabled = widget.svgVisualsEnabled;
    _deepResearchEnabled = widget.deepResearchEnabled;
    _writerContextBudget = widget.writerContextBudget;
    _writerContextBudgetController = TextEditingController(
      text: widget.writerContextBudget.toString(),
    );
    _searchProvider = widget.searchSettings.provider;
    final initialKeys = [
      widget.searchSettings.apiKey,
      ...widget.searchSettings.fallbackApiKeys,
    ].where((k) => k.isNotEmpty).join(', ');
    _searchKeyController = TextEditingController(text: initialKeys);
    _searchCxController = TextEditingController(
      text: widget.searchSettings.googleCx,
    );
    _agenticWorkspaceController = TextEditingController(
      text: widget.agenticWorkspace,
    );
    _customMcpUrlController = TextEditingController(text: widget.customMcpUrl);

    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _driveBackupEnabled =
              prefs.getBool('google_drive_backup_enabled') ?? false;
          _managedSubscriptionEnabled =
              prefs.getBool('nexon_managed_subscription_enabled') ?? false;
          _activePlanTier = prefs.getString('nexon_managed_plan_tier') ?? '';
        });
      }
    });
    _liveDailyPool = ChatClient.liveDailyPool.value;
    _liveSubscriptionCredits = ChatClient.liveSubscriptionCredits.value;
    _liveTopupCredits = ChatClient.liveTopupCredits.value;
    ChatClient.liveDailyPool.addListener(_onWalletChanged);
    ChatClient.liveSubscriptionCredits.addListener(_onWalletChanged);
    ChatClient.liveTopupCredits.addListener(_onWalletChanged);

    _fetchLiveWallet();
    _walletSyncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _fetchLiveWallet(),
    );
  }

  @override
  void didUpdateWidget(covariant MediaAndModelSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final providerChanged = oldWidget.provider.id != widget.provider.id;
    final modelChanged = oldWidget.settings.model != widget.settings.model;
    if (providerChanged ||
        modelChanged ||
        oldWidget.settings.maxTokens != widget.settings.maxTokens ||
        oldWidget.settings.reasoningEnabled !=
            widget.settings.reasoningEnabled ||
        oldWidget.searchSettings.enabled != widget.searchSettings.enabled ||
        oldWidget.agenticEnabled != widget.agenticEnabled ||
        oldWidget.deepResearchEnabled != widget.deepResearchEnabled ||
        oldWidget.searchSettings.provider != widget.searchSettings.provider) {
      setState(() {
        _selectedProviderId = widget.provider.id;
        // When provider changes, reset to that provider's default model.
        // When only model changes (e.g. session switch), honour the new value.
        if (providerChanged) {
          _selectedModel = widget.settings.model.isNotEmpty
              ? widget.settings.model
              : widget.provider.models.first;
        } else if (modelChanged) {
          _selectedModel = widget.settings.model.isNotEmpty
              ? widget.settings.model
              : _selectedModel;
        }
        _maxTokens = widget.settings.maxTokens;
        _reasoningEnabled = widget.settings.reasoningEnabled;
        _searchEnabled = widget.searchSettings.enabled;
        _agenticEnabled = widget.agenticEnabled;
        _artifactsEnabled = widget.artifactsEnabled;
        _svgVisualsEnabled = widget.svgVisualsEnabled;
        _deepResearchEnabled = widget.deepResearchEnabled;
        _writerContextBudget = widget.writerContextBudget;
        _searchProvider = widget.searchSettings.provider;
      });
    }
  }

  Future<Map<String, dynamic>> _checkBridgeAlive() async {
    final endpoint = widget.customMcpUrl.isNotEmpty
        ? widget.customMcpUrl
        : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 3));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({'method': 'ping', 'params': {}}));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 3));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded['result'] is Map) {
          final result = decoded['result'] as Map;
          if (result['ok'] == true) return {'ok': true};
        }
      }
      return {'ok': false, 'reason': 'bridge_error'};
    } catch (_) {
      return {'ok': false, 'reason': 'bridge_unreachable'};
    } finally {
      client.close(force: true);
    }
  }

  void _showDeepResearchSetupDialog({required String reason}) {
    final isUnreachable = reason == 'bridge_unreachable';
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            bool rechecking = false;
            return AlertDialog(
              title: Text(isUnreachable ? 'Bridge Not Running' : 'Deep Research Setup Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isUnreachable
                      ? "The Python bridge process isn't currently running. Please start it in Termux:"
                      : 'Deep Research requires the Python bridge. Please run this setup command in Termux:'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black87,
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            isUnreachable
                                ? 'cd ~/nexon_bridge && python3 mcp_server.py'
                                : 'cd ~/projects/termux_forge && ./install_bridge.sh',
                            style: const TextStyle(color: Colors.green, fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                              text: isUnreachable
                                  ? 'cd ~/nexon_bridge && python3 mcp_server.py'
                                  : 'cd ~/projects/termux_forge && ./install_bridge.sh',
                            ));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
                StatefulBuilder(
                  builder: (ctx2, setRecheckState) {
                    return TextButton(
                      onPressed: rechecking
                          ? null
                          : () async {
                              setRecheckState(() => rechecking = true);
                              final result = await _checkBridgeAlive();
                              if (!mounted) return;
                              if (result['ok'] == true) {
                                Navigator.of(ctx).pop();
                                setState(() => _deepResearchEnabled = true);
                                widget.onDeepResearchEnabledChanged(true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Bridge is running! Deep Research enabled.')),
                                );
                              } else {
                                setRecheckState(() => rechecking = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Bridge still not reachable. Please check it is running.')),
                                );
                              }
                            },
                      child: rechecking
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Recheck'),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _getTotalDailyCap(String planTier) {
    switch (planTier.toUpperCase()) {
      case 'GO':
        return 550000;
      case 'PLUS':
        return 1100000;
      case 'PRO':
        return 2000000;
      case 'MAX':
        return 3100000;
      default:
        return 100000; // Free tier
    }
  }

  int _getTotalMonthlyCap(String planTier) {
    switch (planTier.toUpperCase()) {
      case 'GO':
        return 16500000;
      case 'PLUS':
        return 33500000;
      case 'PRO':
        return 61000000;
      case 'MAX':
        return 95000000;
      default:
        return 0;
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  void _onWalletChanged() {
    if (mounted) {
      setState(() {
        _liveDailyPool = ChatClient.liveDailyPool.value;
        _liveSubscriptionCredits = ChatClient.liveSubscriptionCredits.value;
        _liveTopupCredits = ChatClient.liveTopupCredits.value;
      });
    }
  }

  Future<void> _fetchLiveWallet() async {
    await ChatClient.fetchLiveWallet();
  }

  @override
  void dispose() {
    ChatClient.liveDailyPool.removeListener(_onWalletChanged);
    ChatClient.liveSubscriptionCredits.removeListener(_onWalletChanged);
    ChatClient.liveTopupCredits.removeListener(_onWalletChanged);
    _walletSyncTimer?.cancel();
    _searchKeyController.dispose();
    _searchCxController.dispose();
    _agenticWorkspaceController.dispose();
    _customMcpUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      if (mounted) {
        setState(() {
          // Keep the current selection if it exists in the new list.
          // Only fall back to first model if current selection is absent.
          if (models.isNotEmpty && !models.contains(_selectedModel)) {
            _selectedModel = models.first;
            widget.onModelChanged(_selectedModel);
          }
          // Re-evaluate vision capability after fresh model list is loaded
          // (modelsWithVision is populated during fetchModels)
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model fetch failed: $error')));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFFFFBF2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Attach Image',
            style: TextStyle(
              color: Color(0xFF7B4E2E),
              fontWeight: FontWeight.bold,
              fontFamily: 'serif',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF2D241C)),
                title: const Text(
                  'Take a Photo',
                  style: TextStyle(color: Color(0xFF2D241C)),
                ),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF2D241C),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: Color(0xFF2D241C)),
                ),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (status.isDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Camera permission denied')),
            );
          }
          return;
        }
      }

      if (source == ImageSource.gallery) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null && result.files.single.path != null) {
          final file = File(result.files.single.path!);
          final bytes = await file.readAsBytes();
          final base64String = base64Encode(bytes);
          widget.onImageAttached(base64String);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image attached successfully')),
            );
          }
        }
      } else {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: source);
        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          final base64String = base64Encode(bytes);
          widget.onImageAttached(base64String);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image attached successfully')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('camera_access_denied') ||
            errorStr.contains('permission') ||
            errorStr.contains('denied')) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFFFFFBF2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Permission Denied',
                style: TextStyle(
                  color: Color(0xFF7B4E2E),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'serif',
                ),
              ),
              content: const Text(
                'Camera or Gallery permission was denied. If you selected "Don\'t ask again", you will need to enable this permission manually in the app settings to use this feature.',
                style: TextStyle(color: Color(0xFF2D241C), height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF7B4E2E)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B4E2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
        }
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'txt',
          'md',
          'json',
          'py',
          'dart',
          'js',
          'html',
          'css',
          'yaml',
          'yml',
        ],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final ext = result.files.single.extension?.toLowerCase();
        String text = '';

        if (ext == 'pdf') {
          final PdfDocument document = PdfDocument(
            inputBytes: await file.readAsBytes(),
          );
          text = PdfTextExtractor(document).extractText();
          document.dispose();
        } else {
          text = await file.readAsString();
        }

        widget.onFileAttached(
          AttachedFile(name: result.files.single.name, content: text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document attached successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to read document: $e')));
      }
    }
  }

  void _updateSearchSettings() {
    final rawKeyString = _searchKeyController.text.trim();
    final keys = rawKeyString
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    widget.onSearchSettingsChanged(
      SearchSettings(
        enabled: _searchEnabled,
        provider: _searchProvider,
        apiKey: keys.isNotEmpty ? keys.first : '',
        fallbackApiKeys: keys.length > 1 ? keys.sublist(1) : const [],
        googleCx: _searchCxController.text.trim(),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final active = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7B4E2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? Colors.white : const Color(0xFF6C5946),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : const Color(0xFF6C5946),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentProvider = providerCatalog.firstWhere(
      (p) => p.id == _selectedProviderId,
    );
    final models = widget.cachedModels.isNotEmpty
        ? widget.cachedModels
        : currentProvider.models;
    final visionEnabled = modelHasVision(_selectedModel);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle at top
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFDCCBB8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header Row
          const Text(
            'Input & Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2D241C),
              letterSpacing: -0.5,
            ),
          ),

          // Custom Tab Bar Selector
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EBE0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _buildTabButton(0, Icons.smart_toy_outlined, 'Model'),
                _buildTabButton(1, Icons.explore_outlined, 'Capabilities'),
                _buildTabButton(2, Icons.account_circle_outlined, 'Account'),
                _buildTabButton(3, Icons.attachment_outlined, 'Attach'),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE7D8C4), height: 1),
          const SizedBox(height: 14),

          // Scrollable Content Pane
          Expanded(
            child: SingleChildScrollView(
              child: _buildActiveTabContent(models, visionEnabled),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent(List<String> models, bool visionEnabled) {
    switch (_activeTab) {
      case 0:
        return _buildModelTab(models);
      case 1:
        return _buildCapabilitiesTab();
      case 2:
        return _buildAccountTab();
      case 3:
        return _buildAttachTab(visionEnabled);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildModelTab(List<String> models) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdowns Group Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7EC),
            border: Border.all(color: const Color(0xFFEADCC9)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedProviderId,
                      dropdownColor: const Color(0xFFFFFBF2),
                      decoration: const InputDecoration(
                        labelText: 'AI Provider',
                        labelStyle: TextStyle(
                          color: Color(0xFF6C5946),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF7B4E2E)),
                        ),
                        prefixIcon: Icon(
                          Icons.hub_outlined,
                          color: Color(0xFF7B4E2E),
                          size: 20,
                        ),
                      ),
                      items: providerCatalog.map((p) {
                        return DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final nextProvider = providerCatalog.firstWhere(
                            (p) => p.id == val,
                          );
                          setState(() {
                            _selectedProviderId = val as String;
                            _selectedModel = nextProvider.models.isNotEmpty
                                ? nextProvider.models.first
                                : '';
                          });
                          widget.onProviderChanged(val as String);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCCBB8)),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onConfigureKey(_selectedProviderId);
                      },
                      child: const Icon(
                        Icons.key,
                        color: Color(0xFF7B4E2E),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: models.contains(_selectedModel)
                          ? _selectedModel
                          : (models.isNotEmpty ? models.first : null),
                      dropdownColor: const Color(0xFFFFFBF2),
                      decoration: const InputDecoration(
                        labelText: 'Model Name',
                        labelStyle: TextStyle(
                          color: Color(0xFF6C5946),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF7B4E2E)),
                        ),
                        prefixIcon: Icon(
                          Icons.memory_outlined,
                          color: Color(0xFF7B4E2E),
                          size: 20,
                        ),
                      ),
                      items: models.map((m) {
                        return DropdownMenuItem<String>(
                          value: m,
                          child: Text(
                            m,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedModel = val as String);
                          widget.onModelChanged(val as String);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCCBB8)),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      onPressed: _fetching ? null : _fetch,
                      child: _fetching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF7B4E2E),
                              ),
                            )
                          : const Icon(
                              Icons.sync,
                              color: Color(0xFF7B4E2E),
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Token Slider Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Max Output Tokens',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_maxTokens tokens',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () async {
                          final controller = TextEditingController(
                            text: _maxTokens.toString(),
                          );
                          final customVal = await showDialog<int>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFFFFFBF2),
                              title: const Text(
                                'Custom Token Limit',
                                style: TextStyle(
                                  color: Color(0xFF2D241C),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: TextField(
                                controller: controller,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Enter token limit',
                                  hintText: 'e.g. 32768, 128000',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    final val = int.tryParse(controller.text);
                                    Navigator.pop(ctx, val);
                                  },
                                  child: const Text('Set'),
                                ),
                              ],
                            ),
                          );
                          if (customVal != null && customVal > 0) {
                            setState(() {
                              _maxTokens = customVal;
                            });
                            widget.onMaxTokensChanged(customVal);
                          }
                        },
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Slider(
                value: _maxTokens.toDouble().clamp(128, 16384),
                min: 128,
                max: 16384,
                divisions: 63,
                activeColor: const Color(0xFF7B4E2E),
                inactiveColor: const Color(0xFFE7D8C4),
                onChanged: (val) {
                  setState(() => _maxTokens = (val as double).round());
                  widget.onMaxTokensChanged((val as double).round());
                },
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [512, 1024, 2048, 4096, 8192].map((preset) {
                    final selected = _maxTokens == preset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ChoiceChip(
                        label: Text(
                          preset.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF6C5946),
                          ),
                        ),
                        selected: selected,
                        selectedColor: const Color(0xFF7B4E2E),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: selected
                              ? Colors.transparent
                              : const Color(0xFFE5DDD3),
                        ),
                        onSelected: (sel) {
                          if (sel == true) {
                            setState(() => _maxTokens = preset);
                            widget.onMaxTokensChanged(preset);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Thinking / Reasoning Switch Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CoT Thinking / Reasoning',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Allow models to think step-by-step',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Switch(
                value: _reasoningEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) {
                  setState(() => _reasoningEnabled = val);
                  widget.onReasoningEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCapabilitiesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File Access Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7EC),
            border: Border.all(color: const Color(0xFFEADCC9)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agentic File Access',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Let models read/write local files',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _agenticEnabled,
                    activeColor: const Color(0xFF7B4E2E),
                    onChanged: (val) {
                      setState(() => _agenticEnabled = val);
                      widget.onAgenticEnabledChanged(val);
                    },
                  ),
                ],
              ),
              if (_agenticEnabled) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _agenticWorkspaceController,
                  decoration: const InputDecoration(
                    labelText: 'Workspace Directory Path',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                    hintText: 'e.g. /data/data/com.termux/files/home',
                  ),
                  onChanged: widget.onAgenticWorkspaceChanged,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customMcpUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Custom MCP URL (Optional)',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                    hintText: 'e.g. http://192.168.1.10:8390/mcp',
                  ),
                  onChanged: widget.onCustomMcpUrlChanged,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Web Search Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agentic Web Search',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Let models search the web if needed',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _searchEnabled,
                    activeColor: const Color(0xFF7B4E2E),
                    onChanged: (val) {
                      setState(() => _searchEnabled = val);
                      _updateSearchSettings();
                    },
                  ),
                ],
              ),
              if (_searchEnabled) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _searchProvider,
                  dropdownColor: const Color(0xFFFFFBF2),
                  decoration: const InputDecoration(
                    labelText: 'Search API Provider',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: ['tavily', 'exa', 'firecrawl', 'google'].map((p) {
                    return DropdownMenuItem<String>(
                      value: p,
                      child: Text(
                        p.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _searchProvider = val);
                      _updateSearchSettings();
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Search API Key(s) (comma-separated)',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                    hintText: 'key1, key2...',
                  ),
                  obscureText: true,
                  onChanged: (_) => _updateSearchSettings(),
                ),
                if (_searchProvider == 'google') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCxController,
                    decoration: const InputDecoration(
                      labelText: 'Google Search Engine ID (CX)',
                      labelStyle: TextStyle(
                        color: Color(0xFF6C5946),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateSearchSettings(),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Artifacts Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Markdown Artifacts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Let models create structured markdown artifacts',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                ],
              ),
              Switch(
                value: _artifactsEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) {
                  setState(() => _artifactsEnabled = val);
                  widget.onArtifactsEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // SVG Visuals Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SVG Visuals',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Let models render dynamic SVG diagrams',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                ],
              ),
              Switch(
                value: _svgVisualsEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) {
                  setState(() => _svgVisualsEnabled = val);
                  widget.onSvgVisualsEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Agentic Deep Research Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agentic Deep Research',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Let models perform iterative multi-step research plans',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                ],
              ),
              Switch(
                value: _deepResearchEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) async {
                  if (val) {
                    final result = await _checkBridgeAlive();
                    if (!mounted) return;
                    if (result['ok'] != true) {
                      final reason = result['reason']?.toString() ?? 'bridge_unreachable';
                      _showDeepResearchSetupDialog(reason: reason);
                      setState(() => _deepResearchEnabled = false);
                      widget.onDeepResearchEnabledChanged(false);
                      return;
                    }
                  }
                  setState(() => _deepResearchEnabled = val);
                  widget.onDeepResearchEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Writer Context Budget Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Writer Context Budget',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set this near your selected model\'s context limit, leaving room for instructions and output. '
                'The writer reserves ~18% for prompts; the rest is available for evidence.',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6C5946),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _writerContextBudgetController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g. 32000',
                        suffixText: 'tokens',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5DDD3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF7B4E2E),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5DDD3),
                          ),
                        ),
                      ),
                      onSubmitted: (val) {
                        final parsed = int.tryParse(val.trim());
                        if (parsed != null && parsed > 0) {
                          setState(() => _writerContextBudget = parsed);
                          widget.onWriterContextBudgetChanged(parsed);
                        } else {
                          // Reset field to current valid value
                          _writerContextBudgetController.text =
                              _writerContextBudget.toString();
                        }
                      },
                      onEditingComplete: () {
                        final parsed = int.tryParse(
                          _writerContextBudgetController.text.trim(),
                        );
                        if (parsed != null && parsed > 0) {
                          setState(() => _writerContextBudget = parsed);
                          widget.onWriterContextBudgetChanged(parsed);
                        } else {
                          _writerContextBudgetController.text =
                              _writerContextBudget.toString();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Current: $_writerContextBudget tokens  ·  Evidence cap: ${(_writerContextBudget * 0.82).floor()} tokens',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7B4E2E),
                  fontStyle: FontStyle.italic,
                ),
              ),
              // Soft advisory — shown only when the budget is very low.
              // This is purely informational; deep research will still run.
              if (_writerContextBudget <= 8192)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      border: Border.all(color: const Color(0xFFFFCC02)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1, right: 8),
                          child: Icon(Icons.info_outline, size: 16, color: Color(0xFFF9A825)),
                        ),
                        Expanded(
                          child: Text(
                            'Low context budget: Deep Research works best with at least '
                            '16 000 tokens. With $_writerContextBudget tokens, only a small '
                            'amount of evidence will fit and report quality may be reduced. '
                            'You can still run it — this is only a heads-up.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6D4C00),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cloud Sync & Backup Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google Drive Backup',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Auto-sync chats & artifacts to Drive',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _driveBackupEnabled,
                    activeColor: const Color(0xFF7B4E2E),
                    onChanged: (val) async {
                      setState(() => _driveBackupEnabled = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('google_drive_backup_enabled', val);
                    },
                  ),
                ],
              ),
              if (_driveBackupEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Live progress status text
                      if (_syncProgressStatus.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Color(0xFF7B4E2E),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _syncProgressStatus,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7B4E2E),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: _isRestoring || _isBackingUp
                                ? null
                                : () async {
                                    setState(() {
                                      _isRestoring = true;
                                      _syncProgressStatus = 'Starting restore…';
                                    });
                                    try {
                                      final result =
                                          await DriveSyncService.restoreFromDriveDetailed(
                                            onProgress: (status) {
                                              if (mounted) {
                                                setState(() => _syncProgressStatus = status);
                                              }
                                            },
                                          );
                                      if (mounted) {
                                        setState(() => _syncProgressStatus = '');
                                        if (result.success) {
                                          await widget.onRestoreCompleted();
                                        }
                                        _showSyncResultDialog(
                                          context,
                                          title: result.success ? 'Restore Complete' : 'Restore Failed',
                                          message: result.message,
                                          details: result.details,
                                          success: result.success,
                                          needsRelogin: result.needsRelogin,
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() => _syncProgressStatus = '');
                                        _showSyncResultDialog(
                                          context,
                                          title: 'Restore Error',
                                          message: 'Unexpected error: $e',
                                          details: [],
                                          success: false,
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isRestoring = false;
                                          _syncProgressStatus = '';
                                        });
                                      }
                                    }
                                  },
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download, size: 16),
                            label: Text(
                              _isRestoring ? 'Restoring…' : 'Restore',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF7B4E2E),
                              backgroundColor: const Color(0xFFF5EFE6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _isBackingUp || _isRestoring
                                ? null
                                : () async {
                                    setState(() {
                                      _isBackingUp = true;
                                      _syncProgressStatus = 'Starting backup…';
                                    });
                                    try {
                                      final result =
                                          await DriveSyncService.syncToDriveDetailed(
                                            widget.sessions,
                                            force: true,
                                            onProgress: (status) {
                                              if (mounted) {
                                                setState(() => _syncProgressStatus = status);
                                              }
                                            },
                                          );
                                      if (mounted) {
                                        setState(() => _syncProgressStatus = '');
                                        _showSyncResultDialog(
                                          context,
                                          title: result.success ? 'Backup Complete' : 'Backup Failed',
                                          message: result.message,
                                          details: result.details,
                                          success: result.success,
                                          needsRelogin: result.needsRelogin,
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() => _syncProgressStatus = '');
                                        _showSyncResultDialog(
                                          context,
                                          title: 'Backup Error',
                                          message: 'Unexpected error: $e',
                                          details: [],
                                          success: false,
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isBackingUp = false;
                                          _syncProgressStatus = '';
                                        });
                                      }
                                    }
                                  },
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload, size: 16),
                            label: Text(
                              _isBackingUp ? 'Backing up…' : 'Force Backup',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF7B4E2E),
                              backgroundColor: const Color(0xFFF5EFE6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const Divider(height: 32, color: Color(0xFFE5DDD3)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Supabase
                                .instance
                                .client
                                .auth
                                .currentSession
                                ?.user
                                .email ??
                            'Not logged in',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF2D241C),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (Supabase.instance.client.auth.currentSession !=
                          null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Active Plan: ${_activePlanTier.isEmpty ? "FREE" : _activePlanTier.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF7B4E2E),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Daily Pool: ${_liveDailyPool != null ? "${_formatNumber(_liveDailyPool!)} / ${_formatNumber(_getTotalDailyCap(_activePlanTier))}" : "Loading..."}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6C5946),
                          ),
                        ),
                        if (_activePlanTier.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Monthly Pool: ${_liveSubscriptionCredits != null ? "${_formatNumber(_liveSubscriptionCredits!)} / ${_formatNumber(_getTotalMonthlyCap(_activePlanTier))}" : "Loading..."}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6C5946),
                            ),
                          ),
                        ],
                        if (_liveTopupCredits != null &&
                            _liveTopupCredits! > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Top-up Credits: ${_formatNumber(_liveTopupCredits!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6C5946),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('has_completed_onboarding_v2', false);
                      await Supabase.instance.client.auth.signOut();
                      if (mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ForgeChatApp(
                              hasCompletedOnboarding: false,
                            ),
                          ),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, size: 16, color: Colors.red),
                    label: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Memory Settings Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Memory',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Clear personalized facts learned by AI',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final docDir = await getApplicationDocumentsDirectory();
                  final memoryFile = File('${docDir.path}/nexon_memory.json');
                  if (await memoryFile.exists()) {
                    await memoryFile.writeAsString('');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('AI Memory cleared!')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('AI Memory is already empty.'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.red,
                ),
                label: const Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Subscription Settings Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nexon Pro Subscription',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _managedSubscriptionEnabled
                          ? 'Active Plan: ${_activePlanTier.toUpperCase()}'
                          : 'Switch to a Managed API key and skip the hassle.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (sheetContext) {
                      return Padding(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 24,
                          bottom:
                              MediaQuery.of(sheetContext).viewInsets.bottom +
                              24,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Manage Subscription',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF2D241C),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        Navigator.pop(sheetContext),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildSubscriptionPlans(),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D241C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Manage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSubscriptionPlans() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPlanCard(
          title: 'GO',
          subtitle: 'The Student / Hobbyist Tier',
          price: '₹249',
          monthlyCredits: '16.5M',
          dailyCap: '550K',
          color: const Color(0xFFE8F3EB),
          borderColor: const Color(0xFFC3DFCD),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: 'PLUS',
          subtitle: 'The Light Freelancer Tier',
          price: '₹499',
          monthlyCredits: '33.5M',
          dailyCap: '1.1M',
          color: const Color(0xFFEBF0F6),
          borderColor: const Color(0xFFC7D9EA),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: 'PRO',
          subtitle: 'The Professional Tier',
          price: '₹899',
          monthlyCredits: '61.0M',
          dailyCap: '2.0M',
          color: const Color(0xFFF6EBF0),
          borderColor: const Color(0xFFEAC7D9),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: 'MAX',
          subtitle: 'The Power User Tier',
          price: '₹1,399',
          monthlyCredits: '95.0M',
          dailyCap: '3.1M',
          color: const Color(0xFFFFF7E6),
          borderColor: const Color(0xFFFFD580),
          isPremium: true,
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String subtitle,
    required String price,
    required String monthlyCredits,
    required String dailyCap,
    required Color color,
    required Color borderColor,
    bool isPremium = false,
  }) {
    final bool isThisPlanActive =
        _managedSubscriptionEnabled && _activePlanTier == title.toLowerCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: isPremium ? 2 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      if (isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D241C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'BEST VALUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6C5946),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '$price/mo',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPlanStat(
                'Monthly Credits',
                isThisPlanActive && _liveSubscriptionCredits != null
                    ? '${(_liveSubscriptionCredits! / 1000000).toStringAsFixed(1)}M'
                    : monthlyCredits,
              ),
              _buildPlanStat(
                'Daily Cap',
                isThisPlanActive && _liveDailyPool != null
                    ? '${(_liveDailyPool! / 1000).toStringAsFixed(1)}K'
                    : dailyCap,
              ),
              ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final newState = !isThisPlanActive;
                  final newTier = newState ? title.toLowerCase() : '';
                  await prefs.setBool(
                    'nexon_managed_subscription_enabled',
                    newState,
                  );
                  await prefs.setString('nexon_managed_plan_tier', newTier);
                  if (newState) {
                    await prefs.setString(
                      'nexon_managed_backend_url',
                      'https://nexon-jyp1.onrender.com',
                    );
                  }
                  setState(() {
                    _managedSubscriptionEnabled = newState;
                    _activePlanTier = newTier;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          newState
                              ? 'Activated Nexon $title Plan!'
                              : 'Reverted to Bring-Your-Own-Key',
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isThisPlanActive
                      ? Colors.green
                      : const Color(0xFF2D241C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(
                  isThisPlanActive ? 'Active' : 'Subscribe',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D241C),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachTab(bool visionEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Media & Document Attachments',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose photos, capture via camera, or attach documents to send as context.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
              ),
              const SizedBox(height: 18),

              // Grid of media attachment buttons
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _buildAttachTile(
                    Icons.image_outlined,
                    'Photos',
                    'Gallery images',
                    isEnabled: true,
                    onTap: _pickImage,
                  ),
                  _buildAttachTile(
                    Icons.camera_alt_outlined,
                    'Camera',
                    'Capture photo',
                    isEnabled: true,
                    onTap: _pickImage,
                  ),
                  _buildAttachTile(
                    Icons.insert_drive_file_outlined,
                    'Document',
                    'PDF, TXT, MD, Code',
                    isEnabled: true,
                    onTap: _pickFile,
                  ),
                  _buildAttachTile(
                    Icons.mic_none_outlined,
                    'Audio',
                    'Voice notes',
                    isEnabled: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Audio input is not supported yet.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttachTile(
    IconData icon,
    String title,
    String subtitle, {
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : const Color(0xFFF1EAE0),
            border: Border.all(
              color: isEnabled ? const Color(0xFFE2D6C5) : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 24,
                color: isEnabled
                    ? const Color(0xFF7B4E2E)
                    : const Color(0xFF9E8F7F),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isEnabled
                      ? const Color(0xFF2D241C)
                      : const Color(0xFF9E8F7F),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isEnabled
                      ? const Color(0xFF77624F)
                      : const Color(0xFFB0A59A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaItem(
    IconData icon,
    String label, {
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : const Color(0xFFF8F5F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled ? const Color(0xFFDCCBB8) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: isEnabled
                    ? const Color(0xFF7B4E2E)
                    : const Color(0xFFB0A496),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isEnabled
                      ? const Color(0xFF2D241C)
                      : const Color(0xFFB0A496),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show a detailed result dialog after backup/restore with step-by-step log.
  void _showSyncResultDialog(
    BuildContext context, {
    required String title,
    required String message,
    required List<String> details,
    required bool success,
    bool needsRelogin = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              success ? Icons.cloud_done : Icons.cloud_off,
              color: success ? Colors.green : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: success
                        ? const Color(0xFF3B7A3B)
                        : const Color(0xFFB33A3A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (needsRelogin) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Color(0xFFD4A017), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sign out and sign in again with Google to re-authorize Drive access.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF7B6B2E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Details:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7B4E2E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5EFE6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: details.map((line) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            line,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: line.startsWith('❌')
                                  ? const Color(0xFFB33A3A)
                                  : line.startsWith('✅')
                                      ? const Color(0xFF3B7A3B)
                                      : line.startsWith('⚠️')
                                          ? const Color(0xFFD4A017)
                                          : const Color(0xFF5A4A3A),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(color: Color(0xFF7B4E2E)),
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderSettingsSheet extends StatefulWidget {
  const ProviderSettingsSheet({
    required this.provider,
    required this.settings,
    required this.cachedModels,
    required this.onFetchModels,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final Future<List<String>> Function() onFetchModels;

  @override
  State<ProviderSettingsSheet> createState() => _ProviderSettingsSheetState();
}

class _ProviderSettingsSheetState extends State<ProviderSettingsSheet> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _maxTokensController;
  final List<TextEditingController> _fallbackControllers = [];
  List<String> _models = [];
  var _fetching = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.settings.apiKey);
    _baseUrlController = TextEditingController(text: widget.settings.baseUrl);
    _modelController = TextEditingController(text: widget.settings.model);
    _maxTokensController = TextEditingController(
      text: widget.settings.maxTokens.toString(),
    );
    for (final key in widget.settings.fallbackApiKeys) {
      if (key.trim().isNotEmpty) {
        _fallbackControllers.add(TextEditingController(text: key));
      }
    }
    _models = widget.cachedModels;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    for (final c in _fallbackControllers) c.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      setState(() => _models = models);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model fetch failed: $error')));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: widget.provider.name,
      subtitle: '${widget.provider.keyLabel}  |  ${widget.provider.baseUrl}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.provider.requiresKey
                  ? 'API key'
                  : 'API key (optional)',
              prefixIcon: const Icon(Icons.key),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Fallback API Keys',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B3027),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF7B4E2E)),
                onPressed: () {
                  setState(() {
                    _fallbackControllers.add(TextEditingController());
                  });
                },
              ),
            ],
          ),
          ..._fallbackControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final controller = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Fallback Key ${idx + 1}',
                        prefixIcon: const Icon(Icons.vpn_key),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      setState(() {
                        _fallbackControllers[idx].dispose();
                        _fallbackControllers.removeAt(idx);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Selected model',
                    prefixIcon: Icon(Icons.memory),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Fetch'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Max tokens',
              helperText:
                  'Lower this if a provider says you do not have enough credits.',
              prefixIcon: Icon(Icons.speed),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 138,
            child: ListView.builder(
              itemCount: _models.length,
              itemBuilder: (context, index) {
                final model = _models[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.radio_button_unchecked, size: 18),
                  title: Text(model, overflow: TextOverflow.ellipsis),
                  onTap: () => _modelController.text = model,
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final parsedMaxTokens =
                        int.tryParse(_maxTokensController.text.trim()) ??
                        widget.provider.defaultMaxTokens;
                    Navigator.of(context).pop(
                      ProviderSettings(
                        apiKey: _keyController.text.trim(),
                        baseUrl: _baseUrlController.text.trim(),
                        model: _modelController.text.trim(),
                        maxTokens: parsedMaxTokens.clamp(1, 131072).toInt(),
                        fallbackApiKeys: _fallbackControllers
                            .map((c) => c.text.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                      ),
                    );
                  },
                  child: const Text('Save provider'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ModelPickerSheet extends StatefulWidget {
  const ModelPickerSheet({
    required this.provider,
    required this.models,
    required this.selectedModel,
    required this.isFetching,
    required this.onFetchModels,
    super.key,
  });

  final ProviderDefinition provider;
  final List<String> models;
  final String selectedModel;
  final bool isFetching;
  final Future<List<String>> Function() onFetchModels;

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  final _searchController = TextEditingController();
  final _manualController = TextEditingController();
  late List<String> _models;
  var _fetching = false;

  @override
  void initState() {
    super.initState();
    _models = widget.models;
    _manualController.text = widget.selectedModel;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      setState(() => _models = models);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model fetch failed: $error')));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _models.where((model) {
      return query.isEmpty || model.toLowerCase().contains(query);
    }).toList();

    return SheetFrame(
      title: 'Select model',
      subtitle: widget.provider.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SearchBox(
                  controller: _searchController,
                  hint: 'Search models or type below',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: const Text('Fetch'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manualController,
            decoration: const InputDecoration(
              labelText: 'Manual model ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No models found matching query.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final model = filtered[index];
                      final selected = model == widget.selectedModel;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected ? const Color(0xFF7B4E2E) : const Color(0xFF6C5946),
                        ),
                        title: Text(
                          model,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(model),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_manualController.text),
              child: const Text('Use typed model'),
            ),
          ),
        ],
      ),
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 10,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF3),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE0CEB8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.notoSerif(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF77624F)),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: const Color(0xFFFFFBF4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2D0BA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2D0BA)),
        ),
      ),
    );
  }
}

class AppMark extends StatelessWidget {
  const AppMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/icon_transparent.png',
        fit: BoxFit.cover,
        width: 38,
        height: 38,
      ),
    );
  }
}

enum AvatarAnimationState { idle, typing, reasoning, searching, mcp }

class ProviderAvatar extends StatefulWidget {
  const ProviderAvatar({
    required this.label,
    this.small = false,
    this.animationState = AvatarAnimationState.idle,
    super.key,
  });

  final String label;
  final bool small;
  final AvatarAnimationState animationState;

  @override
  State<ProviderAvatar> createState() => _ProviderAvatarState();
}

class _ProviderAvatarState extends State<ProviderAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.animationState != AvatarAnimationState.idle) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ProviderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationState != AvatarAnimationState.idle &&
        oldWidget.animationState == AvatarAnimationState.idle) {
      _controller.repeat(reverse: true);
    } else if (widget.animationState == AvatarAnimationState.idle &&
        oldWidget.animationState != AvatarAnimationState.idle) {
      _controller.stop();
      _controller.animateTo(0);
    } else if (widget.animationState != oldWidget.animationState) {
      // Just ensure it's still running, maybe change duration depending on state
      if (widget.animationState == AvatarAnimationState.searching ||
          widget.animationState == AvatarAnimationState.mcp) {
        _controller.duration = const Duration(milliseconds: 800);
      } else if (widget.animationState == AvatarAnimationState.reasoning) {
        _controller.duration = const Duration(milliseconds: 2000);
      } else {
        _controller.duration = const Duration(milliseconds: 1200);
      }
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.small ? 24.0 : 38.0;

    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/icon_transparent.png',
        fit: BoxFit.cover,
        width: size,
        height: size,
      ),
    );

    if (widget.animationState == AvatarAnimationState.idle) return avatar;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (widget.animationState == AvatarAnimationState.typing) {
          // Subtle pulse
          return Transform.scale(
            scale: 0.85 + (_controller.value * 0.15),
            child: child,
          );
        } else if (widget.animationState == AvatarAnimationState.reasoning) {
          // Slow breathing/fade
          return Opacity(
            opacity: 0.4 + (_controller.value * 0.6),
            child: Transform.scale(
              scale: 0.9 + (_controller.value * 0.1),
              child: child,
            ),
          );
        } else if (widget.animationState == AvatarAnimationState.searching) {
          // Fast pulse + slight rotation
          return Transform.rotate(
            angle: _controller.value * 0.5 - 0.25,
            child: Transform.scale(
              scale: 0.8 + (_controller.value * 0.3),
              child: child,
            ),
          );
        } else if (widget.animationState == AvatarAnimationState.mcp) {
          // Bounce / aggressive scale for tool execution
          return Transform.translate(
            offset: Offset(0, -5 * _controller.value),
            child: Transform.scale(
              scale: 0.8 + (_controller.value * 0.3),
              child: child,
            ),
          );
        }
        return child!;
      },
      child: avatar,
    );
  }
}

class ChatClient {
  /// Models that accept image input (multimodal/vision).
  static final Set<String> modelsWithVision = {};

  /// Models that can generate images from text (text-to-image).
  static final Set<String> modelsWithImageGeneration = {};

  /// Models that can generate videos from text (text-to-video).
  static final Set<String> modelsWithVideoGeneration = {};

  static final liveDailyPool = ValueNotifier<int?>(null);
  static final liveSubscriptionCredits = ValueNotifier<int?>(null);
  static final liveTopupCredits = ValueNotifier<int?>(null);

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
        liveSubscriptionCredits.value = response['subscription_credits'] as int?;
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
    final client = HttpClient()
      ..findProxy = ((uri) => "DIRECT")
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse('${_baseUrl(provider, settings)}/models');
      final request = await client.getUrl(uri);
      _setHeaders(request, provider, settings, settings.apiKey, stream: false);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
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
              final outputPart = parts.length > 1 ? parts.last.trim() : modality;

              // Detect text-to-image generation models
              if (outputPart.contains('image') && !outputPart.contains('text')) {
                ChatClient.modelsWithImageGeneration.add(id);
                // Don't add to text list — these are pure image generators
                continue;
              }

              // Detect text-to-video generation models
              if (outputPart.contains('video') && !outputPart.contains('text')) {
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
                if (capStr == 'vision' || capStr.contains('image') || capStr.contains('vision')) {
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
      client.close(force: true);
    }
  }

  Future<String> sendChat({
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    required List<ChatMessage> messages,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isManagedMode = provider.id == 'nexon';
    final managedUrl =
        prefs.getString('nexon_managed_backend_url') ??
        'https://nexon-jyp1.onrender.com';
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken ?? '';

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
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
                if (message.files.isNotEmpty) {
                  finalText += '\n\n';
                  for (final file in message.files) {
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
              if (provider.id == 'openrouter')
                'include_reasoning': settings.reasoningEnabled,
            };

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
      client.close(force: true);
    }
  }

  Stream<String> sendChatStream({
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    required List<ChatMessage> messages,
  }) async* {
    final prefs = await SharedPreferences.getInstance();
    final isManagedMode = provider.id == 'nexon';
    final managedUrl =
        prefs.getString('nexon_managed_backend_url') ??
        'https://nexon-jyp1.onrender.com';
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken ?? '';

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
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
                if (message.files.isNotEmpty) {
                  finalText += '\n\n';
                  for (final file in message.files) {
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
              if (provider.id == 'openrouter')
                'include_reasoning': settings.reasoningEnabled,
            };

            final payloadBytes = utf8.encode(jsonEncode(payload));
            request.headers.contentLength = payloadBytes.length;
            request.add(payloadBytes);
            response = await request.close();

            if (response.statusCode < 200 || response.statusCode >= 300) {
              final body = await response.transform(utf8.decoder).join();
              throw HttpException('HTTP ${response.statusCode}: $body');
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
                  liveSubscriptionCredits.value = status['subscription'] as int?;
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
      client.close(force: true);
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
              if (tr == 'd') trVal = 'day';
              else if (tr == 'w') trVal = 'week';
              else if (tr == 'm') trVal = 'month';
              else if (tr == 'y') trVal = 'year';
              else trVal = tr;
            }

            // Give current-events queries a current, thorough result set even
            // if the model omitted optional search attributes.
            final isFreshQuery = RegExp(
              r'\b(latest|recent|current|today|news|update|updated|release|price|pricing|202\d)\b',
              caseSensitive: false,
            ).hasMatch(query);
            final effectiveTopic = topic ?? (isFreshQuery ? 'news' : null);
            final effectiveTimeRange = trVal ?? (isFreshQuery ? 'month' : null);
            final effectiveDepth = searchDepth == 'advanced' || searchDepth == 'basic'
                ? searchDepth!
                : (isFreshQuery ? 'advanced' : 'basic');

            final Map<String, dynamic> payload = {
              'api_key': currentKey,
              'query': query,
              'max_results': 6,
              'search_depth': effectiveDepth,
            };
            if (effectiveTopic != null) payload['topic'] = effectiveTopic;
            if (effectiveTimeRange != null) payload['time_range'] = effectiveTimeRange;
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
              return results.map((r) {
                final publishedDate = r is Map ? r['published_date']?.toString() : null;
                final datePrefix = publishedDate == null || publishedDate.isEmpty
                    ? ''
                    : 'Published $publishedDate — ';
                return '- [${r['title']}](${r['url']}): $datePrefix${r['content']}';
              }).join('\n\n');
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
          } else if (provider == 'duckduckgo') {
            final uri = Uri.parse('https://lite.duckduckgo.com/lite/');
            final request = await client.postUrl(uri);
            request.headers.contentType =
                ContentType('application', 'x-www-form-urlencoded');
            request.headers.set(
              'User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            );
            final bodyBytes = utf8.encode('q=${Uri.encodeQueryComponent(query)}');
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

              title = title.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').trim();
              snippet = snippet.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').trim();

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
}

class ProviderSettings {
  const ProviderSettings({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.maxTokens,
    this.fallbackApiKeys = const [],
    this.reasoningEnabled = true,
  });

  factory ProviderSettings.defaults(ProviderDefinition provider) {
    return ProviderSettings(
      apiKey: '',
      baseUrl: provider.baseUrl,
      model: provider.models.first,
      maxTokens: provider.defaultMaxTokens,
      fallbackApiKeys: const [],
      reasoningEnabled: true,
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
    );
  }

  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxTokens;
  final List<String> fallbackApiKeys;
  final bool reasoningEnabled;

  ProviderSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? maxTokens,
    List<String>? fallbackApiKeys,
    bool? reasoningEnabled,
  }) {
    return ProviderSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      fallbackApiKeys: fallbackApiKeys ?? this.fallbackApiKeys,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
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
    };
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class SearchSettings {
  final bool enabled;
  final String provider; // 'tavily', 'exa', 'firecrawl', 'google'
  final String apiKey;
  final List<String> fallbackApiKeys;
  final String googleCx; // Google Search Engine ID

  const SearchSettings({
    required this.enabled,
    required this.provider,
    required this.apiKey,
    required this.fallbackApiKeys,
    required this.googleCx,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'provider': provider,
    'apiKey': apiKey,
    'fallbackApiKeys': fallbackApiKeys,
    'googleCx': googleCx,
  };

  SearchSettings copyWith({
    bool? enabled,
    String? provider,
    String? apiKey,
    List<String>? fallbackApiKeys,
    String? googleCx,
  }) {
    return SearchSettings(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      fallbackApiKeys: fallbackApiKeys ?? this.fallbackApiKeys,
      googleCx: googleCx ?? this.googleCx,
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

  const AttachedFile({required this.name, required this.content});

  Map<String, dynamic> toJson() => {'name': name, 'content': content};
  factory AttachedFile.fromJson(Map<String, dynamic> json) => AttachedFile(
    name: json['name']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
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
  });

  final MessageRole role;
  final String text;
  final bool isError;
  final String reasoning;
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
  }) {
    return ChatMessage(
      role: role ?? this.role,
      text: text ?? this.text,
      isError: isError ?? this.isError,
      reasoning: reasoning ?? this.reasoning,
      images: images ?? this.images,
      videos: videos ?? this.videos,
      files: files ?? this.files,
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
  });

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
];

class ResearchPlanWidget extends StatefulWidget {
  const ResearchPlanWidget({
    required this.stateMap,
    required this.workspaceDir,
    required this.fileName,
    required this.isSending,
    this.onStartResearch,
    super.key,
  });
  final Map<String, dynamic> stateMap;
  final String workspaceDir;
  final String fileName;
  final bool isSending;
  final void Function([Map<String, dynamic>? editedStateMap])?
      onStartResearch;

  @override
  State<ResearchPlanWidget> createState() => _ResearchPlanWidgetState();
}

class _ResearchPlanWidgetState extends State<ResearchPlanWidget> {
  final Set<int> _expandedSteps = {};
  late final Stopwatch _stopwatch;
  Timer? _timer;

  Future<void> _editPlan() async {
    final originalSteps = widget.stateMap['steps'] as List? ?? [];
    final controllers = originalSteps.map((step) {
      final value = step as Map;
      return TextEditingController(
        text: value['query_text']?.toString() ?? value['prompt']?.toString() ?? '',
      );
    }).toList();
    final titles = originalSteps
        .map((step) => (step as Map)['title']?.toString() ?? 'Research stage')
        .toList();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Edit Research Plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: controllers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => TextField(
                  controller: controllers[index],
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: titles[index],
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Save Plan'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final updatedSteps = <Map<String, dynamic>>[];
      for (var index = 0; index < originalSteps.length; index++) {
        final step = Map<String, dynamic>.from(originalSteps[index] as Map);
        step['query_text'] = controllers[index].text.trim();
        updatedSteps.add(step);
      }
      setState(() => widget.stateMap['steps'] = updatedSteps);
    }
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    final status = widget.stateMap['status'] as String? ?? 'running';
    final isRunning = status == 'running' && widget.isSending;
    if (isRunning) {
      _stopwatch.start();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final currentStatus = widget.stateMap['status'] as String? ?? 'running';
        final currentRunning = currentStatus == 'running' && widget.isSending;
        if (currentRunning) {
          if (!_stopwatch.isRunning) {
            _stopwatch.start();
          }
          setState(() {});
        } else {
          if (_stopwatch.isRunning) {
            _stopwatch.stop();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _downloadFile({bool asDocx = false}) async {
    String contentToSave = widget.stateMap['final_report'] as String? ?? '';
    if (contentToSave.isEmpty) {
      final steps = widget.stateMap['steps'] as List? ?? [];
      for (final step in steps) {
        contentToSave += '# ${step['title']}\n\n${step['content']}\n\n';
      }
    }

    if (contentToSave.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No research content to save.')),
        );
      }
      return;
    }

    try {
      final List<int> bytesList;
      final String targetFileName;

      if (asDocx) {
        final elements = await MarkdownParser.parse(contentToSave);
        final doc = DocxBuiltDocument(elements: elements);
        bytesList = await DocxExporter().exportToBytes(doc);
        
        String docxName = 'research_report.docx';
        if (widget.fileName.isNotEmpty) {
          final base = widget.fileName.split('.').first;
          docxName = '$base.docx';
        }
        targetFileName = docxName;
      } else {
        bytesList = utf8.encode(contentToSave);
        targetFileName = widget.fileName;
      }

      final bytes = Uint8List.fromList(bytesList);
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: asDocx ? 'Save Word Document' : 'Save Research Report',
        fileName: targetFileName,
        bytes: bytes,
      );

      if (path == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${path.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.stateMap['steps'] as List? ?? [];
    final status = widget.stateMap['status'] as String? ?? 'running';

    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0D3E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFE2ECF5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.science,
                        size: 18,
                        color: Color(0xFF2C5282),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status == 'completed'
                              ? 'Deep Research Complete'
                              : status == 'pending'
                              ? 'Research Plan Ready'
                              : (status == 'running' && !widget.isSending)
                              ? 'Deep Research Interrupted'
                              : 'Deep Research in Progress...',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C5282),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (status == 'pending' || (status == 'running' && !widget.isSending) || status == 'failed') ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending')
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          tooltip: 'Edit research plan',
                          onPressed: _editPlan,
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          color: const Color(0xFF2C5282),
                        ),
                      if (status == 'pending') const SizedBox(width: 4),
                      if (widget.onStartResearch != null)
                        FilledButton.icon(
                          onPressed: () => widget.onStartResearch!(widget.stateMap),
                          icon: Icon(
                            status == 'running' ? Icons.play_arrow : (status == 'failed' ? Icons.replay : Icons.play_arrow),
                            size: 16,
                          ),
                          label: Text(
                            status == 'running' ? 'Resume' : (status == 'failed' ? 'Retry' : 'Start'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2C5282),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                    ],
                  ),
                ],
                if (status == 'running' && widget.isSending)
                  Text(
                    '${_stopwatch.elapsed.inMinutes.toString().padLeft(2, '0')}:${(_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C5282),
                    ),
                  ),
                if (status == 'completed')
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.download,
                      size: 20,
                      color: Color(0xFF2C5282),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'markdown') {
                        _downloadFile(asDocx: false);
                      } else if (value == 'docx') {
                        _downloadFile(asDocx: true);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'docx',
                        child: Row(
                          children: [
                            Icon(Icons.description, size: 18, color: Color(0xFF2C5282)),
                            SizedBox(width: 8),
                            Text('Save as DOCX'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'markdown',
                        child: Row(
                          children: [
                            Icon(Icons.article, size: 18, color: Color(0xFF2C5282)),
                            SizedBox(width: 8),
                            Text('Save as Markdown'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: LinearProgressIndicator(
                value: steps.where((step) => step['status'] == 'completed' || step['status'] == 'completed_with_issues').length / steps.length,
                backgroundColor: const Color(0xFFCFE0EE),
                color: const Color(0xFF2C5282),
                minHeight: 5,
              ),
            ),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value as Map<String, dynamic>;
            final stepStatus = step['status'] as String;
            final isExpanded = _expandedSteps.contains(idx);

            IconData statusIcon = Icons.radio_button_unchecked;
            Color statusColor = Colors.grey;
            if (stepStatus == 'running') {
              statusIcon = Icons.hourglass_bottom;
              statusColor = Colors.blue;
            } else if (stepStatus == 'completed') {
              statusIcon = Icons.check_circle;
              statusColor = Colors.green;
            } else if (stepStatus == 'completed_with_issues') {
              statusIcon = Icons.warning_amber;
              statusColor = Colors.orange;
            }

            return Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded)
                        _expandedSteps.remove(idx);
                      else
                        _expandedSteps.add(idx);
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (step['title'] as String?) ?? 'Step ${idx + 1}',
                            style: TextStyle(
                              decoration: (stepStatus == 'completed' || stepStatus == 'completed_with_issues')
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: (stepStatus == 'completed' || stepStatus == 'completed_with_issues')
                                  ? Colors.grey
                                  : Colors.black87,
                              fontWeight: stepStatus == 'running'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    padding: const EdgeInsets.fromLTRB(40, 0, 14, 12),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prompt: ${step['query_text'] ?? step['prompt'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                       if ((step['events'] as List? ?? []).isNotEmpty) ...[
                         const SizedBox(height: 12),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: (step['events'] as List).length,
                            itemBuilder: (context, eventIndex) {
                              final event = (step['events'] as List)[eventIndex]
                                  as Map;
                              return _ResearchEventRow(
                                key: ValueKey(
                                  event['id']?.toString() ??
                                      'legacy-event-$eventIndex',
                                ),
                                event: event,
                              );
                            },
                          ),
                       ],
                        if (step['content'] != null &&
                            step['content'].toString().isNotEmpty)
                          ...step['content']
                              .toString()
                              .split('\n\n')
                              .where((s) => s.trim().isNotEmpty)
                              .map((s) {
                                if (s.contains('<mcp_request>')) {
                                  final jsonStr = s
                                      .substring(
                                        s.indexOf('<mcp_request>') + 13,
                                        s.indexOf('</mcp_request>'),
                                      )
                                      .trim();
                                  return McpToolBlock(mcpJson: jsonStr);
                               } else if (s.contains('<search_request>')) {
                                  final query = s
                                      .substring(
                                        s.indexOf('<search_request>') + 16,
                                        s.indexOf('</search_request>'),
                                      )
                                      .trim();
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F5FA),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFD0E0F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.search,
                                          color: Color(0xFF2B6CB0),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Searched the web for "$query"',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2B6CB0),
                                            ),
                                          ),
                                        ),
                                      ],
                                   ),
                                 );
                                } else if (s.contains('<read_url>')) {
                                  final url = s
                                      .substring(
                                        s.indexOf('<read_url>') + 10,
                                        s.indexOf('</read_url>'),
                                      )
                                      .trim();
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F5FA),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFD0E0F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.link,
                                          color: Color(0xFF2B6CB0),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Read webpage at "$url"',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2B6CB0),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                               }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    s,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.black54,
                                    ),
                                  ),
                                );
                              }),
                      ],
                    ),
                  ),
                if (idx < steps.length - 1)
                  const Divider(
                    height: 1,
                    indent: 40,
                    color: Color(0xFFE2ECF5),
                  ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _ResearchEventRow extends StatefulWidget {
  const _ResearchEventRow({super.key, required this.event});

  final Map event;

  @override
  State<_ResearchEventRow> createState() => _ResearchEventRowState();
}

class _ResearchEventRowState extends State<_ResearchEventRow> {
  Timer? _pulseTimer;
  var _dimmed = false;
  var _expanded = false;

  bool get _isRunning => widget.event['status'] == 'running';
  bool get _isIngesting => widget.event['status'] == 'ingesting';
  bool get _isError => widget.event['status'] == 'error';
  bool get _isPulsing => _isRunning || _isIngesting;
  bool get _canExpand {
    if (_isRunning) return false;
    if (_isError || _isIngesting) return true;
    final payload = widget.event['result_payload'];
    return payload is Map && payload.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _ResearchEventRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
    if (_isRunning && _expanded) _expanded = false;
  }

  void _syncPulse() {
    if (_isPulsing && _pulseTimer == null) {
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        if (mounted) setState(() => _dimmed = !_dimmed);
      });
    } else if (!_isPulsing && _pulseTimer != null) {
      _pulseTimer!.cancel();
      _pulseTimer = null;
      _dimmed = false;
    }
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  Widget _detailBlock(String text, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: accent,
        ),
      ),
    );
  }

  Widget _expandedPayload(Color accent) {
    if (_isIngesting) {
      final parseFormat = widget.event['parse_format']?.toString();
      return _detailBlock(
        'Content fetched${parseFormat != null ? " as ${parseFormat.toUpperCase()}" : ""}, summarizing content…',
        accent,
      );
    }
    if (_isError) {
      return _detailBlock(
        widget.event['error']?.toString() ?? 'Tool call failed.',
        accent,
      );
    }

    final payload = widget.event['result_payload'];
    if (payload is! Map) return const SizedBox.shrink();
    final kind = widget.event['kind']?.toString();
    if (kind == 'search') {
      final results = payload['results'];
      if (results is! List || results.isEmpty) {
        return _detailBlock('No displayable search results returned.', accent);
      }
      return Column(
        children: results.whereType<Map>().map((result) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFD8E5EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result['title']?.toString() ?? 'Search result',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result['snippet']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF52606D),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result['url']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    if (kind == 'fetch') {
      final addedVal = widget.event['new_chunks_added'];
      final stageVal = widget.event['stage']?.toString();
      final parseFormat = widget.event['parse_format']?.toString();
      final isDedup = addedVal is num && addedVal == 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            payload['url']?.toString() ??
                widget.event['url']?.toString() ??
                '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              if (parseFormat != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (parseFormat == 'pdf' || parseFormat == 'skipped_pdf') ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    parseFormat == 'skipped_pdf' ? 'SKIPPED (PDF)' : parseFormat.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: (parseFormat == 'pdf' || parseFormat == 'skipped_pdf') ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (stageVal != null) ...[
                Text(
                  stageVal,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 6),
              ],
              if (isDedup)
                const Text(
                  'Already read (cache hit)',
                  style: TextStyle(fontSize: 10, color: Color(0xFF5C6BC0), fontStyle: FontStyle.italic),
                ),
              if (widget.event.containsKey('facts_count') || widget.event.containsKey('findings_count'))
                Text(
                  '${widget.event['facts_count'] ?? 0} facts · ${widget.event['findings_count'] ?? 0} findings extracted',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF327342)),
                )
              else if (addedVal is num && addedVal > 0)
                Text(
                  '$addedVal new chunks added',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF327342)),
                ),
            ],
          ),
          const SizedBox(height: 5),
          _detailBlock(payload['content_preview']?.toString() ?? '', accent),
        ],
      );
    }
    return _detailBlock(payload['summary']?.toString() ?? '', accent);
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.event['kind']?.toString();
    final isSearch = kind == 'search';
    final isFetch = kind == 'fetch';
    final isError = _isError;
    final isRunning = _isRunning;
    final isIngesting = _isIngesting;
    final tool = widget.event['tool']?.toString() ?? kind ?? 'tool';
    final toolLabel = isSearch
        ? 'Web search'
        : isFetch
        ? 'Read URL'
        : tool;
    final target = isSearch
        ? widget.event['query']?.toString() ?? 'No query'
        : isFetch
        ? widget.event['url']?.toString() ?? 'No URL'
        : 'Tool: ' + tool;
    final resultCount = widget.event['result_count']?.toString();
    final added = widget.event['new_chunks_added'];
    final addedStr = added?.toString();
    final novelty = widget.event['novelty_ratio'];
    final latencyMs = widget.event['latency_ms'];
    final latency = latencyMs is num
        ? ' · ' + (latencyMs / 1000).toStringAsFixed(1) + 's'
        : '';
    final isDedup = (added is num && added == 0) || widget.event['already_attempted'] == true;
    final detail = isRunning
        ? 'Fetching…'
        : isIngesting
        ? 'Summarizing content…'
        : isError
        ? widget.event['error']?.toString() ?? 'Tool call failed'
        : isSearch
        ? (resultCount ?? '0') + ' results'
        : isFetch
        ? isDedup
            ? 'Already read'
            : widget.event.containsKey('facts_count')
                ? '${widget.event['facts_count']} facts · ${widget.event['findings_count']} findings'
                : (addedStr ?? '0') +
                      ' chunks' +
                      (novelty is num
                          ? ' · ' + (novelty * 100).toStringAsFixed(0) + '% novel'
                          : '')
        : tool;
    final background = isError
        ? const Color(0xFFF9ECE8)
        : isRunning
        ? const Color(0xFFEEF2F7)
        : isIngesting
        ? const Color(0xFFFFF8E1)
        : isSearch
        ? const Color(0xFFEAF3FA)
        : isFetch
        ? const Color(0xFFEDF6EF)
        : const Color(0xFFF3F4F6);
    final border = isError
        ? const Color(0xFF9B4D39)
        : isRunning
        ? const Color(0xFFB8C4D4)
        : isIngesting
        ? const Color(0xFFFFCC02)
        : isSearch
        ? const Color(0xFFB8D3E8)
        : isFetch
        ? const Color(0xFFB9D9C0)
        : const Color(0xFFD1D5DB);
    final accent = isError
        ? const Color(0xFF9B4D39)
        : isRunning
        ? const Color(0xFF5A6B7D)
        : isIngesting
        ? const Color(0xFFF57F17)
        : isSearch
        ? const Color(0xFF1D5E85)
        : isFetch
        ? const Color(0xFF327342)
        : const Color(0xFF4B5563);
    final icon = isError
        ? Icons.error_outline
        : isIngesting
        ? Icons.storage_outlined
        : isSearch
        ? Icons.search
        : isFetch
        ? Icons.language
        : Icons.settings;
    final statusIcon = isRunning
        ? Icons.more_horiz
        : isIngesting
        ? Icons.sync
        : isError
        ? Icons.error_outline
        : isDedup && isFetch
        ? Icons.inventory_2_outlined
        : Icons.check_circle;

    return InkWell(
      onTap: _canExpand ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 450),
        opacity: _isPulsing && _dimmed ? 0.58 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toolLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          target,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF52606D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(statusIcon, size: 16, color: accent),
                      if (!isRunning && latency.isNotEmpty)
                        Text(
                          latency.trim(),
                          style: TextStyle(fontSize: 10.5, color: accent),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: isError ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: accent),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeInOut,
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _expandedPayload(accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HtmlArtifactWidget extends StatelessWidget {
  final String htmlContent;
  const HtmlArtifactWidget({super.key, required this.htmlContent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getHtmlTitle(htmlContent),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FullScreenHtmlViewer(htmlContent: htmlContent),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF7B4E2E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'View File',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 150,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Text(
                htmlContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
                maxLines: 8,
                overflow: TextOverflow.fade,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullScreenHtmlViewer extends StatefulWidget {
  final String htmlContent;
  const FullScreenHtmlViewer({super.key, required this.htmlContent});

  @override
  State<FullScreenHtmlViewer> createState() => _FullScreenHtmlViewerState();
}

class _FullScreenHtmlViewerState extends State<FullScreenHtmlViewer> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    final html = widget.htmlContent;
    final wrappedHtml = html.contains('<html')
        ? html
        : '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 16px; background-color: #ffffff; }
  </style>
</head>
<body>
  \$html
</body>
</html>
''';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(wrappedHtml);
  }

  Future<void> _downloadFile() async {
    try {
      final filename = 'page_${DateTime.now().millisecondsSinceEpoch}.html';
      final bytes = Uint8List.fromList(utf8.encode(widget.htmlContent));
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save HTML Page',
        fileName: filename,
        bytes: bytes,
      );

      if (path == null) {
        return; // User cancelled
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${path.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Preview' : 'HTML Code'),
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: const Color(0xFF2D241C),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF2D241C)),
            onSelected: (value) {
              if (value == 'copy') {
                Clipboard.setData(ClipboardData(text: widget.htmlContent));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              } else if (value == 'preview') {
                setState(() => _showPreview = !_showPreview);
              } else if (value == 'download') {
                _downloadFile();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy')),
              PopupMenuItem(
                value: 'preview',
                child: Text(_showPreview ? 'Show Code' : 'Preview'),
              ),
              const PopupMenuItem(value: 'download', child: Text('Download')),
            ],
          ),
        ],
      ),
      body: _showPreview
          ? Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            )
          : Container(
              color: const Color(0xFF1E1E1E),
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    widget.htmlContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class SvgDiagramWidget extends StatefulWidget {
  final String svgString;
  const SvgDiagramWidget({super.key, required this.svgString});

  @override
  State<SvgDiagramWidget> createState() => _SvgDiagramWidgetState();
}

class _SvgDiagramWidgetState extends State<SvgDiagramWidget> {
  // Cache processed SVG so we don't re-run regex on every parent rebuild.
  late String _cachedSvg;
  late bool _isComplete;

  @override
  void initState() {
    super.initState();
    _cachedSvg = _cleanSvg(widget.svgString);
    _isComplete = _cachedSvg.trim().endsWith('</svg>');
  }

  @override
  void didUpdateWidget(SvgDiagramWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reprocess when the raw string actually changes.
    if (oldWidget.svgString != widget.svgString) {
      _cachedSvg = _cleanSvg(widget.svgString);
      final nowComplete = _cachedSvg.trim().endsWith('</svg>');
      // If we just became complete, trigger exactly one rebuild to show SVG.
      if (nowComplete != _isComplete) {
        _isComplete = nowComplete;
        // setState is safe here — didUpdateWidget is called during the build phase
        // but setState schedules a new frame, not an immediate rebuild.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        _isComplete = nowComplete;
      }
    }
  }

  /// Strip everything before <svg and normalize width/height to 100%
  String _cleanSvg(String raw) {
    String s = raw.trim();
    final svgIdx = s.indexOf('<svg');
    if (svgIdx < 0) return s; // not SVG at all, return as-is
    if (svgIdx > 0) s = s.substring(svgIdx);

    // Remove fixed pixel width/height so we control sizing via LayoutBuilder
    s = s.replaceFirstMapped(
      RegExp(
        r'''(<svg[^>]*?)\s+width=["']?[\d.%]+["']?''',
        caseSensitive: false,
      ),
      (m) => m.group(1)!,
    );
    s = s.replaceFirstMapped(
      RegExp(
        r'''(<svg[^>]*?)\s+height=["']?[\d.%]+["']?''',
        caseSensitive: false,
      ),
      (m) => m.group(1)!,
    );
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isComplete) {
      // Streaming in progress — show a subtle shimmer placeholder
      return Container(
        width: double.infinity,
        height: 80,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E3A5F).withOpacity(0.5)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Generating visual…',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    // SVG is complete — render it directly on chat background, no card
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Parse viewBox to derive aspect ratio
          double aspectRatio = 16 / 9;
          final vbMatch = RegExp(
            r'''viewBox=["']\s*([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s*["']''',
            caseSensitive: false,
          ).firstMatch(_cachedSvg);
          if (vbMatch != null) {
            final w = double.tryParse(vbMatch.group(3) ?? '') ?? 0;
            final h = double.tryParse(vbMatch.group(4) ?? '') ?? 0;
            if (w > 0 && h > 0) {
              aspectRatio = (w / h).clamp(0.3, 5.0);
            }
          }

          final availWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width - 32;
          final renderHeight = (availWidth / aspectRatio).clamp(180.0, 520.0);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        FullScreenSvgViewer(svgString: _cachedSvg),
                  ),
                );
              },
              child: SizedBox(
                width: double.infinity,
                height: renderHeight,
                child: SvgPicture.string(
                  _cachedSvg,
                  fit: BoxFit.contain,
                  width: availWidth,
                  height: renderHeight,
                  placeholderBuilder: (_) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FullScreenSvgViewer extends StatelessWidget {
  const FullScreenSvgViewer({required this.svgString, super.key});
  final String svgString;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, color: Colors.white),
            tooltip: 'Copy SVG code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: svgString));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SVG code copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          scaleEnabled: true,
          minScale: 0.5,
          maxScale: 10.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SvgPicture.string(
              svgString,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Document Artifacts & File Permission Helpers ──────────────────────────

String getHtmlTitle(String content) {
  final match = RegExp(
    r'<title>(.*?)</title>',
    caseSensitive: false,
  ).firstMatch(content);
  if (match != null) {
    final title = match.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'HTML Document';
}

String getDocxTitle(String content) {
  final titleMatch = RegExp(
    r'^title:\s*(.*)$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(content);
  if (titleMatch != null) {
    final title = titleMatch.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  final h1Match = RegExp(r'^#\s*(.*)$', multiLine: true).firstMatch(content);
  if (h1Match != null) {
    final title = h1Match.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'Word Document';
}

String getMdTitle(String content) {
  final titleMatch = RegExp(
    r'^title:\s*(.*)$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(content);
  if (titleMatch != null) {
    final title = titleMatch.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  final h1Match = RegExp(r'^#\s*(.*)$', multiLine: true).firstMatch(content);
  if (h1Match != null) {
    final title = h1Match.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'Markdown Document';
}

// ── Docx Artifact Widget ──

class DocxArtifactWidget extends StatelessWidget {
  final String docxContent;
  final String workspacePath;
  const DocxArtifactWidget({
    super.key,
    required this.docxContent,
    required this.workspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getDocxTitle(docxContent),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenDocxViewer(
                          docxContent: docxContent,
                          workspacePath: workspacePath,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF7B4E2E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'View File',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 150,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Text(
                docxContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
                maxLines: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full Screen Docx Viewer ──

class FullScreenDocxViewer extends StatefulWidget {
  final String docxContent;
  final String workspacePath;
  const FullScreenDocxViewer({
    super.key,
    required this.docxContent,
    required this.workspacePath,
  });

  @override
  State<FullScreenDocxViewer> createState() => _FullScreenDocxViewerState();
}

class _FullScreenDocxViewerState extends State<FullScreenDocxViewer> {
  bool _showPreview = true;
  bool _exporting = false;

  Future<void> _exportDocx() async {
    setState(() => _exporting = true);

    try {
      // Use docx_creator to generate the DOCX natively in Dart
      final elements = await MarkdownParser.parse(widget.docxContent);
      final doc = DocxBuiltDocument(elements: elements);
      final docxBytes = await DocxExporter().exportToBytes(doc);

      // Determine filename from content
      String filename = 'document.docx';
      final match = RegExp(
        r'^title:\s*(.*)$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(widget.docxContent);
      if (match != null) {
        final title =
            match.group(1)?.replaceAll(RegExp(r'[^a-zA-Z0-9\s-]'), '').trim() ??
            '';
        if (title.isNotEmpty) {
          filename = '${title.toLowerCase().replaceAll(' ', '_')}.docx';
        }
      }

      final String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Word Document',
        fileName: filename,
        bytes: Uint8List.fromList(docxBytes),
      );

      if (savePath == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(savePath);
        await file.writeAsBytes(docxBytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${savePath.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export document: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Word Preview' : 'Word Content'),
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: const Color(0xFF2D241C),
        actions: [
          if (_exporting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B4E2E),
                  ),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF2D241C)),
              onSelected: (value) {
                if (value == 'copy') {
                  Clipboard.setData(ClipboardData(text: widget.docxContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                } else if (value == 'preview') {
                  setState(() => _showPreview = !_showPreview);
                } else if (value == 'download') {
                  _exportDocx();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                PopupMenuItem(
                  value: 'preview',
                  child: Text(_showPreview ? 'Show Code' : 'Preview'),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: Text('Download (.docx)'),
                ),
              ],
            ),
        ],
      ),
      body: _showPreview
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5DDD3)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                   child: MarkdownBody(
                    data: widget.docxContent,
                    selectable: true,
                    builders: {
                      'table': ScrollableTableBuilder(),
                    },
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          h1: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF7B4E2E),
                            fontFamily: 'serif',
                          ),
                          h2: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7B4E2E),
                            fontFamily: 'serif',
                          ),
                          h3: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6C5946),
                          ),
                          p: const TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: Color(0xFF2D241C),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: const Color(0xFFFAF5EE),
                            border: const Border(
                              left: BorderSide(
                                color: Color(0xFF7B4E2E),
                                width: 4.0,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          tableBorder: TableBorder.all(
                            color: const Color(0xFFE5DDD3),
                          ),
                          tableCellsPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          tableHead: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7B4E2E),
                          ),
                        ),
                  ),
                ),
              ),
            )
          : Container(
              color: const Color(0xFF1E1E1E),
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    widget.docxContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Md Artifact Widget ──

class MdArtifactWidget extends StatelessWidget {
  final String mdContent;
  final String workspacePath;
  const MdArtifactWidget({
    super.key,
    required this.mdContent,
    required this.workspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getMdTitle(mdContent),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenMdViewer(
                          mdContent: mdContent,
                          workspacePath: workspacePath,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF7B4E2E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'View File',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 150,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Text(
                mdContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
                maxLines: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full Screen Md Viewer ──

class FullScreenMdViewer extends StatefulWidget {
  final String mdContent;
  final String workspacePath;
  const FullScreenMdViewer({
    super.key,
    required this.mdContent,
    required this.workspacePath,
  });

  @override
  State<FullScreenMdViewer> createState() => _FullScreenMdViewerState();
}

class _FullScreenMdViewerState extends State<FullScreenMdViewer> {
  bool _showPreview = true;
  bool _saving = false;

  Future<void> _saveMdFile() async {
    setState(() => _saving = true);

    try {
      String filename = 'document.md';
      final match = RegExp(
        r'^title:\s*(.*)$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(widget.mdContent);
      if (match != null) {
        final title =
            match.group(1)?.replaceAll(RegExp(r'[^a-zA-Z0-9\s-]'), '').trim() ??
            '';
        if (title.isNotEmpty) {
          filename = '${title.toLowerCase().replaceAll(' ', '_')}.md';
        }
      }

      final bytes = Uint8List.fromList(utf8.encode(widget.mdContent));
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Markdown File',
        fileName: filename,
        bytes: bytes,
      );

      if (path == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${path.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Markdown Preview' : 'Markdown Code'),
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: const Color(0xFF2D241C),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B4E2E),
                  ),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF2D241C)),
              onSelected: (value) {
                if (value == 'copy') {
                  Clipboard.setData(ClipboardData(text: widget.mdContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                } else if (value == 'preview') {
                  setState(() => _showPreview = !_showPreview);
                } else if (value == 'download') {
                  _saveMdFile();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                PopupMenuItem(
                  value: 'preview',
                  child: Text(_showPreview ? 'Show Code' : 'Preview'),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: Text('Download (.md)'),
                ),
              ],
            ),
        ],
      ),
      body: _showPreview
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE7D8C4)),
                  ),
                  child: MarkdownBody(
                    data: widget.mdContent,
                    selectable: true,
                    builders: {
                      'table': ScrollableTableBuilder(),
                    },
                  ),
                ),
              ),
            )
          : Container(
              color: const Color(0xFF1E1E1E),
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    widget.mdContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

String _resolvePath(String p, String workspace) {
  if (p.startsWith('/') || p.startsWith('~') || p.startsWith('http')) return p;
  final ws = workspace.endsWith('/') ? workspace : '$workspace/';
  return '$ws$p';
}

dynamic _resolveToolPathValue(dynamic value, String workspace, [String? key]) {
  const pathKeys = {
    'path',
    'file',
    'directory',
    'dir',
    'dir_path',
    'src',
    'dest',
    'path_a',
    'path_b',
    'target',
    'output_dir',
  };
  if (value is Map<String, dynamic>) {
    return value.map(
      (k, v) => MapEntry(k, _resolveToolPathValue(v, workspace, k)),
    );
  }
  if (value is List) {
    return value
        .map((item) => _resolveToolPathValue(item, workspace, key))
        .toList();
  }
  if (value is String && key != null && pathKeys.contains(key)) {
    return _resolvePath(value, workspace);
  }
  return value;
}

void _resolveToolPaths(Map<String, dynamic> params, String workspace) {
  final resolved =
      _resolveToolPathValue(params, workspace) as Map<String, dynamic>;
  params
    ..clear()
    ..addAll(resolved);
}

Future<String> _handleMemoryTool(String action, String content) async {
  try {
    final docDir = await getApplicationDocumentsDirectory();
    final memoryFile = File('${docDir.path}/nexon_memory.json');

    String currentMemory = '';
    if (await memoryFile.exists()) {
      currentMemory = await memoryFile.readAsString();
    }

    if (action == 'read') {
      return currentMemory.isEmpty ? 'Memory is empty.' : currentMemory;
    } else if (action == 'append') {
      final newMemory = currentMemory.isEmpty
          ? content.trim()
          : '$currentMemory\n${content.trim()}';
      if (utf8.encode(newMemory).length > 10240) {
        return 'Error: Appending this would exceed the 10KB memory limit. Use replace action instead.';
      }
      await memoryFile.writeAsString(newMemory);
      return 'Appended successfully. Current memory size: ${utf8.encode(newMemory).length} bytes.';
    } else if (action == 'replace') {
      if (utf8.encode(content).length > 10240) {
        return 'Error: New memory exceeds the 10KB memory limit.';
      }
      await memoryFile.writeAsString(content.trim());
      return 'Replaced successfully. Current memory size: ${utf8.encode(content).length} bytes.';
    } else if (action == 'clear') {
      await memoryFile.writeAsString('');
      return 'Memory cleared.';
    } else {
      return 'Error: Unknown action "$action". Valid actions are read, append, replace, clear.';
    }
  } catch (e) {
    return 'Error interacting with memory: $e';
  }
}

class SimpleSemaphore {
  int _maxConcurrency;
  int _running = 0;
  final List<Completer<void>> _queue = [];

  SimpleSemaphore(this._maxConcurrency);

  int get maxConcurrency => _maxConcurrency;

  set maxConcurrency(int value) {
    if (value == _maxConcurrency) return;
    _maxConcurrency = value;
    _triggerQueue();
  }

  void _triggerQueue() {
    while (_queue.isNotEmpty && _running < _maxConcurrency) {
      _running++;
      final completer = _queue.removeAt(0);
      completer.complete();
    }
  }

  Future<void> acquire() async {
    if (_running < _maxConcurrency) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final completer = _queue.removeAt(0);
      completer.complete();
    } else {
      _running--;
    }
  }

  Future<T> run<T>(Future<T> Function() task) async {
    await acquire();
    try {
      return await task();
    } finally {
      release();
    }
  }
}
