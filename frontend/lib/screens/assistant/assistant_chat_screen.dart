import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/assessment.dart';
import '../../models/chat_language.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../../services/assistant_repository.dart';
import '../../services/report_repository.dart';
import '../../services/voice_service.dart';
import '../reports/report_compare_screen.dart';
import '../reports/report_widgets.dart';
import '../reports/reports_screen.dart';
import '../symptoms/symptom_checker_screen.dart';
import '../symptoms/symptom_history_screen.dart';
import 'chat_history_screen.dart';
import 'voice_settings_sheet.dart';

/// One item in the chat list.
class _Item {
  _Item.user(this.text)
      : fromUser = true,
        emergency = false,
        isError = false,
        report = null,
        kind = _Kind.text;
  _Item.bot(this.text, {this.emergency = false, this.isError = false})
      : fromUser = false,
        report = null,
        kind = _Kind.text;
  _Item.languagePicker()
      : text = '',
        fromUser = false,
        emergency = false,
        isError = false,
        report = null,
        kind = _Kind.languages;
  _Item.result(Assessment this.assessment)
      : text = '',
        fromUser = false,
        emergency = false,
        isError = false,
        report = null,
        kind = _Kind.result;
  _Item.report(MedicalReport this.report)
      : text = '',
        fromUser = false,
        emergency = false,
        isError = false,
        kind = _Kind.report;

  final String text;
  final bool fromUser;
  final bool emergency;
  final bool isError;
  final MedicalReport? report;
  Assessment? assessment;
  final _Kind kind;
}

enum _Kind { text, languages, result, report }

const _askLanguage = 'Which language would you like to talk in?\n'
    'آپ کس زبان میں بات کرنا چاہیں گے؟\n'
    'Aap kis zaban mein baat karna chahein ge?';

final _urduScript = RegExp(r'[؀-ۿ]');

