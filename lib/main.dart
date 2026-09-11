import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/widgets/diff_viewer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nexon/services/update_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:nexon/services/voice/live_voice_engine.dart';
import 'package:nexon/widgets/live_voice_overlay.dart';
import 'package:path_provider/path_provider.dart';
import 'package:docx_creator/docx_creator.dart' hide PdfDocument;

import 'package:nexon/widgets/nexon_chart.dart';
import 'package:nexon/services/drive_sync_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nexon/screens/onboarding_screen.dart';
import 'package:nexon/screens/kaggle_scripts.dart';
import 'package:nexon/services/deep_research/deep_research_bridge_client.dart';
import 'package:nexon/services/deep_research/deep_research_helpers.dart';
import 'package:nexon/services/deep_research/deep_research_prompts.dart';
import 'package:nexon/services/slash_command/slash_command_service.dart';
import 'package:nexon/services/context_compression/context_compression_service.dart';
import 'package:nexon/services/system_prompt_engine.dart';
import 'package:nexon/services/system_prompts.dart';
import 'package:nexon/services/termux_bridge/native_tools_service.dart';
import 'package:nexon/services/checkpoint/checkpoint_service.dart';
import 'package:nexon/services/workspace/workspace_service.dart';
import 'package:nexon/services/termux_bridge/termux_bridge_service.dart';
import 'package:nexon/services/termux_bridge/bridge_protocol.dart';
import 'package:uuid/uuid.dart';

// Modules extracted from this file. Imported so the symbols are visible
// here, and re-exported so the widget libraries (which import main.dart)
// can reach them.
import 'package:nexon/widgets/chat_history_panel.dart';
import 'package:nexon/widgets/chat_surface.dart';
import 'package:nexon/widgets/chat_header.dart';
import 'package:nexon/widgets/thought_block.dart';
import 'package:nexon/widgets/mcp_tool_block.dart';
import 'package:nexon/widgets/code_widgets.dart';
import 'package:nexon/utils/content_parser.dart';
import 'package:nexon/widgets/chat_media_widgets.dart';
import 'package:nexon/widgets/message_bubble.dart';
import 'package:nexon/widgets/streaming_widgets.dart';
import 'package:nexon/widgets/quiz_sheet.dart';
import 'package:nexon/widgets/composer.dart';
import 'package:nexon/utils/model_capabilities.dart';
import 'package:nexon/widgets/media_and_model_sheet.dart';
import 'package:nexon/widgets/provider_sheets.dart';
import 'package:nexon/widgets/common_widgets.dart';
import 'package:nexon/services/llm/chat_client.dart';
import 'package:nexon/data/models/provider_models.dart';
import 'package:nexon/widgets/research_widgets.dart';
import 'package:nexon/widgets/artifact_widgets.dart';
import 'package:nexon/services/deep_research/deep_research_utils.dart';
import 'package:nexon/utils/code_helpers.dart';
import 'package:nexon/widgets/research_agent_avatars.dart';
import 'package:nexon/screens/kaggle_setup_screen.dart';

export 'package:nexon/widgets/chat_history_panel.dart';
export 'package:nexon/widgets/chat_surface.dart';
export 'package:nexon/widgets/chat_header.dart';
export 'package:nexon/widgets/thought_block.dart';
export 'package:nexon/widgets/mcp_tool_block.dart';
export 'package:nexon/widgets/code_widgets.dart';
export 'package:nexon/utils/content_parser.dart';
export 'package:nexon/widgets/chat_media_widgets.dart';
export 'package:nexon/widgets/message_bubble.dart';
export 'package:nexon/widgets/streaming_widgets.dart';
export 'package:nexon/widgets/quiz_sheet.dart';
export 'package:nexon/widgets/composer.dart';
export 'package:nexon/utils/model_capabilities.dart';
export 'package:nexon/widgets/media_and_model_sheet.dart';
export 'package:nexon/widgets/provider_sheets.dart';
export 'package:nexon/widgets/common_widgets.dart';
export 'package:nexon/services/llm/chat_client.dart';
export 'package:nexon/data/models/provider_models.dart';
export 'package:nexon/widgets/research_widgets.dart';
export 'package:nexon/widgets/artifact_widgets.dart';
export 'package:nexon/services/deep_research/deep_research_utils.dart';
export 'package:nexon/utils/code_helpers.dart';
export 'package:nexon/widgets/research_agent_avatars.dart';
export 'package:nexon/screens/kaggle_setup_screen.dart';


/// Helper class for Text-To-Speech audio playback of model outputs.
import 'package:nexon/services/tts_service.dart';
export 'package:nexon/services/tts_service.dart';

