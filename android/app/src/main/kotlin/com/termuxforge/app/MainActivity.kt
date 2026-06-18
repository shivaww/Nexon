package com.termuxforge.app

import io.flutter.embedding.android.FlutterActivity

/**
 * Main entry point for the TermuxForge Android application.
 *
 * This activity hosts the Flutter engine and delegates all UI
 * rendering to Flutter. Platform channel communication with
 * Termux and the Python bridge is handled by Flutter plugins
 * and the WebSocket bridge.
 */
class MainActivity : FlutterActivity()
