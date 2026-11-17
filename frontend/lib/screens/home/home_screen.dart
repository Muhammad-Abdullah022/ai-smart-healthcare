import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../providers/auth_provider.dart';
import '../../services/medicine_repository.dart';
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
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(child: _QuickAction(Icons.sick_outlined, 'Symptoms', 1, AppColors.diagnosis, AppColors.diagnosisTint)),
                    SizedBox(width: 10),
                    Expanded(child: _QuickAction(Icons.medication_outlined, 'Medicines', 35, AppColors.medicine, AppColors.medicineTint)),
                    SizedBox(width: 10),
                    Expanded(child: _QuickAction(Icons.mood, 'Log mood', 24, AppColors.mind, AppColors.mindTint)),
                    SizedBox(width: 10),
                    Expanded(child: _QuickAction(Icons.monitor_heart_outlined, 'Readings', 41, AppColors.records, AppColors.recordsTint)),
                  ],
                ),
                const SizedBox(height: 14),
                _BannerCard(
                  icon: Icons.forum_outlined,
                  title: 'Online consultations',
                  subtitle: 'Chat with a doctor, pay, get your prescription',
                  onTap: () => context.push('/consultations'),
                ),
                _BannerCard(
                  icon: Icons.support_agent_outlined,
                  title: 'Help & issues',
                  subtitle: 'Report a payment, doctor or app problem to the admin',
                  onTap: () => context.push('/issues'),
                ),
                const SectionTitle('Your health areas'),
                for (final m in healthModules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SectionCard(
                      padding: EdgeInsets.zero,
                      child: ListRow(
                        icon: m.icon,
                        title: m.title,
                        subtitle: m.subtitle,
                        color: m.color,
                        tint: m.tint,
                        onTap: () => context.push('/module/${m.id}'),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Health information only — not a diagnosis. In an emergency call 1122.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
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
                child: Text(greeting, style: const TextStyle(color: Color(0xFFB8C6CF), fontSize: 15)),
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
      color: const Color(0xFFFFF6F6),
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/feature/$feature'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32, // same height for one- and two-line labels keeps icons aligned
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.25, color: AppColors.text)),
            ),
          ],
        ),
      ),
    );
  }
}


class _BannerCard extends StatelessWidget {
  const _BannerCard(
      {required this.icon, required this.title, required this.subtitle, required this.onTap, this.dark = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.deep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dark ? AppColors.deep : AppColors.mint,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: dark ? Colors.white12 : Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: dark ? Colors.white : AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: fg)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: dark ? Colors.white70 : AppColors.textMuted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: fg),
            ]),
          ),
        ),
      ),
    );
  }
}
