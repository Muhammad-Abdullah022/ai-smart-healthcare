import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/assessment.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../../services/doctor_repository.dart';
import '../consult/doctor_panel_screens.dart' show showConsultRequestSheet;
import '../doctors/doctor_detail_screen.dart';
import '../doctors/doctors_screens.dart';
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
        if (!a.emergency && !a.ready && a.followUpQuestions.isNotEmpty) {
          // The AI is still interviewing: ask its questions one by one (several rounds if needed).
          if (!_asked) _messages.add(_Msg.bot('Thanks. A few quick questions so I understand better:'));
          _asked = true;
          _pending.addAll(a.followUpQuestions);
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
          border: user ? null : Border.all(color: const Color(0xFFE2E8EC)),
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
        border: Border.all(color: const Color(0xFFE2E8EC)),
        boxShadow: const [BoxShadow(color: Color(0x0F0B2B3C), blurRadius: 16, offset: Offset(0, 6))],
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
                if (!critical && a.nextSteps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('What you can do now', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  for (final step in a.nextSteps.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(child: Text(step, style: const TextStyle(fontSize: 14))),
                      ]),
                    ),
                ],
                if (a.otcOptions.isNotEmpty) _OtcCard(options: a.otcOptions),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionPill(
                  icon: Icons.description_outlined,
                  label: 'Full result',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => SymptomResultScreen(assessment: a))),
                ),
                if (a.testsToDiscuss.isNotEmpty)
                  _ActionPill(
                    icon: Icons.biotech_outlined,
                    label: 'Labs & prices',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => LabOptionsScreen(tests: a.testsToDiscuss))),
                  ),
                if (a.testsToDiscuss.isNotEmpty)
                  _ActionPill(
                    icon: Icons.upload_file_outlined,
                    label: 'Add report',
                    onTap: () => GoRouter.of(context).push('/feature/8'),
                  ),
              ],
            ),
          ),
          if (a.specialistType != null && !a.emergency)
            _BookPrompt(
              specialty: a.specialistType!,
              reason: [
                a.symptoms,
                if (a.possibleCauses.isNotEmpty) 'Possible: ${a.possibleCauses.first.name}',
              ].join(' — '),
            ),
        ],
      ),
    );
  }
}

/// When a doctor visit is advised: "Book an appointment?" Yes -> choose a doctor -> request is emailed.
/// Right after the AI names a specialist: only doctors of that specialty (user's city first),
/// each with "Book now". Online doctors open the live consultation straight away; others get the
/// appointment request sheet. The rest of the flow (chat, payment, prescription) continues from there.
class _BookPrompt extends StatefulWidget {
  const _BookPrompt({required this.specialty, required this.reason});
  final String specialty;
  final String reason;

  @override
  State<_BookPrompt> createState() => _BookPromptState();
}

class _BookPromptState extends State<_BookPrompt> {
  late final DoctorRepository _repo = DoctorRepository(context.read<AuthProvider>().repository.api);
  late Future<RecommendedDoctors> _future = _repo.recommended(widget.specialty);
  bool _dismissed = false;
  String? _bookedId;

