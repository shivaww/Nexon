import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum LiveVoiceState { idle, listening, thinking, speaking, error }

/// Hands-free speech recognition and reply playback.
/// Uses the device's native TTS engine (flutter_tts) for all voice output.
class LiveVoiceEngine extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  FlutterTts? _flutterTts;
  bool _speechInitialized = false;
  bool _stopRequested = false;
  int _silentRestartCount = 0;
  ValueChanged<String>? _onFinalSpeechResult;

  LiveVoiceState _state = LiveVoiceState.idle;
  LiveVoiceState get state => _state;
  bool _isSpeechAvailable = false;
  bool get isSpeechAvailable => _isSpeechAvailable;
  String _recognizedText = '';
  String get recognizedText => _recognizedText;
  String _spokenText = '';
  String get spokenText => _spokenText;
  String _errorMessage = '';
  String get errorMessage => _errorMessage;
  double _soundLevel = 0;
  double get soundLevel => _soundLevel;

  final List<String> _sentenceQueue = [];
  bool _isTtsSpeaking = false;
  StringBuffer _streamBuffer = StringBuffer();
  Completer<void>? _currentSentenceCompleter;

  void _setState(LiveVoiceState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  // ── Permission ────────────────────────────────────────────────────────────

  /// Returns the current microphone [PermissionStatus] without requesting it.
  Future<PermissionStatus> micPermissionStatus() =>
      Permission.microphone.status;

  /// Returns true if microphone is already granted.
  Future<bool> checkMicPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Fires the real OS RECORD_AUDIO dialog if not already granted.
  /// Returns true when the permission is granted after the call.
  Future<bool> requestMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      _errorMessage =
          'Microphone access is blocked. Enable it in Android app settings.';
      _setState(LiveVoiceState.error);
      return false;
    }

    // Fire the real OS dialog.
    status = await Permission.microphone.request();

    if (status.isGranted) return true;

    _errorMessage = status.isPermanentlyDenied
        ? 'Microphone access is blocked. Enable it in Android app settings.'
        : 'Microphone permission was not granted.';
    _setState(LiveVoiceState.error);
    return false;
  }

  void setError(String message) {
    _errorMessage = message;
    _setState(LiveVoiceState.error);
  }

  Future<bool> initSpeech() async {
    // Re-check permission — must be granted before initialising STT.
    if (!await checkMicPermission()) return false;

    if (_speechInitialized && _isSpeechAvailable) return true;

    // Allow re-initialization if the previous attempt failed.
    _speechInitialized = false;

    try {
      _isSpeechAvailable = await _speechToText.initialize(
        onError: (val) {
          _errorMessage = 'Mic/Speech error: ${val.errorMsg}';
          _setState(LiveVoiceState.error);
        },
        onStatus: _handleSpeechStatus,
      );
      _speechInitialized = _isSpeechAvailable; // only mark done when success
      if (!_isSpeechAvailable) {
        _errorMessage = 'Speech recognition is unavailable on this device.';
        _setState(LiveVoiceState.error);
      }
      return _isSpeechAvailable;
    } catch (e) {
      _errorMessage = 'Speech initialization failed.';
      debugPrint('LiveVoice speech init failed: $e');
      _setState(LiveVoiceState.error);
      return false;
    }
  }

  // ── Listening ─────────────────────────────────────────────────────────────

  Future<void> startListening({
    required ValueChanged<String> onFinalResult,
  }) async {
    // Permission must be granted before speech_to_text is used.
    if (!await requestMicPermission()) return;
    if (!await initSpeech()) return;

    _silentRestartCount = 0;
    _onFinalSpeechResult = onFinalResult;
    await stopTts();
    _stopRequested =
        false; // fresh listening session — do not drop the first reply
    _recognizedText = '';
    _errorMessage = '';
    _setState(LiveVoiceState.listening);
    await _listen(onFinalResult: onFinalResult);
  }

  Future<void> _listen({required ValueChanged<String> onFinalResult}) async {
    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        _recognizedText = result.recognizedWords;
        notifyListeners();
        if (result.finalResult && _recognizedText.trim().isNotEmpty) {
          _silentRestartCount = 0;
          _setState(LiveVoiceState.thinking);
          onFinalResult(_recognizedText.trim());
        }
      },
      onSoundLevelChange: (double level) {
        _soundLevel = level.clamp(0.0, 10.0) / 10.0;
        notifyListeners();
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: false,
    );
  }

  void _handleSpeechStatus(String status) {
    if ((status != 'done' && status != 'notListening') ||
        _state != LiveVoiceState.listening) {
      return;
    }
    if (_recognizedText.isNotEmpty) {
      _setState(LiveVoiceState.thinking);
      return;
    }

    // speech_to_text exposes status through initialize(), not listen().
    // Keep the capped silent-restart behavior using that global callback.
    final onFinalResult = _onFinalSpeechResult;
    if (onFinalResult == null || _silentRestartCount >= 3) return;
    _silentRestartCount++;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_state == LiveVoiceState.listening &&
          identical(_onFinalSpeechResult, onFinalResult)) {
        _listen(onFinalResult: onFinalResult);
      }
    });
  }

  Future<void> stopListening() async {
    _onFinalSpeechResult = null;
    await _speechToText.stop();
  }

  // ── TTS streaming ─────────────────────────────────────────────────────────

  void startStreamResponse() {
    _streamBuffer.clear();
    _sentenceQueue.clear();
    _spokenText = '';
    _setState(LiveVoiceState.thinking);
  }

  void feedStreamToken(String token) {
    _streamBuffer.write(token);
    _spokenText = _streamBuffer.toString();
    notifyListeners();
    final currentText = _streamBuffer.toString();
    final matches = RegExp(
      r'(?<=[.!?])\s+(?=[A-Z0-9])|\n+',
    ).allMatches(currentText).toList();
    if (matches.isEmpty) return;
    var lastCut = 0;
    for (final match in matches) {
      final sentence = currentText.substring(lastCut, match.end).trim();
      if (sentence.isNotEmpty && sentence.length >= 3) {
        _enqueueSentence(sentence);
      }
      lastCut = match.end;
    }
    _streamBuffer = StringBuffer(currentText.substring(lastCut));
  }

  void endStreamResponse() {
    final remaining = _streamBuffer.toString().trim();
    if (remaining.isNotEmpty) _enqueueSentence(remaining);
    _streamBuffer.clear();
  }

  void _enqueueSentence(String rawSentence) {
    final clean = sanitizeForNaturalTts(stripSsml(rawSentence));
    if (clean.length < 2) return;
    _sentenceQueue.add(clean);
    if (!_isTtsSpeaking) unawaited(_playNextSentence());
  }

  // ── TTS ────────────────────────────────────────────────────────────────────

  Future<void> _playNextSentence() async {
    if (_stopRequested) {
      _stopRequested = false;
      return;
    }
    if (_sentenceQueue.isEmpty) {
      _isTtsSpeaking = false;
      if (_state == LiveVoiceState.speaking) _setState(LiveVoiceState.idle);
      return;
    }
    _isTtsSpeaking = true;
    _setState(LiveVoiceState.speaking);
    var sentence = _sentenceQueue.removeAt(0);
    sentence = sanitizeForNaturalTts(sentence);
    _currentSentenceCompleter = Completer<void>();

    try {
      await _speakWithNative(sentence);
    } catch (e) {
      debugPrint('LiveVoice TTS failed: $e');
      _errorMessage = 'Voice playback is unavailable.';
      _finishSentence();
      _setState(LiveVoiceState.error);
    }
  }

  Future<void> _speakWithNative(String sentence) async {
    final tts = _flutterTts ??= FlutterTts();
    tts.setCompletionHandler(_finishSentence);
    tts.setCancelHandler(_finishSentence);
    tts.setErrorHandler((message) => _finishSentence());
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.48);
    await tts.setVolume(1.0);
    await tts.speak(sentence);
  }

  void _finishSentence() {
    _isTtsSpeaking = false;
    final completer = _currentSentenceCompleter;
    // Only complete + advance once per sentence so a double finish never
    // schedules the next sentence twice.
    if (completer == null || completer.isCompleted) return;
    completer.complete();
    unawaited(_playNextSentence());
  }

  Future<void> interrupt() async {
    _stopRequested = true;
    _onFinalSpeechResult = null;
    _sentenceQueue.clear();
    await stopTts();
    await _speechToText.stop();
    _setState(LiveVoiceState.idle);
  }

  Future<void> stopTts() async {
    _stopRequested = true;
    _sentenceQueue.clear();
    _streamBuffer.clear();
    _isTtsSpeaking = false;
    await _flutterTts?.stop();
    if (_currentSentenceCompleter != null &&
        !_currentSentenceCompleter!.isCompleted) {
      _currentSentenceCompleter!.complete();
    }
  }

  String stripSsml(String text) => text
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  void dispose() {
    _speechToText.cancel();
    _flutterTts?.stop();
    super.dispose();
  }
}

