import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Reads replies aloud and turns the user's voice into text.
/// Every call is wrapped, so a device without a voice engine never crashes the chat.
class VoiceService {
  late final FlutterTts _tts = FlutterTts();
  late final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  Future<void> _queue = Future.value();
  int _generation = 0; // bumped on stop, so queued messages are dropped

  /// Chosen voice per language prefix ("en" / "ur"), and voice settings. Saved on the device.
  final Map<String, Map<String, String>> _voices = {};
  double pitch = 1.0;
  double rate = 0.5;
  bool _prefsLoaded = false;

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      for (final lang in ['en', 'ur']) {
        final name = p.getString('tts_voice_$lang');
        final locale = p.getString('tts_locale_$lang');
        if (name != null && locale != null) _voices[lang] = {'name': name, 'locale': locale};
      }
      pitch = p.getDouble('tts_pitch') ?? 1.0;
      rate = p.getDouble('tts_rate') ?? 0.5;
    } catch (_) {}
  }

  static String _prefix(String locale) => locale.split(RegExp('[-_]')).first.toLowerCase();

  /// Voices installed for this language (e.g. all English voices for "en-IN").
  Future<List<Map<String, String>>> voicesFor(String locale) async {
    await _loadPrefs();
    try {
      final all = await _tts.getVoices.timeout(const Duration(seconds: 3));
      final want = _prefix(locale);
      final list = <Map<String, String>>[
        for (final v in (all as List? ?? const []))
          if (v is Map && v['name'] != null && v['locale'] != null && _prefix('${v['locale']}') == want)
            {
              'name': '${v['name']}',
              'locale': '${v['locale']}',
              if (v['gender'] != null) 'gender': '${v['gender']}',
            }
      ];
      list.sort((a, b) => a['name']!.compareTo(b['name']!));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// The saved voice name for this language, or null for the default voice.
  Future<String?> chosenVoice(String locale) async {
    await _loadPrefs();
    return _voices[_prefix(locale)]?['name'];
  }

  Future<void> chooseVoice(String locale, Map<String, String>? voice) async {
    final lang = _prefix(locale);
    if (voice == null) {
      _voices.remove(lang);
    } else {
      _voices[lang] = {'name': voice['name']!, 'locale': voice['locale']!};
    }
    try {
      final p = await SharedPreferences.getInstance();
      if (voice == null) {
        await p.remove('tts_voice_$lang');
        await p.remove('tts_locale_$lang');
      } else {
        await p.setString('tts_voice_$lang', voice['name']!);
        await p.setString('tts_locale_$lang', voice['locale']!);
      }
    } catch (_) {}
  }

  Future<void> setTone({double? pitch, double? rate}) async {
    if (pitch != null) this.pitch = pitch;
    if (rate != null) this.rate = rate;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('tts_pitch', this.pitch);
      await p.setDouble('tts_rate', this.rate);
    } catch (_) {}
  }

  /// Best guess whether a voice is female, from its gender field or its name.
  static bool? isFemale(Map<String, String> v) {
    final g = v['gender']?.toLowerCase();
    if (g != null && g.isNotEmpty) return g.startsWith('f');
    final n = v['name']!.toLowerCase();
    const female = ['female', 'zira', 'aria', 'jenny', 'hazel', 'susan', 'heera', 'uzma', 'samantha', 'karen',
        'moira', 'tessa', 'veena', 'neerja', 'swara', 'emma', 'libby', 'sonia', 'clara', 'natasha', 'catherine', 'linda'];
    const male = ['male', 'david', 'mark', 'george', 'ravi', 'asad', 'guy', 'ryan', 'prabhat', 'daniel', 'alex',
        'james', 'richard', 'sean', 'salman'];
    if (female.any(n.contains)) return true;
    if (male.any((m) => n.contains(m) && !n.contains('female'))) return false;
    return null;
  }

  /// Speak [text] in [locale] (e.g. "ur-PK") after anything already being read.
  /// Falls back to English if that voice is missing.
  ///
  /// We wait for each sentence ourselves (with a time limit) instead of trusting the engine:
  /// in Chrome the "finished" event is sometimes never sent (after stop, or for long text),
  /// which used to block all later speech, including the speaker button.
  Future<void> speak(String text, String locale) {
    final gen = _generation;
    _queue = _queue.then((_) async {
      if (gen != _generation) return;
      try {
        await _prepare(locale);
        for (final part in _sentences(text)) {
          if (gen != _generation) return;
          await _speakOne(part);
        }
      } catch (_) {
        // No text-to-speech on this device: stay silent.
      }
    });
    return _queue;
  }

  bool _handlersSet = false;
  Completer<void>? _current;

  Future<void> _prepare(String locale) async {
    await _loadPrefs();
    if (!_handlersSet) {
      _handlersSet = true;
      void done() {
        final c = _current;
        if (c != null && !c.isCompleted) c.complete();
      }

      _tts.setCompletionHandler(done);
      _tts.setCancelHandler(done);
      _tts.setErrorHandler((_) => done());
      await _tts.awaitSpeakCompletion(false);
    }
    final voice = _voices[_prefix(locale)];
    if (voice != null) {
      await _tts.setVoice(voice).timeout(const Duration(seconds: 2));
    } else {
      final available =
          await _tts.isLanguageAvailable(locale).timeout(const Duration(seconds: 2), onTimeout: () => false);
      await _tts.setLanguage(available == true ? locale : 'en-US').timeout(const Duration(seconds: 2));
    }
    await _tts.setPitch(pitch);
    await _tts.setSpeechRate(rate);
  }

  Future<void> _speakOne(String part) async {
    final c = Completer<void>();
    _current = c;
    await _tts.speak(part);
    // About 1 second per 12 characters at normal speed, plus a margin.
    final limit = Duration(milliseconds: 3000 + (part.length * 90 / (rate / 0.5)).round());
    await c.future.timeout(limit, onTimeout: () {});
  }

  /// Short pieces read more reliably than one long block (Chrome cuts long text off).
  static List<String> _sentences(String text) {
    final parts = text
        .split(RegExp(r'(?<=[.!?۔؟])\s+|\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? [text] : parts;
  }

  /// Stop now and read [text] instead (the speaker button on a message).
  Future<void> speakNow(String text, String locale) async {
    await stopSpeaking();
    // Chrome sometimes drops speech started right after a stop; wait a moment.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await speak(text, locale);
  }

  Future<void> stopSpeaking() async {
    _generation++;
    final c = _current;
    if (c != null && !c.isCompleted) c.complete();
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
