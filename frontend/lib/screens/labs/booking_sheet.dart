import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/entries_repository.dart';
import '../../services/lab_repository.dart';

/// Book the doctor the symptom check suggested: everything is filled in from the result;
/// the user picks a date and taps Confirm. Saved as an appointment request (feature 11).
Future<void> showBookingSheet(BuildContext context, {required String specialty, required String reason}) async {
  final api = context.read<AuthProvider>().repository.api;
  String? city;
  try {
    city = await LabRepository(api).myCity();
  } catch (_) {}
  if (!context.mounted) return;

  final tomorrow = DateTime.now().add(const Duration(days: 1));
  var date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
  var mode = 'In person';
  final cityCtrl = TextEditingController(text: city ?? '');
  final reasonCtrl = TextEditingController(text: reason);
  var saving = false;

  String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String nice(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const Text('Book a doctor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.medical_services_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(specialty, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
            const SizedBox(height: 14),
            TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text('Date: ${nice(date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (d != null) setSheet(() => date = d);
              },
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'In person', label: Text('In person')),
                ButtonSegment(value: 'Online', label: Text('Online')),
              ],
              selected: {mode},
              onSelectionChanged: (v) => setSheet(() => mode = v.first),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reason (from your symptom check)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your request is saved and shown in Appointments. A verified doctor list is not connected yet, '
              'so the clinic and time will be confirmed later.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('Confirm booking'),
              onPressed: saving
                  ? null
                  : () async {
                      setSheet(() => saving = true);
                      try {
                        await EntriesRepository(api).add(11, {
                          'specialty': specialty,
                          'preferred_date': iso(date),
                          'mode': mode,
                          'city': cityCtrl.text.trim(),
                          'reason': reasonCtrl.text.trim(),
                          'source': 'symptom_check',
                          'status': 'requested',
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Booking request saved: $specialty on ${nice(date)}.')));
                        }
                      } on ApiException catch (e) {
                        setSheet(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
            ),
          ]),
        ),
      ),
    ),
  );
  cityCtrl.dispose();
  reasonCtrl.dispose();
}
