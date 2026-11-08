import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Reads replies aloud and turns the user's voice into text.
/// Every call is wrapped, so a device without a voice engine never crashes the chat.
class VoiceService {
  late final FlutterTts _tts = FlutterTts();
  late final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;

  /// Speak [text] in [locale] (e.g. "ur-PK"). Falls back to English if that voice is missing.
  Future<void> speak(String text, String locale) async {
    try {
      await _tts.stop();
      final available = await _tts.isLanguageAvailable(locale);
      await _tts.setLanguage(available == true ? locale : 'en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    } catch (_) {
      // No text-to-speech on this device: stay silent.
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Start listening. [onText] gets the words so far; [isFinal] is true at the end.
  /// Returns false if the microphone or speech recognition is not available.
  Future<bool> listen(String locale, void Function(String words, bool isFinal) onText,
      {void Function()? onDone}) async {
    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && onDone != null) onDone();
          },
          onError: (_) => onDone?.call(),
        );
      }
      if (!_speechReady) return false;
      await _speech.listen(
        localeId: locale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
        onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  void dispose() {
    stopSpeaking();
    stopListening();
  }
}