/// Sanitizes text before it reaches a TTS engine so markdown, symbols, URLs,
/// code and emojis are not read out loud (e.g. as "asterisk", "hash" or
/// "dollar"). Keeps `, . ! ? : ; ( ) ' "` for prosody.
String sanitizeForTts(String text) {
  var result = text;

  // SSML-style tags.
  result = result.replaceAll(RegExp(r'<[^>]*>'), ' ');

  // Fenced code blocks ```...``` -> "code block".
  result = result.replaceAll(RegExp(r'```[\s\S]*?```'), ' code block ');

  // Inline `code`.
  result = result.replaceAll(RegExp(r'`[^`\n]*`'), ' code ');

  // Markdown links [text](url) -> text.
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m[1] ?? '',
  );

  // Bare http(s):// and www. URLs.
  result = result.replaceAll(
    RegExp(r'https?://\S+', caseSensitive: false),
    ' ',
  );
  result = result.replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ');

  // Currency: $50 / $1,000.00 -> "50 dollars" / "1,000.00 dollars".
  result = result.replaceAllMapped(
    RegExp(r'\$\s*(\d[\d,]*(?:\.\d+)?)'),
    (m) => '${m[1]} dollars',
  );

  // Percent: 50% -> "50 percent".
  result = result.replaceAllMapped(
    RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*%'),
    (m) => '${m[1]} percent',
  );

  // Markdown blockquotes, headings and list markers at line starts.
  result = result.replaceAll(RegExp(r'^[ \t]*>[ \t]*', multiLine: true), ' ');
  result = result.replaceAll(
    RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true),
    ' ',
  );
  result = result.replaceAll(
    RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true),
    ' ',
  );

  // Markdown emphasis / strikethrough pairs.
  result = result.replaceAll(RegExp(r'\*\*'), ' ');
  result = result.replaceAll(RegExp(r'__'), ' ');
  result = result.replaceAll(RegExp(r'~~'), ' ');

  // Symbols TTS would otherwise read out as words (after currency/percent).
  result = result.replaceAll(RegExp(r'[*#%^&{}\[\]@\\|/<>+=~`_\-]'), ' ');

  // Drop the space a removed symbol left in front of kept punctuation.
  result = result.replaceAll(RegExp(r'\s+(?=[,.!?;:)])'), '');

  // Fix duplicate punctuation (e.g. "ok!!!") while keeping one for prosody.
  result = result.replaceAllMapped(RegExp(r'([,.!?;:])\1+'), (m) => m[1]!);

  // Emoji and unicode pictographs.
  result = result.replaceAll(
    RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
      r'\u{2190}-\u{21FF}\u{FE00}-\u{FE0F}\u{200D}\u{20E3}]',
      unicode: true,
    ),
    ' ',
  );

  // Collapse whitespace.
  result = result.replaceAll(RegExp(r'\s+'), ' ');

  return result.trim();
}

