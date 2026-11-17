import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/drug_repository.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_banner.dart';

/// Add a medicine one by one, exactly as prescribed. The app never suggests doses.
/// Typing a name suggests matching medicines from the app's list and fills in the salt and form.
/// If the backend finds a possible allergy match, the user must confirm.
class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key, required this.repository});

  final MedicineRepository repository;

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _salt = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _days = TextEditingController();
  final _notes = TextEditingController();
  late final DrugRepository _drugs = DrugRepository(widget.repository.api);
  Timer? _debounce;
  List<DrugBrand> _suggestions = [];
  List<String> _strengthChoices = [];
  String _form = 'tablet';
  String _food = 'after food';
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  bool _saving = false;
  String? _error;

  static const _forms = ['tablet', 'capsule', 'syrup', 'injection', 'drops', 'inhaler', 'cream', 'other'];
  static const _foodOptions = ['before food', 'after food', 'with food', 'at bedtime', 'any time'];
  static const _presets = <int, List<TimeOfDay>>{
    1: [TimeOfDay(hour: 9, minute: 0)],
    2: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 21, minute: 0)],
    3: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 14, minute: 0), TimeOfDay(hour: 21, minute: 0)],
    4: [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 12, minute: 0),
      TimeOfDay(hour: 16, minute: 0),
      TimeOfDay(hour: 21, minute: 0)
    ],
  };

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _salt, _strength, _dose, _days, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _onName(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await _drugs.search(v, limit: 6);
        if (mounted && _name.text == v) setState(() => _suggestions = r);
      } catch (_) {}
    });
  }

  void _pick(DrugBrand b) {
    final f = b.forms.isEmpty ? '' : b.forms.first.toLowerCase();
    setState(() {
      _name.text = b.brand;
      _salt.text = b.generic;
      _strengthChoices = b.strengths;
      if (b.strengths.length == 1) _strength.text = b.strengths.first;
      _form = _forms.firstWhere((x) => f.contains(x.substring(0, 3)), orElse: () => _form);
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 20, minute: 0));
    if (picked != null && !_times.contains(picked)) setState(() => _times = [..._times, picked]);
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save({bool confirmAllergy = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_times.isEmpty) {
      setState(() => _error = 'Add at least one time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final days = int.tryParse(_days.text.trim());
    final today = DateTime.now();
    final instructions = [
      if (_dose.text.trim().isNotEmpty) _dose.text.trim(),
      if (_food != 'any time') _food,
      if (_notes.text.trim().isNotEmpty) _notes.text.trim(),
    ].join(' · ');
    try {
      await widget.repository.add({
        'name': _name.text.trim(),
        'salt': _salt.text.trim(),
        'strength': _strength.text.trim(),
        'form': _form,
        'times': [for (final t in _times) _fmt(t)],
        'instructions': instructions.length > 200 ? instructions.substring(0, 200) : instructions,
        'start_date': _iso(today),
        if (days != null && days > 0) 'end_date': _iso(today.add(Duration(days: days - 1))),
      }, confirmAllergy: confirmAllergy);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'allergy_warning') {
        setState(() => _saving = false);
        final go = await showConfirmDialog(context,
            title: 'Possible allergy', message: e.message, confirmLabel: 'Save anyway', destructive: true);
        if (go && mounted) await _save(confirmAllergy: true);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
      );

  @override
  Widget build(BuildContext context) {
    final perDay = _presets.entries.where((e) => _sameTimes(e.value)).map((e) => e.key).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Add medicine')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Enter it exactly as written on your prescription or the pack.',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Medicine name',
              controller: _name,
              hint: 'Start typing, e.g. Panadol',
              onChanged: _onName,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the medicine name' : null,
            ),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.softShadow,
                ),
                child: Column(children: [
                  for (final b in _suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.medication_outlined, color: AppColors.green),
                      title: Text(b.brand, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(b.generic),
                      onTap: () => _pick(b),
                    ),
                ]),
              ),
            AppTextField(label: 'Salt / active ingredient', controller: _salt, hint: 'Filled in when you pick a medicine'),
            AppTextField(label: 'Strength (from the pack)', controller: _strength, hint: 'e.g. 500 mg'),
            if (_strengthChoices.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in _strengthChoices)
                    ChoiceChip(
                      label: Text(s),
                      selected: _strength.text == s,
                      onSelected: (_) => setState(() => _strength.text = s),
                    ),
                ]),
              ),
            DropdownButtonFormField<String>(
              value: _form,
              decoration: const InputDecoration(labelText: 'Form'),
              items: [for (final f in _forms) DropdownMenuItem(value: f, child: Text(f[0].toUpperCase() + f.substring(1)))],
              onChanged: (v) => setState(() => _form = v!),
            ),
            const SizedBox(height: 12),
            AppTextField(
                label: 'Amount each time (as the doctor wrote)', controller: _dose, hint: 'e.g. 1 tablet, 2 tsp'),
            _label('How many times a day?'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in _presets.keys)
                ChoiceChip(
                  label: Text(switch (n) { 1 => 'Once', 2 => 'Twice', 3 => '3 times', _ => '4 times' }),
                  selected: perDay == n,
                  onSelected: (_) => setState(() => _times = [..._presets[n]!]),
                ),
            ]),
            _label('Reminder times (tap × to remove)'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in _times)
                InputChip(
                  avatar: const Icon(Icons.alarm, size: 16),
                  label: Text(_fmt(t)),
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: t);
                    if (picked != null) {
                      setState(() => _times = [for (final x in _times) x == t ? picked : x]);
                    }
                  },
                  onDeleted: () => setState(() => _times = [..._times]..remove(t)),
                ),
              if (_times.length < 6)
                ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add time'), onPressed: _addTime),
            ]),
            _label('When to take it'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in _foodOptions)
                ChoiceChip(
                  label: Text(f[0].toUpperCase() + f.substring(1)),
                  selected: _food == f,
                  onSelected: (_) => setState(() => _food = f),
                ),
            ]),
            const SizedBox(height: 14),
            AppTextField(
              label: 'For how many days? (leave empty if ongoing)',
              controller: _days,
              hint: 'e.g. 5',
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                return (n == null || n < 1 || n > 365) ? 'Enter days between 1 and 365' : null;
              },
            ),
            AppTextField(label: 'Notes (optional)', controller: _notes, hint: 'e.g. with plenty of water'),
            if (_error != null) ErrorBanner(_error!),
            AppButton(label: 'Save medicine', loading: _saving, onPressed: () => _save()),
          ],
        ),
      ),
    );
  }

  bool _sameTimes(List<TimeOfDay> preset) =>
      preset.length == _times.length && preset.every((p) => _times.contains(p));
}
