import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/assessment.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../services/report_repository.dart' show ReportRepository, mimeTypeFor;
import '../reports/report_widgets.dart' show pickReport;
import '../doctors/doctor_booking_card.dart';
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

/// Final answer shown inside the chat. What it shows depends on the care path:
///   self_care   -> what to do + over-the-counter medicines (no doctor, no tests)
///   tests_first -> only the tests to get, then "Upload report"; the AI reads it and decides again
///   see_doctor  -> doctor type + matching doctors to book
///   emergency   -> call 1122
class SymptomResultBubble extends StatefulWidget {
  const SymptomResultBubble({super.key, required this.assessment});
  final Assessment assessment;

  @override
  State<SymptomResultBubble> createState() => _SymptomResultBubbleState();
}

class _SymptomResultBubbleState extends State<SymptomResultBubble> {
  late Assessment _a = widget.assessment;
  bool _uploading = false;
  String? _step;

  Future<void> _uploadReport() async {
    final picked = await pickReport(context);
    if (picked == null || !mounted) return;
    final api = context.read<AuthProvider>().repository.api;
    setState(() {
      _uploading = true;
      _step = 'Reading your report…';
    });
    try {
      final report = await ReportRepository(api).upload(
          bytes: picked.bytes, fileName: picked.name, mimeType: mimeTypeFor(picked.name));
      if (report.analysis == null) {
        throw report.error ?? 'The report could not be read. Please upload a clearer photo.';
      }
      if (mounted) setState(() => _step = 'Checking the results with your symptoms…');
      final updated = await AssessmentRepository(api).reviewReport(_a.id, report.id);
      if (mounted) setState(() => _a = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.critical));
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _step = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final path = a.emergency ? 'emergency' : a.carePath;
    final style = TriageStyle.of(a.triageLevel);
    final (title, advice, color, bg, icon) = switch (path) {
      'self_care' => (
          'Self-care at home',
          'This looks minor. Rest and the medicines below usually help. No doctor needed for now.',
          AppColors.success,
          const Color(0xFFE7F7EF),
          Icons.spa_outlined
        ),
      'tests_first' => (
          'Get these tests first',
          'The tests will show whether home care is enough or you need a doctor.',
          const Color(0xFF2563EB),
          const Color(0xFFE8F0FE),
          Icons.biotech_outlined
        ),
      _ => (style.label, style.advice, style.color, style.background, style.icon),
    };
    final review = a.reportReview;
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
          Container(
            color: bg,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              CircleAvatar(radius: 18, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(advice, style: const TextStyle(fontSize: 13, color: AppColors.text)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (path == 'emergency' && a.emergencyNumbers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Call ${a.emergencyNumbers.map((n) => n.number).join(' or ')} now.',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.critical, fontSize: 15)),
                ),
              if (review != null) _ReportReviewCard(review: review),
              if (review == null && a.possibleCauses.isNotEmpty) ...[
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
              // Tests-first: only the tests.
              if (path == 'tests_first') ...[
                const SizedBox(height: 12),
                const Text('Tests to get', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in a.testsToDiscuss)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.science_outlined, size: 15, color: Color(0xFF2563EB)),
                        const SizedBox(width: 5),
                        Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 12),
                if (_uploading)
                  Row(children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_step ?? '', style: const TextStyle(color: AppColors.textMuted))),
                  ])
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: _uploadReport,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Upload test report'),
                    ),
                  ),
                const SizedBox(height: 4),
                const Text('After the test, upload the report here. The AI will read it and tell you the next step.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
              // See a doctor: which doctor and (if any) the tests to take along.
              if (path == 'see_doctor') ...[
                if (a.specialistType != null) ...[
                  const SizedBox(height: 12),
                  _InfoLine(icon: Icons.medical_services_outlined, label: 'Doctor to see', value: a.specialistType!),
                ],
                if (a.testsToDiscuss.isNotEmpty && review == null) ...[
                  const SizedBox(height: 8),
                  _InfoLine(icon: Icons.biotech_outlined, label: 'Tests (English)', value: a.testsToDiscuss.join(', ')),
                ],
              ],
              if (path != 'emergency' && path != 'tests_first' && a.nextSteps.isNotEmpty) ...[
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
              // Self-care: the medicines.
              if (path == 'self_care' && a.otcOptions.isNotEmpty) _OtcCard(options: a.otcOptions),
              if (path == 'self_care' && a.warningSigns.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
                  child: Text('See a doctor if: ${a.warningSigns.take(3).join('; ')}',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF7C4A03))),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _ActionPill(
                icon: Icons.description_outlined,
                label: 'Full result',
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SymptomResultScreen(assessment: a))),
              ),
              if (path == 'tests_first')
                _ActionPill(
                  icon: Icons.biotech_outlined,
                  label: 'Labs & prices',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => LabOptionsScreen(tests: a.testsToDiscuss))),
                ),
              if (path == 'self_care' && a.otcOptions.isNotEmpty)
                _ActionPill(
                  icon: Icons.local_pharmacy_outlined,
                  label: 'Nearby pharmacy',
                  onTap: () => GoRouter.of(context).push('/feature/28'),
                ),
            ]),
          ),
          // Only when a doctor is really needed.
          if (path == 'see_doctor' && a.specialistType != null)
            DoctorBookingCard(
              key: ValueKey('book-${a.specialistType}-${review != null}'),
              specialty: a.specialistType!,
              reason: [
                a.symptoms,
                if (review != null && '${review['summary'] ?? ''}'.isNotEmpty) 'Report: ${review['summary']}'
                else if (a.possibleCauses.isNotEmpty) 'Possible: ${a.possibleCauses.first.name}',
              ].join(' — '),
            ),
        ],
      ),
    );
  }
}

