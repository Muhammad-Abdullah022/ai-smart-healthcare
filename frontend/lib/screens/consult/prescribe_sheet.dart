import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';

class _MedRow {
  final name = TextEditingController();
  final strength = TextEditingController();
  final how = TextEditingController();
  final days = TextEditingController();
  int? times;
  String timing = 'After food';

  void dispose() {
    for (final c in [name, strength, how, days]) {
      c.dispose();
    }
  }
}

const _patterns = {'1+0+1': 2, '1+1+1': 3, '1+0+0': 1, '0+0+1': 1, 'When needed': 0};

/// Doctor writes the prescription (only after the payment is confirmed).
Future<Map<String, dynamic>?> showPrescribeSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _PrescribeSheet(),
  );
}

class _PrescribeSheet extends StatefulWidget {
  const _PrescribeSheet();

  @override
  State<_PrescribeSheet> createState() => _PrescribeSheetState();
}

class _PrescribeSheetState extends State<_PrescribeSheet> {
  final _rows = [_MedRow()];
  final _diagnosis = TextEditingController();
  final _advice = TextEditingController();
  final _tests = TextEditingController();
  final _followUp = TextEditingController();

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final c in [_diagnosis, _advice, _tests, _followUp]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final meds = <Map<String, dynamic>>[];
    for (final r in _rows) {
      if (r.name.text.trim().isEmpty) continue;
      if (r.how.text.trim().length < 2) {
        showMessage(context, 'Write how to take ${r.name.text.trim()}.', error: true);
        return;
      }
      meds.add({
        'name': r.name.text.trim(),
        'strength': r.strength.text.trim(),
        'how_to_take': '${r.how.text.trim()}${r.timing.isEmpty ? '' : ', ${r.timing.toLowerCase()}'}',
        'times_per_day': r.times,
        'timing': r.timing,
        'duration_days': int.tryParse(r.days.text.trim()),
      });
    }
    if (meds.isEmpty) {
      showMessage(context, 'Add at least one medicine.', error: true);
      return;
    }
    Navigator.pop(context, {
      'diagnosis': _diagnosis.text.trim(),
      'medicines': meds,
      'advice': _advice.text.trim(),
      'tests': [for (final t in _tests.text.split(',')) if (t.trim().isNotEmpty) t.trim()],
      'follow_up': _followUp.text.trim(),
    });
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        maxChildSize: .95,
        builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(18, 10, 18, 24), children: [
          Center(
              child: Container(
                  width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 14),
          const Text('Write prescription',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.deep)),
          const SizedBox(height: 14),
          TextField(controller: _diagnosis, decoration: _dec('Diagnosis / impression', hint: 'e.g. Viral fever')),
          const SizedBox(height: 16),
          for (var i = 0; i < _rows.length; i++) _medCard(i),
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_MedRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add another medicine'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _advice, maxLines: 3, decoration: _dec('Advice', hint: 'Rest, fluids, diet …')),
          const SizedBox(height: 12),
          TextField(controller: _tests, decoration: _dec('Tests (comma separated)', hint: 'CBC, Dengue NS1')),
          const SizedBox(height: 12),
          TextField(controller: _followUp, decoration: _dec('Follow-up', hint: 'After 3 days if fever continues')),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send to patient'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _medCard(int i) {
    final r = _rows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.mint.withAlpha(120),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.softGreen)),
      child: Column(children: [
        Row(children: [
          Text('Medicine ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
          const Spacer(),
          if (_rows.length > 1)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _rows.removeAt(i).dispose()),
              icon: const Icon(Icons.delete_outline, color: AppColors.critical, size: 20),
            ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(flex: 3, child: TextField(controller: r.name, decoration: _dec('Name', hint: 'Panadol'))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: TextField(controller: r.strength, decoration: _dec('Strength', hint: '500 mg'))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final p in _patterns.entries)
            ChoiceChip(
              label: Text(p.key),
              selected: r.how.text == p.key || (p.key == 'When needed' && r.how.text == 'When needed'),
              onSelected: (_) => setState(() {
                r.how.text = p.key;
                r.times = p.value == 0 ? null : p.value;
              }),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: r.how,
            onChanged: (_) => setState(() {}),
            decoration: _dec('How to take', hint: '1 tablet morning and night')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: r.timing,
              isDense: true,
              decoration: _dec('Food'),
              items: const [
                DropdownMenuItem(value: 'After food', child: Text('After food')),
                DropdownMenuItem(value: 'Before food', child: Text('Before food')),
                DropdownMenuItem(value: 'At bedtime', child: Text('At bedtime')),
                DropdownMenuItem(value: '', child: Text('Any time')),
              ],
              onChanged: (v) => setState(() => r.timing = v ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 96,
              child: TextField(controller: r.days, keyboardType: TextInputType.number, decoration: _dec('Days'))),
        ]),
      ]),
    );
  }
}

/// Doctor asks the patient to come to the clinic (serious problem / needs examination).
Future<({String urgency, String reason, String date})?> showClinicVisitSheet(BuildContext context) async {
  var urgency = 'today';
  final reason = TextEditingController();
  final date = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ask patient to visit the clinic',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.deep)),
          const SizedBox(height: 4),
          const Text('Your clinic address, phone and timings are sent with this message.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final u in const {
              'emergency': 'Emergency (now)',
              'today': 'Today',
              'within_3_days': 'Within 3 days',
              'this_week': 'This week',
            }.entries)
              ChoiceChip(
                label: Text(u.value),
                selected: urgency == u.key,
                selectedColor: u.key == 'emergency' ? AppColors.criticalTint : AppColors.mint,
                onSelected: (_) => setS(() => urgency = u.key),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Reason', hintText: 'Needs examination / ECG / BP check', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: date,
            decoration: const InputDecoration(
                labelText: 'Suggested day / time (optional)', hintText: 'Tomorrow 6 pm', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: urgency == 'emergency' ? AppColors.critical : AppColors.records,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                if (reason.text.trim().length < 3) {
                  showMessage(ctx, 'Please write a short reason.', error: true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.local_hospital_outlined),
              label: const Text('Send to patient'),
            ),
          ),
        ]),
      ),
    ),
  );
  final result = ok == true ? (urgency: urgency, reason: reason.text.trim(), date: date.text.trim()) : null;
  reason.dispose();
  date.dispose();
  return result;
}
