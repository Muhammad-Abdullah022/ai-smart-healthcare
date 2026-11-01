import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Standard layout for every feature: a soft band in the module's colour with the
/// feature's icon, name and one plain sentence about what it does, then the content.
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

  /// Optional banner under the header, e.g. "Prototype: sample data".
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: floatingActionButton,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: tint,
            foregroundColor: AppColors.primary,
            actions: actions,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppColors.softShadow,
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      purpose,
                      style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (notice != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.science_outlined, size: 20, color: Color(0xFFB45309)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(notice!, style: const TextStyle(fontSize: 13, height: 1.4))),
                    ],
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      ),
    );
  }
}
