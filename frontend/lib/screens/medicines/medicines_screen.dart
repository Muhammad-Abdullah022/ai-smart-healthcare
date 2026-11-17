import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';
import '../prescriptions/prescription_reader_screen.dart';
import 'add_medicine_screen.dart';

/// Features 33, 35, 36: today's doses (mark taken/skipped, missed alerts) and the medicine list.
class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({super.key, this.repository});

  final MedicineRepository? repository;

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  late final MedicineRepository _repo =
      widget.repository ?? MedicineRepository(context.read<AuthProvider>().repository.api);
  late Future<List<Dose>> _today = _repo.today();
  late Future<List<Medicine>> _list = _repo.list();

  void _reload() => setState(() {
        _today = _repo.today();
        _list = _repo.list();
      });

  Future<void> _log(Dose d, String status) async {
    try {
      await _repo.logIntake(d.medicineId, d.time, status);
      _reload();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _stop(Medicine m) async {
    final ok = await showConfirmDialog(context,
        title: 'Stop ${m.name}?',
        message: 'It will be removed from your schedule. Your history is kept. '
            'Only stop a medicine if your doctor has told you to.',
        confirmLabel: 'Stop',
        destructive: true);
    if (!ok) return;
    try {
      await _repo.stop(m.id);
      _reload();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  /// Add medicines: scan a prescription photo (the AI reads it, you check it, reminders are made)
  /// or add them one by one.
  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add medicines', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _AddOption(
              icon: Icons.document_scanner_outlined,
              title: 'Scan a prescription',
              subtitle: 'Take or upload a photo — the AI reads every medicine, you check it, reminders are set',
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            const SizedBox(height: 10),
            _AddOption(
              icon: Icons.edit_note_outlined,
              title: 'Add one by one',
              subtitle: 'Type the medicine name, strength, how often, before/after food and for how many days',
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'scan') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrescriptionReaderScreen()));
      _reload();
      return;
    }
    final added = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => AddMedicineScreen(repository: _repo)));
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My medicines'),
          bottom: const TabBar(tabs: [Tab(text: 'Today'), Tab(text: 'All medicines')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add medicine'),
        ),
        body: TabBarView(
          children: [
            FutureBuilder<List<Dose>>(
              future: _today,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) {
                  final e = snap.error;
                  return ErrorView(message: e is ApiException ? e.message : 'Could not load today.', onRetry: _reload);
                }
                final doses = snap.data!;
                if (doses.isEmpty) {
                  return EmptyView(
                    icon: Icons.medication_outlined,
                    title: 'No doses today',
                    message: 'Add your medicines and their times to see your daily schedule.',
                    actionLabel: 'Add medicine',
                    onAction: _add,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [for (final d in doses) _DoseTile(dose: d, onLog: (s) => _log(d, s))],
                  ),
                );
              },
            ),
            FutureBuilder<List<Medicine>>(
              future: _list,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) return ErrorView(message: 'Could not load medicines.', onRetry: _reload);
                final meds = snap.data!;
                if (meds.isEmpty) {
                  return const EmptyView(
                      icon: Icons.medication_outlined, title: 'No medicines yet', message: 'Tap "Add medicine".');
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    for (final m in meds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const IconBadge(icon: Icons.medication),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${m.name} ${m.strength}'.trim(),
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                        Text(
                                            [m.salt, m.form, if (m.instructions.isNotEmpty) m.instructions]
                                                .where((s) => s.isNotEmpty)
                                                .join(' · '),
                                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Stop medicine',
                                    icon: const Icon(Icons.stop_circle_outlined, color: AppColors.critical),
                                    onPressed: () => _stop(m),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, children: [for (final t in m.times) Chip(label: Text(t))]),
                              if (m.allergyWarning != null)
                                Text(m.allergyWarning!,
                                    style: const TextStyle(color: AppColors.critical, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose, required this.onLog});

  final Dose dose;
  final void Function(String status) onLog;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (dose.status) {
      'taken' => (AppColors.success, Icons.check_circle, 'Taken'),
      'skipped' => (AppColors.textMuted, Icons.remove_circle_outline, 'Skipped'),
      'missed' => (AppColors.critical, Icons.error_outline, 'Missed'),
      'due' => (AppColors.warning, Icons.alarm, 'Due now'),
      _ => (AppColors.primary, Icons.schedule, 'Upcoming'),
    };
    final open = dose.status != 'taken' && dose.status != 'skipped';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Row(
          children: [
            Text(dose.time, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${dose.name} ${dose.strength}'.trim(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Row(children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(label, style: TextStyle(color: color, fontSize: 12)),
                  ]),
                ],
              ),
            ),
            if (open) ...[
              IconButton(
                tooltip: 'Skip',
                icon: const Icon(Icons.close, color: AppColors.textMuted),
                onPressed: () => onLog('skipped'),
              ),
              FilledButton(
                onPressed: () => onLog('taken'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                child: const Text('Taken'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _AddOption extends StatelessWidget {
  const _AddOption({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.deep)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.3)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ]),
          ),
        ),
      );
}
