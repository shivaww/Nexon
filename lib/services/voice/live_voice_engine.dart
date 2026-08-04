import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_kitten_tts/flutter_kitten_tts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum LiveVoiceState { idle, listening, thinking, speaking, error }

/// Hands-free speech recognition and reply playback.
///
/// KittenTTS is created only when it is first needed. If model setup or PCM
/// playback fails, the engine releases it and uses native flutter_tts instead.
class LiveVoiceEngine extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  final List<String> kittenVoices = const [
    'Bella', 'Jasper', 'Luna', 'Bruno', 'Rosie', 'Hugo', 'Kiki', 'Leo',
  ];

  FlutterTts? _flutterTts;
  KittenTTS? _kittenTts;
  AudioPlayer? _audioPlayer;
  bool _speechInitialized = false;
  bool _kittenReady = false;
  bool _kittenAttempted = false;
  bool _isPreparingTts = false;
  double _ttsDownloadProgress = 0;
  String _ttsStatus = '';
  String _kittenVoice = 'Jasper';
  String _activeTtsEngine = 'KittenTTS';
  bool _stopRequested = false;
  int _silentRestartCount = 0;

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
  bool get isPreparingTts => _isPreparingTts;
  double get ttsDownloadProgress => _ttsDownloadProgress;
  String get ttsStatus => _ttsStatus;
  String get activeTtsEngine => _activeTtsEngine;
  String get kittenVoice => _kittenVoice;

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

  void setKittenVoice(String voice) {
    if (!kittenVoices.contains(voice) || voice == _kittenVoice) return;
    _kittenVoice = voice;
    notifyListeners();
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
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') &&
              _state == LiveVoiceState.listening &&
              _recognizedText.isNotEmpty) {
            _setState(LiveVoiceState.thinking);
          }
        },
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

  Future<void> startListening({required ValueChanged<String> onFinalResult}) async {
    // Permission must be granted before speech_to_text is used.
    if (!await requestMicPermission()) return;
    if (!await initSpeech()) return;

    _silentRestartCount = 0;
    await stopTts();
    _stopRequested = false; // fresh listening session — do not drop the first reply
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
      onStatus: (status) {
        // Auto-restart after a brief silence so the mic stays live without an
        // infinite loop (capped at 3 silent restarts per listening session).
        if ((status == 'done' || status == 'notListening') &&
            _state == LiveVoiceState.listening &&
            _recognizedText.trim().isEmpty) {
          if (_silentRestartCount >= 3) return;
          _silentRestartCount++;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (_state == LiveVoiceState.listening) {
              _listen(onFinalResult: onFinalResult);
            }
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: false,
    );
  }

  Future<void> stopListening() => _speechToText.stop();

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
    final matches =
        RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9])|\n+').allMatches(currentText).toList();
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

  // ── KittenTTS ─────────────────────────────────────────────────────────────

  Future<bool> _ensureKittenTts() async {
    if (_kittenReady) return true;
    _kittenAttempted = true;
    _isPreparingTts = true;
    _ttsDownloadProgress = 0;
    _ttsStatus = 'Preparing high-quality voice…';
    notifyListeners();
    try {
      await _disposeNativeTts(); // don't keep both loaded
      final kitten = KittenTTS();
      await kitten.initialize(onProgress: (double progress, String status) {
        _ttsDownloadProgress = progress.clamp(0.0, 1.0);
        _ttsStatus = status;
        notifyListeners();
      });
      _kittenTts = kitten;
      _kittenReady = true;
      _activeTtsEngine = 'KittenTTS';
      debugPrint('LiveVoice active TTS engine: KittenTTS');
      return true;
    } catch (e) {
      await _disposeKittenTts();
      debugPrint('LiveVoice KittenTTS failed; using flutter_tts fallback: $e');
      return false;
    } finally {
      _isPreparingTts = false;
      _ttsStatus = '';
      notifyListeners();
    }
  }

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

    if (await _ensureKittenTts()) {
      try {
        final audio = await _kittenTts!.generate(sentence, voice: _kittenVoice, speed: 1.0);
        await _playKittenAudio(audio); // _finishSentence() invoked in its finally
        return;
      } catch (e) {
        debugPrint('LiveVoice KittenTTS generation/playback failed: $e');
        await _disposeKittenTts();
        _finishSentence(); // idempotent; no-op if _playKittenAudio finally already finished
        return;
      }
    }

    // Fallback: native flutter_tts (reached only when KittenTTS is not ready).
    try {
      await _speakWithNative(sentence);
    } catch (e) {
      debugPrint('LiveVoice native TTS fallback failed: $e');
      _errorMessage = 'Voice playback is unavailable.';
      _finishSentence();
      _setState(LiveVoiceState.error);
    }
  }

  Future<void> _speakWithNative(String sentence) async {
    await _disposeKittenTts(); // don't keep both loaded simultaneously
    final tts = _flutterTts ??= FlutterTts();
    _activeTtsEngine = 'Native TTS';
    debugPrint('LiveVoice active TTS engine: Native TTS');
    tts.setCompletionHandler(_finishSentence);
    tts.setCancelHandler(_finishSentence);
    tts.setErrorHandler((message) => _finishSentence());
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.48);
    await tts.setVolume(1.0);
    await tts.speak(sentence);
  }

  Future<void> _playKittenAudio(Float32List samples) async {
    if (samples.isEmpty) throw StateError('KittenTTS returned no audio samples');
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/kitten_${DateTime.now().millisecondsSinceEpoch}_${_sentenceQueue.length}.wav',
    );
    await file.writeAsBytes(_wavBytes(samples, sampleRate: 24000), flush: true);
    final player = _audioPlayer ??= AudioPlayer();
    try {
      await player.stop();
      await player.setFilePath(file.path);
      final completed = player.playerStateStream
          .firstWhere((state) => state.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 20));
      await player.play();
      await completed;
    } catch (e) {
      debugPrint('LiveVoice KittenTTS playback error: $e');
      rethrow;
    } finally {
      try {
        await file.delete();
      } catch (_) {
        // File already removed or inaccessible; safe to ignore.
      }
      _finishSentence();
    }
  }

  Uint8List _wavBytes(Float32List samples, {required int sampleRate}) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = samples.length * 2;
    final bytes = ByteData(44 + dataSize);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }
    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // 1 = linear PCM (was 3 = IEEE float)
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, byteRate, Endian.little);
    bytes.setUint16(32, blockAlign, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(44 + i * 2, (sample * 32767).toInt(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  void _finishSentence() {
    _isTtsSpeaking = false;
    final completer = _currentSentenceCompleter;
    // Only complete + advance once per sentence so a double finish (e.g. the
    // KittenTTS playback finally *and* the caller catch both firing) never
    // schedules the next sentence twice.
    if (completer == null || completer.isCompleted) return;
    completer.complete();
    unawaited(_playNextSentence());
  }

  Future<void> _disposeNativeTts() async {
    final tts = _flutterTts;
    _flutterTts = null;
    if (tts != null) await tts.stop();
  }

  Future<void> _disposeKittenTts() async {
    final kitten = _kittenTts;
    _kittenTts = null;
    _kittenReady = false;
    if (kitten != null) await kitten.dispose();
  }

  Future<void> interrupt() async {
    _stopRequested = true;
    _kittenAttempted = false;
    _kittenReady = false;
    _sentenceQueue.clear();
    await stopTts();
    await _speechToText.stop();
    _setState(LiveVoiceState.idle);
  }

  Future<void> stopTts() async {
    _stopRequested = true;
    _kittenAttempted = false;
    _kittenReady = false;
    _sentenceQueue.clear();
    _streamBuffer.clear();
    _isTtsSpeaking = false;
    await _audioPlayer?.stop();
    await _flutterTts?.stop();
    if (_currentSentenceCompleter != null && !_currentSentenceCompleter!.isCompleted) {
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
    _kittenTts?.dispose();
    _audioPlayer?.dispose();
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
      RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');

  // Bare http(s):// and www. URLs.
  result = result.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), ' ');
  result = result.replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ');

  // Currency: $50 / $1,000.00 -> "50 dollars" / "1,000.00 dollars".
  result = result.replaceAllMapped(
      RegExp(r'\$\s*(\d[\d,]*(?:\.\d+)?)'), (m) => '${m[1]} dollars');

  // Percent: 50% -> "50 percent".
  result = result.replaceAllMapped(
      RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*%'), (m) => '${m[1]} percent');

  // Markdown blockquotes, headings and list markers at line starts.
  result = result.replaceAll(RegExp(r'^[ \t]*>[ \t]*', multiLine: true), ' ');
  result = result.replaceAll(RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true), ' ');
  result = result.replaceAll(RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true), ' ');

  // Markdown emphasis / strikethrough pairs.
  result = result.replaceAll(RegExp(r'\*\*'), ' ');
  result = result.replaceAll(RegExp(r'__'), ' ');
  result = result.replaceAll(RegExp(r'~~'), ' ');

  // Symbols TTS would otherwise read out as words (after currency/percent).
  result = result.replaceAll(RegExp(r'[*#%^&{}\[\]@\\|/<>+=~`_\-]'), ' ');

  // Drop the space a removed symbol left in front of kept punctuation.
  result = result.replaceAll(RegExp(r'\s+(?=[,.!?;:)])'), '');

  // Fix duplicate punctuation (e.g. "ok!!!") while keeping one for prosody.
  result = result.replaceAllMapped(
      RegExp(r'([,.!?;:])\1+'), (m) => m[1]!);

  // Emoji and unicode pictographs.
  result = result.replaceAll(
      RegExp(
        r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
        r'\u{2190}-\u{21FF}\u{FE00}-\u{FE0F}\u{200D}\u{20E3}]',
        unicode: true,
      ),
      ' ');

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
      RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');

  // Bare http(s):// and www. URLs.
  result = result.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), ' ');
  result = result.replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ');

  // $number -> number dollars.
  result = result.replaceAllMapped(RegExp(r'\$(\d+)'), (m) => '${m[1]} dollars');

  // number% -> number percent.
  result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*%'), (m) => '${m[1]} percent');

  // number*number or number x number -> number times number.
  result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*[*xX]\s*(\d+)'), (m) => '${m[1]} times ${m[2]}');

  // number-number -> number to number.
  result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*-\s*(\d+)'), (m) => '${m[1]} to ${m[2]}');

  // number+number -> number plus number.
  result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*\+\s*(\d+)'), (m) => '${m[1]} plus ${m[2]}');

  // number=number -> number equals number.
  result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*=\s*(\d+)'), (m) => '${m[1]} equals ${m[2]}');

  // & -> and.
  result = result.replaceAll('&', ' and ');

  // @ -> at.
  result = result.replaceAll('@', ' at ');

  // #number -> number number.
  result = result.replaceAllMapped(RegExp(r'#(\d+)'), (m) => 'number ${m[1]}');

  // -- and — -> , (comma pause).
  result = result.replaceAll(RegExp(r'--|—'), ',');

  // Markdown headings, blockquotes and list markers at line starts.
  result = result.replaceAll(RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true), ' ');
  result = result.replaceAll(RegExp(r'^[ \t]*>[ \t]*', multiLine: true), ' ');
  result = result.replaceAll(RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true), ' ');

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
