import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Logo + title shown at the top of login / register / reset screens.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.health_and_safety_outlined, color: AppColors.accent, size: 30),
        ),
        const SizedBox(height: 24),
        Text(title,
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
        const SizedBox(height: 6),
        Text(subtitle, style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 28),
      ],
    );
  }
}
