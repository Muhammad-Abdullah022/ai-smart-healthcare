import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../services/consultation_repository.dart';

/// Lets the user point the app at the laptop running the backend, e.g. 192.168.1.10:8000.
/// The START_BACKEND window shows the address to use ("Phone address").
Future<void> showServerAddressDialog(BuildContext context) async {
  final api = context.read<AuthProvider>().repository.api;
  final ctrl = TextEditingController(text: AppConfig.savedServer ?? api.baseUrl);
  String? result;
  bool? ok;
  var testing = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Future<void> test() async {
          setS(() {
            testing = true;
            ok = null;
          });
          final url = AppConfig.normalize(ctrl.text);
          final good = await api.ping(url);
          setS(() {
            testing = false;
            ok = good;
            result = url;
          });
        }

        return AlertDialog(
          title: const Text('Server address'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Use the "Phone address" shown in the START_BACKEND window on the laptop. '
              'The phone and the laptop must be on the same Wi-Fi.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: '192.168.1.10:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text('Now using: ${api.baseUrl}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            if (testing)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Checking…'),
                ]),
              )
            else if (ok != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Icon(ok! ? Icons.check_circle : Icons.error_outline,
                      color: ok! ? AppColors.success : AppColors.critical, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(ok! ? 'Connected to the backend.' : 'No answer. Check the address, Wi-Fi and firewall.',
                        style: TextStyle(color: ok! ? AppColors.success : AppColors.critical, fontSize: 13)),
                  ),
                ]),
              ),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await AppConfig.saveServer(null);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Automatic'),
            ),
            OutlinedButton(onPressed: testing ? null : test, child: const Text('Test')),
            FilledButton(
              onPressed: testing
                  ? null
                  : () async {
                      if (ok != true || result != AppConfig.normalize(ctrl.text)) await test();
                      if (ok == true) {
                        await AppConfig.saveServer(result);
                        LiveEvents.instance.disconnect();
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
}
