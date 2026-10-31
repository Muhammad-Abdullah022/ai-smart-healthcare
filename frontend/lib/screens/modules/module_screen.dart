import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';

/// Lists every feature in one health module.
class ModuleScreen extends StatelessWidget {
  const ModuleScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    final module = moduleById(moduleId);
    if (module == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(title: 'Module not found', message: 'This module does not exist.'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: module.features.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => FeatureTile(feature: module.features[i], color: module.color),
      ),
    );
  }
}

/// One feature row. Also used on the search screen.
class FeatureTile extends StatelessWidget {
  const FeatureTile({super.key, required this.feature, this.color = AppColors.accent});

  final HealthFeature feature;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      onTap: () => context.push('/feature/${feature.number}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconBadge(icon: feature.icon, color: color, background: AppColors.primaryTint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          StatusChip(status: feature.status),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final FeatureStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color fg, Color bg) = switch (status) {
      FeatureStatus.available => ('Ready', AppColors.success, const Color(0xFFDCFCE7)),
      FeatureStatus.inDevelopment => ('Coming soon', AppColors.primary, AppColors.primaryTint),
      FeatureStatus.prototype => ('Prototype', const Color(0xFFB45309), AppColors.warningTint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