/// AI Health Assistant (features 1–5, 8, 9, 13 in one chat): ask any health question by text
/// or voice, in English, Urdu or Roman Urdu; replies can be read aloud. When the user describes
/// symptoms, the symptom check runs right here (follow-up questions → triage, possible causes,
/// doctor and tests). Reports can be uploaded and compared. Chats are saved.
/// The AI gives information only — no diagnosis, no medicines.
class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({super.key, this.chatId, this.repository, this.reports, this.assessments, this.voice});

  /// Open a saved chat.
  final String? chatId;
  final AssistantRepository? repository;
  final ReportRepository? reports;
  final AssessmentRepository? assessments;
  final VoiceService? voice;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  late final ApiClient? _api =
      widget.repository == null || widget.reports == null || widget.assessments == null
          ? context.read<AuthProvider>().repository.api
          : null;
  late final AssistantRepository _repo = widget.repository ?? AssistantRepository(_api!);
  late final ReportRepository _reports = widget.reports ?? ReportRepository(_api!);
  late final AssessmentRepository _checks = widget.assessments ?? AssessmentRepository(_api!);
  late final VoiceService _voice = widget.voice ?? VoiceService();

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Item> _items = [];

  ChatLanguage? _lang;
  String? _chatId;
  bool _busy = false;
  String _busyText = 'Thinking…';
  bool _listening = false;
  bool _speak = true;
  bool _loading = false;

  // Symptom check inside the chat.
  bool _inCheck = false;
  String? _symptoms;
  final List<Map<String, String>> _answers = [];
  final List<String> _pending = [];
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _voice.toDevanagari = _repo.speech;
    if (widget.chatId != null) {
      _loadChat(widget.chatId!);
    } else {
      _items.addAll([_Item.bot(_askLanguage), _Item.languagePicker()]);
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChat(String id) async {
    setState(() => _loading = true);
    try {
      final c = await _repo.chat(id);
      if (!mounted) return;
      setState(() {
        _chatId = c.id;
        _lang = ChatLanguage.byCode(c.language);
        _items.addAll(c.messages.map((m) => m.fromUser ? _Item.user(m.text) : _Item.bot(m.text, emergency: m.emergency)));
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _items.add(_Item.bot(e.message, isError: true)));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// Read a new bot message aloud. By default it interrupts whatever is still being read,
  /// so the voice always follows the chat; [append] reads it after the current one
  /// (used when two messages belong together, e.g. "a few questions:" + the first question).
  void _say(String text, {bool append = false}) {
    if (!_speak || _lang == null || text.isEmpty) return;
    if (append) {
      _voice.speak(text, _lang!.code);
    } else {
      _voice.speakNow(text, _lang!.code);
    }
  }

  void _chooseLanguage(ChatLanguage l) {
    setState(() {
      _lang = l;
      _items.removeWhere((i) => i.kind == _Kind.languages);
      _items.add(_Item.user(l.label));
      _items.add(_Item.bot(l.greeting));
    });
    _say(l.greeting);
    _scrollDown();
  }

  Future<void> _send([String? spoken]) async {
    final text = (spoken ?? _input.text).trim();
    if (text.isEmpty || _busy || _lang == null) return;
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_input.text.trim().isEmpty) _input.clear();
    });
    setState(() => _items.add(_Item.user(text)));
    _scrollDown();
    // The user has moved on: stop reading the previous reply.
    _voice.stopSpeaking();

    // Inside a symptom check: this message is the symptoms, or an answer to a question.
    if (_inCheck) {
      if (_symptoms == null) {
        _symptoms = text;
        _log([ChatMessage(fromUser: true, text: text)]);
        await _runCheck();
        return;
      }
      if (_pending.isNotEmpty) {
        _answers.add({'question': _pending.removeAt(0), 'answer': text});
        _log([ChatMessage(fromUser: true, text: text)]);
        if (_pending.isNotEmpty) {
          _botSays(_pending.first, logIt: true);
        } else {
          await _runCheck();
        }
        return;
      }
    }

    setState(() {
      _busy = true;
      _busyText = 'Thinking…';
    });
    try {
      final r = await _repo.send(message: text, language: _lang!.code, chatId: _chatId);
      if (!mounted) return;
      setState(() {
        _chatId = r.chatId;
        _items.add(_Item.bot(r.message.text, emergency: r.message.emergency));
      });
      _voice.remember(r.message.text, r.speech);
      _say(r.message.text);
      if (r.suggestSymptomCheck && !r.message.emergency) {
        // The user described symptoms: check them step by step, right here.
        _startCheck(symptoms: text);
        _busy = false;
        await _runCheck();
        return;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _items.add(_Item.bot('${e.message} You can send it again.', isError: true)));
    } catch (e) {
      if (mounted) setState(() => _items.add(_Item.bot('Something went wrong ($e). Please try again.', isError: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _botSays(String text, {bool logIt = false, bool append = false}) {
    setState(() => _items.add(_Item.bot(text)));
    _say(text, append: append);
    if (logIt) _log([ChatMessage(fromUser: false, text: text)]);
    _scrollDown();
  }

  /// Keep symptom-check messages in the saved chat too (best effort).
  Future<void> _log(List<ChatMessage> msgs) {
    // One at a time, so the first call's new chat id is used by the next.
    return _logQueue = _logQueue.then((_) async {
      try {
        _chatId = await _repo.log(chatId: _chatId, language: _lang?.code ?? 'en', messages: msgs);
      } catch (_) {}
    });
  }

  Future<void> _logQueue = Future.value();

  void _startCheck({String? symptoms}) {
    _inCheck = true;
    _symptoms = symptoms;
    _answers.clear();
    _pending.clear();
    _asked = false;
  }

  Future<void> _runCheck() async {
    setState(() {
      _busy = true;
      _busyText = 'Checking your symptoms…';
    });
    _scrollDown();
    try {
      final a = await _checks.checkSymptoms(
          symptoms: _symptoms!, answers: List.of(_answers), language: _lang?.code ?? 'en');
      if (!mounted) return;
      if (!a.emergency && !a.ready && a.followUpQuestions.isNotEmpty) {
        // Still interviewing: ask the next questions (several rounds if the AI needs them).
        final first = !_asked;
        _asked = true;
        _pending.addAll(a.followUpQuestions);
        setState(() => _busy = false);
        // The first round follows the reply just read, so queue instead of interrupting.
        if (first) _botSays(_lang!.checkIntro, append: true);
        _botSays(_pending.first, logIt: true, append: first);
        return;
      }
      _inCheck = false;
      setState(() => _items.add(_Item.result(a)));
      final style = '${a.triageLevel}: ${a.possibleCauses.map((c) => c.name).take(2).join(', ')}';
      _log([ChatMessage(fromUser: false, text: 'Symptom check result — $style')]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _items.add(_Item.bot('${e.message} You can send it again.', isError: true)));
      // Let the user retry: their next message becomes the symptoms again.
      if (_pending.isEmpty) _symptoms = null;
    } catch (e) {
      if (mounted) setState(() => _items.add(_Item.bot('Something went wrong ($e). Please try again.', isError: true)));
      if (_pending.isEmpty) _symptoms = null;
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  Future<void> _toggleMic() async {
    if (_lang == null) return;
    if (_listening) {
      await _voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    await _voice.stopSpeaking();
    final ok = await _voice.listen(
      _lang!.speechLocale,
      (words, isFinal) {
        if (!mounted) return;
        _input.text = words;
        _input.selection = TextSelection.collapsed(offset: words.length);
        if (isFinal) {
          setState(() => _listening = false);
          if (words.trim().isNotEmpty) _send(words);
        }
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _listening = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice input is not available here. Please allow the microphone, or type your message.')));
    }
  }

  Future<void> _uploadReport() async {
    if (_busy) return;
    final picked = await pickReport(context);
    if (picked == null || !mounted) return;
    final lang = _lang ?? chatLanguages.first;
    setState(() {
      _items.add(_Item.user('📄 ${picked.name}'));
      _busy = true;
      _busyText = lang.reportReading;
    });
    _scrollDown();
    try {
      final r = await _reports.upload(
          bytes: picked.bytes, fileName: picked.name, mimeType: mimeTypeFor(picked.name), language: lang.code);
      if (!mounted) return;
      setState(() => _items.add(_Item.report(r)));
      if (r.analysis != null) _say(r.analysis!.summary);
    } on ApiException catch (e) {
      if (mounted) setState(() => _items.add(_Item.bot(e.message, isError: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _openCompare([String? newId]) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ReportCompareScreen(repository: _reports, newId: newId)));

  void _showTools() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file_outlined, color: AppColors.accent),
            title: const Text('Upload a medical report'),
            subtitle: const Text('Photo or PDF — the AI explains it'),
            onTap: () {
              Navigator.pop(ctx);
              _uploadReport();
            },
          ),
          ListTile(
            leading: const Icon(Icons.compare_arrows, color: AppColors.accent),
            title: const Text('Compare old vs new report'),
            onTap: () {
              Navigator.pop(ctx);
              _openCompare();
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined, color: AppColors.accent),
            title: const Text('My reports'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportsScreen(repository: _reports)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.sick_outlined, color: AppColors.accent),
            title: const Text('Check my symptoms'),
            subtitle: const Text('Questions → triage, possible causes, doctor and tests'),
            onTap: () {
              Navigator.pop(ctx);
              if (_lang == null) return;
              _startCheck();
              _botSays(_lang!.describeSymptoms);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_edu_outlined, color: AppColors.accent),
            title: const Text('Past symptom checks'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => SymptomHistoryScreen(repository: _checks)));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _newChat() {
    _voice.stopSpeaking();
    setState(() {
      _chatId = null;
      _lang = null;
      _inCheck = false;
      _symptoms = null;
      _answers.clear();
      _pending.clear();
      _items
        ..clear()
        ..addAll([_Item.bot(_askLanguage), _Item.languagePicker()]);
    });
  }

  Widget _buildItem(_Item i) => switch (i.kind) {
        _Kind.languages => _LanguageChips(onPick: _chooseLanguage),
        _Kind.report => ReportAnalysisCard(report: i.report!, onCompare: () => _openCompare(i.report!.id)),
        _Kind.result => SymptomResultBubble(assessment: i.assessment!),
        _Kind.text => _Bubble(
            item: i,
            onSpeak: i.fromUser || i.isError || _lang == null ? null : () => _voice.speakNow(i.text, _lang!.code),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final lang = _lang;
    final canType = lang != null && !_busy;
    final hasText = _input.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health assistant'),
        actions: [
          IconButton(
            tooltip: 'Voice settings',
            icon: Icon(_speak ? Icons.volume_up_outlined : Icons.volume_off_outlined),
            onPressed: () => showVoiceSettings(
              context,
              voice: _voice,
              language: _lang ?? chatLanguages.first,
              speakOn: _speak,
              onSpeakChanged: (v) {
                setState(() => _speak = v);
                if (!v) _voice.stopSpeaking();
              },
            ),
          ),
          IconButton(
            tooltip: 'Chat history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => ChatHistoryScreen(repository: _repo, reports: _reports))),
          ),
          if (_chatId != null || lang != null)
            IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: _busy ? null : _newChat),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (final i in _items) _buildItem(i),
                    if (_busy) _Typing(text: _busyText),
                  ],
                ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Health information only, not a diagnosis or prescription. Emergency: 1122',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
            child: Row(children: [
              IconButton(
                tooltip: 'Reports and tools',
                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                onPressed: _busy ? null : _showTools,
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
                    const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
                  },
                  child: TextField(
                    controller: _input,
                    enabled: canType,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textDirection: lang?.rtl == true && !hasText ? TextDirection.rtl : null,
                    decoration: InputDecoration(
                      hintText: lang == null
                          ? 'Choose a language above'
                          : _listening
                              ? lang.listening
                              : lang.hint,
                      filled: true,
                      fillColor: _listening ? AppColors.accentTint : Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (hasText && !_listening)
                IconButton.filled(
                  tooltip: 'Send',
                  style: IconButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(48, 48)),
                  onPressed: canType ? _send : null,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                )
              else
                IconButton.filled(
                  tooltip: _listening ? 'Stop' : 'Voice message',
                  style: IconButton.styleFrom(
                      backgroundColor: _listening ? AppColors.critical : AppColors.accent,
                      minimumSize: const Size(48, 48)),
                  onPressed: canType ? _toggleMic : null,
                  icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_none, color: Colors.white),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _LanguageChips extends StatelessWidget {
  const _LanguageChips({required this.onPick});
  final void Function(ChatLanguage) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final l in chatLanguages)
          ActionChip(
            label: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            avatar: const Icon(Icons.translate, size: 18, color: AppColors.accent),
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.accent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onPressed: () => onPick(l),
          ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.item, this.onSpeak});
  final _Item item;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final user = item.fromUser;
    final bg = user
        ? AppColors.primary
        : item.emergency || item.isError
            ? AppColors.criticalTint
            : Colors.white;
    final rtl = _urduScript.hasMatch(item.text) && !item.text.contains('Which language');
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.fromLTRB(14, 10, onSpeak == null ? 14 : 6, 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
          border: user ? null : Border.all(color: item.emergency ? AppColors.critical : const Color(0xFFE9EEF4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Flexible(
            child: Text(
              item.text,
              textDirection: rtl ? TextDirection.rtl : null,
              style: TextStyle(
                color: user ? Colors.white : (item.emergency ? AppColors.critical : AppColors.text),
                fontWeight: item.emergency ? FontWeight.w700 : FontWeight.w400,
                height: rtl ? 1.7 : 1.4,
                fontSize: 15,
              ),
            ),
          ),
          if (onSpeak != null)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onSpeak,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.volume_up_outlined, size: 18, color: AppColors.textMuted),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: const TextStyle(color: AppColors.textMuted))),
        ]),
      ),
    );
  }
}