/// What the AI found in the uploaded report.
class _ReportReviewCard extends StatelessWidget {
  const _ReportReviewCard({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final abnormal = (review['abnormal'] as List? ?? const []).cast<Map>();
    final findings = (review['findings'] as List? ?? const []).cast<Object>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fact_check_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Your report: ${review['report_type'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ]),
        if ('${review['summary'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${review['summary']}', style: const TextStyle(fontSize: 13.5, height: 1.35)),
        ],
        if (abnormal.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in abnormal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: v['critical'] == true ? const Color(0xFFFDE2E2) : const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('${v['name']} ${v['value']} ${v['unit'] ?? ''} ${v['flag'] == 'high' ? '↑' : '↓'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
        ] else if (findings.isEmpty) ...[
          const SizedBox(height: 6),
          const Text('All values in range.', style: TextStyle(fontSize: 12.5, color: AppColors.success)),
        ],
        for (final f in findings.take(3))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $f', style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
          ),
      ]),
    );
  }
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
  final List<({String name, String helpsWith, String avoidIf, int days})> options;

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
        const SizedBox(height: 2),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _otcInk,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.alarm_add_rounded, size: 20),
          label: const Text('Add to my medicine reminders'),
          onPressed: () => showOtcReminderSheet(context, options),
        ),
        const SizedBox(height: 8),
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
          SizedBox(width: 6),
          Expanded(
            child: Text('For relief only, not a prescription. Take it as written on the pack or as the pharmacist '
                'says. See a doctor if you are not better in the days shown.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35)),
          ),
        ]),
      ]),
    );
  }
}

class _OtcItem extends StatelessWidget {
  const _OtcItem({required this.option});
  final ({String name, String helpsWith, String avoidIf, int days}) option;

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
            child: Text('Up to ${o.days} days',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _otcInk)),
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


