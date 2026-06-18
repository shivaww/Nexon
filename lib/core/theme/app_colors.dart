/// TermuxForge Design System — Color Palette
///
/// A curated set of colors following Material You principles with
/// a premium dark-mode-first aesthetic. Every color is intentionally
/// chosen to convey meaning: agent identity, permission risk level,
/// operational status, and surface hierarchy.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

/// Central color palette for the entire TermuxForge application.
///
/// Usage:
/// ```dart
/// Container(color: AppColors.backgroundPrimary);
/// ```
abstract final class AppColors {
  // ──────────────────────────────────────────────
  //  Background & Surface
  // ──────────────────────────────────────────────

  /// Primary dark background — deep navy/charcoal.
  static const Color backgroundPrimary = Color(0xFF0D1117);

  /// Slightly lighter surface for cards & panels.
  static const Color backgroundSecondary = Color(0xFF161B22);

  /// Elevated surface (modals, dialogs).
  static const Color backgroundTertiary = Color(0xFF1C2128);

  /// Subtle border / divider on dark backgrounds.
  static const Color borderSubtle = Color(0xFF30363D);

  /// Stronger border for focus states.
  static const Color borderStrong = Color(0xFF484F58);

  // Light theme counterparts.
  static const Color backgroundPrimaryLight = Color(0xFFF6F8FA);
  static const Color backgroundSecondaryLight = Color(0xFFFFFFFF);
  static const Color backgroundTertiaryLight = Color(0xFFEBEDF0);
  static const Color borderSubtleLight = Color(0xFFD0D7DE);
  static const Color borderStrongLight = Color(0xFF8B949E);

  // ──────────────────────────────────────────────
  //  Gradient Backgrounds
  // ──────────────────────────────────────────────

