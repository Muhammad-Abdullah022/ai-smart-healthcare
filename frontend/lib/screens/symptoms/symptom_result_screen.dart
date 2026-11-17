import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/assessment.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/section_card.dart';
import 'triage_style.dart';

/// What the user typed, kept so follow-up answers can be sent with it.
class SymptomRequestData {
  const SymptomRequestData({
    required this.symptoms,
    required this.duration,
    required this.severity,
    this.age,
    this.sex,
  });

  final String symptoms;
  final String duration;
  final int severity;
  final int? age;
  final String? sex;
}

/// Shows the triage level first, then possible causes, next steps, follow-up
/// questions, and "Why this result?" (explainability, feature 46).
class SymptomResultScreen extends StatefulWidget {
  const SymptomResultScreen({super.key, required this.assessment, this.repository, this.request});

  final Assessment assessment;
  final AssessmentRepository? repository;

  /// Null when opened from history (follow-up answering is then hidden).
  final SymptomRequestData? request;

  @override
  State<SymptomResultScreen> createState() => _SymptomResultScreenState();
}

class _SymptomResultScreenState extends State<SymptomResultScreen> {
  late Assessment _a = widget.assessment;
  final Map<String, TextEditingController> _answers = {};
  bool _updating = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String q) => _answers.putIfAbsent(q, TextEditingController.new);

  /// Feature 2 (adaptive cross-questioning): send answers and get an updated result.
  Future<void> _sendAnswers() async {
    final req = widget.request;
    final repo = widget.repository;
    if (req == null || repo == null) return;
    final answers = [
      for (final q in _a.followUpQuestions)
        if (_controllerFor(q).text.trim().isNotEmpty) {'question': q, 'answer': _controllerFor(q).text.trim()},
    ];
    if (answers.isEmpty) {
      setState(() => _error = 'Please answer at least one question.');
      return;
    }
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final updated = await repo.checkSymptoms(
        symptoms: req.symptoms,
        duration: req.duration,
        severity: req.severity,
        age: req.age,
        sex: req.sex,
        answers: answers,
      );
      if (mounted) {
        setState(() {
          _a = updated;
          for (final c in _answers.values) {
            c.clear();
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TriageStyle.of(_a.triageLevel);
    return Scaffold(
      appBar: AppBar(title: const Text('Your result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TriageCard(style: style, reason: _a.triageReason),
          if (_a.emergencyNumbers.isNotEmpty && _a.triageLevel == 'critical') ...[
            const SizedBox(height: 12),
            _EmergencyNumbers(numbers: _a.emergencyNumbers),
          ],
          if (_a.possibleCauses.isNotEmpty) ...[
            const _Heading('Possible causes'),
            const Text('These are possibilities to discuss with a doctor — not a diagnosis.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < _a.possibleCauses.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: Color(0xFFEDF1F4)),
                  _CauseTile(cause: _a.possibleCauses[i]),
                ],
              ]),
            ),
          ],
          if (_a.nextSteps.isNotEmpty) ...[
            const _Heading('What to do next'),
            _BulletCard(items: _a.nextSteps, icon: Icons.arrow_forward),
          ],
          if (_a.warningSigns.isNotEmpty) ...[
            const _Heading('Get urgent care if you notice'),
            _BulletCard(items: _a.warningSigns, icon: Icons.warning_amber, color: AppColors.critical),
          ],
          if (_a.testsToDiscuss.isNotEmpty || _a.specialistType != null) ...[
            const _Heading('To discuss with a doctor'),
            _BulletCard(
              icon: Icons.biotech_outlined,
              items: [
                for (final t in _a.testsToDiscuss) 'Test: $t',
                if (_a.specialistType != null) 'Doctor type: ${_a.specialistType}',
              ],
            ),
          ],
          if (_a.followUpQuestions.isNotEmpty && widget.request != null && !_a.emergency) ...[
            const _Heading('Help us understand better'),
            for (final q in _a.followUpQuestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _controllerFor(q),
                  decoration: InputDecoration(labelText: q),
                ),
              ),
            if (_error != null) ErrorBanner(_error!),
            AppButton(label: 'Update result', icon: Icons.refresh, loading: _updating, onPressed: _sendAnswers),
          ],
          if (_a.answers.isNotEmpty) ...[
            const _Heading('Your conversation'),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You: ${_a.symptoms}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final (q, ans) in _a.answers) ...[
                    const SizedBox(height: 10),
                    Text(q, style: const TextStyle(color: AppColors.textMuted)),
                    Text('You: $ans', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ],
          const _Heading('Why this result?'),
          _ExplanationCard(explanation: _a.explanation),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(12)),
            child: Text(_a.disclaimer, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
      );
}

class _TriageCard extends StatelessWidget {
  const _TriageCard({required this.style, required this.reason});
  final TriageStyle style;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(style.icon, color: style.color, size: 30),
              const SizedBox(width: 10),
              Text('Triage: ${style.label}',
                  style: TextStyle(color: style.color, fontWeight: FontWeight.w800, fontSize: 20)),
            ],
          ),
          const SizedBox(height: 8),
          Text(style.advice, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          Text(reason, style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }
}

class _EmergencyNumbers extends StatelessWidget {
  const _EmergencyNumbers({required this.numbers});
  final List<EmergencyNumber> numbers;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          for (final n in numbers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone, color: AppColors.critical),
              title: Text(n.name),
              trailing: Text(n.number,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.critical)),
            ),
        ],
      ),
    );
  }
}

class _CauseTile extends StatelessWidget {
  const _CauseTile({required this.cause});
  final PossibleCause cause;

  @override
  Widget build(BuildContext context) {
    final color = switch (cause.likelihood) {
      'high' => AppColors.primary,
      'medium' => AppColors.accent,
      _ => AppColors.textMuted,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Text(cause.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${cause.likelihood} match', style: TextStyle(color: color, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(cause.reason, style: const TextStyle(color: AppColors.textMuted, height: 1.45)),
            ),
          ],
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({required this.items, required this.icon, this.color = AppColors.accent});
  final List<String> items;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item, style: const TextStyle(height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.explanation});
  final AssessmentExplanation explanation;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(explanation.method, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (explanation.aiProvider != null) Text('AI used: ${explanation.aiProvider}', style: muted),
          const SizedBox(height: 6),
          Text('Information used: ${explanation.inputsUsed.join(', ')}', style: muted),
          const SizedBox(height: 4),
          Text('Safety checks: ${explanation.rulesTriggered.join('; ')}', style: muted),
          const SizedBox(height: 4),
          Text('Limitations: ${explanation.limitations}', style: muted),
        ],
      ),
    );
  }
}
