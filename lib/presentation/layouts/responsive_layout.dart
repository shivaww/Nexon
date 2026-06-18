/// TermuxForge — Responsive Layout
///
/// Adapts the UI between phone (single-pane), tablet (dual-pane),
/// and desktop (full IDE) form factors using [LayoutBuilder].
library;

import 'package:flutter/material.dart';

/// Breakpoints for responsive layout decisions.
abstract final class Breakpoints {
  /// Phone max width.
  static const double phone = 600;

  /// Tablet max width.
  static const double tablet = 1024;

  /// Desktop min width.
  static const double desktop = 1025;
}

/// The current form factor.
enum FormFactor { phone, tablet, desktop }

/// A responsive layout builder that provides the correct UI for the
/// current screen size.
///
/// ```dart
/// ResponsiveLayout(
///   phone: (context) => MobileHome(),
///   tablet: (context) => TabletHome(),
///   desktop: (context) => DesktopHome(),
/// )
/// ```
class ResponsiveLayout extends StatelessWidget {
  /// Creates a [ResponsiveLayout].
  const ResponsiveLayout({
    required this.phone,
    super.key,
    this.tablet,
    this.desktop,
  });

  /// Builder for phone-sized screens (<600dp).
  final WidgetBuilder phone;

  /// Builder for tablet-sized screens (600-1024dp). Falls back to [phone].
  final WidgetBuilder? tablet;

  /// Builder for desktop-sized screens (>1024dp). Falls back to [tablet].
  final WidgetBuilder? desktop;

  /// Returns the current [FormFactor] for the given constraints width.
  static FormFactor formFactorOf(double width) {
    if (width < Breakpoints.phone) return FormFactor.phone;
    if (width < Breakpoints.desktop) return FormFactor.tablet;
    return FormFactor.desktop;
  }

  /// Convenience: returns the current [FormFactor] from [MediaQuery].
  static FormFactor of(BuildContext context) {
    return formFactorOf(MediaQuery.sizeOf(context).width);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final factor = formFactorOf(constraints.maxWidth);
        return switch (factor) {
          FormFactor.desktop => (desktop ?? tablet ?? phone)(context),
          FormFactor.tablet => (tablet ?? phone)(context),
          FormFactor.phone => phone(context),
        };
      },
    );
  }
}

/// An extension on [BuildContext] to quickly check the form factor.
extension ResponsiveContext on BuildContext {
  /// Returns the current [FormFactor].
  FormFactor get formFactor => ResponsiveLayout.of(this);

  /// Whether the current layout is phone-sized.
  bool get isPhone => formFactor == FormFactor.phone;

  /// Whether the current layout is tablet-sized.
  bool get isTablet => formFactor == FormFactor.tablet;

  /// Whether the current layout is desktop-sized.
  bool get isDesktop => formFactor == FormFactor.desktop;
}
