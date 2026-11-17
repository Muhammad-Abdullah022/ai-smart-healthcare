import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/health_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import '../doctors/doctors_screens.dart';
import '../modules/feature_form_screen.dart';
import '../pharmacy/medicine_search_screen.dart';

/// Feature 38 (with 39 and 50): one health record built automatically from everything in the app —
/// symptom checks, reports, prescriptions, medicines, vitals, history — plus a locked PDF and a QR code.
class HealthRecordScreen extends StatefulWidget {
  const HealthRecordScreen({super.key, this.showAppBar = true});
  final bool showAppBar;

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  late final HealthRepository _repo = HealthRepository(context.read<AuthProvider>().repository.api);
  late Future<Map<String, dynamic>> _future = _repo.record();

  void _reload() => setState(() => _future = _repo.record());

  Future<String?> _askPassword(String action) async {
    final ctrl = TextEditingController();
    var hidden = true;
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(action),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Enter your login password. The PDF is locked with it — it opens only with this password.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: hidden,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setD(() => hidden = !hidden),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Continue')),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return (pw == null || pw.isEmpty) ? null : pw;
  }

  Future<({String url, int hours})?> _makeLink(String action) async {
    final pw = await _askPassword(action);
    if (pw == null || !mounted) return null;
    try {
      return await _repo.share(pw);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
      return null;
    }
  }

