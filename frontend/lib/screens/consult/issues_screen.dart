import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';

const issueCategories = {
  'payment': 'Payment',
  'doctor': 'Doctor',
  'consultation': 'Consultation',
  'account': 'My account',
  'app_bug': 'App problem',
  'other': 'Other',
};

Color issueStatusColor(String s) => switch (s) {
      'open' => AppColors.critical,
      'in_progress' => AppColors.medicine,
      _ => AppColors.green,
    };

String issueStatusText(String s) => switch (s) {
      'open' => 'Open',
      'in_progress' => 'In progress',
      _ => 'Resolved',
    };

/// Report a problem to the admin (optionally about one consultation).
Future<bool> showReportIssueSheet(BuildContext context, {String? consultationId, String category = 'other'}) async {
  final api = context.read<AuthProvider>().repository.api;
  final subject = TextEditingController();
  final message = TextEditingController();
  var cat = category;
  var busy = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Report a problem', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.deep)),
          const SizedBox(height: 4),
          Text(
              consultationId != null
                  ? 'The admin will see this consultation\'s status and fee (not your chat).'
                  : 'The admin team will reply here and in your notifications.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in issueCategories.entries)
              ChoiceChip(label: Text(e.value), selected: cat == e.key, onSelected: (_) => setS(() => cat = e.key)),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: subject,
              decoration: const InputDecoration(labelText: 'Subject', hintText: 'Paid but not confirmed', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: message,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'What happened?', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: busy
                  ? null
                  : () async {
                      if (subject.text.trim().length < 3 || message.text.trim().length < 3) {
                        showMessage(ctx, 'Please write a subject and what happened.', error: true);
                        return;
                      }
                      setS(() => busy = true);
                      try {
                        await api.post('/issues', body: {
                          'category': cat,
                          'subject': subject.text.trim(),
                          'message': message.text.trim(),
                          if (consultationId != null) 'consultation_id': consultationId,
                        });
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setS(() => busy = false);
                        if (ctx.mounted) showMessage(ctx, '$e', error: true);
                      }
                    },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send to admin'),
            ),
          ),
        ]),
      ),
    ),
  );
  subject.dispose();
  message.dispose();
  if (ok == true && context.mounted) showMessage(context, 'Sent. The admin team will reply soon.');
  return ok == true;
}

class IssueTile extends StatelessWidget {
  const IssueTile({super.key, required this.issue, required this.onTap, this.adminView = false});

  final Map<String, dynamic> issue;
  final VoidCallback onTap;
  final bool adminView;

  @override
  Widget build(BuildContext context) {
    final status = '${issue['status']}';
    final color = issueStatusColor(status);
    final msgs = issue['messages'] as List? ?? const [];
    final last = msgs.isEmpty ? '' : '${(msgs.last as Map)['text']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.softShadow),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(28),
          child: Icon(
              switch ('${issue['category']}') {
                'payment' => Icons.payments_outlined,
                'doctor' => Icons.medical_services_outlined,
                'consultation' => Icons.forum_outlined,
                'account' => Icons.manage_accounts_outlined,
                'app_bug' => Icons.bug_report_outlined,
                _ => Icons.help_outline,
              },
              color: color),
        ),
        title: Text('${issue['subject']}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (adminView)
            Text('${issue['user_name']} (${issue['user_role']}) · ${issue['user_email']}',
                style: const TextStyle(fontSize: 12, color: AppColors.records)),
          Text(last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
        ]),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(20)),
          child: Text(issueStatusText(status), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// Patient / doctor: my reported issues.
class MyIssuesScreen extends StatefulWidget {
  const MyIssuesScreen({super.key});

  @override
  State<MyIssuesScreen> createState() => _MyIssuesScreenState();
}

class _MyIssuesScreenState extends State<MyIssuesScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late Future<List> _future = _fetch();

  Future<List> _fetch() async => await _api.get('/issues') as List;

  Future<void> _reload() async => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & issues')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        onPressed: () async {
          if (await showReportIssueSheet(context)) _reload();
        },
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Report a problem'),
      ),
      body: FutureBuilder<List>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
          if (!snap.hasData) return const LoadingView();
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyView(
                icon: Icons.support_agent_outlined,
                title: 'No issues',
                message: 'If something goes wrong (payment, doctor, app), report it and the admin will help.');
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
              for (final i in list)
                IssueTile(
                  issue: (i as Map).cast<String, dynamic>(),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => IssueThreadScreen(issue: (i as Map).cast<String, dynamic>())));
                    _reload();
                  },
                ),
            ]),
          );
        },
      ),
    );
  }
}

/// One issue with its messages. The admin also sees who reported it and can change the status.
class IssueThreadScreen extends StatefulWidget {
  const IssueThreadScreen({super.key, required this.issue, this.adminView = false});

  final Map<String, dynamic> issue;
  final bool adminView;

  @override
  State<IssueThreadScreen> createState() => _IssueThreadScreenState();
}

class _IssueThreadScreenState extends State<IssueThreadScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late Map<String, dynamic> _i = widget.issue;
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await _api.post('/issues/${_i['id']}/messages', body: {'text': text});
      _input.clear();
      setState(() => _i = (r as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String s) async {
    try {
      final r = await _api.post('/admin/issues/${_i['id']}/status', body: {'status': s});
      setState(() => _i = (r as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = (_i['messages'] as List? ?? const []).cast<Map>();
    final c = (_i['consultation'] as Map?)?.cast<String, dynamic>();
    final status = '${_i['status']}';
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F4),
      appBar: AppBar(
        title: Text('${_i['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.adminView)
            PopupMenuButton<String>(
              onSelected: _setStatus,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'in_progress', child: Text('Mark in progress')),
                PopupMenuItem(value: 'resolved', child: Text('Mark resolved')),
                PopupMenuItem(value: 'open', child: Text('Re-open')),
              ],
            ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: issueStatusColor(status).withAlpha(26), borderRadius: BorderRadius.circular(20)),
                child: Text(issueStatusText(status),
                    style: TextStyle(fontSize: 11.5, color: issueStatusColor(status), fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(issueCategories['${_i['category']}'] ?? '', style: const TextStyle(color: AppColors.textMuted)),
            ]),
            if (widget.adminView) ...[
              const SizedBox(height: 6),
              Text('From: ${_i['user_name']} (${_i['user_role']}) · ${_i['user_email']}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.records)),
            ],
            if (c != null) ...[
              const SizedBox(height: 6),
              Text(
                  'Consultation: ${c['patient_name']} → ${c['doctor_name']} · ${c['status']} · '
                  'Rs ${(c['fee_pkr'] as num?)?.toStringAsFixed(0) ?? '0'} · ${c['paid'] == true ? 'payment confirmed' : 'not confirmed'}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
            ],
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final m in msgs)
              Align(
                alignment: (m['from'] == 'admin') == widget.adminView ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: m['from'] == 'admin' ? AppColors.mint : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m['name']}',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.green)),
                    const SizedBox(height: 2),
                    Text('${m['text']}', style: const TextStyle(fontSize: 14, height: 1.35)),
                  ]),
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: widget.adminView ? 'Reply to the user' : 'Add more details',
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
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
