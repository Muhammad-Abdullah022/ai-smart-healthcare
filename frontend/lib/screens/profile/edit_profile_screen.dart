import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_banner.dart';

/// Edit personal and basic medical details. Returns `true` when saved.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _allergies;
  late final TextEditingController _conditions;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late String _bloodGroup;
  String? _gender;
  DateTime? _dob;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    final contact = p.emergencyContacts.isEmpty ? null : p.emergencyContacts.first;
    _name = TextEditingController(text: p.fullName);
    _phone = TextEditingController(text: p.phone ?? '');
    _allergies = TextEditingController(text: p.allergies.join(', '));
    _conditions = TextEditingController(text: p.conditions.join(', '));
    _contactName = TextEditingController(text: contact?.name ?? '');
    _contactPhone = TextEditingController(text: contact?.phone ?? '');
    _bloodGroup = p.bloodGroup;
    _gender = p.gender;
    _dob = p.dateOfBirth == null ? null : DateTime.tryParse(p.dateOfBirth!);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _allergies, _conditions, _contactName, _contactPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _splitList(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hasContact = _contactName.text.trim().isNotEmpty;
    if (hasContact && _contactPhone.text.trim().length < 5) {
      setState(() => _error = 'Please enter a valid phone number for the emergency contact.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final changes = <String, dynamic>{
      'full_name': _name.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'blood_group': _bloodGroup,
      'gender': _gender,
      'date_of_birth': _dob == null ? null : _formatDate(_dob!),
      'allergies': _splitList(_allergies.text),
      'conditions': _splitList(_conditions.text),
      'emergency_contacts': hasContact
          ? [EmergencyContact(name: _contactName.text.trim(), phone: _contactPhone.text.trim()).toJson()]
          : <Map<String, dynamic>>[],
    };
    try {
      final auth = context.read<AuthProvider>();
      await auth.repository.updateProfile(changes);
      await auth.refreshUser(); // so the new name shows on Home
      if (!mounted) return;
      showMessage(context, 'Profile saved');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppTextField(label: 'Full name', controller: _name, icon: Icons.person_outline, validator: Validators.fullName),
            AppTextField(
                label: 'Phone', controller: _phone, icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
            Text('Date of birth', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_dob == null ? 'Select date' : _formatDate(_dob!)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Not set')),
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
                DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _bloodGroup,
              decoration: const InputDecoration(labelText: 'Blood group'),
              items: [for (final g in Profile.bloodGroups) DropdownMenuItem(value: g, child: Text(g))],
              onChanged: (v) => setState(() => _bloodGroup = v ?? 'Unknown'),
            ),
            const SizedBox(height: 16),
            AppTextField(
                label: 'Allergies', controller: _allergies, hint: 'e.g. Penicillin, Peanuts (comma separated)'),
            AppTextField(
                label: 'Medical conditions', controller: _conditions, hint: 'e.g. Asthma, Diabetes (comma separated)'),
            const Divider(),
            const SizedBox(height: 12),
            AppTextField(label: 'Emergency contact name', controller: _contactName, icon: Icons.contact_phone_outlined),
            AppTextField(
              label: 'Emergency contact phone',
              controller: _contactPhone,
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
            ),
            if (_error != null) ErrorBanner(_error!),
            const SizedBox(height: 8),
            AppButton(label: 'Save changes', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
