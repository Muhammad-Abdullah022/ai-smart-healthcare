import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to log in again to see your health data.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (ok) await auth.logout(); // the router returns to the login screen
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email'),
                  subtitle: Text(user?.email ?? ''),
                  trailing: user == null || user.emailVerified
                      ? null
                      : const Text('Not verified', style: TextStyle(color: AppColors.warning)),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.language),
                  title: Text('Language'),
                  subtitle: Text('English (Urdu and Roman Urdu coming soon)'),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.notifications_outlined),
                  title: Text('Notifications'),
                  subtitle: Text('Reminder settings arrive with medicine reminders'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Privacy & consent'),
                  subtitle: const Text('Choose what the app may use. Everything is off until you allow it.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/consent'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.critical),
              title: const Text('Log out', style: TextStyle(color: AppColors.critical)),
              onTap: () => _logout(context),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('${AppConfig.appName} · version 0.1.0',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