export 'package:nexon/widgets/glass_widgets.dart';
export 'package:nexon/widgets/liquid_glass_widgets.dart';

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
      builder: (context, child) {
        final data = MediaQuery.of(context);
        final scale = data.textScaler.scale(1.0);
        return MediaQuery(
          data: scale > 1.2
              ? data.copyWith(textScaler: const TextScaler.linear(1.2))
              : data,
          child: child ?? const SizedBox.shrink(),
        );
      },
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

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> with WidgetsBindingObserver {
  static final _secureStorage = const FlutterSecureStorage();
  static const _settingsKey = 'provider_settings_v1';
  static const _selectedProviderKey = 'selected_provider_id';
  static const _customProvidersKey = 'custom_providers_v1';

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatClient = ChatClient();

  SharedPreferences? _prefs;
  Map<String, ProviderSettings> _settings = {};
  final Map<String, List<String>> _modelCache = {};
  List<ProviderDefinition> _customProviders = [];
  var _selectedProviderId = providerCatalog.first.id;
  final Set<String> _sendingSessionIds = {};
  var _isFetchingModels = false;
  SearchSettings _searchSettings = SearchSettings.defaults();
  bool _agenticEnabled = true;
  bool _artifactsEnabled = false;
  bool _svgVisualsEnabled = false;
  // Shell command permission: 'ask', 'session', 'always', 'never'
  String _shellPermission = 'ask';
  // Per-session always-allow flag (reset when app restarts)
  bool _shellSessionAllow = false;
  // Approved two-segment command prefixes (e.g. 'flutter test'), persisted.
  final Set<String> _shellPrefixAllowed = {};
  String _agenticWorkspace = '/data/data/com.termux/files/home';
  String _customMcpUrl = '';
  final Map<String, StreamSubscription<String>> _activeSubscriptions = {};
  final Map<String, Completer<void>> _activeCompleters = {};
  final HttpClient _mcpHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);
  bool _deepResearchEnabled = false;
  bool _studyModeEnabled = false;
  String _userName = '';
  String _promptSig = '';
  int _promptUseCount = 0;

  /// System prompt engine — assembles the XML-tagged prompt from base + features.
  final SystemPromptEngine _promptEngine = SystemPromptEngine();

  /// User-configured token budget for writer-phase evidence (set in settings).
  int _writerContextBudget = 32000;
  static const int maxConcurrentFetchCalls = 6;
  // Bounded by fetch limit since backend is now decoupled and parallelised
  static const int maxConcurrentIngestCalls = 6;
  final SimpleSemaphore _ingestSemaphore = SimpleSemaphore(
    maxConcurrentIngestCalls,
  );
  final Map<String, Map<String, dynamic>> _runUrlCache = {};
  CheckpointService? _checkpointService;

  DeepResearchBridgeClient? _cachedBridge;
  String _cachedBridgeUrl = '';
  DeepResearchBridgeClient get _deepResearchBridge {
    final url = _customMcpUrl.isNotEmpty
        ? _customMcpUrl
        : 'http://127.0.0.1:8390/mcp';
    if (_cachedBridge != null && _cachedBridgeUrl == url) return _cachedBridge!;
    _cachedBridge = DeepResearchBridgeClient(endpoint: url);
    _cachedBridgeUrl = url;
    return _cachedBridge!;
  }

  String _normalizeQueryOrUrl(String input) {
    if (input.startsWith('http://') || input.startsWith('https://')) {
      var s = input.toLowerCase();
      if (s.endsWith('/') && s.length > 12) s = s.substring(0, s.length - 1);
      return s;
    }
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\-\.\:\/]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<int> _getSystemAvailableRamBytes() async {
    final endpoint = _customMcpUrl.isNotEmpty
        ? _customMcpUrl
        : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 4));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(
        jsonEncode({'method': 'system_ram_headroom', 'params': {}}),
      );
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
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

  late final LiveVoiceEngine _liveVoiceEngine = LiveVoiceEngine();
  String? _selectedVoiceName;

  void _openLiveVoiceMode() {
    // Voice Mode only works in Normal Mode (no other mode/feature active)
    if (_agenticEnabled || _searchSettings.enabled || _deepResearchEnabled ||
        _studyModeEnabled || _svgVisualsEnabled || _artifactsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice Mode requires Normal Mode. Disable all other features first.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Live Voice Mode',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return PopScope(
          canPop: true,
          onPopInvoked: (didPop) {
            if (didPop) _liveVoiceEngine.interrupt();
          },
          child: LiveVoiceOverlay(
            engine: _liveVoiceEngine,
            onSendPrompt: (prompt) {
              _sendMessage(promptText: prompt);
            },
            onClose: () {
              _liveVoiceEngine.interrupt();
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  String _toolStatus = '';

  List<TodoItem> _activeTodos = [];
  bool _todoListVisible = false;


  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  int? _editingMessageIndex;
  int _historyLimit = 50;
  bool _isLoadingMoreHistory = false;
  DateTime _lastDriveSync = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _loadMoreHistory() async {
    if (_isLoadingMoreHistory) return;
    setState(() {
      _isLoadingMoreHistory = true;
    });

    var added = 0;
    try {
      // 1) Local full-history backup written by _saveSessions when the
      //    prefs payload exceeds the size cap. Works offline — no Drive.
      final backupFile = await _sessionBackupPrefsFile();
      if (await backupFile.exists()) {
        final raw = await backupFile.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          final backupSessions = decoded
              .map((s) => ChatSession.fromJson(s as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              added = _mergeLoadedSessions(backupSessions);
            });
          }
        }
      }

      // 2) Fall back to Google Drive when the local backup added nothing.
      if (added == 0) {
        final result = await DriveSyncService.restoreFromDriveDetailed();
        if (result.success) {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('chat_sessions_v1');
          if (raw != null && raw.trim().isNotEmpty) {
            final decoded = jsonDecode(raw) as List<dynamic>;
            final driveSessions = decoded
                .map((s) => ChatSession.fromJson(s as Map<String, dynamic>))
                .toList();
            if (mounted) {
              setState(() {
                added = _mergeLoadedSessions(driveSessions);
              });
            }
          }
        }
      }

      if (added > 0) await _saveSessions();
    } catch (e) {
      debugPrint('[HistoryPagination] Error loading more history: $e');
    } finally {
      if (mounted) {
        setState(() {
          _historyLimit += 25;
          _isLoadingMoreHistory = false;
        });
      }
    }
  }

  /// Merges [incoming] sessions into [_sessions]. If an ID already exists,
  /// preserves whichever copy contains more messages or a newer timestamp.
  int _mergeLoadedSessions(List<ChatSession> incoming) {
    if (incoming.isEmpty) return 0;
    int added = 0;
    final Map<String, ChatSession> map = {
      for (final s in _sessions) s.id: s,
    };

    for (final remote in incoming) {
      if (!map.containsKey(remote.id)) {
        map[remote.id] = remote;
        added++;
      } else {
        final local = map[remote.id]!;
        final localMsgs = local.messages.length;
        final remoteMsgs = remote.messages.length;
        final localTime = local.updatedAt;
        final remoteTime = remote.updatedAt;

        if (remoteMsgs > localMsgs || (remoteMsgs == localMsgs && remoteTime.isAfter(localTime))) {
          map[remote.id] = remote;
          added++;
        }
      }
    }

    if (added > 0) {
      _sessions = map.values.toList();
      _sessions.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    }
    return added;
  }

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
    _agenticEnabled = false;
    _deepResearchEnabled = false;
    _studyModeEnabled = false;
    _searchSettings = SearchSettings(
      enabled: false,
      provider: _searchSettings.provider,
      apiKey: _searchSettings.apiKey,
      fallbackApiKeys: _searchSettings.fallbackApiKeys,
      googleCx: _searchSettings.googleCx,
    );
    _promptSig = '';
    _promptUseCount = 0;
    _clearWorkspaceBucket();
  }

  Future<void> _clearWorkspaceBucket() async {
    try {
      final client = HttpClient();
      final req = await client
          .postUrl(Uri.parse('http://127.0.0.1:8390/workspace/clear'))
          .timeout(const Duration(seconds: 5));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode('{}'));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      await resp.drain<void>();
      client.close(force: true);
    } catch (_) {
      // Bridge offline at startup — upload-time session check clears instead.
    }
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_sessions_v1');
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final loadedSessions = decoded
            .map((s) => ChatSession.fromJson(s as Map<String, dynamic>))
            .toList();
        setState(() {
          _sessions = loadedSessions;

          // Check if the most recent session is already an empty new/welcome chat
          bool hasEmptySession = false;
          if (_sessions.isNotEmpty) {
            final first = _sessions.first;
            final userMsgs = first.messages.where(
              (m) => m.role == MessageRole.user,
            );
            if (userMsgs.isEmpty &&
                (first.title == 'New Chat' || first.title == 'Welcome Chat')) {
              _activeSessionId = first.id;
              _agenticEnabled = false;
              _deepResearchEnabled = false;
              _studyModeEnabled = false;
              _promptSig = '';
              _promptUseCount = 0;
              _clearWorkspaceBucket();
              hasEmptySession = true;
            }
          }

          if (!hasEmptySession) {
            // Create a new fresh chat session on startup
            final newId = DateTime.now().millisecondsSinceEpoch.toString();
            final newSession = ChatSession(
              id: newId,
              title: 'New Chat',
              messages: const [],
              providerId: _selectedProviderId,
              model: _activeModel,
            );
            _sessions.insert(0, newSession);
            _activeSessionId = newId;
            _agenticEnabled = false;
            _deepResearchEnabled = false;
            _studyModeEnabled = false;
            _promptSig = '';
            _promptUseCount = 0;
            _clearWorkspaceBucket();
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
    final allJson = jsonEncode(serialized);
    final maxPrefsBytes = 1500 * 1024;
    if (utf8.encode(allJson).length <= maxPrefsBytes) {
      await prefs.setString('chat_sessions_v1', allJson);
    } else {
      final trimmed = _sessions.take(20).map((s) => s.toJson()).toList();
      await prefs.setString('chat_sessions_v1', jsonEncode(trimmed));
      try {
        final backupFile = await _sessionBackupPrefsFile();
        if (!await backupFile.parent.exists()) {
          await backupFile.parent.create(recursive: true);
        }
        final tmp = File('${backupFile.path}.tmp');
        await tmp.writeAsString(allJson, flush: true);
        await tmp.rename(backupFile.path);
      } catch (e) {
        debugPrint('Session backup write failed: $e');
      }
    }
    if (_activeSessionId != null) {
      await prefs.setString('active_session_id_v1', _activeSessionId!);
    }

    // Fire-and-forget auto-sync to Google Drive, throttled so we don't
    // serialize + upload the full history on every single chat turn.
    final nowSync = DateTime.now();
    if (nowSync.difference(_lastDriveSync).inSeconds >= 15) {
      _lastDriveSync = nowSync;
      DriveSyncService.syncToDrive(_sessions);
    }
  }

  Future<String> _expandHomePath(String path) async {
    if (path == '~') {
      return Platform.environment['HOME'] ??
          '/data/data/com.termux/files/home';
    }
    if (path.startsWith('~/')) {
      final home =
          Platform.environment['HOME'] ?? '/data/data/com.termux/files/home';
      return '$home/${path.substring(2)}';
    }
    return path;
  }

  String _normalizeFsPath(String input) {
    final normalized = Uri.file(input).normalizePath().toFilePath();
    if (normalized.length > 1 && normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<Directory> _chooseWritableNexonRoot() async {
    final expandedWorkspace = await _expandHomePath(_agenticWorkspace);
    final workspaceRoot = Directory(
      '${expandedWorkspace.replaceAll(RegExp(r'/+$'), '')}/.nexon',
    );
    try {
      await WorkspaceService.ensureWorkspaceSupportDirs(expandedWorkspace);
      final probe = File('${workspaceRoot.path}/.write_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return workspaceRoot;
    } catch (_) {
      return WorkspaceService.ensureFallbackSupportDirs();
    }
  }

  Future<void> _ensureLocalSupportDirs() async {
    final root = await _chooseWritableNexonRoot();
    _checkpointService ??= CheckpointService(
      repository: FileCheckpointRepository(
        directoryPath: '${root.path}/checkpoints',
      ),
    );
  }

  Future<File> _sessionBackupPrefsFile() async {
    final root = await _chooseWritableNexonRoot();
    return File('${root.path}/sessions/prefs_backup.json');
  }

  Future<void> _resetDeepResearch() async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await _deepResearchBridge.reset();
        return;
      } catch (e) {
        if (attempt == 1) {
          throw StateError('Deep Research bridge reset failed: $e');
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _updateDeepResearchPhase({
    required String stageId,
    required String phaseTitle,
    String summary = '',
    required List<dynamic> facts,
    required List<dynamic> findings,
    required List<dynamic> skippedPdfs,
    required List<dynamic> failedFetches,
    String status = 'running',
  }) async {
    try {
      await _deepResearchBridge.updatePhase(
        stageId: stageId,
        phaseTitle: phaseTitle,
        summary: summary,
        facts: facts,
        findings: findings,
        skippedPdfs: skippedPdfs,
        failedFetches: failedFetches,
        status: status,
      );
    } catch (e) {
      throw StateError('Deep Research bridge phase update failed: $e');
    }
  }

  /// Normalize batch evidence with per-source attribution.
  /// Unlike single-source normalization, this preserves the source field from
  /// each fact/finding record instead of overwriting with a single URL.
  Map<String, dynamic> _normalizeBatchEvidence(
    Map<String, dynamic>? parsed,
    List<String> expectedSources,
  ) {
    final facts = <Map<String, dynamic>>[];
    final findings = <Map<String, dynamic>>[];
    if (parsed == null) {
      return {'facts': facts, 'findings': findings};
    }
    final rawFacts = parsed['facts'] is List ? parsed['facts'] as List : const [];
    final rawFindings =
        parsed['findings'] is List ? parsed['findings'] as List : const [];
    
    String _normUrl(String u) {
      var s = u.trim().toLowerCase();
      if (s.endsWith('/') && s.length > 8) s = s.substring(0, s.length - 1);
      s = s.replaceAll('http://', 'https://');
      return s;
    }
    String _matchSource(String url) {
      final norm = _normUrl(url);
      for (final expected in expectedSources) {
        if (_normUrl(expected) == norm) return expected;
      }
      return expectedSources.first;
    }
    for (final item in rawFacts) {
      if (item is! Map) continue;
      final sourceUrl = item['source']?.toString() ?? '';
      facts.add({
        'metric': item['metric']?.toString() ?? '',
        'subject': item['subject']?.toString() ?? '',
        'value': item['value']?.toString() ?? '',
        'date': item['date']?.toString() ?? '',
        'source': _matchSource(sourceUrl),
        'confidence': item['confidence']?.toString() ?? 'high',
      });
    }
    for (final item in rawFindings) {
      if (item is! Map) continue;
      final sourceUrl = item['source']?.toString() ?? '';
      findings.add({
        'text': item['text']?.toString() ?? '',
        'source': _matchSource(sourceUrl),
        'confidence': item['confidence']?.toString() ?? 'high',
      });
    }
    return {'facts': facts, 'findings': findings};
  }

  /// IMPROVEMENT: LLM retry wrapper with exponential backoff.
  /// Retries failed LLM calls up to [maxRetries] times with increasing delay.
  /// Prevents silent evidence loss when the API rate-limits or times out.
  Future<String> _retryLlmCall({
    required List<ChatMessage> messages,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
    int maxRetries = 2,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _chatClient.sendChat(
          provider: provider,
          settings: settings,
          model: model,
          messages: messages,
          studyModeEnabled: _studyModeEnabled,
        );
        if (response.trim().isNotEmpty) return response;
      } catch (e) {
        if (attempt == maxRetries) rethrow;
        final delay = Duration(seconds: (attempt + 1) * 2);
        debugPrint(
          'LLM call failed (attempt ${attempt + 1}/${maxRetries + 1}), '
          'retrying in ${delay.inSeconds}s: $e',
        );
        await Future.delayed(delay);
      }
    }
    return '';
  }

  /// Batch summarizer: extract facts/findings from multiple sources in ONE LLM call.
  /// This cuts API usage by ~80% compared to per-URL summarization.
  Future<Map<String, dynamic>> _summarizeBatchInline({
    required Map<String, String> sources,
    required String query,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    if (sources.isEmpty) return {'facts': [], 'findings': []};

    // Build combined content with source markers
    final StringBuffer combinedContent = StringBuffer();
    combinedContent.writeln('Research Query: $query');
    combinedContent.writeln();
    for (final entry in sources.entries) {
      combinedContent.writeln('=== SOURCE: ${entry.key} ===');
      final content = entry.value;
      if (content.length > 8000) {
        combinedContent.writeln(content.substring(0, 6000));
        combinedContent.writeln('\n...[${content.length - 7000} chars omitted]...\n');
        combinedContent.writeln(content.substring(content.length - 1000));
      } else {
        combinedContent.writeln(content);
      }
      combinedContent.writeln();
    }

    final summarizerMessages = [
      ChatMessage(
        role: MessageRole.system,
        text: DeepResearchPrompts.summarizerSystemPrompt +
            '\n\nYou are summarizing MULTIPLE sources. ' +
            'Each source is marked with === SOURCE: <url> ===. ' +
            'Extract facts and findings from ALL sources. ' +
            'Tag each fact and finding with its source URL. ' +
            'Deduplicate across sources — if two sources report the same fact, ' +
            'keep only one with the more authoritative source.',
      ),
      ChatMessage(
        role: MessageRole.user,
        text: combinedContent.toString(),
      ),
    ];

    try {
      final responseText = await _chatClient.sendChat(
        provider: provider,
        settings: settings,
        model: model,
        messages: summarizerMessages,
        studyModeEnabled: _studyModeEnabled,
      );
      final cleanResp = responseText
          .replaceAll(RegExp(r'```json'), '')
          .replaceAll('```', '')
          .trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleanResp);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        // Parse evidence with per-source attribution instead of tagging all
        // records with the first source URL.
        return _normalizeBatchEvidence(parsed, sources.keys.toList());
      }
    } catch (e) {
      debugPrint('Batch summarization failed: $e');
    }
    return {
      'facts': <Map<String, dynamic>>[],
      'findings': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _exportDeepResearchForWriter(
    int maxEvidenceTokens,
  ) {
    return _deepResearchBridge.exportForWriter(
      maxEvidenceTokens: maxEvidenceTokens.clamp(1, 200000) as int,
    );
  }

  String _deepResearchNow() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${now.toIso8601String()} ${now.timeZoneName} (UTC$sign$hours:$minutes)';
  }

  String _buildDeepResearchPhaseSummary({
    required String phaseTitle,
    required String stepContent,
    required List<dynamic> facts,
    required List<dynamic> findings,
    required List<dynamic> skippedPdfs,
    required List<dynamic> failedFetches,
  }) {
    final items = <String>[
      'Phase: $phaseTitle.',
      '${facts.length} facts and ${findings.length} findings were extracted.',
    ];
    for (final fact in facts.take(3)) {
      if (fact is Map) {
        final subject = fact['subject']?.toString().trim() ?? '';
        final metric = fact['metric']?.toString().trim() ?? '';
        final value = fact['value']?.toString().trim() ?? '';
        if (subject.isNotEmpty || metric.isNotEmpty || value.isNotEmpty) {
          items.add('$subject $metric: $value.'.trim());
        }
      }
    }
    for (final finding in findings.take(2)) {
      if (finding is Map) {
        final text = finding['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) items.add(text);
      }
    }
    if (skippedPdfs.isNotEmpty)
      items.add('${skippedPdfs.length} PDF source(s) skipped.');
    if (failedFetches.isNotEmpty)
      items.add('${failedFetches.length} source fetch(es) failed.');
    if (items.length == 2 && stepContent.trim().isNotEmpty) {
      final cleaned = stepContent
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.isNotEmpty) {
        items.add(cleaned.substring(0, cleaned.length.clamp(0, 800).toInt()));
      }
    }
    return items.join(' ');
  }

  List<String> _evidenceSourceUrls(String tempJsonContent) {
    try {
      final decoded = jsonDecode(tempJsonContent);
      if (decoded is! List) return const [];
      final urls = <String>{};
      for (final phase in decoded) {
        if (phase is! Map) continue;
        for (final key in ['facts', 'findings']) {
          final records = phase[key];
          if (records is! List) continue;
          for (final record in records) {
            if (record is! Map) continue;
            final source = record['source']?.toString().trim() ?? '';
            if (Uri.tryParse(source)?.hasScheme == true) urls.add(source);
          }
        }
      }
      return urls.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  String _unwrapMarkdownArtifact(String text) {
    final match = RegExp(
      r'```(?:markdown|md)\s*\n([\s\S]*?)\n```',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final before = text.substring(0, match.start).trim();
      final after = text.substring(match.end).trim();
      final content = match.group(1)?.trim() ?? '';
      if (before.isEmpty && after.isEmpty) return content;
      return '${before.isNotEmpty ? '$before\n\n' : ''}$content${after.isNotEmpty ? '\n\n$after' : ''}';
    }
    return text.trim();
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

      // Turn off agentic file access, deep research, and study modes when switching sessions
      _agenticEnabled = false;
      _deepResearchEnabled = false;
      _studyModeEnabled = false;
      _searchSettings = SearchSettings(
        enabled: false,
        provider: _searchSettings.provider,
        apiKey: _searchSettings.apiKey,
        fallbackApiKeys: _searchSettings.fallbackApiKeys,
        googleCx: _searchSettings.googleCx,
      );
      _promptSig = '';
      _promptUseCount = 0;
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

  ProviderDefinition get _provider => _resolveProvider(_selectedProviderId);

  List<ProviderDefinition> get _allProviders => [
        ...providerCatalog,
        ..._customProviders,
      ];

  ProviderDefinition _resolveProvider(String id) => _allProviders.firstWhere(
        (item) => item.id == id,
        orElse: () => providerCatalog.first,
      );

  static bool _isCustomProviderId(String id) =>
      id == 'custom' || id.startsWith('custom_');

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
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_handleMessageTextChanged);
    _loadSettings();
    NexonTts.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _autoBackup();
    }
  }

  Future<void> _autoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupEnabled = prefs.getBool('google_drive_backup_enabled') ?? false;
      if (!backupEnabled) return;

      // Prefer the in-memory full session list to avoid sending truncated history.
      // Fall back to reading disk backup or SharedPreferences if in-memory is empty.
      List<dynamic> sessionsToBackup = _sessions;
      if (sessionsToBackup.isEmpty) {
        try {
          final backupFile = await _sessionBackupPrefsFile();
          if (await backupFile.exists()) {
            final raw = await backupFile.readAsString();
            if (raw.trim().isNotEmpty) {
              sessionsToBackup = jsonDecode(raw) as List<dynamic>;
            }
          }
        } catch (_) {}
      }

      if (sessionsToBackup.isEmpty) {
        final rawSessions = prefs.getString('chat_sessions_v1');
        if (rawSessions != null && rawSessions.trim().isNotEmpty) {
          sessionsToBackup = jsonDecode(rawSessions) as List<dynamic>;
        }
      }

      if (sessionsToBackup.isNotEmpty) {
        await DriveSyncService.syncToDrive(sessionsToBackup, force: true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_handleMessageTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _mcpHttpClient.close();
    super.dispose();
  }

  // Large paste handling: very large pastes can be truncated by the IME,
  // so we detect big single-insertion jumps on the message controller,
  // revert them, and let the user insert the full clipboard text or
  // attach it as a file instead.
  static const int _largePasteThreshold = 1000;
  String _lastMessageText = '';
  bool _suppressPasteDetection = false;
  bool _pasteChoiceDialogOpen = false;

  void _handleMessageTextChanged() {
    final newText = _messageController.text;
    final oldText = _lastMessageText;
    _lastMessageText = newText;
    if (_suppressPasteDetection || _pasteChoiceDialogOpen) return;
    if (newText.length - oldText.length < _largePasteThreshold) return;

    // Locate the inserted span via common prefix/suffix comparison.
    final minLen = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    var prefix = 0;
    while (prefix < minLen &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }
    final inserted = newText.substring(prefix, newText.length - suffix);
    if (inserted.length < _largePasteThreshold) return;

    // Revert the field while the user decides how to handle the paste.
    final before = oldText.substring(0, prefix);
    final after = oldText.substring(oldText.length - suffix);
    _suppressPasteDetection = true;
    _messageController.text = oldText;
    _suppressPasteDetection = false;
    _showLargePasteChoiceDialog(before, after, inserted);
  }

  Future<void> _showLargePasteChoiceDialog(
    String before,
    String after,
    String inserted,
  ) async {
    _pasteChoiceDialogOpen = true;
    String clipboardText = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      clipboardText = data?.text ?? '';
    } catch (_) {
      clipboardText = '';
    }
    // The IME may have truncated the paste; prefer the full clipboard
    // content when it matches what actually reached the field.
    final payload = (clipboardText.length > inserted.length &&
            clipboardText.startsWith(inserted))
        ? clipboardText
        : inserted;
    if (!mounted) {
      _pasteChoiceDialogOpen = false;
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Large Paste Detected',
          style: TextStyle(
            color: Color(0xFF7B4E2E),
            fontWeight: FontWeight.bold,
            fontFamily: 'serif',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${payload.length} characters. Paste as text or attach as file?',
              style: const TextStyle(color: Color(0xFF2D241C), fontSize: 14),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.text_fields_rounded,
                color: Color(0xFF2D241C),
              ),
              title: const Text(
                'Paste as Text',
                style: TextStyle(color: Color(0xFF2D241C)),
              ),
              onTap: () => Navigator.of(ctx).pop('text'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.attach_file_rounded,
                color: Color(0xFF2D241C),
              ),
              title: const Text(
                'Attach as File',
                style: TextStyle(color: Color(0xFF2D241C)),
              ),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
          ],
        ),
      ),
    );
    _pasteChoiceDialogOpen = false;
    if (choice == 'text') {
      final full = before + payload + after;
      _suppressPasteDetection = true;
      _messageController.value = TextEditingValue(
        text: full,
        selection: TextSelection.collapsed(offset: full.length),
      );
      _suppressPasteDetection = false;
    } else if (choice == 'file') {
      final file = AttachedFile(
        name: 'pasted_${DateTime.now().millisecondsSinceEpoch}.txt',
        content: payload,
      );
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('Pasted text attached as file')),
        );
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    final selected = prefs.getString(_selectedProviderKey);
    final customRaw = prefs.getString(_customProvidersKey);
    final searchRaw = prefs.getString('search_settings_v1');
    final nextSettings = <String, ProviderSettings>{};

    SearchSettings loadedSearchSettings = SearchSettings.defaults();
    if (searchRaw != null && searchRaw.trim().isNotEmpty) {
      try {
        loadedSearchSettings = SearchSettings.fromJson(
          jsonDecode(searchRaw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    String? savedSearchKey;
    List<String> savedFallbackKeys = const [];
    try {
      savedSearchKey = await _secureStorage.read(key: 'search_api_key');
      final savedFallbacks = await _secureStorage.read(key: 'search_fallback_keys');
      if (savedFallbacks != null && savedFallbacks.trim().isNotEmpty) {
        savedFallbackKeys = (jsonDecode(savedFallbacks) as List).map((e) => e.toString()).toList();
      }
    } catch (_) {}
    loadedSearchSettings = SearchSettings(
      enabled: loadedSearchSettings.enabled,
      provider: loadedSearchSettings.provider,
      apiKey: savedSearchKey ?? loadedSearchSettings.apiKey,
      fallbackApiKeys: savedFallbackKeys.isNotEmpty ? savedFallbackKeys : loadedSearchSettings.fallbackApiKeys,
      googleCx: loadedSearchSettings.googleCx,
      customProviders: loadedSearchSettings.customProviders,
    );

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

    final loadedCustom = <ProviderDefinition>[];
    if (customRaw != null && customRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(customRaw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) continue;
            final id = entry['id']?.toString() ?? '';
            final name = entry['name']?.toString() ?? '';
            final baseUrl = entry['baseUrl']?.toString() ?? '';
            if (!id.startsWith('custom_') ||
                name.isEmpty ||
                baseUrl.isEmpty) {
              continue;
            }
            loadedCustom.add(
              ProviderDefinition(
                id: id,
                name: name,
                shortName: name.trim().length >= 2
                    ? name.trim().substring(0, 2).toUpperCase()
                    : 'CU',
                keyLabel: 'CUSTOM_API_KEY',
                baseUrl: baseUrl,
                models: const ['custom-model'],
              ),
            );
          }
        }
      } catch (_) {
        loadedCustom.clear();
      }
    }

    var effectiveSelected = selected;
    final legacy = nextSettings['custom'];
    if (legacy != null &&
        !loadedCustom.any((p) => p.id == 'custom_legacy') &&
        (legacy.apiKey.trim().isNotEmpty ||
            (legacy.baseUrl.trim().isNotEmpty &&
                legacy.baseUrl.trim() != 'https://example.com/v1'))) {
      const legacyId = 'custom_legacy';
      loadedCustom.insert(
        0,
        ProviderDefinition(
          id: legacyId,
          name: 'My Custom Provider',
          shortName: 'MC',
          keyLabel: 'CUSTOM_API_KEY',
          baseUrl: legacy.baseUrl.trim().isEmpty
              ? 'https://example.com/v1'
              : legacy.baseUrl.trim(),
          models: const ['custom-model'],
        ),
      );
      nextSettings[legacyId] = legacy;
      if (effectiveSelected == 'custom') effectiveSelected = legacyId;
    }

    for (final provider in loadedCustom) {
      String? key;
      try {
        key = await _secureStorage.read(key: _keyStorageName(provider.id));
      } catch (e) {
        key = prefs.getString('fallback_api_key_${provider.id}');
      }
      final current =
          nextSettings[provider.id] ?? ProviderSettings.defaults(provider);
      final normalized = current.maxTokens < 1
          ? current.copyWith(maxTokens: provider.defaultMaxTokens)
          : current;
      nextSettings[provider.id] =
          normalized.copyWith(apiKey: key ?? normalized.apiKey);
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
      _agenticEnabled = agenticRaw ?? false;
      _artifactsEnabled = artifactsRaw ?? false;
      _svgVisualsEnabled = svgVisualsRaw ?? false;
      _shellPermission = prefs.getString('shell_permission_v1') ?? 'ask';
      _shellPrefixAllowed
        ..clear()
        ..addAll(prefs.getStringList('shell_prefix_allowed_v1') ?? []);
      final loadedWorkspace = (agenticWorkspaceRaw ?? '').trim();
      _agenticWorkspace = loadedWorkspace.isNotEmpty
          ? loadedWorkspace
          : '/data/data/com.termux/files/home';
      _customMcpUrl = customMcpUrlRaw ?? '';
      _deepResearchEnabled = deepResearchRaw ?? false;
      _studyModeEnabled = prefs.getBool('study_mode_enabled_v1') ?? false;
      _userName = prefs.getString('user_name_v1') ?? '';
      // Enforce mode exclusivity at load: prefs may predate the toggle guards,
      // and conflicting modes dilute the system prompt (models drop tool
      // discipline when agentic + search instructions are mixed).
      if (_studyModeEnabled && _agenticEnabled) _agenticEnabled = false;
      if (_deepResearchEnabled && _agenticEnabled) _deepResearchEnabled = false;
      if (_agenticEnabled && _searchSettings.enabled) {
        _searchSettings = SearchSettings(
          enabled: false,
          provider: _searchSettings.provider,
          apiKey: _searchSettings.apiKey,
          fallbackApiKeys: _searchSettings.fallbackApiKeys,
          googleCx: _searchSettings.googleCx,
          customProviders: _searchSettings.customProviders,
        );
      }
      SlashCommandService.agenticAccessEnabled = _agenticEnabled;
      _writerContextBudget = writerContextBudgetRaw ?? 32000;
      _customProviders = loadedCustom;
      if (effectiveSelected != null &&
          (providerCatalog.any((provider) => provider.id == effectiveSelected) ||
              loadedCustom.any(
                (provider) => provider.id == effectiveSelected,
              ))) {
        _selectedProviderId = effectiveSelected;
      }
    });

    await _ensureLocalSupportDirs();
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
      _customProvidersKey,
      jsonEncode([
        for (final provider in _customProviders)
          {
            'id': provider.id,
            'name': provider.name,
            'baseUrl': provider.baseUrl,
          },
      ]),
    );
    final searchSettingsToSave = SearchSettings(
      enabled: _searchSettings.enabled,
      provider: _searchSettings.provider,
      apiKey: '',
      fallbackApiKeys: const [],
      googleCx: _searchSettings.googleCx,
      customProviders: _searchSettings.customProviders,
    );
    await prefs.setString(
      'search_settings_v1',
      jsonEncode(searchSettingsToSave.toJson()),
    );
    if (_searchSettings.apiKey.isNotEmpty) {
      try {
        await _secureStorage.write(
          key: 'search_api_key',
          value: _searchSettings.apiKey,
        );
      } catch (_) {}
    }
    if (_searchSettings.fallbackApiKeys.isNotEmpty) {
      try {
        await _secureStorage.write(
          key: 'search_fallback_keys',
          value: jsonEncode(_searchSettings.fallbackApiKeys),
        );
      } catch (_) {}
    }
    await prefs.setBool('agentic_enabled_v1', _agenticEnabled);
    await prefs.setBool('artifacts_enabled_v1', _artifactsEnabled);
    await prefs.setBool('svg_visuals_enabled_v1', _svgVisualsEnabled);
    await prefs.setString('shell_permission_v1', _shellPermission);
    await prefs.setBool('deep_research_enabled_v1', _deepResearchEnabled);
    await prefs.setBool('study_mode_enabled_v1', _studyModeEnabled);
    await prefs.setString('user_name_v1', _userName);
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
    final provider = _resolveProvider(providerId ?? _selectedProviderId);
    // 'custom' is create-mode: always start from a clean blank form so a
    // new provider never inherits a previously saved key/base URL.
    final current = provider.id == 'custom'
        ? ProviderSettings.defaults(provider)
        : _settings[provider.id] ?? ProviderSettings.defaults(provider);
    final result = await showModalBottomSheet<ProviderSheetResult>(
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
    var targetId = provider.id;
    if (_isCustomProviderId(provider.id)) {
      final name = (result.customName ?? '').trim().isEmpty
          ? 'Custom Provider'
          : (result.customName ?? '').trim();
      final baseUrl = result.settings.baseUrl.trim().isEmpty
          ? 'https://example.com/v1'
          : result.settings.baseUrl.trim();
      final shortName = name.length >= 2
          ? name.substring(0, 2).toUpperCase()
          : 'CU';
      final definition = ProviderDefinition(
        id: provider.id == 'custom'
            ? 'custom_${DateTime.now().millisecondsSinceEpoch}'
            : provider.id,
        name: name,
        shortName: shortName,
        keyLabel: 'CUSTOM_API_KEY',
        baseUrl: baseUrl,
        models: const ['custom-model'],
      );
      targetId = definition.id;
      setState(() {
        if (provider.id == 'custom') {
          _customProviders = [..._customProviders, definition];
        } else {
          _customProviders = [
            for (final existing in _customProviders)
              existing.id == provider.id ? definition : existing,
          ];
        }
      });
    }
    setState(() {
      _settings = {..._settings, targetId: result.settings};
      _selectedProviderId = targetId;

      final targetSessionId = _activeSessionId;
      if (targetSessionId != null) {
        final sessionIndex = _sessions.indexWhere(
          (s) => s.id == targetSessionId,
        );
        if (sessionIndex != -1) {
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            providerId: targetId,
            model: result.settings.model,
            maxTokens: result.settings.maxTokens,
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

  Future<void> _sendMessage({
    String? promptText,
    String? userTextOverride,
  }) async {
    final prompt = (promptText ?? userTextOverride ?? _messageController.text)
        .trim();
    if (prompt.isEmpty) return;
    if (prompt.startsWith('/')) {
      if (promptText == null && userTextOverride == null) {
        _messageController.clear();
      }
      await SlashCommandService.handle(
        prompt,
        SlashCommandCallbacks(
          createNew: _slashNew,
          listSessions: _slashList,
          switchSession: _slashSwitch,
          saveSession: ({String? name, String? path}) =>
              _slashSave(name: name, path: path),
          resumeSession: _slashResume,
          summarizeSession: _slashSummarize,
          createCheckpoint: _slashCheckpoint,
          restoreCheckpoint: _slashRestoreCheckpoint,
          listCheckpoints: _slashListCheckpoints,
          clearCurrent: _slashClear,
          showSystemMessage: _appendSystemMessage,
          planPrompt: _slashPlan,
        ),
      );
      return;
    }
    if (promptText == null && userTextOverride == null) {
      _messageController.clear();
    }

    final targetSessionId = _activeSessionId;
    if (targetSessionId == null) return;
    if (_sendingSessionIds.contains(targetSessionId)) return;

    final sessionIndex = _sessions.indexWhere((s) => s.id == targetSessionId);
    if (sessionIndex == -1) return;

    final session = _sessions[sessionIndex];
    final provider = _resolveProvider(session.providerId);
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
      while (shouldContinue && toolCallCount < 30) {
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

        if (_deepResearchEnabled &&
            !currentSession.messages.any(
              (m) => m.text.contains('"research_state"'),
            )) {
          systemPromptText = DeepResearchPrompts.plannerSystemPrompt;
        } else {
          _promptEngine.resetToDefaults();
          _promptEngine.setUserInfo(
            userName: _userName,
            cwd: (_agenticEnabled || _studyModeEnabled) ? _agenticWorkspace : null,
            os: (_agenticEnabled || _studyModeEnabled) ? 'android with termux' : null,
            date: currentDateStr,
            modelName: _settings[_selectedProviderId]?.model ?? '',
          );

          final bool isVoiceActive =
              _liveVoiceEngine.state != LiveVoiceState.idle;

          if (_studyModeEnabled) {
            _promptEngine.setIdentity(StudyModePrompts.identity);
            _promptEngine.setNarration(StudyModePrompts.narration);
            _promptEngine.addFeature(StudyModePrompts.features);
          } else if (_agenticEnabled) {
            _promptEngine.setIdentity(AgenticPrompts.identity);
            _promptEngine.setNarration(AgenticPrompts.narration);
            _promptEngine.setContext(AgenticPrompts.context);
            _promptEngine.addFeature(AgenticPrompts.features);
          }

          if (_searchSettings.enabled) {
            _promptEngine.setContext(WebSearchPrompts.context(currentDateStr));
            if (!_agenticEnabled && !_studyModeEnabled) {
              _promptEngine.setNarration(WebSearchPrompts.narration);
            }
            _promptEngine.addFeature(WebSearchPrompts.features);
          }

          if (_artifactsEnabled) {
            _promptEngine.addFeature(ArtifactsPrompts.features);
          }

          if (_svgVisualsEnabled) {
            _promptEngine.addFeature(SvgVisualsPrompts.features);
          }

          if (isVoiceActive) {
            _promptEngine.setNarration(VoiceModePrompts.narration);
            _promptEngine.addFeature(VoiceModePrompts.features);
          }


          systemPromptText = _promptEngine.assemble();
        }

        // System prompt goes out on EVERY request. Chat-completions APIs are
        // stateless — the provider remembers nothing between calls — so
        // skipping turns left the model instruction-less (SVG/web-search
        // prompts never reached it) and the alternating prefix defeated
        // provider-side KV-cache reuse. A byte-stable repeated prompt is what
        // makes prefix caching fast.
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

        // Token budget: degrade oldest long messages to stubs before the
        // provider hard-fails on context length (chars/4 token estimate).
        int estTokens = 0;
        for (final m in historyForApi) {
          estTokens += m.text.length ~/ 4;
        }
        const kHistoryBudget = 90000;
        for (var i = 1;
            i < historyForApi.length - 8 && estTokens > kHistoryBudget;
            i++) {
          final m = historyForApi[i];
          if (m.text.length > 200) {
            final stub = '[context space: earlier turn omitted]';
            estTokens -= (m.text.length - stub.length) ~/ 4;
            historyForApi[i] = ChatMessage(
              role: m.role,
              text: stub,
              isError: m.isError,
              reasoning: m.reasoning,
            );
          }
        }

        final stream = _chatClient.sendChatStream(
          provider: provider,
          settings: settings,
          model: activeModel,
          messages: historyForApi,
          studyModeEnabled: _studyModeEnabled,
        );

        final completer = Completer<void>();
        var fullText = '';
        var reasoningText = '';
        var isThinking = false;
        final updateStopwatch = Stopwatch()..start();
        final streamStopwatch = Stopwatch()..start();
        var streamCharCount = 0;

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
                streamCharCount += textChunk.length;
                if (_liveVoiceEngine.state == LiveVoiceState.thinking ||
                    _liveVoiceEngine.state == LiveVoiceState.speaking) {
                  // Skip tool-call / SSML tag chunks so they are not spoken
                  // (SSML tags, and fenced ```json tool blocks). Pure speech
                  // chunks are stripped of SSML at enqueue time.
                  final fenceCount = '```'.allMatches(fullText).length;
                  if (!textChunk.contains('<') && fenceCount.isEven) {
                    _liveVoiceEngine.feedStreamToken(textChunk);
                  }
                }
              }
            }

            if (updateStopwatch.elapsedMilliseconds > 80) {
              setState(() {
                final idx = _sessions.indexWhere(
                  (s) => s.id == targetSessionId,
                );
                if (idx != -1) {
                  final msgs = List<ChatMessage>.from(_sessions[idx].messages);
                  if (assistantMessageIndex < msgs.length) {
                    final elapsedSec = streamStopwatch.elapsedMilliseconds / 1000.0;
                    final estTokens = (streamCharCount / 4).ceil();
                    final tps = elapsedSec > 0.1 ? (estTokens / elapsedSec) : 0.0;
                    final maxTok = settings.maxTokens;
                    msgs[assistantMessageIndex] = ChatMessage(
                      role: MessageRole.assistant,
                      text: _fenceBareToolCalls(fullText),
                      reasoning: reasoningText,
                      tokensPerSec: tps > 0 ? tps.toStringAsFixed(1) : '',
                      tokenUsage: formatTokenUsage(estTokens, maxTok),
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
            if (_liveVoiceEngine.state == LiveVoiceState.thinking ||
                _liveVoiceEngine.state == LiveVoiceState.speaking) {
              _liveVoiceEngine.interrupt();
            }
            if (!completer.isCompleted) completer.completeError(err);
          },
          onDone: () {
            if (_liveVoiceEngine.state == LiveVoiceState.thinking ||
                _liveVoiceEngine.state == LiveVoiceState.speaking) {
              _liveVoiceEngine.endStreamResponse();
            }
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
        streamStopwatch.stop();
        final finalElapsedSec = streamStopwatch.elapsedMilliseconds / 1000.0;
        final finalEstTokens = (streamCharCount / 4).ceil();
        final finalTps = finalElapsedSec > 0.1 ? (finalEstTokens / finalElapsedSec) : 0.0;
        final finalMaxTok = settings.maxTokens;
        final finalUsage = formatTokenUsage(finalEstTokens, finalMaxTok);

        setState(() {
          final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
          if (idx != -1) {
            final msgs = List<ChatMessage>.from(_sessions[idx].messages);
            if (assistantMessageIndex < msgs.length) {
              msgs[assistantMessageIndex] = ChatMessage(
                  role: MessageRole.assistant,
                  text: _svgVisualsEnabled
                      ? _fenceBareToolCalls(fullText)
                      : _stripSvgVisuals(_fenceBareToolCalls(fullText)),
                  reasoning: reasoningText,
                  tokensPerSec: finalTps > 0 ? finalTps.toStringAsFixed(1) : '',
                  tokenUsage: finalUsage,
                );
              _sessions[idx] = _sessions[idx].copyWith(messages: msgs);
            }
          }
        });
        if (targetSessionId == _activeSessionId) {
          _scrollToBottom();
        }

        if (_deepResearchEnabled) {
          final planFence = findFenceWithKeys(fullText, ['research_plan']);
          if (planFence != null) {
            final rawPlan =
                (planFence['json'] as Map<String, dynamic>)['research_plan'];
            final phaseList = rawPlan is List
                ? rawPlan
                : (rawPlan is Map<String, dynamic> &&
                          rawPlan['phases'] is List
                      ? rawPlan['phases'] as List
                      : const <dynamic>[]);
            final List<Map<String, dynamic>> stepsList = [];
            int phaseNum = 1;
            for (final entry in phaseList) {
              if (entry is! Map) continue;
              final textContent = (entry['prompt'] ?? '').toString().trim();
              var title = (entry['title'] ?? '').toString().trim();
              final prompt = textContent;
              if (title.isEmpty) {
                final separatorIndex = textContent.indexOf(RegExp(r' - | \| | success:', caseSensitive: false));
                if (separatorIndex != -1 && separatorIndex < 35) {
                  title = textContent.substring(0, separatorIndex).trim();
                } else {
                  title = 'Phase $phaseNum';
                }
              }
              stepsList.add({
                "title": title,
                "prompt": prompt.isNotEmpty ? prompt : title,
                "status": "pending",
                "content": "",
              });
              phaseNum++;
            }

            if (stepsList.isNotEmpty) {
              final stateMap = {"status": "pending", "steps": stepsList};

              setState(() {
                final msgs = List<ChatMessage>.from(
                  _sessions[sessionIndex].messages,
                );
                msgs[assistantMessageIndex] = ChatMessage(
                  role: MessageRole.assistant,
                  text: fullText + '\n\n' + researchStateFence(stateMap),
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
        }

        if (toolCallCount >= 30) {
          shouldContinue = false;
          final cpMsg = await _slashCheckpoint(
            'tool_loop_limit_${DateTime.now().millisecondsSinceEpoch}',
          );
          await _appendSystemMessage(
            '$cpMsg\nTool loop reached 30 calls. Stop here and resume with /restore <checkpoint-id> if needed.',
          );
          continue;
        }

        List<String> toolOutputs = [];
        bool executedTools = false;

        // JSON calls for tools the C++ binary doesn't own are collected here
        // and dispatched through the existing Python-bridge HTTP path below.
        final List<String> nativeHttpCalls = [];

        // ── Native C++ tools fast path (JSON tool calls) ──────────────────
        // Fenced ```json blocks shaped {"t","a"} or {"calls":[...]}. Tools the
        // C++ binary owns run locally with no Python/HTTP hop; web_search and
        // read_url run in-app; other JSON tools are translated to the Python
        // bridge's {"method","params"} shape and queued for the existing HTTP
        // dispatch below.
        // JSON tool-call extraction runs in every mode (parity with the old
        // always-on XML regexes): web_search/read_url must work in plain chat
        // too, and workspace tools + quiz in study mode. The cheap fence
        // prefilter skips replies that can't contain a JSON tool block.
        if (fullText.contains('```') ||
            fullText.contains('"t"')) {
          final nativeCalls = _findNativeToolCalls(fullText);
          if (nativeCalls.isEmpty &&
              (_agenticEnabled || _studyModeEnabled) &&
              fullText.contains('```json') &&
              fullText.contains('"t"')) {
            toolOutputs.add(
              'Tool Result [format]:\n\n{"error":"a ```json block looked like a tool call but was not valid JSON. Emit exactly one fenced json block: {"t": "tool", "a": {...}} with strictly valid JSON - double quotes, no trailing commas."}',
            );
            executedTools = true;
          }
          for (final nativeCall in nativeCalls) {
            final toolName = (nativeCall['t'] ?? '').toString();
            if (toolName.isEmpty) continue;
            Map<String, dynamic> toolArgs = const {};
            final rawArgs = nativeCall['a'];
            if (rawArgs is Map<String, dynamic>) {
              toolArgs = rawArgs;
            } else if (rawArgs is String && rawArgs.trim().isNotEmpty) {
              try {
                final decodedArgs = jsonDecode(rawArgs);
                if (decodedArgs is Map<String, dynamic>) toolArgs = decodedArgs;
              } catch (_) {}
            }

            if (!NativeToolsService.handles(toolName)) {
              // ── Non-cpp JSON tools ──────────────────────────────────────
              if (toolName == 'web_search' || toolName == 'search_web') {
                executedTools = true;
                if (!_searchSettings.enabled) {
                  toolOutputs.add(
                    'Tool Result [$toolName]:\n\n{"error":"web search is disabled in settings"}',
                  );
                  continue;
                }
                final List<String> searchQueries = [];
                final qList = toolArgs['queries'] ?? toolArgs['q_list'];
                if (qList is List) {
                  for (final item in qList) {
                    final s = item.toString().trim();
                    if (s.isNotEmpty) searchQueries.add(s);
                  }
                }
                final singleQ =
                    (toolArgs['q'] ?? toolArgs['query'] ?? '').toString().trim();
                if (searchQueries.isEmpty && singleQ.isNotEmpty) {
                  searchQueries.add(singleQ);
                }
                if (searchQueries.length > 4) {
                  searchQueries.removeRange(4, searchQueries.length);
                }
                if (searchQueries.isEmpty) {
                  toolOutputs.add(
                    'Tool Result [$toolName]:\n\n{"error":"no query provided"}',
                  );
                  continue;
                }
                final topic = toolArgs['topic']?.toString();
                final timeRange =
                    (toolArgs['time_range'] ?? toolArgs['timeRange'])
                        ?.toString();
                final startDate =
                    (toolArgs['start_date'] ?? toolArgs['startDate'])
                        ?.toString();
                final endDate =
                    (toolArgs['end_date'] ?? toolArgs['endDate'])
                        ?.toString();
                if (mounted) {
                  setState(() => _toolStatus =
                      searchQueries.length == 1
                          ? '🔍 Searching: "${searchQueries.first}"'
                          : '🔍 Searching ${searchQueries.length} queries…');
                }
                final results = await Future.wait(
                  searchQueries.map(
                    (q) => _executeWebSearchQuery(
                      q,
                      topic: topic,
                      timeRange: timeRange,
                      startDate: startDate,
                      endDate: endDate,
                    ).catchError((e) => 'Error running web search: $e'),
                  ),
                );
                if (mounted) setState(() => _toolStatus = '');
                final buf = StringBuffer();
                for (var i = 0; i < searchQueries.length; i++) {
                  buf.writeln(
                    "Search results for '${searchQueries[i]}':\n${results[i]}\n",
                  );
                }
                toolOutputs.add(
                  "Web Search results for ${searchQueries.length == 1 ? "'${searchQueries.first}'" : '${searchQueries.length} queries'}:\n\n${buf.toString().trim()}",
                );
                continue;
              }
              if (toolName == 'read_url') {
                executedTools = true;
                final url = (toolArgs['url'] ?? '').toString();
                final shortUrl =
                    url.length > 50 ? '${url.substring(0, 47)}…' : url;
                if (mounted) {
                  setState(() => _toolStatus = '🌐 Fetching: $shortUrl');
                }
                final urlResult = url.isEmpty
                    ? 'Error fetching URL: no url provided'
                    : await _fetchUrlText(url);
                if (mounted) setState(() => _toolStatus = '');
                toolOutputs.add("Content of URL '$url':\n\n$urlResult");
                continue;
              }
              if (toolName == 'todo_create') {
                executedTools = true;
                final tasks = toolArgs['tasks'];
                final List<TodoItem> items = [];
                if (tasks is List) {
                  for (var i = 0; i < tasks.length; i++) {
                    final item = tasks[i];
                    String title;
                    if (item is String) {
                      title = item;
                    } else if (item is Map) {
                      title = item['title']?.toString() ??
                          item['t']?.toString() ??
                          'Task ${i + 1}';
                    } else {
                      title = item.toString();
                    }
                    if (title.trim().isNotEmpty) {
                      items.add(TodoItem(n: items.length + 1, title: title.trim()));
                    }
                  }
                }
                if (items.isEmpty) {
                  toolOutputs.add(
                    'Tool Result [todo_create]:\n\n{"error":"no tasks provided"}',
                  );
                  continue;
                }
                if (mounted) {
                  setState(() {
                    _activeTodos = items;
                    _todoListVisible = true;
                  });
                }
                toolOutputs.add(
                  'Tool Result [todo_create]:\n\n{"ok":true,"n":${items.length},"tasks":[${items.map((t) => '{"n":${t.n},"title":"${t.title.replaceAll('"', '\\"')}"').join(',')}]}',
                );
                continue;
              }
              if (toolName == 'todo_done') {
                executedTools = true;
                final doneN = toolArgs['n'];
                final doneList = toolArgs['done'];
                final List<int> completed = [];
                if (doneN is int) {
                  completed.add(doneN);
                } else if (doneN is String) {
                  final parsed = int.tryParse(doneN);
                  if (parsed != null) completed.add(parsed);
                }
                if (doneList is List) {
                  for (final d in doneList) {
                    final parsed = d is int ? d : int.tryParse(d.toString());
                    if (parsed != null) completed.add(parsed);
                  }
                }
                if (mounted) {
                  setState(() {
                    for (final n in completed) {
                      final idx = _activeTodos.indexWhere((t) => t.n == n);
                      if (idx != -1) _activeTodos[idx].done = true;
                    }
                  });
                }
                final remaining = _activeTodos.where((t) => !t.done).length;
                toolOutputs.add(
                  'Tool Result [todo_done]:\n\n{"ok":true,"completed":${completed.length},"remaining":$remaining}',
                );
                continue;
              }
              if (toolName == 'quiz' || toolName == 'quiz_request') {
                if (!_studyModeEnabled) {
                  executedTools = true;
                  toolOutputs.add(
                    'Tool Result [$toolName]:\n\n{"error":"the quiz tool is only available in study mode"}',
                  );
                  continue;
                }
                executedTools = true;
                // Hide the quiz's JSON block from the visible bubble and
                // from future API history so the answer key ("correct" indices)
                // is not re-shown to the model on the next turn.
                // Handles both fenced and bare (unfenced) quiz JSON.
                final quizBlockRegex = RegExp(
                  r'```(?:json)?\s*\n[\s\S]*?"t"\s*:\s*"quiz(?:_request)?"[\s\S]*?```',
                  caseSensitive: false,
                );
                String rawQuizBlock =
                    quizBlockRegex.firstMatch(fullText)?.group(0) ?? '';
                // Fallback: find bare (unfenced) quiz JSON via brace matching
                if (rawQuizBlock.isEmpty) {
                  final bareStart = RegExp(
                    r'\{\s*"t"\s*:\s*"quiz(?:_request)?"',
                  ).firstMatch(fullText);
                  if (bareStart != null) {
                    int depth = 0;
                    bool inStr = false;
                    bool esc = false;
                    for (int i = bareStart.start; i < fullText.length; i++) {
                      final c = fullText[i];
                      if (inStr) {
                        if (esc) { esc = false; }
                        else if (c == '\\') { esc = true; }
                        else if (c == '"') { inStr = false; }
                      } else {
                        if (c == '"') { inStr = true; }
                        else if (c == '{') { depth++; }
                        else if (c == '}') {
                          depth--;
                          if (depth == 0) {
                            rawQuizBlock = fullText.substring(bareStart.start, i + 1);
                            break;
                          }
                        }
                      }
                    }
                  }
                }
                if (rawQuizBlock.isNotEmpty && mounted) {
                  setState(() {
                    final idx = _sessions.indexWhere(
                      (s) => s.id == targetSessionId,
                    );
                    if (idx != -1) {
                      final msgs = List<ChatMessage>.from(
                        _sessions[idx].messages,
                      );
                      if (assistantMessageIndex < msgs.length) {
                        final cleaned = msgs[assistantMessageIndex]
                            .text
                            .replaceFirst(rawQuizBlock, '')
                            .trim();
                        msgs[assistantMessageIndex] =
                            msgs[assistantMessageIndex].copyWith(
                              text: cleaned,
                            );
                        _sessions[idx] = _sessions[idx].copyWith(
                          messages: msgs,
                        );
                      }
                    }
                  });
                }
                final questions = QuizSheet.parseQuestions(
                  jsonEncode(toolArgs),
                );
                if (questions.isEmpty) {
                  toolOutputs.add(
                    'Quiz Tool Result:\n\n{"error":"malformed quiz tool call, no valid questions"}',
                  );
                } else {
                  final answers =
                      await showModalBottomSheet<List<Map<String, dynamic>>>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        isDismissible: false,
                        builder: (_) => QuizSheet(questions: questions),
                      );
                  if (answers == null) {
                    toolOutputs.add(
                      'Quiz Tool Result:\n\nUser dismissed the quiz without answering. Ask whether to retry or skip, then continue teaching.',
                    );
                  } else {
                    final sb = StringBuffer(
                      'Quiz results (${answers.length} questions):\n',
                    );
                    for (var qi = 0; qi < answers.length; qi++) {
                      final a = answers[qi];
                      sb.writeln('Q${qi + 1}: ${a['q']}');
                      sb.writeln('  User answer: ${a['picked']}');
                      sb.writeln(
                        a['correct'] == true
                            ? '  Verdict: CORRECT'
                            : '  Verdict: WRONG (correct answer: ${a['answer']})',
                      );
                    }
                    sb.writeln(
                      'For each WRONG answer: first explain why the chosen answer is incorrect, then clearly state the correct answer with a brief explanation. After addressing all wrong answers, continue to the next concept.',
                    );
                    toolOutputs.add(sb.toString());
                  }
                }
                continue;
              }
              // Python-bridge passthrough (run_background, service_*, dart_*,
              // workspace_*...). Translated to the bridge's method/params
              // shape; the HTTP block below handles validation, permission
              // gates, retries and result formatting exactly as it does for
              // legacy calls.
              nativeHttpCalls.add(
                jsonEncode({'method': toolName, 'params': toolArgs}),
              );
              continue;
            }
            executedTools = true;

            // Safety checkpoint before heavy file mutations (parity with the
            // legacy patch_file/write_file_rich/delete_path checkpointing).
            if (toolName == 'patch' ||
                toolName == 'edit' ||
                toolName == 'create_file' ||
                toolName == 'cut' ||
                toolName == 'extract' ||
                toolName == 'fileops') {
              try {
                await _slashCheckpoint(
                  'auto_before_native_${toolName}_${DateTime.now().millisecondsSinceEpoch}',
                );
              } catch (e) {
                toolOutputs.add(
                  'Tool Result [$toolName]:\n\n{"warning":"checkpoint creation failed","details":"$e"}',
                );
              }
            }

            // Shell permission gate (parity with run_command).
            if (toolName == 'sh' ||
                toolName == 'diagnostics' ||
                toolName == 'py') {
              final cmd = toolName == 'sh'
                  ? (toolArgs['cmd']?.toString() ?? '')
                  : toolName == 'diagnostics'
                      ? (toolArgs['cmd']?.toString() ?? '')
                      : 'py:${toolArgs['m'] ?? ''}';
              if (_classifyShellSegments(cmd) == 'deny') {
                toolOutputs.add(
                  'Tool Result [$toolName]:\n\n{"error":"Command denied by safety policy: contains a hard-denied segment (rm -rf, chmod 777/666, mkfs, dd if=, or force-push)."}',
                );
                continue;
              }
              final allowed = await _askShellPermission(cmd);
              if (!allowed) {
                toolOutputs.add(
                  'Tool Result [$toolName]:\n\n{"error":"User denied shell command execution."}',
                );
                continue;
              }
            }

            // File-mutation permission gate. Native arg names differ from the
            // legacy tools (f/to vs path/src/dest), so map them onto the keys
            // the existing permission dialog understands.
            if (_nativeIsFileMutation(toolName, toolArgs)) {
              final permParams = _nativePermParams(toolName, toolArgs);
              if (!_allPathsTrusted(permParams)) {
                final allowed = await _askFileMutationPermission(
                  toolName,
                  permParams,
                );
                if (!allowed) {
                  toolOutputs.add(
                    'Tool Result [$toolName]:\n\n{"error":"User denied file operation."}',
                  );
                  continue;
                }
              }
            }

            if (mounted) {
              setState(
                () => _toolStatus = _toolStatusLabel(toolName, toolArgs),
              );
            }

            Map<String, dynamic> result;
            try {
              result = await NativeToolsService().call(
                workspace: _agenticWorkspace,
                tool: toolName,
                args: toolArgs,
              );
            } on NativeToolsException catch (e) {
              result = {'err': e.message, 't': toolName};
            } catch (e) {
              result = {'err': 'native tools error: $e', 't': toolName};
            }

            if (mounted) setState(() => _toolStatus = '');
            final resultJson = jsonEncode(result);
            toolOutputs.add('Tool Result [$toolName]:\n\n$resultJson');

            if (toolName == 'patch' || toolName == 'edit' || toolName == 'create_file') {
              String? filePath;
              if (toolArgs['f'] is String) {
                filePath = toolArgs['f'] as String;
              } else if (toolArgs['p'] is List && (toolArgs['p'] as List).isNotEmpty) {
                final first = (toolArgs['p'] as List).first;
                if (first is Map && first['f'] is String) filePath = first['f'] as String;
              } else if (toolArgs['e'] is List && (toolArgs['e'] as List).isNotEmpty) {
                final first = (toolArgs['e'] as List).first;
                if (first is Map && first['f'] is String) filePath = first['f'] as String;
              }
              if (filePath != null && filePath.endsWith('.dart') && !resultJson.contains('"err"')) {
                try {
                  final diagResult = await NativeToolsService().call(
                    workspace: _agenticWorkspace,
                    tool: 'diagnostics',
                    args: {'cmd': 'dart analyze ${_verifyShellQuote(filePath)} 2>&1', 'to': 60},
                  );
                  final diagOut = (diagResult['out'] ?? '').toString();
                  if (diagOut.contains('error')) {
                    toolOutputs.add('Tool Result [auto_verify]:\n\n$diagOut');
                  } else {
                    toolOutputs.add(
                      'Tool Result [auto_verify]: PASSED (dart analyze, 0 errors)',
                    );
                  }
                } catch (_) {}
              }
            }
          }
        }

        if (nativeHttpCalls.isNotEmpty &&
            !_agenticEnabled &&
            !_studyModeEnabled) {
          for (final js in nativeHttpCalls) {
            toolOutputs.add(
              'Tool Result [bridge]:\n\n{"error":"Python bridge tools require Agentic File Access or Study Mode to be enabled."}',
            );
          }
          executedTools = true;
        }

        if ((_agenticEnabled || _studyModeEnabled) &&
            nativeHttpCalls.isNotEmpty) {
          final mcpMatches = [
            for (final js in nativeHttpCalls)
              RegExp(r'([\s\S]*)').firstMatch(js)!,
          ];
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
            String? paramResolveError;
            try {
              final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
              toolMethod = parsed['method']?.toString() ?? 'tool';
              toolMethod = _normalizeToolMethod(toolMethod);
              parsed['method'] = toolMethod;
              toolParams = parsed['params'] as Map<String, dynamic>? ?? {};
              final callError = _validateToolCall(
                jsonString,
                toolMethod,
                toolParams,
              );
              if (callError != null) paramResolveError = callError;

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
              resolveToolPaths(toolParams, _agenticWorkspace);
              parsed['params'] = toolParams;
              jsonString = jsonEncode(parsed);
            } catch (e) {
              paramResolveError = e.toString();
            }
            if (paramResolveError != null) {
              toolOutputs.add(
                'Tool Result [${toolMethod}]:\n\n{"error":"invalid tool call","details":"$paramResolveError"}',
              );
              continue;
            }

            if (toolMethod == 'patch_file' ||
                toolMethod == 'patch_file_rich' ||
                toolMethod == 'write_file_rich' ||
                toolMethod == 'delete_path') {
              try {
                await _slashCheckpoint(
                  'auto_before_${toolMethod}_${DateTime.now().millisecondsSinceEpoch}',
                );
              } catch (e) {
                toolOutputs.add(
                  'Tool Result [${toolMethod}]:\n\n{"warning":"checkpoint creation failed","details":"$e"}',
                );
              }
            }

            // Permission check before running shell commands
            if (toolMethod == 'run_command' ||
                toolMethod == 'shell_exec' ||
                toolMethod == 'execute_command' ||
                toolMethod == 'execute_shell' ||
                toolMethod == 'shell_rich' ||
                toolMethod == 'run_background') {
              final cmd = toolParams['command']?.toString() ?? '';
              // F-1: Hard-deny dangerous segments with a specific error
              if (_classifyShellSegments(cmd) == 'deny') {
                toolOutputs.add(
                  'Tool Result [${toolMethod}]:\n\n{"error": "Command denied by safety policy: contains a hard-denied segment (rm -rf, chmod 777/666, mkfs, dd if=, or force-push)."}',
                );
                continue;
              }
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
              try {
                final request = await _mcpHttpClient
                    .postUrl(Uri.parse(mcpEndpoint))
                    .timeout(const Duration(seconds: 120));
                request.headers.contentType = ContentType.json;

                final bytes = utf8.encode(jsonString);
                request.headers.contentLength = bytes.length;
                request.add(bytes);

                final response = await request.close().timeout(
                  const Duration(seconds: 120),
                );
                final body = await response
                    .transform(utf8.decoder)
                    .join()
                    .timeout(const Duration(seconds: 120));

                String cleanResult = body;
                try {
                  final parsed = jsonDecode(body);
                  dynamic resultData;
                  if (parsed is Map<String, dynamic>) {
                    resultData = parsed['result'] ?? parsed;
                  } else {
                    resultData = parsed;
                  }

                  if (resultData is Map<String, dynamic>) {
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
                    } else {
                      cleanResult = jsonEncode(resultData);
                    }
                  } else if (resultData is List) {
                    cleanResult = jsonEncode(resultData);
                  }
                } catch (_) {}

                mcpResult = cleanResult;
                if (mcpResult.length > 32000) {
                  const fileReadMethods = {
                    'read_file_rich',
                    'file_outline',
                    'file_outline_rich',
                    'search_rich',
                    'tree',
                    'tree_rich',
                    'multi_read_rich',
                  };
                  if (fileReadMethods.contains(toolMethod)) {
                    mcpResult = mcpResult.substring(0, 20000);
                  } else {
                    mcpResult =
                        mcpResult.substring(0, 16000) +
                        '\n\n...[middle truncated — ${mcpResult.length - 22000} chars removed]...\n\n' +
                        mcpResult.substring(mcpResult.length - 6000);
                  }
                }
                break; // Success, break out of retry loop.
              } catch (e) {
                if (attempt >= maxRetries) {
                  mcpResult =
                      '{"error": "MCP bridge connection failed after $maxRetries attempts: $e"}';
                } else {
                  // Wait a short time before retrying
                  await Future.delayed(Duration(milliseconds: 500 * attempt));
                }
              }
            }
            if (mounted) setState(() => _toolStatus = '');
            final verification = await _autoVerifyMutation(
              toolMethod,
              toolParams,
              mcpResult,
            );
            if (verification != null) mcpResult += verification;
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
              errorMsg =
                  'This model does not support $attachmentInfo attachments. ($error)';
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

  List<ChatMessage> _compactHistoryForApi(
    List<ChatMessage> messages,
    int assistantMessageIndex,
  ) {
    final List<ChatMessage> rawHistory = messages
        .take(assistantMessageIndex)
        .toList();
    // Filter out welcome/new-chat placeholder messages — they aren't real responses
    const _welcomeTexts = [
      'Select a provider, add its API key, fetch or type a model, then start chatting.',
      'New chat ready. Choose any configured provider and model.',
    ];
    rawHistory.removeWhere(
      (m) =>
          m.role == MessageRole.assistant &&
          _welcomeTexts.any((w) => m.text.trim() == w),
    );
    if (rawHistory.length <= 4) {
      return rawHistory;
    }

    final List<ChatMessage> compacted = [];

    // Always keep the first message (initial instruction/goal)
    compacted.add(rawHistory.first);

    // Preserve the last 3 messages fully to maintain immediate conversation flow.
    // Inside an active tool loop keep a wider verbatim tail (last 8) so a pending
    // patch's source read is never halved mid-loop.
    final inToolLoop = rawHistory.reversed.take(12).any(
      (m) => m.role == MessageRole.system && m.text.startsWith('Tool Result ['),
    );
    final tailKeep = inToolLoop ? 8 : 3;
    final intermediateEndIndex = rawHistory.length - tailKeep - 1;

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
          final toolResultMatch = RegExp(
            r'Tool Result \[(\w+)\]',
          ).firstMatch(newText);
          final mcpMatch = newText.contains('MCP Result:\n');
          final method = toolResultMatch?.group(1)?.trim();
          const keepRichToolMethods = {
            'read_file_rich', 'file_outline', 'file_outline_rich',
            'search_rich', 'tree', 'tree_rich', 'multi_read_rich',
            'find_files', 'symbol_search', 'symbol_references',
            'workspace_list', 'workspace_search', 'workspace_read_page',
            'workspace_get_outline', 'workspace_cross_compare',
            'read', 'search', 'outline', 'list', 'find', 'recent',
          };

          if (toolResultMatch != null &&
              method != null &&
              keepRichToolMethods.contains(method)) {
            newText = newText.substring(0, 4000);
          } else if (toolResultMatch != null) {
            newText =
                'Tool Result [$method]:\n\n'
                '[System: Detailed tool output (${newText.length} characters) omitted for context space. Operation completed successfully.]';
          } else if (mcpMatch) {
            newText =
                'MCP Result:\n\n'
                '[System: Detailed MCP tool output (${newText.length} characters) omitted for context space. Operation completed successfully.]';
          } else if (newText.startsWith('Search results:\n') ||
              newText.startsWith('Web Search results')) {
            newText =
                '🔍 Web Search Results:\n\n'
                '[System: Search results omitted for context space.]';
          } else if (newText.startsWith('URL Content:\n') ||
              newText.startsWith('Content of URL')) {
            newText =
                '🌐 URL Content:\n\n'
                '[System: Webpage content omitted for context space.]';
          } else {
            // General truncation for very long intermediate system messages
            newText =
                newText.substring(0, 500) +
                '\n\n... [${newText.length - 1000} characters omitted for context space] ...\n\n' +
                newText.substring(newText.length - 500);
          }
        }

        compacted.add(
          ChatMessage(
            role: msg.role,
            text: newText,
            isError: msg.isError,
            reasoning: msg.reasoning,
            images: msg.images,
            videos: msg.videos,
            files: const [], // Strip files from intermediate system messages
          ),
        );
      } else if (msg.role == MessageRole.assistant) {
        String newText = msg.text;

        if (newText.length > 2500) {
          // Stub native ```json tool-call bodies (their edit text already lives
          // in tool results); prose JSON that fails to parse stays verbatim.
          newText = newText.replaceAllMapped(
            RegExp(r'```json\s*\n([\s\S]*?)\n```'),
            (m) {
              try {
                final d = jsonDecode(m.group(1)!);
                if (d is Map && (d['t'] != null || d['calls'] != null)) {
                  final names = d['calls'] is List
                      ? (d['calls'] as List).map((c) => c['t']).join(',')
                      : d['t'];
                  return '[tool call: $names - body omitted for context space]';
                }
              } catch (_) {}
              return m.group(0)!;
            },
          );
          newText = newText.replaceAllMapped(
            RegExp(r'<content>([\s\S]{1000,})</content>'),
            (match) =>
                '<content>... [Code content of length ${match.group(1)!.length} characters omitted for context space] ...</content>',
          );
          newText = newText.replaceAllMapped(
            RegExp(r'<new_content>([\s\S]{1000,})</new_content>'),
            (match) =>
                '<new_content>... [New code content of length ${match.group(1)!.length} characters omitted for context space] ...</new_content>',
          );
          newText = newText.replaceAllMapped(
            RegExp(r'<patches>([\s\S]{1000,})</patches>'),
            (match) =>
                '<patches>... [Patches data of length ${match.group(1)!.length} characters omitted] ...</patches>',
          );
          newText = newText.replaceAllMapped(
            RegExp(r'```(?:html|markdown|md|react|json-chart|docx)\s*\n([\s\S]{800,}?)\n```'),
            (match) =>
                '```[Artifact of ${match.group(1)!.length} chars omitted for context space]```',
          );
        }

        compacted.add(
          ChatMessage(
            role: msg.role,
            text: newText,
            isError: msg.isError,
            reasoning: msg.reasoning,
            images: msg.images,
            videos: msg.videos,
            files: const [],
          ),
        );
      } else if (msg.role == MessageRole.user) {
        String userText = msg.text;
        if (userText.length > 4000) {
          if (userText.startsWith('Search results for') ||
              userText.startsWith('Content of URL') ||
              userText.startsWith('Web Search results')) {
            userText = userText.substring(0, 2000) +
                '\n\n...[${userText.length - 3000} chars omitted for context space]...\n\n' +
                userText.substring(userText.length - 1000);
          }
        }
        compacted.add(
          ChatMessage(
            role: msg.role,
            text: userText,
            isError: msg.isError,
            reasoning: msg.reasoning,
            images: msg.images,
            videos: msg.videos,
            files: const [],
          ),
        );
      }
    }

    return compacted;
  }

  /// F-1: Classify a shell command by splitting on chain operators and
  /// checking each segment against deny/allow lists.
  /// Returns 'deny', 'readonly', or 'ask'.
  String _classifyShellSegments(String command) {
    // Split on &&, ||, ;, |, and newlines
    final segments = command
        .split(RegExp(r'&&|\|\||;|\||\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.isEmpty) return 'readonly';

    // Hard-deny patterns — deny wins over everything, even always-allow
    final denyPatterns = [
      RegExp(r'\brm\s+-[a-zA-Z]*[rf]'), // any rm carrying -r or -f
      RegExp(r'\brm\s+--(recursive|force)'),
      RegExp(r'\bfind\b.*(-delete|-exec\s+rm)'),
      RegExp(r'\b(shred|truncate)\b'),
      RegExp(r'\bchmod\s+(777|666)'),
      RegExp(r'\bmkfs\b'),
      RegExp(r'\bdd\s+if='),
      RegExp(r'>\s*/dev/(sd|block)'),
      RegExp(r'\b(curl|wget)\b[^|]*\|\s*(ba)?sh'),
      RegExp(r'\bgit\s+push\s+.*(--force|-f|--force-with-lease)'),
      RegExp(r'\bgit\s+(reset|clean)\s+--hard'),
    ];

    for (final seg in segments) {
      for (final pat in denyPatterns) {
        if (pat.hasMatch(seg)) return 'deny';
      }
    }

    // Read-only auto-approve: every segment must start with a known safe command
    final readOnlyPatterns = [
      RegExp(r'^\s*ls\b'),
      RegExp(r'^\s*cat\b'),
      RegExp(r'^\s*pwd\b'),
      RegExp(r'^\s*head\b'),
      RegExp(r'^\s*tail\b'),
      RegExp(r'^\s*wc\b'),
      RegExp(r'^\s*grep\b'),
      RegExp(r'^\s*rg\b'),
      RegExp(r'^\s*git\s+(status|diff|log|show|branch)\b'),
      RegExp(r'^\s*echo\b'),
      RegExp(r'^\s*which\b'),
      RegExp(r'^\s*find\b'),
      RegExp(r'^\s*file\b'),
      RegExp(r'^\s*stat\b'),
      RegExp(r'^\s*du\b'),
      RegExp(r'^\s*df\b'),
    ];

    for (final seg in segments) {
      final isReadOnly = readOnlyPatterns.any((pat) => pat.hasMatch(seg));
      if (!isReadOnly) return 'ask';
    }

    return 'readonly';
  }

  /// First two command segments, used as the prefix-memory key.
  String _shellPrefixKey(String cmd) {
    final s = cmd.trim().split(RegExp(r'\s+'));
    return s.length >= 2 ? '${s[0]} ${s[1]}' : (s.isNotEmpty ? s[0] : '');
  }

  /// Show permission dialog before executing a shell command.
  /// Returns true if the command should proceed.
  Future<bool> _askShellPermission(String command) async {
    // F-1: Segment-based safety (deny wins over everything)
    final classification = _classifyShellSegments(command);
    if (classification == 'deny') return false;

    // Already allowed globally
    if (_shellPermission == 'always') return true;
    // Already allowed for this session
    if (_shellSessionAllow) return true;
    // Previously approved command prefix (e.g. 'flutter test')
    if (_shellPrefixAllowed.contains(_shellPrefixKey(command))) return true;
    // User previously denied always
    if (_shellPermission == 'never') return false;

    // F-1: Auto-approve pure read-only chains without prompting
    if (classification == 'readonly') return true;

    if (!mounted) return false;

    final short = command.length > 80
        ? command.substring(0, 77) + '…'
        : command;
    if (!mounted) return false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final result = await showDialog<String>(
          context: context,
          useRootNavigator: true,
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
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(
                        Icons.playlist_add_check,
                        size: 14,
                        color: Color(0xFF7B4E2E),
                      ),
                      onPressed: () => Navigator.pop(ctx, 'prefix'),
                      label: Text(
                        'Always allow "${_shellPrefixKey(command)}"',
                        style: const TextStyle(
                          color: Color(0xFF7B4E2E),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => 'no',
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
    if (result == 'prefix') {
      setState(() => _shellPrefixAllowed.add(_shellPrefixKey(command)));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'shell_prefix_allowed_v1',
        _shellPrefixAllowed.toList(),
      );
      return true;
    }
    if (!mounted) return false;
    if (!navigator.mounted) return false;
    return true; // 'yes'
  }

  /// Maps legacy/short tool names emitted by models to the canonical
  /// hybrid-tools registry names on the Python bridge.
  String _normalizeToolMethod(String method) {
    const aliases = {
      'file_read': 'read_file_rich',
      'read_file': 'read_file_rich',
      'multi_read': 'multi_read_rich',
      'file_write': 'write_file_rich',
      'write_file': 'write_file_rich',
      'edit_file': 'patch_file_rich',
      'patch_file': 'patch_file_rich',
      'replace_lines': 'replace_lines_rich',
      'insert_lines': 'insert_lines_rich',
      'delete_lines': 'delete_lines_rich',
      'file_outline': 'file_outline_rich',
      'outline': 'file_outline_rich',
      'file_search': 'search_rich',
      'code_search': 'search_rich',
      'search': 'search_rich',
      'tree': 'tree_rich',
      'dir_list': 'tree_rich',
      'diff_files': 'diff_files_rich',
      'file_info': 'stat_path',
      'file_delete': 'delete_path',
      'dir_create': 'mkdir_path',
      'glob': 'find_files',
      'find': 'find_files',
    };
    return aliases[method] ?? method;
  }

  /// True when every path-like param resolves inside the agentic workspace.
  /// The Python bridge re-enforces the jail server-side; this only decides
  /// whether the user is prompted (Codex/Claude-Code trusted workspace).
  bool _allPathsTrusted(Map<String, dynamic> params) {
    final ws = _agenticWorkspace.trim().replaceAll(RegExp(r'/+$'), '');
    if (ws.isEmpty) return false;
    const home = '/data/data/com.termux/files/home';
    for (final key in ['path', 'src', 'dest', 'file', 'directory', 'dir']) {
      var p = params[key]?.toString().trim() ?? '';
      if (p.isEmpty) continue;
      if (p == '~') p = home;
      if (p.startsWith('~/')) p = '$home${p.substring(1)}';
      p = p.replaceAll(RegExp(r'/+$'), '');
      if (p != ws && !p.startsWith('$ws/')) return false;
    }
    return true;
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
      'patch_file_rich',
      'replace_lines',
      'replace_lines_rich',
      'insert_lines',
      'insert_lines_rich',
      'delete_lines',
      'delete_lines_rich',
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
    var isMutating = mutatingFileTools.contains(method);
    if (method == 'dart_format') {
      final output = params['output']?.toString().toLowerCase().trim();
      isMutating = output == null || output.isEmpty || output == 'write';
    }
    if (!isMutating) return false;
    // Trusted workspace (Codex/Claude-Code style): mutations fully inside
    // the agentic workspace run without prompts — the Python bridge
    // re-enforces the jail, trash and audit log server-side.
    return !_allPathsTrusted(params);
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

  // IMPROVEMENT: structured validation of agent tool calls before they reach
  // the bridge — catches truncated JSON, invalid method names and wrong-typed
  // core params with clear, actionable errors instead of bridge crashes.
  String? _validateToolCall(
    String rawJson,
    String method,
    Map<String, dynamic> params,
  ) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (final ch in rawJson.split('')) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{' || ch == '[') depth++;
      if (ch == '}' || ch == ']') depth--;
      if (depth < 0) return 'tool call JSON has unbalanced brackets';
    }
    if (depth != 0 || inString) {
      return 'tool call JSON is truncated (unbalanced braces)';
    }
    if (!RegExp(r'^[a-z][a-z0-9_.]*$').hasMatch(method)) {
      return 'invalid tool method name: "$method"';
    }
    final reads = params['reads'];
    if (reads != null && reads is! List) {
      if (reads is String) {
        try {
          final decodedReads = jsonDecode(reads.trim());
          if (decodedReads is List) params['reads'] = decodedReads;
        } catch (_) {}
      }
      if (params['reads'] is! List) {
        return '"reads" must be a JSON array of {path, start_line, end_line}';
      }
    }
    final patches = params['patches'];
    if (patches != null && patches is! List) {
      // The XML-style prompt example shows <patches>[...]</patches> as a tag
      // value, so LLMs often send the array as a JSON string. Coerce it here
      // so the call reaches the bridge instead of dying pre-flight.
      if (patches is! String) {
        return '"patches" must be a JSON array';
      }
      final patchText = patches.trim();
      Object? decoded;
      try {
        decoded = jsonDecode(patchText);
      } catch (_) {
        // Strict jsonDecode rejects raw control characters inside strings;
        // escape them and retry once for LLM output that forgot to escape.
        try {
          decoded = jsonDecode(
            patchText
                .replaceAll('\n', '\\n')
                .replaceAll('\r', '\\r')
                .replaceAll('\t', '\\t'),
          );
        } catch (_) {
          decoded = null;
        }
      }
      if (decoded is! List) {
        return '"patches" must be a JSON array of {search, replace} objects';
      }
      params['patches'] = decoded;
    }
    for (final intKey in [
      'start_line',
      'end_line',
      'after_line',
      'count',
      'max_matches',
    ]) {
      final v = params[intKey];
      if (v != null && v is! int && int.tryParse(v.toString()) == null) {
        return '"$intKey" must be an integer, got: $v';
      }
    }
    return null;
  }

  // IMPROVEMENT: ask the bridge for a dry-run diff so the dialog can show
  // exactly what will change before the user approves. Best-effort only.
  Future<String?> _fetchMutationPreview(
    String method,
    Map<String, dynamic> params,
  ) async {
    const previewable = {
      'patch_file',
      'patch_file_rich',
      'edit_file',
      'write_file',
      'write_file_rich',
      'replace_lines',
      'replace_lines_rich',
      'insert_lines',
      'insert_lines_rich',
      'delete_lines',
      'delete_lines_rich',
      'append_file',
    };
    if (!previewable.contains(method)) return null;
    try {
      final previewParams = Map<String, dynamic>.from(params);
      previewParams['dry_run'] = true;
      previewParams['auto_checkpoint'] = false;
      final resultData = await _postMcp(method, previewParams, timeoutSeconds: 10);
      if (resultData == null) return null;
      final diff = resultData['diff']?.toString() ?? '';
      return diff.trim().isNotEmpty ? diff : null;
    } catch (_) {
      return null;
    }
  }

  /// IMPROVEMENT: shared low-level MCP request used by preview + verification.
  Future<Map<String, dynamic>?> _postMcp(
    String method,
    Map<String, dynamic> params, {
    int timeoutSeconds = 15,
  }) async {
    final payload = jsonEncode({'method': method, 'params': params});
    final endpoint = _customMcpUrl.isNotEmpty
        ? _customMcpUrl
        : 'http://127.0.0.1:8390/mcp';
    final request = await _mcpHttpClient
        .postUrl(Uri.parse(endpoint))
        .timeout(Duration(seconds: timeoutSeconds));
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(payload);
    request.headers.contentLength = bytes.length;
    request.add(bytes);
    final response = await request
        .close()
        .timeout(Duration(seconds: timeoutSeconds));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(Duration(seconds: timeoutSeconds));
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    final resultData = parsed['result'] as Map<String, dynamic>? ?? parsed;
    if (resultData['error'] != null) return null;
    return resultData;
  }

  String _verifyShellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  // IMPROVEMENT: closed verification loop — after a successful file mutation,
  // automatically run static checks on the touched file and feed failures back
  // to the model so it fixes them instead of moving on.
  Future<String?> _autoVerifyMutation(
    String method,
    Map<String, dynamic> params,
    String mcpResult,
  ) async {
    const mutating = {
      'patch_file',
      'patch_file_rich',
      'edit_file',
      'write_file',
      'write_file_rich',
      'replace_lines',
      'replace_lines_rich',
      'insert_lines',
      'insert_lines_rich',
      'delete_lines',
      'delete_lines_rich',
      'append_file',
    };
    if (!mutating.contains(method)) return null;
    if (mcpResult.contains('"error"') || mcpResult.startsWith('Error:')) {
      return null;
    }
    final path = params['path']?.toString() ?? '';
    if (path.isEmpty) return null;
    try {
      if (path.endsWith('.dart')) {
        final data = await _postMcp('dart_diagnostics', {
          'path': path,
          'workspace_dir': _agenticWorkspace,
        });
        if (data == null) return null;
        if (!data.containsKey('errors') && !data.containsKey('diags')) {
          return null; // unknown shape — don't claim anything
        }
        final diags = data['diags'];
        final errors = data['errors'];
        final hasErrors = (errors is int && errors > 0) ||
            (diags is List &&
                diags.any(
                  (d) => d is Map && d['severity'] == 'error',
                ));
        if (!hasErrors) {
          return '\n\n--- AUTO-VERIFICATION: PASSED (dart_diagnostics, 0 errors) ---';
        }
        final snippet = (data['stdout'] ?? '').toString();
        return '\n\n--- AUTO-VERIFICATION FAILED ---\n'
            'dart_diagnostics found errors in $path. Fix them now before continuing:\n'
            '${snippet.length > 4000 ? snippet.substring(0, 4000) : snippet}';
      }
      if (path.endsWith('.py')) {
        final data = await _postMcp('run_command', {
          'command': 'python -m py_compile ${_verifyShellQuote(path)}',
          'cwd': _agenticWorkspace,
        });
        if (data == null) return null;
        final code = data['exitCode'];
        if (code == 0) {
          return '\n\n--- AUTO-VERIFICATION: PASSED (py_compile) ---';
        }
        final err = (data['stderr'] ?? data['stdout'] ?? '').toString();
        return '\n\n--- AUTO-VERIFICATION FAILED ---\n'
            'py_compile errors in $path. Fix them now before continuing:\n'
            '${err.length > 3000 ? err.substring(0, 3000) : err}';
      }
      return null;
    } catch (_) {
      return null; // verification is best-effort, never blocks the loop
    }
  }

  Future<bool> _askFileMutationPermission(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!mounted) return false;
    final target = _fileMutationTarget(method, params);
    final preview = _fileMutationPreview(params);
    final diffPreview = await _fetchMutationPreview(method, params);
    if (!mounted) return false;

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
                PermissionInfoRow(label: 'Tool', value: method),
                const SizedBox(height: 8),
                PermissionInfoRow(label: 'Target', value: target),
                if (diffPreview != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Proposed changes',
                    style: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DiffViewerWidget(content: diffPreview),
                ],
                if (diffPreview == null && preview.isNotEmpty) ...[
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

  /// Run one web search query through the chat client and return the
  /// length-capped result text. Shared by the legacy XML path and the native
  /// JSON router so both produce identical output.
  Future<String> _executeWebSearchQuery(
    String query, {
    String? topic,
    String? timeRange,
    String? startDate,
    String? endDate,
  }) async {
    final searchResultRaw = await _chatClient
        .searchWeb(
          query,
          _searchSettings.provider,
          [_searchSettings.apiKey, ..._searchSettings.fallbackApiKeys],
          googleCx: _searchSettings.googleCx,
          topic: topic,
          timeRange: timeRange,
          startDate: startDate,
          endDate: endDate,
          customProviders: _searchSettings.customProviders,
        )
        .timeout(const Duration(seconds: 30));
    String searchResult = searchResultRaw;
    if (searchResult.length > 4000) {
      searchResult =
          searchResult.substring(0, 4000) +
          '\n\n...[truncated due to length]';
    }
    return searchResult;
  }

  /// Fetch a URL and return readable text: redirects followed, PDFs text-
  /// extracted, HTML boilerplate stripped, result length-capped. Errors come
  /// back as a readable string, never thrown. Shared by the legacy XML path
  /// and the native JSON router so both behave identically.
  Future<String> _fetchUrlText(String url) async {
    try {
      var targetUrl = url;
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'https://$targetUrl';
      }
      final client = HttpClient()
        ..findProxy = ((uri) => "DIRECT")
        ..connectionTimeout = const Duration(seconds: 15);

      var currentUrl = targetUrl;
      HttpClientResponse response;
      int redirectCount = 0;

      while (true) {
        final request = await client
            .getUrl(Uri.parse(currentUrl))
            .timeout(const Duration(seconds: 45));
        request.followRedirects = true;
        request.maxRedirects = 10;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        );
        request.headers.set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        );
        request.headers.set(
          HttpHeaders.acceptLanguageHeader,
          'en-US,en;q=0.9',
        );

        response = await request.close().timeout(
          const Duration(seconds: 45),
        );

        if ((response.isRedirect ||
                (response.statusCode >= 300 &&
                    response.statusCode < 400)) &&
            redirectCount < 8) {
          final location = response.headers.value(
            HttpHeaders.locationHeader,
          );
          if (location != null && location.isNotEmpty) {
            await response.drain<void>();
            redirectCount++;
            final resolvedUri = Uri.parse(currentUrl).resolve(location);
            currentUrl = resolvedUri.toString();
            continue;
          }
        }
        break;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }

      final isPdf =
          targetUrl.toLowerCase().endsWith('.pdf') ||
          (response.headers.contentType?.mimeType == 'application/pdf');

      String text = '';
      if (isPdf) {
        try {
          final bytesBuilder = BytesBuilder();
          await for (final chunk in response.timeout(
            const Duration(seconds: 60),
          )) {
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
            throw const FormatException(
              'No extractable text in PDF (possibly scanned/image-only)',
            );
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

        // Strip boilerplate/navigation tags to save tokens
        htmlBody = htmlBody.replaceAll(
          RegExp(r'<(nav|header|footer|aside)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false, dotAll: true),
          ' ',
        );

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

      var urlResult = text;
      if (urlResult.length > 8000) {
        // Truncate at a sentence boundary to avoid cutting mid-sentence
        final substring = urlResult.substring(0, 8000);
        final lastPeriod = substring.lastIndexOf('. ');
        final endIdx = lastPeriod > 6000 ? lastPeriod + 1 : 8000;
        urlResult =
            urlResult.substring(0, endIdx) +
            '\n\n...[truncated due to length]';
      }
      return urlResult;
    } catch (e) {
      return 'Error fetching URL: $e';
    }
  }

  // ── Native JSON tool-call extraction & routing helpers ──────────────────
  // The JSON-format prompt emits fenced ```json blocks containing either a
  // single call {"t": "tool", "a": {...}} or a batch {"calls": [...]}.
  // Returns all calls flattened, in order. Non-tool JSON blocks (prose code
  // samples, config snippets) are ignored: a block only counts when it is a
  // valid JSON object with a 't' key or a 'calls' array of such objects.
  List<Map<String, dynamic>> _findNativeToolCalls(String fullText) {
    final results = <Map<String, dynamic>>[];
    int searchFrom = 0;
    while (true) {
      final fenceStart = fullText.indexOf('```', searchFrom);
      if (fenceStart == -1) break;
      final lineEnd = fullText.indexOf('\n', fenceStart);
      if (lineEnd == -1) break;
      final contentStart = lineEnd + 1;
      final fenceEnd = fullText.indexOf('```', contentStart);
      if (fenceEnd == -1) {
        searchFrom = contentStart;
        break;
      }
      final raw = fullText.substring(contentStart, fenceEnd).trim();
      searchFrom = fenceEnd + 2;
      if (raw.isEmpty) continue;

      final decoded = _decodeRepairedToolJson(raw);
      if (decoded is Map<String, dynamic>) {
        _addDecodedToolCall(results, decoded);
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) _addDecodedToolCall(results, item);
        }
      }
    }

    final bareCalls = _findBareToolCalls(fullText);
    final existingTools = results.map((r) => r['t']?.toString()).toSet();
    for (final bc in bareCalls) {
      if (!existingTools.contains(bc['t']?.toString())) results.add(bc);
    }
    return results;
  }

  void _addDecodedToolCall(
    List<Map<String, dynamic>> results,
    Map<String, dynamic> parsed,
  ) {
    final calls = parsed['calls'];
    if (calls is List) {
      for (final c in calls) {
        if (c is Map<String, dynamic> && c['t'] != null) {
          results.add(c);
        } else if (c is Map<String, dynamic>) {
          results.add({
            't': 'error',
            'a': {'err': 'batch entry missing "t" field'},
          });
        }
      }
      return;
    }
    if (parsed['t'] != null) {
      results.add(parsed);
      return;
    }
    if (parsed['method'] != null) {
      final method = parsed['method'].toString();
      final params = parsed['params'];
      results.add({
        't': method,
        'a': params is Map<String, dynamic> ? params : <String, dynamic>{},
      });
    }
  }

  dynamic _decodeRepairedToolJson(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    s = s.replaceFirst(RegExp(r'\s*```$'), '');
    s = s.trim();

    final firstBrace = s.indexOf('{');
    final firstBracket = s.indexOf('[');
    if (firstBrace == -1 && firstBracket == -1) return null;
    final int start;
    if (firstBrace == -1) {
      start = firstBracket;
    } else if (firstBracket == -1) {
      start = firstBrace;
    } else {
      start = math.min(firstBrace, firstBracket);
    }

    final stack = <String>[];
    var inString = false;
    var esc = false;
    var end = -1;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        stack.add(c);
      } else if (c == '}' || c == ']') {
        if (stack.isEmpty) {
          end = -1;
          break;
        }
        final open = stack.removeLast();
        if ((open == '{' && c != '}') || (open == '[' && c != ']')) {
          end = -1;
          break;
        }
        if (stack.isEmpty) {
          end = i;
          break;
        }
      }
    }

    if (end == -1) {
      final suffix = stack.reversed.map((ch) => ch == '{' ? '}' : ']').join();
      s = s.substring(start) + suffix;
    } else {
      s = s.substring(start, end + 1);
    }

    s = _stripJsonComments(s);
    s = s.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!);
    s = s.replaceAllMapped(
      RegExp(r"'([^']*)':"),
      (m) => '"${m.group(1)}":',
    );
    s = s.replaceAllMapped(
      RegExp(r":\s*'([^']*)'"),
      (m) => ':"${m.group(1)}"',
    );
    s = s.replaceAllMapped(
      RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'),
      (m) => '${m.group(1)}"${m.group(2)}":',
    );
    s = s.replaceAll(RegExp(r'\bTrue\b'), 'true');
    s = s.replaceAll(RegExp(r'\bFalse\b'), 'false');
    s = s.replaceAll(RegExp(r'\bNone\b'), 'null');

    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  String _stripJsonComments(String s) {
    final out = StringBuffer();
    var inString = false;
    var esc = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        out.write(c);
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        out.write(c);
        continue;
      }
      if (c == '/' && i + 1 < s.length) {
        final next = s[i + 1];
        if (next == '/') {
          while (i < s.length && s[i] != '\n') i++;
          if (i < s.length) out.write('\n');
          continue;
        }
        if (next == '*') {
          i += 2;
          while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) {
            i++;
          }
          i++;
          continue;
        }
      }
      out.write(c);
    }
    return out.toString();
  }




  /// Fallback for models that emit tool JSON without a ```json fence:
  /// scans for bare {"t": ...} objects whose tool name is known. Plain JSON
  /// code samples or prose braces never match: the 't' value must be a
  /// registered tool name.
  List<Map<String, dynamic>> _findBareToolCalls(String text) {
    final results = <Map<String, dynamic>>[];
    for (final m in RegExp(r'\{\s*"t"\s*:').allMatches(text)) {
      final start = m.start;
      int depth = 0;
      bool inStr = false;
      bool esc = false;
      int end = -1;
      for (int i = start; i < text.length; i++) {
        final c = text[i];
        if (inStr) {
          if (esc) {
            esc = false;
          } else if (c == '\\') {
            esc = true;
          } else if (c == '"') {
            inStr = false;
          }
        } else {
          if (c == '"') {
            inStr = true;
          } else if (c == '{') {
            depth++;
          } else if (c == '}') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
      }
      if (end == -1) continue;
      try {
        final dynamic d = jsonDecode(text.substring(start, end + 1));
        if (d is Map<String, dynamic> &&
            _isKnownToolName(d['t']?.toString() ?? '')) {
          results.add(d);
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  bool _isKnownToolName(String t) => isKnownToolNameGlobal(t);


  /// Wraps bare known-tool JSON objects in ```json fences so the existing
  /// renderer shows them as tool cards instead of raw text.
  String _fenceBareToolCalls(String text) {
    if (!text.contains('"t"')) return text;
    if (text.contains('```json')) return text;
    final sb = StringBuffer();
    int last = 0;
    bool wrapped = false;
    for (final m in RegExp(r'\{\s*"t"\s*:').allMatches(text)) {
      final start = m.start;
      if (start < last) continue;
      int depth = 0;
      bool inStr = false;
      bool esc = false;
      int end = -1;
      for (int i = start; i < text.length; i++) {
        final c = text[i];
        if (inStr) {
          if (esc) {
            esc = false;
          } else if (c == '\\') {
            esc = true;
          } else if (c == '"') {
            inStr = false;
          }
        } else {
          if (c == '"') {
            inStr = true;
          } else if (c == '{') {
            depth++;
          } else if (c == '}') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
      }
      if (end == -1) continue;
      final candidate = text.substring(start, end + 1);
      bool known = false;
      try {
        final dynamic d = jsonDecode(candidate);
        known = d is Map<String, dynamic> &&
            _isKnownToolName(d['t']?.toString() ?? '');
      } catch (_) {}
      if (!known) continue;
      sb.write(text.substring(last, start));
      sb.write('\n```json\n');
      sb.write(candidate);
      sb.write('\n```\n');
      last = end + 1;
      wrapped = true;
    }
    if (!wrapped) return text;
    sb.write(text.substring(last));
    return sb.toString();
  }

  /// True when a native C++ tool call mutates files and therefore needs the
  /// user permission prompt (read-only tools never prompt).
  bool _nativeIsFileMutation(String toolName, Map<String, dynamic> args) {
    switch (toolName) {
      case 'patch':
      case 'edit':
      case 'create_file':
      case 'create_directory':
      case 'cut':
      case 'extract':
      case 'fileops':
      case 'undo':
        return true;
      case 'git':
        final action = (args['a'] ?? '').toString();
        return action == 'commit' ||
            action == 'ci' ||
            action == 'revert_file' ||
            action == 'rv' ||
            action == 'undo_last_commit' ||
            action == 'uc' ||
            action == 'raw' ||
            action == 'r';
      default:
        return false;
    }
  }

  /// Map native tool arg names onto the legacy permission-dialog keys so
  /// _askFileMutationPermission/_allPathsTrusted can find the paths.
  Map<String, dynamic> _nativePermParams(
    String toolName,
    Map<String, dynamic> args,
  ) {
    final perm = Map<String, dynamic>.from(args);
    String? f;
    String? to;
    if (toolName == 'patch' && args['p'] is List) {
      final first = (args['p'] as List).firstWhere(
        (e) => e is Map && e['f'] != null,
        orElse: () => <String, dynamic>{},
      );
      if (first is Map) {
        f = first['f']?.toString();
        to = first['to']?.toString();
      }
    } else if (toolName == 'edit' && args['e'] is List) {
      final first = (args['e'] as List).firstWhere(
        (e) => e is Map && e['f'] != null,
        orElse: () => <String, dynamic>{},
      );
      if (first is Map) {
        f = first['f']?.toString();
        to = first['to']?.toString();
      }
    } else if (toolName == 'fileops' && args['ops'] is List) {
      final first = (args['ops'] as List).firstWhere(
        (e) => e is Map && e['f'] != null,
        orElse: () => <String, dynamic>{},
      );
      if (first is Map) {
        f = first['f']?.toString();
        to = first['to']?.toString();
      }
    } else {
      f = args['f']?.toString();
      to = args['to']?.toString();
    }
    if (f != null && f.isNotEmpty) perm['path'] = f;
    if (to != null && to.isNotEmpty) perm['dest'] = to;
    if (toolName == 'create_directory') {
      final p = args['p']?.toString();
      if (p != null && p.isNotEmpty) perm['path'] = p;
    }
    return perm;
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
          RegExp(
            r'!\[[^\]]*\]\([^)]*\.svg(?:\?[^)]*)?\)',
            caseSensitive: false,
          ),
          '',
        );
  }

  Future<String> _persistResearchReport(String fileName, String content) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  String _updateResearchStateInText(
    String oldText,
    Map<String, dynamic> stateMap,
  ) {
    final newStateStr = researchStateFence(stateMap);
    final span = findFenceWithKeys(oldText, ['research_state']);
    if (span == null) {
      return oldText.isEmpty ? newStateStr : '$oldText\n\n$newStateStr';
    }
    return oldText.substring(0, span['start'] as int) +
        newStateStr +
        oldText.substring(span['end'] as int);
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
      case 'patch_file_rich':
        return '✏️  Patching ${shortPath(p('path'))}';
      case 'replace_lines':
      case 'replace_lines_rich':
        return '✏️  Replacing lines ${p('start_line')}–${p('end_line')} in ${shortPath(p('path'))}';
      case 'insert_lines':
      case 'insert_lines_rich':
        return '✏️  Inserting after line ${p('after_line')} in ${shortPath(p('path'))}';
      case 'delete_lines':
      case 'delete_lines_rich':
        return '🗑️  Deleting lines ${p('start_line')}–${p('end_line')} in ${shortPath(p('path'))}';
      case 'write_file_rich':
      case 'file_write':
        return '✏️  Writing ${shortPath(p('path'))}';
      case 'search_rich':
      case 'file_search':
      case 'code_search':
        return '🔎 Searching: "${p('query')}${p('pattern')}" in ${shortPath(p('path'))}';
      case 'file_outline':
      case 'file_outline_rich':
        return '🗂️  Outline: ${shortPath(p('path'))}';
      case 'tree':
      case 'tree_rich':
        return '📂 Tree: ${shortPath(p('path'))}';
      case 'diff_files':
      case 'diff_files_rich':
        return '🔍 Diffing files…';
      case 'list_trash':
        return '🗑️  Listing trash…';
      case 'restore_trash':
        return '♻️  Restoring ${p('name')} from trash';
      case 'tool_help':
        return '📚 Loading tool reference…';
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
      case 'find_files':
        return '🔎 Finding: ${p('pattern')} in ${shortPath(p('path'))}';
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
      case 'read':
        final r = params['r'];
        if (r is List && r.isNotEmpty) {
          final first = r.first;
          if (first is Map) return '📖 Reading ${shortPath(first['f']?.toString() ?? '')}';
        }
        return '📖 Reading…';
      case 'search':
        final q = params['q'] ?? params['queries'];
        if (q is List && q.isNotEmpty) return '🔎 Searching: "${q.first}"';
        return '🔎 Searching…';
      case 'patch':
        final patches = params['p'];
        if (patches is List && patches.isNotEmpty) {
          final first = patches.first;
          if (first is Map) return '✏️ Patching ${shortPath(first['f']?.toString() ?? '')}';
        }
        return '✏️ Patching…';
      case 'edit':
        final edits = params['e'];
        if (edits is List && edits.isNotEmpty) {
          final first = edits.first;
          if (first is Map) return '✏️ Editing ${shortPath(first['f']?.toString() ?? '')}';
        }
        return '✏️ Editing…';
      case 'sh':
        final cmd = p('cmd');
        final short = cmd.length > 45 ? '${cmd.substring(0, 42)}…' : cmd;
        return '🔧 Running: $short';
      case 'git':
        final action = p('a');
        return '📊 Git $action…';
      case 'list':
        return '📂 Listing ${shortPath(p('p'))}';
      case 'find':
        return '🔎 Finding: ${p('glob') ?? p('g')}';
      case 'outline':
        return '🗂️ Outline: ${shortPath(p('f'))}';
      case 'recent':
        return '🕒 Recent files…';
      case 'undo':
        return '↩️ Undoing ${shortPath(p('f'))}';
      case 'create_file':
        return '📝 Creating ${shortPath(p('f'))}';
      case 'create_directory':
      case 'mkdir':
        return '📁 Creating dir ${shortPath(p('p'))}';
      case 'cut':
        return '✂️ Cutting ${shortPath(p('f'))}';
      case 'extract':
        return '🔧 Extracting ${p('name')} from ${shortPath(p('f'))}';
      case 'fileops':
        return '📂 File operations…';
      case 'diagnostics':
        final dcmd = p('cmd');
        final dshort = dcmd.length > 45 ? '${dcmd.substring(0, 42)}…' : dcmd;
        return '🔍 Diagnostics: $dshort';
      case 'py':
        return '🐍 Python: ${p('m')}';
      case 'todo_create':
        return '📋 Creating todo list…';
      case 'todo_done':
        return '✅ Task ${p('n')} done';
      case 'version':
        return 'ℹ️ Version check…';
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
    final stateFence = findFenceWithKeys(message.text, ['research_state']);
    if (stateFence == null) return;

    try {
      final stateMap = editedStateMap ??
          (stateFence['json'] as Map<String, dynamic>)['research_state']
              as Map<String, dynamic>;
      stateMap['status'] = 'running';

      if (!_searchSettings.enabled) {
        setState(() {
          _sendingSessionIds.add(_sessions[sessionIndex].id);
          final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
          msgs[messageIndex] = ChatMessage(
            role: MessageRole.assistant,
            text: message.text.replaceRange(
              stateFence['start'] as int,
              stateFence['end'] as int,
              researchStateFence(stateMap),
            ),
            reasoning: message.reasoning,
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(messages: msgs);
        });
        _appendSystemMessage(
          'Deep Research requires Web Search to be enabled. Enable it in Settings → Features → Web Search.',
        );
        _sendingSessionIds.remove(_sessions[sessionIndex].id);
        return;
      }

      setState(() {
        _sendingSessionIds.add(_sessions[sessionIndex].id);
        final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
        msgs[messageIndex] = ChatMessage(
          role: MessageRole.assistant,
          text: message.text.replaceRange(
            stateFence['start'] as int,
            stateFence['end'] as int,
            researchStateFence(stateMap),
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

  // Bound state persisted into the research_state JSON fence; all limits are UTF-8 bytes.
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
      final content =
          data?['content'] ??
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
    // IMPROVEMENT: Search dedup across phases + stable run ID for checkpointing
    final Set<String> executedQueries = {};
    final String runId = 'run_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await _resetDeepResearch();

      final activeSession = _sessions[sessionIndex];
      final prompt = activeSession.messages[messageIndex - 1].text;

      // ── STAGE 1: PLANNING ──
      // Reuse an existing usable plan (UI-edited / resume) instead of re-calling the planner.
      final List<Map<String, dynamic>> steps;
      if (DeepResearchHelpers.hasUsablePlan(stateMap)) {
        steps = DeepResearchHelpers.normalizeSteps(stateMap['steps'] as List?);
        stateMap['steps'] = steps;
        stateMap['status'] = 'running';
        stateMap.remove('regenerate_plan');
        _publishResearchState(sessionIndex, messageIndex, stateMap);
      } else {
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
            text:
                "Analyze the user's research request and output a detailed research plan. "
                "Research Request: \"$prompt\"\n\n"
                "Current date and time: ${_deepResearchNow()}. Plan for information that is current as of this timestamp. "
                "For time-sensitive topics, require each phase to find and verify the latest available primary or authoritative sources.",
          ),
        ];

        String planText = '';
        String plannerReasoning = '';
        final plannerStream = _chatClient.sendChatStream(
          provider: provider,
          settings: settings,
          model: model,
          messages: _compactHistoryForApi(
            plannerMessages,
            plannerMessages.length,
          ),
          studyModeEnabled: _studyModeEnabled,
        );

        await for (final chunk in plannerStream) {
          if (chunk.startsWith('[REASONING]')) {
            plannerReasoning += chunk.substring(11);
          } else {
            var textChunk = chunk;
            if (textChunk.contains('<think>') ||
                textChunk.contains('<reasoning>') ||
                textChunk.contains('<thought>')) {
              textChunk = textChunk.replaceAll(
                RegExp(
                  r'<think>|<reasoning>|<thought>|</think>|</reasoning>|</thought>',
                ),
                '',
              );
            }
            planText += textChunk;
          }
        }

        final plannedSteps = <Map<String, dynamic>>[];
        final planFence = findFenceWithKeys(planText, ['research_plan']);
        final rawPlan = planFence == null
            ? null
            : (planFence['json'] as Map<String, dynamic>)['research_plan'];
        final phaseListRaw = rawPlan is List
            ? rawPlan
            : (rawPlan is Map<String, dynamic> && rawPlan['phases'] is List
                  ? rawPlan['phases'] as List
                  : const <dynamic>[]);
        final phaseList = phaseListRaw.length > 12
            ? phaseListRaw.sublist(0, 12)
            : phaseListRaw;

        int stepIdx = 1;
        for (final entry in phaseList) {
          if (entry is! Map) continue;
          // Keep full queryText; derive a short UI title when absent.
          final queryText = (entry['prompt'] ?? entry['title'] ?? '')
              .toString()
              .trim();
          var derivedTitle = (entry['title'] ?? '').toString().trim();
          if (derivedTitle.isEmpty) {
            derivedTitle = queryText
                .split(RegExp(r' - | \| | success:', caseSensitive: false))
                .first
                .trim();
          }
          final title = derivedTitle.isNotEmpty
              ? derivedTitle
              : 'Phase $stepIdx';
          plannedSteps.add({
            'id': 'step_$stepIdx',
            'title': title,
            'query_text': queryText,
            'status': 'pending',
            'content': '',
            'events': <Map<String, dynamic>>[],
          });
          stepIdx++;
        }

        if (plannedSteps.isEmpty) {
          final parts = prompt.split(RegExp(r'[;,\n]'));
          for (var i = 0; i < parts.length && i < 6; i++) {
            final p = parts[i].trim();
            if (p.isEmpty) continue;
            plannedSteps.add({
              'id': 'step_${i + 1}',
              'title': p.length > 50 ? '${p.substring(0, 47)}…' : p,
              'query_text': p,
              'status': 'pending',
              'content': '',
              'events': <Map<String, dynamic>>[],
            });
          }
          if (plannedSteps.isEmpty) {
            plannedSteps.add({
              'id': 'step_1',
              'title': 'General Research',
              'query_text': prompt,
              'status': 'pending',
              'content': '',
              'events': <Map<String, dynamic>>[],
            });
          }
        }

        steps = plannedSteps;
        stateMap['steps'] = steps;
        stateMap['status'] = 'running';
        stateMap.remove('regenerate_plan');
        _publishResearchState(sessionIndex, messageIndex, stateMap);
      }

      // ── STAGE 2: MULTI-AGENT EXECUTION ──
      final int maxConcurrentFetchCalls = 6;
      final Duration globalTimeBudget = const Duration(minutes: 60);
      final DateTime startTime = DateTime.now();
      int cumulativeFacts = 0;
      int cumulativeFindings = 0;

      DateTime getGlobalElapsed() {
        return DateTime.now();
      }

      final List<Map<String, dynamic>> phaseFacts = [];
      final List<Map<String, dynamic>> phaseFindings = [];
      final List<Map<String, dynamic>> phaseSkippedPdfs = [];
      final List<Map<String, dynamic>> phaseFailedFetches = [];
      final StringBuffer crossPhaseContext = StringBuffer();

      for (int i = 0; i < steps.length; i++) {
        final stageId = steps[i]['id'] as String;
        final phaseTitle = steps[i]['title'] as String;
        final queryText = steps[i]['query_text'] as String;
        final phaseCurrentTime = _deepResearchNow();
        // Keep each temp.json phase scoped to evidence gathered for that phase.
        phaseFacts.clear();
        phaseFindings.clear();
        phaseSkippedPdfs.clear();
        phaseFailedFetches.clear();

        // Skip already-completed phases when resuming a usable plan.
        if (steps[i]['status'] == 'completed') {
          continue;
        }

        if (startTime.add(globalTimeBudget).isBefore(DateTime.now())) {
          steps[i]['status'] = 'failed';
          steps[i]['error'] =
              'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
          _publishResearchState(sessionIndex, messageIndex, stateMap);
          continue;
        }

        steps[i]['status'] = 'running';
        _publishResearchState(sessionIndex, messageIndex, stateMap);

        // IMPROVEMENT: Per-phase timeout (4 minutes max per phase)
        final phaseStartTime = DateTime.now();
        const phaseTimeout = Duration(minutes: 4);

        final String Function({
          required String kind,
          required String tool,
          String? query,
          String? url,
        })
        beginResearchEvent =
            ({
              required String kind,
              required String tool,
              String? query,
              String? url,
            }) {
              final eventId = const Uuid().v4();
              final newEvent = {
                'id': eventId,
                'kind': kind,
                'tool': tool,
                'status': 'running',
                if (query != null) 'query': query,
                if (url != null) 'url': url,
                'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
              };

              // Mutate stateMap outside setState; single publish triggers one rebuild.
              final idx = (stateMap['steps'] as List).indexWhere(
                (s) => s['id'] == stageId,
              );
              if (idx != -1) {
                final evts = List<Map<String, dynamic>>.from(
                  stateMap['steps'][idx]['events'] ?? [],
                );
                evts.add(newEvent);
                if (evts.length > 50) {
                  evts.removeRange(0, evts.length - 50);
                }
                stateMap['steps'][idx]['events'] = evts;
              }
              _publishResearchState(sessionIndex, messageIndex, stateMap);
              return eventId;
            };

        final void Function(
          String eventId, {
          required String status,
          required Stopwatch stopwatch,
          Map<String, dynamic>? details,
          String? error,
        })
        finishResearchEvent =
            (
              String eventId, {
              required String status,
              required Stopwatch stopwatch,
              Map<String, dynamic>? details,
              String? error,
            }) {
              stopwatch.stop();
              // Mutate stateMap outside setState; single publish triggers one rebuild.
              final idx = (stateMap['steps'] as List).indexWhere(
                (s) => s['id'] == stageId,
              );
              if (idx != -1) {
                final evts = List<Map<String, dynamic>>.from(
                  stateMap['steps'][idx]['events'] ?? [],
                );
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
              _publishResearchState(sessionIndex, messageIndex, stateMap);
            };

        final void Function(
          String eventId,
          String status, {
          Map<String, dynamic>? details,
        })
        updateResearchEventStatus =
            (String eventId, String status, {Map<String, dynamic>? details}) {
              // Mutate stateMap outside setState; single publish triggers one rebuild.
              final idx = (stateMap['steps'] as List).indexWhere(
                (s) => s['id'] == stageId,
              );
              if (idx != -1) {
                final evts = List<Map<String, dynamic>>.from(
                  stateMap['steps'][idx]['events'] ?? [],
                );
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
              _publishResearchState(sessionIndex, messageIndex, stateMap);
            };

        final List<ChatMessage> stepMessages = [
          const ChatMessage(
            role: MessageRole.system,
            text: DeepResearchPrompts.researchSystemPrompt,
          ),
          ChatMessage(
            role: MessageRole.user,
            text:
                "Your current research stage is: \"$phaseTitle\"\n"
                "Focus Area Instructions: $queryText\n\n"
                "${crossPhaseContext.length > 0 ? '━━ PREVIOUS PHASE RESULTS (MANDATORY RESEARCH TARGETS) ━━\nBelow are the entities, facts, and sources discovered in earlier phases. Your current phase MUST build on these:\n- Use the EXACT entity names listed below as your search queries (e.g. search \"[model name] specs\" not \"coding model specs\").\n- Use read_url on the source URLs listed below if they contain information relevant to your current phase.\n- NEVER search for generic terms when specific entities were already discovered. Search for the specific entity + your phase\'s focus.\n- If a previous phase found models A, B, C, your phase about specs should search \"A specs\", \"B specs\", \"C specs\" — not \"coding model specs\".\n\n$crossPhaseContext\n' : ''}"
                "━━ RECENCY MANDATE ━━\n"
                "Current date and time: $phaseCurrentTime.\n"
                "You are researching for a reader who needs CURRENT information. "
                "For ANY time-sensitive claim (versions, prices, scores, releases, statistics):\n"
                "1. Search with time_range=\"month\" or time_range=\"week\" to find the latest data.\n"
                "2. Check the publication date on every source you read.\n"
                "3. If the newest source you find is >6 months old, explicitly note this.\n"
                "4. NEVER state a fact from your training data. If you haven't found it via search/fetch, you don't know it.\n\n"
                "Please formulate search queries or read specific URLs to gather evidence. "
                "Cite specific metrics, comparisons, and sources in your final response. "
                "When you are finished, write a concise summary of your findings and emit {\"t\":\"step_complete\"} in its own ```json block.",
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

        while (!stepDone && loopCount < 20) {
          if (startTime.add(globalTimeBudget).isBefore(DateTime.now())) {
            stepDone = true;
            stepFailed = true;
            stepFailure =
                'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
            break;
          }
          if (phaseStartTime.add(phaseTimeout).isBefore(DateTime.now())) {
            stepDone = true;
            stepFailure =
                'Phase exceeded ${phaseTimeout.inMinutes}-minute timeout. Proceeding with partial results.';
            break;
          }
          if (!mounted) return;
          if (!_sendingSessionIds.contains(_sessions[sessionIndex].id)) {
            stepDone = true;
            stepFailed = true;
            stepFailure = 'Research cancelled by user.';
            break;
          }
          loopCount++;

          String responseText = '';
          String reasoningText = '';
          var isThinking = false;
          var researchStreamCharCount = 0;

          try {
            final stream = _chatClient.sendChatStream(
              provider: provider,
              settings: settings,
              model: model,
              messages: _compactHistoryForApi(
                stepMessages,
                stepMessages.length,
              ),
              studyModeEnabled: _studyModeEnabled,
            );

            await for (final chunk in stream) {
            if (chunk.startsWith('[REASONING]')) {
              reasoningText += chunk.substring(11);
              researchStreamCharCount += chunk.length - 11;
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
                  textChunk = parts.length > 1
                      ? parts.sublist(1).join(tag)
                      : '';
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
                  textChunk = parts.length > 1
                      ? parts.sublist(1).join(tag)
                      : '';
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

            final unrecognizedErrors = <Map<String, dynamic>>[];
            // JSON tool calls are extracted directly from fenced ```json blocks
            // in the dispatch loop — no preprocessing/reinterpretation needed.
            final preprocessedText = responseText;

            // JSON tool calls: the research agent uses the same fenced
            // ```json protocol as the chat agent (web_search / read_url /
            // step_complete). Parameters live inside "a" — no XML parsing.
            final nativeCalls = _findNativeToolCalls(preprocessedText);
            final searchCalls = nativeCalls
                .where((c) => c['t'] == 'web_search' || c['t'] == 'search_web')
                .toList();
            final readUrlCalls = nativeCalls
                .where((c) => c['t'] == 'read_url')
                .toList();
            final bool stepCompleteRequested = nativeCalls.any(
              (c) => c['t'] == 'step_complete',
            );

            bool isMalformed = unrecognizedErrors.isNotEmpty;

            if (isMalformed) {
              consecutiveMalformedTags++;
              final eventWatch = Stopwatch()..start();
              final eventId = beginResearchEvent(
                kind: 'error',
                tool: 'malformed_tag',
              );
              final String errMessage = unrecognizedErrors.isNotEmpty
                  ? unrecognizedErrors
                        .map((e) => e['error']?.toString() ?? '')
                        .join('; ')
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
                stepFailure =
                    'Step failed after $consecutiveMalformedTags consecutive malformed tool calls.';
                break;
              }
              stepMessages.add(
                const ChatMessage(
                  role: MessageRole.user,
                  text:
                      'Error: Malformed or unclosed tool call tags detected. Please check tag syntax.',
                ),
              );
              continue;
            } else {
              consecutiveMalformedTags = 0;
            }

            if (stepCompleteRequested) {
              if (phaseFacts.isEmpty && phaseFindings.isEmpty && webSearchCount == 0) {
                stepMessages.add(
                  const ChatMessage(
                    role: MessageRole.user,
                    text: 'You emitted step_complete without any searches or evidence. The grounding rule is non-negotiable: you must search and read at least one source before completing a phase. Emit a web_search call now.',
                  ),
                );
                continue;
              }
              final contentClean = responseText
                  .replaceAll(
                    RegExp(
                      r'```json\s*\n\s*\{\s*"t"\s*:\s*"step_complete"\s*(,\s*"a"\s*:\s*\{[\s\S]*?\})?\s*\}\s*\n```',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .trim();
              stepContent = stepContent.isEmpty
                  ? contentClean
                  : '$stepContent\n\n$contentClean';
              stepDone = true;
            } else if (searchCalls.isNotEmpty) {
              final List<Future<String>> searchFutures = [];
              final List<String> eventIds = [];
              final List<Stopwatch> stopwatches = [];
              final List<String> queries = [];
              final List<Map<String, String>> searchAttrsList = [];

              for (final call in searchCalls) {
                final a = call['a'] is Map<String, dynamic>
                    ? call['a'] as Map<String, dynamic>
                    : <String, dynamic>{};
                final List<String> callQueries = [];
                final qList = a['queries'] ?? a['q_list'];
                if (qList is List) {
                  for (final item in qList) {
                    final s = item.toString().trim();
                    if (s.isNotEmpty) callQueries.add(s);
                  }
                }
                final singleQ = (a['q'] ?? a['query'] ?? '').toString().trim();
                if (callQueries.isEmpty && singleQ.isNotEmpty) {
                  callQueries.add(singleQ);
                }
                if (callQueries.length > 4) {
                  callQueries.removeRange(4, callQueries.length);
                }
                final attrs = {
                  for (final key in const [
                    'topic',
                    'time_range',
                    'start_date',
                    'end_date',
                    'search_depth',
                  ])
                    if (a[key] != null) key: a[key].toString(),
                };
                for (final cq in callQueries) {
                  queries.add(cq);
                  searchAttrsList.add(attrs);
                  final eventWatch = Stopwatch()..start();
                  stopwatches.add(eventWatch);
                  final eventId = beginResearchEvent(
                    kind: 'search',
                    tool: 'web_search',
                    query: cq,
                  );
                  eventIds.add(eventId);
                }
                final trailEntry = jsonEncode({'t': 'web_search', 'a': a});
                stepContent = stepContent.isEmpty
                    ? trailEntry
                    : '$stepContent\n\n$trailEntry';
              }

              steps[i]['content'] = stepContent;
              _publishResearchState(sessionIndex, messageIndex, stateMap);

              bool searchCapHit = false;
              for (var k = 0; k < queries.length; k++) {
                final query = queries[k];
                final attrs = searchAttrsList[k];
                final normQuery = _normalizeQueryOrUrl(query);

                if (executedQueries.contains(normQuery)) {
                  searchFutures.add(Future.value(
                    'This exact query was already executed earlier in this research run. '
                    'Refer to the previous search results instead of repeating this search. '
                    'If you need different information, reformulate your query with different terms.',
                  ));
                  finishResearchEvent(
                    eventIds[k],
                    status: 'done',
                    stopwatch: stopwatches[k],
                    details: {'query': query, 'deduplicated': true},
                  );
                  continue;
                }
                executedQueries.add(normQuery);

                if (webSearchCount >= 20) {
                  searchCapHit = true;
                  final limitMsg =
                      'Search limit reached for this phase (20/20 used). No further web_search calls are available this phase — proceed to reflection/summary with what has been gathered, or move to the next phase.';
                  searchFutures.add(Future.value('Error: $limitMsg'));
                  finishResearchEvent(
                    eventIds[k],
                    status: 'error',
                    stopwatch: stopwatches[k],
                    error: 'Web search limit exceeded.',
                  );
                  continue;
                }

                webSearchCount++;
                if (stepSearchCache.containsKey(normQuery)) {
                  searchFutures.add(
                    Future.value(
                      'Web search already attempted in this phase.\n\n${stepSearchCache[normQuery]}',
                    ),
                  );
                } else {
                  searchFutures.add(() async {
                    try {
                      final res = await _chatClient
                          .searchWeb(
                            query,
                            _searchSettings.provider,
                            [
                              _searchSettings.apiKey,
                              ..._searchSettings.fallbackApiKeys,
                            ],
                            googleCx: _searchSettings.googleCx,
                            topic: attrs['topic'],
                            timeRange:
                                attrs['time_range'] ?? attrs['time-range'],
                            startDate:
                                attrs['start_date'] ?? attrs['start-date'],
                            endDate: attrs['end_date'] ?? attrs['end-date'],
                            searchDepth:
                                attrs['search_depth'] ??
                                attrs['search-depth'] ??
                                'basic',
                          )
                          .timeout(const Duration(seconds: 60));
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

              for (var k = 0; k < queries.length; k++) {
                final query = queries[k];
                final eventId = eventIds[k];
                final eventWatch = stopwatches[k];
                final searchResultRaw = searchResults[k];
                final bool isCapError = searchResultRaw.startsWith(
                  'Error: Web search cap',
                );
                final bool isDup = searchResultRaw.startsWith(
                  'Web search already attempted',
                );

                String searchResult = searchResultRaw;
                if (searchResult.length > 4000) {
                  searchResult =
                      searchResult.substring(0, 4000) + '\n\n...[truncated]';
                }
                final searchError =
                    (searchResult.startsWith('Web search failed:') ||
                        isCapError)
                    ? searchResult
                    : null;
                final resultMatches = RegExp(
                  r'(?:^|\n)[-*\d.]+\s*\[?([^\]\n]+?)\]?\s*[(:-]\s*(https?://[^\s)\]]+)',
                  multiLine: true,
                ).allMatches(searchResult);

                if (!isCapError) {
                  finishResearchEvent(
                    eventId,
                    status: searchError == null ? 'done' : 'error',
                    stopwatch: isDup ? Stopwatch() : eventWatch,
                    details: {
                      'result_count': resultMatches.length,
                      if (isDup) 'already_attempted': true,
                      'result_payload': _compactSearchPayload(
                        resultMatches.map(
                          (match) => {
                            'title': match.group(1) ?? '',
                            'url': match.group(2) ?? '',
                            'snippet': '',
                          },
                        ),
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
                combinedResults.writeln(
                  "Search results for '$query':\n$searchResult\n",
                );
              }

              stepMessages.add(
                ChatMessage(
                  role: MessageRole.user,
                  text: combinedResults.toString().trim(),
                ),
              );
            } else if (readUrlCalls.isNotEmpty) {
              final availableRam = await _getSystemAvailableRamBytes();
              final bool lowMemory = availableRam < 300 * 1024 * 1024;
              final int activeFetchConcurrency = lowMemory
                  ? 1
                  : maxConcurrentFetchCalls;

              final List<String> eventIds = [];
              final List<Stopwatch> stopwatches = [];
              final List<String> urls = [];
              // Pre-classify each URL and reserve read_url slots synchronously so
              // N parallel tags cannot race past the 5/phase cap. PDF heuristics
              // and cache hits do not consume the fetch budget.
              final List<bool> overLimit = [];
              const int readUrlLimit = 5;

              bool looksLikePdfUrl(String u) {
                final lower = u.toLowerCase();
                return lower.contains('.pdf') || lower.contains('/pdf/');
              }

              for (final call in readUrlCalls) {
                final url = ((call['a'] is Map<String, dynamic>)
                        ? ((call['a'] as Map<String, dynamic>)['url'] ?? '')
                            .toString()
                        : '')
                    .trim();
                urls.add(url);
                final eventWatch = Stopwatch()..start();
                stopwatches.add(eventWatch);
                final eventId = beginResearchEvent(
                  kind: 'fetch',
                  tool: 'read_url',
                  url: url,
                );
                eventIds.add(eventId);
                final trailEntry = jsonEncode({'t': 'read_url', 'a': call['a']});
                stepContent = stepContent.isEmpty
                    ? trailEntry
                    : '$stepContent\n\n$trailEntry';

                var targetPreview = url.trim();
                if (!targetPreview.startsWith('http')) {
                  targetPreview = 'https://$targetPreview';
                }
                final normPreview = _normalizeQueryOrUrl(url);
                final isPdfPreview = looksLikePdfUrl(targetPreview);
                final isCacheHit = runFetchedUrls.contains(normPreview);

                if (isPdfPreview || isCacheHit) {
                  // No budget slot consumed for skips / re-reads.
                  overLimit.add(false);
                } else if (readUrlCount >= readUrlLimit) {
                  overLimit.add(true);
                } else {
                  // Reserve the slot synchronously before Future.wait.
                  readUrlCount++;
                  overLimit.add(false);
                }
              }
              steps[i]['content'] = stepContent;
              _publishResearchState(sessionIndex, messageIndex, stateMap);

              final List<String> urlResults = List.filled(urls.length, '');
              final fetchSemaphore = SimpleSemaphore(activeFetchConcurrency);
              var fetchTimeBudgetExceeded = false;

              // Dedup helper for cache-hit merges (metric|subject|value).
              String factDedupKey(Map item) =>
                  '${item['metric']}|${item['subject']}|${item['value']}';

              // Batch summarization: collect fetched texts, summarize in ONE LLM call
              final Map<String, String> fetchedTexts = {};
              final Map<String, String> fetchedEventIds = {};
              final Map<String, Stopwatch> fetchedStopwatches = {};

              await Future.wait(
                Iterable<int>.generate(urls.length).map((idx) async {
                  final url = urls[idx];
                  final eventId = eventIds[idx];
                  final eventWatch = stopwatches[idx];
                  var targetUrl = url.trim();
                  if (!targetUrl.startsWith('http')) {
                    targetUrl = 'https://$targetUrl';
                  }
                  final normUrl = _normalizeQueryOrUrl(url);

                  // Global time budget: cancel remaining fetches if exceeded.
                  if (fetchTimeBudgetExceeded ||
                      startTime
                          .add(globalTimeBudget)
                          .isBefore(DateTime.now())) {
                    fetchTimeBudgetExceeded = true;
                    finishResearchEvent(
                      eventId,
                      status: 'error',
                      stopwatch: eventWatch,
                      error:
                          'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.',
                    );
                    urlResults[idx] =
                        'Error: Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
                    return;
                  }

                  if (overLimit[idx]) {
                    const capMsg =
                        'Read URL limit reached for this phase (5/5 used). No further read_url calls are available this phase — proceed to reflection/summary with what has been gathered, or move to the next phase.';
                    finishResearchEvent(
                      eventId,
                      status: 'error',
                      stopwatch: eventWatch,
                      error: 'read_url limit reached',
                    );
                    urlResults[idx] = 'Error: $capMsg';
                    return;
                  }

                  // Client-side PDF heuristic; bridge status skipped_pdf is still source of truth.
                  if (looksLikePdfUrl(targetUrl)) {
                    final skipMsg =
                        'Skipped PDF URL: $targetUrl (PDFs are excluded from Deep Research)';
                    phaseSkippedPdfs.add({
                      'url': targetUrl,
                      'reason': 'PDF files are excluded (by extension)',
                    });
                    runFetchedUrls.add(normUrl);
                    runUrlSummaries[normUrl] = {
                      'facts': [],
                      'findings': [],
                      'isPdf': true,
                      'skipped': true,
                    };

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
                        'result_payload': {'summary': 'Skipped PDF URL'},
                      },
                    );
                    urlResults[idx] = skipMsg;
                    return;
                  }

                  if (runFetchedUrls.contains(normUrl)) {
                    final cached = runUrlSummaries[normUrl]!;
                    if (cached['skipped'] == true) {
                      phaseSkippedPdfs.add({
                        'url': targetUrl,
                        'reason': 'PDF files are excluded (cache hit)',
                      });
                    } else {
                      final cachedFacts = List<Map<String, dynamic>>.from(
                        cached['facts'] ?? [],
                      );
                      final cachedFindings = List<Map<String, dynamic>>.from(
                        cached['findings'] ?? [],
                      );
                      final existingKeys = phaseFacts.map(factDedupKey).toSet();
                      for (final fact in cachedFacts) {
                        if (existingKeys.add(factDedupKey(fact))) {
                          phaseFacts.add(fact);
                        }
                      }
                      // Findings: avoid exact text+source dupes on re-fetch.
                      final existingFindingKeys = phaseFindings
                          .map((f) => '${f['text']}|${f['source']}')
                          .toSet();
                      for (final finding in cachedFindings) {
                        final key = '${finding['text']}|${finding['source']}';
                        if (existingFindingKeys.add(key)) {
                          phaseFindings.add(finding);
                        }
                      }
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
                        'parse_format': cached['isPdf'] == true
                            ? 'skipped_pdf'
                            : 'html',
                        'already_attempted': true,
                        'facts_count': cached['facts']?.length ?? 0,
                        'findings_count': cached['findings']?.length ?? 0,
                        'result_payload': {
                          'summary': 'Already read & summarized (cache hit)',
                        },
                      },
                    );
                    urlResults[idx] = 'Already read & summarized (cache hit).';
                    return;
                  }

                  String text = '';
                  bool isPdfResponse = false;
                  bool fetchFailed = false;

                  // The bridge owns network retrieval, URL policy, and cleaning.
                  // Keeping this result on the server side avoids a second, divergent
                  // fetch implementation in Flutter.
                  try {
                    // Re-check budget immediately before the network call.
                    if (startTime
                        .add(globalTimeBudget)
                        .isBefore(DateTime.now())) {
                      fetchTimeBudgetExceeded = true;
                      finishResearchEvent(
                        eventId,
                        status: 'error',
                        stopwatch: eventWatch,
                        error:
                            'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.',
                      );
                      urlResults[idx] =
                          'Error: Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
                      return;
                    }
                    final fetched = await fetchSemaphore.run(() async {
                      if (fetchTimeBudgetExceeded ||
                          startTime
                              .add(globalTimeBudget)
                              .isBefore(DateTime.now())) {
                        fetchTimeBudgetExceeded = true;
                        throw TimeoutException(
                          'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.',
                        );
                      }
                      final relevanceQuery = queryText
                          .split(RegExp(r' - | \| | success:| Key questions:', caseSensitive: false))
                          .where((s) => s.trim().isNotEmpty)
                          .take(2)
                          .join(' ');
                      return _deepResearchBridge.readUrl(
                        targetUrl,
                        allowPdf: false,
                        query: relevanceQuery,
                      );
                    });
                    // Bridge skipped_pdf is the source of truth for PDF exclusion.
                    if (fetched['status'] == 'skipped_pdf') {
                      final reason =
                          fetched['reason']?.toString() ??
                          'PDF files are excluded from Deep Research';
                      phaseSkippedPdfs.add({
                        'url': targetUrl,
                        'reason': reason,
                      });
                      runFetchedUrls.add(normUrl);
                      runUrlSummaries[normUrl] = {
                        'facts': [],
                        'findings': [],
                        'isPdf': true,
                        'skipped': true,
                      };
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
                          'result_payload': {'summary': reason},
                        },
                      );
                      urlResults[idx] = 'Skipped PDF URL: $targetUrl';
                      return;
                    }
                    if (fetched['error'] != null) {
                      throw HttpException(fetched['error'].toString());
                    }
                    text = fetched['content']?.toString() ?? '';
                    if (text.isEmpty) {
                      throw const HttpException(
                        'Fetch returned no readable content',
                      );
                    }
                  } catch (e) {
                    fetchFailed = true;
                    final errStr = 'Fetch failed: $e';
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
                  if (fetchTimeBudgetExceeded ||
                      startTime
                          .add(globalTimeBudget)
                          .isBefore(DateTime.now())) {
                    fetchTimeBudgetExceeded = true;
                    finishResearchEvent(
                      eventId,
                      status: 'error',
                      stopwatch: eventWatch,
                      error:
                          'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.',
                    );
                    urlResults[idx] =
                        'Error: Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
                    return;
                  }

                  updateResearchEventStatus(
                    eventId,
                    'ingesting',
                    details: {'url': targetUrl, 'parse_format': 'html'},
                  );

                  // Store fetched text for batch summarization
                  fetchedTexts[targetUrl] = text;
                  fetchedEventIds[targetUrl] = eventId;
                  fetchedStopwatches[targetUrl] = eventWatch;
                  urlResults[idx] = 'Fetched: ${text.length} chars';
                }),
              );

              // ── BATCH SUMMARIZATION ──
              // Summarize all fetched URLs in ONE LLM call to cut API usage by ~80%
              if (fetchedTexts.isNotEmpty) {
                try {
                  final summaries = await _summarizeBatchInline(
                    sources: fetchedTexts,
                    query: queryText,
                    provider: provider,
                    settings: settings,
                    model: model,
                  );
                  final List<dynamic> facts = summaries['facts'] ?? [];
                  final List<dynamic> findings = summaries['findings'] ?? [];

                  // Deduplicate facts (metric|subject|value)
                  final existingKeys = phaseFacts.map(factDedupKey).toSet();
                  for (final fact in facts) {
                    if (existingKeys.add(factDedupKey(fact))) {
                      phaseFacts.add(fact);
                    }
                  }
                  // Deduplicate findings (text|source)
                  final existingFindingKeys = phaseFindings
                      .map((f) => '${f['text']}|${f['source']}')
                      .toSet();
                  for (final finding in findings) {
                    final key = '${finding['text']}|${finding['source']}';
                    if (existingFindingKeys.add(key)) {
                      phaseFindings.add(finding);
                    }
                  }

                  // Cap at 20 facts per phase, drop lowest confidence first
                  if (phaseFacts.length > 20) {
                    phaseFacts.sort((a, b) {
                      final ra =
                          a['confidence']?.toString().toLowerCase() ?? 'medium';
                      final rb =
                          b['confidence']?.toString().toLowerCase() ?? 'medium';
                      const ranks = {'high': 0, 'medium': 1, 'low': 2};
                      return (ranks[ra] ?? 1).compareTo(ranks[rb] ?? 1);
                    });
                    phaseFacts.removeRange(20, phaseFacts.length);
                  }

                  for (final entry in fetchedTexts.entries) {
                    final url = entry.key;
                    final normUrl = _normalizeQueryOrUrl(url);
                    runFetchedUrls.add(normUrl);
                    final urlFacts = facts
                        .where(
                            (f) => f['source']?.toString() == url)
                        .toList();
                    final urlFindings = findings
                        .where(
                            (f) => f['source']?.toString() == url)
                        .toList();
                    runUrlSummaries[normUrl] = {
                      'facts': urlFacts,
                      'findings': urlFindings,
                      'isPdf': false,
                      'skipped': false,
                    };
                  }

                  await _updateDeepResearchPhase(
                    stageId: stageId,
                    phaseTitle: phaseTitle,
                    facts: phaseFacts,
                    findings: phaseFindings,
                    skippedPdfs: phaseSkippedPdfs,
                    failedFetches: phaseFailedFetches,
                  );

                  for (final entry in fetchedEventIds.entries) {
                    final url = entry.key;
                    final eventId = entry.value;
                    final eventWatch = fetchedStopwatches[url]!;
                    final urlFacts = facts
                        .where(
                            (f) => f['source']?.toString() == url)
                        .length;
                    final urlFindings = findings
                        .where(
                            (f) => f['source']?.toString() == url)
                        .length;
                    finishResearchEvent(
                      eventId,
                      status: 'done',
                      stopwatch: eventWatch,
                      details: {
                        'url': url,
                        'parse_format': 'html',
                        'facts_count': urlFacts,
                        'findings_count': urlFindings,
                        'result_payload': {
                          'summary': 'Batch summarized',
                        },
                      },
                    );
                  }
                } catch (e) {
                  final errStr = 'Batch summarization failed: $e';
                  for (final entry in fetchedEventIds.entries) {
                    finishResearchEvent(
                      entry.value,
                      status: 'error',
                      stopwatch: fetchedStopwatches[entry.key]!,
                      details: {'url': entry.key, 'parse_format': 'html'},
                      error: errStr,
                    );
                  }
                  for (var k = 0; k < urls.length; k++) {
                    if (fetchedTexts.containsKey(urls[k])) {
                      urlResults[k] = errStr;
                    }
                  }
                }
              }

              final StringBuffer combinedResults = StringBuffer();
              for (var k = 0; k < urls.length; k++) {
                combinedResults.writeln("URL: ${urls[k]}");
                combinedResults.writeln(
                  "Summarization Result:\n${urlResults[k]}",
                );
                combinedResults.writeln();
              }

              stepMessages.add(
                ChatMessage(
                  role: MessageRole.user,
                  text: combinedResults.toString().trim(),
                ),
              );
            } else {
              stepContent = stepContent.isEmpty
                  ? responseText
                  : '$stepContent\n\n$responseText';
              stepDone = true;
            }

            if (!stepDone &&
                (phaseFacts.isNotEmpty || phaseFindings.isNotEmpty)) {
              final stepReflectMessages = [
                const ChatMessage(
                  role: MessageRole.system,
                  text: DeepResearchPrompts.reflectorSystemPrompt,
                ),
                ChatMessage(
                  role: MessageRole.user,
                  text:
                      "Phase goal: $queryText\n\n"
                      "Current facts: ${jsonEncode(phaseFacts)}\n\n"
                      "Current findings: ${jsonEncode(phaseFindings)}\n\n"
                      "Based on what we have, is the phase goal fully addressed?",
                ),
              ];
              try {
                final reflectResp = await _chatClient.sendChat(
                  provider: provider,
                  settings: settings,
                  model: model,
                  messages: _compactHistoryForApi(
                    stepReflectMessages,
                    stepReflectMessages.length,
                  ),
                  studyModeEnabled: _studyModeEnabled,
                );
                // Use regex fallback for robust JSON extraction
                final cleanReflectResp = reflectResp
                    .replaceAll(RegExp(r"```json"), '')
                    .replaceAll('```', '')
                    .trim();
                final reflectJsonMatch =
                    RegExp(r'\{[\s\S]*\}').firstMatch(cleanReflectResp);
                if (reflectJsonMatch != null) {
                  final reflectJson =
                      jsonDecode(reflectJsonMatch.group(0)!) as Map<String, dynamic>;
                  if (reflectJson['should_continue'] == false) {
                    stepDone = true;
                  } else {
                    // Extract gaps and append as guidance for next search
                    final gaps = reflectJson['gaps'];
                    if (gaps is List && gaps.isNotEmpty) {
                      final gapText = gaps
                          .whereType<String>()
                          .take(4)
                          .map((g) => '- $g')
                          .join('\n');
                      stepMessages.add(
                        ChatMessage(
                          role: MessageRole.user,
                          text: 'Reflection identified gaps. Focus next searches on:\n$gapText',
                        ),
                      );
                    }
                  }
                } else {
                  debugPrint('Reflection JSON parse failed: $cleanReflectResp');
                }
                } catch (e) {
                  debugPrint('Reflection error: $e');
                  stepMessages.add(
                    const ChatMessage(
                      role: MessageRole.user,
                      text: 'Reflection analysis failed. Continue searching for more evidence or emit step_complete if you have enough.',
                    ),
                  );
                }
            }
          } catch (e) {
            stepDone = true;
            stepFailed = true;
            stepFailure = e.toString();
            break;
          }
        }

        final phaseSummary = _buildDeepResearchPhaseSummary(
          phaseTitle: phaseTitle,
          stepContent: stepContent,
          facts: phaseFacts,
          findings: phaseFindings,
          skippedPdfs: phaseSkippedPdfs,
          failedFetches: phaseFailedFetches,
        );
        try {
          await _updateDeepResearchPhase(
            stageId: stageId,
            phaseTitle: phaseTitle,
            summary: phaseSummary,
            facts: phaseFacts,
            findings: phaseFindings,
            skippedPdfs: phaseSkippedPdfs,
            failedFetches: phaseFailedFetches,
            status: stepFailed ? 'failed' : 'completed',
          );
        } catch (e) {
          stepFailed = true;
          stepFailure = 'Could not persist this phase to temp.json: $e';
        }

        steps[i]['status'] = stepFailed ? 'failed' : 'completed';
        if (stepFailed) {
          steps[i]['error'] = stepFailure;
        }
        steps[i]['content'] = stepContent;

        if (phaseFacts.isNotEmpty || phaseFindings.isNotEmpty) {
          final entitySet = <String>{};
          for (final f in phaseFacts) {
            final subj = (f['subject'] ?? '').toString().trim();
            final val = (f['value'] ?? '').toString().trim();
            if (subj.isNotEmpty) entitySet.add(subj);
            if (val.isNotEmpty && val.length < 60) entitySet.add(val);
          }
          for (final f in phaseFindings) {
            final text = (f['text'] ?? '').toString();
            final words = text.split(RegExp(r'\s+'));
            for (final w in words) {
              final clean = w.replaceAll(RegExp(r'[^\w\-\.]'), '');
              if (clean.length > 3 && clean.length < 40 &&
                  (clean.contains('-') || clean.contains('.') || clean[0].toUpperCase() == clean[0])) {
                entitySet.add(clean);
              }
            }
          }
          final sourceUrls = <String>{};
          for (final f in [...phaseFacts, ...phaseFindings]) {
            final s = (f['source'] ?? '').toString().trim();
            if (s.isNotEmpty) sourceUrls.add(s);
          }
          crossPhaseContext.writeln('━━ Phase ${i + 1}: $phaseTitle ━━');
          crossPhaseContext.writeln('Discovered entities: ${entitySet.join(', ')}');
          crossPhaseContext.writeln('Key facts:');
          for (final f in phaseFacts.take(15)) {
            crossPhaseContext.writeln('  - ${f['subject']} ${f['metric']}: ${f['value']} (date: ${f['date'] ?? 'n/a'})');
          }
          crossPhaseContext.writeln('Key findings:');
          for (final f in phaseFindings.take(8)) {
            crossPhaseContext.writeln('  - ${f['text']}');
          }
          if (sourceUrls.isNotEmpty) {
            crossPhaseContext.writeln('Sources found (use read_url on these if needed):');
            for (final u in sourceUrls.take(8)) {
              crossPhaseContext.writeln('  - $u');
            }
          }
          crossPhaseContext.writeln('');
        }

        _publishResearchState(sessionIndex, messageIndex, stateMap);
        await _saveSessions();

        // IMPROVEMENT: Incremental checkpoint after each phase for crash recovery
        try {
          await _deepResearchBridge.saveCheckpoint(
            runId: runId,
            status: stepFailed ? 'running_with_errors' : 'running',
            currentPhaseIndex: i + 1,
            steps: steps.map((s) => Map<String, dynamic>.from(s)).toList(),
            stats: {
              'phases_completed': i + 1,
              'phases_total': steps.length,
              'facts_collected': (cumulativeFacts += phaseFacts.length),
              'findings_collected': (cumulativeFindings += phaseFindings.length),
            },
          );
        } catch (e) {
          debugPrint('Checkpoint save failed after phase ${i + 1}: $e');
        }
      }

      // ── STAGE 3: WRITING THE REPORT ──
      final executionIssues = <Map<String, dynamic>>[];
      for (final stepValue in steps) {
        final step = stepValue as Map;
        final eventErrors = (step['events'] as List? ?? [])
            .whereType<Map>()
            .where((event) => event['status'] == 'error')
            .map(
              (event) => _truncateEventText(
                event['error']?.toString() ?? 'Tool call failed.',
                300,
              ),
            )
            .toList();
        if (step['status'] == 'failed' || eventErrors.isNotEmpty) {
          executionIssues.add({
            'step': step['title']?.toString() ?? 'Research step',
            'status':
                step['status']?.toString() ?? 'completed_with_tool_errors',
            'error': _truncateEventText(
              step['error']?.toString() ??
                  (eventErrors.isNotEmpty
                      ? eventErrors.join('; ')
                      : 'Step completed with issues.'),
              500,
            ),
          });
        }
      }

      stateMap['status'] = 'generating_report';
      _publishResearchState(sessionIndex, messageIndex, stateMap);

      String tempJsonContent = '[]';
      // Raw temp.json is the source of truth for verified URLs (budget export
      // may trim records and drop sources).
      String rawTempJson = '[]';
      String compactText = '';
      String? writerInputFailure;
      try {
        final int userBudget = _writerContextBudget;
        // IMPROVEMENT: Reasoning models have larger context windows — reduce
        // the prompt reserve so more evidence reaches the writer.
        final double reserveRatio = settings.reasoningEnabled ? 0.10 : 0.18;
        final int reserve = (userBudget * reserveRatio).round();
        final int maxEvidenceTokens = userBudget - reserve;
        final writerExport = await _exportDeepResearchForWriter(
          maxEvidenceTokens,
        );
        tempJsonContent = writerExport['content']?.toString() ?? '[]';
        // Use compact structured text if available (~40% fewer tokens than JSON)
        compactText = writerExport['compact_text']?.toString() ?? '';
        rawTempJson = await _deepResearchBridge.exportTemp();
        final rawPhases = jsonDecode(rawTempJson);
        final exportedPhases = jsonDecode(tempJsonContent);
        final rawHasPhases = rawPhases is List && rawPhases.isNotEmpty;
        final exportedHasPhases =
            exportedPhases is List && exportedPhases.isNotEmpty;
        if (!exportedHasPhases && rawHasPhases) {
          // Never discard successfully persisted phase summaries just because
          // a budget export was unexpectedly empty.
          tempJsonContent = rawTempJson;
          executionIssues.add({
            'step': 'Writer input export',
            'status': 'warning',
            'error':
                'Budgeted evidence export was empty; the writer received the complete temp.json fallback instead.',
          });
        } else if (!rawHasPhases) {
          writerInputFailure =
              'No phase results were persisted to temp.json, so a sourced report cannot be generated.';
        }
        final truncatedFacts =
            (writerExport['truncated_facts'] as num?)?.toInt() ?? 0;
        final truncatedFindings =
            (writerExport['truncated_findings'] as num?)?.toInt() ?? 0;
        final truncatedPhases =
            (writerExport['truncated_phases'] as num?)?.toInt() ?? 0;
        if (truncatedFacts + truncatedFindings + truncatedPhases > 0) {
          executionIssues.add({
            'step': 'Evidence budget',
            'status': 'warning',
            'error':
                'Evidence was trimmed to fit $userBudget tokens: $truncatedFacts facts, $truncatedFindings findings, and $truncatedPhases empty phases omitted.',
          });
        }
      } catch (e) {
        debugPrint("Error exporting/processing deep-research temp.json: $e");
        writerInputFailure =
            'The writer could not load the bridge-owned retrieval data.';
        executionIssues.add({
          'step': 'Writer input export',
          'status': 'failed',
          'error':
              'The writer could not load the bridge-owned retrieval data: ${_truncateEventText(e.toString(), 300)}',
        });
      }

      var verifiedSourceUrls = _evidenceSourceUrls(rawTempJson);
      if (writerInputFailure == null && verifiedSourceUrls.isEmpty) {
        writerInputFailure =
            'No verified source URLs were persisted to temp.json, so a research artifact cannot be generated safely.';
      }

      final writerEvidence = compactText.isNotEmpty ? compactText : tempJsonContent;

      final evidenceUrls = <String>{};
      try {
        final parsedTemp = jsonDecode(rawTempJson);
        if (parsedTemp is List) {
          for (final phase in parsedTemp) {
            if (phase is! Map) continue;
            for (final fact in phase['facts'] as List? ?? []) {
              if (fact is Map) {
                final s = fact['source']?.toString();
                if (s != null && s.isNotEmpty) evidenceUrls.add(s);
              }
            }
            for (final finding in phase['findings'] as List? ?? []) {
              if (finding is Map) {
                final s = finding['source']?.toString();
                if (s != null && s.isNotEmpty) evidenceUrls.add(s);
              }
            }
          }
        }
      } catch (_) {}
      verifiedSourceUrls = verifiedSourceUrls.where((u) => evidenceUrls.contains(u)).toList();

      // IMPROVEMENT: Build evidence summary so the writer knows the scope of research
      int totalFacts = 0;
      int totalFindings = 0;
      int totalSources = 0;
      try {
        final phases = jsonDecode(tempJsonContent);
        if (phases is List) {
          for (final phase in phases.whereType<Map>()) {
            totalFacts += (phase['facts'] is List) ? (phase['facts'] as List).length : 0;
            totalFindings += (phase['findings'] is List) ? (phase['findings'] as List).length : 0;
          }
          totalSources = verifiedSourceUrls.length;
        }
      } catch (_) {}
      final evidenceSummary =
          'Research scope: ${steps.length} phases completed, '
          '$totalFacts facts and $totalFindings findings extracted from '
          '$totalSources verified sources.';

      List<ChatMessage> writerMessages = [
        const ChatMessage(
          role: MessageRole.system,
          text: DeepResearchPrompts.writerSystemPrompt,
        ),
        ChatMessage(
          role: MessageRole.user,
          text:
              "$evidenceSummary\n\n"
              "Here is the retrieved evidence:\n$writerEvidence\n\n"
              "Execution issues that must be disclosed in the report:\n"
              "${jsonEncode(executionIssues)}\n\n"
              "Write the final, comprehensive research report following the DOCUMENT STRUCTURE in your system prompt exactly. "
              "Start with the Executive Summary, then Key Findings, then Detailed Analysis chapters, "
              "then Confidence Assessment, then Suggested Follow-Up Research. "
              "Use clear headings, detailed paragraphs, and tables where data supports it. "
              "Do not use SVG, HTML, Mermaid, or image-based visuals. "
              "Use only the URLs provided in the evidence; do not invent, infer, or search for sources. "
              "The app will insert the verified source list directly into the final artifact.",
        ),
      ];

      String finalReportText = '';
      String finalReasoningText = '';
      bool finalReportDone = false;
      int writerRetries = 0;
      String? writerFailure = writerInputFailure;

      while (!finalReportDone && writerFailure == null && writerRetries < 3) {
        if (!mounted) return;
        if (!_sendingSessionIds.contains(_sessions[sessionIndex].id)) {
          break;
        }
        try {
          String responseText = '';
          String reasoningText = '';
          var isThinking = false;

          final stream = _chatClient.sendChatStream(
            provider: provider,
            settings: settings,
            model: model,
            messages: _compactHistoryForApi(
              writerMessages,
              writerMessages.length,
            ),
            studyModeEnabled: _studyModeEnabled,
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
          if (writerRetries >= 3) {
            writerFailure = e.toString();
          }
        }
      }

      if (!finalReportDone && writerFailure == null) {
        writerFailure = 'Writer stopped before producing a report.';
      }
      if (writerFailure == null) {
        finalReportText = _unwrapMarkdownArtifact(
          _stripSvgVisuals(finalReportText),
        );
        if (finalReportText.isEmpty) {
          writerFailure = 'Writer returned an empty report.';
        } else {
          if (verifiedSourceUrls.isNotEmpty) {
            final sources = verifiedSourceUrls
                .map((url) => '- <$url>')
                .join('\n');
            finalReportText =
                '$finalReportText\n\n## Verified retrieved sources\n$sources';
          }
          stateMap['final_report'] = finalReportText;
          try {
            stateMap['report_path'] = await _persistResearchReport(
              _getResearchFileName(_sessions[sessionIndex].title),
              finalReportText,
            );
          } catch (e) {
            stateMap['report_save_error'] =
                'Could not save the Markdown report: $e';
          }
        }
      }
      stateMap['status'] = writerFailure == null ? 'completed' : 'failed';
      if (writerFailure != null) {
        stateMap['error'] = 'Writer agent failed: $writerFailure';
      }
      stateMap['plan_end_ms'] = DateTime.now().millisecondsSinceEpoch;

      // Clean up temp.json after successful report generation to free storage
      if (writerFailure == null) {
        try {
          await _deepResearchBridge.reset(keepCheckpoint: false);
          debugPrint('Deep Research: temp.json cleaned up after successful report.');
        } catch (e) {
          debugPrint('Deep Research: temp.json cleanup failed: $e');
        }
      }

      if (mounted) {
        setState(() {
          final msgs = List<ChatMessage>.from(_sessions[sessionIndex].messages);
          _sendingSessionIds.remove(_sessions[sessionIndex].id);

          String text = _updateResearchStateInText(
            msgs[messageIndex].text,
            stateMap,
          );
          if (writerFailure == null) {
            text += "\n\n```markdown\n$finalReportText\n```";
          } else {
            text += "\n\n⚠️ Writer agent failed: $writerFailure";
          }

          msgs[messageIndex] = ChatMessage(
            role: MessageRole.assistant,
            text: text,
            reasoning: finalReasoningText.isNotEmpty
                ? finalReasoningText
                : msgs[messageIndex].reasoning,
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            messages: msgs,
          );
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
            text:
                _updateResearchStateInText(msgs[messageIndex].text, stateMap) +
                '\n\n⚠️ Deep Research stopped before completion. Reason: $globalError',
            reasoning: msgs[messageIndex].reasoning,
          );
          _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
            messages: msgs,
          );
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
      messages: const [],
      providerId: _selectedProviderId,
      model: _activeModel,
    );
    setState(() {
      _sessions.insert(0, newSession);
      _activeSessionId = newId;
      _editingMessageIndex = null;
      _agenticEnabled = false; // Default off for new chat
      _deepResearchEnabled = false; // Default off for new chat
      _studyModeEnabled = false; // Default off for new chat
    });
    _saveSessions();
    _clearWorkspaceBucket();
  }

  String _safeFileStem(String input) {
    final sanitized = input
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'session' : sanitized;
  }

  Future<File> _slashSessionFile({String? name, String? path}) async {
    if (path != null && path.trim().isNotEmpty) {
      final explicit = await _expandHomePath(path.trim());
      return File(explicit);
    }
    final root = await _chooseWritableNexonRoot();
    final stem = _safeFileStem(
      (name == null || name.trim().isEmpty)
          ? 'session_${DateTime.now().millisecondsSinceEpoch}'
          : name,
    );
    return File('${root.path}/sessions/$stem.json');
  }

  Future<void> _appendSystemMessage(String text) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    if (!mounted) return;
    setState(() {
      final msgs = List<ChatMessage>.from(_sessions[idx].messages);
      msgs.add(ChatMessage(role: MessageRole.system, text: text));
      _sessions[idx] = _sessions[idx].copyWith(messages: msgs);
    });
    await _saveSessions();
    _scrollToBottom(force: true);
  }

  Future<String> _slashNew(String? title) async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final resolvedTitle = (title == null || title.trim().isEmpty)
        ? 'New Chat'
        : title.trim();
    final newSession = ChatSession(
      id: newId,
      title: resolvedTitle,
      messages: const [],
      providerId: _selectedProviderId,
      model: _activeModel,
    );
    if (mounted) {
      setState(() {
        _sessions.insert(0, newSession);
        _activeSessionId = newId;
        _editingMessageIndex = null;
        _agenticEnabled = false;
        _deepResearchEnabled = false;
        _studyModeEnabled = false;
      });
    }
    await _saveSessions();
    return 'Created new chat: ${newSession.title} (${newSession.id})';
  }

  Future<String> _slashList() async {
    if (_sessions.isEmpty) return 'No sessions.';
    final lines = <String>[];
    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      final marker = s.id == _activeSessionId ? ' *active*' : '';
      lines.add(
        '${i + 1}. `${s.id}` — ${s.title} (${s.updatedAt.toIso8601String()})$marker',
      );
    }
    return lines.join('\n');
  }

  Future<String> _slashSwitch(String target) async {
    final byIndex = int.tryParse(target);
    if (byIndex != null && byIndex > 0 && byIndex <= _sessions.length) {
      _switchSession(_sessions[byIndex - 1].id);
      return 'Switched to session #$byIndex.';
    }
    final byId = _sessions.where((s) => s.id == target).toList();
    if (byId.isNotEmpty) {
      _switchSession(target);
      return 'Switched to `${target}`.';
    }
    return 'Session not found: $target';
  }

  Future<String> _slashSave({String? name, String? path}) async {
    final activeId = _activeSessionId;
    if (activeId == null) return 'No active session.';
    final idx = _sessions.indexWhere((s) => s.id == activeId);
    if (idx == -1) return 'No active session.';
    final session = _sessions[idx];

    final file = await _slashSessionFile(name: name, path: path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = <String, dynamic>{
      'saved_at': DateTime.now().toIso8601String(),
      'session': session.toJson(),
    };
    final raw = jsonEncode(payload);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(raw, flush: true);
    await tmp.rename(file.path);
    await _saveSessions();
    DriveSyncService.syncToDrive(_sessions);
    return 'Saved session `${session.id}` to `${file.path}`.';
  }

  Future<String> _slashResume(String target) async {
    String sourcePath = target;
    if (!target.contains('/')) {
      final root = await _chooseWritableNexonRoot();
      final candidate = File('${root.path}/sessions/${_safeFileStem(target)}.json');
      if (await candidate.exists()) {
        sourcePath = candidate.path;
      } else {
        final byId = _sessions.where((s) => s.id == target).toList();
        if (byId.isNotEmpty) {
          _switchSession(target);
          return 'Switched to existing session `${target}`.';
        }
      }
    }
    final resolved = await _expandHomePath(sourcePath);
    final file = File(resolved);
    if (!await file.exists()) {
      return 'Session file not found: $resolved';
    }
    final decoded = jsonDecode(await file.readAsString());
    Map<String, dynamic>? sessionMap;
    if (decoded is Map && decoded['session'] is Map) {
      sessionMap = Map<String, dynamic>.from(decoded['session'] as Map);
    } else if (decoded is Map<String, dynamic>) {
      sessionMap = decoded;
    }
    if (sessionMap == null) {
      return 'Invalid session JSON: $resolved';
    }
    var loaded = ChatSession.fromJson(sessionMap);
    final duplicateId = _sessions.any((s) => s.id == loaded.id);
    if (duplicateId) {
      loaded = loaded.copyWith(id: DateTime.now().millisecondsSinceEpoch.toString());
    }
    if (mounted) {
      setState(() {
        _sessions.insert(0, loaded);
        _activeSessionId = loaded.id;
        _editingMessageIndex = null;
      });
    }
    await _saveSessions();
    DriveSyncService.syncToDrive(_sessions);
    return 'Loaded session `${loaded.title}` (${loaded.id}) from `${file.path}`.';
  }

  Future<String> _slashSummarize(int keepLast) async {
    final activeId = _activeSessionId;
    if (activeId == null) return 'No active session.';
    final idx = _sessions.indexWhere((s) => s.id == activeId);
    if (idx == -1) return 'No active session.';
    final session = _sessions[idx];
    if (session.messages.length <= keepLast + 2) {
      return 'Not enough messages to summarize.';
    }
    final safeKeepLast = keepLast < 1 ? 1 : keepLast;
    final head = session.messages.take(1).toList();
    final tail = session.messages.skip(session.messages.length - safeKeepLast).toList();
    final middle = session.messages
        .skip(1)
        .take(session.messages.length - safeKeepLast - 1)
        .map((m) => '${m.role.apiName}: ${m.text}')
        .toList();
    final compressed = await ContextCompressionService().compress(
      middle,
      config: const CompressionConfig(
        maxTokens: 1500,
        preferredMethods: [CompressionMethod.extractive, CompressionMethod.pruning],
      ),
    );
    final summaryMsg = ChatMessage(
      role: MessageRole.system,
      text:
          'Conversation summary (${(compressed.compressionRatio * 100).toStringAsFixed(1)}% of original):\n${compressed.compressedContent}',
    );
    final nextMessages = <ChatMessage>[...head, summaryMsg, ...tail];
    if (mounted) {
      setState(() {
        _sessions[idx] = session.copyWith(messages: nextMessages);
      });
    }
    await _saveSessions();
    final before = compressed.originalContent.length;
    final after = compressed.compressedContent.length;
    return 'Summarized history. chars: $before → $after (ratio ${(after / before).toStringAsFixed(2)}).';
  }

  Future<CheckpointService> _checkpointSvc() async {
    await _ensureLocalSupportDirs();
    return _checkpointService!;
  }

  Future<String> _slashCheckpoint(String? name) async {
    final svc = await _checkpointSvc();
    final cp = await svc.create(
      name: (name == null || name.trim().isEmpty)
          ? 'manual_${DateTime.now().millisecondsSinceEpoch}'
          : name.trim(),
      projectId: _agenticWorkspace,
      autoCreated: true,
      memorySnapshot: {
        'active_session_id': _activeSessionId,
        'sessions': _sessions.map((s) => s.toJson()).toList(),
      },
    );
    return 'Checkpoint created: ${cp.id} (${cp.name})';
  }

  Future<String> _slashRestoreCheckpoint(String id) async {
    final svc = await _checkpointSvc();
    final checkpoints = await svc.list(projectId: _agenticWorkspace);
    final cp = checkpoints.where((c) => c.id == id).toList();
    if (cp.isEmpty) return 'Checkpoint not found: $id';
    final memory = cp.first.memorySnapshot;
    final activeId = memory['active_session_id']?.toString();
    final rawSessions = memory['sessions'];
    if (rawSessions is! List) return 'Checkpoint has no session snapshot.';
    final restored = rawSessions
        .whereType<Map>()
        .map((e) => ChatSession.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (restored.isEmpty) return 'Checkpoint session snapshot is empty.';
    if (mounted) {
      setState(() {
        _sessions = restored;
        _activeSessionId = activeId ?? restored.first.id;
        _editingMessageIndex = null;
      });
    }
    await _saveSessions();
    return 'Restored checkpoint ${cp.first.id}.';
  }

  Future<String> _slashListCheckpoints() async {
    final svc = await _checkpointSvc();
    final list = await svc.list(projectId: _agenticWorkspace);
    if (list.isEmpty) return 'No checkpoints.';
    return list
        .take(50)
        .map((c) => '- `${c.id}` ${c.name} (${c.createdAt.toIso8601String()})')
        .join('\n');
  }

  Future<String> _slashClear() async {
    final activeId = _activeSessionId;
    if (activeId == null) return 'No active session.';
    final idx = _sessions.indexWhere((s) => s.id == activeId);
    if (idx == -1) return 'No active session.';
    if (mounted) {
      setState(() {
        _sessions[idx] = _sessions[idx].copyWith(messages: const []);
      });
    }
    await _saveSessions();
    return 'Cleared current session messages.';
  }

  Future<String> _slashPlan(String prompt) async {
    if (!_agenticEnabled) {
      return 'Plan mode requires Agentic File Access. Enable it in Settings.';
    }
    final activeId = _activeSessionId;
    if (activeId == null) return 'No active session.';
    bool hasExistingFiles = false;
    try {
      final dir = Directory(_agenticWorkspace);
      if (dir.existsSync()) {
        final entries = dir.listSync(followLinks: false).where((e) {
          final name = e.path.split('/').last;
          return !name.startsWith('.') && name != 'build' && name != 'node_modules';
        });
        hasExistingFiles = entries.isNotEmpty;
      }
    } catch (_) {}
    final String planInstruction;
    if (hasExistingFiles) {
      planInstruction =
        'The user wants: $prompt\n\n'
        'This workspace already has files. Before creating a todo list, explore the codebase to understand the current structure:\n'
        '1. Call list to see the project tree (depth 2-3).\n'
        '2. Call search for key terms from the user request to find relevant files.\n'
        '3. Call outline on the most relevant files to understand the code organization.\n'
        '4. Based on what you found, create a todo list with todo_create covering the specific changes needed.\n'
        '5. Execute each task one by one, marking each with todo_done when complete.\n'
        'Do NOT create the todo list until you have explored the codebase and understand what exists.';
    } else {
      planInstruction =
        'The user wants: $prompt\n\n'
        'This workspace is empty — the user is building from scratch. Create a todo list immediately:\n'
        '1. Call todo_create with the steps needed to build this project from scratch (project setup, core files, configuration, tests, etc.).\n'
        '2. Execute each task one by one using create_file, sh (for package installs), and other tools.\n'
        '3. Mark each task with todo_done as you complete it.\n'
        'Be thorough in the todo list — include project structure, dependencies, all source files, config, and a README.';
    }
    await _appendSystemMessage('Plan mode: "$prompt" — ${hasExistingFiles ? "exploring codebase" : "building from scratch"}…');
    if (mounted) {
      setState(() => _toolStatus = '📋 Planning: $prompt');
    }
    await _sendMessage(promptText: planInstruction);
    if (mounted) setState(() => _toolStatus = '');
    return 'Plan initiated.';
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
          sessionId: _activeSessionId ?? '',
          onSystemMessage: _appendSystemMessage,
          onRestoreCompleted: _loadSessions,
          provider: provider,
          customProviders: _customProviders,
          allSettings: _settings,
          modelCache: _modelCache,
          settings: settings,
          cachedModels: models,
          searchSettings: _searchSettings,
          agenticEnabled: _agenticEnabled,
          artifactsEnabled: _artifactsEnabled,
          svgVisualsEnabled: _svgVisualsEnabled,
          deepResearchEnabled: _deepResearchEnabled,
          studyModeEnabled: _studyModeEnabled,
          userName: _userName,
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
              SlashCommandService.agenticAccessEnabled = val;
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
          onStudyModeEnabledChanged: (val) async {
            setState(() {
              _studyModeEnabled = val;
            });
            await _saveSettings();
          },
          onUserNameChanged: (val) async {
            setState(() {
              _userName = val;
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
            final trimmed = val.trim();
            // Never persist a blank workspace: an empty path makes every
            // tool call fail and the workspace look 'cleared'.
            if (trimmed.isEmpty) return;
            setState(() {
              _agenticWorkspace = trimmed;
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
            final nextProvider = _resolveProvider(newProviderId);
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
          onTemperatureChanged: (newTemperature) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings =
                  _settings[currentProv] ??
                  ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(
                temperature: newTemperature,
              );
            });
            await _saveSettings();
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
          onReasoningEffortChanged: (effort) async {
            setState(() {
              final currentProv = _selectedProviderId;
              final currentSettings =
                  _settings[currentProv] ??
                  ProviderSettings.defaults(_provider);
              _settings[currentProv] = currentSettings.copyWith(
                reasoningEffort: effort,
              );
            });
            await _saveSettings();
          },
          onFetchModels: () => _fetchModels(provider),
          onConfigureKey: (selectedProvId) {
            _openProviderSheet(selectedProvId);
          },
          onDeleteCustomProvider: (id) async {
            setState(() {
              _customProviders = [
                for (final p in _customProviders)
                  if (p.id != id) p,
              ];
              if (_selectedProviderId == id) {
                _selectedProviderId = 'custom';
              }
            });
            await _saveSettings();
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
          _suppressPasteDetection = true;
          _messageController.text = targetMessage.text;
          _suppressPasteDetection = false;
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

      if (force || (maxScroll - currentScroll) <= 400.0) {
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
    final wide = width >= 700;
    final activeSession = _activeSession;

    final chatHistoryPanel = ChatHistoryPanel(
      sessions: _sessions,
      activeSessionId: _activeSessionId,
      onSessionTap: _switchSession,
      onSessionDelete: _deleteSession,
      onSessionRename: _renameSession,
      onSessionPinToggle: _togglePinSession,
      onNewChat: _newChat,
      visibleLimit: _historyLimit,
      isLoadingMore: _isLoadingMoreHistory,
      onLoadMore: _loadMoreHistory,
    );

    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              width: width < 400 ? width * 0.85 : 330,
              child: chatHistoryPanel,
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: (width * 0.36).clamp(280.0, 360.0),
                child: chatHistoryPanel,
              ),
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
                 activeTodos: _activeTodos,
                 todoListVisible: _todoListVisible,
                 onCloseTodoList: () => setState(() => _todoListVisible = false),
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
                onOpenLiveVoice: _openLiveVoiceMode,
                activeFeaturePills: [
                  if (_deepResearchEnabled) const FeaturePill(icon: Icons.psychology, label: 'Deep Research'),
                  if (_agenticEnabled) const FeaturePill(icon: Icons.terminal, label: 'Agentic IDE'),
                  if (_searchSettings.enabled) const FeaturePill(icon: Icons.search, label: 'Web Search'),
                  if (_studyModeEnabled) const FeaturePill(icon: Icons.menu_book, label: 'Study Mode'),
                  if (_artifactsEnabled) const FeaturePill(icon: Icons.extension, label: 'Artifacts'),
                  if (_svgVisualsEnabled) const FeaturePill(icon: Icons.auto_awesome, label: 'Visuals'),
                ],
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
