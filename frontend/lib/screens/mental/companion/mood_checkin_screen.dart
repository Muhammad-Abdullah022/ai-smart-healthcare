import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/chat_language.dart';
import '../../../models/mood_checkin.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_client.dart';
import '../../../services/companion_repository.dart';
import '../../../services/mental_repository.dart';
import 'companion_chat_screen.dart';
import 'companion_insights_screen.dart';

/// MindEase flow, step 1 and 2: mood check-in, then an affirmation with small tips,
/// then "Talk about it" opens the companion chat (step 3).
class MoodCheckInScreen extends StatefulWidget {
  const MoodCheckInScreen({super.key});

  @override
  State<MoodCheckInScreen> createState() => _MoodCheckInScreenState();
}

class _MoodCheckInScreenState extends State<MoodCheckInScreen> {
  String _lang = 'en';
  CheckInMood? _mood;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final l = p.getString('companion_language');
      if (l != null && mounted) setState(() => _lang = l);
    }).catchError((_) {});
  }

  void _setLang(String l) {
    setState(() => _lang = l);
    SharedPreferences.getInstance().then((p) => p.setString('companion_language', l)).catchError((_) => true);
  }

  Future<void> _pick(CheckInMood m) async {
    setState(() => _saving = true);
    try {
      await MentalRepository(context.read<AuthProvider>().repository.api).saveMood(m.score, 'Check-in: ${m.label['en']}');
      if (mounted) setState(() => _mood = m);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      if (e.code == 'consent_required') context.push('/settings/consent');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openChat({CheckInMood? mood}) {
    final api = context.read<AuthProvider>().repository.api;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CompanionChatScreen(
        repository: CompanionRepository(api),
        language: _lang,
        mood: mood?.label['en'],
        opener: mood == null ? null : mood.t(mood.opener, _lang),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().repository.api;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MindEase'),
        actions: [
          IconButton(
            tooltip: 'My wellbeing insights',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CompanionInsightsScreen(repository: CompanionRepository(api)))),
          ),
          IconButton(
            tooltip: 'Chat without check-in',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => _openChat(),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _mood == null ? _grid() : _affirmation(_mood!),
      ),
    );
  }

  Widget _languageChips() => Wrap(spacing: 8, children: [
        for (final l in chatLanguages)
          ChoiceChip(
            label: Text(l.label),
            selected: _lang == l.code,
            onSelected: (_) => _setLang(l.code),
            selectedColor: AppColors.mindTint,
          ),
      ]);

  Widget _grid() {
    final title = switch (_lang) {
      'ur' => 'آپ اس وقت کیسا محسوس کر رہے ہیں؟',
      'roman_ur' => 'Aap is waqt kaisa mehsoos kar rahe hain?',
      _ => 'How are you feeling right now?',
    };
    return ListView(
      key: const ValueKey('grid'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _languageChips(),
        const SizedBox(height: 16),
        Text(title,
            textDirection: _lang == 'ur' ? TextDirection.rtl : null,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
        const SizedBox(height: 4),
        const Text('Choose the mood closest to this moment. It is saved to your mood tracker.',
            style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final m in checkInMoods)
              Material(
                color: m.color.withAlpha(22),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _saving ? null : () => _pick(m),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(m.emoji, style: const TextStyle(fontSize: 34)),
                    const SizedBox(height: 6),
                    Text(m.t(m.label, _lang),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: m.color)),
                  ]),
                ),
              ),
          ],
        ),
        if (_saving) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
      ],
    );
  }

  Widget _affirmation(CheckInMood m) {
    final rtl = _lang == 'ur';
    final talk = switch (_lang) { 'ur' => 'اس بارے میں بات کریں', 'roman_ur' => 'Is baare mein baat karein', _ => 'Talk about it' };
    return ListView(
      key: const ValueKey('affirmation'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Change mood'),
            onPressed: () => setState(() => _mood = null),
          ),
        ),
        Center(child: Text(m.emoji, style: const TextStyle(fontSize: 56))),
        const SizedBox(height: 8),
        Center(
          child: Text(m.t(m.label, _lang),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: m.color)),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: m.color.withAlpha(22), borderRadius: BorderRadius.circular(20)),
          child: Text(m.t(m.affirmation, _lang),
              textAlign: TextAlign.center,
              textDirection: rtl ? TextDirection.rtl : null,
              style: TextStyle(fontSize: 18, height: 1.6, color: AppColors.primary, fontStyle: rtl ? null : FontStyle.italic)),
        ),
        const SizedBox(height: 18),
        Text(switch (_lang) { 'ur' => 'ابھی کے لیے چھوٹے قدم', 'roman_ur' => 'Abhi ke liye chhote qadam', _ => 'Small steps for right now' },
            textDirection: rtl ? TextDirection.rtl : null,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        for (final tip in m.tips[_lang] ?? m.tips['en']!)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(textDirection: rtl ? TextDirection.rtl : null, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.circle, size: 8, color: m.color),
              const SizedBox(width: 10),
              Expanded(child: Text(tip, textDirection: rtl ? TextDirection.rtl : null, style: const TextStyle(height: 1.4))),
            ]),
          ),
        const SizedBox(height: 22),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.mind, minimumSize: const Size.fromHeight(50)),
          icon: const Icon(Icons.forum_outlined),
          label: Text(talk),
          onPressed: () => _openChat(mood: m),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          icon: const Icon(Icons.air),
          label: const Text('Guided breathing'),
          onPressed: () => context.push('/feature/22'),
        ),
      ],
    );
  }
}
