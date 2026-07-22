/// TermuxForge — Glassmorphism Card Widget
///
/// A frosted-glass card with configurable blur, opacity, border
/// radius, and optional gradient overlay. Used throughout the app
/// for sidebars, info panels, and elevated surfaces.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// A premium glassmorphism card widget.
///
/// ```dart
/// GlassCard(
///   child: Text('Hello'),
///   borderRadius: 20,
///   blurAmount: 15,
/// )
/// ```
class GlassCard extends StatelessWidget {
  /// Creates a [GlassCard].
  const GlassCard({
    required this.child,
    super.key,
    this.borderRadius = 16,
    this.blurAmount = 12,
    this.opacity = 0.72,
    this.padding,
    this.margin,
    this.gradient,
    this.borderColor,
    this.width,
    this.height,
    this.onTap,
    this.enableBlur = true,
  });

  /// The widget to display inside the glass card.
  final Widget child;

  /// Corner radius of the card. Defaults to 16.
  final double borderRadius;

  /// Strength of the backdrop blur. Defaults to 12.
  final double blurAmount;

  /// Opacity of the background surface. Defaults to 0.72.
  final double opacity;

  /// Inner padding. Defaults to `EdgeInsets.all(16)`.
  final EdgeInsetsGeometry? padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Optional gradient overlay on the glass surface.
  final Gradient? gradient;

  /// Border color override. Uses [AppColors.glassBorder] by default.
  final Color? borderColor;

  /// Fixed width.
  final double? width;

  /// Fixed height.
  final double? height;

  /// Tap callback — makes the card tappable.
  final VoidCallback? onTap;

  /// Disable backdrop blur for dense scrolling lists where a translucent
  /// surface is preferable to an expensive GPU blur.
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final effectiveOpacity =
        highContrast ? opacity.clamp(0.90, 1.0) as double : opacity;
    final surfaceColor = isDark
        ? AppColors.backgroundSecondary.withValues(alpha: effectiveOpacity)
        : const Color(0xFFFFFBF2).withValues(alpha: effectiveOpacity);
    final border = borderColor ??
        (isDark
            ? AppColors.glassBorder
            : const Color(0xFFE5DDD3).withValues(alpha: highContrast ? 0.95 : 0.72));
    final highlightEdge =
        isDark ? AppColors.glassHighlight : Colors.white.withValues(alpha: 0.5);

    final radius = BorderRadius.circular(borderRadius);
    Widget content = Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: radius,
            gradient: gradient,
            border: Border.all(color: border, width: 0.8),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: const Color(0xFF2D241C).withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          // Top highlight edge for 3D effect.
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border(top: BorderSide(color: highlightEdge, width: 0.5)),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    Widget card = ClipRRect(
      borderRadius: radius,
      child: enableBlur && !highContrast
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
              child: content,
            )
          : content,
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }
}
