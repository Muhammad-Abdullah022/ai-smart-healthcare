import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/mental_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';
import '../doctors/doctor_booking_card.dart';

/// Features 16 and 18: PHQ-9 (mood) and GAD-7 (anxiety), scored by fixed published rules.
class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key, this.repository, this.initialInstrument = 'phq9'});

  final MentalRepository? repository;
  final String initialInstrument;

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  late final MentalRepository _repo =
      widget.repository ?? MentalRepository(context.read<AuthProvider>().repository.api);
  late Future<Map<String, Instrument>> _future = _repo.instruments();
  late String _instrument = widget.initialInstrument;
  final Map<int, int> _answers = {};
  bool _sending = false;
  String? _error;
  bool _needsConsent = false;
  ScreeningResult? _result;

  Future<void> _submit(Instrument inst) async {
    if (_answers.length < inst.questions.length) {
      setState(() => _error = 'Please answer all ${inst.questions.length} questions.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _needsConsent = false;
    });
    try {
      final answers = [for (var i = 0; i < inst.questions.length; i++) _answers[i]!];
      final result = await _repo.submitScreening(inst.key, answers);
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _needsConsent = e.code == 'consent_required';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mental health check')),
      body: FutureBuilder<Map<String, Instrument>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            return ErrorView(
                message: 'Could not load the questions.',
                onRetry: () => setState(() => _future = _repo.instruments()));
          }
          if (_result != null) return _ResultView(result: _result!, onAgain: () => setState(() {
                _result = null;
                _answers.clear();
              }));
          final inst = snap.data![_instrument]!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'phq9', label: Text('Mood (PHQ-9)')),
                  ButtonSegment(value: 'gad7', label: Text('Anxiety (GAD-7)')),
                ],
                selected: {_instrument},
                onSelectionChanged: (s) => setState(() {
                  _instrument = s.first;
                  _answers.clear();
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              Text(inst.intro, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
              const SizedBox(height: 12),
              for (var i = 0; i < inst.questions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${inst.questions[i]}', style: const TextStyle(height: 1.4)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var o = 0; o < inst.options.length; o++)
                              ChoiceChip(
                                label: Text(inst.options[o], style: const TextStyle(fontSize: 12)),
                                selected: _answers[i] == o,
                                selectedColor: AppColors.accentTint,
                                onSelected: (_) => setState(() => _answers[i] = o),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null) ErrorBanner(_error!),
              if (_needsConsent)
                TextButton.icon(
                  onPressed: () => context.push('/settings/consent'),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Open Privacy & consent'),
                ),
              AppButton(label: 'See my result', loading: _sending, onPressed: () => _submit(inst)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.push('/feature/25'),
                child: const Text('Need help right now? Get crisis support'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onAgain});

  final ScreeningResult result;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (result.crisis) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.criticalTint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.critical),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please reach out now',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.critical)),
                const SizedBox(height: 6),
                const Text('You mentioned thoughts of hurting yourself. You deserve support, and help is available.'),
                const SizedBox(height: 12),
                AppButton(label: 'Get help now', icon: Icons.support_agent, onPressed: () => context.push('/feature/25')),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.title, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Text('${result.score} / ${result.maxScore}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary)),
              Text(result.severity[0].toUpperCase() + result.severity.substring(1),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(result.advice, style: const TextStyle(height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Moderate or worse: show real psychiatrists to book (same flow as the symptom checker).
        if (const {'moderate', 'moderately severe', 'severe'}.contains(result.severity)) ...[
          DoctorBookingCard(
            specialty: 'Psychiatrist',
            reason: '${result.title}: score ${result.score}/${result.maxScore} (${result.severity}). '
                'I would like to talk to a psychiatrist.',
          ),
          const SizedBox(height: 4),
        ] else ...[
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Helpful next steps', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 10),
              _NextStep(
                icon: Icons.self_improvement,
                title: 'Meditation & wellness plan',
                subtitle: '7 days of short guided sessions',
                onTap: () => context.push('/feature/23'),
              ),
              _NextStep(
                icon: Icons.chat_bubble_outline,
                title: 'Talk to MindEase',
                subtitle: 'A supportive chat, any time',
                onTap: () => context.push('/feature/17'),
              ),
              _NextStep(
                icon: Icons.insights_outlined,
                title: 'Track your mood',
                subtitle: 'See how you feel over the weeks',
                onTap: () => context.push('/feature/24'),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Text(result.note, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        AppButton(label: 'Take another check', outlined: true, onPressed: onAgain),
      ],
    );
  }
}


class _NextStep extends StatelessWidget {
  const _NextStep({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: AppColors.mindTint, child: Icon(icon, color: AppColors.mind)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      );
}
