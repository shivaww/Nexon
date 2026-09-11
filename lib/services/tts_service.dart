// Extracted from main.dart lines 138-228
// Extracted: 2026-08-26T13:46:48.250224

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexon/services/voice/live_voice_engine.dart';

class NexonTts {
  static final FlutterTts _flutterTts = FlutterTts();
  static String? _speakingText;
  static bool _isSpeaking = false;
  static Map<String, String>? _selectedVoice;

  /// Bumped on every speaking-state change so any read-aloud button in the
  /// chat can rebuild its icon without holding its own listener.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The caller's state callback for the current utterance. Kept here so the
  /// completion/cancel/error handlers can be bound to the engine exactly once
  /// instead of re-registered on every tap.
  static VoidCallback? _onStateChange;

  /// True once language/rate/volume/voice have been pushed to the engine.
  /// Re-applying them on every tap cost four platform round-trips before the
  /// first word was spoken — the lag on the read-aloud button.
  static bool _configured = false;
  static bool _handlersBound = false;

  static void _notify() {
    _onStateChange?.call();
    revision.value++;
  }

  static void _bindHandlersOnce() {
    if (_handlersBound) return;
    _handlersBound = true;
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _speakingText = null;
      _notify();
    });
    _flutterTts.setCancelHandler(() {
      _isSpeaking = false;
      _speakingText = null;
      _notify();
    });
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      _speakingText = null;
      _notify();
    });
  }

  static Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.48);
    await _flutterTts.setVolume(1.0);
    if (_selectedVoice != null) {
      await _flutterTts.setVoice(_selectedVoice!);
    }
    _configured = true;
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('tts_voice_name');
      if (saved != null && saved.isNotEmpty) {
        final locale = prefs.getString('tts_voice_locale') ?? 'en-US';
        _selectedVoice = {'name': saved, 'locale': locale};
      }
    } catch (_) {}
  }

  static Future<void> toggleSpeak(
    String text,
    VoidCallback onStateChange,
  ) async {
    text = sanitizeForTts(text);
    _onStateChange = onStateChange;
    try {
      // Tapping the button that is already reading stops it.
      if (_isSpeaking && _speakingText == text) {
        await _flutterTts.stop();
        _isSpeaking = false;
        _speakingText = null;
        _notify();
        return;
      }
      // Only interrupt the engine when something is actually playing — a
      // stop() on an idle engine is a wasted round-trip before every start.
      if (_isSpeaking) {
        await _flutterTts.stop();
      }
      _bindHandlersOnce();
      _speakingText = text;
      _isSpeaking = true;
      // Flip the icon first so the tap feels instant, then pay the one-time
      // engine setup on the very first utterance only.
      _notify();
      await _ensureConfigured();
      await _flutterTts.speak(text);
    } catch (_) {
      _isSpeaking = false;
      _speakingText = null;
      _notify();
    }
  }

  static bool isSpeaking(String text) {
    return _isSpeaking && _speakingText == text;
  }

  /// Same as [isSpeaking] but accepts the raw (unsanitized) message text,
  /// matching what [toggleSpeak] stores while it is reading.
  static bool isSpeakingMessage(String rawText) {
    return _isSpeaking && _speakingText == sanitizeForTts(rawText);
  }

  static Future<List<dynamic>> getVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) return voices;
    } catch (_) {}
    return [];
  }

  static Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoice = voice;
    // Force the next utterance to re-apply voice/language/rate together.
    _configured = false;
    try {
      await _flutterTts.setVoice(voice);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tts_voice_name', voice['name'] ?? '');
      await prefs.setString('tts_voice_locale', voice['locale'] ?? 'en-US');
    } catch (_) {}
  }

  static String? get selectedVoiceName => _selectedVoice?['name'];
}
