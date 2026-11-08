import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

final _urduScript = RegExp(r'[؀-ۿ]');
final _devanagariScript = RegExp(r'[ऀ-ॿ]');

/// Reads replies aloud and turns the user's voice into text.
/// Every call is wrapped, so a device without a voice engine never crashes the chat.
///
/// Urdu / Roman Urdu: an English voice reads Roman Urdu badly, and most PCs and browsers
/// have no Urdu voice. Spoken Urdu and Hindi sound almost the same, so we:
///  1. use an Urdu voice for Urdu-script text when the device has one (many phones do);
///  2. otherwise write the same Urdu words in Devanagari (backend AI, cached) and use a
///     Hindi voice (e.g. Chrome's "Google हिन्दी");
///  3. otherwise fall back to an English (India) voice.
/// The screen always shows the original Urdu / Roman Urdu text.
class VoiceService {
  late final FlutterTts _tts = FlutterTts();
  late final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  Future<void> _queue = Future.value();
  int _generation = 0; // bumped on stop, so queued messages are dropped

  /// Turns Urdu / Roman Urdu text into Devanagari for a Hindi voice (set by the chat screen).
  Future<String?> Function(String text)? toDevanagari;
  final Map<String, String> _devanagari = {};

  /// Chosen voice per group ("en" or "ur"), and voice settings. Saved on the device.
  final Map<String, Map<String, String>> _voices = {};
  double pitch = 1.0;
  double rate = 0.5;
  bool _prefsLoaded = false;
  List<Map<String, String>>? _installed;

  /// Remember a ready-made Devanagari version (the chat reply already includes one).
  void remember(String text, String devanagari) {
    if (devanagari.trim().isNotEmpty) _devanagari[text] = devanagari;
  }

  static String _group(String languageCode) => languageCode == 'en' ? 'en' : 'ur';
  static String _prefix(String locale) => locale.split(RegExp('[-_]')).first.toLowerCase();

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      for (final g in ['en', 'ur']) {
        final name = p.getString('tts_voice_$g');
        final locale = p.getString('tts_locale_$g');
        if (name != null && locale != null) _voices[g] = {'name': name, 'locale': locale};
      }
      pitch = p.getDouble('tts_pitch') ?? 1.0;
      rate = p.getDouble('tts_rate') ?? 0.5;
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _allVoices() async {
    if (_installed != null && _installed!.isNotEmpty) return _installed!;
    try {
      final all = await _tts.getVoices.timeout(const Duration(seconds: 3));
      _installed = [
        for (final v in (all as List? ?? const []))
          if (v is Map && v['name'] != null && v['locale'] != null)
            {
              'name': '${v['name']}',
              'locale': '${v['locale']}',
              if (v['gender'] != null) 'gender': '${v['gender']}',
            }
      ]..sort((a, b) => a['name']!.compareTo(b['name']!));
    } catch (_) {
      _installed = [];
    }
    return _installed!;
  }

  /// Voices that can be used for this chat language (Urdu chats: Urdu and Hindi voices).
  Future<List<Map<String, String>>> voicesFor(String languageCode) async {
    await _loadPrefs();
    final want = _group(languageCode) == 'en' ? {'en'} : {'ur', 'hi'};
    return [for (final v in await _allVoices()) if (want.contains(_prefix(v['locale']!))) v];
  }

  Future<String?> chosenVoice(String languageCode) async {
    await _loadPrefs();
    return _voices[_group(languageCode)]?['name'];
  }

  Future<void> chooseVoice(String languageCode, Map<String, String>? voice) async {
    final g = _group(languageCode);
    if (voice == null) {
      _voices.remove(g);
    } else {
      _voices[g] = {'name': voice['name']!, 'locale': voice['locale']!};
    }
    try {
      final p = await SharedPreferences.getInstance();
      if (voice == null) {
        await p.remove('tts_voice_$g');
        await p.remove('tts_locale_$g');
      } else {
        await p.setString('tts_voice_$g', voice['name']!);
        await p.setString('tts_locale_$g', voice['locale']!);
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

  Future<String?> _toDevanagari(String text) async {
    if (_devanagariScript.hasMatch(text)) return text;
    final cached = _devanagari[text];
    if (cached != null) return cached;
    final convert = toDevanagari;
    if (convert == null) return null;
    try {
      final d = await convert(text).timeout(const Duration(seconds: 10));
      if (d != null && d.trim().isNotEmpty) _devanagari[text] = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// Decide what to read and with which voice.
  Future<(String, Map<String, String>?, String)> _plan(String text, String languageCode) async {
    if (_group(languageCode) == 'en') return (text, _voices['en'], 'en-US');
    final voices = await _allVoices();
    final chosen = _voices['ur'];
    Map<String, String>? firstOf(String p) {
      for (final v in voices) {
        if (_prefix(v['locale']!) == p) return v;
      }
      return null;
    }

    final chosenIs = chosen == null ? null : _prefix(chosen['locale']!);
    final urVoice = chosenIs == 'ur' ? chosen : firstOf('ur');
    final hiVoice = chosenIs == 'hi' ? chosen : firstOf('hi');
    final isUrduScript = _urduScript.hasMatch(text);

    if (isUrduScript && urVoice != null && chosenIs != 'hi') return (text, urVoice, 'ur-PK');
    if (hiVoice != null) {
      final d = await _toDevanagari(text);
      if (d != null) return (d, hiVoice, 'hi-IN');
    }
    if (isUrduScript) return (text, urVoice, 'ur-PK');
    return (text, null, 'en-IN');
  }

  /// Speak [text] for a chat in [languageCode] ("en" / "ur" / "roman_ur"),
  /// after anything already being read.
  ///
  /// We wait for each sentence ourselves (with a time limit) instead of trusting the engine:
  /// in Chrome the "finished" event is sometimes never sent, which used to block all speech.
  Future<void> speak(String text, String languageCode) {
    final gen = _generation;
    _queue = _queue.then((_) async {
      if (gen != _generation) return;
      try {
        await _loadPrefs();
        final (say, voice, locale) = await _plan(text, languageCode);
        if (gen != _generation) return;
        await _prepare(voice, locale);
        for (final part in _sentences(say)) {
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

  Future<void> _prepare(Map<String, String>? voice, String locale) async {
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
    if (voice != null) {
      await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!}).timeout(const Duration(seconds: 2));
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
        .split(RegExp(r'(?<=[.!?।۔؟])\s+|\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? [text] : parts;
  }

  /// Stop now and read [text] instead (the speaker button on a message).
  Future<void> speakNow(String text, String languageCode) async {
    await stopSpeaking();
    // Chrome sometimes drops speech started right after a stop; wait a moment.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await speak(text, languageCode);
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
