import '../../widgets/capsule_loader.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/chat_language.dart';
import '../../services/api_client.dart';
import '../../services/assistant_repository.dart';
import '../../services/medicine_repository.dart';
import '../../services/prescription_repository.dart';
import '../../services/voice_service.dart';
import '../../widgets/confirm_dialog.dart';

/// What the AI read from a prescription: each medicine explained, unclear parts marked,
/// then "Check & confirm" and "Add to medicine reminders".
class PrescriptionResultScreen extends StatefulWidget {
  const PrescriptionResultScreen({super.key, required this.repository, required this.prescription, this.imageBytes});

  final PrescriptionRepository repository;
  final Prescription prescription;
  final List<int>? imageBytes;

  @override
  State<PrescriptionResultScreen> createState() => _PrescriptionResultScreenState();
}

class _PrescriptionResultScreenState extends State<PrescriptionResultScreen> {
  late Prescription _rx = widget.prescription;
  Uint8List? _image;
  bool _busy = false;
  late final VoiceService _voice = VoiceService()
    ..toDevanagari = AssistantRepository(widget.repository.api).speech
    ..urduAudio = (text, lang) => widget.repository.api.postForBytes('/voice/tts', {'text': text, 'language': lang});
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    if (widget.imageBytes != null) {
      _image = Uint8List.fromList(widget.imageBytes!);
    } else if (_rx.status != 'error') {
      widget.repository.image(_rx.id).then((b) {
        if (mounted) setState(() => _image = Uint8List.fromList(b));
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _voice.stopSpeaking();
    super.dispose();
  }

  Future<void> _readAgain([String? language]) async {
    setState(() => _busy = true);
    try {
      final rx = await widget.repository.readAgain(_rx.id, language: language);
      if (mounted) setState(() => _rx = rx);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Read the explanation aloud in the prescription's language.
  Future<void> _listen() async {
    if (_speaking) {
      await _voice.stopSpeaking();
      setState(() => _speaking = false);
      return;
    }
    final parts = <String>[
      if (_rx.summary.isNotEmpty) _rx.summary,
      for (final m in _rx.shown)
        [m.name, if (m.strength.isNotEmpty) m.strength, m.howToTake, if (m.duration.isNotEmpty) m.duration]
            .where((p) => p.isNotEmpty)
            .join(', '),
    ];
    setState(() => _speaking = true);
    try {
      await _voice.speakNow(parts.join('. '), _rx.language);
    } catch (_) {}
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _confirm() async {
    final updated = await Navigator.of(context).push<Prescription>(MaterialPageRoute(
        builder: (_) => ConfirmPrescriptionScreen(repository: widget.repository, prescription: _rx)));
    if (updated != null && mounted) setState(() => _rx = updated);
  }

  void _zoom() {
    if (_image == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(_image!))),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rx = _rx;
    final lang = ChatLanguage.byCode(rx.language);
    final failed = rx.status == 'error' || rx.status == 'unreadable';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription'),
        actions: [
          if (!failed)
            IconButton(
              tooltip: _speaking ? 'Stop' : 'Listen',
              icon: Icon(_speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
              onPressed: _listen,
            ),
          PopupMenuButton<String>(
            tooltip: 'Explain in another language',
            icon: const Icon(Icons.translate),
            onSelected: _readAgain,
            itemBuilder: (_) => [
              for (final l in chatLanguages) PopupMenuItem(value: l.code, child: Text('Explain in ${l.label}')),
            ],
          ),
        ],
      ),
      body: Stack(children: [
        Directionality(
          textDirection: lang.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
            if (_image != null) _photo(),
            _statusBanner(),
            if (failed) _failed() else ...[
              _summaryCard(),
              const SizedBox(height: 14),
              Text('Medicines (${rx.shown.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
              const SizedBox(height: 8),
              for (var i = 0; i < rx.shown.length; i++) MedicineReadCard(medicine: rx.shown[i], index: i + 1),
              if (rx.notes.isNotEmpty) _listCard('Doctor\'s other notes', Icons.sticky_note_2_outlined, rx.notes),
              if (rx.warnings.isNotEmpty)
                _listCard('Please note', Icons.health_and_safety_outlined, rx.warnings, warn: true),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    'Read by AI from handwriting. It can make mistakes — always confirm with your pharmacist or '
                    'doctor. The app never changes a dose.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
            ],
          ]),
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withAlpha(180),
              child: const Center(child: CapsuleLoader(size: 48)),
            ),
          ),
      ]),
      bottomNavigationBar: failed ? null : _bottomBar(),
    );
  }

  Widget _photo() => GestureDetector(
        onTap: _zoom,
        child: Container(
          height: 170,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: DecorationImage(image: MemoryImage(_image!), fit: BoxFit.cover),
          ),
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.all(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black.withAlpha(140), borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.zoom_in, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _statusBanner() {
    final (icon, fg, bg, text) = switch (_rx.status) {
      'verified' => (Icons.verified_rounded, AppColors.success, AppColors.mint,
          'You checked these medicines. You can now add them to your reminders.'),
      'needs_review' => (Icons.fact_check_outlined, const Color(0xFFB45309), AppColors.warningTint,
          'Compare each medicine with the paper. Fix anything wrong, then tap "Check & confirm".'),
      'unreadable' => (Icons.image_not_supported_outlined, AppColors.critical, AppColors.criticalTint,
          'The prescription could not be read clearly.'),
      _ => (Icons.cloud_off_outlined, AppColors.critical, AppColors.criticalTint, 'The AI could not read it right now.'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: fg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }

  Widget _failed() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if ((_rx.error ?? _rx.summary).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_rx.error ?? _rx.summary, style: const TextStyle(color: AppColors.textMuted)),
          ),
        const Text('Tips: good light, the whole page in the photo, paper flat, camera held straight.',
            style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        FilledButton.icon(
            icon: const Icon(Icons.refresh), label: const Text('Try reading again'), onPressed: () => _readAgain()),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take a new photo'),
            onPressed: () => Navigator.pop(context)),
      ]);

  Widget _summaryCard() {
    final rx = _rx;
    final who = [rx.doctorName, rx.clinic].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (who.isNotEmpty || rx.date.isNotEmpty)
          Row(children: [
            const Icon(Icons.person_outline, size: 18, color: AppColors.green),
            const SizedBox(width: 6),
            Expanded(
                child: Text(who.isEmpty ? 'Doctor' : who,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.deep))),
            if (rx.date.isNotEmpty)
              Text(rx.date, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        if (who.isNotEmpty || rx.date.isNotEmpty) const SizedBox(height: 10),
        Text(rx.summary, style: const TextStyle(height: 1.5)),
      ]),
    );
  }

  Widget _listCard(String title, IconData icon, List<String> items, {bool warn = false}) => Container(
        margin: const EdgeInsets.only(top: 6, bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: warn ? AppColors.warningTint : AppColors.mint, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: warn ? const Color(0xFFB45309) : AppColors.green),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
          ]),
          const SizedBox(height: 6),
          for (final t in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ', style: TextStyle(fontWeight: FontWeight.w800)),
                Expanded(child: Text(t, style: const TextStyle(height: 1.4))),
              ]),
            ),
        ]),
      );

  Widget _bottomBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _rx.verified
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  icon: const Icon(Icons.alarm_add_outlined),
                  label: const Text('Add to medicine reminders'),
                  onPressed: () => showRemindersFromPrescription(context, _rx, MedicineRepository(widget.repository.api)),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Check & confirm'),
                  onPressed: _confirm,
                ),
        ),
      );
}