/// Sanitizes text for natural-sounding TTS: converts meaningful symbols into
/// spoken words (dollars, percent, times, plus, etc.), strips decorative
/// markdown/symbols, and keeps prosody punctuation so the engine never says
/// "comma", "asterisk", "hash" or "dollar".
String sanitizeForNaturalTts(String text) {
  if (text.isEmpty) return '';

  var result = text;

  // Fenced code blocks ```...``` -> ' . Code block. '
  result = result.replaceAll(RegExp(r'```[\s\S]*?```'), ' . Code block. ');

  // Inline `code`.
  result = result.replaceAll(RegExp(r'`[^`\n]*`'), ' code ');

  // Markdown links [text](url) -> text.
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m[1] ?? '',
  );

  // Bare http(s):// and www. URLs.
  result = result.replaceAll(
    RegExp(r'https?://\S+', caseSensitive: false),
    ' ',
  );
  result = result.replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ');

  // $number -> number dollars.
  result = result.replaceAllMapped(
    RegExp(r'\$(\d+)'),
    (m) => '${m[1]} dollars',
  );

  // number% -> number percent.
  result = result.replaceAllMapped(
    RegExp(r'(\d+)\s*%'),
    (m) => '${m[1]} percent',
  );

  // number*number or number x number -> number times number.
  result = result.replaceAllMapped(
    RegExp(r'(\d+)\s*[*xX]\s*(\d+)'),
    (m) => '${m[1]} times ${m[2]}',
  );

  // number-number -> number to number.
  result = result.replaceAllMapped(
    RegExp(r'(\d+)\s*-\s*(\d+)'),
    (m) => '${m[1]} to ${m[2]}',
  );

  // number+number -> number plus number.
  result = result.replaceAllMapped(
    RegExp(r'(\d+)\s*\+\s*(\d+)'),
    (m) => '${m[1]} plus ${m[2]}',
  );

  // number=number -> number equals number.
  result = result.replaceAllMapped(
    RegExp(r'(\d+)\s*=\s*(\d+)'),
    (m) => '${m[1]} equals ${m[2]}',
  );

  // & -> and.
  result = result.replaceAll('&', ' and ');

  // @ -> at.
  result = result.replaceAll('@', ' at ');

  // #number -> number number.
  result = result.replaceAllMapped(RegExp(r'#(\d+)'), (m) => 'number ${m[1]}');

  // -- and — -> , (comma pause).
  result = result.replaceAll(RegExp(r'--|—'), ',');

  // Markdown headings, blockquotes and list markers at line starts.
  result = result.replaceAll(
    RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true),
    ' ',
  );
  result = result.replaceAll(RegExp(r'^[ \t]*>[ \t]*', multiLine: true), ' ');
  result = result.replaceAll(
    RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true),
    ' ',
  );

  // Markdown emphasis / strikethrough pairs.
  result = result.replaceAll(RegExp(r'\*\*'), ' ');
  result = result.replaceAll(RegExp(r'__'), ' ');
  result = result.replaceAll(RegExp(r'~~'), ' ');

  // Remove decorative symbols.
  result = result.replaceAll(RegExp(r'[*#\$%\^&{}\[\]@\\|/<>=+~`]+'), ' ');

  // Leftover underscore emphasis.
  result = result.replaceAll('_', ' ');

  // Fix duplicate punctuation (e.g. "ok!!!") keeping one for prosody.
  result = result.replaceAllMapped(RegExp(r'([.,!?])\1+'), (m) => m[1]!);

  // Remove space a removed symbol left in front of punctuation.
  result = result.replaceAllMapped(RegExp(r'\s+([.,!?;:])'), (m) => m[1]!);

  // Collapse whitespace.
  result = result.replaceAll(RegExp(r'\s+'), ' ');

  return result.trim();
}
