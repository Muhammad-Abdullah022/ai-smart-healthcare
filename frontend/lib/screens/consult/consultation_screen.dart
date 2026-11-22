import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/consultation_repository.dart';
import '../../services/live_notifications.dart';
import '../../services/prescription_repository.dart';
import '../../services/report_repository.dart' show mimeTypeFor;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/file_opener.dart';
import '../../widgets/state_views.dart';
import '../prescriptions/prescription_result_screen.dart';
import 'issues_screen.dart';
import 'prescribe_sheet.dart';

/// Live chat between a patient and a doctor, with the consultation steps
/// (accept → pay with screenshot → doctor confirms → prescription or "visit the clinic").
/// The same screen is used by both sides; the buttons depend on who is looking.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, required this.id});

  final String id;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late final ConsultationRepository _repo = ConsultationRepository(_api);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription? _sub;
  Timer? _poll;
  ConsultDetail? _c;
  Object? _error;
  bool _busy = false;
  bool _sending = false;
  bool _sendingFile = false;
  bool _showPatient = true;

  @override
  void initState() {
    super.initState();
    _load();
    LiveNotifications.instance.openConsultationId = widget.id;
    LiveEvents.instance.ensureConnected(_api);
    _sub = LiveEvents.instance.events.listen((e) {
      if (e['consultation_id'] == widget.id) {
        _load(scrollDown: true);
      } else if (e['type'] == 'connected' || e['type'] == 'disconnected') {
        if (mounted) setState(() {});
      }
    });
    // Safety net if the live connection is blocked: quietly refresh every 15 s.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!LiveEvents.instance.connected) _load();
    });
  }

  @override
  void dispose() {
    if (LiveNotifications.instance.openConsultationId == widget.id) {
      LiveNotifications.instance.openConsultationId = null;
    }
    _sub?.cancel();
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool scrollDown = false}) async {
    try {
      final c = await _repo.get(widget.id);
      if (!mounted) return;
      final grew = (_c?.messages.length ?? 0) != c.messages.length;
      setState(() {
        _c = c;
        _error = null;
      });
      if (grew || scrollDown) _toBottom();
    } catch (e) {
      if (mounted && _c == null) setState(() => _error = e);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showMessage(context, done);
      await _load(scrollDown: true);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.send(widget.id, text);
      _input.clear();
      await _load(scrollDown: true);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------- patient actions

  Future<void> _uploadPayment() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose screenshot from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ]),
      ),
    );
    if (source == null) return;
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1800);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not open the camera or gallery.', error: true);
      return;
    }
    if (photo == null || !mounted) return;
    final bytes = await photo.readAsBytes();
    final name = photo.name.isEmpty ? 'payment.jpg' : photo.name;
    var mime = mimeTypeFor(name);
    if (!mime.startsWith('image/')) mime = 'image/jpeg';
    if (!mounted) return;
    final tidCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send payment screenshot'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes, height: 220, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          TextField(
            controller: tidCtrl,
            decoration: const InputDecoration(
                labelText: 'Transaction ID (optional)', hintText: 'e.g. 012345678901', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    final tid = tidCtrl.text.trim();
    tidCtrl.dispose();
    if (ok != true) return;
    await _run(() => _repo.uploadPayment(widget.id, bytes, name, mime, tid),
        done: 'Screenshot sent. The doctor will confirm it.');
  }

  Future<void> _openPrescription(String rxId) async {
    final repo = PrescriptionRepository(_api);
    try {
      final rx = await repo.get(rxId);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PrescriptionResultScreen(repository: repo, prescription: rx)));
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  // ---------------------------------------------------------------- attachments

  static const _mimeByExt = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp',
    'pdf': 'application/pdf', 'doc': 'application/msword', 'txt': 'text/plain',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.green),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.green),
            title: const Text('Photo from gallery'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.green),
            title: const Text('PDF, Word or other file'),
            subtitle: const Text('Old reports, prescriptions, X-ray reports…'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    List<int>? bytes;
    String name = 'file';
    try {
      if (choice == 'file') {
        final r = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: _mimeByExt.keys.toList(),
          withData: true,
        );
        final f = r?.files.single;
        if (f == null || f.bytes == null) return;
        bytes = f.bytes;
        name = f.name;
      } else {
        final x = await ImagePicker().pickImage(
            source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name.isEmpty ? 'photo.jpg' : x.name;
      }
    } catch (_) {
      if (mounted) showMessage(context, 'Could not open the camera or files.', error: true);
      return;
    }
    if (bytes == null || !mounted) return;
    if (bytes.length > 10 * 1024 * 1024) {
      showMessage(context, 'The file is too big (max 10 MB).', error: true);
      return;
    }
    final ext = name.toLowerCase().split('.').last;
    final mime = _mimeByExt[ext] ?? 'image/jpeg';
    final isImage = mime.startsWith('image/');
    final caption = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isImage ? 'Send photo' : 'Send file'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(Uint8List.fromList(bytes!), height: 220, fit: BoxFit.contain),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_fileIcon(mime), color: AppColors.critical, size: 36),
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(_size(bytes!.length)),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: caption,
              decoration: const InputDecoration(labelText: 'Message (optional)', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send'),
          ),
        ],
      ),
    );
    final text = caption.text.trim();
    caption.dispose();
    if (ok != true || !mounted) return;
    setState(() => _sendingFile = true);
    try {
      await _repo.sendFile(widget.id, bytes, name, mime, caption: text);
      await _load(scrollDown: true);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  static IconData _fileIcon(String mime) => mime == 'application/pdf'
      ? Icons.picture_as_pdf
      : mime.startsWith('image/')
          ? Icons.image_outlined
          : Icons.description_outlined;

  static String _size(int b) => b > 1024 * 1024
      ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(b / 1024).ceil()} KB';

  Future<void> _openFile(ConsultMessage m) async {
    try {
      final bytes = await _repo.file(widget.id, '${m.meta['file_id']}');
      final err = await openFileBytes(bytes, '${m.meta['file_name'] ?? 'file'}', '${m.meta['mime_type']}');
      if (err != null && mounted) showMessage(context, err, error: true);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  Widget _fileBubble(bool mine, ConsultMessage m) {
    final kind = '${m.meta['file_kind']}';
    final name = '${m.meta['file_name'] ?? 'file'}';
    final caption = m.text == 'Photo' || m.text == 'PDF: $name' || m.text == 'File: $name' ? '' : m.text;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: mine ? AppColors.deep : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (kind == 'image')
            _PaymentImage(repo: _repo, consultationId: widget.id, fileId: '${m.meta['file_id']}')
          else
            InkWell(
              onTap: () => _openFile(m),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mine ? Colors.white12 : const Color(0xFFF3F6F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(_fileIcon('${m.meta['mime_type']}'),
                      size: 34, color: kind == 'pdf' ? const Color(0xFFE5484D) : const Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: mine ? Colors.white : AppColors.text, fontSize: 13.5)),
                      Text('${_size((m.meta['size'] as num?)?.toInt() ?? 0)} · Tap to open',
                          style: TextStyle(fontSize: 11.5, color: mine ? Colors.white60 : AppColors.textMuted)),
                    ]),
                  ),
                ]),
              ),
            ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Text(caption, style: TextStyle(color: mine ? Colors.white : AppColors.text, fontSize: 14)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(_time(m.createdAt),
                  style: TextStyle(fontSize: 10.5, color: mine ? Colors.white60 : AppColors.textMuted)),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- doctor actions

  Future<void> _decline() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline request'),
        content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason (shown to patient)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.critical),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Decline')),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true) await _run(() => _repo.decline(widget.id, reason));
  }

  Future<void> _rejectPayment() async {
    final ctrl = TextEditingController(text: 'Payment not received in my account. Please check and upload again.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment not received'),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    final note = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true) await _run(() => _repo.verifyPayment(widget.id, false, note: note));
  }

  Future<void> _prescribe() async {
    final body = await showPrescribeSheet(context);
    if (body == null) return;
    await _run(() => _repo.prescribe(widget.id, body), done: 'Prescription sent to the patient.');
  }

  Future<void> _visitClinic() async {
    final result = await showClinicVisitSheet(context);
    if (result == null) return;
    await _run(() => _repo.visitClinic(widget.id,
        urgency: result.urgency, reason: result.reason, date: result.date));
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Consultation')),
        body: _error != null ? ErrorView(message: '$_error', onRetry: _load) : const LoadingView(),
      );
    }
    final other = c.isDoctor ? c.summary.patientName : c.summary.doctorName;
    final otherOnline = c.isDoctor ? (c.patient?['online_now'] == true) : (c.doctor['online_now'] == true);
    final closed = !c.summary.open;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F4),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.mint,
            child: Icon(c.isDoctor ? Icons.person_outline : Icons.medical_services_outlined,
                color: AppColors.green, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(other, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: otherOnline ? AppColors.green : Colors.grey.shade400)),
                const SizedBox(width: 5),
                Text(otherOnline ? 'Online' : (c.isDoctor ? 'Patient' : c.summary.specialty),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ]),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: LiveEvents.instance.connected ? 'Messages arrive live' : 'Reconnecting…',
              child: Icon(LiveEvents.instance.connected ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  color: LiveEvents.instance.connected ? AppColors.green : AppColors.textMuted, size: 20),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'issue') {
                await showReportIssueSheet(context,
                    consultationId: widget.id, category: c.status.contains('pay') ? 'payment' : 'consultation');
              }
              if (v == 'close' &&
                  await showConfirmDialog(context,
                      title: 'Close consultation?', message: 'The chat will become read-only.', confirmLabel: 'Close')) {
                await _run(() => _repo.complete(widget.id));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'issue', child: Text('Report a problem to admin')),
              if (c.summary.open && c.isDoctor && const {'paid', 'advised', 'visit_clinic'}.contains(c.status))
                const PopupMenuItem(value: 'close', child: Text('Close consultation')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        _Steps(status: c.status),
        if (c.isDoctor && c.patient != null) _patientCard(c.patient!),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: c.messages.length,
              itemBuilder: (_, i) => _message(c, c.messages[i]),
            ),
          ),
        ),
        _actionBar(c),
        if (!closed) _composer() else _closedBar(c),
      ]),
    );
  }

  Widget _patientCard(Map<String, dynamic> p) {
    final allergies = (p['allergies'] as List? ?? const []).join(', ');
    final conditions = (p['conditions'] as List? ?? const []).join(', ');
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => setState(() => _showPatient = !_showPatient),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.badge_outlined, size: 17, color: AppColors.records),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    [
                      if (p['age'] != null) '${p['age']} y',
                      if ('${p['gender'] ?? ''}'.isNotEmpty) '${p['gender']}',
                      if ('${p['blood_group'] ?? ''}'.isNotEmpty && p['blood_group'] != 'Unknown') '${p['blood_group']}',
                      if ('${p['city'] ?? ''}'.isNotEmpty) '${p['city']}',
                    ].join(' · ').ifEmpty('Patient details'),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.deep, fontSize: 13)),
              ),
              Icon(_showPatient ? Icons.expand_less : Icons.expand_more, size: 20, color: AppColors.textMuted),
            ]),
            if (_showPatient) ...[
              const SizedBox(height: 4),
              Text('Allergies: ${allergies.ifEmpty('none recorded')}',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: allergies.isEmpty ? AppColors.textMuted : AppColors.critical,
                      fontWeight: allergies.isEmpty ? FontWeight.normal : FontWeight.w600)),
              Text('Conditions: ${conditions.ifEmpty('none recorded')}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _message(ConsultDetail c, ConsultMessage m) {
    final mine = m.sender == c.role;
    switch (m.kind) {
      case 'status':
        return _systemCard(m, c);
      case 'summary':
        return _bubbleWrap(mine, _summaryCard(m));
      case 'payment':
        return _bubbleWrap(mine, _paymentCard(c, m));
      case 'file':
        return _fileBubble(mine, m);
      case 'payment_ok':
        return _pill(m.text, AppColors.green, Icons.verified_outlined);
      case 'payment_rejected':
        return _pill(m.text, AppColors.warning, Icons.error_outline);
      case 'prescription':
        return _bubbleWrap(mine, _prescriptionCard(c, m));
      case 'clinic_visit':
        return _bubbleWrap(mine, _clinicCard(m));
      case 'reminders':
        return GestureDetector(
          onTap: c.isDoctor ? null : () => GoRouter.of(context).push('/feature/33'),
          child: _pill(m.text, AppColors.green, Icons.alarm_on_outlined),
        );
      default:
        return _bubble(mine, m);
    }
  }

  Widget _bubble(bool mine, ConsultMessage m) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
          decoration: BoxDecoration(
            color: mine ? AppColors.deep : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SelectableText(m.text,
                style: TextStyle(color: mine ? Colors.white : AppColors.text, fontSize: 14.5, height: 1.35)),
            const SizedBox(height: 3),
            Text(_time(m.createdAt),
                style: TextStyle(fontSize: 10.5, color: mine ? Colors.white60 : AppColors.textMuted)),
          ]),
        ),
      );

  Widget _bubbleWrap(bool mine, Widget child) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          padding: const EdgeInsets.all(13),
          child: child,
        ),
      );

  Widget _pill(String text, Color color, IconData icon) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, color: AppColors.deep, fontWeight: FontWeight.w600))),
          ]),
        ),
      );

  Widget _systemCard(ConsultMessage m, ConsultDetail c) {
    final pay = (m.meta['payment'] as Map?)?.cast<String, dynamic>();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(color: const Color(0xFFE4ECE9), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(m.text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.deep)),
          if (pay != null && pay['account'] != null && !c.isDoctor) ...[
            const SizedBox(height: 6),
            _copyRow('${pay['method']} · ${pay['title']}', '${pay['account']}'),
          ],
          const SizedBox(height: 2),
          Text(_time(m.createdAt), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
      ),
    );
  }

  Widget _copyRow(String label, String value) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          showMessage(context, 'Copied $value');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.deep, letterSpacing: .5)),
            ]),
            const SizedBox(width: 10),
            const Icon(Icons.copy_rounded, size: 17, color: AppColors.green),
          ]),
        ),
      );

  Widget _cardTitle(IconData icon, String title, Color color) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep, fontSize: 14.5))),
      ]);

  Widget _summaryCard(ConsultMessage m) {
    final causes = (m.meta['possible_causes'] as List? ?? const []).join(', ');
    final otc = (m.meta['otc_options'] as List? ?? const []).join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(Icons.smart_toy_outlined, 'AI symptom check (shared)', AppColors.records),
      const SizedBox(height: 8),
      _kv('Symptoms', '${m.meta['symptoms'] ?? ''}'),
      if ('${m.meta['urgency'] ?? ''}'.isNotEmpty) _kv('Urgency', '${m.meta['urgency']}'),
      if (causes.isNotEmpty) _kv('Possible causes', causes),
      if ('${m.meta['specialist'] ?? ''}'.isNotEmpty) _kv('AI suggested', '${m.meta['specialist']}'),
      if (otc.isNotEmpty) _kv('OTC suggested', otc),
      const Text('AI suggestions, not a diagnosis.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: RichText(
          text: TextSpan(style: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.35), children: [
            TextSpan(text: '$k: ', style: const TextStyle(color: AppColors.textMuted)),
            TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _paymentCard(ConsultDetail c, ConsultMessage m) {
    final ai = (m.meta['ai'] as Map?)?.cast<String, dynamic>() ?? const {};
    final matches = m.meta['amount_matches'] == true;
    final fileId = '${m.meta['file_id'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(Icons.receipt_long_outlined, 'Payment screenshot', AppColors.medicine),
      const SizedBox(height: 8),
      if (fileId.isNotEmpty) _PaymentImage(repo: _repo, consultationId: widget.id, fileId: fileId),
      const SizedBox(height: 8),
      if ('${m.meta['transaction_id'] ?? ''}'.isNotEmpty) _kv('Transaction ID', '${m.meta['transaction_id']}'),
      if (ai.isNotEmpty && ai['looks_like_payment'] == true) ...[
        if (ai['amount_pkr'] != null) _kv('AI read amount', 'Rs ${(ai['amount_pkr'] as num).toStringAsFixed(0)}'),
        if ('${ai['app'] ?? ''}'.isNotEmpty) _kv('App', '${ai['app']}'),
        if ('${ai['paid_to'] ?? ''}'.isNotEmpty) _kv('Paid to', '${ai['paid_to']}'),
        Row(children: [
          Icon(matches ? Icons.check_circle : Icons.help_outline, size: 16,
              color: matches ? AppColors.green : AppColors.warning),
          const SizedBox(width: 5),
          Expanded(
            child: Text(matches ? 'Amount matches the fee' : 'Amount could not be matched — please check',
                style: TextStyle(fontSize: 12, color: matches ? AppColors.green : const Color(0xFFB45309))),
          ),
        ]),
      ] else if (ai.isNotEmpty)
        const Text('AI: this does not look like a payment receipt.',
            style: TextStyle(fontSize: 12, color: Color(0xFFB45309))),
      if (c.isDoctor)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Check your own JazzCash / Easypaisa / bank app before confirming.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
    ]);
  }

  Widget _prescriptionCard(ConsultDetail c, ConsultMessage m) {
    final meds = (m.meta['medicines'] as List? ?? const []).cast<Map>();
    final tests = (m.meta['tests'] as List? ?? const []).join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(Icons.medication_outlined, 'Prescription', AppColors.green),
      if ('${m.meta['diagnosis'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 8),
        _kv('Diagnosis', '${m.meta['diagnosis']}'),
      ],
      const SizedBox(height: 6),
      for (final x in meds)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rx ', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.green)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${x['name']} ${x['strength'] ?? ''}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
                Text('${x['how_to_take']}${x['duration_days'] != null ? ' · ${x['duration_days']} days' : ''}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
              ]),
            ),
          ]),
        ),
      if ('${m.meta['advice'] ?? ''}'.isNotEmpty) _kv('Advice', '${m.meta['advice']}'),
      if (tests.isNotEmpty) _kv('Tests', tests),
      if ('${m.meta['follow_up'] ?? ''}'.isNotEmpty) _kv('Follow-up', '${m.meta['follow_up']}'),
      if (!c.isDoctor && '${m.meta['prescription_id'] ?? ''}'.isNotEmpty)
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _openPrescription('${m.meta['prescription_id']}'),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('View prescription'),
          ),
        ),
    ]);
  }

  Widget _clinicCard(ConsultMessage m) {
    final emergency = m.meta['urgency'] == 'emergency';
    final color = emergency ? AppColors.critical : AppColors.records;
    final phone = '${m.meta['phone'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(emergency ? Icons.emergency_outlined : Icons.local_hospital_outlined,
          emergency ? 'Go to hospital now' : 'Please visit the clinic', color),
      const SizedBox(height: 8),
      Text(m.text, style: const TextStyle(fontSize: 13.5, color: AppColors.text, height: 1.4)),
      const SizedBox(height: 8),
      if ('${m.meta['date'] ?? ''}'.isNotEmpty) _kv('When', '${m.meta['date']}'),
      if ('${m.meta['clinic'] ?? ''}'.isNotEmpty) _kv('Clinic', '${m.meta['clinic']}'),
      if ('${m.meta['address'] ?? ''}'.isNotEmpty) _kv('Address', '${m.meta['address']}, ${m.meta['city'] ?? ''}'),
      if ('${m.meta['timings'] ?? ''}'.isNotEmpty) _kv('Timings', '${m.meta['timings']}'),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (emergency)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.critical),
            onPressed: () => launchUrl(Uri.parse('tel:1122')),
            icon: const Icon(Icons.call, size: 17),
            label: const Text('Call 1122'),
          ),
        if (phone.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}')),
            icon: const Icon(Icons.call_outlined, size: 17),
            label: const Text('Call clinic'),
          ),
        if ('${m.meta['address'] ?? ''}'.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => launchUrl(
                Uri.parse('https://www.google.com/maps/search/?api=1&query='
                    '${Uri.encodeComponent('${m.meta['clinic']} ${m.meta['address']} ${m.meta['city']}')}'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.map_outlined, size: 17),
            label: const Text('Map'),
          ),
      ]),
    ]);
  }

  Widget _actionBar(ConsultDetail c) {
    final s = c.status;
    final buttons = <Widget>[];
    String? hint;
    if (c.isDoctor) {
      if (s == 'requested') {
        hint = 'New request — accept to ask for the fee, or refer to the clinic if it looks serious.';
        buttons.addAll([
          _btn('Accept', Icons.check, AppColors.green, () => _run(() => _repo.accept(widget.id))),
          _btn('Visit clinic', Icons.local_hospital_outlined, AppColors.records, _visitClinic, outlined: true),
          _btn('Decline', Icons.close, AppColors.critical, _decline, outlined: true),
        ]);
      } else if (s == 'awaiting_payment') {
        hint = 'Waiting for the patient to pay Rs ${c.summary.fee?.toStringAsFixed(0) ?? '0'}.';
        buttons.add(_btn('Visit clinic', Icons.local_hospital_outlined, AppColors.records, _visitClinic, outlined: true));
      } else if (s == 'payment_submitted') {
        hint = 'Check the screenshot above against your account.';
        buttons.addAll([
          _btn('Payment received', Icons.verified_outlined, AppColors.green,
              () => _run(() => _repo.verifyPayment(widget.id, true), done: 'Payment confirmed.')),
          _btn('Not received', Icons.error_outline, AppColors.warning, _rejectPayment, outlined: true),
        ]);
      } else if (s == 'paid' || s == 'advised') {
        hint = s == 'paid' ? 'Paid. Send the prescription, or ask the patient to visit the clinic.' : null;
        buttons.addAll([
          _btn(s == 'paid' ? 'Write prescription' : 'New prescription', Icons.edit_note, AppColors.green, _prescribe),
          _btn('Visit clinic', Icons.local_hospital_outlined, AppColors.records, _visitClinic, outlined: true),
        ]);
      }
    } else {
      if (s == 'requested') {
        hint = 'Request sent. You will be told here as soon as the doctor accepts.';
        buttons.add(_btn('Cancel request', Icons.close, AppColors.textMuted,
            () => _run(() => _repo.cancel(widget.id)), outlined: true));
      } else if (s == 'awaiting_payment' && c.payment != null) {
        return _payPanel(c.payment!);
      } else if (s == 'payment_submitted') {
        hint = 'Screenshot sent. The doctor is checking your payment.';
      } else if (s == 'paid') {
        hint = 'Payment confirmed. The doctor will send your prescription here.';
      }
    }
    if (buttons.isEmpty && hint == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hint != null)
          Row(children: [
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              const Padding(
                  padding: EdgeInsets.only(right: 6), child: Icon(Icons.info_outline, size: 16, color: AppColors.textMuted)),
            Expanded(child: Text(hint, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
          ]),
        if (buttons.isNotEmpty) ...[
          if (hint != null) const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ],
      ]),
    );
  }

  Widget _payPanel(Map<String, dynamic> p) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.deep, Color(0xFF0E5A4B)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.payments_outlined, color: Colors.white),
            const SizedBox(width: 8),
            Text('Pay Rs ${(p['amount_pkr'] as num?)?.toStringAsFixed(0) ?? '0'}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: Text('${p['method']}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 10),
          _copyRow('Send to: ${p['title']}', '${p['account']}'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green, padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: _busy ? null : _uploadPayment,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_rounded),
              label: const Text('Upload payment screenshot'),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Pay in your JazzCash / Easypaisa / bank app, then upload the screenshot. The app never takes money.',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      );

  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap, {bool outlined = false}) => outlined
      ? OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withAlpha(120))),
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 17),
          label: Text(label))
      : FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 17),
          label: Text(label));

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
          child: Row(children: [
            IconButton(
              tooltip: 'Send photo or file',
              onPressed: _sendingFile ? null : _attach,
              icon: _sendingFile
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.attach_file_rounded, color: AppColors.textMuted),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Type a message',
                  filled: true,
                  fillColor: const Color(0xFFF1F5F4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ]),
        ),
      );

  Widget _closedBar(ConsultDetail c) => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(14),
          child: Text('This consultation is ${c.summary.statusText.toLowerCase()}.',
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ),
      );

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final now = DateTime.now();
    final day = d.year == now.year && d.month == now.month && d.day == now.day ? '' : '${d.day}/${d.month} ';
    return '$day$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Progress: Request → Accepted → Paid → Advice.
