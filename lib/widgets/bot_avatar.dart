import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nexon/widgets/bot_avatar_path.dart';
import 'package:nexon/widgets/bot_avatar_shapes.dart';

/// What the agent is doing right now.
enum BotAvatarState { idle, working, sleeping }

/// A single animated agent face, drawn from the bot-avatars body outlines.
///
/// The 3D fur/plastic shading of the web library is approximated with a smooth
/// gradient plus rim light: at the 28-40px sizes this is used at, the strand
/// detail is sub-pixel, and a CustomPainter keeps it cheap inside a scrolling
/// feed. Motion is a single controller driving idle sway, working bounce and a
/// slow sleeping breath.
class BotAvatar extends StatefulWidget {
  const BotAvatar({
    super.key,
    required this.type,
    this.state = BotAvatarState.idle,
    this.size = 34,
    this.color,
    this.face = 'eyes',
    this.paused = false,
    this.showLabel = true,
    this.label = '',
    this.seed = 0.0,
  });

  /// Body outline key, e.g. 'clover', 'star', 'cat'.
  final String type;
  final BotAvatarState state;
  final double size;
  final Color? color;

  /// 'eyes' or 'mouth'.
  final String face;
  final bool paused;
  final bool showLabel;
  final String label;

  /// 0-1 offset so a row of avatars does not animate in lockstep.
  final double seed;

  @override
  State<BotAvatar> createState() => _BotAvatarState();
}

class _BotAvatarState extends State<BotAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BotAvatar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state || old.paused != widget.paused) _sync();
  }

  void _sync() {
    if (widget.paused) {
      _c.stop();
      return;
    }
    if (!_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String pathData =
        kBotAvatarShapes[widget.type] ?? kBotAvatarShapes['circle']!;
    final Color body = widget.color ??
        (kBotAvatarColors[widget.type] ?? const Color(0xFF7B4E2E));

    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bool animate = !widget.paused && !reduceMotion;

    final Widget avatar = SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, Widget? _) {
            final double t =
                (_c.value + widget.seed) % 1.0;
            return CustomPaint(
              painter: _BotPainter(
                type: widget.type,
                pathData: pathData,
                body: body,
                phase: t,
                state: widget.state,
                face: widget.face,
                animate: animate,
              ),
            );
          },
        ),
      ),
    );

    if (!widget.showLabel) return avatar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        avatar,
        const SizedBox(height: 2),
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 7.5,
            height: 1.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: Color(0xFF5A6B85),
          ),
        ),
      ],
    );
  }
}

class _BotPainter extends CustomPainter {
  _BotPainter({
    required this.type,
    required this.pathData,
    required this.body,
    required this.phase,
    required this.state,
    required this.face,
    required this.animate,
  });

  final String type;
  final String pathData;
  final Color body;
  final double phase;
  final BotAvatarState state;
  final String face;
  final bool animate;

  // Face placement, in the 100x100 design box. Most bodies are round enough
  // that a single anchor reads correctly; the wide/flat bodies get nudged.
  static const Map<String, Offset> _faceAnchor = <String, Offset>{
    'pill': Offset(50, 50),
    'pebble': Offset(50, 52),
    'mech': Offset(50, 52),
    'droid': Offset(50, 54),
    'ghost': Offset(50, 45),
    'alien': Offset(50, 46),
    'drop': Offset(50, 56),
    'puddle': Offset(50, 50),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;

    final Path shape = botAvatarPath(pathData, size);
    final Rect box = Offset.zero & size;

    // ── motion ────────────────────────────────────────────────
    double dy = 0, rot = 0, sx = 1, sy = 1;
    if (animate) {
      switch (state) {
        case BotAvatarState.idle:
          dy = math.sin(phase * 2 * math.pi) * size.height * 0.022;
          rot = math.sin(phase * 2 * math.pi) * 0.035;
        case BotAvatarState.working:
          final double b = math.sin(phase * 4 * math.pi);
          dy = -b.abs() * size.height * 0.075;
          sx = 1 + b * 0.035;
          sy = 1 - b * 0.035;
        case BotAvatarState.sleeping:
          final double br = math.sin(phase * 2 * math.pi);
          sx = 1 + br * 0.012;
          sy = 1 - br * 0.012;
          dy = br * size.height * 0.006;
      }
    }

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + dy);
    canvas.rotate(rot);
    canvas.scale(sx, sy);
    canvas.translate(-size.width / 2, -size.height / 2);

