import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/assessment.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../labs/booking_sheet.dart';
import '../labs/lab_options_screen.dart';
import 'symptom_history_screen.dart';
import 'symptom_result_screen.dart';
import 'triage_style.dart';

/// One chat message on screen.
class _Msg {
  _Msg.user(this.text) : fromUser = true, assessment = null, isError = false;
  _Msg.bot(this.text, {this.isError = false}) : fromUser = false, assessment = null;
  _Msg.result(this.assessment) : fromUser = false, text = '', isError = false;

  final bool fromUser;
  final String text;
  final Assessment? assessment;
  final bool isError;
}

/// AI Symptom Checker as a chat (features 1–5 together):
/// the user describes symptoms; the AI asks follow-up questions one at a time
/// (duration, severity, etc.), then shows triage, possible causes and next steps.
/// Emergency signs are answered immediately by the backend's safety rules.
class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({super.key, this.repository});

  /// Optional, so tests can pass a fake.
  final AssessmentRepository? repository;

  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen> {
  late final AssessmentRepository _repo =
      widget.repository ?? AssessmentRepository(context.read<AuthProvider>().repository.api);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    _Msg.bot('Hi! Tell me what you are feeling, in your own words. '
        'I will ask a few short questions, then explain what it might be and what to do next.'),
  ];

  String? _symptoms; // the first message
  final List<Map<String, String>> _answers = [];
  final List<String> _pending = []; // follow-up questions still to ask
  bool _asked = false; // follow-up round already done
  bool _busy = false;
  bool _finished = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (_symptoms == null && text.length < 3) {
      setState(() => _messages.add(_Msg.bot('Please describe your symptoms in a few words, e.g. "fever and headache".')));
      _scrollDown();
      return;
    }
    _input.clear();
    // On some browsers Enter also types a new line after we clear; remove it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_input.text.trim().isEmpty) _input.clear();
    });
    setState(() => _messages.add(_Msg.user(text)));
    _scrollDown();

    if (_symptoms == null) {
      _symptoms = text;
      await _ask();
      return;
    }
    if (_pending.isEmpty) {
      // The first request failed earlier: treat this as the symptoms again.
      _symptoms = text;
      await _ask();
      return;
    }
    // Answer to the current follow-up question.
    _answers.add({'question': _pending.removeAt(0), 'answer': text});
    if (_pending.isNotEmpty) {
      setState(() => _messages.add(_Msg.bot(_pending.first)));
      _scrollDown();
    } else {
      await _ask();
    }
  }

  Future<void> _ask() async {
    setState(() => _busy = true);
    try {
      final a = await _repo.checkSymptoms(symptoms: _symptoms!, answers: List.of(_answers));
      if (!mounted) return;
      setState(() {
        if (!a.emergency && !_asked && a.followUpQuestions.isNotEmpty) {
          // First round: ask the follow-up questions one by one.
          _asked = true;
          _pending.addAll(a.followUpQuestions);
          _messages.add(_Msg.bot('Thanks. A few quick questions so I understand better:'));
          _messages.add(_Msg.bot(_pending.first));
        } else {
          _messages.add(_Msg.result(a));
          _finished = true;
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_Msg.bot('${e.message} You can send your message again.', isError: true)));
      }
    } catch (e) {
      // Any other problem must be visible too, never a silent failure.
      if (mounted) {
        setState(() => _messages.add(_Msg.bot('Something went wrong ($e). Please try again.', isError: true)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _restart() => setState(() {
        _messages.removeRange(1, _messages.length);
        _symptoms = null;
        _answers.clear();
        _pending.clear();
        _asked = false;
        _finished = false;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Symptom checker'),
        actions: [
          if (_messages.length > 1)
            IconButton(tooltip: 'New check', icon: const Icon(Icons.refresh), onPressed: _busy ? null : _restart),
          IconButton(
            tooltip: 'Past checks',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SymptomHistoryScreen(repository: _repo)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                for (final m in _messages)
                  if (m.assessment != null) SymptomResultBubble(assessment: m.assessment!) else _Bubble(msg: m),
                if (_busy) const _Typing(),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Health information only, not a diagnosis. Emergency: 1122',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): _send,
                        const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
                      },
                      child: TextField(
                      controller: _input,
                      enabled: !_finished,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _finished
                            ? 'Tap ↻ to start a new check'
                            : _symptoms == null
                                ? 'Describe your symptoms…'
                                : 'Type your answer…',
                        filled: true,
                        fillColor: Colors.white,
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
                  IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(48, 48)),
                    onPressed: _busy || _finished ? null : _send,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final user = msg.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: user ? AppColors.primary : (msg.isError ? AppColors.criticalTint : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
          border: user ? null : Border.all(color: const Color(0xFFE9EEF4)),
        ),
        child: Text(msg.text,
            style: TextStyle(color: user ? Colors.white : AppColors.text, height: 1.4, fontSize: 15)),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            SizedBox(width: 10),
            Text('Thinking…', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Final answer shown inside the chat: triage, what to do, doctor, tests and next actions.
class SymptomResultBubble extends StatelessWidget {
  const SymptomResultBubble({required this.assessment});
  final Assessment assessment;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final style = TriageStyle.of(a.triageLevel);
    final critical = a.triageLevel == 'critical';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9EEF4)),
        boxShadow: const [BoxShadow(color: Color(0x0F16324F), blurRadius: 16, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coloured triage header
          Container(
            color: style.background,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                CircleAvatar(radius: 18, backgroundColor: style.color, child: Icon(style.icon, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(style.label, style: TextStyle(color: style.color, fontWeight: FontWeight.w800, fontSize: 17)),
                      Text(style.advice, style: const TextStyle(fontSize: 13, color: AppColors.text)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (critical && a.emergencyNumbers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Call ${a.emergencyNumbers.map((n) => n.number).join(' or ')} now.',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.critical, fontSize: 15)),
                  ),
                if (a.possibleCauses.isNotEmpty) ...[
                  const Text('It may be', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  for (final c in a.possibleCauses.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.likelihood == 'high'
                                ? AppColors.primary
                                : c.likelihood == 'medium'
                                    ? AppColors.accent
                                    : const Color(0xFFB3BDC9),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                    ),
                ],
                if (a.specialistType != null) ...[
                  const SizedBox(height: 12),
                  _InfoLine(icon: Icons.medical_services_outlined, label: 'Doctor to see', value: a.specialistType!),
                ],
                if (a.testsToDiscuss.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoLine(icon: Icons.biotech_outlined, label: 'Tests (English)', value: a.testsToDiscuss.join(', ')),
                ],
              ],
            ),
          ),
          const Divider(height: 20, color: Color(0xFFEEF2F6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Full result'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => SymptomResultScreen(assessment: a))),
                ),
                if (a.specialistType != null)
                  TextButton.icon(
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text('Book ${a.specialistType}'),
                    onPressed: () => showBookingSheet(
                      context,
                      specialty: a.specialistType!,
                      reason: [
                        a.symptoms,
                        if (a.possibleCauses.isNotEmpty) 'Possible: ${a.possibleCauses.first.name}',
                      ].join(' — '),
                    ),
                  ),
                if (a.testsToDiscuss.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.biotech_outlined, size: 18),
                    label: const Text('Labs & prices'),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => LabOptionsScreen(tests: a.testsToDiscuss))),
                  ),
                if (a.testsToDiscuss.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Add report later'),
                    onPressed: () => GoRouter.of(context).push('/feature/8'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textMuted)),
            TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ])),
        ),
      ],
    );
  }
}
