import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/confirm_dialog.dart';
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
        appBar: AppBar(title: const Text('My medicines')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add medicine', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: Column(children: [
          // Pill-style tabs
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(16)),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppColors.softShadow,
              ),
              labelColor: AppColors.deep,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              tabs: const [Tab(height: 40, text: 'Today'), Tab(height: 40, text: 'All medicines')],
            ),
          ),
          Expanded(
            child: TabBarView(children: [_todayTab(), _allTab()]),
          ),
        ]),
      ),
    );
  }

  Widget _todayTab() => FutureBuilder<List<Dose>>(
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
          final groups = <String, List<Dose>>{};
          for (final d in doses) {
            groups.putIfAbsent(_partOfDay(d.time), () => []).add(d);
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _ProgressCard(doses: doses),
                const SizedBox(height: 18),
                for (final part in const ['Morning', 'Afternoon', 'Evening', 'Night'])
                  if (groups[part] != null) ...[
                    _partHeader(part),
                    for (final d in groups[part]!) _DoseTile(dose: d, onLog: (st) => _log(d, st)),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      );

  Widget _partHeader(String part) {
    final icon = switch (part) {
      'Morning' => Icons.wb_twilight_rounded,
      'Afternoon' => Icons.wb_sunny_rounded,
      'Evening' => Icons.wb_cloudy_outlined,
      _ => Icons.nightlight_round,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.medicine),
        const SizedBox(width: 6),
        Text(part, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.deep)),
      ]),
    );
  }

  Widget _allTab() => FutureBuilder<List<Medicine>>(
        future: _list,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(message: 'Could not load medicines.', onRetry: _reload);
          final meds = snap.data!;
          if (meds.isEmpty) {
            return EmptyView(
                icon: Icons.medication_outlined,
                title: 'No medicines yet',
                message: 'Scan a prescription or add a medicine.',
                actionLabel: 'Add medicine',
                onAction: _add);
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [for (final m in meds) _MedicineCard(medicine: m, onStop: () => _stop(m))],
            ),
          );
        },
      );
}

String _partOfDay(String hhmm) {
  final h = int.tryParse(hhmm.split(':').first) ?? 0;
  if (h >= 4 && h < 12) return 'Morning';
  if (h >= 12 && h < 17) return 'Afternoon';
  if (h >= 17 && h < 21) return 'Evening';
  return 'Night';
}

/// "19:00" -> ("7:00", "PM")
(String, String) _clock(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first) ?? 0;
  final m = p.length > 1 ? p[1] : '00';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return ('$h12:$m', h < 12 ? 'AM' : 'PM');
}

IconData _formIcon(String form) => switch (form) {
      'syrup' => Icons.local_drink_outlined,
      'injection' => Icons.vaccines_outlined,
      'drops' => Icons.water_drop_outlined,
      'inhaler' => Icons.air_rounded,
      'cream' => Icons.back_hand_outlined,
      _ => Icons.medication_rounded,
    };

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.doses});
  final List<Dose> doses;

  @override
  Widget build(BuildContext context) {
    final taken = doses.where((d) => d.status == 'taken').length;
    final missed = doses.where((d) => d.status == 'missed').length;
    final left = doses.where((d) => d.status == 'due' || d.status == 'upcoming').length;
    final done = taken == doses.length;
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
            colors: [AppColors.deep, AppColors.primaryDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(children: [
        SizedBox(
          width: 78,
          height: 78,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: doses.isEmpty ? 0 : taken / doses.length,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white.withAlpha(40),
                valueColor: const AlwaysStoppedAnimation(AppColors.softGreen),
              ),
            ),
            Text('$taken/${doses.length}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}',
                style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(done ? 'All doses taken today' : 'Doses taken today',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (left > 0) _chip('$left left', Colors.white.withAlpha(36)),
              if (missed > 0) _chip('$missed missed', AppColors.critical.withAlpha(150)),
              if (done) _chip('Well done!', Colors.white.withAlpha(36)),
            ]),
          ]),
        ),
      ]),
    );
  }

  static Widget _chip(String t, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose, required this.onLog});

  final Dose dose;
  final void Function(String status) onLog;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (dose.status) {
      'taken' => (AppColors.success, Icons.check_circle_rounded, 'Taken'),
      'skipped' => (AppColors.textMuted, Icons.remove_circle_outline, 'Skipped'),
      'missed' => (AppColors.critical, Icons.error_outline_rounded, 'Missed'),
      'due' => (AppColors.warning, Icons.alarm_rounded, 'Due now'),
      _ => (AppColors.textMuted, Icons.schedule_rounded, 'Upcoming'),
    };
    final open = dose.status != 'taken' && dose.status != 'skipped';
    final (time, ampm) = _clock(dose.time);
    final faded = dose.status == 'taken' || dose.status == 'skipped';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dose.status == 'due' ? AppColors.warning : AppColors.border,
            width: dose.status == 'due' ? 1.5 : 1),
        boxShadow: faded ? null : AppColors.softShadow,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          // Time block
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: faded ? AppColors.background : AppColors.accentTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text(time,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: faded ? AppColors.textMuted : AppColors.deep)),
              Text(ampm, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dose.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: faded ? AppColors.textMuted : AppColors.deep,
                      decoration: dose.status == 'taken' ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textMuted)),
              if (dose.strength.isNotEmpty)
                Text(dose.strength, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ]),
        if (open) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => onLog('skipped'),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Skip'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => onLog('taken'),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Mark as taken', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  const _MedicineCard({required this.medicine, required this.onStop});
  final Medicine medicine;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    int? total, done;
    if (m.startDate != null && m.endDate != null) {
      final t = m.endDate!.difference(m.startDate!).inDays + 1;
      total = t;
      done = (day0.difference(m.startDate!).inDays + 1).clamp(0, t).toInt();
    }
    final sub = [m.salt, m.form].where((s) => s.isNotEmpty && s.toLowerCase() != m.name.toLowerCase()).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.medicineTint, borderRadius: BorderRadius.circular(14)),
            child: Icon(_formIcon(m.form), color: AppColors.medicine),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.deep)),
              if (m.strength.isNotEmpty || sub.isNotEmpty)
                Text([m.strength, sub].where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ]),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
            onSelected: (_) => onStop(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'stop',
                child: Row(children: [
                  Icon(Icons.stop_circle_outlined, color: AppColors.critical),
                  SizedBox(width: 8),
                  Text('Stop medicine'),
                ]),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in m.times)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.alarm_rounded, size: 14, color: AppColors.accent),
                const SizedBox(width: 4),
                Text('${_clock(t).$1} ${_clock(t).$2}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.deep)),
              ]),
            ),
        ]),
        if (m.instructions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
                child: Text(m.instructions,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.35))),
          ]),
        ],
        if (total != null && done != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Day $done of $total',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.deep)),
                const Spacer(),
                Text(total - done == 0 ? 'Last day' : '${total - done} days left',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 6,
                  backgroundColor: AppColors.primaryTint,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Text('Ongoing — no end date', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
        if (m.allergyWarning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.criticalTint, borderRadius: BorderRadius.circular(10)),
            child: Text(m.allergyWarning!, style: const TextStyle(color: AppColors.critical, fontSize: 12)),
          ),
        ],
      ]),
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
