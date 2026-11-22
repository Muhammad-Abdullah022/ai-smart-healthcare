import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../services/report_repository.dart';

/// A picked report file, ready to upload.
class PickedReport {
  PickedReport(this.bytes, this.name);
  final List<int> bytes;
  final String name;
}

/// Ask the user for a report: camera photo, gallery photo, or a PDF/image file.
/// Returns null if they cancel.
Future<PickedReport?> pickReport(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
          title: const Text('Take a photo of the report'),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
          title: const Text('Choose a photo'),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.accent),
          title: const Text('Choose a PDF or file'),
          onTap: () => Navigator.pop(ctx, 'file'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null) return null;
  if (source == 'file') {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final f = result?.files.single;
    if (f == null || f.bytes == null) return null;
    return PickedReport(f.bytes!, f.name);
  }
  final photo = await ImagePicker().pickImage(
    source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 85,
    maxWidth: 2200,
  );
  if (photo == null) return null;
  return PickedReport(await photo.readAsBytes(), photo.name);
}

Color flagColor(String flag) => switch (flag) {
      'high' => AppColors.critical,
      'low' => AppColors.warning,
      'normal' => AppColors.success,
      _ => AppColors.textMuted,
    };

String flagLabel(String flag) => switch (flag) {
      'high' => 'High',
      'low' => 'Low',
      'normal' => 'Normal',
      _ => '—',
    };

/// What the AI read from one report: summary, abnormal values first, doctor and next steps.
class ReportAnalysisCard extends StatelessWidget {
  const ReportAnalysisCard({super.key, required this.report, this.onCompare, this.showAllValues = false});

  final MedicalReport report;
  final VoidCallback? onCompare;
  final bool showAllValues;

  @override
  Widget build(BuildContext context) {
    final a = report.analysis;
    if (a == null) {
      return _Shell(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(report.error ?? 'The report was saved but could not be read yet.',
              style: const TextStyle(color: AppColors.critical)),
        ),
      );
    }
    final abnormal = a.values.where((v) => v.abnormal).toList();
    final shown = showAllValues ? a.values : (abnormal.isNotEmpty ? abnormal : a.values.take(5).toList());
    final (uColor, uTint, uLabel) = switch (a.urgency) {
      'urgent' => (AppColors.critical, AppColors.criticalTint, 'See a doctor today'),
      'soon' => (AppColors.warning, AppColors.warningTint, 'See a doctor in the next few days'),
      _ => (AppColors.success, const Color(0xFFF1EBFE), 'Discuss at your next visit'),
    };
    return _Shell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: uTint,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            CircleAvatar(
                radius: 17, backgroundColor: uColor, child: const Icon(Icons.description_outlined, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.reportType, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(uLabel, style: TextStyle(color: uColor, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
            if (a.reportDate != null)
              Text(a.reportDate!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(a.summary, style: const TextStyle(height: 1.45)),
        ),
        if (shown.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
                showAllValues
                    ? 'All values'
                    : abnormal.isNotEmpty
                        ? 'Outside the normal range (${abnormal.length})'
                        : 'Values',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          for (final v in shown) ValueRow(value: v),
        ],
        if (a.doctorType.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              const Icon(Icons.medical_services_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Doctor to see: ', style: TextStyle(color: AppColors.textMuted)),
                  TextSpan(text: a.doctorType, style: const TextStyle(fontWeight: FontWeight.w600)),
                ])),
              ),
            ]),
          ),
        for (final s in a.nextSteps.take(3))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 14))),
            ]),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Values read by AI; low / normal / high checked by the app against the reference range. Please confirm with your doctor.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
        if (onCompare != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.compare_arrows, size: 18),
                label: const Text('Compare with an older report'),
                onPressed: onCompare,
              ),
            ),
          )
        else
          const SizedBox(height: 12),
      ]),
    );
  }
}

class ValueRow extends StatelessWidget {
  const ValueRow({super.key, required this.value});
  final ReportValue value;

  @override
  Widget build(BuildContext context) {
    final c = value.critical ? AppColors.critical : flagColor(value.flag);
    final range = value.range.isNotEmpty ? value.range : value.standardRange;
    final source = switch (value.flagSource) {
      'report' => 'checked against the report\'s range',
      'standard' => 'checked against the standard adult range',
      _ => '',
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: value.critical ? AppColors.criticalTint : (value.abnormal ? c.withAlpha(18) : AppColors.background),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: c, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(value.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${value.value} ${value.unit}'.trim(), style: TextStyle(fontWeight: FontWeight.w700, color: c)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: c.withAlpha(31), borderRadius: BorderRadius.circular(10)),
            child: Text(value.critical ? 'Very ${flagLabel(value.flag).toLowerCase()}' : flagLabel(value.flag),
                style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (range.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('Normal: $range${source.isEmpty ? '' : '  ·  $source'}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ),
        if (value.about.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(value.about, style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.3)),
          ),
      ]),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8EC)),
          boxShadow: const [BoxShadow(color: Color(0x0F2A1B4D), blurRadius: 16, offset: Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}
