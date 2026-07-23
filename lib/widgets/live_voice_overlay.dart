import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

class _LiveVoiceOverlayState extends State<LiveVoiceOverlay> {
  bool _showCaptions = true;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngineChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptMicPermission();
    });
  }

  Future<void> _checkAndPromptMicPermission() async {
    final granted = await widget.engine.checkMicPermission();
    if (!granted && mounted) {
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
            'Nexon Live Voice Mode uses your microphone to listen to your voice commands and converse with you hands-free.\n\nTap "Grant Permission" to allow OS microphone access.',
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

      if (shouldRequest == true) {
        await widget.engine.requestMicPermission();
      }
    }

    if (widget.engine.state == LiveVoiceState.idle) {
      widget.engine.startListening(onFinalResult: widget.onSendPrompt);
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineChange);
    super.dispose();
  }

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final soundLevel = widget.engine.soundLevel;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Fullscreen Backdrop
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

          // Main Layout
          SafeArea(
            child: Column(
              children: [
                // Top Header Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B4E2E).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
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
                          // Toggle Captions Button
                          IconButton(
                            tooltip: _showCaptions ? 'Hide Captions' : 'Show Captions',
                            style: IconButton.styleFrom(
                              backgroundColor: _showCaptions
                                  ? const Color(0xFF7B4E2E).withValues(alpha: 0.15)
                                  : Colors.transparent,
                            ),
                            icon: Icon(
                              _showCaptions
                                  ? Icons.subtitles_rounded
                                  : Icons.subtitles_off_outlined,
                              color: const Color(0xFF7B4E2E),
                            ),
                            onPressed: () {
                              setState(() => _showCaptions = !_showCaptions);
                            },
                          ),
                          const SizedBox(width: 8),
                          // Exit Button
                          IconButton(
                            tooltip: 'Exit Voice Mode',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF7B4E2E).withValues(alpha: 0.12),
                            ),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF2D241C),
                              size: 24,
                            ),
                            onPressed: widget.onClose,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status Banner
                _buildStatusHeader(state),

                // Center Animated Glass Orb Focal Point
                Expanded(
                  child: Center(
                    child: _buildAnimatedLiquidOrb(state, soundLevel),
                  ),
                ),

                // Live Captions Subtitle Box
                if (_showCaptions) _buildLiveCaptionsBox(state),

                const SizedBox(height: 16),

                // Bottom Action Bar & Barge-in Controls
                _buildBottomControls(state),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        statusColor = const Color(0xFFB9381E);
        break;
      case LiveVoiceState.idle:
      default:
        statusText = 'Tap mic to start speaking';
        statusColor = const Color(0xFF6C5946);
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(statusText),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        ),
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

  Widget _buildAnimatedLiquidOrb(LiveVoiceState state, double soundLevel) {
    // Determine gradient colors & scale per state using implicit animations
    List<Color> gradientColors;
    double orbScale;
    double blurSigma;

    switch (state) {
      case LiveVoiceState.listening:
        gradientColors = [
          const Color(0xFFEADCC9),
          const Color(0xFFD8B98D),
          const Color(0xFFB88E5E),
        ];
        orbScale = 1.0 + (soundLevel * 0.35);
        blurSigma = 18.0;
        break;
      case LiveVoiceState.thinking:
        gradientColors = [
          const Color(0xFF9B6B43),
          const Color(0xFF7B4E2E),
          const Color(0xFF56331A),
        ];
        orbScale = 1.05;
        blurSigma = 24.0;
        break;
      case LiveVoiceState.speaking:
        gradientColors = [
          const Color(0xFFF3D5A5),
          const Color(0xFFE4B373),
          const Color(0xFFC58B49),
        ];
        orbScale = 1.15;
        blurSigma = 20.0;
        break;
      case LiveVoiceState.error:
        gradientColors = [
          const Color(0xFFF8D7DA),
          const Color(0xFFE29399),
          const Color(0xFFB9381E),
        ];
        orbScale = 0.95;
        blurSigma = 12.0;
        break;
      case LiveVoiceState.idle:
      default:
        gradientColors = [
          const Color(0xFFF5EADA),
          const Color(0xFFE5D5C0),
          const Color(0xFFCDB89E),
        ];
        orbScale = 1.0;
        blurSigma = 15.0;
        break;
    }

    return GestureDetector(
      onTap: () {
        if (state == LiveVoiceState.speaking) {
          widget.engine.interrupt();
        } else if (state == LiveVoiceState.idle || state == LiveVoiceState.error) {
          widget.engine.startListening(onFinalResult: widget.onSendPrompt);
        }
      },
      child: AnimatedScale(
        scale: orbScale,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: gradientColors,
              center: Alignment.topLeft,
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
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 2.0,
                  ),
                ),
                child: Center(
                  child: Icon(
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
      ),
    );
  }

  Widget _buildLiveCaptionsBox(LiveVoiceState state) {
    String textToShow = '';
    if (state == LiveVoiceState.listening || state == LiveVoiceState.thinking) {
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

  Widget _buildBottomControls(LiveVoiceState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Barge-in / Mic Action Button
        FloatingActionButton.large(
          elevation: 4,
          backgroundColor: state == LiveVoiceState.speaking
              ? const Color(0xFFB5784C)
              : state == LiveVoiceState.listening
                  ? const Color(0xFF7B4E2E)
                  : const Color(0xFF8C5C39),
          foregroundColor: const Color(0xFFFFF8EA),
          child: Icon(
            state == LiveVoiceState.speaking
                ? Icons.stop_rounded
                : state == LiveVoiceState.listening
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
            size: 38,
          ),
          onPressed: () {
            if (state == LiveVoiceState.speaking) {
              // Immediate barge-in interrupt
              widget.engine.interrupt();
              widget.engine.startListening(onFinalResult: widget.onSendPrompt);
            } else if (state == LiveVoiceState.listening) {
              widget.engine.stopListening();
            } else {
              widget.engine.startListening(onFinalResult: widget.onSendPrompt);
            }
          },
        ),
      ],
    );
  }
}
