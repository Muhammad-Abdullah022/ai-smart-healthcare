import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/consultation_repository.dart';
import '../../services/doctor_repository.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import 'consultation_screen.dart';

Color statusColor(String s) => switch (s) {
      'requested' => AppColors.records,
      'awaiting_payment' || 'payment_submitted' => AppColors.medicine,
      'paid' => AppColors.green,
      'advised' || 'completed' => AppColors.deep,
      'visit_clinic' => AppColors.critical,
      _ => AppColors.textMuted,
    };

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${d.day}/${d.month}';
}

/// One row in a consultation list (patient or doctor view).
class ConsultTile extends StatelessWidget {
  const ConsultTile({super.key, required this.c, required this.doctorView, required this.onTap});

  final ConsultSummary c;
  final bool doctorView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(c.status);
    final name = doctorView ? c.patientName : c.doctorName;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.softShadow),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: color.withAlpha(30),
              child: Text(name.replaceAll(RegExp(r'^(Dr\.?\s*)'), '').trim().characters.take(1).toString().toUpperCase(),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.deep))),
                  Text(_ago(c.updatedAt), style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ]),
                const SizedBox(height: 2),
                Text(c.lastMessage.isEmpty ? c.reason : c.lastMessage,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(20)),
                    child: Text(c.statusText,
                        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  if (c.unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(20)),
                      child: Text('${c.unread}',
                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

Future<void> openConsultation(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: id)));

/// Patient: list of my online consultations.
class MyConsultationsScreen extends StatefulWidget {
  const MyConsultationsScreen({super.key});

  @override
  State<MyConsultationsScreen> createState() => _MyConsultationsScreenState();
}

class _MyConsultationsScreenState extends State<MyConsultationsScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late final _repo = ConsultationRepository(_api);
  late Future<List<ConsultSummary>> _future = _repo.mine();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    LiveEvents.instance.ensureConnected(_api);
    _sub = LiveEvents.instance.events.listen((e) {
      if (e['type'] == 'message' && mounted) setState(() => _future = _repo.mine());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async => setState(() => _future = _repo.mine());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Online consultations')),
      body: FutureBuilder<List<ConsultSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.forum_outlined,
              title: 'No consultations yet',
              message: 'Ask the AI chatbot about your symptoms, then choose a doctor with the "Online" badge to chat, '
                  'pay and get a prescription.',
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final c in list)
                ConsultTile(c: c, doctorView: false, onTap: () async {
                  await openConsultation(context, c.id);
                  _reload();
                }),
            ]),
          );
        },
      ),
    );
  }
}

/// Patient: ask an online doctor for a consultation (from the chatbot, doctor list or health record).
Future<String?> showConsultRequestSheet(BuildContext context,
    {required Doctor doctor, String? reason, bool fromChat = false}) async {
  final repo = ConsultationRepository(context.read<AuthProvider>().repository.api);
  final ctrl = TextEditingController(text: reason ?? '');
  var share = fromChat;
  var busy = false;
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.forum_outlined, color: AppColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Consult ${doctor.name} online',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              'Chat live with the doctor. After the doctor accepts, pay '
              '${doctor.fee != null ? 'Rs ${doctor.fee!.toStringAsFixed(0)}' : 'the fee'} and upload the screenshot. '
              'The doctor then sends your prescription, or asks you to visit the clinic.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Your problem', hintText: 'Fever for 3 days with body ache …', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: share,
            onChanged: (v) => setS(() => share = v ?? false),
            title: const Text('Share my latest AI symptom check with the doctor', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('Symptoms, urgency and possible causes', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: busy
                  ? null
                  : () async {
                      if (ctrl.text.trim().length < 3) {
                        showMessage(ctx, 'Please describe your problem.', error: true);
                        return;
                      }
                      setS(() => busy = true);
                      try {
                        final c = await repo.request(
                            doctorId: doctor.id,
                            reason: ctrl.text.trim(),
                            shareAssessment: share,
                            source: fromChat ? 'chat' : 'doctor_list');
                        if (ctx.mounted) Navigator.pop(ctx, c.id);
                      } catch (e) {
                        setS(() => busy = false);
                        if (ctx.mounted) showMessage(ctx, '$e', error: true);
                      }
                    },
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: const Text('Send request'),
            ),
          ),
        ]),
      ),
    ),
  );
  ctrl.dispose();
  if (id != null && context.mounted) await openConsultation(context, id);
  return id;
}

/// Doctor panel: requests, payments to check, patients to advise. Updates live.
class DoctorPanelScreen extends StatefulWidget {
  const DoctorPanelScreen({super.key});

  @override
  State<DoctorPanelScreen> createState() => _DoctorPanelScreenState();
}

