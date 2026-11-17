import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../services/companion_repository.dart';
import '../../../widgets/state_views.dart';
import '../../../widgets/trend_chart.dart';

const _toneLabels = {
  'hopeless': 'Hopeless', 'fearful': 'Fearful', 'angry': 'Angry', 'sad': 'Sad', 'numb': 'Numb',
  'overwhelmed': 'Overwhelmed', 'confused': 'Confused', 'isolated': 'Isolated', 'ashamed': 'Ashamed',
  'calm': 'Calm', 'hopeful': 'Hopeful', 'neutral': 'Neutral',
};
const _themeLabels = {
  'stress': 'Stress', 'anxiety': 'Worry / anxiety', 'low_mood': 'Low mood', 'loneliness': 'Loneliness',
  'grief': 'Grief / loss', 'anger': 'Anger', 'sleep': 'Sleep', 'relationships': 'Relationships',
  'work_study': 'Work / studies', 'trauma': 'Hard past events', 'addiction': 'Habits / addiction', 'eating': 'Eating',
};

/// Wellbeing insights: mood check-ins over time and the feelings that came up most in chats.
class CompanionInsightsScreen extends StatefulWidget {
  const CompanionInsightsScreen({super.key, required this.repository});
  final CompanionRepository repository;

  @override
  State<CompanionInsightsScreen> createState() => _CompanionInsightsScreenState();
}

class _CompanionInsightsScreenState extends State<CompanionInsightsScreen> {
  int _days = 14;
  late Future<CompanionInsights> _future = widget.repository.insights(days: _days);

  void _reload(int d) => setState(() {
        _days = d;
        _future = widget.repository.insights(days: d);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My wellbeing')),
      body: FutureBuilder<CompanionInsights>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(message: e is ApiException ? e.message : 'Could not load insights.', onRetry: () => _reload(_days));
          }
          final d = snap.data!;
          final points = [
            for (final x in d.days)
              if (x.mood != null) TrendPoint(x.day, [x.mood!])
          ];
          final maxTone = d.tones.isEmpty ? 1 : d.tones.first.count;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 14, label: Text('14 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => _reload(s.first),
            ),
            const SizedBox(height: 16),
            _card('Mood check-ins (1 = very low, 5 = very good)', TrendChart(points: points, color: AppColors.mind)),
            _card(
              'Feelings in your chats',
              d.tones.isEmpty
                  ? const Text('Talk to MindEase to see which feelings come up most.',
                      style: TextStyle(color: AppColors.textMuted))
                  : Column(children: [
                      for (final t in d.tones.take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            SizedBox(width: 110, child: Text(_toneLabels[t.name] ?? t.name)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: t.count / maxTone,
                                  minHeight: 10,
                                  backgroundColor: AppColors.mindTint,
                                  color: AppColors.mind,
                                ),
                              ),
                            ),
                            SizedBox(width: 30, child: Text(' ${t.count}', textAlign: TextAlign.right)),
                          ]),
                        ),
                    ]),
            ),
            if (d.themes.isNotEmpty)
              _card(
                'What you talked about most',
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in d.themes)
                    Chip(label: Text('${_themeLabels[t.name] ?? t.name} · ${t.count}'), backgroundColor: AppColors.mindTint),
                ]),
              ),
            Text(d.note, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]);
        },
      ),
    );
  }

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8EC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 12),
          child,
        ]),
      );
}