  Future<void> _exportPdf() async {
    final link = await _makeLink('Download PDF');
    if (link == null) return;
    final ok = await launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, 'Could not open the PDF. Use the QR code instead.', error: true);
  }

  Future<void> _showQr() async {
    final link = await _makeLink('Show QR code');
    if (link == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Scan to open my health record',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.deep)),
            const SizedBox(height: 6),
            Text('The PDF opens only with my login password. This code works for ${link.hours} hours.',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
              child: QrImageView(data: link.url, size: 230, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy link'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link.url));
                    showMessage(ctx, 'Link copied');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.link_off, size: 18, color: AppColors.critical),
                  label: const Text('Turn off', style: TextStyle(color: AppColors.critical)),
                  onPressed: () async {
                    await _repo.stopSharing().catchError((_) {});
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) showMessage(context, 'Shared links turned off.');
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _addHistory() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeatureFormScreen(number: 39)));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) return ErrorView(message: 'Could not load your health record.', onRetry: _reload);
        final r = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            _patientCard(r['patient'] as Map<String, dynamic>),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                  onPressed: _exportPdf,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('QR code'),
                  onPressed: _showQr,
                ),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 6),
              child: Text('Saved automatically from your symptom checks, reports, prescriptions, medicines and readings.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            _vitals(r['vitals'] as Map<String, dynamic>),
            _section(Icons.medication_outlined, 'Medicines', AppColors.medicine,
                [for (final m in (r['medicines'] as List).where((m) => m['active'] == true)) _medTile(m as Map<String, dynamic>)],
                footer: _adherence(r['adherence_30d'] as Map<String, dynamic>)),
            _section(Icons.biotech_outlined, 'Reports & scans', AppColors.records,
                [for (final x in r['reports'] as List) _reportTile(x as Map<String, dynamic>)]),
            _section(Icons.monitor_heart_outlined, 'Symptom checks (AI assistant)', AppColors.green,
                [for (final x in r['symptom_checks'] as List) _checkTile(x as Map<String, dynamic>)]),
            _section(Icons.local_pharmacy_outlined, 'Medicines suggested by AI chatbot', AppColors.medicine,
                [for (final x in (r['ai_medicines'] as List? ?? const [])) _aiMedTile(x as Map<String, dynamic>)],
                footer: (r['ai_medicines'] as List? ?? const []).isEmpty
                    ? null
                    : const Text('Over-the-counter options only, no doses. Ask a pharmacist or doctor before taking.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted))),
            _section(Icons.medical_services_outlined, 'Recommended doctors & websites', AppColors.records,
                [for (final x in (r['recommended_doctors'] as List? ?? const [])) _doctorTile(x as Map<String, dynamic>)]),
            _section(Icons.receipt_long_outlined, 'Prescriptions', AppColors.deep,
                [for (final x in r['prescriptions'] as List) _rxTile(x as Map<String, dynamic>)]),
            _section(Icons.history_edu_outlined, 'Medical history', AppColors.mind,
                [for (final x in r['history'] as List) _historyTile(x as Map<String, dynamic>)],
                action: TextButton.icon(onPressed: _addHistory, icon: const Icon(Icons.add, size: 18), label: const Text('Add'))),
            if ((r['mental_health'] as List).isNotEmpty)
              _section(Icons.self_improvement, 'Mental wellbeing', AppColors.mind,
                  [for (final x in r['mental_health'] as List) _simple('${x['test']} · ${x['severity']}', 'Score ${x['score']} · ${_d(x['date'])}')]),
            if ((r['appointments'] as List).isNotEmpty)
              _section(Icons.event_available_outlined, 'Appointment requests', AppColors.records,
                  [for (final x in r['appointments'] as List) _simple('${x['doctor']} (${x['specialty']})', '${_d(x['date'])} · ${x['status']}')]),
          ]),
        );
      },
    );
    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text('My health record')), body: body);
  }

  static String _d(Object? iso) {
    final s = iso?.toString() ?? '';
    final d = DateTime.tryParse(s);
    return d == null ? s : '${d.day}/${d.month}/${d.year}';
  }

  Widget _patientCard(Map<String, dynamic> p) {
    Widget chips(String label, List items, Color c) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('$label: ', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12.5)),
              for (final i in items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                  child: Text('$i', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
          );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.deep, AppColors.green]),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(radius: 26, backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white, size: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              Text(
                  [
                    if (p['age'] != null) '${p['age']} years',
                    if (p['gender'] != null) '${p['gender']}',
                    if (p['city'] != null) '${p['city']}',
                  ].join(' · '),
                  style: TextStyle(color: Colors.white.withAlpha(215))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              const Text('Blood', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              Text('${p['blood_group'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.critical, fontSize: 16)),
            ]),
          ),
        ]),
        chips('Allergies', p['allergies'] as List? ?? const [], const Color(0x66DC2626)),
        chips('Conditions', p['conditions'] as List? ?? const [], Colors.white24),
      ]),
    );
  }

  Widget _vitals(Map<String, dynamic> v) {
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in v.values)
          Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['label']}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(
                  '${_n(e['value'])}${e['value2'] != null ? '/${_n(e['value2'])}' : ''} ${e['unit']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.deep)),
              Text('${_d(e['at'])}${e['source'] == 'watch' ? ' · watch' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
      ]),
    );
  }

  static String _n(Object? v) {
    final d = (v as num?)?.toDouble() ?? 0;
    return d % 1 == 0 ? d.toInt().toString() : d.toStringAsFixed(1);
  }

  final Set<String> _showAll = {};

  Widget _section(IconData icon, String title, Color color, List<Widget> children, {Widget? footer, Widget? action}) {
    const preview = 4;
    final all = _showAll.contains(title);
    final visible = all ? children : children.take(preview).toList();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: children.isNotEmpty,
          shape: const RoundedRectangleBorder(),
          tilePadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep, fontSize: 16)),
          subtitle: Text(children.isEmpty ? 'Nothing saved yet' : '${children.length} saved',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          trailing: action,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            ...visible,
            if (children.length > preview)
              TextButton.icon(
                onPressed: () => setState(() => all ? _showAll.remove(title) : _showAll.add(title)),
                icon: Icon(all ? Icons.expand_less : Icons.expand_more),
                label: Text(all ? 'Show less' : 'Show all ${children.length}'),
              ),
            if (footer != null) footer,
          ],
        ),
      ),
    );
  }

  static String _niceText(String t) {
    final s = t.trim();
    if (s.isEmpty) return s;
    // "MUJY SAR DARD HA" -> "Mujy sar dard ha"
    final lower = s == s.toUpperCase() ? s.toLowerCase() : s;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  static Widget _dateChip(String iso) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(_d(iso), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]);

  static Widget _levelBadge(String level) {
    final l = level.toLowerCase();
    final (fg, bg, label) = switch (l) {
      'emergency' || 'urgent' => (AppColors.critical, AppColors.criticalTint, l == 'emergency' ? 'Emergency' : 'Urgent'),
      'soon' || 'see_doctor' || 'moderate' => (const Color(0xFFB45309), AppColors.warningTint, 'See a doctor soon'),
      'routine' || 'self_care' || 'normal' || 'low' => (AppColors.success, AppColors.mint, 'Routine'),
      _ => (AppColors.textMuted, AppColors.primaryTint, level.isEmpty ? '—' : level),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  static Widget _itemCard({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _simple(String title, String sub) => _itemCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.deep)),
          if (sub.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
            ),
        ]),
      );

  Widget _medTile(Map<String, dynamic> m) => _simple(
      '${m['name']} ${m['strength'] ?? ''}'.trim(),
      [
        if ((m['salt'] ?? '').toString().isNotEmpty) m['salt'],
        (m['times'] as List).join(', '),
        if ((m['instructions'] ?? '').toString().isNotEmpty) m['instructions'],
      ].join(' · '));

  Widget _adherence(Map<String, dynamic> a) {
    final total = (a['taken'] as int) + (a['missed'] as int) + (a['skipped'] as int);
    if (total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('Last 30 days: ${a['taken']} taken · ${a['missed']} missed · ${a['skipped']} skipped '
          '(${(100 * (a['taken'] as int) / total).round()}% on time)',
          style: const TextStyle(fontSize: 12.5, color: AppColors.green, fontWeight: FontWeight.w600)),
    );
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final ab = (r['abnormal'] as List).cast<Map<String, dynamic>>();
    final type = '${r['type']}';
    final t = type.toLowerCase();
    final icon = t.contains('x-ray') || t.contains('xray') || t.contains('scan') || t.contains('ultrasound') || t.contains('mri')
        ? Icons.image_search_outlined
        : t.contains('prescription')
            ? Icons.receipt_long_outlined
            : Icons.science_outlined;
    return _itemCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.recordsTint, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: AppColors.records, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.deep)),
              const SizedBox(height: 2),
              _dateChip('${r['date']}'),
            ]),
          ),
          if (ab.isNotEmpty) _levelBadge(ab.any((v) => v['critical'] == true) ? 'urgent' : 'moderate'),
        ]),
        if ('${r['summary'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${r['summary']}', style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ),
        const SizedBox(height: 10),
        if (ab.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 15, color: AppColors.success),
              SizedBox(width: 5),
              Text('All values in range', style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600)),
            ]),
          )
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in ab)
              Builder(builder: (_) {
                final high = v['flag'] == 'high';
                final critical = v['critical'] == true;
                final fg = critical ? AppColors.critical : (high ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8));
                final bg = critical ? AppColors.criticalTint : (high ? const Color(0xFFFDECEC) : const Color(0xFFE8F0FE));
                return Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(high ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: fg),
                    const SizedBox(width: 3),
                    Text('${v['name']} ', style: const TextStyle(fontSize: 12, color: AppColors.text)),
                    Text('${v['value']} ${v['unit']}', style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w700)),
                  ]),
                );
              }),
          ]),
      ]),
    );
  }

  Widget _checkTile(Map<String, dynamic> c) {
    final causes = (c['possible_causes'] as List).cast<String>();
    final doctor = '${c['specialist'] ?? ''}';
    return _itemCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _levelBadge('${c['urgency'] ?? ''}'),
          const Spacer(),
          _dateChip('${c['date']}'),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.chat_bubble_outline, size: 17, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text('"${_niceText('${c['symptoms']}')}"',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.deep)),
          ),
        ]),
        if (causes.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Possible causes', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 5),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final cause in causes)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.softGreen),
                ),
                child: Text(cause, style: const TextStyle(fontSize: 12.5, color: AppColors.deep)),
              ),
          ]),
        ],
        if ((c['otc_options'] as List? ?? const []).isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('AI suggested medicines (no dose)', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 5),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in c['otc_options'] as List)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.medication_outlined, size: 14, color: AppColors.green),
                  const SizedBox(width: 4),
                  Text('${o['name']}', style: const TextStyle(fontSize: 12.5, color: AppColors.deep, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ],
        if (doctor.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.medical_services_outlined, size: 16, color: AppColors.records),
            const SizedBox(width: 6),
            Text('See: $doctor', style: const TextStyle(fontSize: 12.5, color: AppColors.records, fontWeight: FontWeight.w600)),
          ]),
        ],
      ]),
    );
  }

  Widget _aiMedTile(Map<String, dynamic> m) => _itemCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.medication_liquid_outlined, size: 18, color: AppColors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text('${m['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.deep))),
            _dateChip('${m['date']}'),
          ]),
          if ('${m['helps_with'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoLine(Icons.check_circle_outline, AppColors.green, 'Helps with: ${m['helps_with']}'),
          ],
          if ('${m['avoid_if'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            _infoLine(Icons.warning_amber_rounded, Colors.orange.shade800, 'Avoid if: ${m['avoid_if']}'),
          ],
          if ('${m['for_symptoms'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            _infoLine(Icons.chat_bubble_outline, AppColors.textMuted, 'Suggested for: "${_niceText('${m['for_symptoms']}')}"'),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MedicineSearchScreen(initialQuery: '${m['name']}'))),
              icon: const Icon(Icons.search, size: 17),
              label: const Text('Brands & prices'),
            ),
          ),
        ]),
      );

  Widget _doctorTile(Map<String, dynamic> d) {
    final sites = (d['websites'] as List? ?? const []).cast<Map<String, dynamic>>();
    return _itemCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: AppColors.recordsTint, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.person_search_outlined, size: 18, color: AppColors.records),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text('${d['specialist']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.deep))),
          _dateChip('${d['date']}'),
        ]),
        if ('${d['for_symptoms'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          _infoLine(Icons.chat_bubble_outline, AppColors.textMuted, 'For: "${_niceText('${d['for_symptoms']}')}"'),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DoctorListScreen(specialty: '${d['specialist']}', reason: 'Recommended in your health record'))),
            icon: const Icon(Icons.search, size: 17),
            label: const Text('Find in app'),
          ),
          for (final w in sites)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => openExternal(context, Uri.parse('${w['url']}')),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text('${w['site']}'),
            ),
        ]),
      ]),
    );
  }

  static Widget _infoLine(IconData icon, Color color, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.deep, height: 1.35))),
      ]);

  Widget _rxTile(Map<String, dynamic> x) =>
      _simple('${x['doctor'].toString().isEmpty ? 'Prescription' : x['doctor']} · ${_d(x['date'])}', (x['medicines'] as List).join('\n'));

  Widget _historyTile(Map<String, dynamic> h) =>
      _simple('${h['name']}', [h['kind'], if ('${h['year']}'.isNotEmpty) '${h['year']}', if ('${h['notes']}'.isNotEmpty) h['notes']].join(' · '));
}