class _DoctorPanelScreenState extends State<DoctorPanelScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late final _repo = ConsultationRepository(_api);
  DoctorPanelData? _data;
  Object? _error;
  bool _notDoctor = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();

    LiveEvents.instance.ensureConnected(_api);
    _sub = LiveEvents.instance.events.listen((e) {
      if (e['type'] == 'message') {
        _load();
        final m = e['message'] as Map?;
        if (mounted && m != null && m['sender'] == 'patient') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('New: ${m['text']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            action: SnackBarAction(label: 'Open', onPressed: () => openConsultation(context, '${e['consultation_id']}')),
          ));
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await _repo.myDoctorProfile();
      if (profile == null) {
        if (mounted) setState(() => _notDoctor = true);
        return;
      }
      final d = await _repo.panel();
      if (mounted) {
        setState(() {
          _data = d;
          _notDoctor = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _editProfile() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => DoctorJoinScreen(existing: _data?.doctor)));
    if (saved == true) {
      if (mounted) await context.read<AuthProvider>().refreshUser();
      _load();
    }
  }

  Future<void> _toggleAvailable(bool v) async {
    final d = Map<String, dynamic>.from(_data!.doctor)..['available'] = v;
    d.remove('id');
    try {
      await _repo.saveDoctorProfile(d);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notDoctor) {
      return Scaffold(
        appBar: AppBar(title: const Text('Doctor panel')),
        body: const EmptyView(
          icon: Icons.medical_services_outlined,
          title: 'Not a doctor account',
          message: 'Doctors sign up from the register screen ("I am a Doctor"). '
              'The administrator approves the account before the doctor can log in.',
        ),
      );
    }
    final d = _data;
    if (d == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Doctor panel')),
          body: _error != null ? ErrorView(message: '$_error', onRetry: _load) : const LoadingView());
    }
    final open = d.consultations.where((c) => c.open).toList();
    final closed = d.consultations.where((c) => !c.open).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 230,
              backgroundColor: AppColors.deep,
              foregroundColor: Colors.white,
              title: const Text('Doctor panel'),
              actions: [
                IconButton(onPressed: _editProfile, icon: const Icon(Icons.edit_outlined), tooltip: 'Edit profile'),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'password') showChangePasswordDialog(context);
                    if (v == 'issues') context.push('/issues');
                    if (v == 'logout') context.read<AuthProvider>().logout();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'issues', child: Text('Help & issues')),
                    PopupMenuItem(value: 'password', child: Text('Change password')),
                    PopupMenuItem(value: 'logout', child: Text('Log out')),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(background: _header(d)),
              bottom: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: AppColors.green,
                tabs: [Tab(text: 'Active (${open.length})'), Tab(text: 'Closed (${closed.length})')],
              ),
            ),
          ],
          body: TabBarView(children: [_list(open, 'No active consultations', 'New requests appear here live.'),
            _list(closed, 'Nothing closed yet', 'Completed and declined consultations appear here.')]),
        ),
      ),
    );
  }

  Widget _header(DoctorPanelData d) {
    final s = d.stats;
    final available = d.doctor['available'] == true;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.deep, Color(0xFF0E5A4B)])),
      padding: const EdgeInsets.fromLTRB(16, 92, 16, 56),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${d.doctor['name']} · ${d.doctor['specialty']}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          Text(available ? 'Available' : 'Away', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Switch(value: available, activeColor: AppColors.green, onChanged: _toggleAvailable),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _stat('${s['new']}', 'New', Icons.mark_email_unread_outlined),
          _stat('${s['to_check']}', 'Payments', Icons.receipt_long_outlined),
          _stat('${s['to_advise']}', 'To advise', Icons.edit_note),
          _stat('Rs ${(s['earned_pkr'] as num).toStringAsFixed(0)}', 'Received', Icons.payments_outlined),
        ]),
      ]),
    );
  }

  Widget _stat(String value, String label, IconData icon) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(height: 2),
            FittedBox(
                child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
          ]),
        ),
      );

  Widget _list(List<ConsultSummary> list, String emptyTitle, String emptyText) {
    if (list.isEmpty) return EmptyView(icon: Icons.forum_outlined, title: emptyTitle, message: emptyText);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        for (final c in list)
          ConsultTile(c: c, doctorView: true, onTap: () async {
            await openConsultation(context, c.id);
            _load();
          }),
      ]),
    );
  }
}

/// Doctor profile form: specialty, clinic, fee and the account patients pay into.
/// Doctor profile form. Used by the doctor (edit own profile) and by the admin
/// ([onSubmit] given; [askLogin] adds email + temporary password for a new doctor account).
class DoctorJoinScreen extends StatefulWidget {
  const DoctorJoinScreen({super.key, this.existing, this.onSubmit, this.askLogin = false});

  final Map<String, dynamic>? existing;
  final Future<void> Function(Map<String, dynamic> body)? onSubmit;
  final bool askLogin;

  @override
  State<DoctorJoinScreen> createState() => _DoctorJoinScreenState();
}

