import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/account_repository.dart';
import '../../services/api_client.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_card.dart';
import '../../widgets/state_views.dart';

/// Privacy & consent (C-15, feature 48). Everything is OFF until the user turns it on.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, this.repository});

  final AccountRepository? repository;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  late final AccountRepository _repo =
      widget.repository ?? AccountRepository(context.read<AuthProvider>().repository.api);
  late Future<List<ConsentItem>> _future = _repo.consents();
  final Set<String> _saving = {};

  Future<void> _toggle(ConsentItem item, bool value) async {
    setState(() => _saving.add(item.category));
    try {
      await _repo.setConsent(item.category, value);
      if (mounted) setState(() => _future = _repo.consents());
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(item.category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & consent')),
      body: FutureBuilder<List<ConsentItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) return const LoadingView();
          if (snap.hasError) {
            return ErrorView(
              message: 'Could not load your privacy settings.',
              onRetry: () => setState(() => _future = _repo.consents()),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'You decide what the app may use. You can change these at any time; '
                'every change is recorded with the date.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              for (final item in snap.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: SwitchListTile(
                      value: item.granted,
                      activeColor: AppColors.accent,
                      onChanged: _saving.contains(item.category) ? null : (v) => _toggle(item, v),
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(item.description, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
