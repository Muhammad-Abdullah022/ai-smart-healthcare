import 'package:flutter/material.dart';

import '../../widgets/state_views.dart';

/// Notification center. Filled by reminders and alerts in later tasks (B-15, B-21).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const EmptyView(
        icon: Icons.notifications_none,
        title: "You're all caught up",
        message: 'Medicine reminders, appointment updates and health alerts will appear here.',
      ),
    );
  }
}
