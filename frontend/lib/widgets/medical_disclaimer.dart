import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Shown on every screen that displays AI output.
/// Reminds the user that results are informational, not a diagnosis.
class MedicalDisclaimer extends StatelessWidget {
  const MedicalDisclaimer({super.key, this.compact = false});

  final bool compact;

  static const text =
      'This app gives health information only. It is not a medical diagnosis and does not '
      'replace a doctor. If you have severe or sudden symptoms, call 1122 or go to the '
      'nearest emergency department now.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: compact ? 12 : 13, color: AppColors.text, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