/// One tap: the self-care medicines become reminders for the days the AI said (never longer than a week).
/// The app never sets a dose: the user picks the times written on the pack or told by the pharmacist.
Future<void> showOtcReminderSheet(
    BuildContext context, List<({String name, String helpsWith, String avoidIf, int days})> options) async {
  final api = context.read<AuthProvider>().repository.api;
  final repo = MedicineRepository(api);
  final selected = [for (final _ in options) true];
  final days = [for (final o in options) o.days.clamp(1, 7).toInt()];
  final times = [
    for (final _ in options) <String>['09:00', '21:00']
  ];
  var saving = false;
  String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String form(String name) {
    final n = name.toLowerCase();
    if (n.contains('cream') || n.contains('lotion')) return 'cream';
    if (n.contains('spray') || n.contains('ors') || n.contains('rehydration') || n.contains('lozenge')) return 'other';
    return 'tablet';
  }

  final added = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add medicine reminders',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deep)),
            const SizedBox(height: 4),
            const Text('Reminders stop by themselves after the days shown. Set the times written on the pack '
                'or told by your pharmacist.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35)),
            const SizedBox(height: 12),
            for (var i = 0; i < options.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 10),
                decoration: BoxDecoration(
                  color: selected[i] ? _otcTint : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: selected[i] ? _otcInk.withAlpha(60) : AppColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CheckboxListTile(
                    value: selected[i],
                    onChanged: (v) => setSheet(() => selected[i] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(cap(options[i].name), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    subtitle: Text('For ${days[i]} day${days[i] == 1 ? '' : 's'} (from today)'),
                  ),
                  if (selected[i])
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Text('Days', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: days[i] > 1 ? () => setSheet(() => days[i]--) : null,
                          ),
                          Text('${days[i]}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: days[i] < 7 ? () => setSheet(() => days[i]++) : null,
                          ),
                        ]),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (var t = 0; t < times[i].length; t++)
                            InputChip(
                              label: Text(times[i][t]),
                              avatar: const Icon(Icons.alarm, size: 16),
                              onPressed: () async {
                                final parts = times[i][t].split(':');
                                final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
                                if (picked != null) {
                                  setSheet(() => times[i][t] =
                                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                                }
                              },
                              onDeleted: times[i].length > 1 ? () => setSheet(() => times[i].removeAt(t)) : null,
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: const Text('Time'),
                            onPressed: times[i].length >= 4 ? null : () => setSheet(() => times[i].add('14:00')),
                          ),
                        ]),
                      ]),
                    ),
                ]),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: _otcInk),
              icon: saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.alarm_add_outlined),
              label: const Text('Save reminders'),
              onPressed: saving || !selected.contains(true)
                  ? null
                  : () async {
                      setSheet(() => saving = true);
                      var count = 0;
                      final today = DateTime.now();
                      for (var i = 0; i < options.length; i++) {
                        if (!selected[i]) continue;
                        final o = options[i];
                        final body = {
                          'name': cap(o.name),
                          'salt': cap(o.name),
                          'form': form(o.name),
                          'times': times[i],
                          'instructions': 'As written on the pack or as your pharmacist says. '
                              'Stop and see a doctor if not better in ${days[i]} days.',
                          'start_date': iso(today),
                          'end_date': iso(today.add(Duration(days: days[i] - 1))),
                        };
                        try {
                          await repo.add(body);
                          count++;
                        } on ApiException catch (e) {
                          if (e.code == 'allergy_warning' && ctx.mounted) {
                            final ok = await showConfirmDialog(ctx,
                                title: 'Allergy warning', message: e.message, confirmLabel: 'Add anyway');
                            if (ok) {
                              try {
                                await repo.add(body, confirmAllergy: true);
                                count++;
                              } on ApiException catch (_) {}
                            }
                          } else if (ctx.mounted) {
                            showMessage(ctx, '${o.name}: ${e.message}', error: true);
                          }
                        }
                      }
                      if (ctx.mounted) Navigator.pop(ctx, count);
                    },
            ),
          ]),
        ),
      ),
    ),
  );
  if (added != null && added > 0 && context.mounted) {
    showMessage(context, '$added reminder${added == 1 ? '' : 's'} added. See them in Smart Medicine Reminders.');
  }
}