class _DoctorJoinScreenState extends State<DoctorJoinScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = {
    for (final k in const ['name', 'pmdc_number', 'specialty', 'qualification', 'city', 'clinic', 'address', 'phone',
      'timings', 'fee_pkr', 'payment_title', 'payment_account', 'experience_years', 'about'])
      k: TextEditingController(text: '${widget.existing?[k] ?? ''}'.replaceAll(RegExp(r'\.0$'), '').replaceAll('null', ''))
  };
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _method = '${widget.existing?['payment_method'] ?? 'JazzCash'}';
  late String _gender = '${widget.existing?['gender'] ?? ''}';
  bool _saving = false;
  List<String> _specialties = const [];

  @override
  void initState() {
    super.initState();
    if (_c['qualification']!.text.isEmpty) _c['qualification']!.text = 'MBBS';
    DoctorRepository(context.read<AuthProvider>().repository.api).specialties().then((s) {
      if (mounted) setState(() => _specialties = [for (final x in s) x.name]);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        for (final e in _c.entries)
          if (e.key != 'fee_pkr' && e.key != 'experience_years') e.key: e.value.text.trim(),
        'fee_pkr': int.tryParse(_c['fee_pkr']!.text.trim()) ?? 0,
        'experience_years': int.tryParse(_c['experience_years']!.text.trim()),
        'payment_method': _method,
        'gender': _gender,
        'available': widget.existing?['available'] ?? true,
        if (widget.askLogin) 'email': _email.text.trim(),
        if (widget.askLogin) 'password': _password.text,
      };
      if (widget.onSubmit != null) {
        await widget.onSubmit!(body);
      } else {
        await ConsultationRepository(context.read<AuthProvider>().repository.api).saveDoctorProfile(body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label,
      {String? hint, bool isRequired = false, TextInputType? keyboard, int maxLines = 1, int minLength = 2}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[key],
          keyboardType: keyboard,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
          validator: isRequired
              ? (v) => (v ?? '').trim().length < minLength ? 'Required' : null
              : null,
        ),
      );

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.deep)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing?['id'] == null ? 'Doctor details' : 'Doctor profile')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.askLogin) ...[
            _heading('Login'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Doctor email (login)', border: OutlineInputBorder()),
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextFormField(
                controller: _password,
                decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'Give this to the doctor. They must change it at first login.',
                    border: OutlineInputBorder()),
                validator: (v) {
                  final p = v ?? '';
                  if (p.length < 8) return 'At least 8 characters';
                  if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'Use letters and numbers';
                  return null;
                },
              ),
            ),
          ],
          _heading(widget.askLogin ? 'Doctor' : 'About you'),
          _field('name', 'Full name', isRequired: true, minLength: 3),
          _field('pmdc_number', 'PMDC registration number', hint: '12345-P', isRequired: true, minLength: 3),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _c['specialty']!.text),
            optionsBuilder: (v) => _specialties
                .where((s) => s.toLowerCase().contains(v.text.toLowerCase()))
                .take(8),
            onSelected: (s) => _c['specialty']!.text = s,
            fieldViewBuilder: (ctx, ctrl, focus, _) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: ctrl,
                focusNode: focus,
                onChanged: (v) => _c['specialty']!.text = v,
                decoration: const InputDecoration(labelText: 'Specialty', hintText: 'General Physician', border: OutlineInputBorder()),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Required' : null,
              ),
            ),
          ),
          _field('qualification', 'Qualification', hint: 'MBBS, FCPS (Medicine)'),
          Row(children: [
            Expanded(child: _field('experience_years', 'Experience (years)', keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  value: const ['male', 'female', ''].contains(_gender) ? _gender : '',
                  decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('—')),
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                  ],
                  onChanged: (v) => _gender = v ?? '',
                ),
              ),
            ),
          ]),
          _field('about', 'About (shown to patients)', maxLines: 3),
          _heading('Clinic'),
          _field('city', 'City', isRequired: true),
          _field('clinic', 'Clinic / hospital name'),
          _field('address', 'Clinic address', hint: 'Sent to patients you ask to visit'),
          _field('phone', 'Clinic phone', keyboard: TextInputType.phone),
          _field('timings', 'Timings', hint: 'Mon–Sat, 5–9 pm'),
          _heading('Fee & payment'),
          _field('fee_pkr', 'Online consultation fee (Rs)', keyboard: TextInputType.number, isRequired: true, minLength: 1),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'JazzCash', label: Text('JazzCash')),
                ButtonSegment(value: 'Easypaisa', label: Text('Easypaisa')),
                ButtonSegment(value: 'Bank transfer', label: Text('Bank')),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
          ),
          _field('payment_title', 'Account holder name', isRequired: true),
          _field('payment_account', _method == 'Bank transfer' ? 'IBAN / account number' : 'Mobile account number',
              hint: _method == 'Bank transfer' ? 'PK36SCBL0000001123456702' : '03XX XXXXXXX',
              isRequired: true, minLength: 5),
          const Text(
              'Patients see this account only after you accept their request. They pay in their own app and upload '
              'the screenshot; you confirm it here. The app never handles money.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(widget.existing?['id'] == null ? 'Send for approval' : 'Save'),
          ),
        ]),
      ),
    );
  }
}
