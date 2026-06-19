/// TermuxForge — Application Entry Point
///
/// Initializes storage services and launches the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:termux_forge/app.dart';
import 'package:termux_forge/services/storage/app_storage.dart';

/// Application bootstrap.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistent storage.
  await AppStorage.init();

  // Allow all orientations.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Set system UI style for the immersive dark theme.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Check if user has completed onboarding.
  final onboarded = await AppStorage.isOnboarded();

  runApp(
    ProviderScope(
      child: TermuxForgeApp(isOnboarded: onboarded),
    ),
  );
}
