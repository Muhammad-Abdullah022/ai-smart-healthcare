import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/report_repository.dart';
import '../../widgets/state_views.dart';
import 'report_compare_screen.dart';
import 'report_widgets.dart';

String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Feature 8: the user's medical reports. Upload a photo/PDF and the AI explains it.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.repository});

  final ReportRepository? repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportRepository _repo =
      widget.repository ?? ReportRepository(context.read<AuthProvider>().repository.api);
  late Future<List<ReportSummary>> _future = _repo.list();
  bool _uploading = false;

  void _reload() => setState(() => _future = _repo.list());

  Future<void> _upload() async {
    final picked = await pickReport(context);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final r = await _repo.upload(bytes: picked.bytes, fileName: picked.name, mimeType: mimeTypeFor(picked.name));
      if (!mounted) return;
      _reload();
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ReportDetailScreen(repository: _repo, report: r)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(String id) async {
    try {
      final r = await _repo.get(id);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ReportDetailScreen(repository: _repo, report: r)));
      _reload();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My reports'),
        actions: [
          IconButton(
            tooltip: 'Compare old vs new',
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => ReportCompareScreen(repository: _repo))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file_outlined),
        label: Text(_uploading ? 'Reading report…' : 'Upload report'),
      ),
      body: FutureBuilder<List<ReportSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(message: e is ApiException ? e.message : 'Could not load reports.', onRetry: _reload);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.document_scanner_outlined,
              title: 'No reports yet',
              message: 'Upload a photo or PDF of a lab report. The AI explains it in simple words.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => ReportTile(report: items[i], onTap: () => _open(items[i].id)),
          );
        },
      ),
    );
  }
}

class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, this.onTap, this.selected = false});

  final ReportSummary report;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final sub = [
      r.reportDate ?? shortDate(r.createdAt),
      if (!r.analyzed) 'not read yet' else if (r.abnormalCount > 0) '${r.abnormalCount} outside range' else 'all in range',
    ].join(' · ');
    return Material(
      color: selected ? AppColors.accentTint : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.accent : const Color(0xFFE2E8EC)),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.diagnosisTint, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.description_outlined, color: AppColors.diagnosis),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 13, color: r.abnormalCount > 0 ? AppColors.warning : AppColors.textMuted)),
              ]),
            ),
            Icon(selected ? Icons.check_circle : Icons.chevron_right,
                color: selected ? AppColors.accent : AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

/// One report: everything the AI read, with a retry if reading failed.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.repository, required this.report});

  final ReportRepository repository;
  final MedicalReport report;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late MedicalReport _report = widget.report;
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final r = await widget.repository.reanalyze(_report.id);
      if (mounted) setState(() => _report = r);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_report.analysis?.reportType ?? 'Report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ReportAnalysisCard(
            report: _report,
            showAllValues: true,
            onCompare: _report.analysis == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReportCompareScreen(repository: widget.repository, newId: _report.id))),
          ),
          if (_report.analysis == null)
            FilledButton.icon(
              onPressed: _busy ? null : _retry,
              icon: const Icon(Icons.refresh),
              label: Text(_busy ? 'Reading…' : 'Try reading again'),
            ),
        ],
      ),
    );
  }
}
