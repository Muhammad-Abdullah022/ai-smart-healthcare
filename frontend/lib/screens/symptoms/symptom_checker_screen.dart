import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/assessment_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/medical_disclaimer.dart';
import 'symptom_history_screen.dart';
import 'symptom_result_screen.dart';

/// Feature 1: AI Symptom Checker. The user describes symptoms; the backend
/// checks emergency rules first, then asks the AI for a structured answer.
class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({super.key, this.repository});

  /// Optional, so tests can pass a fake.
  final AssessmentRepository? repository;

  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _symptoms = TextEditingController();
  final _age = TextEditingController();
  String _duration = '1–3 days';
  double _severity = 5;
  String? _sex;
  bool _loading = false;
  String? _error;

  static const _durations = ['Less than 1 day', '1–3 days', '4–7 days', '1–4 weeks', 'More than a month'];

  late final AssessmentRepository _repo =
      widget.repository ?? AssessmentRepository(context.read<AuthProvider>().repository.api);

  @override
  void dispose() {
    _symptoms.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.checkSymptoms(
        symptoms: _symptoms.text.trim(),
        duration: _duration,
        severity: _severity.round(),
        age: int.tryParse(_age.text.trim()),
        sex: _sex,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SymptomResultScreen(
          assessment: result,
          repository: _repo,
          request: SymptomRequestData(
            symptoms: _symptoms.text.trim(),
            duration: _duration,
            severity: _severity.round(),
            age: int.tryParse(_age.text.trim()),
            sex: _sex,
          ),
        ),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Symptom checker'),
        actions: [
          IconButton(
            tooltip: 'Past checks',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SymptomHistoryScreen(repository: _repo)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MedicalDisclaimer(compact: true),
            const SizedBox(height: 16),
            AppTextField(
              label: 'What symptoms do you have?',
              controller: _symptoms,
              hint: 'e.g. fever, headache and body aches since yesterday',
              maxLines: 4,
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Please describe your symptoms' : null,
            ),
            Text('How long have you had them?', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in _durations)
                  ChoiceChip(
                    label: Text(d),
                    selected: _duration == d,
                    selectedColor: AppColors.accentTint,
                    onSelected: (_) => setState(() => _duration = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('How bad is it? ${_severity.round()} / 10', style: Theme.of(context).textTheme.labelLarge),
            Slider(
              value: _severity,
              min: 1,
              max: 10,
              divisions: 9,
              activeColor: _severity >= 8 ? AppColors.critical : AppColors.accent,
              label: _severity.round().toString(),
              onChanged: (v) => setState(() => _severity = v),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mild', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                Text('Worst ever', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Age (optional)',
                    controller: _age,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = int.tryParse(v.trim());
                      return (n == null || n < 0 || n > 120) ? 'Enter 0–120' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: DropdownButtonFormField<String?>(
                      value: _sex,
                      decoration: const InputDecoration(hintText: 'Sex (optional)'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Not given')),
                        DropdownMenuItem(value: 'female', child: Text('Female')),
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ErrorBanner(_error!),
            const SizedBox(height: 8),
            AppButton(label: 'Check symptoms', icon: Icons.search, loading: _loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
