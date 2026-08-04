import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/voice/live_voice_engine.dart';
import '../main.dart' show LiquidGlassSurface;

class LiveVoiceOverlay extends StatefulWidget {
  const LiveVoiceOverlay({
    required this.engine,
    required this.onSendPrompt,
    required this.onClose,
    super.key,
  });

  final LiveVoiceEngine engine;
  final ValueChanged<String> onSendPrompt;
  final VoidCallback onClose;

  @override
  State<LiveVoiceOverlay> createState() => _LiveVoiceOverlayState();
}

class _LiveVoiceOverlayState extends State<LiveVoiceOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _showCaptions = true;
  late final Timer _orbTimer;
  bool _pulseUp = false;
  bool _thinkingSweep = false;
  late final AnimationController _thinkingCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.engine.addListener(_onEngineChange);
    _thinkingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _orbTimer = Timer.periodic(const Duration(milliseconds: 1050), (_) {
      if (!mounted) return;
      setState(() {
        _pulseUp = !_pulseUp;
        if (widget.engine.state == LiveVoiceState.thinking) {
          _thinkingSweep = !_thinkingSweep;
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptMicPermission();
    });
  }

  // ── Permission flow ───────────────────────────────────────────────────────

  Future<void> _checkAndPromptMicPermission() async {
    final status = await widget.engine.micPermissionStatus();

    if (status.isGranted) {
      // Already granted — start directly.
      if (widget.engine.state == LiveVoiceState.idle) {
        widget.engine.startListening(onFinalResult: widget.onSendPrompt);
      }
      return;
    }

    if (status.isPermanentlyDenied) {
      _showPermanentlyDeniedDialog();
      return;
    }

    // Not yet asked — show our custom rationale dialog, then fire the OS dialog.
    if (!mounted) return;
    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFDF8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5DDD3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.mic_rounded, color: Color(0xFF7B4E2E)),
            SizedBox(width: 10),
            Text(
              'Microphone Access',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D241C),
              ),
            ),
          ],
        ),
        content: const Text(
          'Nexon Live Voice Mode uses your microphone to listen to your voice '
          'commands and converse with you hands-free.\n\nTap "Grant Permission" '
          'to allow OS microphone access.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6C5946), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8C7A6B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B4E2E),
              foregroundColor: const Color(0xFFFFF8EA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest != true) {
      if (mounted) {
        widget.engine.setError('Microphone permission was not granted.');
      }
      return;
    }
    if (!mounted) return;

    // requestMicPermission() fires the real Android RECORD_AUDIO OS dialog.
    final granted = await widget.engine.requestMicPermission();
    if (granted && mounted && widget.engine.state == LiveVoiceState.idle) {
      widget.engine.startListening(onFinalResult: widget.onSendPrompt);
    } else if (!granted && mounted) {
      // Check again — might be permanently denied now.
      final newStatus = await widget.engine.micPermissionStatus();
      if (newStatus.isPermanentlyDenied && mounted) {
        _showPermanentlyDeniedDialog();
      } else {
        widget.engine.setError('Microphone permission was not granted.');
      }
    }
  }

  void _showPermanentlyDeniedDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFDF8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5DDD3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.mic_off_rounded, color: Color(0xFFA2675A)),
            SizedBox(width: 10),
            Text(
              'Microphone Blocked',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D241C),
              ),
            ),
          ],
        ),
        content: const Text(
          'Microphone access is permanently blocked. Open Android Settings → '
          'Apps → Nexon → Permissions and enable Microphone.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6C5946), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss', style: TextStyle(color: Color(0xFF8C7A6B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B4E2E),
              foregroundColor: const Color(0xFFFFF8EA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orbTimer.cancel();
    _thinkingCtrl.dispose();
    widget.engine.removeListener(_onEngineChange);
    super.dispose();
  }

  void _onEngineChange() {
    if (!mounted) return;
    setState(() {});
  }

  /// Intercept the Android back button while the overlay is visible so the
  /// engine is interrupted and no background audio keeps playing.
  @override
  Future<bool> didPopRoute() {
    if (!mounted) return Future.value(true);
    widget.onClose();
    return Future.value(true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final soundLevel = widget.engine.soundLevel;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // ── Fullscreen backdrop ────────────────────────────────────────
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFFFFDF8),
                      Color(0xFFF7EFE2),
                      Color(0xFFEBE0D0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // ── Main content ───────────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  // Top header bar
                  _buildTopBar(),

                  // Status pill
                  _buildStatusHeader(state),
                  if (widget.engine.isPreparingTts) _buildTtsDownloadProgress(),

                  // Orb
                  Expanded(
                    child: Center(
                      child: _buildAnimatedLiquidOrb(state, soundLevel),
                    ),
                  ),

                  // Live captions
                  if (_showCaptions) _buildLiveCaptionsBox(state),
                  const SizedBox(height: 16),

                  // Bottom mic / barge-in
                  _buildBottomControls(state),
                  const SizedBox(height: 12),

                  // Voice picker (KittenTTS voices)
                  _buildVoicePicker(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Icon pill with glass
              LiquidGlassSurface(
                isCircle: true,
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                backgroundColor: const Color(0xFF7B4E2E).withValues(alpha: 0.12),
                highlightColor: Colors.white.withValues(alpha: 0.5),
                sigma: 8,
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Color(0xFF7B4E2E),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Live Voice Mode',
                style: GoogleFonts.notoSerif(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D241C),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _glassIconButton(
                tooltip: _showCaptions ? 'Hide Captions' : 'Show Captions',
                icon: _showCaptions
                    ? Icons.subtitles_rounded
                    : Icons.subtitles_off_outlined,
                onPressed: () => setState(() => _showCaptions = !_showCaptions),
              ),
              const SizedBox(width: 8),
              _glassIconButton(
                tooltip: 'Exit Voice Mode',
                icon: Icons.close_rounded,
                onPressed: widget.onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: LiquidGlassSurface(
        width: 42,
        height: 42,
        borderRadius: BorderRadius.circular(15),
        padding: EdgeInsets.zero,
        backgroundColor: const Color(0xFFFFFDF8).withValues(alpha: 0.52),
        highlightColor: Colors.white.withValues(alpha: 0.6),
        sigma: 10,
        child: IconButton(
          icon: Icon(icon, color: const Color(0xFF7B4E2E)),
          onPressed: onPressed,
        ),
      ),
    );
  }

  // ── Status pill ───────────────────────────────────────────────────────────

  Widget _buildStatusHeader(LiveVoiceState state) {
    String statusText;
    Color statusColor;

    switch (state) {
      case LiveVoiceState.listening:
        statusText = 'Listening to your voice…';
        statusColor = const Color(0xFF7B4E2E);
        break;
      case LiveVoiceState.thinking:
        statusText = 'Nexon is thinking…';
        statusColor = const Color(0xFF9B6B43);
        break;
      case LiveVoiceState.speaking:
        statusText = 'Nexon is speaking… (Tap orb or mic to barge-in)';
        statusColor = const Color(0xFFB5784C);
        break;
      case LiveVoiceState.error:
        statusText = widget.engine.errorMessage.isNotEmpty
            ? widget.engine.errorMessage
            : 'Voice error occurred.';
        // Muted app accent — NOT solid red.
        statusColor = const Color(0xFFA2675A);
        break;
      case LiveVoiceState.idle:
      default:
        statusText = 'Tap mic to start speaking';
        statusColor = const Color(0xFF6C5946);
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: LiquidGlassSurface(
        key: ValueKey(statusText),
        borderRadius: BorderRadius.circular(20),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        backgroundColor: statusColor.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.5),
        sigma: 8,
        child: Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── TTS download progress ─────────────────────────────────────────────────

  Widget _buildTtsDownloadProgress() {
    final progress = widget.engine.ttsDownloadProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        highlightColor: Colors.white.withValues(alpha: 0.55),
        sigma: 10,
        child: Column(
          children: [
            Text(
              widget.engine.ttsStatus.isEmpty
                  ? 'Preparing voice model…'
                  : widget.engine.ttsStatus,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(99),
              color: const Color(0xFF9B6B43),
              backgroundColor: const Color(0xFFE5D5C0),
            ),
          ],
        ),
      ),
    );
  }

  // ── Liquid glass orb ──────────────────────────────────────────────────────

  Widget _buildAnimatedLiquidOrb(LiveVoiceState state, double soundLevel) {
    List<Color> gradientColors;
    double orbScale;
    double blurSigma;
    // Sweep direction for thinking animation
    Alignment gradientCenter;

    switch (state) {
      case LiveVoiceState.listening:
        gradientColors = [
          const Color(0xFFEADCC9),
          const Color(0xFFD8B98D),
          const Color(0xFFB88E5E),
        ];
        // Amplitude-reactive: soundLevel drives extra scale.
        orbScale = 1.0 + (soundLevel * 0.35) + (_pulseUp ? 0.025 : 0.0);
        blurSigma = 18.0;
        gradientCenter = Alignment.topLeft;
        break;
      case LiveVoiceState.thinking:
        gradientColors = [
          const Color(0xFF9B6B43),
          const Color(0xFF7B4E2E),
          const Color(0xFF56331A),
        ];
        orbScale = 1.04 + (_pulseUp ? 0.025 : 0.0);
        blurSigma = 24.0;
        // Sweep back and forth for gradient-sweep effect.
        gradientCenter =
            _thinkingSweep ? Alignment.bottomRight : Alignment.topLeft;
        break;
      case LiveVoiceState.speaking:
        gradientColors = [
          const Color(0xFFF3D5A5),
          const Color(0xFFE4B373),
          const Color(0xFFC58B49),
        ];
        orbScale = 1.10 + (_pulseUp ? 0.05 : 0.0);
        blurSigma = 20.0;
        gradientCenter = Alignment.topLeft;
        break;
      case LiveVoiceState.error:
        // Muted app accent — NOT solid red.
        gradientColors = [
          const Color(0xFFF0E2DD),
          const Color(0xFFD4AFA6),
          const Color(0xFFA2675A),
        ];
        orbScale = 0.97;
        blurSigma = 12.0;
        gradientCenter = Alignment.topLeft;
        break;
      case LiveVoiceState.idle:
      default:
        gradientColors = [
          const Color(0xFFF5EADA),
          const Color(0xFFE5D5C0),
          const Color(0xFFCDB89E),
        ];
        // Slow idle pulse.
        orbScale = _pulseUp ? 1.035 : 1.0;
        blurSigma = 15.0;
        gradientCenter = Alignment.topLeft;
        break;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (state == LiveVoiceState.speaking) {
          widget.engine.interrupt();
        } else if (state == LiveVoiceState.idle ||
            state == LiveVoiceState.error) {
          widget.engine.startListening(onFinalResult: widget.onSendPrompt);
        }
      },
      child: AnimatedScale(
        scale: orbScale,
        duration: state == LiveVoiceState.idle
            ? const Duration(milliseconds: 1050)
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: state == LiveVoiceState.thinking
              ? const Duration(milliseconds: 1050)
              : const Duration(milliseconds: 360),
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: gradientColors,
              center: gradientCenter,
              radius: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors[1].withValues(alpha: 0.45),
                blurRadius: blurSigma * 1.5,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: const Color(0xFFFFF8EA).withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(-4, -4),
              ),
            ],
          ),
          child: LiquidGlassSurface(
            isCircle: true,
            padding: EdgeInsets.zero,
            // Translucent fill with blur for the glass look.
            backgroundColor: gradientColors[0].withValues(alpha: 0.34),
            // Bright edge highlight — key for the glass effect.
            highlightColor: Colors.white.withValues(alpha: 0.75),
            shadowColor: gradientColors.last.withValues(alpha: 0.6),
            sigma: 14,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  key: ValueKey(state),
                  state == LiveVoiceState.speaking
                      ? Icons.volume_up_rounded
                      : state == LiveVoiceState.thinking
                          ? Icons.auto_awesome_rounded
                          : Icons.mic_rounded,
                  size: 54,
                  color: const Color(0xFF2D241C).withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Captions box ──────────────────────────────────────────────────────────

  Widget _buildLiveCaptionsBox(LiveVoiceState state) {
    String textToShow = '';
    if (state == LiveVoiceState.listening ||
        state == LiveVoiceState.thinking) {
      textToShow = widget.engine.recognizedText;
    } else if (state == LiveVoiceState.speaking) {
      textToShow = widget.engine.spokenText;
    }

    if (textToShow.trim().isEmpty) {
      textToShow = state == LiveVoiceState.listening
          ? 'Listening… (speak into your microphone)'
          : 'Live captions will display here…';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxHeight: 130),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        highlightColor: Colors.white.withValues(alpha: 0.55),
        sigma: 12,
        child: SingleChildScrollView(
          reverse: true,
          child: Text(
            textToShow,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2D241C),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // ── Bottom mic controls ───────────────────────────────────────────────────

  Widget _buildBottomControls(LiveVoiceState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LiquidGlassSurface(
          isCircle: true,
          width: 76,
          height: 76,
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFF9B6B43).withValues(alpha: 0.32),
          highlightColor: Colors.white.withValues(alpha: 0.65),
          sigma: 12,
          child: IconButton(
            iconSize: 38,
            color: const Color(0xFF2D241C),
            icon: Icon(
              state == LiveVoiceState.speaking
                  ? Icons.stop_rounded
                  : state == LiveVoiceState.listening
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              if (state == LiveVoiceState.speaking) {
                widget.engine.interrupt();
                widget.engine.startListening(
                    onFinalResult: widget.onSendPrompt);
              } else if (state == LiveVoiceState.listening) {
                widget.engine.stopListening();
              } else {
                widget.engine.startListening(
                    onFinalResult: widget.onSendPrompt);
              }
            },
          ),
        ),
      ],
    );
  }

  // ── Voice picker ──────────────────────────────────────────────────────────

  Widget _buildVoicePicker() {
    final voice = widget.engine.kittenVoice;
    return LiquidGlassSurface(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      highlightColor: Colors.white.withValues(alpha: 0.55),
      sigma: 10,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: voice,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: widget.engine.kittenVoices
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded,
                          size: 16, color: Color(0xFF9B6B43)),
                      const SizedBox(width: 8),
                      Text(
                        'KittenTTS · $v',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) widget.engine.setKittenVoice(v);
          },
        ),
      ),
    );
  }
}
