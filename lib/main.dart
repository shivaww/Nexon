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
import 'package:nexon/services/deep_research/deep_research_bridge_client.dart';
import 'package:nexon/services/deep_research/deep_research_helpers.dart';
import 'package:nexon/services/slash_command/slash_command_service.dart';
import 'package:nexon/services/context_compression/context_compression_service.dart';
import 'package:nexon/services/checkpoint/checkpoint_service.dart';
import 'package:nexon/services/workspace/workspace_service.dart';
import 'package:nexon/services/termux_bridge/termux_bridge_service.dart';
import 'package:nexon/services/termux_bridge/bridge_protocol.dart';
import 'package:uuid/uuid.dart';

/// Shared warm cream/tan glassmorphism container matching Nexon's palette.
class WarmGlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final double sigma;
  final bool enableBlur;

  const WarmGlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.backgroundColor,
    this.border,
    this.boxShadow,
    this.sigma = 12.0,
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(16);
    final effectiveBg =
        backgroundColor ??
        const Color(0xFFFFFBF2).withValues(alpha: highContrast ? 0.96 : 0.65);
    final effectiveBorder =
        border ??
        Border.all(
          color: const Color(
            0xFFE5DDD3,
          ).withValues(alpha: highContrast ? 0.95 : 0.70),
          width: 1.0,
        );
    final effectiveShadow =
        boxShadow ??
        [
          BoxShadow(
            color: const Color(0xFF2D241C).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ];

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: effectiveShadow,
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: enableBlur && !highContrast
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Container(
                  padding: padding,
                  decoration: BoxDecoration(
                    color: effectiveBg,
                    borderRadius: effectiveRadius,
                    border: effectiveBorder,
                  ),
                  child: child,
                ),
              )
            : Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: effectiveBg,
                  borderRadius: effectiveRadius,
                  border: effectiveBorder,
                ),
                child: child,
              ),
      ),
    );
  }
}

/// Helper class for Text-To-Speech audio playback of model outputs.
class NexonTts {
  static final FlutterTts _flutterTts = FlutterTts();
  static String? _speakingText;
  static bool _isSpeaking = false;

  static Future<void> toggleSpeak(
    String text,
    VoidCallback onStateChange,
  ) async {
    text = sanitizeForTts(text);
    try {
      if (_isSpeaking && _speakingText == text) {
        await _flutterTts.stop();
        _isSpeaking = false;
        _speakingText = null;
        onStateChange();
        return;
      }
      await _flutterTts.stop();
      _speakingText = text;
      _isSpeaking = true;
      onStateChange();

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _speakingText = null;
        onStateChange();
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        _speakingText = null;
        onStateChange();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        _speakingText = null;
        onStateChange();
      });

      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.speak(text);
    } catch (_) {
      _isSpeaking = false;
      _speakingText = null;
      onStateChange();
    }
  }

  static bool isSpeaking(String text) {
    return _isSpeaking && _speakingText == text;
  }

  static Future<List<dynamic>> getVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) return voices;
    } catch (_) {}
    return [];
  }

  static Future<void> setVoice(Map<String, String> voice) async {
    try {
      await _flutterTts.setVoice(voice);
    } catch (_) {}
  }
}

/// Custom painter for Liquid Glass rim highlights.
/// Traces a thin specular edge highlight line along the top/outer boundary of a pill or circle shape.
class _LiquidGlassRimPainter extends CustomPainter {
  final BorderRadius? borderRadius;
  final bool isCircle;
  final double borderWidth;
  final Color? highlightColor;
  final Color? shadowColor;

  _LiquidGlassRimPainter({
    this.borderRadius,
    this.isCircle = false,
    this.borderWidth = 1.2,
    this.highlightColor,
    this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final path = Path();

    if (isCircle) {
      path.addOval(rect.deflate(borderWidth / 2));
    } else if (borderRadius != null) {
      path.addRRect(borderRadius!.toRRect(rect).deflate(borderWidth / 2));
    } else {
      path.addRect(rect.deflate(borderWidth / 2));
    }

    final topHighlight = highlightColor ?? const Color(0xFFFFFFFF);
    final botShadow = shadowColor ?? const Color(0xFFE2D6C7);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          topHighlight.withValues(
            alpha: 0.95,
          ), // Bright specular top rim highlight
          topHighlight.withValues(alpha: 0.45), // Translucent side rim
          botShadow.withValues(
            alpha: 0.40,
          ), // Warm/semantic bottom border shadow
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassRimPainter oldDelegate) => false;
}

/// Shared liquid glass surface widget matching Nexon's warm cream/tan palette and semantic tool tints.
class LiquidGlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final bool isCircle;
  final Color? backgroundColor;
  final Color? highlightColor;
  final Color? shadowColor;
  final double sigma;
  final bool enableBlur;
  final VoidCallback? onTap;
  final String? tooltip;
  final double? width;
  final double? height;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.isCircle = false,
    this.backgroundColor,
    this.highlightColor,
    this.shadowColor,
    this.sigma = 12.0,
    this.enableBlur = true,
    this.onTap,
    this.tooltip,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final effectiveRadius = isCircle
        ? null
        : (borderRadius ?? BorderRadius.circular(30));

    final effectiveBg =
        backgroundColor ??
        const Color(0xFFFFFDF8).withValues(alpha: highContrast ? 0.96 : 0.72);

    Widget innerContent = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: effectiveRadius,
      ),
      child: child,
    );

    if (enableBlur && !highContrast) {
      innerContent = isCircle
          ? ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: innerContent,
              ),
            )
          : ClipRRect(
              borderRadius: effectiveRadius!,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: innerContent,
              ),
            );
    }

    Widget decorated = Container(
      margin: margin,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: effectiveRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D2817).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _LiquidGlassRimPainter(
          borderRadius: effectiveRadius,
          isCircle: isCircle,
          highlightColor: highlightColor,
          shadowColor: shadowColor,
        ),
        child: innerContent,
      ),
    );

    if (onTap != null) {
      decorated = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: isCircle
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: effectiveRadius!),
          child: decorated,
        ),
      );
    }

    if (tooltip != null) {
      decorated = Tooltip(message: tooltip!, child: decorated);
    }

    return decorated;
  }
}

/// Circular liquid glass button widget (Target #1 & Target #2).
class LiquidGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final Color? iconColor;
  final Color? backgroundColor;

  const LiquidGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 42,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      isCircle: true,
      width: size,
      height: size,
      backgroundColor: backgroundColor,
      onTap: onPressed,
      tooltip: tooltip,
      child: Center(
        child: Icon(
          icon,
          size: size * 0.50,
          color: iconColor ?? const Color(0xFF5C3D26),
        ),
      ),
    );
  }
}

/// Pill-shaped liquid glass suggestion chip widget (Target #4).
class LiquidGlassChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const LiquidGlassChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF7B4E2E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A3424),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared warm glass dialog wrapper for modal popups.
class WarmGlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? actionsPadding;
  final Widget? child;

  const WarmGlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsPadding,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: WarmGlassContainer(
        borderRadius: BorderRadius.circular(22),
        backgroundColor: const Color(0xFFFFFBF2).withValues(alpha: 0.92),
        sigma: 10.0,
        padding: const EdgeInsets.all(20),
        child:
            child ??
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) title!,
                if (content != null) ...[const SizedBox(height: 12), content!],
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!,
                  ),
                ],
              ],
            ),
      ),
    );
  }
}

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

class DeepResearchPrompts {
  static const String plannerSystemPrompt =
      """ROLE: Planner. No searching, no fetching. Output XML only.
Decide: complexity (STANDARD/COMPLEX), stage_count (5-15) based on user query.
Generate a phase-by-phase research plan.
Output format:
<research_plan>
  <phase1>Stage Title - Detailed goal and instructions for this phase</phase1>
  <phase2>Stage Title - Detailed goal and instructions for this phase</phase2>
  ...
</research_plan>
No text outside the XML tags. Each phase tag MUST match the phase number, e.g. <phase1>...</phase1>, <phase2>...</phase2>. Do not include reasoning or preamble outside the XML.""";

  static const String researchSystemPrompt =
      """ROLE: Research agent. You are running one phase of a multi-step research plan.
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
2. Fetch Page: Output <read_url>URL</read_url> to fetch HTML page content in depth. PDFs are excluded to protect mobile memory and writer context.
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
   - For recent/current-events-flavored queries (product releases, benchmark results, pricing, "latest", "current", "2026"), default to time_range="week" or time_range="day" or topic="news". Avoid time_range="month" for fast-changing topics.
   - For general/foundational/definitional queries (explaining a concept, historical background), omit time_range entirely to avoid artificially excluding older-but-still-correct foundational sources.
   - Do NOT rely on a single source. If the first search result is insufficient or outdated, refine your query and search again. Cross-reference multiple sources to verify accuracy and recency.
5. Once you have collected enough info for this phase, output <step_complete/> to finish the phase.
6. You can output multiple `<search_request>` tags (or multiple `<read_url>` tags) in a single response to execute them in parallel. Do not mix search and read url tags in the same message. Wait for the user response after each action.

7. RECENCY & ACCURACY: For time-sensitive queries (news, versions, releases), ALWAYS use time_range="week" or time_range="day". Do NOT rely on a single source. If the first search result is insufficient or outdated, refine your query and search again. Cross-reference multiple sources to verify accuracy and recency.""";

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

