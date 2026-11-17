import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/lab_repository.dart';
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
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionTitle('Account'),
          GroupedList(children: [
            ListRow(
              icon: Icons.email_outlined,
              title: 'Email',
              subtitle: user?.email ?? '',
              color: AppColors.primary,
              tint: AppColors.primaryTint,
              trailing: user == null || user.emailVerified
                  ? null
                  : const Text('Not verified', style: TextStyle(color: AppColors.warning, fontSize: 12)),
            ),
            ListRow(
              icon: Icons.person_outline,
              title: 'Edit profile',
              color: AppColors.primary,
              tint: AppColors.primaryTint,
              onTap: () => context.go('/profile'),
            ),
          ]),
          const SectionTitle('Privacy'),
          GroupedList(children: [
            ListRow(
              icon: Icons.lock_outline,
              title: 'Privacy & consent',
              subtitle: 'Choose what the app may use',
              onTap: () => context.push('/settings/consent'),
            ),
            ListRow(
              icon: Icons.manage_history,
              title: 'Account activity',
              subtitle: 'What happened in your account',
              onTap: () => context.push('/feature/49'),
            ),
          ]),
          const SectionTitle('App'),
          const GroupedList(children: [
            ListRow(
              icon: Icons.language,
              title: 'Language',
              subtitle: 'English · Urdu coming soon',
              color: AppColors.mind,
              tint: AppColors.mindTint,
            ),
            ListRow(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Medicine reminders and alerts',
              color: AppColors.medicine,
              tint: AppColors.medicineTint,
            ),
          ]),
          const SectionTitle('Demo'),
          const GroupedList(children: [_DemoPricesRow()]),
          const SizedBox(height: 24),
          GroupedList(children: [
            ListRow(
              icon: Icons.logout,
              title: 'Log out',
              color: AppColors.critical,
              tint: AppColors.criticalTint,
              trailing: const SizedBox.shrink(),
              onTap: () => _logout(context),
            ),
          ]),
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


/// Switch for estimated (demo) lab prices for labs that do not publish prices. On by default.
class _DemoPricesRow extends StatefulWidget {
  const _DemoPricesRow();

  @override
  State<_DemoPricesRow> createState() => _DemoPricesRowState();
}

class _DemoPricesRowState extends State<_DemoPricesRow> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    DemoPrices.enabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      icon: Icons.science_outlined,
      title: 'Estimated lab prices',
      subtitle: 'Shows an estimated (demo) price for labs that have not published prices. Always marked "demo".',
      color: const Color(0xFFC2410C),
      tint: const Color(0xFFFFEDD5),
      trailing: Switch(
        value: _on,
        onChanged: (v) {
          setState(() => _on = v);
          DemoPrices.set(v);
        },
      ),
    );
  }
}
