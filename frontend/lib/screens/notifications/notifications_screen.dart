import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/account_repository.dart';
import '../../services/api_client.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';

/// Notification center (B-15): reminders, alerts and updates from the backend.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final AccountRepository _repo = AccountRepository(context.read<AuthProvider>().repository.api);
  late Future<List<AppNotification>> _future = _repo.notifications();

  void _reload() => setState(() => _future = _repo.notifications());

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      try {
        await _repo.markRead(n.id);
      } on ApiException {
        // Not critical; still open the link.
      }
    }
    if (!mounted) return;
    if (n.link != null) await context.push(n.link!);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await _repo.markAllRead();
              _reload();
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(message: e is ApiException ? e.message : 'Could not load notifications.', onRetry: _reload);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.notifications_none,
              title: "You're all caught up",
              message: 'Medicine reminders, appointment updates and health alerts will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = items[i];
                return SectionCard(
                  onTap: () => _open(n),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(n.read ? Icons.notifications_none : Icons.notifications_active,
                          color: n.read ? AppColors.textMuted : AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title,
                                style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(n.body, style: const TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