class _Steps extends StatelessWidget {
  const _Steps({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    const labels = ['Requested', 'Accepted', 'Paid', 'Advice'];
    final step = switch (status) {
      'requested' => 0,
      'awaiting_payment' || 'payment_submitted' => 1,
      'paid' => 2,
      'advised' || 'visit_clinic' || 'completed' => 3,
      _ => -1,
    };
    if (step < 0) {
      return Container(
        width: double.infinity,
        color: AppColors.criticalTint,
        padding: const EdgeInsets.all(8),
        child: Text(status == 'declined' ? 'The doctor declined this request.' : 'This request was cancelled.',
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.critical, fontSize: 12.5)),
      );
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          Column(children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: i <= step ? AppColors.green : const Color(0xFFE2E8EC),
              child: i < step
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(fontSize: 11, color: i <= step ? Colors.white : AppColors.textMuted)),
            ),
            const SizedBox(height: 3),
            Text(i == 3 && status == 'visit_clinic' ? 'Clinic' : labels[i],
                style: TextStyle(
                    fontSize: 10.5,
                    color: i <= step ? AppColors.deep : AppColors.textMuted,
                    fontWeight: i == step ? FontWeight.w700 : FontWeight.normal)),
          ]),
          if (i < labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 14, left: 4, right: 4),
                color: i < step ? AppColors.green : const Color(0xFFE2E8EC),
              ),
            ),
        ],
      ]),
    );
  }
}

class _PaymentImage extends StatefulWidget {
  const _PaymentImage({required this.repo, required this.consultationId, required this.fileId});

  final ConsultationRepository repo;
  final String consultationId;
  final String fileId;

  @override
  State<_PaymentImage> createState() => _PaymentImageState();
}

class _PaymentImageState extends State<_PaymentImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    widget.repo.file(widget.consultationId, widget.fileId).then((b) {
      if (mounted) setState(() => _bytes = Uint8List.fromList(b));
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(
          height: 140,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFF1F5F4), borderRadius: BorderRadius.circular(10)),
          child: const CircularProgressIndicator(strokeWidth: 2));
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                body: InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(_bytes!))),
              ))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_bytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
      ),
    );
  }
}
