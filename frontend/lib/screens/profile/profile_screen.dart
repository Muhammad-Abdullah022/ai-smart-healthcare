import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';

/// Shows the user's profile loaded from the backend.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Profile> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Profile> _load() => context.read<AuthProvider>().repository.getProfile();

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: FutureBuilder<Profile>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingView(message: 'Loading your profile...');
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return ErrorView(
              message: error is ApiException ? error.message : 'Could not load your profile.',
              onRetry: _reload,
            );
          }
          final profile = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(profile: profile),
                const SizedBox(height: 20),
                _InfoCard(title: 'Personal details', rows: [
                  ('Date of birth', profile.dateOfBirth ?? 'Not set'),
                  ('Gender', _gender(profile.gender)),
                  ('Phone', profile.phone ?? 'Not set'),
                ]),
                const SizedBox(height: 16),
                _InfoCard(title: 'Medical basics', rows: [
                  ('Blood group', profile.bloodGroup),
                  ('Allergies', profile.allergies.isEmpty ? 'None recorded' : profile.allergies.join(', ')),
                  ('Conditions', profile.conditions.isEmpty ? 'None recorded' : profile.conditions.join(', ')),
                ]),
                const SizedBox(height: 16),
                _InfoCard(
                  title: 'Emergency contacts',
                  rows: profile.emergencyContacts.isEmpty
                      ? [('Contacts', 'None added')]
                      : [
                          for (final c in profile.emergencyContacts)
                            (c.relation.isEmpty ? c.name : '${c.name} (${c.relation})', c.phone),
                        ],
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                  onPressed: () async {
                    final changed = await context.push<bool>('/profile/edit', extra: profile);
                    if (changed == true) _reload();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _gender(String? value) => switch (value) {
        'male' => 'Male',
        'female' => 'Female',
        'other' => 'Other',
        'prefer_not_to_say' => 'Prefer not to say',
        _ => 'Not set',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final initials = profile.fullName.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0]).join();
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Color(0xFFA9CDB0), fontSize: 12)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDeep],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.accent,
                child: Text(initials.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.fullName,
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(profile.email, style: const TextStyle(color: Color(0xFFA9CDB0), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withAlpha(30)),
          const SizedBox(height: 14),
          Row(
            children: [
              stat(profile.bloodGroup == 'Unknown' ? '—' : profile.bloodGroup, 'Blood group'),
              stat('${profile.allergies.length}', 'Allergies'),
              stat('${profile.emergencyContacts.length}', 'Contacts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primary)),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFE3F2E0)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rows[i].$1, style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(rows[i].$2,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: rows[i].$2.startsWith('Not set') || rows[i].$2.startsWith('None')
                              ? const Color(0xFFA0AAB7)
                              : AppColors.text,
                        )),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