/// One medicine as read from the prescription.
class MedicineReadCard extends StatelessWidget {
  const MedicineReadCard({super.key, required this.medicine, required this.index});
  final RxMedicine medicine;
  final int index;

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final unsure = m.unsure;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: unsure ? const Color(0xFFF2C46D) : AppColors.border, width: unsure ? 1.5 : 1),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Icon(_formIcon(m.form), color: AppColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name.isEmpty ? 'Unclear medicine name' : m.name,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: m.name.isEmpty ? AppColors.critical : AppColors.deep)),
                if (m.genericName.isNotEmpty)
                  Text(m.genericName, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (m.strength.isNotEmpty) _chip(m.strength),
                  if (m.form.isNotEmpty) _chip(m.form),
                  if (m.doseAsWritten.isNotEmpty) _chip('Written: ${m.doseAsWritten}'),
                ]),
              ]),
            ),
            Text('#$index', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (m.howToTake.isNotEmpty) _line(Icons.schedule, 'How to take', m.howToTake + (m.timing.isEmpty ? '' : ' · ${m.timing}')),
        if (m.duration.isNotEmpty) _line(Icons.date_range_outlined, 'For how long', m.duration),
        if (m.purpose.isNotEmpty) _line(Icons.info_outline, 'Usually used for', m.purpose),
        if (unsure)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.help_outline, size: 18, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Not sure: ${m.unclearParts.isEmpty ? 'part of this line is hard to read' : m.unclearParts}',
                    style: const TextStyle(color: Color(0xFF92400E), fontSize: 13)),
              ),
            ]),
          )
        else
          const SizedBox(height: 10),
      ]),
    );
  }

  static IconData _formIcon(String form) {
    final f = form.toLowerCase();
    if (f.contains('syr') || f.contains('liquid') || f.contains('susp')) return Icons.local_drink_outlined;
    if (f.contains('inj')) return Icons.vaccines_outlined;
    if (f.contains('drop')) return Icons.water_drop_outlined;
    if (f.contains('cream') || f.contains('oint') || f.contains('gel')) return Icons.sanitizer_outlined;
    if (f.contains('inhal')) return Icons.air;
    return Icons.medication_outlined;
  }

  static Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: const TextStyle(fontSize: 12, color: AppColors.deep, fontWeight: FontWeight.w500)),
      );

  static Widget _line(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ])),
          ),
        ]),
      );
}

