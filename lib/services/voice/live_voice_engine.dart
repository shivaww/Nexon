import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum LiveVoiceState {
  idle,
  listening,
  thinking,
  speaking,
  error,
}

class LiveVoiceEngine extends ChangeNotifier {
  LiveVoiceEngine() {
    _initTts();
  }

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

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

  double _soundLevel = 0.0;
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
  Future<bool> checkMicPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> initSpeech() async {
    try {
      _isSpeechAvailable = await _speechToText.initialize(
        onError: (val) {
          _errorMessage = 'Mic/Speech error: ${val.errorMsg}';
          _setState(LiveVoiceState.error);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (_state == LiveVoiceState.listening && _recognizedText.isNotEmpty) {
              _setState(LiveVoiceState.thinking);
            }
          }
        },
      );
      if (!_isSpeechAvailable) {
        _errorMessage = 'Microphone permission denied or speech recognition unavailable on device.';
        _setState(LiveVoiceState.error);
      }
      return _isSpeechAvailable;
    } catch (e) {
      _errorMessage = 'Speech init failed: $e';
      _setState(LiveVoiceState.error);
      return false;
    }
  }

  void _initTts() {
    _flutterTts.setCompletionHandler(() {
      _isTtsSpeaking = false;
      if (_currentSentenceCompleter != null && !_currentSentenceCompleter!.isCompleted) {
        _currentSentenceCompleter!.complete();
      }
      _playNextSentence();
    });

    _flutterTts.setErrorHandler((msg) {
      _isTtsSpeaking = false;
      if (_currentSentenceCompleter != null && !_currentSentenceCompleter!.isCompleted) {
        _currentSentenceCompleter!.complete();
      }
      _playNextSentence();
    });
  }

  Future<void> startListening({required ValueChanged<String> onFinalResult}) async {
    if (!_isSpeechAvailable) {
      final ok = await initSpeech();
      if (!ok) return;
    }

    await stopTts();
    _recognizedText = '';
    _errorMessage = '';
    _setState(LiveVoiceState.listening);

    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        _recognizedText = result.recognizedWords;
        notifyListeners();
        if (result.finalResult && _recognizedText.trim().isNotEmpty) {
          _setState(LiveVoiceState.thinking);
          onFinalResult(_recognizedText.trim());
        }
      },
      onSoundLevelChange: (level) {
        _soundLevel = level.clamp(0.0, 10.0) / 10.0;
        notifyListeners();
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
    );
  }

  Future<void> stopListening() async {
    await _speechToText.stop();
  }

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
    final RegExp sentenceEnd = RegExp(r'([.!?\n]+)');
    final matches = sentenceEnd.allMatches(currentText).toList();

    if (matches.isNotEmpty) {
      int lastCut = 0;
      for (final m in matches) {
        final cutIndex = m.end;
        final sentence = currentText.substring(lastCut, cutIndex).trim();
        if (sentence.isNotEmpty) {
          _enqueueSentence(sentence);
        }
        lastCut = cutIndex;
      }
      _streamBuffer = StringBuffer(currentText.substring(lastCut));
    }
  }

  void endStreamResponse() {
    final remaining = _streamBuffer.toString().trim();
    if (remaining.isNotEmpty) {
      _enqueueSentence(remaining);
    }
    _streamBuffer.clear();
  }

  void _enqueueSentence(String rawSentence) {
    final clean = stripSsml(rawSentence);
    if (clean.trim().isEmpty) return;
    _sentenceQueue.add(clean.trim());

    if (!_isTtsSpeaking) {
      _playNextSentence();
    }
  }

  Future<void> _playNextSentence() async {
    if (_sentenceQueue.isEmpty) {
      _isTtsSpeaking = false;
      if (_state == LiveVoiceState.speaking) {
        _setState(LiveVoiceState.idle);
      }
      return;
    }

    _isTtsSpeaking = true;
    _setState(LiveVoiceState.speaking);
    final sentence = _sentenceQueue.removeAt(0);

    _currentSentenceCompleter = Completer<void>();
    await _flutterTts.speak(sentence);
  }

  /// Instantly stops TTS playback, clears speech queues, and triggers barge-in.
  Future<void> interrupt() async {
    await stopTts();
    await _speechToText.stop();
    _setState(LiveVoiceState.idle);
  }

  Future<void> stopTts() async {
    _sentenceQueue.clear();
    _streamBuffer.clear();
    _isTtsSpeaking = false;
    await _flutterTts.stop();
  }

  /// Strip or gracefully degrade SSML tags for native OS TTS compatibility.
  String stripSsml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _flutterTts.stop();
    super.dispose();
  }
}
