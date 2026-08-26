// Extracted from main.dart lines 12295-12511
// Extracted on: 2026-08-26T18:20:45.718786

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    const svgLangs = {'svg', 'chart', 'json-chart'};
    final visual = svgLangs.contains(language.toLowerCase());
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