  static const String reflectorSystemPrompt =
      """ROLE: Research Sufficiency Judger.
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

Ensure you write detailed paragraphs for each section, citing the URLs in brackets (e.g. [https://example.com]). Do not create a Sources section: the application inserts the verified source list directly into the final artifact. Output plain Markdown only: do not generate SVG, HTML, Mermaid, or image-based visuals.""";
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
  final HttpClient _mcpHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);
  bool _deepResearchEnabled = false;
  bool _studyModeEnabled = false;

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

  DeepResearchBridgeClient get _deepResearchBridge => DeepResearchBridgeClient(
    endpoint: _customMcpUrl.isNotEmpty
        ? _customMcpUrl
        : 'http://127.0.0.1:8390/mcp',
  );

  String _normalizeQueryOrUrl(String input) {
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

  String _toolStatus = ''; // live tool status shown in UI banner

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

  /// Merges [incoming] sessions into [_sessions], skipping ids that already
  /// exist (the in-memory copy is newer). Returns how many were added.
  int _mergeLoadedSessions(List<ChatSession> incoming) {
    if (incoming.isEmpty) return 0;
    final existingIds = _sessions.map((s) => s.id).toSet();
    final older = incoming.where((s) => !existingIds.contains(s.id)).toList();
    if (older.isEmpty) return 0;
    _sessions = [..._sessions, ...older];
    return older.length;
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
    _agenticEnabled = false; // Default off for new chat
    _deepResearchEnabled = false; // Default off for new chat
    _studyModeEnabled = false; // Default off for new chat
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
              _agenticEnabled = false; // Default off for new chat
              _deepResearchEnabled = false; // Default off for new chat
              _studyModeEnabled = false; // Default off for new chat
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
              messages: [
                const ChatMessage(
                  role: MessageRole.assistant,
                  text:
                      'New chat ready. Choose any configured provider and model.',
                ),
              ],
              providerId: _selectedProviderId,
              model: _activeModel,
            );
            _sessions.insert(0, newSession);
            _activeSessionId = newId;
            _agenticEnabled = false; // Default off for new chat
            _deepResearchEnabled = false; // Default off for new chat
            _studyModeEnabled = false; // Default off for new chat
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
    try {
      await _deepResearchBridge.reset();
    } catch (e) {
      throw StateError('Deep Research bridge reset failed: $e');
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

  Future<Map<String, dynamic>> _summarizeSourceInline({
    required String sourceUrl,
    required String content,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    // Keep head + tail so long pages retain both lede and late conclusions.
    final String truncatedContent;
    if (content.length > 12000) {
      final head = content.substring(0, 12000);
      final tailStart = content.length > 2000 ? content.length - 2000 : 0;
      final tail = content.substring(tailStart);
      truncatedContent = '$head\n...[middle truncated]...\n$tail';
    } else {
      truncatedContent = content;
    }
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
      final responseText = await _retryLlmCall(
        messages: summarizerMessages,
        provider: provider,
        settings: settings,
        model: model,
      );
      final cleanResp = responseText
          .replaceAll(RegExp(r"```json"), "")
          .replaceAll("```", "")
          .trim();
      final jsonMatch = RegExp(r"\{[\s\S]*\}").firstMatch(cleanResp);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        // Preserve confidence via shared normalizer (facts + findings).
        return DeepResearchHelpers.normalizeEvidence(
          parsed,
          sourceUrl: sourceUrl,
        );
      }
    } catch (e) {
      debugPrint("Inline summarization failed for $sourceUrl: $e");
    }
    return {
      'facts': <Map<String, dynamic>>[],
      'findings': <Map<String, dynamic>>[],
    };
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
    
    for (final item in rawFacts) {
      if (item is! Map) continue;
      final sourceUrl = item['source']?.toString() ?? '';
      // Validate source is one of the expected URLs to catch hallucinations
      final normalizedSource = expectedSources.contains(sourceUrl)
          ? sourceUrl
          : expectedSources.first; // Fallback to first if LLM hallucinated
      facts.add({
        'metric': item['metric']?.toString() ?? '',
        'subject': item['subject']?.toString() ?? '',
        'value': item['value']?.toString() ?? '',
        'date': item['date']?.toString() ?? '',
        'source': normalizedSource,
        'confidence': item['confidence']?.toString() ?? 'high',
      });
    }
    for (final item in rawFindings) {
      if (item is! Map) continue;
      final sourceUrl = item['source']?.toString() ?? '';
      final normalizedSource = expectedSources.contains(sourceUrl)
          ? sourceUrl
          : expectedSources.first;
      findings.add({
        'text': item['text']?.toString() ?? '',
        'source': normalizedSource,
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
        combinedContent.writeln(content.substring(0, 8000));
        combinedContent.writeln('...[truncated]');
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

  Future<bool> _checkResearchSufficiency({
    required String phaseGoal,
    required List<Map<String, dynamic>> facts,
    required List<Map<String, dynamic>> findings,
    required ProviderDefinition provider,
    required ProviderSettings settings,
    required String model,
  }) async {
    if (facts.isEmpty && findings.isEmpty) return false;
    final factsText = facts
        .map(
          (f) =>
              "Fact: metric=${f['metric']} | subject=${f['subject']} | value=${f['value']} | source=${f['source']}",
        )
        .join("\n");
    final findingsText = findings
        .map((f) => "Finding: ${f['text']} (source=${f['source']})")
        .join("\n");
    final prompt =
        "Phase Goal/Prompt: $phaseGoal\n\n"
        "Facts gathered so far:\n$factsText\n\n"
        "Findings gathered so far:\n$findingsText\n\n"
        "Based ONLY on the facts and findings above, have we gathered sufficient information to address the phase goal/prompt?\n"
        "Respond with a JSON object: {\"sufficient\": true | false, \"reason\": \"<short explanation>\"}";
    final messages = [
      const ChatMessage(
        role: MessageRole.system,
        text: DeepResearchPrompts.reflectorSystemPrompt,
      ),
      ChatMessage(role: MessageRole.user, text: prompt),
    ];
    try {
      final responseText = await _chatClient.sendChat(
        provider: provider,
        settings: settings,
        model: model,
        messages: messages,
        studyModeEnabled: _studyModeEnabled,
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
      r'^\s*```(?:markdown|md)\s*\n([\s\S]*?)\n?```\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.trim() ?? text.trim();
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
    _messageController.addListener(_handleMessageTextChanged);
    _loadSettings();
  }

  @override
  void dispose() {
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
      _agenticEnabled = agenticRaw ?? true;
      _artifactsEnabled = artifactsRaw ?? true;
      _svgVisualsEnabled = svgVisualsRaw ?? true;
      _shellPermission = prefs.getString('shell_permission_v1') ?? 'ask';
      _agenticWorkspace =
          agenticWorkspaceRaw ?? '/data/data/com.termux/files/home';
      _customMcpUrl = customMcpUrlRaw ?? '';
      _deepResearchEnabled = deepResearchRaw ?? false;
      _studyModeEnabled = prefs.getBool('study_mode_enabled_v1') ?? false;
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
    await prefs.setString(
      'search_settings_v1',
      jsonEncode(_searchSettings.toJson()),
    );
    await prefs.setBool('agentic_enabled_v1', _agenticEnabled);
    await prefs.setBool('artifacts_enabled_v1', _artifactsEnabled);
    await prefs.setBool('svg_visuals_enabled_v1', _svgVisualsEnabled);
    await prefs.setString('shell_permission_v1', _shellPermission);
    await prefs.setBool('deep_research_enabled_v1', _deepResearchEnabled);
    await prefs.setBool('study_mode_enabled_v1', _studyModeEnabled);
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
    final current =
        _settings[provider.id] ?? ProviderSettings.defaults(provider);
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
              (m) => m.text.contains('<research_state>'),
            )) {
          systemPromptText = DeepResearchPrompts.plannerSystemPrompt;
        } else {
          systemPromptText =
              "Date: $currentDateStr. Use current-year data unless asked otherwise.\n\n"
              "Render via markdown code blocks:\n"
              "- LaTeX: \\[ ... \\] or \\( ... \\)\n";

          if (_studyModeEnabled) {
            systemPromptText +=
                "\n\n[MODE: STUDY / CROSS-DOCUMENT ANALYSIS]\n"
                "You are a patient tutor and a document analyst. You answer from the user's uploaded documents when they exist, and teach concepts step by step.\n\n"
                "SOURCE RULE (check first):\n"
                "- Workspace HAS documents → every fact must come from workspace tools. Do NOT answer from memory.\n"
                "- Workspace is EMPTY → teach from your own knowledge. Do NOT call workspace tools.\n"
                "- Not sure? Call workspace_list once.\n\n"
                "TOOLBOX — emit EXACTLY ONE tool per turn, then STOP and wait:\n"
                "1. workspace_list = SEE the file list.\n"
                "   USE WHEN: first document question of the session; user asks what files exist.\n"
                "   <mcp_request>{\"method\":\"workspace_list\",\"params\":{}}</mcp_request>\n"
                "2. workspace_search = FIND a fact (best chunks overall).\n"
                "   USE WHEN: question about one topic, e.g. 'what does the report say about diesel?'.\n"
                "   <mcp_request>{\"method\":\"workspace_search\",\"params\":{\"queries\":[\"diesel price\"],\"top_k\":5}}</mcp_request>\n"
                "3. workspace_cross_compare = COMPARE the same topic across ALL documents (one result group per file).\n"
                "   USE WHEN: change over time or differences between documents, e.g. 'how did crude oil price change 2020 to 2026?', 'compare fuel prices across all reports'.\n"
                "   <mcp_request>{\"method\":\"workspace_cross_compare\",\"params\":{\"query\":\"crude oil price\",\"max_per_doc\":2}}</mcp_request>\n"
                "4. workspace_read_page = READ one full page of one file.\n"
                "   USE WHEN: a search chunk is cut off or unclear and you need the whole page.\n"
                "   <mcp_request>{\"method\":\"workspace_read_page\",\"params\":{\"file_path\":\"file.pdf\",\"page\":1}}</mcp_request>\n"
                "5. workspace_get_outline = SEE headings/chapters of one file.\n"
                "   USE WHEN: you don't know which page or section to read.\n"
                "   <mcp_request>{\"method\":\"workspace_get_outline\",\"params\":{\"file_path\":\"file.pdf\"}}</mcp_request>\n"
                "6. workspace_ingest = INDEX a file that is in the workspace but returns nothing in searches.\n"
                "   USE WHEN: workspace_list shows a file, but workspace_search finds nothing inside it.\n"
                "   <mcp_request>{\"method\":\"workspace_ingest\",\"params\":{\"file_path\":\"/path/to/file\"}}</mcp_request>\n"
                "7. quiz_request = TEST the user (TUTOR RULES below).\n"
                "   USE WHEN: the user replied yes to the understanding check.\n\n"
                "CHEAT-SHEET (pick the tool by the question shape):\n"
                "- 'what files do I have?' → workspace_list\n"
                "- 'what does the document say about X?' → workspace_search\n"
                "- 'how did X change over the years / across documents?' → workspace_cross_compare\n"
                "- 'which chapter covers Y?' → workspace_get_outline\n"
                "- 'give me the full page about Z' → workspace_read_page\n"
                "- 'teach me T' → explain ONE concept, understanding check, then quiz_request\n\n"
                "ANSWER RULES:\n"
                "1. Cite every fact: [Source: file.pdf, Page N] when the tool result provides it.\n"
                "2. For workspace_cross_compare results: build ONE markdown table with one row per document (ordered by year or file name), then 2-3 sentences of trend (rising / falling / stable).\n"
                "3. Documents disagree → show both values and say they disagree. Never pick one silently.\n"
                "4. No document mentions the topic → say so plainly; do not invent numbers.\n\n"
                "TUTOR RULES (when the user wants to learn):\n"
                "1. Teach ONE concept per reply (what it is, why it matters). Never the whole topic at once.\n"
                "2. End EVERY explanation with exactly: 'Reply yes if you understood this concept, or no and I will explain it more simply.'\n"
                "3. User says no → explain the SAME concept simpler (analogy, tiny steps), ask again.\n"
                "4. User says yes → emit ONE <quiz_request> about this concept BEFORE the next concept.\n"
                "5. Quiz results back → explain every WRONG verdict clearly, ask the check again, then move on.\n"
                "6. Order concepts basic → advanced; make quizzes harder as the session goes.\n"
                "7. USER SWITCHES TOPIC WITHOUT yes/no: if the user asks for a different concept instead of answering yes/no, do not switch yet. First say politely: 'Before we move on, please answer these quick questions about what we just learned.' Then emit a <quiz_request> about the concept you just explained. When results return, explain every WRONG verdict clearly, then teach the concept the user asked for.\n\n"
                "QUIZ FORMAT:\n"
                "<quiz_request>{\"questions\":[{\"q\":\"Question?\",\"options\":[\"A\",\"B\",\"C\",\"D\"],\"correct\":0}]}</quiz_request>\n"
                "1-10 questions; 2-4 options; exactly ONE correct (index in \"correct\"); options get trickier down the list; never 'all of the above'.\n"
                "RANDOMIZE THE CORRECT INDEX — NO PATTERN: pick each question's \"correct\" index at random from its valid range. Never sequential (0,1,2,3,0,1...), never alternating (0,1,0,1...), never fixed on one index (e.g. always 0 or always 1), and never repeat the same index on consecutive questions. Before emitting the quiz_request, check the full list of \"correct\" values you chose — if you see any repeating or sequential pattern, reassign indices until the placement looks genuinely random.\n\n";
          }

          if (_svgVisualsEnabled) {
            systemPromptText +=
                "- SVG VISUALS (flowcharts, architecture, state-machines, illustrations): ```svg\n"
                "  Root: width=\"100%\" viewBox=\"0 0 800 450\" preserveAspectRatio=\"xMidYMid meet\"\n"
                "  IMPORTANT: SVGs MUST be strictly enclosed with `<svg>` and `</svg>` tags.\n"
                "  SELECTIVE INTERACTIVITY GUIDANCE:\n"
                "  - Static Diagrams (Architecture, Pipelines): Keep SVG clean without scripts/events.\n"
                "  - Interactive Diagrams (Toggle Switches, State Machines, Interactive Components): Include embedded `onclick=\"this.classList.toggle('active')\"`, CSS hover effects, or state transitions if interactivity enhances understanding.\n\n";
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
                "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. Use ```svg ONLY for non-graph diagrams (flowcharts, architecture, state-machines, illustrations). NEVER use SVG for charts. ALWAYS include the closing </svg> tag for SVGs.\n";
          } else {
            systemPromptText +=
                "CRITICAL DIRECTIVE ON VISUALS: You MUST proactively generate ```chart blocks whenever discussing data, comparisons, metrics, statistics, or trends. Do NOT generate SVG visuals.\n";
          }

          if (_agenticEnabled && !_studyModeEnabled) {
            systemPromptText += r"""
AGENTIC IDE — You are the AI engine of a real, production-grade mobile IDE powered by Termux on Android.
You have full shell access AND a suite of structured file tools via a Python bridge.

━━ CORE RULES ━━
1. STRICT ONE-TOOL-AT-A-TIME (NON-NEGOTIABLE): Use EXACTLY ONE tool per turn. Emit a single tool block (`<tool_request>`, `<search_request>`, `<read_url>`, `<memory>`, or `<run_command>`), then STOP. NEVER emit two or more tool calls in the same response. NEVER emit a second tool call in the same response as a fallback.
2. WAIT FOR OUTPUT, THEN PROCEED: After emitting a tool call you MUST stop and wait for its result to come back before doing anything else. You may NOT assume, guess, or continue the workflow in the same turn. The next tool call may only be emitted in a NEW response AFTER you have actually seen the previous tool's result.
3. ONE STEP PER TURN: Each turn advances the workflow by exactly one tool call. read → WAIT → then edit. edit → WAIT → then verify. Never skip the waiting step and never batch steps together.
4. STRUCTURED TOOLS FIRST: ALWAYS prefer structured file tools (`<tool_request>`) over raw shell commands (`run_command`) for file operations.
5. NO BLIND REWRITES: NEVER rewrite a whole file to make a small edit. Use `patch_file` or `replace_lines`.
6. READ BEFORE EDIT: NEVER edit a file from memory. Always use `read_file_rich` to verify exact content and whitespace first.
7. NO PLACEHOLDERS: Write clean, production-grade code. No TODOs, no incomplete logic. Handle errors explicitly.

━━ CODE NAVIGATION PROTOCOL (STRICT) ━━
NEVER read an entire file blindly. Follow this workflow based on file size:
• SMALL FILE FAST-PATH (< 150 lines): Call `read_file_rich` directly.
• LARGE FILE OUTLINE (> 150 lines): 
  1. GET THE MAP: Use `<method>file_outline</method>` to get structured symbol line numbers.
  2. READ SPECIFIC LINES: Use `<method>read_file_rich</method>` with `start_line` and `end_line` to read target ranges.
  3. MULTI-READ: Use `<method>multi_read_rich</method>` to fetch multiple non-adjacent sections or files in ONE call.

━━ STRUCTURED FILE TOOLS ━━
Use XML format: `<tool_request><method>NAME</method><param>value</param>...</tool_request>`
CRITICAL: Always use direct tag format like `<path>/foo</path>`. Do NOT use `<PARAM name="path">/foo</PARAM>`. Works on ALL file types.

── READ & SEARCH ──
• read_file_rich: Read file (max 600 lines). Returns numbered lines, size, language.
  <tool_request><method>read_file_rich</method><path>/absolute/path.ext</path><start_line>1</start_line><end_line>120</end_line></tool_request>
• multi_read_rich: Read multiple files/ranges in ONE call.
  <tool_request><method>multi_read_rich</method><reads>[{"path":"/src/main.ts","start_line":45,"end_line":80},{"path":"/config.json"}]</reads></tool_request>
• search_rich: Grep across codebase (max 50 results).
  <tool_request><method>search_rich</method><path>/src</path><query>myFunctionName</query><include>*</include><case_insensitive>false</case_insensitive></tool_request>
• file_outline: Get class/function/struct structure with line numbers.
  <tool_request><method>file_outline</method><path>/src/main.ext</path></tool_request>
• symbol_references: Find cross-file references before renames.
  <tool_request><method>symbol_references</method><symbol>MyClass</symbol><path>/projects/myapp/src</path></tool_request>
• tree: List project structure.
  <tool_request><method>tree</method><path>/projects/myapp</path><max_depth>3</max_depth></tool_request>
• find_files: <tool_request><method>find_files</method><pattern>*.dart</pattern><path>/projects/myapp</path><max_results>100</max_results></tool_request> (glob file names)
• symbol_search: <tool_request><method>symbol_search</method><symbol>MyClass</symbol><path>/projects/myapp/src</path></tool_request> (locate definitions across files)

── EDIT & CREATE ──
• patch_file: Multi search-and-replace, atomic, outputs unified diff. The tool request and all parameter tags are XML; the VALUE inside `<patches>` MUST be a valid JSON array because this parameter is a list of patch objects. Each item has string `search` and `replace`, plus optional integer `count` (0 = all matches) and `label`. Escape newlines inside the JSON strings as `\n`; search text must EXACTLY match, including whitespace. If any item fails, NO changes are written.
  <tool_request><method>patch_file</method><path>/absolute/path.ext</path><patches>[{"search":"old code\n","replace":"new code\n","count":1,"label":"fix"}]</patches></tool_request>
• replace_lines: Replace a specific line range (use after reading exact line numbers).
  <tool_request><method>replace_lines</method><path>/file.ext</path><start_line>45</start_line><end_line>52</end_line><new_content>  // New code</new_content></tool_request>
• write_file_rich: Create or overwrite entire file. For existing files, pass `<expected_sha256>` if available.
  <tool_request><method>write_file_rich</method><path>/newfile.ext</path><content>full content</content><create_dirs>true</create_dirs></tool_request>
• insert_lines: Insert after a specific line.
  <tool_request><method>insert_lines</method><path>/file.ext</path><after_line>120</after_line><content>  // New code</content></tool_request>
• append_file: Append to file (safe for .env, pubspec.yaml, logs).
  <tool_request><method>append_file</method><path>/file.log</path><content>New line</content></tool_request>

── FILE SYSTEM MANAGEMENT ──
• delete_path: <tool_request><method>delete_path</method><path>/path</path><recursive>false</recursive></tool_request> (recursive=true for dirs)
• move_path: <tool_request><method>move_path</method><src>/old</src><dest>/new</dest><overwrite>false</overwrite></tool_request>
• copy_path: <tool_request><method>copy_path</method><src>/src</src><dest>/dest</dest><overwrite>false</overwrite></tool_request>
• mkdir_path: <tool_request><method>mkdir_path</method><path>/new/dir</path><parents>true</parents></tool_request>
• stat_path: <tool_request><method>stat_path</method><path>/file.ext</path></tool_request> (Checks existence, size, sha256, mtime)
• chmod_path: <tool_request><method>chmod_path</method><path>/script.sh</path><mode>755</mode><recursive>false</recursive></tool_request>
• diff_files: <tool_request><method>diff_files</method><path_a>/a.ext</path_a><path_b>/b.ext</path_b></tool_request>
• list_trash: <tool_request><method>list_trash</method></tool_request> (see soft-deleted files)
• restore_trash: <tool_request><method>restore_trash</method><name>TRASH_NAME</name><dest>/optional/path</dest></tool_request>
• tool_help: <tool_request><method>tool_help</method></tool_request> — live reference of ALL hybrid tools with exact params. Call it whenever unsure about a tool's parameters.

── SHELL & BACKGROUND ──
• run_command: For build tools, git, installs — NOT for file reading/editing.
  <tool_request><method>run_command</method><command>npm test</command><cwd>/projects/myapp</cwd></tool_request>
• run_background: For long-running processes (dev servers).
  <tool_request><method>run_background</method><command>npm run dev</command><name>web</name><cwd>/projects/myapp</cwd></tool_request>
• background_time_limit: Wait for background service (max 90s pause).
  <tool_request><method>background_time_limit</method><pid>12345</pid><time_limit_seconds>30</time_limit_seconds><poll_interval_seconds>2</poll_interval_seconds></tool_request>
  (Other bg tools: list_services, service_status, service_logs, stop_service)

── DART & GIT TOOLS ──
• dart_diagnostics: <tool_request><method>dart_diagnostics</method><path>/projects/myapp</path></tool_request>
• dart_format: <tool_request><method>dart_format</method><path>/main.dart</path><output>none</output></tool_request> (output=none to check, output=write to apply)
• git_status: <tool_request><method>git_status</method><cwd>/projects/myapp</cwd></tool_request>
• git_diff: <tool_request><method>git_diff</method><staged>false</staged><cwd>/projects/myapp</cwd></tool_request>
• git_commit: <tool_request><method>git_commit</method><message>feat: x</message><add_all>true</add_all><cwd>/projects/myapp</cwd></tool_request>
• git_push: <tool_request><method>git_push</method><message>feat: x</message><branch>main</branch><cwd>/projects/myapp</cwd></tool_request>
• git_pull: <tool_request><method>git_pull</method><branch>main</branch><cwd>/projects/myapp</cwd></tool_request>

━━ DECISION GUIDE ━━
| Task | Use | NOT |
|---|---|---|
| Read file / check code | read_file_rich | cat, head, tail |
| Read multiple files | multi_read_rich | multiple read_file_rich turns |
| Edit multiple sections | patch_file (array of patches) | sed -i, rewrite whole file |
| Edit by line number | replace_lines | sed -i |
| Create new file | write_file_rich | cat > file << 'EOF' |
| Append to file / log | append_file | echo >> |
| Search codebase | search_rich | grep -rn |
| List structure | tree | ls -la |
| Delete / Move / Copy | delete_path / move_path / copy_path | rm / mv / cp |
| Check file existence | stat_path | ls -la |
| Dart syntax check | dart_format (output=none) | raw dart analyze |
| Full Dart analysis | dart_diagnostics | raw dart analyze |
| Git status / diff / commit | git_status / git_diff / git_commit | raw git via run_command |
| Build / installs | run_command | N/A |
| Long-running server | run_background | run_command |
| Wait for background job | background_time_limit | arbitrary sleep command |
| Non-Dart diagnostics | run_command (py_compile, eslint) | dart_diagnostics |

━━ VERSATILE TOOL STRATEGIES (DUAL-USE PRO TIPS) ━━
1. FAST SYNTAX SANITY CHECK: Before full `dart_diagnostics`, run `dart_format` with `<output>none</output>`. It fails instantly on syntax errors without waiting for analyzer.
2. INTEGRITY GUARD: Use `stat_path` to check file existence and `sha256`/`mtime` before reading or editing to ensure external state hasn't changed.
3. SAFE CONFIG EDITS: Use `append_file` for `.env`, `pubspec.yaml`, or `.gitignore`. It cannot erase existing content like `patch_file` might.
4. CROSS-FILE INSPECTION: Use `multi_read_rich` to read a model and its controller simultaneously to save turns.
5. PRE-FLIGHT SHELL GUARDS: Before running complex shell binaries, ensure tools exist in Termux to prevent bash failures.

━━ STANDARD OPERATING PROCEDURES (SOPs) ━━

1. LOCATING AN UNKNOWN SYMBOL:
   search_rich → file_outline (on matched file) → read_file_rich (target lines).

2. EDITING CODE (STRICT LOOP):
   read_file_rich (verify exact content) → patch_file / replace_lines → dart_diagnostics / linter → Report result.
   * If `patch_file` fails due to mismatch: DO NOT use `write_file_rich`. Call `read_file_rich` on that exact range, inspect whitespace, and retry `patch_file` OR use `replace_lines` with exact line numbers.

3. HANDLING FAILED SHELL COMMANDS (run_command):
   Read error → Missing tool? Use install_package. Syntax error? Use linter. Permission denied? Use chmod_path. Git conflict? git_status + git_diff → patch_file. NEVER retry blindly.

4. GIT OPERATIONS:
   Use structured Git tools. Do NOT use raw `git` via run_command unless unavoidable.
   Flow: git_status → git_diff → git_commit/git_push.

━━ RESPONSE PROTOCOL & SAFETY ━━
• Automatic safety snapshots are created before file mutations. If an edit fails catastrophically, use `run_command` with `git restore <file>`.
• TRUSTED WORKSPACE: file mutations inside the workspace execute WITHOUT permission prompts — the bridge jail, trash and audit log protect you. Anything targeting paths outside the workspace asks the user first. Deleted files are recoverable via list_trash / restore_trash.
• Keep final responses concise. Summarize edited files, key logic changes, and diagnostic results.
• NEVER dump full file contents into chat if you already edited them via tools.
• For every project, maintain a README.md at the project root.
""";
          }

          if (_customMcpUrl.isNotEmpty) {
            systemPromptText +=
                "Remote MCP at $_customMcpUrl — add \"server\":\"remote\" to params to use it.\n";
          }

          if (_searchSettings.enabled) {
            systemPromptText +=
                "\n━━ WEB SEARCH PROTOCOL (STRICT ENFORCEMENT) ━━\n"
                "NEVER guess, hallucinate, or provide outdated information for time-sensitive queries, recent events, current software/library versions, or facts outside your knowledge cutoff. If you are not 100% certain, you MUST use the web.\n\n"
                "STRICT WORKFLOW (Respect the ONE tool call per turn rule):\n"
                "1. SEARCH: Output <search_request>precise query here</search_request> to get search results, then STOP. Wait for the result.\n"
                "   - RECENCY: For time-sensitive queries (news, versions, releases), ALWAYS add time_range=\"week\" or time_range=\"day\". Example: <search_request time_range=\"week\">latest flutter version</search_request>\n"
                "2. READ: After viewing the search results, output <read_url>URL</read_url> to fetch the full content of the most relevant page, then STOP. Wait for the result.\n"
                "3. CROSS-REFERENCE: Do NOT rely on a single source. If the first source is insufficient, outdated, or lacks detail, perform another <search_request> with a different query or read another <read_url>. Continue searching until you have verified, up-to-date information from multiple sources.\n"
                "4. ANSWER: Synthesize the fetched page content to provide an accurate, up-to-date response with citations.\n\n"
                "CRITICAL: Never skip Step 1 or Step 2. Do not answer from memory if the topic requires live data. If search results are insufficient or outdated, perform another <search_request> with a different query. You MUST keep searching until you find current, accurate information.\n";
          }

          systemPromptText +=
              "\nMemory Tool: Use <memory action=\"read\"></memory>, <memory action=\"append\">text</memory>, or <memory action=\"replace\">text</memory> to save/read personal details across sessions. Limit 10KB. Use only when essential.\n";
        }

        if (_liveVoiceEngine.state != LiveVoiceState.idle) {
          systemPromptText +=
              "\n\n━━ LIVE VOICE MODE (TTS ACTIVE) ━━\n"
              "Your text output is being read aloud via Text-to-Speech. Apply these output rules strictly on top of all other capabilities (Agentic, Web Search):\n\n"
              "1. PERSONA: Always address the user as 'Boss' (e.g., 'Yes Boss...', 'Right away, Boss.').\n"
              "2. EXTREME CONCISENESS: Keep spoken text brief and conversational (1-3 sentences max). Get straight to the point.\n"
              "3. NO MARKDOWN: NEVER use markdown formatting (*, #, or code blocks). Speak in plain, natural sentences.\n"
              "4. TOOL ACKNOWLEDGMENT: When using ANY tools (Agentic, Git, or Web Search), provide a 1-sentence spoken acknowledgment first (e.g., 'Working on it, Boss.'), then emit your ONE tool tag. Do NOT explain the code or search process out loud.\n"
              "5. RESULT REPORTING: After a tool result returns, provide a brief spoken summary of the outcome (e.g., 'Done, Boss. Pushed it to GitHub.' or 'Here is the information, Boss.').\n"
              "6. RESTRICTIONS: Do NOT launch Deep Research or heavy SVG rendering. Keep all actions lightweight and fast.\n";
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
          studyModeEnabled: _studyModeEnabled,
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
                if (_liveVoiceEngine.state == LiveVoiceState.thinking ||
                    _liveVoiceEngine.state == LiveVoiceState.speaking) {
                  // Skip tool-call / SSML tag chunks so they are not spoken
                  // (e.g. <tool_request>, <dialect>, </reasoning>). Pure
                  // speech chunks are stripped of SSML at enqueue time.
                  if (!textChunk.contains('<')) {
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

        // IMPROVEMENT: accept attribute-bearing tags like
        // <search_request time_range="month">… — the old pattern only matched
        // bare tags, so attributed searches rendered raw and never executed.
        final searchRegex = RegExp(
          r'<search_request\b([^>]*)>\s*([\s\S]*?)\s*</search_request>',
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
        final quizRegex = RegExp(
          r'<quiz_request>\s*(\{[\s\S]*?\})\s*</quiz_request>',
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
            r'<phase\s*(\d+)\s*>(.*?)</phase\s*\d+\s*>',
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

        if (_searchSettings.enabled && searchMatch != null) {
          final searchMatches = searchRegex.allMatches(fullText);
          for (final match in searchMatches) {
            executedTools = true;
            final query = match.group(2)?.trim() ?? '';
            // IMPROVEMENT: parse tag attributes (time_range/topic/dates) and
            // forward them so recency-filtered searches work in chat mode.
            final attrStr = match.group(1) ?? '';
            String? searchAttr(String name) {
              final m = RegExp(
                '$name="([^"]*)"',
                caseSensitive: false,
              ).firstMatch(attrStr);
              final v = m?.group(1)?.trim();
              return (v == null || v.isEmpty) ? null : v;
            }
            if (mounted) setState(() => _toolStatus = '🔍 Searching: "$query"');
            final searchResultRaw = await _chatClient.searchWeb(
              query,
              _searchSettings.provider,
              [_searchSettings.apiKey, ..._searchSettings.fallbackApiKeys],
              googleCx: _searchSettings.googleCx,
              topic: searchAttr('topic'),
              timeRange: searchAttr('time_range'),
              startDate: searchAttr('start_date'),
              endDate: searchAttr('end_date'),
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

              urlResult = text;
              if (urlResult.length > 8000) {
                // Truncate at a sentence boundary to avoid cutting mid-sentence
                final substring = urlResult.substring(0, 8000);
                final lastPeriod = substring.lastIndexOf('. ');
                final endIdx = lastPeriod > 6000 ? lastPeriod + 1 : 8000;
                urlResult =
                    urlResult.substring(0, endIdx) +
                    '\n\n...[truncated due to length]';
              }
            } catch (e) {
              urlResult = 'Error fetching URL: $e';
            }
            if (mounted) setState(() => _toolStatus = '');
            toolOutputs.add("Content of URL '$url':\n\n$urlResult");
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

        if ((_agenticEnabled || _studyModeEnabled) && mcpMatch != null) {
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
              _resolveToolPaths(toolParams, _agenticWorkspace);
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

        final quizMatch = quizRegex.firstMatch(fullText);
        if (_studyModeEnabled && quizMatch != null) {
          executedTools = true;
          // Hide the raw <quiz_request> tag from the visible bubble and from
          // future API history; the quiz-results system message (below)
          // carries the questions/answers forward for the model.
          setState(() {
            final idx = _sessions.indexWhere((s) => s.id == targetSessionId);
            if (idx != -1) {
              final msgs = List<ChatMessage>.from(_sessions[idx].messages);
              if (assistantMessageIndex < msgs.length) {
                final cleaned = msgs[assistantMessageIndex].text
                    .replaceFirst(quizMatch.group(0) ?? '', '')
                    .trim();
                msgs[assistantMessageIndex] = msgs[assistantMessageIndex]
                    .copyWith(text: cleaned);
                _sessions[idx] = _sessions[idx].copyWith(messages: msgs);
              }
            }
          });
          final questions = _QuizSheet.parseQuestions(quizMatch.group(1) ?? '');
          if (questions.isEmpty) {
            toolOutputs.add('Quiz Tool Result:\n\n{"error":"malformed quiz_request, no valid questions"}');
          } else {
            final answers = await showModalBottomSheet<List<Map<String, dynamic>>>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              isDismissible: false,
              builder: (_) => _QuizSheet(questions: questions),
            );
            if (answers == null) {
              toolOutputs.add('Quiz Tool Result:\n\nUser dismissed the quiz without answering. Ask whether to retry or skip, then continue teaching.');
            } else {
              final sb = StringBuffer('Quiz results (${answers.length} questions):\n');
              for (var qi = 0; qi < answers.length; qi++) {
                final a = answers[qi];
                sb.writeln('Q${qi + 1}: ${a['q']}');
                sb.writeln('  User answer: ${a['picked']}');
                sb.writeln(a['correct'] == true
                    ? '  Verdict: CORRECT'
                    : '  Verdict: WRONG (correct answer: ${a['answer']})');
              }
              sb.writeln('Explain every WRONG verdict clearly, then repeat the understanding check before the next concept.');
              toolOutputs.add(sb.toString());
            }
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
          final toolResultMatch = RegExp(
            r'Tool Result \[(\w+)\]',
          ).firstMatch(newText);
          final mcpMatch = newText.contains('MCP Result:\n');
          final method = toolResultMatch?.group(1)?.trim();
          const keepRichToolMethods = {
            'read_file_rich',
            'file_outline',
            'file_outline_rich',
            'search_rich',
            'tree',
            'tree_rich',
            'multi_read_rich',
            'find_files',
            'symbol_search',
            'symbol_references',
            'workspace_list',
            'workspace_search',
            'workspace_read_page',
            'workspace_get_outline',
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
        compacted.add(
          ChatMessage(
            role: msg.role,
            text: msg.text,
            isError: msg.isError,
            reasoning: msg.reasoning,
            images: msg.images,
            videos: msg.videos,
            files:
                const [], // Strip attached files from intermediate user messages to avoid re-sending large base64 contents
          ),
        );
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
                _PermissionInfoRow(label: 'Tool', value: method),
                const SizedBox(height: 8),
                _PermissionInfoRow(label: 'Target', value: target),
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

  Match? _findMcpMatch(String fullText) {
    // 0. Try direct command format: <command>...</command> (case-insensitive with spacing support & unclosed fallback)
    final cmdStartMatch = RegExp(
      r'<command\s*>',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (cmdStartMatch != null) {
      final cmdEndMatch = RegExp(
        r'</command\s*>',
        caseSensitive: false,
      ).firstMatch(fullText);
      final String commandVal;
      if (cmdEndMatch != null) {
        commandVal = fullText
            .substring(cmdStartMatch.end, cmdEndMatch.start)
            .trim();
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

    final toolRequestJson = _findToolRequestMatch(fullText);
    if (toolRequestJson != null) {
      return RegExp(r'([\s\S]*)').firstMatch(toolRequestJson);
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

  String? _findToolRequestMatch(String fullText) {
    final xmlStartMatch = RegExp(
      r'<tool_request\s*>',
      caseSensitive: false,
    ).firstMatch(fullText);
    String? xmlContent;
    if (xmlStartMatch != null) {
      final xmlEndMatch = RegExp(
        r'</tool_request\s*>',
        caseSensitive: false,
      ).firstMatch(fullText);
      if (xmlEndMatch != null) {
        xmlContent = fullText.substring(xmlStartMatch.end, xmlEndMatch.start);
      } else {
        xmlContent = fullText.substring(xmlStartMatch.end);
      }
    } else if (RegExp(r'<method\s*>', caseSensitive: false).hasMatch(fullText)) {
      xmlContent = fullText;
    }
    if (xmlContent == null) return null;

    final Map<String, dynamic> result = {};
    const preserveWhitespaceKeys = {'content', 'new_content', 'patches', 'reads'};

    String cleanToolValue(String key, String value) {
      if (preserveWhitespaceKeys.contains(key)) {
        var output = value;
        if (output.startsWith('\n')) output = output.substring(1);
        if (output.endsWith('\n')) output = output.substring(0, output.length - 1);
        return output;
      }
      return value.trim();
    }

    final regex = RegExp(
      r'<([a-zA-Z0-9_]+)(?:\s+[^>]*?)?>([\s\S]*?)</\1\s*>',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(xmlContent)) {
      final key = match.group(1)!.toLowerCase();
      result[key] = cleanToolValue(key, match.group(2)!);
    }

    final paramRegex = RegExp(
      r'''<[Pp][Aa][Rr][Aa][Mm]\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp][Aa][Rr][Aa][Mm]>''',
    );
    for (final m in paramRegex.allMatches(xmlContent)) {
      final key = m.group(1)!.toLowerCase();
      result[key] = cleanToolValue(key, m.group(2)!);
    }

    final paramRegex2 = RegExp(
      r'''<[Pp]arameter\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp]arameter>''',
      caseSensitive: false,
    );
    for (final m in paramRegex2.allMatches(xmlContent)) {
      final key = m.group(1)!.toLowerCase();
      result[key] = cleanToolValue(key, m.group(2)!);
    }

    if (!result.containsKey('method')) return null;
    for (final key in ['method', 'path', 'query', 'start_line', 'end_line', 'pattern', 'command']) {
      if (result.containsKey(key) && result[key] is String) {
        result[key] = (result[key] as String).trim();
      }
    }
    final method = result['method'];
    result.remove('method');
    return jsonEncode({'method': method, 'params': result});
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
    final newStateStr =
        '<research_state>${jsonEncode(stateMap)}</research_state>';
    final startIdx = oldText.indexOf('<research_state>');
    if (startIdx == -1) {
      return oldText.isEmpty ? newStateStr : '$oldText\n\n$newStateStr';
    }
    final endIdx = oldText.indexOf('</research_state>', startIdx);
    if (endIdx == -1) {
      return oldText.substring(0, startIdx) + newStateStr;
    }
    return oldText.substring(0, startIdx) +
        newStateStr +
        oldText.substring(endIdx + 17);
  }

  String _preprocessUnrecognizedToolCalls(
    String text,
    List<Map<String, dynamic>> unrecognizedErrors,
  ) {
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
      if (nameLower.contains('read_url') ||
          nameLower.contains('readurl') ||
          nameLower.contains('fetch')) {
        isKnownTool = true;
        mappedTool = 'read_url';
      } else if (nameLower.contains('web_search') ||
          nameLower.contains('search_web') ||
          nameLower.contains('search_request') ||
          (nameLower.contains('search') && !nameLower.contains('research'))) {
        isKnownTool = true;
        mappedTool = 'search_request';
      } else if (nameLower.contains('mcp_request') ||
          nameLower.contains('mcp_call') ||
          (nameLower.contains('mcp') && !nameLower.contains('mcp_server'))) {
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
          final queryRegex1 = RegExp(
            '(?:query|q)[:\\s="\']+\\s*["\']([^"\']+)["\']',
          );
          final queryRegex2 = RegExp(
            '(?:query|q)[:\\s="\']+\\s*([^\\s"\'\\}]+)',
          );
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
          result =
              result.substring(0, matchStart) +
              replacement +
              result.substring(braceEnd + 1);
          offset = matchStart + replacement.length;
        } else {
          unrecognizedErrors.add({
            'tool': name,
            'error':
                'Unrecognized tool call syntax with unparseable parameters: $fullMatchText',
          });
          offset = braceEnd + 1;
        }
      } else {
        final isGenericCallShape =
            name.contains(':') ||
            nameLower.startsWith('call') ||
            nameLower.startsWith('tool') ||
            nameLower.startsWith('request');
        if (isGenericCallShape) {
          unrecognizedErrors.add({
            'tool': name,
            'error':
                'Generic tool call attempt in unrecognized format: $fullMatchText',
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
      final stateMap =
          editedStateMap ?? (jsonDecode(stateStr) as Map<String, dynamic>);
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
        final stepMatches = RegExp(
          r"<phase\s*(\d+)\s*>(.*?)</phase\s*\d+\s*>",
          caseSensitive: false,
          dotAll: true,
        ).allMatches(planText);

        int stepIdx = 1;
        for (final match in stepMatches) {
          // Keep full queryText; derive a short UI title from the planner's
          // "Title - instructions" / "Title | …" / "… success:" conventions.
          final queryText = match.group(2)?.trim() ?? '';
          final derivedTitle = queryText
              .split(RegExp(r' - | \| | success:', caseSensitive: false))
              .first
              .trim();
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
          plannedSteps.add({
            'id': 'step_1',
            'title': 'General Research',
            'query_text': prompt,
            'status': 'pending',
            'content': '',
            'events': <Map<String, dynamic>>[],
          });
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
                "${crossPhaseContext.length > 0 ? '━━ PREVIOUS PHASE RESULTS (USE AS RESEARCH TARGETS) ━━\nThese entities and findings were discovered in earlier phases. When your current phase requires specific subjects (models, products, tools, etc.), you MUST use ONLY these discovered entities as your search targets. Do NOT substitute or guess entities from your training data.\n$crossPhaseContext\n\n' : ''}"
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
            stepFailure =
                'Research run exceeded global time budget of ${globalTimeBudget.inMinutes} minutes.';
            break;
          }
          // IMPROVEMENT: Per-phase timeout — prevents a single phase from hanging
          // the entire run. Partial results are still passed to the writer.
          if (phaseStartTime.add(phaseTimeout).isBefore(DateTime.now())) {
            stepDone = true;
            stepFailure =
                'Phase exceeded ${phaseTimeout.inMinutes}-minute timeout. Proceeding with partial results.';
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
              messages: _compactHistoryForApi(
                stepMessages,
                stepMessages.length,
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
            turnWatch.stop();

            final unrecognizedErrors = <Map<String, dynamic>>[];
            final preprocessedText = _preprocessUnrecognizedToolCalls(
              responseText,
              unrecognizedErrors,
            );

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
            final hasRawSearchTag =
                preprocessedText.contains('<search_request') ||
                preprocessedText.contains('</search_request');
            final hasRawReadTag =
                preprocessedText.contains('<read_url') ||
                preprocessedText.contains('</read_url');

            if ((hasRawSearchTag && searchMatches.isEmpty) ||
                (hasRawReadTag && readUrlMatches.isEmpty)) {
              isMalformed = true;
            }

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

            final completeMatch = RegExp(
              r'<step_complete/?>',
              caseSensitive: false,
            ).firstMatch(responseText);

            if (completeMatch != null) {
              final contentClean = responseText
                  .replaceAll(
                    RegExp(r'<step_complete/?>', caseSensitive: false),
                    '',
                  )
                  .trim();
              stepContent = stepContent.isEmpty
                  ? contentClean
                  : '$stepContent\n\n$contentClean';
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

                // IMPROVEMENT: Skip duplicate queries already executed in this run
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

                // TOOL LIMITS PER PHASE:
                // Capped at 20 web_search calls per research phase to focus the agent on high-relevance
                // Tavily search queries rather than infinite querying loops. This matches the accuracy-over-depth
                // priority of this project. If this limit is exceeded, we return a clear feedback message.
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

              for (var k = 0; k < searchMatches.length; k++) {
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
                  r'- \[([^\]]+)\]\(([^)]+)\):\s*(.*)',
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
                            'snippet': match.group(3) ?? '',
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

                if (searchError == null &&
                    !isDup &&
                    !isCapError &&
                    searchResult.isNotEmpty) {
                  // Search snippets are discovery leads only. They are never promoted to
                  // facts/findings; evidence is created exclusively after a successful read_url.
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
                      return _deepResearchBridge.readUrl(
                        targetUrl,
                        allowPdf: false,
                        query: queryText,
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
                  text:
                      "You are a research sufficiency judger. Analyze the current facts and findings "
                      "and decide if the phase goal is fully addressed.\n"
                      "Respond with JSON:\n"
                      "{\n"
                      "  \"should_continue\": true | false,\n"
                      "  \"reason\": \"<brief explanation>\",\n"
                      "  \"gaps\": [\"specific gap 1\", \"specific gap 2\", ...]\n"
                      "}\n"
                      "If should_continue is false, gaps should be [].\n"
                      "If should_continue is true, list 2-4 specific, searchable questions that would fill missing information. "
                      "These gaps will guide the next search queries.",
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
                          .take(3)
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
                // Don't silently swallow — log but continue
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

        // Update cross-phase context: entity handoff + compact evidence summary
        if (phaseFacts.isNotEmpty || phaseFindings.isNotEmpty) {
          final entitySet = <String>{};
          for (final f in phaseFacts) {
            final subj = (f['subject'] ?? '').toString().trim();
            if (subj.isNotEmpty) entitySet.add(subj);
          }
          final topFacts = phaseFacts
              .take(8)
              .map((f) => "${f['subject']} ${f['metric']}: ${f['value']}")
              .join('; ');
          final topFinding = phaseFindings.isNotEmpty
              ? ' | Top: ${phaseFindings.first['text']}'
              : '';
          crossPhaseContext.writeln(
            '- Phase ${i + 1} ($phaseTitle): ${phaseFacts.length} facts, ${phaseFindings.length} findings. ' +
            'Key: $topFacts$topFinding',
          );
          if (entitySet.isNotEmpty) {
            crossPhaseContext.writeln('  Discovered entities: ${entitySet.join(', ')}');
          }
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
              'facts_collected': phaseFacts.length,
              'findings_collected': phaseFindings.length,
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

      final verifiedSourceUrls = _evidenceSourceUrls(rawTempJson);
      if (writerInputFailure == null && verifiedSourceUrls.isEmpty) {
        writerInputFailure =
            'No verified source URLs were persisted to temp.json, so a research artifact cannot be generated safely.';
      }

      // Prefer compact structured text for the writer LLM (~40% fewer tokens than JSON)
      final writerEvidence = compactText.isNotEmpty ? compactText : tempJsonContent;

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
        final turnWatch = Stopwatch()..start();
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
          writerFailure = e.toString();
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
      messages: const [
        ChatMessage(
          role: MessageRole.assistant,
          text: 'New chat ready. Choose any configured provider and model.',
        ),
      ],
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
          onRestoreCompleted: _loadSessions,
          provider: provider,
          customProviders: _customProviders,
          settings: settings,
          cachedModels: models,
          searchSettings: _searchSettings,
          agenticEnabled: _agenticEnabled,
          artifactsEnabled: _artifactsEnabled,
          svgVisualsEnabled: _svgVisualsEnabled,
          deepResearchEnabled: _deepResearchEnabled,
          studyModeEnabled: _studyModeEnabled,
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
                  if (_deepResearchEnabled) const _FeaturePill(icon: Icons.psychology, label: 'Deep Research'),
                  if (_agenticEnabled) const _FeaturePill(icon: Icons.terminal, label: 'Agentic IDE'),
                  if (_studyModeEnabled) const _FeaturePill(icon: Icons.menu_book, label: 'Study Mode'),
                  if (_artifactsEnabled) const _FeaturePill(icon: Icons.extension, label: 'Artifacts'),
                  if (_svgVisualsEnabled) const _FeaturePill(icon: Icons.auto_awesome, label: 'Visuals'),
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

class ChatHistoryPanel extends StatelessWidget {
  const ChatHistoryPanel({
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionTap,
    required this.onSessionDelete,
    required this.onSessionRename,
    required this.onSessionPinToggle,
    required this.onNewChat,
    required this.visibleLimit,
    required this.isLoadingMore,
    required this.onLoadMore,
    super.key,
  });

  final List<ChatSession> sessions;
  final String? activeSessionId;
  final ValueChanged<String> onSessionTap;
  final ValueChanged<String> onSessionDelete;
  final void Function(String sessionId, String newTitle) onSessionRename;
  final ValueChanged<String> onSessionPinToggle;
  final VoidCallback onNewChat;
  final int visibleLimit;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    // Sort pinned chats to the top
    final sortedSessions = List<ChatSession>.from(sessions)
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return 0; // Maintain original relative order
      });

    final displayedSessions = sortedSessions.take(visibleLimit).toList();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final sevenDaysStart = todayStart.subtract(const Duration(days: 7));

    String getBucket(DateTime date) {
      if (date.isAfter(todayStart) || date.isAtSameMomentAs(todayStart)) {
        return 'Today';
      } else if (date.isAfter(yesterdayStart) ||
          date.isAtSameMomentAs(yesterdayStart)) {
        return 'Yesterday';
      } else if (date.isAfter(sevenDaysStart) ||
          date.isAtSameMomentAs(sevenDaysStart)) {
        return 'Previous 7 Days';
      } else {
        return 'Older';
      }
    }

    final buckets = ['Today', 'Yesterday', 'Previous 7 Days', 'Older'];
    final Map<String, List<ChatSession>> grouped = {
      for (final b in buckets) b: <ChatSession>[],
    };

    for (final session in displayedSessions) {
      final b = getBucket(session.updatedAt);
      grouped[b]!.add(session);
    }

    final List<Widget> listItems = [];
    for (final bucket in buckets) {
      final items = grouped[bucket]!;
      if (items.isEmpty) continue;

      listItems.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Text(
            bucket.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF8C7A6B),
            ),
          ),
        ),
      );

      for (final session in items) {
        final selected = session.id == activeSessionId;
        final messageCount = session.messages.length;
        listItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 4.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected
                    ? const Color(0xFFFFF6E5).withValues(alpha: 0.95)
                    : const Color(0xFFFFFDF8).withValues(alpha: 0.8),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFD8B98D)
                      : const Color(0xFFE5DDD3),
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
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: Color(0xFF5C3D26),
                    ),
                  ],
                ),
                title: Text(
                  session.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: const Color(0xFF33291F),
                    fontSize: 13,
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
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: const Color(0xFF8C7A6B),
                  onPressed: () => onSessionDelete(session.id),
                ),
                onTap: () => onSessionTap(session.id),
                onLongPress: () {
                  _showOptionsSheet(context, session);
                },
              ),
            ),
          ),
        );
      }
    }

    listItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 6.0),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            side: const BorderSide(color: Color(0xFFD8B98D), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: const Color(0xFFFFF8EA),
          ),
          onPressed: isLoadingMore ? null : onLoadMore,
          icon: isLoadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B4E2E),
                  ),
                )
              : const Icon(Icons.history, size: 18, color: Color(0xFF7B4E2E)),
          label: Text(
            isLoadingMore
                ? 'Loading…'
                : 'Load earlier chats',
            style: const TextStyle(
              color: Color(0xFF7B4E2E),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );

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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 18),
              children: listItems,
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
    this.onOpenLiveVoice,
    this.activeFeaturePills = const [],
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
  final VoidCallback? onOpenLiveVoice;
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
  final List<Widget> activeFeaturePills;

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
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 84, 18, 90),
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
          ),
          if (messages.isEmpty && deepResearchEnabled)
            Center(
              child: LiquidGlassSurface(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                borderRadius: BorderRadius.circular(20),
                backgroundColor: const Color(
                  0xFFFFF9F2,
                ).withValues(alpha: 0.85),
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: LiquidGlassSurface(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.only(bottom: 2),
                child: SafeArea(
                  bottom: false,
                  child: ChatHeader(
                    provider: provider,
                    settings: settings,
                    model: model,
                    onOpenProvider: onOpenProvider,
                    onOpenModel: onOpenModel,
                    onOpenLiveVoice: onOpenLiveVoice,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: toolStatus.isNotEmpty
                      ? LiquidGlassSurface(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          backgroundColor: const Color(
                            0xFFEEF4FF,
                          ).withValues(alpha: 0.85),
                          highlightColor: const Color(0xFF93C5FD),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
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
                  onOpenLiveVoice: onOpenLiveVoice,
                  attachedImages: attachedImages,
                  onRemoveImage: onRemoveImage,
                  attachedFiles: attachedFiles,
                  onRemoveFile: onRemoveFile,
                  deepResearchEnabled: deepResearchEnabled,
                  isEditing: isEditing,
                  onCancelEdit: onCancelEdit,
                  activeFeaturePills: activeFeaturePills,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatHeader extends StatefulWidget {
  const ChatHeader({
    required this.provider,
    required this.settings,
    required this.model,
    required this.onOpenProvider,
    required this.onOpenModel,
    this.onOpenLiveVoice,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;
  final VoidCallback? onOpenLiveVoice;

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader> {
  bool _isMuted = false;

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.settings.apiKey.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          // Target #1: Hamburger menu button -> circular glass button
          Builder(
            builder: (context) {
              final hasDrawer = Scaffold.hasDrawer(context);
              if (!hasDrawer) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LiquidGlassIconButton(
                    icon: Icons.menu_rounded,
                    size: 42,
                    tooltip: 'Chats',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            },
          ),
          GestureDetector(
            onTap: widget.onOpenProvider,
            child: Tooltip(
              message: '${widget.provider.name} settings',
              child: ProviderAvatar(
                label: widget.provider.shortName,
                small: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Target #3: Model selector -> pill-shaped glass container
          Expanded(
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.circular(30),
              onTap: widget.onOpenModel,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Color(0xFF7B4E2E),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.model,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Color(0xFF7B4E2E),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onOpenLiveVoice != null) ...[
            const SizedBox(width: 8),
            LiquidGlassIconButton(
              icon: Icons.graphic_eq_rounded,
              size: 38,
              tooltip: 'Live Voice Mode',
              onPressed: widget.onOpenLiveVoice!,
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            hasKey || !widget.provider.requiresKey
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            size: 18,
            color: hasKey || !widget.provider.requiresKey
                ? const Color(0xFF36764D)
                : const Color(0xFF9B4D39),
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
      case 'patch_file_rich':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Patch  ${shortPath(p('path'))}',
          'search-replace',
        );
      case 'replace_lines':
      case 'replace_lines_rich':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Replace lines  ${p('start_line')}–${p('end_line')}',
          shortPath(p('path')),
        );
      case 'insert_lines':
      case 'insert_lines_rich':
        return (
          Icons.playlist_add,
          const Color(0xFF059669),
          'Insert after line ${p('after_line')}',
          shortPath(p('path')),
        );
      case 'delete_lines':
      case 'delete_lines_rich':
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
      case 'file_outline_rich':
        return (
          Icons.account_tree_outlined,
          const Color(0xFF0369A1),
          'Outline  ${shortPath(p('path'))}',
          null,
        );
      case 'tree':
      case 'tree_rich':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'Tree  ${shortPath(p('path'))}',
          null,
        );
      case 'diff_files':
      case 'diff_files_rich':
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
      case 'list_trash':
        return (
          Icons.delete_outline,
          const Color(0xFF475569),
          'List trash',
          null,
        );
      case 'restore_trash':
        return (
          Icons.restore_from_trash_outlined,
          const Color(0xFF059669),
          'Restore ${p('name')}',
          shortPath(p('dest')),
        );
      case 'tool_help':
        return (
          Icons.help_outline,
          const Color(0xFF475569),
          'Tool reference',
          null,
        );
      case 'find_files':
        return (
          Icons.manage_search_outlined,
          const Color(0xFFD97706),
          'Find  ${p('pattern')}',
          shortPath(p('path')),
        );
      case 'symbol_search':
        return (
          Icons.travel_explore_outlined,
          const Color(0xFF7C3AED),
          'Symbol search  ${p('symbol')}',
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
      case 'workspace_list':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'List workspace files',
          null,
        );
      case 'workspace_search':
        {
          final queries = params['queries'];
          String? querySub;
          if (queries is List && queries.isNotEmpty) {
            querySub = queries.map((q) => '"$q"').join(', ');
          } else if (p('query').isNotEmpty) {
            querySub = '"${p('query')}"';
          }
          return (
            Icons.search,
            const Color(0xFF0369A1),
            'Search workspace',
            querySub,
          );
        }
      case 'workspace_ingest':
        return (
          Icons.upload_file,
          const Color(0xFF059669),
          'Ingest  ${shortPath(p('file_path'))}',
          null,
        );
      case 'workspace_read_page':
        return (
          Icons.menu_book_outlined,
          const Color(0xFF0369A1),
          'Read page  ${p('page')}',
          shortPath(p('file_path')),
        );
      case 'workspace_get_outline':
        return (
          Icons.account_tree_outlined,
          const Color(0xFF0369A1),
          'Outline  ${shortPath(p('file_path'))}',
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

    return LiquidGlassSurface(
      margin: const EdgeInsets.symmetric(vertical: 8),
      borderRadius: BorderRadius.circular(14),
      backgroundColor: color.withValues(alpha: 0.12),
      highlightColor: color.withValues(alpha: 0.50),
      shadowColor: color.withValues(alpha: 0.20),
      enableBlur: false, // Optimized for scrolling list performance
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
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
                              color: color.withValues(alpha: 0.75),
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
                    color: color.withValues(alpha: 0.6),
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
    keywords = [
      'def',
      'class',
      'import',
      'from',
      'as',
      'return',
      'if',
      'elif',
      'else',
      'for',
      'while',
      'in',
      'is',
      'not',
      'and',
      'or',
      'try',
      'except',
      'finally',
      'pass',
      'lambda',
      'with',
      'assert',
      'global',
      'nonlocal',
      'del',
      'yield',
      'None',
      'True',
      'False',
    ];
  } else if (lang == 'dart' ||
      lang == 'java' ||
      lang == 'kotlin' ||
      lang == 'go' ||
      lang == 'rust' ||
      lang == 'rs') {
    keywords = [
      'class',
      'import',
      'package',
      'void',
      'return',
      'if',
      'else',
      'for',
      'while',
      'in',
      'try',
      'catch',
      'finally',
      'final',
      'const',
      'var',
      'let',
      'static',
      'extends',
      'implements',
      'interface',
      'mixin',
      'with',
      'as',
      'is',
      'new',
      'this',
      'super',
      'switch',
      'case',
      'default',
      'break',
      'continue',
      'async',
      'await',
      'yield',
      'fn',
      'pub',
      'use',
      'impl',
      'struct',
      'enum',
      'mut',
      'let',
    ];
  } else if (lang == 'javascript' ||
      lang == 'js' ||
      lang == 'typescript' ||
      lang == 'ts') {
    keywords = [
      'class',
      'import',
      'export',
      'from',
      'function',
      'return',
      'if',
      'else',
      'for',
      'while',
      'in',
      'of',
      'try',
      'catch',
      'finally',
      'const',
      'let',
      'var',
      'new',
      'this',
      'super',
      'switch',
      'case',
      'default',
      'break',
      'continue',
      'async',
      'await',
      'yield',
      'type',
      'interface',
      'namespace',
      'typeof',
      'instanceof',
      'true',
      'false',
      'null',
      'undefined',
    ];
  } else {
    keywords = [
      'class',
      'import',
      'export',
      'void',
      'function',
      'return',
      'if',
      'else',
      'for',
      'while',
      'try',
      'catch',
      'finally',
      'const',
      'let',
      'var',
      'final',
      'def',
      'fn',
      'true',
      'false',
      'null',
    ];
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
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFF7A828F)),
        ),
      );
    } else if (m.group(3) != null) {
      // Strings
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFF98C379)),
        ),
      );
    } else if (m.group(4) != null) {
      // Numbers
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFFD19A66)),
        ),
      );
    } else if (m.group(5) != null) {
      // Words
      if (keywordSet.contains(text)) {
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(
              color: Color(0xFFC678DD),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (RegExp(r'^[A-Z]').hasMatch(text)) {
        // Classes/Types
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFE5C07B)),
          ),
        );
      } else if (text == 'void' ||
          text == 'int' ||
          text == 'double' ||
          text == 'num' ||
          text == 'bool' ||
          text == 'dynamic') {
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFE5C07B)),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFABB2BF)),
          ),
        );
      }
    } else {
      // Operators, braces, spaces
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFFABB2BF)),
        ),
      );
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
              style: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.45),
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
                style: GoogleFonts.jetBrainsMono(fontSize: 12, height: 1.4),
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
        blocks.add(ContentBlock(isCode: true, content: part, language: ''));
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
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 12,
  });
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
        child: SizedBox(width: 260, height: 180, child: tiles.first),
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
                Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true),
                // Subtle gradient overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
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
                  bottom: 6,
                  right: 6,
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
      final file = File(
        '${dir.path}/nexon_video_${widget.index}_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
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
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
        // Duration badge
        Positioned(
          bottom: 6,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xB2000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _fmtDuration(_ctrl!.value.duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Video badge
        Positioned(
          top: 6,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xB2000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_rounded,
                  color: Color(0xFF67E8A0),
                  size: 12,
                ),
                SizedBox(width: 3),
                Text(
                  'VIDEO',
                  style: TextStyle(
                    color: Color(0xFF67E8A0),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
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
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        // Progress bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF67E8A0),
                    ),
                    minHeight: 3,
                  ),
                  Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmtDuration(val.position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          _fmtDuration(val.duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
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
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF67E8A0),
                      ),
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
        Text(
          'Video unavailable',
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
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
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 60,
                    ),
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
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.images.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_current + 1} / ${widget.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hint: swipe down to dismiss
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              left: 0,
              right: 0,
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
                left: 0,
                right: 0,
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
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white30,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          child: bytes == null
                              ? const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white38,
                                )
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
  final void Function([Map<String, dynamic>? editedStateMap])? onStartResearch;
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LiquidGlassIconButton(
                        icon: Icons.content_copy_rounded,
                        size: 28,
                        tooltip: 'Copy text',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Message copied to clipboard'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      if (!isUser) ...[
                        const SizedBox(width: 6),
                        StatefulBuilder(
                          builder: (context, setTtsState) {
                            final speaking = NexonTts.isSpeaking(message.text);
                            return LiquidGlassIconButton(
                              icon: speaking
                                  ? Icons.stop_circle_rounded
                                  : Icons.volume_up_rounded,
                              size: 28,
                              tooltip: speaking
                                  ? 'Stop audio'
                                  : 'Read aloud (TTS)',
                              iconColor: speaking
                                  ? const Color(0xFF9B4D39)
                                  : const Color(0xFF5C3D26),
                              onPressed: () {
                                NexonTts.toggleSpeak(
                                  message.text,
                                  () => setTtsState(() {}),
                                );
                              },
                            );
                          },
                        ),
                      ],
                      if (isUser) ...[
                        const SizedBox(width: 6),
                        LiquidGlassIconButton(
                          icon: Icons.edit_rounded,
                          size: 28,
                          tooltip: 'Edit message',
                          onPressed: onEditUserMessage,
                        ),
                      ],
                    ],
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
              if (animationState != AvatarAnimationState.idle)
                const _StreamingCursor(),
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
      (tag: '<workspace_list>', isXml: false),
      (tag: '<workspace_search>', isXml: false),
      (tag: '<workspace_read_page>', isXml: false),
      (tag: '<workspace_get_outline>', isXml: false),
      (tag: '<workspace_ingest>', isXml: false),
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
        widgets.add(
          _buildSpecializedWidget(openTag, contentStr, matchedTag.isXml),
        );
        break;
      }

      final contentStr = text
          .substring(tagContentStartIndex, closeTagIndexInFull)
          .trim();
      widgets.add(
        _buildSpecializedWidget(openTag, contentStr, matchedTag.isXml),
      );

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
              final planEndIndex = cleanContent.indexOf(
                '</research_plan>',
                planIndex,
              );
              if (planEndIndex != -1) {
                cleanContent =
                    (cleanContent.substring(0, planIndex) +
                            cleanContent.substring(planEndIndex + 16))
                        .trim();
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
          final contentStr =
              '<method>run_command</method><command>$content</command>';
          return McpToolBlock(mcpJson: contentStr, isXml: true);
        case '<workspace_list>':
        case '<workspace_search>':
        case '<workspace_read_page>':
        case '<workspace_get_outline>':
        case '<workspace_ingest>':
          return _buildWorkspaceResultBlock(openTag, content);
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

  /// IMPROVEMENT: Renders workspace tool results (<workspace_list>,
  /// <workspace_search>, etc.) as collapsible blocks instead of raw JSON text.
  Widget _buildWorkspaceResultBlock(String openTag, String content) {
    final method = openTag.replaceAll(RegExp('[<>/]'), '');
    String header;
    IconData icon;
    Color accent;
    final List<Widget> detailChildren = [];

    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Color(0xFF52606D),
    );

    try {
      final decoded = jsonDecode(content);
      if (method == 'workspace_list' && decoded is Map) {
        final files = (decoded['files'] as List?) ?? [];
        final usedMb = decoded['used_quota_mb']?.toString() ?? '';
        final totalMb = decoded['quota_mb']?.toString() ?? '';
        header = 'Workspace files (${files.length})' +
            (usedMb.isNotEmpty ? ' · $usedMb/$totalMb MB used' : '');
        icon = Icons.folder_open_outlined;
        accent = const Color(0xFFD97706);
        for (final f in files.whereType<Map>()) {
          final name = f['path']?.toString() ?? 'file';
          final sizeKb =
              ((f['size_bytes'] as num? ?? 0) / 1024).toStringAsFixed(1);
          detailChildren.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file,
                    size: 14,
                    color: Color(0xFF8B7355),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                  ),
                  Text(
                    '$sizeKb KB',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B7355),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else if (method == 'workspace_search' && decoded is Map) {
        final matches = (decoded['matches'] as List?) ?? [];
        header = 'Workspace search (${matches.length} matches)';
        icon = Icons.manage_search_outlined;
        accent = const Color(0xFF0369A1);
        for (final m in matches.whereType<Map>().take(8)) {
          final file = m['file_path']?.toString() ?? '';
          final section = m['section']?.toString() ?? '';
          final excerpt = m['excerpt']?.toString() ?? '';
          detailChildren.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE7D8C4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file + (section.isNotEmpty ? ' — $section' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF52606D),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        header = 'Workspace result';
        icon = Icons.work_outline;
        accent = const Color(0xFF059669);
        detailChildren.add(SelectableText(content, style: monoStyle));
      }
    } catch (_) {
      header = 'Workspace result';
      icon = Icons.work_outline;
      accent = const Color(0xFF059669);
      detailChildren.add(SelectableText(content, style: monoStyle));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        collapsedBackgroundColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        leading: Icon(icon, color: accent, size: 18),
        title: Text(
          header,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        children: detailChildren.isEmpty
            ? [const SizedBox.shrink()]
            : detailChildren,
      ),
    );
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
    final blocks = parseContentBlocks(text);
    // While streaming, the last ``` fence is still open — render that final
    // block as a lightweight streaming view so tokens flow in smoothly, and
    // swap to the rich artifact widget once the fence closes.
    final unclosedFence = text.split('```').length % 2 == 0;
    final widgets = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final streaming = animationState != AvatarAnimationState.idle &&
          i == blocks.length - 1 &&
          block.isCode &&
          unclosedFence;
      widgets.add(
        streaming
            ? _StreamingCodeBlock(code: block.content, language: block.language)
            : _buildSingleBlock(context, block),
      );
    }
    return widgets;
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
            tableColumnWidth: const IntrinsicColumnWidth(),
            tableHeadAlign: TextAlign.left,
            tableCellsPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
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

// ── Streaming cursor: the app sparkle, pulsing while the LLM streams ──

class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor({this.size = 22, this.inline = false, super.key});

  final double size;
  final bool inline;

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final sparkle = Transform.scale(
          scale: 0.75 + 0.3 * t,
          child: Opacity(
            opacity: 0.45 + 0.55 * t,
            child: Image.asset(
              'assets/icon_transparent.png',
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
            ),
          ),
        );
        if (widget.inline) return sparkle;
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [sparkle]),
        );
      },
    );
  }
}