/// The user checks every line against the paper, fixes mistakes, removes wrong lines, then confirms.
class ConfirmPrescriptionScreen extends StatefulWidget {
  const ConfirmPrescriptionScreen({super.key, required this.repository, required this.prescription});
  final PrescriptionRepository repository;
  final Prescription prescription;

  @override
  State<ConfirmPrescriptionScreen> createState() => _ConfirmPrescriptionScreenState();
}

class _ConfirmPrescriptionScreenState extends State<ConfirmPrescriptionScreen> {
  late final List<RxMedicine> _meds =
      widget.prescription.shown.map((m) => RxMedicine.fromJson(m.toJson())).toList();
  bool _checked = false;
  bool _saving = false;

  Future<void> _save() async {
    if (_meds.isEmpty) return showMessage(context, 'Keep at least one medicine.', error: true);
    if (_meds.any((m) => m.name.trim().isEmpty)) {
      return showMessage(context, 'Every medicine needs a name. Ask your pharmacist if you cannot read it.',
          error: true);
    }
    setState(() => _saving = true);
    try {
      final rx = await widget.repository.confirm(widget.prescription.id, _meds);
      if (mounted) Navigator.pop(context, rx);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check & confirm')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        const Text('Look at the paper and correct anything that is wrong. Do not change what the doctor wrote.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 12),
        for (var i = 0; i < _meds.length; i++) _editor(i),
        const SizedBox(height: 4),
        CheckboxListTile(
          value: _checked,
          onChanged: (v) => setState(() => _checked = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I checked these medicines against my prescription'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: const Text('Confirm'),
          onPressed: _checked && !_saving ? _save : null,
        ),
      ]),
    );
  }

  Widget _editor(int i) {
    final m = _meds[i];
    Widget field(String label, String value, void Function(String) onChanged, {int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextFormField(
              initialValue: value,
              decoration: InputDecoration(labelText: label, isDense: true),
              onChanged: onChanged,
            ),
          ),
        );
    return Container(
      key: ObjectKey(m),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: m.unsure ? const Color(0xFFF2C46D) : AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          Text('Medicine ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
          if (m.unsure)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('check this one', style: TextStyle(color: Color(0xFFB45309), fontSize: 12)),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Remove this line',
            icon: const Icon(Icons.delete_outline, color: AppColors.critical),
            onPressed: () => setState(() => _meds.removeAt(i)),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(children: [
            Row(children: [
              field('Name', m.name, (v) => m.name = v, flex: 3),
              const SizedBox(width: 8),
              field('Strength', m.strength, (v) => m.strength = v, flex: 2),
            ]),
            Row(children: [field('How to take', m.howToTake, (v) => m.howToTake = v)]),
            Row(children: [
              field('Written as (e.g. 1+0+1)', m.doseAsWritten, (v) => m.doseAsWritten = v, flex: 3),
              const SizedBox(width: 8),
              field('Days', m.durationDays?.toString() ?? '', (v) => m.durationDays = int.tryParse(v), flex: 2),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Feature 34: create reminders from a verified prescription. The user confirms the times for each medicine.
Future<void> showRemindersFromPrescription(BuildContext context, Prescription rx, MedicineRepository repo) async {
  final meds = rx.shown;
  final selected = List<bool>.filled(meds.length, true);
  final times = [for (final m in meds) m.suggestedTimes().isEmpty ? ['09:00'] : m.suggestedTimes()];
  var saving = false;

  String form(String f) {
    final x = f.toLowerCase();
    for (final k in ['tablet', 'capsule', 'syrup', 'injection', 'drops', 'inhaler', 'cream']) {
      if (x.contains(k.substring(0, 3))) return k;
    }
    return x.isEmpty ? 'tablet' : 'other';
  }

  final added = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
            const Text('Add reminders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Times are suggested from the prescription. Tap a time to change it.',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            for (var i = 0; i < meds.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 10),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CheckboxListTile(
                    value: selected[i],
                    onChanged: (v) => setSheet(() => selected[i] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${meds[i].name} ${meds[i].strength}'.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        [meds[i].howToTake, if (meds[i].durationDays != null) '${meds[i].durationDays} days']
                            .where((s) => s.isNotEmpty)
                            .join(' · ')),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var t = 0; t < times[i].length; t++)
                        InputChip(
                          label: Text(times[i][t]),
                          avatar: const Icon(Icons.alarm, size: 16),
                          onPressed: () async {
                            final parts = times[i][t].split(':');
                            final picked = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
                            if (picked != null) {
                              setSheet(() => times[i][t] =
                                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                            }
                          },
                          onDeleted: times[i].length > 1 ? () => setSheet(() => times[i].removeAt(t)) : null,
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Time'),
                        onPressed: times[i].length >= 6 ? null : () => setSheet(() => times[i].add('12:00')),
                      ),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.alarm_add_outlined),
              label: const Text('Save reminders'),
              onPressed: saving || !selected.contains(true)
                  ? null
                  : () async {
                      setSheet(() => saving = true);
                      var count = 0;
                      final today = DateTime.now();
                      String iso(DateTime d) =>
                          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                      for (var i = 0; i < meds.length; i++) {
                        if (!selected[i]) continue;
                        final m = meds[i];
                        final body = {
                          'name': m.name,
                          'salt': m.genericName,
                          'strength': m.strength,
                          'form': form(m.form),
                          'times': times[i],
                          'instructions': [m.howToTake, m.timing].where((s) => s.isNotEmpty).join(' · '),
                          'start_date': iso(today),
                          if (m.durationDays != null && m.durationDays! > 0)
                            'end_date': iso(today.add(Duration(days: m.durationDays! - 1))),
                          'prescription_id': rx.id,
                        };
                        try {
                          await repo.add(body);
                          count++;
                        } on ApiException catch (e) {
                          if (e.code == 'allergy_warning' && ctx.mounted) {
                            final ok = await showConfirmDialog(ctx,
                                title: 'Allergy warning', message: e.message, confirmLabel: 'Add anyway');
                            if (ok) {
                              try {
                                await repo.add(body, confirmAllergy: true);
                                count++;
                              } on ApiException catch (_) {}
                            }
                          } else if (ctx.mounted) {
                            showMessage(ctx, '${m.name}: ${e.message}', error: true);
                          }
                        }
                      }
                      if (ctx.mounted) Navigator.pop(ctx, count);
                    },
            ),
          ]),
        ),
      ),
    ),
  );
  if (added != null && added > 0 && context.mounted) {
    showMessage(context, '$added reminder${added == 1 ? '' : 's'} added. See them in Smart Medicine Reminders.');
  }
}
