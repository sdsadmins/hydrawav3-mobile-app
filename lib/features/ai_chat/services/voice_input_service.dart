import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/utils/logger.dart';

final voiceInputServiceProvider = Provider<VoiceInputService>((ref) {
  return VoiceInputService();
});

/// Voice input service using speech_to_text.
/// Abstracted behind an interface for future on-device LLM migration.
abstract class VoiceInputPort {
  Future<bool> isAvailable();
  Future<void> startListening(void Function(String text) onResult);
  Future<void> stopListening();
  bool get isListening;
}

class VoiceInputService implements VoiceInputPort {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> isAvailable() async {
    if (!_initialized) {
      _initialized = await _speech.initialize(
        onError: (error) {
          appLogger.e('Speech error: ${error.errorMsg}');
          _listening = false;
        },
        onStatus: (status) {
          appLogger.d('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            _listening = false;
          }
        },
      );
    }
    return _initialized;
  }

  @override
  Future<void> startListening(void Function(String text) onResult) async {
    final available = await isAvailable();
    if (!available) {
      appLogger.w('Speech recognition not available');
      return;
    }

    _listening = true;
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          _listening = false;
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
    );
  }

  @override
  Future<void> stopListening() async {
    await _speech.stop();
    _listening = false;
  }

  void dispose() {
    _speech.cancel();
  }
}
