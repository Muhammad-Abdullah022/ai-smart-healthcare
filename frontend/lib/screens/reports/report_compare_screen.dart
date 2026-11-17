import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/report_repository.dart';
import '../../widgets/state_views.dart';
import 'report_widgets.dart';
import 'reports_screen.dart';

/// Feature 9: pick an older and a newer report and see how each value changed.
class ReportCompareScreen extends StatefulWidget {
  const ReportCompareScreen({super.key, required this.repository, this.newId});

  final ReportRepository repository;

  /// Pre-selected newer report (opened from a report).
  final String? newId;

  @override
  State<ReportCompareScreen> createState() => _ReportCompareScreenState();
}

class _ReportCompareScreenState extends State<ReportCompareScreen> {
  late Future<List<ReportSummary>> _future = widget.repository.list();
  final List<String> _picked = [];
  ReportComparison? _result;
  List<ReportSummary> _all = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.newId != null) _picked.add(widget.newId!);
  }

  void _toggle(String id) => setState(() {
        _result = null;
        _error = null;
        if (_picked.contains(id)) {
          _picked.remove(id);
        } else {
          if (_picked.length == 2) _picked.removeAt(0);
          _picked.add(id);
        }
      });

  Future<void> _compare() async {
    // Older report = the one created first.
    final chosen = _all.where((r) => _picked.contains(r.id)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await widget.repository.compare(chosen.first.id, chosen.last.id);
      if (mounted) setState(() => _result = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Old vs new report')),
      body: FutureBuilder<List<ReportSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            return ErrorView(
                message: 'Could not load reports.',
                onRetry: () => setState(() => _future = widget.repository.list()));
          }
          _all = snap.data!.where((r) => r.analyzed).toList();
          if (_all.length < 2) {
            return const EmptyView(
              icon: Icons.compare_arrows,
              title: 'Two reports needed',
              message: 'Upload an older and a newer report of the same test, then compare them here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text('Choose two reports of the same test', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              for (final r in _all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ReportTile(report: r, selected: _picked.contains(r.id), onTap: () => _toggle(r.id)),
                ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: _picked.length == 2 && !_busy ? _compare : null,
                icon: const Icon(Icons.compare_arrows),
                label: Text(_busy ? 'Comparing…' : 'Compare'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: AppColors.critical)),
                ),
              if (_result != null) ...[
                const SizedBox(height: 18),
                if (_result!.rows.isEmpty)
                  const Text('No matching tests were found in these two reports.')
                else
                  _CompareTable(rows: _result!.rows),
                const SizedBox(height: 10),
                Text(_result!.note, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.rows});
  final List<CompareRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8EC)),
      ),
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            Expanded(flex: 4, child: Text('Test', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
            Expanded(flex: 3, child: Text('Old', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
            Expanded(flex: 3, child: Text('New', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
          ]),
        ),
        for (final r in rows) ...[
          const Divider(height: 1, color: Color(0xFFEDF1F4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                flex: 4,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (r.nowNormal)
                    const Text('Now normal', style: TextStyle(fontSize: 12, color: AppColors.success))
                  else if (r.nowAbnormal)
                    const Text('Now outside range', style: TextStyle(fontSize: 12, color: AppColors.critical)),
                ]),
              ),
              Expanded(
                flex: 3,
                child: Text('${r.oldValue} ${r.unit}'.trim(), style: TextStyle(color: flagColor(r.oldFlag))),
              ),
              Expanded(
                flex: 3,
                child: Row(children: [
                  Flexible(
                    child: Text('${r.newValue} ${r.unit}'.trim(),
                        style: TextStyle(color: flagColor(r.newFlag), fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    switch (r.change) {
                      'up' => Icons.arrow_upward,
                      'down' => Icons.arrow_downward,
                      'same' => Icons.remove,
                      _ => Icons.more_horiz,
                    },
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
