import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'confirm_dialog.dart';

/// Change password (doctors must do this after the admin gives a temporary password).
Future<void> showChangePasswordDialog(BuildContext context, {bool forced = false}) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final again = TextEditingController();
  final form = GlobalKey<FormState>();
  var busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(forced ? 'Set your own password' : 'Change password'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (forced)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('The administrator gave you a temporary password. Please choose your own now.'),
              ),
            TextFormField(
              controller: current,
              obscureText: true,
              decoration: InputDecoration(labelText: forced ? 'Temporary password' : 'Current password'),
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (v) {
                final p = v ?? '';
                if (p.length < 8) return 'At least 8 characters';
                if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'Use letters and numbers';
                return null;
              },
            ),
            TextFormField(
              controller: again,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password again'),
              validator: (v) => v != next.text ? 'Passwords do not match' : null,
            ),
          ]),
        ),
        actions: [
          if (!forced) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setS(() => busy = true);
                    try {
                      final auth = ctx.read<AuthProvider>();
                      await auth.repository.api.post('/auth/change-password',
                          body: {'current_password': current.text, 'new_password': next.text});
                      await auth.refreshUser();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showMessage(ctx, 'Password changed.');
                      }
                    } catch (e) {
                      setS(() => busy = false);
                      if (ctx.mounted) showMessage(ctx, '$e', error: true);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  current.dispose();
  next.dispose();
  again.dispose();
}
