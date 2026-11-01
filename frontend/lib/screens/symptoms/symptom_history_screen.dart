import 'package:flutter/material.dart';

import '../../models/assessment.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';
import 'symptom_result_screen.dart';
import 'triage_style.dart';

/// The user's own past symptom checks.
class SymptomHistoryScreen extends StatefulWidget {
  const SymptomHistoryScreen({super.key, required this.repository});

  final AssessmentRepository repository;

  @override
  State<SymptomHistoryScreen> createState() => _SymptomHistoryScreenState();
}

class _SymptomHistoryScreenState extends State<SymptomHistoryScreen> {
  late Future<List<AssessmentSummary>> _future = widget.repository.history();

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _open(String id) async {
    try {
      final full = await widget.repository.getById(id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SymptomResultScreen(assessment: full)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past symptom checks')),
      body: FutureBuilder<List<AssessmentSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(
              message: e is ApiException ? e.message : 'Could not load your history.',
              onRetry: () => setState(() => _future = widget.repository.history()),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.history,
              title: 'No checks yet',
              message: 'Your symptom checks will be saved here privately.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              final style = TriageStyle.of(item.triageLevel);
              return SectionCard(
                onTap: () => _open(item.id),
                child: Row(
                  children: [
                    IconBadge(icon: style.icon, color: style.color, background: style.background),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.symptoms,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('${style.label} · ${_date(item.createdAt)}',
                              style: TextStyle(color: style.color, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