  Future<void> _book(Doctor d) async {
    if (d.online) {
      final id = await showConsultRequestSheet(context, doctor: d, reason: widget.reason, fromChat: true);
      if (id != null && mounted) setState(() => _bookedId = d.id);
    } else {
      final ok = await showDoctorBookingSheet(context,
          repository: _repo, doctor: d, reason: widget.reason, fromChat: true);
      if (ok && mounted) setState(() => _bookedId = d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<RecommendedDoctors>(
        future: _future,
        builder: (context, snap) {
          final r = snap.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryDeep])),
              child: Row(children: [
                const Icon(Icons.medical_services_outlined, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Book a ${r?.specialty ?? widget.specialty}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        r == null
                            ? 'Finding doctors for this problem…'
                            : r.backup
                                ? 'No ${widget.specialty} listed yet — showing the backup the AI advised.'
                                : 'Only ${r.specialty}s${r.city != null ? ' in ${r.city}' : ''} for this problem',
                        style: const TextStyle(color: Color(0xFFCBD7E6), fontSize: 12.5)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Not now',
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ]),
            ),
            if (snap.hasError)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Expanded(child: Text('Could not load doctors.', style: TextStyle(color: AppColors.textMuted))),
                  TextButton(
                      onPressed: () => setState(() => _future = _repo.recommended(widget.specialty)),
                      child: const Text('Retry')),
                ]),
              )
            else if (r == null)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
              )
            else if (r.doctors.isEmpty)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('No doctor of this specialty is listed yet. Use "See all doctors" to search other cities.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              )
            else
              for (final d in r.doctors) _doctorRow(d, r.otherCity.contains(d.id)),
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DoctorListScreen(
                    specialty: r?.specialty ?? widget.specialty, reason: widget.reason, fromChat: true),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                      r != null && r.totalInCity > r.doctors.length
                          ? 'See all ${r.totalInCity} ${r.specialty}s'
                          : 'See all doctors',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: AppColors.primary, size: 20),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _doctorRow(Doctor d, bool otherCity) {
    final booked = _bookedId == d.id;
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: [
        InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DoctorDetailScreen(
                  doctor: d, repository: _repo, reason: widget.reason, fromChat: true))),
          child: DoctorAvatar(doctor: d, size: 46),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.text)),
            Text(
                [
                  d.city + (otherCity ? ' (other city)' : ''),
                  if (d.fee != null) 'Rs ${d.fee!.toStringAsFixed(0)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            Wrap(spacing: 4, children: [
              if (d.online) _tag('Online now', AppColors.green),
              if (d.government) _tag('Govt. list', AppColors.primary),
              if (d.demo) _tag('Demo profile', AppColors.warning),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        booked
            ? const Chip(
                avatar: Icon(Icons.check_circle, color: AppColors.green, size: 18),
                label: Text('Booked'),
                visualDensity: VisualDensity.compact,
              )
            : FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.online ? AppColors.green : AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () => _book(d),
                child: Text(d.online ? 'Consult now' : 'Book now', style: const TextStyle(fontSize: 13)),
              ),
      ]),
    );
  }

  static Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
      );
}

/// Small rounded action button under a result.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.accentTint,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent, fontSize: 13.5)),
            ]),
          ),
        ),
      );
}

final _urduText = RegExp(r'[؀-ۿ]');
const _otcInk = Color(0xFF4C3FA8);
const _otcTint = Color(0xFFF4F2FF);

/// Over-the-counter options a pharmacist could suggest. Generic names only — the pharmacist or the
/// pack gives the dose. Shown only for mild/moderate results for adults (filtered on the backend).
class _OtcCard extends StatelessWidget {
  const _OtcCard({required this.options});
  final List<({String name, String helpsWith, String avoidIf})> options;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: _otcTint, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.local_pharmacy_outlined, size: 18, color: _otcInk),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Ask a pharmacist about',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _otcInk)),
          ),
        ]),
        const SizedBox(height: 10),
        for (final o in options) _OtcItem(option: o),
        const SizedBox(height: 4),
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
          SizedBox(width: 6),
          Expanded(
            child: Text('For relief only, not a prescription. The pharmacist gives the dose. '
                'See a doctor if you are not better in 2–3 days.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35)),
          ),
        ]),
      ]),
    );
  }
}

class _OtcItem extends StatelessWidget {
  const _OtcItem({required this.option});
  final ({String name, String helpsWith, String avoidIf}) option;

  Widget _line(IconData icon, Color color, String text) {
    final rtl = _urduText.hasMatch(text);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                style: TextStyle(fontSize: 13.5, height: rtl ? 1.7 : 1.4, color: AppColors.text)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = option;
    final name = o.name.isEmpty ? '' : o.name[0].toUpperCase() + o.name.substring(1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.medication_rounded, size: 18, color: _otcInk),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _otcTint, borderRadius: BorderRadius.circular(8)),
            child: const Text('OTC', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _otcInk)),
          ),
        ]),
        if (o.helpsWith.isNotEmpty) _line(Icons.check_circle_rounded, AppColors.success, o.helpsWith),
        if (o.avoidIf.isNotEmpty) _line(Icons.warning_amber_rounded, AppColors.warning, o.avoidIf),
      ]),
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
