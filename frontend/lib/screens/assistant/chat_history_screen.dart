import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/chat_language.dart';
import '../../services/api_client.dart';
import '../../services/assistant_repository.dart';
import '../../services/report_repository.dart';
import '../../widgets/state_views.dart';
import 'assistant_chat_screen.dart';

/// The user's saved health-assistant chats.
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key, required this.repository, required this.reports});

  final AssistantRepository repository;
  final ReportRepository reports;

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  late Future<List<ChatSummary>> _future = widget.repository.chats();

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat history')),
      body: FutureBuilder<List<ChatSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(
              message: e is ApiException ? e.message : 'Could not load your chats.',
              onRetry: () => setState(() => _future = widget.repository.chats()),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.chat_bubble_outline,
              title: 'No chats yet',
              message: 'Your conversations with the health assistant are saved here privately.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final c = items[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE9EEF4))),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.diagnosisTint,
                    child: Icon(Icons.chat_bubble_outline, color: AppColors.diagnosis, size: 20),
                  ),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${ChatLanguage.byCode(c.language).label} · ${_date(c.updatedAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) =>
                        AssistantChatScreen(chatId: c.id, repository: widget.repository, reports: widget.reports),
                  )),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
