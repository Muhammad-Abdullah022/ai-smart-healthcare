import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_banner.dart';

/// Feature 35: enter a medicine exactly as prescribed. The app never suggests doses.
/// Feature 32: if the backend finds a possible allergy match, the user must confirm.
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
  final _instructions = TextEditingController();
  String _form = 'tablet';
  final List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  bool _saving = false;
  String? _error;

  static const _forms = ['tablet', 'capsule', 'syrup', 'injection', 'drops', 'inhaler', 'cream', 'other'];

  @override
  void dispose() {
    for (final c in [_name, _salt, _strength, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 20, minute: 0));
    if (picked != null && !_times.contains(picked)) setState(() => _times.add(picked));
  }

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
    try {
      await widget.repository.add({
        'name': _name.text.trim(),
        'salt': _salt.text.trim(),
        'strength': _strength.text.trim(),
        'form': _form,
        'times': [for (final t in _times) _fmt(t)],
        'instructions': _instructions.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add medicine')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Enter it exactly as written on your prescription or the pack.',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Medicine name',
              controller: _name,
              hint: 'e.g. Panadol',
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the medicine name' : null,
            ),
            AppTextField(label: 'Active ingredient / salt (optional)', controller: _salt, hint: 'e.g. Paracetamol'),
            AppTextField(label: 'Strength (from the pack)', controller: _strength, hint: 'e.g. 500 mg'),
            DropdownButtonFormField<String>(
              value: _form,
              decoration: const InputDecoration(labelText: 'Form'),
              items: [for (final f in _forms) DropdownMenuItem(value: f, child: Text(f[0].toUpperCase() + f.substring(1)))],
              onChanged: (v) => setState(() => _form = v!),
            ),
            const SizedBox(height: 16),
            Text('Times each day', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _times)
                  InputChip(label: Text(_fmt(t)), onDeleted: () => setState(() => _times.remove(t))),
                if (_times.length < 6)
                  ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add time'), onPressed: _addTime),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(label: 'Instructions (optional)', controller: _instructions, hint: 'e.g. after food'),
            if (_error != null) ErrorBanner(_error!),
            AppButton(label: 'Save medicine', loading: _saving, onPressed: () => _save()),
          ],
        ),
      ),
    );
  }
}
