import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/section_card.dart';

/// Feature 12: SOS. Numbers are shown at once (no waiting for the server);
/// pressing the button records the emergency and prepares a message for contacts.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key, this.api});

  final ApiClient? api;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  late final ApiClient _api = widget.api ?? context.read<AuthProvider>().repository.api;
  bool _sending = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _trigger() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final data = await _api.post('/sos', body: <String, dynamic>{}) as Map<String, dynamic>;
      if (mounted) setState(() => _result = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = '${e.message} You can still call the numbers below.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = (_result?['contacts'] as List<dynamic>?) ?? const [];
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(backgroundColor: const Color(0xFFFFF5F5), title: const Text('Emergency')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _sending ? null : _trigger,
              child: Semantics(
                button: true,
                label: 'Send SOS',
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.critical,
                    boxShadow: [
                      BoxShadow(color: AppColors.critical.withAlpha(70), blurRadius: 40, spreadRadius: 10),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _sending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('SOS',
                                style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
                            Text(_result == null ? 'Tap for help' : 'Sent',
                                style: const TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.critical)),
            ),
          const Text('Call now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          for (final (name, number) in const [('Rescue / Ambulance', '1122'), ('Edhi Ambulance', '115'), ('Police', '15')])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SectionCard(
                child: Row(
                  children: [
                    const Icon(Icons.phone_in_talk, color: AppColors.critical),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    SelectableText(number,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.critical)),
                  ],
                ),
              ),
            ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            const Text('Your emergency contacts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (contacts.isEmpty)
              const Text('No emergency contacts yet. Add them in Profile → Edit profile.',
                  style: TextStyle(color: AppColors.textMuted)),
            for (final c in contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SectionCard(
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${(c as Map)['name']}')),
                      SelectableText('${c['phone']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Message for your contacts', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SelectableText('${_result!['message']}', style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy message'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '${_result!['message']}'));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
                      }
                    },
                  ),
                  Text('${_result!['limitation']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
