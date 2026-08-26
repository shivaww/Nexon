// Extracted from main.dart lines 19882-20122
// Extracted on: 2026-08-26T18:20:45.688880

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
