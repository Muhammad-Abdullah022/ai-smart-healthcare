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
        if (module.id == 'mental')
          // Mental Health = the MindEase module only (check-in, tips, chat, memory, insights).
          const _MindEaseHero()
        else
          GroupedList(children: [
            for (final f in module.features)
              // Features 2–5 (questions, prediction, triage, tests) live inside the Symptom Checker chat.
              // Features 1 and 13 (symptom checker + assistant) are the large card above.
              if (isListedFeature(f) && !(module.id == 'diagnosis' && (f.number == 13 || f.number == 1)))
                FeatureTile(feature: f, color: module.color, tint: module.tint, inGroup: true),
          ]),
      ],
    );
  }
}

/// The Mental Health section: one large entry into MindEase, plus quick help.
class _MindEaseHero extends StatelessWidget {
  const _MindEaseHero();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/feature/17'),
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF5B4BC4), Color(0xFF7C6BD9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.spa_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MindEase', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('Your mental wellbeing companion', style: TextStyle(color: Color(0xFFE4DFFB), fontSize: 13)),
                  ]),
                ),
                const Icon(Icons.arrow_forward, color: Colors.white),
              ]),
              const SizedBox(height: 14),
              const Text('How are you feeling today? Check in, get a few gentle steps, and talk it through.',
                  style: TextStyle(color: Colors.white, height: 1.4)),
              const SizedBox(height: 12),
              const Wrap(spacing: 8, runSpacing: 8, children: [
                _HeroChip(icon: Icons.mood_outlined, label: 'Mood check-in'),
                _HeroChip(icon: Icons.lightbulb_outline, label: 'Tips'),
                _HeroChip(icon: Icons.forum_outlined, label: 'Chat'),
                _HeroChip(icon: Icons.psychology_alt_outlined, label: 'Remembers you'),
                _HeroChip(icon: Icons.insights_outlined, label: 'Insights'),
              ]),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.air),
            label: const Text('Guided breathing'),
            onPressed: () => context.push('/feature/22'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46), foregroundColor: AppColors.critical),
            icon: const Icon(Icons.support_agent),
            label: const Text('Get help now'),
            onPressed: () => context.push('/feature/25'),
          ),
        ),
      ]),
    ]);
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
                  Text('Symptoms, questions, reports · English · اردو · Roman Urdu', style: TextStyle(color: Color(0xFFB8C7D9), fontSize: 13)),
                ]),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white),
            ]),
            const SizedBox(height: 14),
            const Wrap(spacing: 8, runSpacing: 8, children: [
              _HeroChip(icon: Icons.chat_bubble_outline, label: 'Ask anything'),
              _HeroChip(icon: Icons.sick_outlined, label: 'Symptom check'),
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
