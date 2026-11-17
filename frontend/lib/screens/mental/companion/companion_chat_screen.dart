import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/chat_language.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_client.dart';
import '../../../services/assistant_repository.dart';
import '../../../services/companion_repository.dart';
import '../../../services/voice_service.dart';
import 'companion_insights_screen.dart';

class _Msg {
  _Msg.user(this.text)
      : fromUser = true,
        crisis = false,
        tip = '',
        lines = const [],
        error = false;
  _Msg.bot(this.text, {this.crisis = false, this.tip = '', this.lines = const [], this.error = false})
      : fromUser = false;

  final String text;
  final bool fromUser;
  final bool crisis;
  final String tip;
  final List<({String name, String number})> lines;
  final bool error;
}

final _urdu = RegExp(r'[؀-ۿ]');

/// MindEase flow, step 3: a caring chat that remembers the user (long-term memory on the
/// backend), reads how they feel, and switches to crisis support when needed.
class CompanionChatScreen extends StatefulWidget {
  const CompanionChatScreen(
      {super.key, required this.repository, required this.language, this.mood, this.opener, this.chatId, this.voice});

  final CompanionRepository repository;
  final String language;
  final String? mood;

  /// Sent automatically as the first message (from the mood check-in).
  final String? opener;
  final String? chatId;
  final VoiceService? voice;

  @override
  State<CompanionChatScreen> createState() => _CompanionChatScreenState();
}

class _CompanionChatScreenState extends State<CompanionChatScreen> {
  late final VoiceService _voice = widget.voice ?? VoiceService();
  late final ChatLanguage _lang = ChatLanguage.byCode(widget.language);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String? _chatId;
  bool _busy = false;
  bool _speak = true;
  bool _listening = false;
  int _stage = 0;
  Timer? _stageTimer;
  bool _moodSent = false;

