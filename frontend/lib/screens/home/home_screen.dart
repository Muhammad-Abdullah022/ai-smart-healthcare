import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../providers/auth_provider.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/medical_disclaimer.dart';
import '../../widgets/pulse_line.dart';
import '../../widgets/section_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<List<Dose>> _doses =
      MedicineRepository(context.read<AuthProvider>().repository.api).today().catchError((_) => <Dose>[]);

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(greeting: _greeting, name: user?.firstName ?? 'there', doses: _doses),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SosStrip(),
                const SizedBox(height: 24),
                const Text('Quick actions',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(child: _QuickAction(Icons.sick_outlined, 'Check symptoms', 1, AppColors.diagnosis, AppColors.diagnosisTint)),
                    SizedBox(width: 10),
                    Expanded(child: _QuickAction(Icons.medication_outlined, 'Medicines', 35, AppColors.medicine, AppColors.medicineTint)),
                    SizedBox(width: 10),
                    Expanded(child: _QuickAction(Icons.mood, 'Log mood', 24, AppColors.mind, AppColors.mindTint)),
                    SizedBox(width: 10),
                    Expanded(child: _QuickAction(Icons.monitor_heart_outlined, 'Readings', 41, AppColors.records, AppColors.recordsTint)),
                  ],
                ),
                const SizedBox(height: 28),
                const Text('Your health areas',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 12),
                for (final module in healthModules) ...[
                  _ModuleCard(module: module),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                const MedicalDisclaimer(compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one bold moment: deep navy header with a teal heartbeat line.
class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.name, required this.doses});

  final String greeting;
  final String name;
  final Future<List<Dose>> doses;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 12, 12, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDeep],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(greeting, style: const TextStyle(color: Color(0xFFB8C7D9), fontSize: 15)),
              ),
              IconButton(
                tooltip: 'Search',
                color: Colors.white,
                icon: const Icon(Icons.search),
                onPressed: () => context.push('/search'),
              ),
              IconButton(
                tooltip: 'Settings',
                color: Colors.white,
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          Text(name,
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 4),
          const PulseLine(),
          const SizedBox(height: 4),
          FutureBuilder<List<Dose>>(
            future: doses,
            builder: (context, snap) {
              final list = snap.data ?? const <Dose>[];
              final left = list.where((d) => d.status == 'due' || d.status == 'upcoming').length;
              final missed = list.where((d) => d.status == 'missed').length;
              final text = !snap.hasData
                  ? 'Loading today…'
                  : list.isEmpty
                      ? 'No medicines scheduled today'
                      : missed > 0
                          ? '$missed missed · $left still to take today'
                          : left == 0
                              ? 'All of today\'s medicines are done'
                              : '$left medicine dose${left == 1 ? '' : 's'} left today';
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/feature/36'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(missed > 0 ? Icons.error_outline : Icons.medication,
                          size: 18, color: missed > 0 ? const Color(0xFFFCA5A5) : AppColors.accent),
                      const SizedBox(width: 8),
                      Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SosStrip extends StatelessWidget {
  const _SosStrip();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: const Color(0xFFFFF1F1),
      onTap: () => context.push('/feature/12'),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.critical,
            child: Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need help now?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('Emergency numbers and your contacts', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.critical),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.feature, this.color, this.tint);

  final IconData icon;
  final String label;
  final int feature;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      onTap: () => context.push('/feature/$feature'),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        children: [
          IconBadge(icon: icon, color: color, background: tint),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final HealthModule module;

  @override
  Widget build(BuildContext context) {
    final ready = module.features.where((f) => f.status == FeatureStatus.available).length;
    return SectionCard(
      onTap: () => context.push('/module/${module.id}'),
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 88,
            height: 92,
            decoration: BoxDecoration(
              color: module.tint,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
            ),
            child: Icon(module.icon, color: module.color, size: 36),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(module.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(module.subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ready / module.features.length,
                    minHeight: 5,
                    color: module.color,
                    backgroundColor: module.tint,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.chevron_right, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
