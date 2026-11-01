import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Standard layout for every feature: a large, calm title, one muted sentence about
/// what the screen does, an optional quiet note, then the content. No coloured bands.
class FeaturePage extends StatelessWidget {
  const FeaturePage({
    super.key,
    required this.title,
    required this.purpose,
    required this.icon,
    required this.color,
    required this.tint,
    required this.children,
    this.actions,
    this.floatingActionButton,
    this.notice,
  });

  final String title;
  final String purpose;
  final IconData icon;
  final Color color;
  final Color tint;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(actions: actions),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.2, letterSpacing: -0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(purpose, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textMuted)),
          if (notice != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                ),
                Expanded(
                  child: Text(notice!, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textMuted)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}
