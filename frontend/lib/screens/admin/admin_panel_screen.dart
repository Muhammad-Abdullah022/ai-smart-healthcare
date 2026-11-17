import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import '../consult/doctor_panel_screens.dart' show DoctorJoinScreen;
import '../consult/issues_screen.dart';

/// Admin API (backend /admin/*). Admins see names, emails and counts only — never health data.
class AdminRepository {
  AdminRepository(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> stats() async => (await api.get('/admin/stats') as Map).cast<String, dynamic>();

  Future<List<Map<String, dynamic>>> doctors({String? q}) async => [
        for (final d in await api.get('/admin/doctors${q == null || q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}')
            as List)
          (d as Map).cast<String, dynamic>()
      ];

  Future<void> approveDoctor(String id) => api.post('/admin/doctors/$id/approve');
  Future<void> rejectDoctor(String id, String reason) =>
      api.post('/admin/doctors/$id/reject', body: {'reason': reason});
  Future<List<Map<String, dynamic>>> issues() async =>
      [for (final i in await api.get('/admin/issues') as List) (i as Map).cast<String, dynamic>()];
  Future<void> updateDoctor(String id, Map<String, dynamic> body) => api.put('/admin/doctors/$id', body: body);
  Future<void> setDoctorActive(String id, bool active) =>
      api.post('/admin/doctors/$id/status', body: {'active': active});
  Future<void> resetPassword(String id, String password) =>
      api.post('/admin/doctors/$id/reset-password', body: {'password': password});

  Future<List<Map<String, dynamic>>> users({String? q}) async => [
        for (final u in await api.get('/admin/users${q == null || q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}')
            as List)
          (u as Map).cast<String, dynamic>()
      ];

  Future<void> setUserActive(String id, bool active) => api.post('/admin/users/$id/status', body: {'active': active});
}

/// Admin panel: approve doctor sign-ups, manage all accounts, answer reported issues.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late final AdminRepository _repo = AdminRepository(context.read<AuthProvider>().repository.api);
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>>? _doctors;
  List<Map<String, dynamic>>? _users;
  List<Map<String, dynamic>>? _issues;
  Object? _error;
  String _doctorQuery = '';
  String _userQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait(
          [_repo.stats(), _repo.doctors(q: _doctorQuery), _repo.users(q: _userQuery), _repo.issues()]);
      if (!mounted) return;
      setState(() {
        _stats = r[0] as Map<String, dynamic>;
        _doctors = r[1] as List<Map<String, dynamic>>;
        _users = r[2] as List<Map<String, dynamic>>;
        _issues = r[3] as List<Map<String, dynamic>>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _approve(Map<String, dynamic> d) async {
    try {
      await _repo.approveDoctor('${d['id']}');
      if (mounted) showMessage(context, '${d['name']} approved. They can log in now.');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  Future<void> _reject(Map<String, dynamic> d) async {
    final ctrl = TextEditingController(text: 'PMDC registration could not be verified.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject ${d['name']}?'),
        content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason (shown to the doctor)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.critical),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject')),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    try {
      await _repo.rejectDoctor('${d['id']}', reason);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  Future<void> _editDoctor(Map<String, dynamic> d) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => DoctorJoinScreen(existing: d, onSubmit: (b) => _repo.updateDoctor('${d['id']}', b))));
    if (ok == true) _load();
  }

  Future<void> _toggleDoctor(Map<String, dynamic> d) async {
    final active = d['active'] == true;
    if (active &&
        !await showConfirmDialog(context,
            title: 'Disable ${d['name']}?',
            message: 'The doctor will be logged out, cannot log in, and is hidden from online consultations.',
            confirmLabel: 'Disable',
            destructive: true)) {
      return;
    }
    try {
      await _repo.setDoctorActive('${d['id']}', !active);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> d) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New temporary password for ${d['name']}'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'Temporary password', helperText: '8+ characters, letters and numbers')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    final pw = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    try {
      await _repo.resetPassword('${d['id']}', pw);
      if (mounted) showMessage(context, 'Password reset. The doctor must change it at next login.');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AuthProvider>().user;
    if (_stats == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin panel')),
        body: _error != null ? ErrorView(message: '$_error', onRetry: _load) : const LoadingView(),
      );
    }
    final pending = (_stats!['pending_doctors'] as num?) ?? 0;
    final openIssues = (_stats!['open_issues'] as num?) ?? 0;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.deep,
          foregroundColor: Colors.white,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Admin panel', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(admin?.email ?? '', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'password') showChangePasswordDialog(context);
                if (v == 'logout') context.read<AuthProvider>().logout();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'password', child: Text('Change password')),
                PopupMenuItem(value: 'logout', child: Text('Log out')),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.green,
            tabs: [
              const Tab(text: 'Overview'),
              Tab(text: pending > 0 ? 'Doctors ($pending new)' : 'Doctors'),
              const Tab(text: 'Users'),
              Tab(text: openIssues > 0 ? 'Issues ($openIssues)' : 'Issues'),
            ],
          ),
        ),
        body: TabBarView(children: [_overview(), _doctorsTab(), _usersTab(), _issuesTab()]),
      ),
    );
  }

  // ---------------------------------------------------------------- overview

  Widget _overview() {
    final s = _stats!;
    final byStatus = (s['consultations_by_status'] as Map? ?? const {}).cast<String, dynamic>();
    const names = {
      'requested': 'Waiting for doctor',
      'awaiting_payment': 'Waiting for payment',
      'payment_submitted': 'Payment to check',
      'paid': 'Paid',
      'advised': 'Prescription sent',
      'visit_clinic': 'Sent to clinic',
      'completed': 'Completed',
      'declined': 'Declined',
      'cancelled': 'Cancelled',
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _statTile('Doctors to approve', '${s['pending_doctors'] ?? 0}', Icons.how_to_reg_outlined, AppColors.medicine),
            _statTile('Open issues', '${s['open_issues'] ?? 0}', Icons.support_agent_outlined, AppColors.critical),
            _statTile('Patients', '${s['patients']}', Icons.people_outline, AppColors.records),
            _statTile('Doctor accounts', '${s['active_doctors']} / ${s['doctors']} active', Icons.medical_services_outlined,
                AppColors.green),
            _statTile('Consultations', '${s['consultations']}', Icons.forum_outlined, AppColors.mind),
            _statTile('Fees confirmed', 'Rs ${(s['fees_confirmed_pkr'] as num).toStringAsFixed(0)}',
                Icons.payments_outlined, AppColors.medicine),
            _statTile('Symptom checks', '${s['symptom_assessments']}', Icons.smart_toy_outlined, AppColors.deep),
            _statTile('Emergency alerts', '${s['emergency_assessments']}', Icons.emergency_outlined, AppColors.critical),
            _statTile('Reports read', '${s['reports']}', Icons.biotech_outlined, AppColors.records),
            _statTile('Listed doctors', '${s['listed_doctors']}', Icons.list_alt, AppColors.textMuted),
          ],
        ),
        const SizedBox(height: 18),
        const Text('Consultations by status',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.deep)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.softShadow),
          child: byStatus.isEmpty
              ? const Text('No consultations yet.', style: TextStyle(color: AppColors.textMuted))
              : Column(children: [
                  for (final e in names.entries)
                    if ((byStatus[e.key] ?? 0) > 0) _bar(e.value, byStatus[e.key] as int, s['consultations'] as int),
                ]),
        ),
        const SizedBox(height: 12),
        const Text('Admins see totals only — never patients\' health data or chats.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.softShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          FittedBox(
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.deep)),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      );

  Widget _bar(String label, int n, int total) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : n / total,
                minHeight: 9,
                backgroundColor: AppColors.mint,
                color: AppColors.green,
              ),
            ),
          ),
          SizedBox(width: 34, child: Text('$n', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  // ---------------------------------------------------------------- doctors

  Widget _search(String hint, ValueChanged<String> onSubmit) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: TextField(
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmit,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _doctorsTab() {
    final list = _doctors ?? const [];
    return Column(children: [
      _search('Search name, specialty, city, PMDC', (q) {
        _doctorQuery = q.trim();
        _load();
      }),
      Expanded(
        child: list.isEmpty
            ? const EmptyView(
                icon: Icons.medical_services_outlined,
                title: 'No doctors yet',
                message: 'Doctors sign up from the register screen ("I am a doctor"). They appear here for approval.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
                  for (final d in list) _doctorTile(d),
                ]),
              ),
      ),
    ]);
  }

  Widget _doctorTile(Map<String, dynamic> d) {
    final approval = '${d['approval'] ?? 'approved'}';
    final active = d['active'] == true && approval == 'approved';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: active ? AppColors.mint : Colors.grey.shade300,
            child: Icon(Icons.person, color: active ? AppColors.green : Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.deep)),
              Text('${d['specialty']} · ${d['city']}', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              Text('${d['email']}', style: const TextStyle(fontSize: 12.5, color: AppColors.records)),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editDoctor(d);
              if (v == 'reset') _resetPassword(d);
              if (v == 'toggle') _toggleDoctor(d);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit profile')),
              if (approval == 'approved') ...[
                const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                PopupMenuItem(value: 'toggle', child: Text(active ? 'Disable account' : 'Enable account')),
              ],
            ],
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (approval == 'pending')
            _chip('Waiting for approval', AppColors.medicine)
          else if (approval == 'rejected')
            _chip('Rejected', AppColors.critical)
          else
            _chip(active ? 'Active' : 'Disabled', active ? AppColors.green : AppColors.critical),
          _chip('PMDC ${d['pmdc_number']}', AppColors.deep),
          _chip('Rs ${(d['fee_pkr'] as num?)?.toStringAsFixed(0) ?? '0'}', AppColors.medicine),
          _chip('${d['consultations']} consultations (${d['open_consultations']} open)', AppColors.mind),
          if (d['must_change_password'] == true) _chip('Temporary password', AppColors.warning),
          if (active && d['available'] != true) _chip('Away', AppColors.textMuted),
        ]),
        if (approval == 'rejected' && '${d['rejection_reason'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reason: ${d['rejection_reason']}', style: const TextStyle(fontSize: 12, color: AppColors.critical)),
          ),
        if (approval != 'approved') ...[
          const SizedBox(height: 10),
          Text('Check the PMDC number ${d['pmdc_number']} before approving.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                onPressed: () => _approve(d),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Approve'),
              ),
            ),
            if (approval == 'pending') ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.critical),
                  onPressed: () => _reject(d),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
      );

  // ---------------------------------------------------------------- users

  Widget _usersTab() {
    final list = _users ?? const [];
    final me = context.read<AuthProvider>().user?.id;
    return Column(children: [
      _search('Search name or email', (q) {
        _userQuery = q.trim();
        _load();
      }),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
            for (final u in list)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.mint,
                    child: Icon(
                        (u['roles'] as List).contains('admin')
                            ? Icons.admin_panel_settings_outlined
                            : (u['roles'] as List).contains('doctor')
                                ? Icons.medical_services_outlined
                                : Icons.person_outline,
                        color: AppColors.green),
                  ),
                  title: Text('${u['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${u['email']} · ${(u['roles'] as List).join(', ')}'
                      '${u['approval'] == 'pending' ? ' · waiting for approval' : u['approval'] == 'rejected' ? ' · rejected' : ''}'),
                  trailing: u['id'] == me
                      ? const Text('You', style: TextStyle(color: AppColors.textMuted))
                      : Switch(
                          value: u['active'] == true,
                          activeColor: AppColors.green,
                          onChanged: (v) async {
                            try {
                              await _repo.setUserActive('${u['id']}', v);
                              _load();
                            } catch (e) {
                              if (mounted) showMessage(context, '$e', error: true);
                            }
                          },
                        ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- issues

  Widget _issuesTab() {
    final list = _issues ?? const [];
    if (list.isEmpty) {
      return const EmptyView(
          icon: Icons.support_agent_outlined,
          title: 'No issues',
          message: 'Problems reported by patients and doctors (payments, consultations, app) appear here.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
        for (final i in list)
          IssueTile(
            issue: i,
            adminView: true,
            onTap: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => IssueThreadScreen(issue: i, adminView: true)));
              _load();
            },
          ),
      ]),
    );
  }
}
