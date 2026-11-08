import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/chat_language.dart';
import '../../services/voice_service.dart';

/// Bottom sheet: read aloud on/off, female/male voice, choose any installed voice, pitch and speed.
Future<void> showVoiceSettings(BuildContext context,
    {required VoiceService voice,
    required ChatLanguage language,
    required bool speakOn,
    required ValueChanged<bool> onSpeakChanged}) async {
  final voices = await voice.voicesFor(language.ttsLocale);
  var chosen = await voice.chosenVoice(language.ttsLocale);
  var on = speakOn;
  if (!context.mounted) return;
  final sample = switch (language.code) {
    'ur' => 'السلام علیکم، میں آپ کا صحت کا مددگار ہوں۔',
    'roman_ur' => 'Assalam o alaikum, main aap ka sehat ka madadgar hoon.',
    _ => 'Hello, I am your health assistant.',
  };

  Future<void> pick(StateSetter setSheet, Map<String, String>? v) async {
    await voice.chooseVoice(language.ttsLocale, v);
    setSheet(() => chosen = v?['name']);
    await voice.speakNow(sample, language.ttsLocale);
  }

  Future<void> pickGender(StateSetter setSheet, bool female) async {
    final match = voices.where((v) => VoiceService.isFemale(v) == female).toList();
    if (match.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No ${female ? 'female' : 'male'} ${language.label} voice is installed on this device. '
                'Try changing the pitch below.')));
      }
      // Pitch makes the default voice sound higher or deeper.
      await voice.setTone(pitch: female ? 1.25 : 0.85);
      setSheet(() {});
      await voice.speakNow(sample, language.ttsLocale);
      return;
    }
    await pick(setSheet, match.first);
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Text('Voice', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Read replies aloud'),
                value: on,
                onChanged: (v) {
                  setSheet(() => on = v);
                  onSpeakChanged(v);
                },
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.face_3_outlined),
                    label: const Text('Female voice'),
                    onPressed: () => pickGender(setSheet, true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.face_outlined),
                    label: const Text('Male voice'),
                    onPressed: () => pickGender(setSheet, false),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text('Pitch', style: Theme.of(ctx).textTheme.labelLarge),
              Slider(
                value: voice.pitch,
                min: 0.6,
                max: 1.5,
                divisions: 9,
                label: voice.pitch.toStringAsFixed(1),
                onChanged: (v) => setSheet(() => voice.pitch = v),
                onChangeEnd: (v) async {
                  await voice.setTone(pitch: v);
                  await voice.speakNow(sample, language.ttsLocale);
                },
              ),
              Text('Speed', style: Theme.of(ctx).textTheme.labelLarge),
              Slider(
                value: voice.rate,
                min: 0.3,
                max: 0.8,
                divisions: 5,
                label: voice.rate.toStringAsFixed(1),
                onChanged: (v) => setSheet(() => voice.rate = v),
                onChangeEnd: (v) async {
                  await voice.setTone(rate: v);
                  await voice.speakNow(sample, language.ttsLocale);
                },
              ),
              const Divider(),
              Text('${language.label} voices on this device',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(chosen == null ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AppColors.accent),
                title: const Text('Default voice'),
                onTap: () => pick(setSheet, null),
              ),
              for (final v in voices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(chosen == v['name'] ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: AppColors.accent),
                  title: Text(v['name']!),
                  subtitle: Text([
                    v['locale']!,
                    if (VoiceService.isFemale(v) == true) 'female' else if (VoiceService.isFemale(v) == false) 'male',
                  ].join(' · ')),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => pick(setSheet, v),
                ),
              if (voices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No extra voices found. On a phone you can add voices in '
                      'Settings → Text-to-speech (e.g. Urdu in Google Speech Services).',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
