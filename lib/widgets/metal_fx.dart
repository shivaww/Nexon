import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Liquid-metal presets tuned to Nexon's warm cream/bronze palette.
enum MetalPreset { bronze, silver, gold }

/// Shape of the surface being wrapped.
enum MetalVariant { circle, button }

/// Colour set for one metal preset: rotating sheen bands, halo glow, rim.
class _MetalPalette {
  const _MetalPalette(this.sheen, this.halo, this.rim);

  final List<Color> sheen;
  final Color halo;
  final Color rim;

  static const Map<MetalPreset, _MetalPalette> all =
      <MetalPreset, _MetalPalette>{
    MetalPreset.bronze: _MetalPalette(
      <Color>[
        Color(0xFFFFE9C9),
        Color(0xFFC98F5B),
        Color(0xFF7B4E2E),
        Color(0xFFF6DDB4),
      ],
      Color(0xFFE9A85C),
      Color(0xFFFFF3E0),
    ),
    MetalPreset.silver: _MetalPalette(
      <Color>[
        Color(0xFFF7F7F7),
        Color(0xFFC9CDD3),
        Color(0xFF8B9099),
        Color(0xFFE8EBEF),
      ],
      Color(0xFFBFC7D1),
      Color(0xFFFFFFFF),
    ),
    MetalPreset.gold: _MetalPalette(
      <Color>[
        Color(0xFFFFF3C4),
        Color(0xFFD9B45A),
        Color(0xFF8A6A22),
        Color(0xFFF7E3A1),
      ],
      Color(0xFFE4C56B),
      Color(0xFFFFF8DC),
    ),
  };
}

/// Paints the liquid-metal ring: rotating sheen bands, a wandering halo
/// outside the edge, and a punched-out centre so the child stays legible.
class _MetalRingPainter extends CustomPainter {
  _MetalRingPainter({
    required this.palette,
    required this.progress,
    required this.strength,
    required this.variant,
    required this.glowGain,
    required this.disableGlow,
  });

  final _MetalPalette palette;
  final double progress;
  final double strength;
  final MetalVariant variant;
  final double glowGain;
  final bool disableGlow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final Rect rect = Offset.zero & size;
    final Path outer = _shapePath(rect);
    final double band = size.shortestSide * 0.14;

    // Halo: a soft rotating glow just outside the rim.
    if (!disableGlow) {
      final double angle = progress * 2 * math.pi;
      final Offset haloCentre = rect.center +
          Offset(math.cos(angle), math.sin(angle)) * (size.shortestSide * 0.06);
      final Paint halo = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            palette.halo.withValues(alpha: 0.55 * strength * glowGain),
            palette.halo.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
          center: haloCentre,
          radius: size.shortestSide * 0.62,
        ));
      canvas.drawCircle(haloCentre, size.shortestSide * 0.62, halo);
    }

    // Sheen: sweep the palette bands around the ring over time.
    final double sweep = progress * 2 * math.pi;
    final Paint sheen = Paint()
      ..shader = SweepGradient(
        startAngle: sweep,
        endAngle: sweep + 2 * math.pi,
        colors: palette.sheen
            .map((Color c) => c.withValues(alpha: 0.85 * strength))
            .toList(growable: false),
        stops: const <double>[0.0, 0.35, 0.65, 1.0],
      ).createShader(rect);
    canvas.drawPath(outer, sheen);

    // Punch the centre back out so the icon/child sits on its own colour.
    canvas.saveLayer(rect, Paint());
    canvas.drawPath(outer, Paint()..color = const Color(0xFF000000));
    canvas.drawPath(
      _shapePath(rect.deflate(band)),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    // Specular top rim — the same trick as the app's glass buttons.
    final Paint rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          palette.rim.withValues(alpha: 0.9 * strength),
          palette.rim.withValues(alpha: 0.15 * strength),
        ],
      ).createShader(rect);
    canvas.drawPath(outer.deflate(0.6), rim);
  }

  Path _shapePath(Rect rect) {
    final Path p = Path();
    if (variant == MetalVariant.circle) {
      p.addOval(rect);
    } else {
      p.addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height * 0.5)),
      );
    }
    return p;
  }

  @override
  bool shouldRepaint(covariant _MetalRingPainter old) =>
      old.progress != progress ||
      old.strength != strength ||
      old.palette != palette ||
      old.variant != variant ||
      old.glowGain != glowGain ||
      old.disableGlow != disableGlow;
}

/// Wraps any child in a real-time liquid-metal ring.
///
/// Falls back to [child] untouched when [enabled] is false, so callers can
/// respect reduced-motion / battery-saver settings without branching.
class MetalFx extends StatefulWidget {
  const MetalFx({
    super.key,
    required this.child,
    this.preset = MetalPreset.bronze,
    this.variant = MetalVariant.circle,
    this.strength = 1.0,
    this.disableGlow = false,
    this.glowGain = 1.0,
    this.paused = false,
    this.enabled = true,
  });

  final Widget child;
  final MetalPreset preset;
  final MetalVariant variant;
  final double strength;
  final bool disableGlow;
  final double glowGain;
  final bool paused;
  final bool enabled;

  @override
  State<MetalFx> createState() => _MetalFxState();
}

class _MetalFxState extends State<MetalFx>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MetalFx old) {
    super.didUpdateWidget(old);
    if (old.paused != widget.paused || old.enabled != widget.enabled) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (!widget.enabled || widget.paused) {
      _controller.stop();
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    // Respect the OS reduced-motion / power-saving hint.
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? _) {
                  return CustomPaint(
                    painter: _MetalRingPainter(
                      palette: _MetalPalette.all[widget.preset]!,
                      progress: _controller.value,
                      strength: widget.strength.clamp(0.0, 1.0),
                      variant: widget.variant,
                      glowGain: widget.glowGain,
                      disableGlow: widget.disableGlow,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
