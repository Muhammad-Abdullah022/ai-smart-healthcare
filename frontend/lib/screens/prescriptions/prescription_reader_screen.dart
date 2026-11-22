import '../../widgets/capsule_loader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/chat_language.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/prescription_repository.dart';
import '../../services/report_repository.dart' show mimeTypeFor;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import 'prescription_result_screen.dart';

/// Feature 26 (and 34): photograph a prescription; the AI reads the doctor's handwriting and explains it.
class PrescriptionReaderScreen extends StatefulWidget {
  const PrescriptionReaderScreen({super.key});

  @override
  State<PrescriptionReaderScreen> createState() => _PrescriptionReaderScreenState();
}

class _PrescriptionReaderScreenState extends State<PrescriptionReaderScreen> {
  late final PrescriptionRepository _repo = PrescriptionRepository(context.read<AuthProvider>().repository.api);
  late Future<List<PrescriptionSummary>> _list = _repo.list();
  String _language = 'en';
  bool _reading = false;

  void _reload() => setState(() => _list = _repo.list());

  Future<void> _pick(String source) async {
    List<int>? bytes;
    String name = 'prescription.jpg';
    try {
      if (source == 'file') {
        final r = await FilePicker.platform.pickFiles(
            type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'], withData: true);
        final f = r?.files.single;
        if (f?.bytes == null) return;
        bytes = f!.bytes!;
        name = f.name;
      } else {
        final photo = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2400,
        );
        if (photo == null) return;
        bytes = await photo.readAsBytes();
        name = photo.name.isEmpty ? name : photo.name;
      }
    } catch (_) {
      if (mounted) showMessage(context, 'Could not open the camera or gallery.', error: true);
      return;
    }
    final data = bytes;
    if (data == null) return;
    setState(() => _reading = true);
    try {
      final rx = await _repo.upload(bytes: data, fileName: name, mimeType: mimeTypeFor(name), language: _language);
      if (!mounted) return;
      setState(() => _reading = false);
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PrescriptionResultScreen(
              repository: _repo, prescription: rx, imageBytes: mimeTypeFor(name).startsWith('image/') ? data : null)));
      _reload();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _reading = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  Future<void> _open(PrescriptionSummary s) async {
    try {
      final rx = await _repo.get(s.id);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PrescriptionResultScreen(repository: _repo, prescription: rx)));
      _reload();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prescription reader')),
      body: Stack(children: [
        RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            _hero(),
            const SizedBox(height: 14),
            _tips(),
            const SizedBox(height: 20),
            const Text('Your prescriptions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
            const SizedBox(height: 8),
            FutureBuilder<List<PrescriptionSummary>>(
              future: _list,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(24), child: Center(child: CapsuleLoader(size: 48)));
                }
                if (snap.hasError) return ErrorView(message: 'Could not load prescriptions.', onRetry: _reload);
                final list = snap.data!;
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No prescriptions yet. Take a photo of one to start.',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(children: [for (final s in list) _SummaryTile(summary: s, onTap: () => _open(s))]);
              },
            ),
          ]),
        ),
        if (_reading) const _ReadingOverlay(),
      ]),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.deep, Color(0xFF0F766E)]),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Read your prescription',
                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text('AI reads the doctor\'s handwriting: each medicine, how to take it and for how long.',
                  style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13.5, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 30),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Explain in', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        // Segmented language picker (custom, so the text is always readable on the dark card).
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.black.withAlpha(45), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            for (final l in chatLanguages)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _language = l.code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _language == l.code ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(l.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _language == l.code ? AppColors.deep : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFC857),
            foregroundColor: AppColors.deep,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          icon: const Icon(Icons.photo_camera_rounded),
          label: const Text('Scan with camera'),
          onPressed: _reading ? null : () => _pick('camera'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ghostButton(Icons.photo_library_outlined, 'Gallery', () => _pick('gallery'))),
          const SizedBox(width: 10),
          Expanded(child: _ghostButton(Icons.picture_as_pdf_outlined, 'PDF / file', () => _pick('file'))),
        ]),
      ]),
    );
  }

  Widget _ghostButton(IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withAlpha(18),
          side: BorderSide(color: Colors.white.withAlpha(120)),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onPressed: _reading ? null : onTap,
      );

  Widget _tips() {
    Widget step(int n, IconData i, String title, String text) => Expanded(
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(15)),
                child: Icon(i, color: AppColors.green, size: 22),
              ),
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.deep, shape: BoxShape.circle),
                  child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.deep)),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          step(1, Icons.wb_sunny_outlined, 'Photo', 'Good light, whole page'),
          step(2, Icons.auto_awesome_outlined, 'AI reads', 'Medicines & timings'),
          step(3, Icons.fact_check_outlined, 'You check', 'Fix anything unclear'),
          step(4, Icons.alarm_on_outlined, 'Reminders', 'Set automatically'),
        ]),
      ]),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.summary, required this.onTap});
  final PrescriptionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final (label, fg, bg) = switch (s.status) {
      'verified' => ('Checked', AppColors.success, AppColors.mint),
      'needs_review' => ('Check needed', const Color(0xFFB45309), AppColors.warningTint),
      _ => ('Not read', AppColors.critical, AppColors.criticalTint),
    };
    final d = s.createdAt;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.receipt_long_outlined, color: AppColors.green),
        ),
        title: Text(
          s.medicines.isEmpty ? 'Prescription' : s.medicines.take(3).join(', ') + (s.medicines.length > 3 ? '…' : ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
            '${s.doctorName.isEmpty ? '' : '${s.doctorName} · '}${d.day}/${d.month}/${d.year}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _ReadingOverlay extends StatelessWidget {
  const _ReadingOverlay();

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withAlpha(110),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(height: 16),
                Text('Reading the handwriting…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('This takes about 10–20 seconds.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
          ),
        ),
      );
}
