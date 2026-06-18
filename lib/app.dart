/// TermuxForge — Root Application Widget
///
/// Configures [MaterialApp.router] with:
/// - GoRouter navigation
/// - Material 3 dark/light themes
/// - Google Fonts typography
/// - Global error handling
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:termux_forge/core/router/app_router.dart';
import 'package:termux_forge/core/theme/app_theme.dart';

/// Root widget for the TermuxForge application.
///
/// Uses [ConsumerStatefulWidget] to access Riverpod providers for
/// theme mode and onboarding state.
class TermuxForgeApp extends ConsumerStatefulWidget {
  /// Creates the [TermuxForgeApp].
  const TermuxForgeApp({super.key});

  @override
  ConsumerState<TermuxForgeApp> createState() => _TermuxForgeAppState();
}

class _TermuxForgeAppState extends ConsumerState<TermuxForgeApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // TODO: Read isOnboarded from shared_preferences or Isar.
    _router = createRouter(isOnboarded: false);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Watch a themeMode provider for live toggling.
    // final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'TermuxForge',
      debugShowCheckedModeBanner: false,

      // ── Theme ──
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default to dark.

      // ── Router ──
      routerConfig: _router,

      // ── Global error widget ──
      builder: (context, child) {
        // Wrap in a global error boundary.
        ErrorWidget.builder = (details) => _AppErrorWidget(details: details);
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

/// A user-friendly error widget that replaces the default red screen.
class _AppErrorWidget extends StatelessWidget {
  const _AppErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
