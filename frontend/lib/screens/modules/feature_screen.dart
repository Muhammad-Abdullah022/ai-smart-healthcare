import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../widgets/medical_disclaimer.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';
import 'module_screen.dart';

/// Detail page for one feature.
///
/// Features are being built one by one (see the Excel tracker). Until a feature
/// is implemented, this page says so honestly instead of showing fake results.
/// The SOS feature (12) always shows emergency numbers, even before it is built.
class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key, required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    HealthFeature? feature;
    for (final f in allFeatures) {
      if (f.number == number) feature = f;
    }
    if (feature == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(title: 'Feature not found', message: 'This feature does not exist.'),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(feature.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (number == 12) ...[const EmergencyNumbersCard(), const SizedBox(height: 16)],
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: feature.icon, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Feature ${feature.number}',
                          style: const TextStyle(color: AppColors.textMuted)),
                    ),
                    StatusChip(status: feature.status),
                  ],
                ),
                const SizedBox(height: 16),
                Text(feature.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  'This feature is being built. It will appear here as soon as it is ready and tested.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.4),
                ),
                if (feature.note != null) ...[
                  const SizedBox(height: 12),
                  Text('Note: ${feature.note}', style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const MedicalDisclaimer(),
        ],
      ),
    );
  }
}

/// Emergency numbers for Pakistan.
/// TODO(E-12): verify numbers against an official source before release (see tracker).
class EmergencyNumbersCard extends StatelessWidget {
  const EmergencyNumbersCard({super.key});

  @override
  Widget build(BuildContext context) {
    const numbers = [
      ('Rescue / Ambulance', '1122'),
      ('Edhi Ambulance', '115'),
      ('Police', '15'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.criticalTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.critical),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('If this is an emergency, call now',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.critical, fontSize: 16)),
          const SizedBox(height: 12),
          for (final (label, phone) in numbers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: AppColors.critical, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                  Text(phone, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