/// Lightweight code view shown while an artifact/code fence is still open,
/// so tokens stream in smoothly instead of re-rendering heavy artifact
/// widgets on every chunk. Swaps to the rich artifact widget on completion.
class _StreamingCodeBlock extends StatelessWidget {
  const _StreamingCodeBlock({
    required this.code,
    required this.language,
    super.key,
  });

  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    const visualLangs = {'svg', 'chart', 'json-chart', 'html', 'artifact', 'react', 'docx'};
    final visual = visualLangs.contains(language.toLowerCase());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                visual ? Icons.auto_awesome_rounded : Icons.code,
                size: 13,
                color: const Color(0xFF9CDCFE),
              ),
              const SizedBox(width: 6),
              Text(
                visual
                    ? 'Rendering ${language.toLowerCase()}…'
                    : language.isEmpty
                        ? 'streaming'
                        : language,
                style: const TextStyle(
                  color: Color(0xFF9CDCFE),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const _StreamingCursor(size: 16, inline: true),
            ],
          ),
          if (visual)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF9CDCFE),
                  ),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFFD4D4D4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizSheet extends StatefulWidget {
  const _QuizSheet({required this.questions, super.key});
  final List<Map<String, dynamic>> questions;

  static List<Map<String, dynamic>> parseQuestions(String json) {
    try {
      final decoded = jsonDecode(json);
      final raw = decoded is Map
          ? (decoded['questions'] is List ? decoded['questions'] as List : [decoded])
          : (decoded is List ? decoded : <dynamic>[]);
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map || out.length >= 10) continue;
        final q = (item['q'] ?? item['question'] ?? '').toString();
        final opts = item['options'] is List
            ? (item['options'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final correct = item['correct'] is num
            ? (item['correct'] as num).toInt()
            : int.tryParse((item['correct'] ?? '').toString()) ?? -1;
        if (q.isEmpty || opts.length < 2 || correct < 0 || correct >= opts.length) {
          continue;
        }
        out.add({'q': q, 'options': opts, 'correct': correct});
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  @override
  State<_QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends State<_QuizSheet> {
  int _idx = 0;
  bool _review = false;
  final List<Map<String, dynamic>> _answers = [];
  final TextEditingController _own = TextEditingController();

  void _submit(int picked, String pickedText) {
    final q = widget.questions[_idx];
    final opts = (q['options'] as List).map((e) => e.toString()).toList();
    final correct = (q['correct'] as num).toInt();
    _answers.add({
      'q': q['q'],
      'picked': pickedText,
      'answer': opts[correct],
      'correct': picked == correct,
    });
    _own.clear();
    setState(() {
      if (_idx + 1 < widget.questions.length) {
        _idx++;
      } else {
        _review = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF242822) : const Color(0xFFFBF7F0);
    final text = dark ? const Color(0xFFEDE8E0) : const Color(0xFF2D241C);
    final sub = dark ? const Color(0xFF9AA096) : const Color(0xFF7B7468);
    const accent = Color(0xFF7B4E2E);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: _review ? _buildReview(text, sub) : _buildQuestion(text, sub, accent),
      ),
    );
  }

  Widget _buildQuestion(Color text, Color sub, Color accent) {
    final q = widget.questions[_idx];
    final opts = (q['options'] as List).map((e) => e.toString()).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${_idx + 1} of ${widget.questions.length}',
              style: TextStyle(fontSize: 12, color: sub),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: sub,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          q['q'] as String,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: opts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => InkWell(
              onTap: () => _submit(i, opts[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 13, color: accent)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(opts[i], style: TextStyle(fontSize: 15, color: text)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _own,
                style: TextStyle(fontSize: 14, color: text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Type your own answer...',
                  hintStyle: TextStyle(fontSize: 14, color: sub),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              color: accent,
              onPressed: () {
                final t = _own.text.trim();
                if (t.isEmpty) return;
                final match = opts.indexWhere((o) => o.toLowerCase() == t.toLowerCase());
                _submit(match, t);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReview(Color text, Color sub) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Results',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _answers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = _answers[i];
              final ok = a['correct'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 18,
                      color: ok ? const Color(0xFF3E7B3E) : const Color(0xFFB3402E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Q${i + 1}: ${a['q']}', style: TextStyle(fontSize: 14, color: text)),
                          const SizedBox(height: 2),
                          Text(
                            ok
                                ? 'Your answer: ${a['picked']}'
                                : 'Your answer: ${a['picked']} — correct: ${a['answer']}',
                            style: TextStyle(fontSize: 12, color: sub),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B4E2E)),
            onPressed: () => Navigator.pop(context, _answers),
            child: const Text('Continue', style: TextStyle(color: Color(0xFFFBF7F0))),
          ),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF7B4E2E).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFF7B4E2E).withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7B4E2E).withOpacity(0.8),
            ),
          ),
        ],
      ),
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
    this.onOpenLiveVoice,
    this.activeFeaturePills = const [],
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback onPlusPressed;
  final VoidCallback? onOpenLiveVoice;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final bool deepResearchEnabled;
  final bool isEditing;
  final VoidCallback onCancelEdit;
  final List<Widget> activeFeaturePills;

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
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final suggestions = SlashCommandService.filterCommands(value.text);
              if (suggestions.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5DDD3)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final command = suggestions[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        command,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4A3424),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        controller.value = TextEditingValue(
                          text: command.split(' ').first + ' ',
                          selection: TextSelection.collapsed(
                            offset: command.split(' ').first.length + 1,
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
          if (activeFeaturePills.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
              child: SizedBox(
                height: 24,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: activeFeaturePills
                      .map((pill) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: pill,
                          ))
                      .toList(),
                ),
              ),
            ),
          // Target #5: Bottom message input -> full-width pill glass container
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(30),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                LiquidGlassIconButton(
                  icon: Icons.add_rounded,
                  size: 38,
                  onPressed: onPlusPressed,
                  tooltip: 'Attach media or file',
                ),
                if (onOpenLiveVoice != null) ...[
                  const SizedBox(width: 6),
                  LiquidGlassIconButton(
                    icon: Icons.mic_rounded,
                    size: 38,
                    onPressed: onOpenLiveVoice!,
                    tooltip: 'Live Voice Mode',
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2D241C),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Message Nexon...',
                        hintStyle: TextStyle(
                          color: Color(0xFF8C7A6B),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                LiquidGlassIconButton(
                  icon: isSending
                      ? Icons.stop_rounded
                      : Icons.arrow_upward_rounded,
                  size: 38,
                  backgroundColor: const Color(0xFF7B4E2E),
                  iconColor: Colors.white,
                  onPressed: isSending ? (onStop ?? () {}) : onSend,
                  tooltip: isSending ? 'Stop response' : 'Send message',
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
    required this.customProviders,
    required this.settings,
    required this.cachedModels,
    required this.searchSettings,
    required this.agenticEnabled,
    required this.artifactsEnabled,
    required this.svgVisualsEnabled,
    required this.deepResearchEnabled,
    required this.studyModeEnabled,
    required this.writerContextBudget,
    required this.agenticWorkspace,
    required this.customMcpUrl,
    required this.onSearchSettingsChanged,
    required this.onAgenticEnabledChanged,
    required this.onArtifactsEnabledChanged,
    required this.onSvgVisualsEnabledChanged,
    required this.onDeepResearchEnabledChanged,
    required this.onStudyModeEnabledChanged,
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
    required this.onDeleteCustomProvider,
    required this.sessionId,
  });

  final ProviderDefinition provider;
  final List<ProviderDefinition> customProviders;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final SearchSettings searchSettings;
  final bool agenticEnabled;
  final bool artifactsEnabled;
  final bool svgVisualsEnabled;
  final bool deepResearchEnabled;
  final bool studyModeEnabled;
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
  final ValueChanged<bool> onStudyModeEnabledChanged;
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
  final ValueChanged<String> onDeleteCustomProvider;
  final String sessionId;

  @override
  State<MediaAndModelSheet> createState() => _MediaAndModelSheetState();
}

class _MediaAndModelSheetState extends State<MediaAndModelSheet> {
  List<ProviderDefinition> get _allProviders => [
        ...providerCatalog,
        ...widget.customProviders,
      ];

  late List<ProviderDefinition> _customLocal;

  bool get _isCustomSel =>
      _selectedProviderId == 'custom' ||
      _selectedProviderId.startsWith('custom_');

  late bool _studyModeEnabled;

  Future<void> _saveStudyMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('study_mode_enabled_v1', val);
  }
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
  String? _selectedVoiceName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkOnStartup(context);
      }
    });
    _maxTokens = widget.settings.maxTokens;
    _customLocal = List.of(widget.customProviders);
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
    _studyModeEnabled = widget.studyModeEnabled;
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
        oldWidget.studyModeEnabled != widget.studyModeEnabled ||
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
        _studyModeEnabled = widget.studyModeEnabled;
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
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
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
              title: Text(
                isUnreachable
                    ? 'Bridge Not Running'
                    : 'Deep Research Setup Required',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUnreachable
                        ? "The Python bridge process isn't currently running. Please start it in Termux:"
                        : 'Deep Research requires the Python bridge. Please run this setup command in Termux:',
                  ),
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
                                : 'curl -sL https://raw.githubusercontent.com/shivaww/Nexon/main/install_bridge.sh | bash',
                            style: const TextStyle(
                              color: Colors.green,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: isUnreachable
                                    ? 'cd ~/nexon_bridge && python3 mcp_server.py'
                                    : 'curl -sL https://raw.githubusercontent.com/shivaww/Nexon/main/install_bridge.sh | bash',
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                              ),
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
                                  const SnackBar(
                                    content: Text(
                                      'Bridge is running! Deep Research enabled.',
                                    ),
                                  ),
                                );
                              } else {
                                setRecheckState(() => rechecking = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Bridge still not reachable. Please check it is running.',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: rechecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
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
    const maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB (normal mode)
    const maxContentChars = 50000; // 50K chars

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
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Validate files and filter by size limits
      final validFiles = <PlatformFile>[];
      for (final pickedFile in result.files) {
        if (pickedFile.path == null) continue;
        final file = File(pickedFile.path!);
        final stat = await file.stat();

        if (_studyModeEnabled) {
          if (stat.size > 150 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${pickedFile.name} too large (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB). Max: 150 MB.')),
              );
            }
            continue;
          }
        } else {
          if (stat.size > maxFileSizeBytes) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${pickedFile.name} too large (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB). Max: 5 MB for normal mode. Use Study Mode for up to 150MB.',
                  ),
                ),
              );
            }
            continue;
          }
        }
        validFiles.add(pickedFile);
      }

      if (validFiles.isEmpty) return;

      if (_studyModeEnabled) {
        // ── Study mode: batch stream-upload to Termux workspace ──
        final totalFiles = validFiles.length;
        final progressNotifier = ValueNotifier<double?>(0.0);
        final statusNotifier = ValueNotifier<String>('Preparing upload…');
        final fileNotifier = ValueNotifier<String>('');
        bool dialogShown = false;

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Uploading to Workspace'),
              content: ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (ctx, status, _) {
                  return ValueListenableBuilder<double?>(
                    valueListenable: progressNotifier,
                    builder: (ctx, value, _) {
                      return ValueListenableBuilder<String>(
                        valueListenable: fileNotifier,
                        builder: (ctx, fileName, _) {
                          final percent = value != null ? (value * 100).round() : 0;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LinearProgressIndicator(
                                value: (value != null && value > 0) ? value : null,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7B4E2E)),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                status,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              if (fileName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  fileName,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                (value != null && value > 0) ? '$percent%' : '',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          );
          dialogShown = true;
        }

        try {
          int uploadedCount = 0;
          final httpClient = HttpClient();

          for (final pickedFile in validFiles) {
            final path = pickedFile.path!;
            final file = File(path);
            final fileName = pickedFile.name;
            final fileSize = await file.length();

            fileNotifier.value = fileName;
            statusNotifier.value = 'Uploading ${uploadedCount + 1}/$totalFiles';
            progressNotifier.value = 0.0;

            final uploadUri = Uri.parse('http://127.0.0.1:8390/workspace/upload?ingest=false&session=${widget.sessionId}');
            final httpReq = await httpClient.postUrl(uploadUri);

            final boundary = '----NexonUpload${DateTime.now().millisecondsSinceEpoch}';
            httpReq.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

            final header = '--$boundary\r\n'
                'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
                'Content-Type: application/octet-stream\r\n\r\n';
            httpReq.add(utf8.encode(header));

            int bytesUploaded = 0;
            final stream = file.openRead();
            await for (final chunk in stream) {
              httpReq.add(chunk);
              bytesUploaded += chunk.length;
              final fileProgress = bytesUploaded / fileSize;
              progressNotifier.value = (uploadedCount + fileProgress) / totalFiles;
            }

            httpReq.add(utf8.encode('\r\n--$boundary--\r\n'));
            final httpResp = await httpReq.close();
            final respBody = await httpResp.transform(utf8.decoder).join();

            if (httpResp.statusCode != 200) {
              throw Exception('Upload failed for $fileName (${httpResp.statusCode}): $respBody');
            }

            final respJson = jsonDecode(respBody) as Map<String, dynamic>;
            final workspacePath = respJson['workspace_path'] as String? ?? '';

            widget.onFileAttached(
              AttachedFile(
                name: fileName,
                content: '[Workspace file — use <mcp_request> to query]',
                workspacePath: workspacePath,
              ),
            );
            uploadedCount++;
          }

          httpClient.close();

          // ── Chunking / Indexing phase ──
          fileNotifier.value = '';
          statusNotifier.value = 'Indexing & chunking documents…';
          progressNotifier.value = null; // Indeterminate spinner during indexing

          final reindexUri = Uri.parse('http://127.0.0.1:8390/workspace/reindex');
          final reindexClient = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5);
          final reindexReq = await reindexClient.postUrl(reindexUri);
          reindexReq.headers.set('Content-Type', 'application/json');
          final reindexResp = await reindexReq
              .close()
              .timeout(const Duration(minutes: 5));
          final reindexBody = await reindexResp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 30));
          reindexClient.close();

          if (reindexResp.statusCode != 200) {
            throw Exception('Reindex failed (${reindexResp.statusCode}): $reindexBody');
          }

          final reindexJson = jsonDecode(reindexBody) as Map<String, dynamic>;
          final summary = reindexJson['index_summary'] as Map<String, dynamic>? ?? {};
          final totalChunks = summary['total_chunks'] ?? 0;

          progressNotifier.value = 1.0;
          statusNotifier.value = 'Done! $totalChunks chunks indexed.';

          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted && dialogShown) {
            Navigator.of(context, rootNavigator: true).pop();
            dialogShown = false;
          }

          if (mounted) {
            final failedCount = (summary['failed_files'] as List?)?.length ?? 0;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(
                failedCount > 0
                    ? '$uploadedCount file(s) uploaded, $totalChunks chunks indexed. $failedCount file(s) failed to process.'
                    : '$uploadedCount file(s) uploaded & indexed ($totalChunks chunks)',
              )),
            );
          }
        } catch (e) {
          if (mounted && dialogShown) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Workspace upload failed: $e')),
            );
          }
        }
      } else {
        // ── Normal mode: read files into memory for inline attachment ──
        for (final pickedFile in validFiles) {
          final file = File(pickedFile.path!);
          final ext = pickedFile.extension?.toLowerCase();
          String text = '';

          if (ext == 'pdf') {
            final bytes = await file.readAsBytes();
            final PdfDocument document = PdfDocument(inputBytes: bytes);
            try {
              text = PdfTextExtractor(document).extractText();
            } finally {
              document.dispose();
            }
          } else {
            text = await file.readAsString();
          }

          if (text.length > maxContentChars) {
            text =
                '${text.substring(0, maxContentChars)}\n\n[Content truncated — file exceeds size limit for full analysis]';
          }

          widget.onFileAttached(
            AttachedFile(name: pickedFile.name, content: text),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${pickedFile.name} attached')),
            );
          }
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

  void _showAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFFFFBF2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF6C5946)),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _buildAccountTab(),
                ),
              ),
            ],
          ),
        ),
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7B4E2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
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
    final currentProvider = _allProviders.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => providerCatalog.first,
    );
    final models = widget.cachedModels.isNotEmpty
        ? widget.cachedModels
        : currentProvider.models;
    final visionEnabled = modelHasVision(_selectedModel);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: WarmGlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        backgroundColor: const Color(0xFFFFFBF2).withValues(alpha: 0.88),
        sigma: 10.0,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Input & Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2D241C),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Account & Sync',
                  icon: const Icon(
                    Icons.account_circle_outlined,
                    color: Color(0xFF7B4E2E),
                    size: 22,
                  ),
                  onPressed: _showAccountDialog,
                ),
              ],
            ),

            // Custom Tab Bar Selector (Liquid Glass style)
            LiquidGlassSurface(
              margin: const EdgeInsets.symmetric(vertical: 14),
              padding: const EdgeInsets.all(4),
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  _buildTabButton(0, Icons.smart_toy_outlined, 'Model'),
                  _buildTabButton(1, Icons.explore_outlined, 'Features'),
                  _buildTabButton(2, Icons.attachment_outlined, 'Attach'),
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
        return _buildAttachTab(visionEnabled);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomProvidersCard() {
    return LiquidGlassSurface(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                size: 18,
                color: Color(0xFF7B4E2E),
              ),
              const SizedBox(width: 8),
              const Text(
                'Saved providers',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onConfigureKey('custom');
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add provider'),
              ),
            ],
          ),
          if (_customLocal.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No saved providers yet. Tap "Add provider" to create one.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
              ),
            ),
          for (final p in _customLocal)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedProviderId == p.id
                      ? const Color(0xFF7B4E2E)
                      : const Color(0xFFDCCBB8),
                ),
              ),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Radio<String>(
                  value: p.id,
                  groupValue: _selectedProviderId,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedProviderId = val;
                      _selectedModel = p.models.isNotEmpty ? p.models.first : '';
                    });
                    widget.onProviderChanged(val);
                  },
                ),
                title: Text(
                  p.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  p.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onConfigureKey(p.id);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Color(0xFFB3261E),
                      ),
                      onPressed: () {
                        setState(() {
                          _customLocal = [
                            for (final x in _customLocal)
                              if (x.id != p.id) x,
                          ];
                          if (_selectedProviderId == p.id) {
                            _selectedProviderId = 'custom';
                            widget.onProviderChanged('custom');
                          }
                        });
                        widget.onDeleteCustomProvider(p.id);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelTab(List<String> models) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdowns Group Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _isCustomSel ? 'custom' : _selectedProviderId,
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
                            orElse: () => providerCatalog.first,
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
              if (_isCustomSel) ...[
                const SizedBox(height: 12),
                _buildCustomProvidersCard(),
              ],
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
        const SizedBox(height: 12),

        // Token Slider Section
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
        const SizedBox(height: 12),

        // Thinking / Reasoning Switch Card
        LiquidGlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          borderRadius: BorderRadius.circular(18),
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
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
                      setState(() {
                        _agenticEnabled = val;
                        if (val) _studyModeEnabled = false;
                      });
                      widget.onAgenticEnabledChanged(val);
                      if (val) widget.onStudyModeEnabledChanged(false);
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
        const SizedBox(height: 12),

        // Web Search Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
        const SizedBox(height: 12),

        // Markdown Artifacts Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
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
        const SizedBox(height: 12),

        // SVG Visuals Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
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
        const SizedBox(height: 12),

        // Agentic Deep Research Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
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
                      final reason =
                          result['reason']?.toString() ?? 'bridge_unreachable';
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
        const SizedBox(height: 12),

        // Study Mode / Cross-Document Analysis Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Study Mode / Cross-Document Analysis',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cross-reference sources, synthesize insights, and build study guides across documents',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _studyModeEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) async {
                  setState(() {
                    _studyModeEnabled = val;
                    if (val) _agenticEnabled = false;
                  });
                  await _saveStudyMode(val);
                  widget.onStudyModeEnabledChanged(val);
                  if (val) widget.onAgenticEnabledChanged(false);

                  if (val) {
                    // Check backend dependencies for document extraction
                    try {
                      final client = HttpClient();
                      client.connectionTimeout = const Duration(seconds: 4);
                      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8390/workspace/deps'));
                      final resp = await req.close();
                      final body = await resp.transform(utf8.decoder).join();
                      client.close();

                      if (resp.statusCode == 200) {
                        final deps = jsonDecode(body) as Map<String, dynamic>;
                        final allPresent = deps['all_present'] == true;
                        if (!allPresent && mounted) {
                          final missing = (deps['missing'] as List).cast<String>();
                          final commands = (deps['commands'] as List).cast<String>();
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Missing Document Extractors'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Study mode is enabled, but some document extractors are missing. You may not be able to index PDFs or DOCX files until they are installed in Termux.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  Text('Missing: ${missing.join(', ')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  const Text('Run in Termux:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  ...commands.map((c) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(6)),
                                      child: SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent)),
                                    ),
                                  )),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Got it'),
                                ),
                              ],
                            ),
                          );
                        }
                      }
                    } catch (_) {
                      // Silently fail if bridge isn't running yet — user can toggle later
                    }
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Audio Feedback / TTS Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audio Feedback / TTS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Text-to-Speech audio button on model outputs',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Icon(Icons.volume_up_rounded, color: Color(0xFF7B4E2E), size: 24),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Live Voice & TTS Engine Voice Selection Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voice',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'The voice used for read-aloud and Live Voice.',
                style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<dynamic>>(
                future: NexonTts.getVoices(),
                builder: (context, snapshot) {
                  final voices = snapshot.data ?? [];
                  if (voices.isEmpty) {
                    return const Text(
                      'Default System Voice',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7B4E2E),
                      ),
                    );
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedVoiceName,
                    dropdownColor: const Color(0xFFFFFBF2),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: voices.map((v) {
                      final name = v is Map
                          ? (v['name']?.toString() ?? 'Voice')
                          : v.toString();
                      final lang = v is Map
                          ? (v['locale']?.toString() ?? '')
                          : '';
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(
                          '$name ${lang.isNotEmpty ? "($lang)" : ""}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedVoiceName = val);
                        NexonTts.setVoice({"name": val, "locale": "en-US"});
                      }
                    },
                  );
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
                style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFFF9A825),
                          ),
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
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
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
                                                setState(
                                                  () => _syncProgressStatus =
                                                      status,
                                                );
                                              }
                                            },
                                          );
                                      if (mounted) {
                                        setState(
                                          () => _syncProgressStatus = '',
                                        );
                                        if (result.success) {
                                          await widget.onRestoreCompleted();
                                        }
                                        _showSyncResultDialog(
                                          context,
                                          title: result.success
                                              ? 'Restore Complete'
                                              : 'Restore Failed',
                                          message: result.message,
                                          details: result.details,
                                          success: result.success,
                                          needsRelogin: result.needsRelogin,
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(
                                          () => _syncProgressStatus = '',
                                        );
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
                                                setState(
                                                  () => _syncProgressStatus =
                                                      status,
                                                );
                                              }
                                            },
                                          );
                                      if (mounted) {
                                        setState(
                                          () => _syncProgressStatus = '',
                                        );
                                        _showSyncResultDialog(
                                          context,
                                          title: result.success
                                              ? 'Backup Complete'
                                              : 'Backup Failed',
                                          message: result.message,
                                          details: result.details,
                                          success: result.success,
                                          needsRelogin: result.needsRelogin,
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(
                                          () => _syncProgressStatus = '',
                                        );
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
                    Supabase.instance.client.auth.currentSession?.user.email ??
                        'Not logged in',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2D241C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (Supabase.instance.client.auth.currentSession != null) ...[
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => WarmGlassDialog(
                              title: const Text(
                                'Confirm Logout',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              content: const Text(
                                'Are you sure you want to logout?',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(ctx).pop();
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                      'has_completed_onboarding_v2',
                                      false,
                                    );
                                    await Supabase.instance.client.auth
                                        .signOut();
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
                                  child: const Text(
                                    'Logout',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.logout,
                          size: 16,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => UpdateService.checkForUpdates(
                          context,
                          userInitiated: true,
                        ),
                        icon: const Icon(
                          Icons.system_update_rounded,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                        label: const Text(
                          'Check for Updates',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
                      'Nexon Subscription Plans',
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
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor: Colors.white,
                      title: const Row(
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            color: Color(0xFFD97706),
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Coming Soon',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        'Subscriptions for the $title plan are coming soon! Stay updated for upcoming releases.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                      actionsPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      actions: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2D241C),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'Got it, Stay Updated!',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D241C),
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
                child: const Text(
                  'Subscribe',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
        LiquidGlassSurface(
          padding: const EdgeInsets.all(18),
          borderRadius: BorderRadius.circular(18),
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
                        Icon(
                          Icons.warning_amber,
                          color: Color(0xFFD4A017),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sign out and sign in again with Google to re-authorize Drive access.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7B6B2E),
                            ),
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
            child: const Text('OK', style: TextStyle(color: Color(0xFF7B4E2E))),
          ),
        ],
      ),
    );
  }
}

class ProviderSheetResult {
  const ProviderSheetResult({required this.settings, this.customName});

  final ProviderSettings settings;
  final String? customName;
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
  late final TextEditingController _nameController;
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
    _nameController = TextEditingController(
      text: widget.provider.id.startsWith('custom_')
          ? widget.provider.name
          : '',
    );
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
    _nameController.dispose();
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
          if (widget.provider.id == 'custom' ||
              widget.provider.id.startsWith('custom_')) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Provider name',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                    final isCustom = widget.provider.id == 'custom' ||
                        widget.provider.id.startsWith('custom_');
                    Navigator.of(context).pop(
                      ProviderSheetResult(
                        customName: isCustom
                            ? _nameController.text.trim()
                            : null,
                        settings: ProviderSettings(
                          apiKey: _keyController.text.trim(),
                          baseUrl: _baseUrlController.text.trim(),
                          model: _modelController.text.trim(),
                          maxTokens:
                              parsedMaxTokens.clamp(1, 131072).toInt(),
                          fallbackApiKeys: _fallbackControllers
                              .map((c) => c.text.trim())
                              .where((e) => e.isNotEmpty)
                              .toList(),
                        ),
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
                          color: selected
                              ? const Color(0xFF7B4E2E)
                              : const Color(0xFF6C5946),
                        ),
                        title: Text(
                          model,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
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
  final void Function([Map<String, dynamic>? editedStateMap])? onStartResearch;

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
        text:
            value['query_text']?.toString() ??
            value['prompt']?.toString() ??
            '',
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

    return LiquidGlassSurface(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      borderRadius: BorderRadius.circular(16),
      backgroundColor: const Color(0xFFEAF3FF).withValues(alpha: 0.85),
      highlightColor: const Color(0xFF90CDF4),
      shadowColor: const Color(0xFF2C5282),
      enableBlur: false, // In-feed scrolling list performance optimization
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xD9D7E9FA), Color(0xBFD9ECFA)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _ResearchAgentAvatars(
                        status: status,
                        isSending: widget.isSending,
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
                if (status == 'pending' ||
                    (status == 'running' && !widget.isSending) ||
                    status == 'failed') ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending')
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          tooltip: 'Edit research plan',
                          onPressed: _editPlan,
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          color: const Color(0xFF2C5282),
                        ),
                      if (status == 'pending') const SizedBox(width: 4),
                      if (widget.onStartResearch != null)
                        FilledButton.icon(
                          onPressed: () =>
                              widget.onStartResearch!(widget.stateMap),
                          icon: Icon(
                            status == 'running'
                                ? Icons.play_arrow
                                : (status == 'failed'
                                      ? Icons.replay
                                      : Icons.play_arrow),
                            size: 16,
                          ),
                          label: Text(
                            status == 'running'
                                ? 'Resume'
                                : (status == 'failed' ? 'Retry' : 'Start'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2C5282),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
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
                            Icon(
                              Icons.description,
                              size: 18,
                              color: Color(0xFF2C5282),
                            ),
                            SizedBox(width: 8),
                            Text('Save as DOCX'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'markdown',
                        child: Row(
                          children: [
                            Icon(
                              Icons.article,
                              size: 18,
                              color: Color(0xFF2C5282),
                            ),
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
                value:
                    steps
                        .where(
                          (step) =>
                              step['status'] == 'completed' ||
                              step['status'] == 'completed_with_issues',
                        )
                        .length /
                    steps.length,
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
                              decoration:
                                  (stepStatus == 'completed' ||
                                      stepStatus == 'completed_with_issues')
                                  ? TextDecoration.lineThrough
                                  : null,
                              color:
                                  (stepStatus == 'completed' ||
                                      stepStatus == 'completed_with_issues')
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
                              final event =
                                  (step['events'] as List)[eventIndex] as Map;
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

class _ResearchEventRowState extends State<_ResearchEventRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathCtrl;
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
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _breathCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant _ResearchEventRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBreathing();
    if (_isRunning && _expanded) _expanded = false;
  }

  void _syncBreathing() {
    if (_isPulsing && !_breathCtrl.isAnimating) {
      _breathCtrl.repeat(reverse: true);
    } else if (!_isPulsing && _breathCtrl.isAnimating) {
      _breathCtrl.stop();
      _breathCtrl.reset();
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
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
        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: accent),
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
            payload['url']?.toString() ?? widget.event['url']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              if (parseFormat != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (parseFormat == 'pdf' || parseFormat == 'skipped_pdf')
                        ? const Color(0xFFFFF3E0)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    parseFormat == 'skipped_pdf'
                        ? 'SKIPPED (PDF)'
                        : parseFormat.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          (parseFormat == 'pdf' || parseFormat == 'skipped_pdf')
                          ? const Color(0xFFE65100)
                          : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (stageVal != null) ...[
                Text(
                  stageVal,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (isDedup)
                const Text(
                  'Already read (cache hit)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF5C6BC0),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (widget.event.containsKey('facts_count') ||
                  widget.event.containsKey('findings_count'))
                Text(
                  '${widget.event['facts_count'] ?? 0} facts · ${widget.event['findings_count'] ?? 0} findings extracted',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF327342),
                  ),
                )
              else if (addedVal is num && addedVal > 0)
                Text(
                  '$addedVal new chunks added',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF327342),
                  ),
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
    final isDedup =
        (added is num && added == 0) ||
        widget.event['already_attempted'] == true;
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
        opacity: _isPulsing ? 0.72 + 0.28 * _breathCtrl.value : 1.0,
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
  final Function(String errorDetails)? onError;

  const SvgDiagramWidget({super.key, required this.svgString, this.onError});

  @override
  State<SvgDiagramWidget> createState() => _SvgDiagramWidgetState();
}

class _SvgDiagramWidgetState extends State<SvgDiagramWidget> {
  late String _cachedSvg;
  late bool _isComplete;
  bool _hasError = false;
  String _errorMessage = '';
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _processSvg();
  }

  void _processSvg() {
    _cachedSvg = _cleanSvg(widget.svgString);
    _isComplete = _cachedSvg.trim().endsWith('</svg>');

    if (!_isComplete) {
      _startTimeoutTimer();
    } else {
      _timeoutTimer?.cancel();
      _validateSvg();
    }
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_isComplete) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Incomplete SVG visual stream (missing </svg> tag)';
        });
        widget.onError?.call(_errorMessage);
      }
    });
  }

  void _validateSvg() {
    if (!_cachedSvg.contains('<svg')) {
      _hasError = true;
      _errorMessage = 'Invalid SVG content (missing <svg> tag)';
      widget.onError?.call(_errorMessage);
      return;
    }
    _hasError = false;
  }

  @override
  void didUpdateWidget(SvgDiagramWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgString != widget.svgString) {
      _processSvg();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  String _cleanSvg(String raw) {
    String s = raw.trim();
    final svgIdx = s.indexOf('<svg');
    if (svgIdx < 0) return s;
    if (svgIdx > 0) s = s.substring(svgIdx);

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
    if (_hasError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to render visual: ${_errorMessage.length > 55 ? "${_errorMessage.substring(0, 55)}…" : _errorMessage}',
                style: const TextStyle(
                  color: Color(0xFF991B1B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isComplete) {
      return Container(
        width: double.infinity,
        height: 80,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.5),
          ),
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
                  // IMPROVEMENT: malformed AI-generated SVG previously left the
                  // placeholder spinner on screen forever; show an error card.
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Failed to render visual: invalid SVG code',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
      body: SafeArea(
        child: Stack(
          children: [
            Center(
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
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Failed to render SVG: the generated code is invalid.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              child: WarmGlassContainer(
                borderRadius: BorderRadius.circular(16),
                backgroundColor: const Color(
                  0xFF0D1B2A,
                ).withValues(alpha: 0.72),
                border: Border.all(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                sigma: 10.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_all, color: Colors.white),
                      tooltip: 'Copy SVG code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: svgString));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('SVG code copied to clipboard'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          tableColumnWidth: const IntrinsicColumnWidth(),
                          tableHeadAlign: TextAlign.left,
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
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          tableColumnWidth: const IntrinsicColumnWidth(),
                          tableHeadAlign: TextAlign.left,
                          tableBorder: TableBorder.all(
                            color: const Color(0xFFE7D8C4),
                            width: 1,
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
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  String expandHome(String path) {
    if (path == '~') {
      return Platform.environment['HOME'] ?? '/data/data/com.termux/files/home';
    }
    if (path.startsWith('~/')) {
      final home =
          Platform.environment['HOME'] ?? '/data/data/com.termux/files/home';
      return '$home/${path.substring(2)}';
    }
    return path;
  }

  String normalize(String path) {
    final normalized = Uri.file(path).normalizePath().toFilePath();
    if (normalized.length > 1 && normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  final workspaceExpanded = expandHome(workspace);
  final workspaceCanonical = normalize(
    workspaceExpanded.startsWith('/')
        ? workspaceExpanded
        : Directory.current.uri.resolve(workspaceExpanded).toFilePath(),
  );

  final candidateBase = expandHome(p);
  final candidateResolved = candidateBase.startsWith('/')
      ? candidateBase
      : '$workspaceCanonical/$candidateBase';
  final candidateCanonical = normalize(candidateResolved);
  final insideWorkspace = candidateCanonical == workspaceCanonical ||
      candidateCanonical.startsWith('$workspaceCanonical/');
  if (!insideWorkspace) {
    throw StateError('outside workspace jail: $candidateCanonical');
  }
  return candidateCanonical;
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

class _ResearchAgentAvatars extends StatefulWidget {
  const _ResearchAgentAvatars({required this.status, required this.isSending});
  final String status;
  final bool isSending;

  @override
  State<_ResearchAgentAvatars> createState() => _ResearchAgentAvatarsState();
}

class _ResearchAgentAvatarsState extends State<_ResearchAgentAvatars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanCtrl;
  late final Animation<double> _scanAnim;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scanAnim = CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut);
    _syncAnimation();
  }

  void _syncAnimation() {
    final shouldAnimate = widget.isSending &&
        (widget.status == 'planning' ||
            widget.status == 'running' ||
            widget.status == 'generating_report');
    if (shouldAnimate && !_scanCtrl.isAnimating) {
      _scanCtrl.repeat();
    } else if (!shouldAnimate && _scanCtrl.isAnimating) {
      _scanCtrl.stop();
      _scanCtrl.reset();
    }
  }

  @override
  void didUpdateWidget(_ResearchAgentAvatars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  int get _activePhase {
    if (!widget.isSending) return -1;
    switch (widget.status) {
      case 'planning':
        return 0;
      case 'running':
        return 1;
      case 'generating_report':
        return 2;
      default:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activePhase;
    return SizedBox(
      width: 140,
      height: 28,
      child: AnimatedBuilder(
        animation: _scanAnim,
        builder: (context, _) {
          return CustomPaint(
            painter: _PipelinePainter(
              activePhase: active,
              scan: _scanAnim.value,
            ),
          );
        },
      ),
    );
  }
}

class _PipelinePainter extends CustomPainter {
  _PipelinePainter({required this.activePhase, required this.scan});
  final int activePhase;
  final double scan;

  static const _labels = ['PLAN', 'RESEARCH', 'WRITE'];
  static const _accents = <Color>[
    Color(0xFF2C5282),
    Color(0xFF7B4E2E),
    Color(0xFF38A169),
  ];

  static const _muted = Color(0xFF94A3B8);
  static const _bg = Color(0xFFF8FAFC);
  static const _connector = Color(0xFFCBD5E1);
  static const _ink = Color(0xFF1E293B);

  @override
  void paint(Canvas canvas, Size size) {
    const cellW = 42.0;
    const cellH = 22.0;
    const topY = 3.0;
    const cellsX = <double>[1.0, 48.0, 95.0];
    const connectorY = topY + cellH / 2;

    final connectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 2; i++) {
      final x1 = cellsX[i] + cellW;
      final x2 = cellsX[i + 1];
      final isPassed = activePhase > i;
      connectorPaint.color =
          isPassed ? _accents[i].withOpacity(0.55) : _connector;
      canvas.drawLine(
        Offset(x1 + 1, connectorY),
        Offset(x2 - 1, connectorY),
        connectorPaint,
      );
    }

    for (int i = 0; i < 3; i++) {
      final x = cellsX[i];
      final isActive = activePhase == i;
      final isDone = activePhase > i;
      final accent = _accents[i];

      final rect = Rect.fromLTWH(x, topY, cellW, cellH);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

      final bgPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isActive
            ? accent.withOpacity(0.14)
            : isDone
                ? accent.withOpacity(0.06)
                : _bg;
      canvas.drawRRect(rrect, bgPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.2 : 0.8
        ..color = isActive
            ? accent
            : isDone
                ? accent.withOpacity(0.4)
                : _connector;
      canvas.drawRRect(rrect, borderPaint);

      if (isActive) {
        canvas.save();
        canvas.clipRRect(rrect);
        final scanX = x + scan * cellW;
        final glowPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = accent.withOpacity(0.18);
        canvas.drawRect(
          Rect.fromLTWH(scanX - 10, topY, 20, cellH),
          glowPaint,
        );
        final linePaint = Paint()
          ..style = PaintingStyle.fill
          ..color = accent.withOpacity(0.55);
        canvas.drawRect(
          Rect.fromLTWH(scanX - 0.5, topY + 2, 1, cellH - 4),
          linePaint,
        );
        canvas.restore();
      }

      final dotX = x + 6.5;
      final dotY = topY + cellH / 2;
      if (isDone) {
        canvas.drawCircle(
          Offset(dotX, dotY),
          2.2,
          Paint()..color = accent,
        );
        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(dotX - 1.2, dotY + 0.1)
          ..lineTo(dotX - 0.2, dotY + 1.1)
          ..lineTo(dotX + 1.4, dotY - 1.1);
        canvas.drawPath(path, checkPaint);
      } else if (isActive) {
        canvas.drawCircle(
          Offset(dotX, dotY),
          2.0,
          Paint()..color = accent,
        );
      } else {
        canvas.drawCircle(
          Offset(dotX, dotY),
          1.8,
          Paint()
            ..color = _muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9,
        );
      }

      final labelColor = isActive
          ? accent
          : isDone
              ? _ink.withOpacity(0.72)
              : _muted;
      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: TextStyle(
            fontSize: 8.4,
            color: labelColor,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.35,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(dotX + 4.5, dotY - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PipelinePainter oldDelegate) {
    return oldDelegate.activePhase != activePhase || oldDelegate.scan != scan;
  }
}
