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
                  return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.deep, AppColors.green]),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.document_scanner_outlined, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Read your prescription',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          'Take a photo of the doctor\'s prescription. The AI reads the handwriting and tells you each medicine, '
          'how to take it and for how long.',
          style: TextStyle(color: Colors.white.withAlpha(225), height: 1.45),
        ),
        const SizedBox(height: 14),
        Text('Explain in', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final l in chatLanguages)
            ChoiceChip(
              label: Text(l.label),
              selected: _language == l.code,
              onSelected: (_) => setState(() => _language = l.code),
              selectedColor: Colors.white,
              backgroundColor: Colors.white.withAlpha(30),
              side: BorderSide(color: Colors.white.withAlpha(90)),
              labelStyle: TextStyle(
                  color: _language == l.code ? AppColors.deep : Colors.white, fontWeight: FontWeight.w600),
              showCheckmark: false,
            ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.deep,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _reading ? null : () => _pick('camera'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
              onPressed: _reading ? null : () => _pick('gallery'),
            ),
          ),
        ]),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('Upload a PDF or file'),
            onPressed: _reading ? null : () => _pick('file'),
          ),
        ),
      ]),
    );
  }

  Widget _tips() {
    Widget tip(IconData i, String t) => Expanded(
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
              child: Icon(i, color: AppColors.green, size: 20),
            ),
            const SizedBox(height: 6),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ]),
        );
    return Row(children: [
      tip(Icons.wb_sunny_outlined, 'Good light,\nno shadow'),
      tip(Icons.crop_free, 'Whole page\nin the photo'),
      tip(Icons.straighten, 'Paper flat,\ncamera straight'),
      tip(Icons.verified_user_outlined, 'You check\nbefore saving'),
    ]);
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
