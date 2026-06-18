/// TermuxForge — Application Entry Point
///
/// Initializes the Isar database, secure storage, and core services,
/// then wraps the app in a Riverpod [ProviderScope] and runs
/// [TermuxForgeApp].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:termux_forge/app.dart';

/// Application bootstrap.
///
/// Initializes platform services and databases before launching the
/// widget tree. All heavy initialization is done here to keep the
/// widget layer clean.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait on phones (tablets stay flexible).
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

  // TODO: Initialize Isar database.
  // final dir = await getApplicationDocumentsDirectory();
  // final isar = await Isar.open(
  //   [ChatMessageSchema, ProjectSchema, ...],
  //   directory: dir.path,
  // );

  // TODO: Initialize flutter_secure_storage for API keys.
  // const secureStorage = FlutterSecureStorage();

  // TODO: Initialize services (TermuxBridge, MCP, etc.).

  runApp(
    const ProviderScope(
      // overrides: [
      //   isarProvider.overrideWithValue(isar),
      //   secureStorageProvider.overrideWithValue(secureStorage),
      // ],
      child: TermuxForgeApp(),
    ),
  );
}