    // ── body: soft vertical gradient + rim light ──────────────
    final Paint fill = Paint()
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          _lighten(body, 0.30),
          body,
          _darken(body, 0.22),
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(box);
    canvas.drawPath(shape, fill);

    // Contact shadow under the body.
    canvas.save();
    canvas.translate(0, size.height * 0.035);
    canvas.drawPath(
      shape,
      Paint()
        ..color = _darken(body, 0.5).withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.045),
    );
    canvas.restore();

    // Specular rim along the top edge.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, size.width * 0.035)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(box),
    );

    // ── face ─────────────────────────────────────────────────
    _paintFace(canvas, size);

    canvas.restore();
  }

  void _paintFace(Canvas canvas, Size size) {
    final double u = size.width / 100.0;
    final Offset anchor = _faceAnchor[type] ?? const Offset(50, 50);

    final double cx = anchor.dx * u;
    final double cy = anchor.dy * u;
    final double eyeR = 3.1 * u;
    final double gap = 8.4 * u;

    // Blink: a quick squash once per cycle on idle, held shut when sleeping.
    double lidClose = 0.0;
    if (state == BotAvatarState.sleeping) {
      lidClose = 1.0;
    } else if (animate) {
      final double b = (phase * 1.0) % 1.0;
      if (b > 0.94) {
        lidClose = math.sin((b - 0.94) / 0.06 * math.pi);
      }
    }

    // Look-around on idle: eyes drift sideways and back.
    double lookX = 0.0;
    if (animate && state == BotAvatarState.idle) {
      lookX = math.sin(phase * 2 * math.pi) * 1.5 * u;
    } else if (animate && state == BotAvatarState.working) {
      lookX = math.sin(phase * 4 * math.pi) * 0.9 * u;
    }

    final Paint ink = Paint()..isAntiAlias = true;
    final Color inkColor = _inkFor(body);

    for (int i = 0; i < 2; i++) {
      final double ex = cx + (i == 0 ? -gap : gap) + lookX;
      final double ey = cy;

      if (lidClose > 0.6) {
        // Shut lid: a soft arc.
        final Path lid = Path()
          ..moveTo(ex - eyeR, ey)
          ..quadraticBezierTo(ex, ey + eyeR * 0.85, ex + eyeR, ey);
        canvas.drawPath(
          lid,
          ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, 0.9 * u)
            ..strokeCap = StrokeCap.round
            ..color = inkColor,
        );
        ink.style = PaintingStyle.fill;
      } else {
        final double ry = eyeR * (1.0 - lidClose * 0.85);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, ey), width: eyeR * 1.75, height: ry * 2),
          ink..color = inkColor,
        );
        // Bead highlight.
        canvas.drawCircle(
          Offset(ex - eyeR * 0.35, ey - ry * 0.4),
          math.max(0.6, eyeR * 0.30),
          Paint()..color = Colors.white.withValues(alpha: 0.75),
        );
      }
    }

    if (face == 'mouth') {
      final Path mouth = Path()
        ..moveTo(cx - 3.2 * u, cy + 6.0 * u)
        ..quadraticBezierTo(cx, cy + 8.4 * u, cx + 3.2 * u, cy + 6.0 * u);
      canvas.drawPath(
        mouth,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, 1.0 * u)
          ..strokeCap = StrokeCap.round
          ..color = inkColor,
      );
    }
  }

  static Color _lighten(Color c, double amt) =>
      Color.lerp(c, Colors.white, amt) ?? c;

  static Color _darken(Color c, double amt) =>
      Color.lerp(c, Colors.black, amt) ?? c;

  /// Dark ink on light bodies, light ink on dark ones.
  static Color _inkFor(Color body) {
    final double lum = body.computeLuminance();
    return lum > 0.45
        ? const Color(0xFF2E2A26)
        : const Color(0xFFFFF8F0);
  }

  @override
  bool shouldRepaint(covariant _BotPainter old) =>
      old.phase != phase ||
      old.type != type ||
      old.state != state ||
      old.body != body ||
      old.pathData != pathData ||
      old.face != face ||
      old.animate != animate;
}
