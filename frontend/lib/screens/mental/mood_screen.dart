import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/mental_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';

const _moodEmoji = ['😞', '🙁', '😐', '🙂', '😄'];
const _moodLabel = ['Very bad', 'Bad', 'Okay', 'Good', 'Very good'];

/// Feature 24: daily mood tracking with a 14-day chart.
class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key, this.repository});

  final MentalRepository? repository;

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  late final MentalRepository _repo =
      widget.repository ?? MentalRepository(context.read<AuthProvider>().repository.api);
  late Future<List<MoodEntry>> _future = _repo.moods(days: 14);
  final _note = TextEditingController();
  int? _selected;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      await _repo.saveMood(_selected! + 1, _note.text.trim());
      if (!mounted) return;
      showMessage(context, 'Mood saved for today');
      setState(() => _future = _repo.moods(days: 14));
    } on ApiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
      if (e.code == 'consent_required') context.push('/settings/consent');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily mood')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('How are you feeling today?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 5; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selected = i),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selected == i ? AppColors.accentTint : null,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _selected == i ? AppColors.accent : Colors.transparent),
                    ),
                    child: Column(
                      children: [
                        Text(_moodEmoji[i], style: const TextStyle(fontSize: 30)),
                        Text(_moodLabel[i], style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(hintText: 'Add a note (optional)'),
          ),
          AppButton(label: 'Save today', loading: _saving, onPressed: _selected == null ? null : _save),
          const SizedBox(height: 24),
          const Text('Last 14 days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          FutureBuilder<List<MoodEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 160, child: LoadingView());
              }
              if (snap.hasError) {
                final e = snap.error;
                return Text(e is ApiException ? e.message : 'Could not load your moods.',
                    style: const TextStyle(color: AppColors.textMuted));
              }
              return SectionCard(child: MoodChart(entries: snap.data!));
            },
          ),
        ],
      ),
    );
  }
}

/// Simple bar chart drawn with containers (no chart package needed).
class MoodChart extends StatelessWidget {
  const MoodChart({super.key, required this.entries});

  final List<MoodEntry> entries;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final byDay = {for (final e in entries) DateUtils.dateOnly(e.day): e.mood};
    final days = [for (var i = 13; i >= 0; i--) DateUtils.dateOnly(today.subtract(Duration(days: i)))];
    if (byDay.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No moods saved yet. Your chart will appear here.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    final average = byDay.values.reduce((a, b) => a + b) / byDay.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: byDay[d] == null ? 'No entry' : _moodLabel[byDay[d]! - 1],
                      child: Container(
                        height: byDay[d] == null ? 4 : 20.0 * byDay[d]!,
                        decoration: BoxDecoration(
                          color: byDay[d] == null
                              ? AppColors.border
                              : (byDay[d]! >= 4 ? AppColors.accent : byDay[d]! == 3 ? AppColors.warning : AppColors.critical),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Average: ${average.toStringAsFixed(1)} / 5 over ${byDay.length} days',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }
}