  /// Hero gradient for the main background.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D1117), Color(0xFF111827), Color(0xFF0F172A)],
  );

  /// Sidebar gradient — subtle purple tint.
  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF161B22), Color(0xFF13111C)],
  );

  /// Accent glow gradient for highlights.
  static const LinearGradient accentGlow = LinearGradient(
    colors: [Color(0xFF58A6FF), Color(0xFF8B5CF6)],
  );

  /// Premium card gradient.
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1A58A6FF), Color(0x0D8B5CF6)],
  );

  // ──────────────────────────────────────────────
  //  Primary Accent
  // ──────────────────────────────────────────────

  /// Electric blue — primary interactive color.
  static const Color accentBlue = Color(0xFF58A6FF);

  /// Hover / pressed variant.
  static const Color accentBlueDark = Color(0xFF388BFD);

  /// Softer blue for badges and tags.
  static const Color accentBlueLight = Color(0xFFB6DCFE);

  /// Purple accent for secondary highlights.
  static const Color accentPurple = Color(0xFF8B5CF6);

  /// Teal for tertiary elements.
  static const Color accentTeal = Color(0xFF2DD4BF);

  // ──────────────────────────────────────────────
  //  Agent Identity Colors
  // ──────────────────────────────────────────────

  /// Returns the signature color for each agent type.
  static Color agentColor(String agentType) {
    return switch (agentType.toLowerCase()) {
      'orchestrator' => const Color(0xFF58A6FF), // Blue — command center
      'coder' => const Color(0xFF7C3AED), // Violet — creative
      'architect' => const Color(0xFF2DD4BF), // Teal — structural
      'debugger' => const Color(0xFFF97316), // Orange — alert
      'reviewer' => const Color(0xFF22D3EE), // Cyan — analytical
      'devops' => const Color(0xFF10B981), // Emerald — operational
      'researcher' => const Color(0xFFA78BFA), // Lavender — explorative
      'tester' => const Color(0xFFFBBF24), // Amber — validation
      'documenter' => const Color(0xFF60A5FA), // Sky — informational
      'security' => const Color(0xFFEF4444), // Red — critical
      'background' => const Color(0xFF6366F1), // Indigo — autonomous
      _ => const Color(0xFF8B949E), // Gray — default
    };
  }

  /// Returns a soft background variant of an agent color.
  static Color agentColorSoft(String agentType) =>
      agentColor(agentType).withValues(alpha: 0.15);

  // ──────────────────────────────────────────────
  //  Permission Level Colors
  // ──────────────────────────────────────────────

  /// Green — safe, auto-approved.
  static const Color permissionSafe = Color(0xFF10B981);

  /// Yellow — low risk, usually approved.
  static const Color permissionLow = Color(0xFFFBBF24);

  /// Orange — moderate risk, review recommended.
  static const Color permissionModerate = Color(0xFFF97316);

  /// Red — high risk, manual approval required.
  static const Color permissionDangerous = Color(0xFFEF4444);

  /// Returns the color for a numeric permission level (1-10).
  static Color permissionLevel(int level) {
    if (level <= 3) return permissionSafe;
    if (level <= 5) return permissionLow;
    if (level <= 7) return permissionModerate;
    return permissionDangerous;
  }

  // ──────────────────────────────────────────────
  //  Mode Indicator Colors
  // ──────────────────────────────────────────────

  static const Color modeCode = Color(0xFF7C3AED); // Violet
  static const Color modeArchitect = Color(0xFF2DD4BF); // Teal
  static const Color modeDebug = Color(0xFFF97316); // Orange
  static const Color modeAsk = Color(0xFF58A6FF); // Blue
  static const Color modeReview = Color(0xFF22D3EE); // Cyan
  static const Color modeDeploy = Color(0xFF10B981); // Emerald
  static const Color modeResearch = Color(0xFFA78BFA); // Lavender
  static const Color modeTest = Color(0xFFFBBF24); // Amber
  static const Color modeDocument = Color(0xFF60A5FA); // Sky
  static const Color modeSecurity = Color(0xFFEF4444); // Red
  static const Color modeBattle = Color(0xFFEC4899); // Pink

  /// Returns the color for a named mode.
  static Color modeColor(String mode) {
    return switch (mode.toLowerCase()) {
      'code' => modeCode,
      'architect' => modeArchitect,
      'debug' => modeDebug,
      'ask' => modeAsk,
      'review' => modeReview,
      'deploy' => modeDeploy,
      'research' => modeResearch,
      'test' => modeTest,
      'document' => modeDocument,
      'security' => modeSecurity,
      'battle' => modeBattle,
      _ => accentBlue,
    };
  }

  // ──────────────────────────────────────────────
  //  Semantic / Status Colors
  // ──────────────────────────────────────────────

  static const Color success = Color(0xFF10B981);
  static const Color successSoft = Color(0x2610B981);
  static const Color warning = Color(0xFFFBBF24);
  static const Color warningSoft = Color(0x26FBBF24);
  static const Color error = Color(0xFFEF4444);
  static const Color errorSoft = Color(0x26EF4444);
  static const Color info = Color(0xFF58A6FF);
  static const Color infoSoft = Color(0x2658A6FF);

  // ──────────────────────────────────────────────
  //  Text Colors
  // ──────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textTertiary = Color(0xFF6E7681);
  static const Color textLink = Color(0xFF58A6FF);

  static const Color textPrimaryLight = Color(0xFF1F2328);
  static const Color textSecondaryLight = Color(0xFF656D76);
  static const Color textTertiaryLight = Color(0xFF8B949E);

  // ──────────────────────────────────────────────
  //  Glassmorphism Surfaces
  // ──────────────────────────────────────────────

  /// Semi-transparent overlay for glass effect.
  static Color glassSurface = const Color(0xFF161B22).withValues(alpha: 0.72);

  /// Frosted glass border.
  static Color glassBorder = const Color(0xFFFFFFFF).withValues(alpha: 0.08);

  /// Highlight edge for glass.
  static Color glassHighlight =
      const Color(0xFFFFFFFF).withValues(alpha: 0.04);

  // ──────────────────────────────────────────────
  //  Utility
  // ──────────────────────────────────────────────

  /// Creates a shimmer / loading color list.
  static List<Color> get shimmerGradient => [
    backgroundSecondary,
    backgroundTertiary,
    backgroundSecondary,
  ];
}
