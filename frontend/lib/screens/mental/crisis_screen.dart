import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/mental_repository.dart';
import '../../widgets/section_card.dart';

/// Feature 25: crisis support and professional referral.
/// Always shows something, even offline (falls back to built-in emergency numbers).
class CrisisScreen extends StatefulWidget {
  const CrisisScreen({super.key, this.repository});

  final MentalRepository? repository;

  @override
  State<CrisisScreen> createState() => _CrisisScreenState();
}

class _CrisisScreenState extends State<CrisisScreen> {
  late final MentalRepository _repo =
      widget.repository ?? MentalRepository(context.read<AuthProvider>().repository.api);
  late final Future<CrisisResources> _future = _repo.crisisResources();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Get help now')),
      body: FutureBuilder<CrisisResources>(
        future: _future,
        initialData: CrisisResources.offline,
        builder: (context, snap) {
          final r = snap.data ?? CrisisResources.offline;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                    const Text('You are not alone',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.critical)),
                    const SizedBox(height: 8),
                    Text(r.note, style: const TextStyle(height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Emergency (24/7)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              for (final line in r.emergency) _LineTile(line: line, urgent: true),
              if (r.support.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Talk to a counsellor', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                for (final line in r.support) _LineTile(line: line),
              ],
              const SizedBox(height: 16),
              const SectionCard(
                child: Text(
                  'Other steps that help right now:\n'
                  '• Stay with someone, or call a friend or family member.\n'
                  '• Move away from anything you could use to hurt yourself.\n'
                  '• A doctor at any hospital can refer you to a psychiatrist or psychologist.',
                  style: TextStyle(height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              Text('Numbers last checked: ${r.checked}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          );
        },
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, this.urgent = false});

  final HelpLine line;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AppColors.critical : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        child: Row(
          children: [
            Icon(Icons.phone, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(line.hours, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            SelectableText(line.phone,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}
