import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../widgets/feature_page.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';

/// One health area: all its features in a single calm list.
class ModuleScreen extends StatelessWidget {
  const ModuleScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    final module = moduleById(moduleId);
    if (module == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(title: 'Area not found', message: 'Go back and choose a health area.'),
      );
    }
    return FeaturePage(
      title: module.title,
      purpose: '${module.subtitle}.',
      icon: module.icon,
      color: module.color,
      tint: module.tint,
      children: [
        if (module.id == 'diagnosis') ...[
          const _AssistantHero(),
          const SizedBox(height: 16),
        ],
        GroupedList(children: [
          for (final f in module.features)
            // Features 2–5 (questions, prediction, triage, tests) live inside the Symptom Checker chat.
            // Feature 13 (the assistant) is the large card above.
            if (!mergedIntoSymptomChecker.contains(f.number) && !(module.id == 'diagnosis' && f.number == 13))
              FeatureTile(feature: f, color: module.color, tint: module.tint, inGroup: true),
        ]),
      ],
    );
  }
}

/// Big entry card for the AI Health Assistant chatbot.
class _AssistantHero extends StatelessWidget {
  const _AssistantHero();

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/feature/13'),
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.forum_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('AI Health Assistant',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('English · اردو · Roman Urdu', style: TextStyle(color: Color(0xFFB8C7D9), fontSize: 13)),
                ]),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white),
            ]),
            const SizedBox(height: 14),
            const Wrap(spacing: 8, runSpacing: 8, children: [
              _HeroChip(icon: Icons.chat_bubble_outline, label: 'Ask anything'),
              _HeroChip(icon: Icons.mic_none, label: 'Voice message'),
              _HeroChip(icon: Icons.volume_up_outlined, label: 'Reads aloud'),
              _HeroChip(icon: Icons.upload_file_outlined, label: 'Upload report'),
              _HeroChip(icon: Icons.compare_arrows, label: 'Old vs new'),
              _HeroChip(icon: Icons.history, label: 'History'),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// One feature row. Inside a module it is a plain row; on its own (search) it gets a card.
class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.feature,
    this.color = AppColors.accent,
    this.tint = AppColors.accentTint,
    this.inGroup = false,
  });

  final HealthFeature feature;
  final Color color;
  final Color tint;
  final bool inGroup;

  @override
  Widget build(BuildContext context) {
    final row = ListRow(
      icon: feature.icon,
      title: feature.title,
      subtitle: feature.number == 1
          ? 'Chat: follow-up questions, risk, triage and test suggestions'
          : feature.status == FeatureStatus.prototype
              ? 'Prototype'
              : null,
      color: color,
      tint: tint,
      onTap: () => context.push('/feature/${feature.number}'),
    );
    return inGroup ? row : SectionCard(padding: EdgeInsets.zero, child: row);
  }
}

/// Kept for screens that still show a status label.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final FeatureStatus status;

  @override
  Widget build(BuildContext context) {
    if (status != FeatureStatus.prototype) return const SizedBox.shrink();
    return const Text('Prototype', style: TextStyle(color: Color(0xFFB45309), fontSize: 12));
  }
}