  static const _stages = {
    'en': ['Reading how you feel…', 'Thinking about what may help…', 'Writing a reply…'],
    'ur': ['آپ کے احساسات سمجھ رہا ہوں…', 'سوچ رہا ہوں کیا مدد کر سکتا ہے…', 'جواب لکھ رہا ہوں…'],
    'roman_ur': ['Aap ke ehsaasaat samajh raha hoon…', 'Soch raha hoon kya madad kar sakta hai…', 'Jawab likh raha hoon…'],
  };

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    if (widget.voice == null) {
      try {
        final api = context.read<AuthProvider>().repository.api;
        _voice.toDevanagari = AssistantRepository(api).speech;
        _voice.urduAudio = (text, lang) => api.postForBytes('/voice/tts', {'text': text, 'language': lang});
      } catch (_) {}
    }
    if (widget.chatId != null) {
      _load(widget.chatId!);
    } else if (widget.opener != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.opener));
    } else {
      _msgs.add(_Msg.bot(switch (_lang.code) {
        'ur' => 'السلام علیکم! میں MindEase ہوں۔ آج آپ کے دل میں کیا ہے؟ میں سن رہا ہوں۔',
        'roman_ur' => 'Assalam o alaikum! Main MindEase hoon. Aaj aap ke dil mein kya hai? Main sun raha hoon.',
        _ => "Hi, I'm MindEase. What's on your mind today? I'm here to listen.",
      }));
    }
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _voice.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(String id) async {
    setState(() => _busy = true);
    try {
      final c = await widget.repository.chat(id);
      if (!mounted) return;
      setState(() {
        _chatId = id;
        _moodSent = true;
        for (final t in c.turns) {
          _msgs.add(_Msg.user(t.user));
          _msgs.add(_Msg.bot(t.reply, crisis: t.crisis, tip: t.copingTip));
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _msgs.add(_Msg.bot(e.message, error: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _down();
    }
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    _voice.stopSpeaking();
    setState(() {
      _msgs.add(_Msg.user(text));
      _busy = true;
      _stage = 0;
    });
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (mounted && _stage < 2) setState(() => _stage++);
    });
    _down();
    try {
      final r = await widget.repository.send(
          message: text, language: _lang.code, chatId: _chatId, mood: _moodSent ? null : widget.mood);
      _moodSent = true;
      if (!mounted) return;
      setState(() {
        _chatId = r.chatId;
        _msgs.add(_Msg.bot(r.reply, crisis: r.crisis, tip: r.copingTip, lines: r.crisisLines));
      });
      _voice.remember(r.reply, r.speech);
      if (_speak) _voice.speakNow(r.reply, _lang.code);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_Msg.bot(e.message, error: true)));
      if (e.code == 'consent_required') context.push('/settings/consent');
    } catch (e) {
      if (mounted) setState(() => _msgs.add(_Msg.bot('Something went wrong. Please try again.', error: true)));
    } finally {
      _stageTimer?.cancel();
      if (mounted) setState(() => _busy = false);
      _down();
    }
  }

  Future<void> _mic() async {
    if (_listening) {
      await _voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    await _voice.stopSpeaking();
    final ok = await _voice.listen(_lang.speechLocale, (words, isFinal) {
      if (!mounted) return;
      _input.text = words;
      if (isFinal) {
        setState(() => _listening = false);
        if (words.trim().isNotEmpty) _send(words);
      }
    }, onDone: () {
      if (mounted) setState(() => _listening = false);
    });
    if (!mounted) return;
    if (ok) {
      setState(() => _listening = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice input is not available here. Please allow the microphone or type.')));
    }
  }

  Future<void> _showMemory() async {
    final api = widget.repository;
    final mem = await api.memory().catchError((_) => (summary: '', turns: 0));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('What MindEase remembers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(mem.summary.isEmpty
                ? 'Nothing summarised yet. After about 10 messages, older ones are summarised here so MindEase can '
                    'remember you without keeping every word.'
                : mem.summary),
            const SizedBox(height: 8),
            Text('${mem.turns} messages saved privately to your account.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.critical),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Forget everything'),
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: const Text('Forget everything?'),
                    content: const Text('All MindEase chats and memory will be deleted. This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (sure != true) return;
                await api.forgetMe();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() {
                    _msgs.clear();
                    _chatId = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MindEase memory deleted.')));
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showHistory() async {
    final chats = await widget.repository.chats().catchError((_) => <CompanionChatSummary>[]);
    if (!mounted) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: chats.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('No past chats yet.'))
            : ListView(shrinkWrap: true, children: [
                for (final c in chats)
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline, color: AppColors.mind),
                    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([if (c.mood != null) c.mood!, ChatLanguage.byCode(c.language).label].join(' · ')),
                    onTap: () => Navigator.pop(ctx, c.id),
                  ),
              ]),
      ),
    );
    if (id == null || !mounted) return;
    final c = chats.firstWhere((x) => x.id == id);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CompanionChatScreen(repository: widget.repository, language: c.language, chatId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _input.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MindEase'),
        actions: [
          IconButton(
            tooltip: _speak ? 'Mute replies' : 'Read replies aloud',
            icon: Icon(_speak ? Icons.volume_up_outlined : Icons.volume_off_outlined),
            onPressed: () {
              setState(() => _speak = !_speak);
              if (!_speak) _voice.stopSpeaking();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'memory') _showMemory();
              if (v == 'history') _showHistory();
              if (v == 'insights') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CompanionInsightsScreen(repository: widget.repository)));
              }
              if (v == 'crisis') context.push('/feature/25');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'history', child: Text('Past chats')),
              PopupMenuItem(value: 'insights', child: Text('My wellbeing insights')),
              PopupMenuItem(value: 'memory', child: Text('What MindEase remembers')),
              PopupMenuItem(value: 'crisis', child: Text('Get help now')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final m in _msgs) _bubble(m),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mind)),
                    const SizedBox(width: 10),
                    Text((_stages[_lang.code] ?? _stages['en']!)[_stage],
                        style: const TextStyle(color: AppColors.textMuted)),
                  ]),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('MindEase is a support companion, not a therapist. In danger? Call 1122.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
                  child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _listening ? _lang.listening : _lang.hint,
                      filled: true,
                      fillColor: _listening ? AppColors.mindTint : Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: hasText ? 'Send' : (_listening ? 'Stop' : 'Voice message'),
                style: IconButton.styleFrom(
                    backgroundColor: _listening ? AppColors.critical : AppColors.mind, minimumSize: const Size(48, 48)),
                onPressed: _busy ? null : (hasText ? _send : _mic),
                icon: Icon(hasText ? Icons.send_rounded : (_listening ? Icons.stop_rounded : Icons.mic_none),
                    color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(_Msg m) {
    final rtl = _urdu.hasMatch(m.text);
    final bg = m.fromUser ? AppColors.mind : (m.crisis || m.error ? AppColors.criticalTint : Colors.white);
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Column(crossAxisAlignment: m.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: m.fromUser ? null : Border.all(color: m.crisis ? AppColors.critical : const Color(0xFFE2E8EC)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flexible(
                child: Text(m.text,
                    textDirection: rtl ? TextDirection.rtl : null,
                    style: TextStyle(
                        color: m.fromUser ? Colors.white : AppColors.text, height: rtl ? 1.7 : 1.45, fontSize: 15)),
              ),
              if (!m.fromUser && !m.error)
                InkWell(
                  onTap: () => _voice.speakNow(m.text, _lang.code),
                  child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.volume_up_outlined, size: 18, color: AppColors.textMuted)),
                ),
            ]),
          ),
          if (m.tip.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.mindTint, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.mind),
                const SizedBox(width: 6),
                Flexible(child: Text(m.tip, textDirection: _urdu.hasMatch(m.tip) ? TextDirection.rtl : null)),
              ]),
            ),
          if (m.lines.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.critical)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('You can talk to someone now',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.critical)),
                for (final l in m.lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      const Icon(Icons.call, size: 16, color: AppColors.critical),
                      const SizedBox(width: 8),
                      SelectableText(l.number, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Flexible(child: Text(l.name, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                    ]),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
