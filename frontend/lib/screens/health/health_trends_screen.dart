import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/health_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import '../../widgets/trend_chart.dart';

/// Feature 41: trend lines for readings (BP, sugar, weight, heart rate…), lab values across reports,
/// medicine adherence per week and mood — with latest / average / min / max and direction.
class HealthTrendsScreen extends StatefulWidget {
  const HealthTrendsScreen({super.key});

  @override
  State<HealthTrendsScreen> createState() => _HealthTrendsScreenState();
}

class _HealthTrendsScreenState extends State<HealthTrendsScreen> {
  late final HealthRepository _repo = HealthRepository(context.read<AuthProvider>().repository.api);
  int _days = 90;
  late Future<Map<String, dynamic>> _future = _repo.trends(days: _days);

  void _reload() => setState(() => _future = _repo.trends(days: _days));

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddReadingSheet(repository: _repo),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health trends')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add reading')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(children: [
            for (final (d, l) in const [(7, '7 days'), (30, '30 days'), (90, '3 months'), (365, '1 year')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(l),
                  selected: _days == d,
                  onSelected: (_) {
                    _days = d;
                    _reload();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingView();
              if (snap.hasError) return ErrorView(message: 'Could not load trends.', onRetry: _reload);
              final d = snap.data!;
              final vitals = (d['vitals'] as List).cast<Map<String, dynamic>>();
              final labs = (d['labs'] as List).cast<Map<String, dynamic>>();
              final adherence = (d['adherence'] as List).cast<Map<String, dynamic>>();
              final mood = (d['mood'] as List).cast<Map<String, dynamic>>();
              if (vitals.isEmpty && labs.isEmpty && adherence.isEmpty && mood.isEmpty) {
                return EmptyView(
                  icon: Icons.show_chart,
                  title: 'No readings yet',
                  message: 'Add blood pressure, sugar or weight readings — or connect a smartwatch — to see your trends.',
                  actionLabel: 'Add reading',
                  onAction: _add,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
                  for (final v in vitals) _VitalCard(data: v),
                  if (labs.isNotEmpty) _title('Lab values over time'),
                  for (final l in labs) _LabCard(data: l),
                  if (adherence.isNotEmpty) _title('Medicines taken on time'),
                  if (adherence.isNotEmpty) _AdherenceCard(weeks: adherence),
                  if (mood.where((m) => m['score'] != null).length >= 2) _title('Mood'),
                  if (mood.where((m) => m['score'] != null).length >= 2)
                    _card(TrendChart(
                      color: AppColors.mind,
                      points: [
                        for (final m in mood.where((m) => m['score'] != null))
                          TrendPoint(DateTime.parse(m['day'] as String), [(m['score'] as num).toDouble()])
                      ],
                    )),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  static Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.deep)),
      );
}

Widget _card(Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: child,
    );

String _n(num v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

Widget _stat(String label, String value) => Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
    );

Widget _direction(String dir) {
  final (icon, label) = switch (dir) {
    'up' => (Icons.trending_up, 'Going up'),
    'down' => (Icons.trending_down, 'Going down'),
    _ => (Icons.trending_flat, 'Steady'),
  };
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 18, color: AppColors.textMuted),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
  ]);
}

class _VitalCard extends StatelessWidget {
  const _VitalCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final st = data['stats'] as Map<String, dynamic>;
    final normal = data['normal'] as Map<String, dynamic>;
    final ok = st['in_normal_range'] == true;
    final points = [
      for (final p in data['points'] as List)
        TrendPoint(DateTime.parse(p['at'] as String).toLocal(), [
          (p['value'] as num).toDouble(),
          if (p['value2'] != null) (p['value2'] as num).toDouble(),
        ])
    ];
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('${data['label']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.deep)),
        ),
        _direction(st['direction'] as String),
      ]),
      if (normal['low'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${ok ? 'Latest is in the normal range' : 'Latest is outside the normal range'} '
            '(${_n(normal['low'] as num)}–${_n(normal['high'] as num)} ${data['unit']})',
            style: TextStyle(fontSize: 12, color: ok ? AppColors.success : AppColors.critical),
          ),
        ),
      const SizedBox(height: 8),
      TrendChart(points: points, unit: '${data['unit']}', color: ok ? AppColors.green : AppColors.critical),
      const SizedBox(height: 8),
      Row(children: [
        _stat('Average', _n(st['average'] as num)),
        _stat('Lowest', _n(st['min'] as num)),
        _stat('Highest', _n(st['max'] as num)),
        _stat('Readings', '${st['count']}'),
      ]),
    ]));
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final st = data['stats'] as Map<String, dynamic>;
    final points = [
      for (final p in data['points'] as List)
        TrendPoint(DateTime.parse(p['at'] as String).toLocal(), [(p['value'] as num).toDouble()])
    ];
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('${data['name']}',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.deep)),
        ),
        _direction(st['direction'] as String),
      ]),
      const SizedBox(height: 8),
      TrendChart(points: points, unit: '${data['unit']}', color: AppColors.records),
      Text('Change since first report: ${(st['change'] as num) > 0 ? '+' : ''}${_n(st['change'] as num)} ${data['unit']}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
    ]));
  }
}

class _AdherenceCard extends StatelessWidget {
  const _AdherenceCard({required this.weeks});
  final List<Map<String, dynamic>> weeks;

  @override
  Widget build(BuildContext context) {
    return _card(Column(children: [
      for (final w in weeks.reversed.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
                width: 78,
                child: Text('Week of ${DateTime.parse(w['week'] as String).day}/${DateTime.parse(w['week'] as String).month}',
                    style: const TextStyle(fontSize: 12))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 12,
                  value: ((w['percent'] as num?) ?? 0) / 100,
                  backgroundColor: AppColors.criticalTint,
                  color: ((w['percent'] as num?) ?? 0) >= 80 ? AppColors.green : const Color(0xFFD97706),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 44,
                child: Text('${w['percent'] ?? '—'}%',
                    textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
    ]));
  }
}

class _AddReadingSheet extends StatefulWidget {
  const _AddReadingSheet({required this.repository});
  final HealthRepository repository;

  @override
  State<_AddReadingSheet> createState() => _AddReadingSheetState();
}

class _AddReadingSheetState extends State<_AddReadingSheet> {
  String _kind = 'bp';
  final _v1 = TextEditingController();
  final _v2 = TextEditingController();
  DateTime _at = DateTime.now();
  bool _saving = false;

  Future<void> _save() async {
    final a = double.tryParse(_v1.text.trim());
    final b = double.tryParse(_v2.text.trim());
    if (a == null || (_kind == 'bp' && b == null)) {
      showMessage(context, _kind == 'bp' ? 'Enter both numbers, e.g. 120 and 80.' : 'Enter a number.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.addVital(_kind, a, value2: _kind == 'bp' ? b : null, at: _at);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(
        context: context, initialDate: _at, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute));
  }

  @override
  Widget build(BuildContext context) {
    final unit = vitalKinds[_kind]!.unit;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add a reading', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in vitalKinds.entries)
                ChoiceChip(label: Text(e.value.label), selected: _kind == e.key, onSelected: (_) => setState(() => _kind = e.key)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _v1,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: _kind == 'bp' ? 'Top (systolic)' : 'Value', suffixText: unit),
                ),
              ),
              if (_kind == 'bp') ...[
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _v2,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Bottom (diastolic)', suffixText: 'mmHg'),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text('${_at.day}/${_at.month}/${_at.year}  ${TimeOfDay.fromDateTime(_at).format(context)}'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save reading'),
            ),
          ]),
        ),
      ),
    );
  }
}
