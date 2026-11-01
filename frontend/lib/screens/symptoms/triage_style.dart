import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Colors, labels and advice for the 4 triage levels (feature 4).
class TriageStyle {
  const TriageStyle(this.label, this.advice, this.color, this.background, this.icon);

  final String label;
  final String advice;
  final Color color;
  final Color background;
  final IconData icon;

  static TriageStyle of(String level) => switch (level) {
        'critical' => const TriageStyle('Critical', 'Call 1122 or go to an emergency department now.',
            AppColors.critical, AppColors.criticalTint, Icons.emergency),
        'urgent' => const TriageStyle('Urgent', 'See a doctor today.', Color(0xFFEA580C),
            Color(0xFFFFEDD5), Icons.priority_high),
        'moderate' => const TriageStyle('Moderate', 'See a doctor within 1–3 days.', Color(0xFFB45309),
            AppColors.warningTint, Icons.schedule),
        _ => const TriageStyle('Routine', 'Self-care or a routine appointment is usually enough.',
            AppColors.success, Color(0xFFDCFCE7), Icons.check_circle_outline),
      };
}
