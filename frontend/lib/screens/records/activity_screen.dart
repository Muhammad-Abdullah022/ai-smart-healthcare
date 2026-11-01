import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/feature_page.dart';
import '../../widgets/section_card.dart';

/// Feature 49: everything important that happened in your account, newest first.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final Future<List<dynamic>> _future =
      context.read<AuthProvider>().repository.api.get('/profile/activity').then((v) => v as List<dynamic>);

  static const _labels = {
    'user.register': ('Account created', Icons.person_add_alt),
    'user.login': ('Logged in', Icons.login),
    'user.login_failed': ('Failed login attempt', Icons.gpp_maybe_outlined),
    'user.logout': ('Logged out', Icons.logout),
    'profile.update': ('Profile updated', Icons.edit_outlined),
    'assessment.create': ('Symptom check', Icons.sick_outlined),
    'consent.change': ('Privacy setting changed', Icons.lock_outline),
    'mental.screening': ('Mental health check', Icons.psychology_outlined),
    'medicine.add': ('Medicine added', Icons.medication_outlined),
    'sos.trigger': ('SOS pressed', Icons.sos),
  };

  @override
  Widget build(BuildContext context) {
    final module = moduleOf(49);
    return FeaturePage(
      title: 'Decision history',
      purpose: 'A record of important actions in your account, so you always know what happened and when.',
      icon: Icons.manage_history,
      color: module.color,
      tint: module.tint,
      children: [
        FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            if (snap.hasError) {
              final e = snap.error;
              return Text(e is ApiException ? e.message : 'Could not load your history.');
            }
            return Column(
              children: [
                for (final item in snap.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon((_labels[(item as Map)['action']]?.$2) ?? Icons.history, color: module.color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_labels[item['action']]?.$1 ?? '${item['action']}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Text(
                            DateTime.parse('${item['created_at']}').toLocal().toString().substring(0, 16),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
