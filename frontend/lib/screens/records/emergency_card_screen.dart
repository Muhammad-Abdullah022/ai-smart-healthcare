import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/entries_repository.dart';
import '../../widgets/feature_page.dart';
import '../../widgets/section_card.dart';
import '../modules/feature_form_screen.dart';

/// Feature 44: emergency medical passport. The QR holds plain text only
/// (no link, no login), with exactly the fields the user chose to show.
class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({super.key});

  @override
  State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  late Future<(Profile, Map<String, dynamic>)> _future = _load();

  Future<(Profile, Map<String, dynamic>)> _load() async {
    final auth = context.read<AuthProvider>();
    final profile = await auth.repository.getProfile();
    final entries = await EntriesRepository(auth.repository.api).list(44);
    // Latest saved choices; if none yet, show blood group and allergies by default.
    final prefs = entries.isEmpty
        ? <String, dynamic>{'show_blood_group': true, 'show_allergies': true}
        : entries.first.data;
    return (profile, prefs);
  }

  String _cardText(Profile p, Map<String, dynamic> prefs) {
    final lines = <String>['EMERGENCY MEDICAL INFO', 'Name: ${p.fullName}'];
    if (prefs['show_blood_group'] == true) lines.add('Blood group: ${p.bloodGroup}');
    if (prefs['show_allergies'] == true) {
      lines.add('Allergies: ${p.allergies.isEmpty ? 'None recorded' : p.allergies.join(', ')}');
    }
    if (prefs['show_conditions'] == true) {
      lines.add('Conditions: ${p.conditions.isEmpty ? 'None recorded' : p.conditions.join(', ')}');
    }
    if (prefs['show_contacts'] == true) {
      for (final c in p.emergencyContacts) {
        lines.add('Contact: ${c.name} ${c.phone}');
      }
    }
    final note = prefs['extra_note'];
    if (note is String && note.isNotEmpty) lines.add('Note: $note');
    lines.add('Emergency: 1122');
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final module = moduleOf(44);
    return FeaturePage(
      title: 'Emergency medical card',
      purpose: 'Show this QR to doctors or rescuers. It contains only what you choose.',
      icon: Icons.qr_code_2,
      color: module.color,
      tint: module.tint,
      children: [
        FutureBuilder<(Profile, Map<String, dynamic>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            if (snap.hasError) return const Text('Could not load your card. Pull down to try again.');
            final (profile, prefs) = snap.data!;
            final text = _cardText(profile, prefs);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      QrImageView(data: text, size: 220, backgroundColor: Colors.white),
                      const SizedBox(height: 16),
                      Text(profile.fullName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      const SizedBox(height: 4),
                      const Text('Scan with any phone camera',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                const SectionTitle('On this card'),
                SectionCard(
                  child: Text(text.split('\n').skip(1).join('\n'), style: const TextStyle(height: 1.6)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Choose what the card shows'),
                  onPressed: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const FeatureFormScreen(number: 44)));
                    if (mounted) setState(() => _future = _load());
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
