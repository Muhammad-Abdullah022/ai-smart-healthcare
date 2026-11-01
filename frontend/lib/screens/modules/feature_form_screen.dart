import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/feature_catalog.dart';
import '../../models/feature_forms.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/entries_repository.dart';
import '../../widgets/app_button.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/feature_page.dart';
import '../../widgets/section_card.dart';

/// One screen for every feature that has a form in [featureForms].
/// It shows the form, saves to the backend, and lists what was saved before.
class FeatureFormScreen extends StatefulWidget {
  const FeatureFormScreen({super.key, required this.number, this.repository});

  final int number;
  final EntriesRepository? repository;

  @override
  State<FeatureFormScreen> createState() => _FeatureFormScreenState();
}

class _FeatureFormScreenState extends State<FeatureFormScreen> {
  late final EntriesRepository _repo =
      widget.repository ?? EntriesRepository(context.read<AuthProvider>().repository.api);
  late final FormSpec _spec = featureForms[widget.number]!;
  late Future<List<Entry>> _entries = _repo.list(widget.number);

  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  final Map<String, Object?> _values = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key) => _text.putIfAbsent(key, TextEditingController.new);

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _time(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> _collect() {
    final out = <String, dynamic>{};
    for (final f in _spec.fields) {
      switch (f.type) {
        case FieldType.text:
        case FieldType.long:
          final v = _ctrl(f.key).text.trim();
          if (v.isNotEmpty) out[f.key] = v;
        case FieldType.number:
          final v = num.tryParse(_ctrl(f.key).text.trim());
          if (v != null) out[f.key] = v;
        case FieldType.tags:
          final v = _ctrl(f.key).text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (v.isNotEmpty) out[f.key] = v;
        case FieldType.toggle:
          out[f.key] = _values[f.key] == true;
        case FieldType.date:
        case FieldType.time:
        case FieldType.choice:
          if (_values[f.key] != null) out[f.key] = _values[f.key];
      }
    }
    return out;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final missing = _spec.fields
        .where((f) => f.required && const {FieldType.date, FieldType.time, FieldType.choice}.contains(f.type))
        .where((f) => _values[f.key] == null)
        .map((f) => f.label);
    if (missing.isNotEmpty) {
      setState(() => _error = 'Please choose: ${missing.join(', ')}');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.add(widget.number, _collect());
      if (!mounted) return;
      for (final c in _text.values) {
        c.clear();
      }
      setState(() {
        _values.clear();
        _entries = _repo.list(widget.number);
      });
      showMessage(context, 'Saved');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(Entry e) async {
    final ok = await showConfirmDialog(context,
        title: 'Remove this entry?', message: 'It will no longer show here.', confirmLabel: 'Remove', destructive: true);
    if (!ok) return;
    try {
      await _repo.archive(widget.number, e.id);
      if (mounted) setState(() => _entries = _repo.list(widget.number));
    } on ApiException catch (err) {
      if (mounted) showMessage(context, err.message, error: true);
    }
  }

  Widget _field(FieldSpec f, Color color) {
    final label = Text(f.label, style: Theme.of(context).textTheme.labelLarge);
    String? requiredText(String? v) => f.required && (v == null || v.trim().isEmpty) ? 'Please fill this in' : null;
    final Widget input = switch (f.type) {
      FieldType.text || FieldType.long || FieldType.tags => TextFormField(
          controller: _ctrl(f.key),
          maxLines: f.type == FieldType.long ? 4 : 1,
          decoration: InputDecoration(hintText: f.type == FieldType.tags ? (f.hint ?? 'Separate with commas') : f.hint),
          validator: requiredText,
        ),
      FieldType.number => TextFormField(
          controller: _ctrl(f.key),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: f.hint),
          validator: (v) {
            final req = requiredText(v);
            if (req != null) return req;
            if (v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) == null) return 'Enter a number';
            return null;
          },
        ),
      FieldType.choice => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in f.options)
              ChoiceChip(
                label: Text(o),
                selected: _values[f.key] == o,
                selectedColor: color.withAlpha(40),
                side: BorderSide(color: _values[f.key] == o ? color : AppColors.border),
                onSelected: (_) => setState(() => _values[f.key] = o),
              ),
          ],
        ),
      FieldType.toggle => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _values[f.key] == true,
          activeColor: color,
          title: Text(f.label),
          onChanged: (v) => setState(() => _values[f.key] = v),
        ),
      FieldType.date => OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text((_values[f.key] as String?) ?? 'Choose date'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context, initialDate: DateTime.now(), firstDate: DateTime(1900), lastDate: DateTime(2100));
            if (d != null) setState(() => _values[f.key] = _date(d));
          },
        ),
      FieldType.time => OutlinedButton.icon(
          icon: const Icon(Icons.schedule, size: 18),
          label: Text((_values[f.key] as String?) ?? 'Choose time'),
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
            if (t != null) setState(() => _values[f.key] = _time(t));
          },
        ),
    };
    if (f.type == FieldType.toggle) return input;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, const SizedBox(height: 8), input]),
    );
  }

  String _entryTitle(Entry e) {
    for (final f in _spec.fields) {
      final v = e.data[f.key];
      if (v is String && v.isNotEmpty) return v.length > 60 ? '${v.substring(0, 60)}…' : v;
    }
    return 'Entry';
  }

  String _entrySubtitle(Entry e) {
    final parts = <String>[];
    for (final f in _spec.fields.skip(1).take(3)) {
      final v = e.data[f.key];
      if (v == null || v == false) continue;
      parts.add(v == true ? f.label : (v is List ? v.join(', ') : '$v'));
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final feature = featureByNumber(widget.number)!;
    final module = moduleOf(widget.number);
    final d = DateTime.now();
    String when(DateTime t) => t.year == d.year && t.month == d.month && t.day == d.day
        ? 'Today ${_time(TimeOfDay.fromDateTime(t))}'
        : _date(t);

    return FeaturePage(
      title: feature.title,
      purpose: _spec.purpose,
      icon: feature.icon,
      color: module.color,
      tint: module.tint,
      notice: _spec.notice,
      children: [
        SectionCard(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in _spec.fields) _field(f, module.color),
                if (_error != null) ErrorBanner(_error!),
                AppButton(label: _spec.saveLabel, loading: _saving, onPressed: _save),
              ],
            ),
          ),
        ),
        const SectionTitle('Your entries'),
        FutureBuilder<List<Entry>>(
          future: _entries,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              );
            }
            if (snap.hasError) {
              final e = snap.error;
              return Text(e is ApiException ? e.message : 'Could not load your entries.',
                  style: const TextStyle(color: AppColors.textMuted));
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('Nothing here yet. What you save above will appear here.',
                    style: TextStyle(color: AppColors.textMuted, height: 1.5)),
              );
            }
            return GroupedList(children: [
              for (final e in items)
                ListRow(
                  icon: feature.icon,
                  color: module.color,
                  tint: module.tint,
                  title: _entryTitle(e),
                  subtitle: [_entrySubtitle(e), when(e.createdAt)].where((s) => s.isNotEmpty).join('\n'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFFB3BDC9)),
                    onPressed: () => _remove(e),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
