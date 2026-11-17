import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/health_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';

/// Feature 40 (+45): future health risk from the user's saved data, with the reasons and
/// personalised recommendations. Calculated by rules in the backend — explainable, not AI.
class HealthRiskScreen extends StatefulWidget {
  const HealthRiskScreen({super.key});

  @override
  State<HealthRiskScreen> createState() => _HealthRiskScreenState();
}

class _HealthRiskScreenState extends State<HealthRiskScreen> {
  late final HealthRepository _repo = HealthRepository(context.read<AuthProvider>().repository.api);
  late Future<Map<String, dynamic>> _future = _repo.risk();

  static Color _color(String level) => switch (level) {
        'high' => AppColors.critical,
        'moderate' => const Color(0xFFD97706),
        _ => AppColors.success,
      };

  Future<void> _editLifestyle(Map<String, dynamic> life) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LifestyleSheet(initial: life, repository: _repo),
    );
    if (updated != null && mounted) setState(() => _future = Future.value(updated));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Future health risk')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            return ErrorView(message: 'Could not calculate your risk.', onRetry: () => setState(() => _future = _repo.risk()));
          }
          final d = snap.data!;
          final risks = (d['risks'] as List).cast<Map<String, dynamic>>();
          final missing = (d['missing'] as List).cast<String>();
          final overall = d['overall'] as String;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(colors: [_color(overall), _color(overall).withAlpha(190)]),
              ),
              child: Row(children: [
                const Icon(Icons.insights_rounded, color: Colors.white, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Overall: ${overall[0].toUpperCase()}${overall.substring(1)} risk',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${d['note']}', style: TextStyle(color: Colors.white.withAlpha(225), fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.tune),
              label: const Text('Update my details (height, weight, waist, habits)'),
              onPressed: () => _editLifestyle((d['lifestyle'] as Map?)?.cast<String, dynamic>() ?? {}),
            ),
            if (missing.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(14)),
                child: Text('For a better estimate add: ${missing.join(', ')}.',
                    style: const TextStyle(color: AppColors.deep, fontSize: 13)),
              ),
            const SizedBox(height: 16),
            const Text('Your recommendations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
            const SizedBox(height: 8),
            for (final t in (d['recommendations'] as List))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle, size: 18, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$t', style: const TextStyle(height: 1.4))),
                ]),
              ),
            const SizedBox(height: 14),
            for (final r in risks) _RiskCard(risk: r, color: _color(r['level'] as String)),
          ]);
        },
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.risk, required this.color});
  final Map<String, dynamic> risk;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final r = risk;
    final level = r['level'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: AppColors.softShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: level != 'low',
          title: Text('${r['title']}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
          subtitle: Text(
              r['score'] != null && '${r['score_label']}'.isNotEmpty ? '${r['score_label']}: ${r['score']}' : '',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
            child: Text(level.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Why', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            for (final f in r['factors'] as List)
              Padding(padding: const EdgeInsets.only(top: 3), child: Text('•  $f', style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 8),
            const Text('What you can do', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            for (final t in r['tips'] as List)
              Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('✓  $t', style: const TextStyle(fontSize: 13, color: AppColors.deep))),
          ],
        ),
      ),
    );
  }
}

class _LifestyleSheet extends StatefulWidget {
  const _LifestyleSheet({required this.initial, required this.repository});
  final Map<String, dynamic> initial;
  final HealthRepository repository;

  @override
  State<_LifestyleSheet> createState() => _LifestyleSheetState();
}

class _LifestyleSheetState extends State<_LifestyleSheet> {
  late final _height = TextEditingController(text: _s(widget.initial['height_cm']));
  late final _weight = TextEditingController(text: _s(widget.initial['weight_kg']));
  late final _waist = TextEditingController(text: _s(widget.initial['waist_cm']));
  late bool _smoker = widget.initial['smoker'] == true;
  late String? _activity = widget.initial['activity'] as String?;
  late String? _parents = widget.initial['diabetes_parents'] as String?;
  late final Set<String> _family = {...((widget.initial['family_history'] as List?) ?? const []).cast<String>()};
  bool _saving = false;

  static String _s(Object? v) => v == null ? '' : (v is num && v % 1 == 0 ? v.toInt().toString() : '$v');

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final d = await widget.repository.saveLifestyle({
        if (double.tryParse(_height.text) != null) 'height_cm': double.parse(_height.text),
        if (double.tryParse(_weight.text) != null) 'weight_kg': double.parse(_weight.text),
        if (double.tryParse(_waist.text) != null) 'waist_cm': double.parse(_waist.text),
        'smoker': _smoker,
        if (_activity != null) 'activity': _activity,
        if (_parents != null) 'diabetes_parents': _parents,
        'family_history': _family.toList(),
      });
      if (mounted) Navigator.pop(context, d);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  Widget _num(String label, TextEditingController c, String hint) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );

  Widget _choices(String title, Map<String, String> options, String? value, ValueChanged<String> onPick) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in options.entries)
              ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onPick(e.key)),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('My details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              _num('Height (cm)', _height, '165'),
              const SizedBox(width: 10),
              _num('Weight (kg)', _weight, '70'),
              const SizedBox(width: 10),
              _num('Waist (cm)', _waist, '90'),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I smoke (cigarettes, huqqa, sheesha)'),
              value: _smoker,
              onChanged: (v) => setState(() => _smoker = v),
            ),
            _choices('Exercise', const {'active': 'Most days', 'some': 'Sometimes', 'inactive': 'Rarely'}, _activity,
                (v) => setState(() => _activity = v)),
            _choices('Parents with diabetes', const {'none': 'None', 'one': 'One', 'both': 'Both'}, _parents,
                (v) => setState(() => _parents = v)),
            const Padding(
              padding: EdgeInsets.only(top: 14, bottom: 6),
              child: Text('Family history', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in const ['heart disease', 'stroke', 'high blood pressure', 'kidney disease', 'cancer'])
                FilterChip(
                  label: Text(f),
                  selected: _family.contains(f),
                  onSelected: (on) => setState(() => on ? _family.add(f) : _family.remove(f)),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save and recalculate'),
            ),
          ]),
        ),
      ),
    );
  }
}
