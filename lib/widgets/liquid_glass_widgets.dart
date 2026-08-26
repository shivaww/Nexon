// Extracted from main.dart lines 140-445
// Extracted on: 2026-08-26T18:20:45.737553

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

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
