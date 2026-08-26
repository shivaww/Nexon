// Extracted from main.dart lines 52-135
// Extracted on: 2026-08-26T18:20:45.738705

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

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
