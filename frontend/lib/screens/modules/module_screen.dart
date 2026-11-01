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
        GroupedList(children: [
          for (final f in module.features) FeatureTile(feature: f, color: module.color, tint: module.tint, inGroup: true),
        ]),
      ],
    );
  }
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
      subtitle: feature.status == FeatureStatus.prototype ? 'Prototype' : null,
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
