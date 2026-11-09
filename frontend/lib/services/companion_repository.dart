import 'api_client.dart';

class CompanionReply {
  CompanionReply.fromJson(Map<String, dynamic> j)
      : chatId = j['chat_id'] as String,
        reply = j['reply'] as String,
        crisis = j['crisis'] as bool? ?? false,
        crisisLines = (j['crisis_lines'] as List<dynamic>? ?? [])
            .map((l) => (name: (l as Map<String, dynamic>)['name'] as String, number: l['number'] as String))
            .toList(),
        messageType = j['message_type'] as String? ?? 'general',
        tone = j['tone'] as String? ?? 'neutral',
        severity = j['severity'] as String? ?? 'mild',
        copingTip = j['coping_tip'] as String? ?? '',
        speech = j['speech'] as String? ?? '';

  final String chatId;
  final String reply;
  final bool crisis;
  final List<({String name, String number})> crisisLines;
  final String messageType;
  final String tone;
  final String severity;
  final String copingTip;
  final String speech;
}

class CompanionTurn {
  CompanionTurn.fromJson(Map<String, dynamic> j)
      : user = j['user'] as String,
        reply = j['reply'] as String,
        crisis = j['crisis'] as bool? ?? false,
        copingTip = j['coping_tip'] as String? ?? '';

  final String user;
  final String reply;
  final bool crisis;
  final String copingTip;
}

class CompanionChatSummary {
  CompanionChatSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? 'Chat',
        language = j['language'] as String? ?? 'en',
        mood = j['mood'] as String?,
        updatedAt = DateTime.parse(j['updated_at'] as String).toLocal();

  final String id;
  final String title;
  final String language;
  final String? mood;
  final DateTime updatedAt;
}

class CompanionInsights {
  CompanionInsights.fromJson(Map<String, dynamic> j)
      : days = (j['days'] as List<dynamic>)
            .map((d) => (
                  day: DateTime.parse((d as Map<String, dynamic>)['day'] as String),
                  mood: (d['mood'] as num?)?.toDouble(),
                  heaviness: (d['chat_heaviness'] as num?)?.toDouble(),
                ))
            .toList(),
        tones = (j['tones'] as List<dynamic>)
            .map((t) => (name: (t as Map<String, dynamic>)['tone'] as String, count: t['count'] as int))
            .toList(),
        themes = (j['themes'] as List<dynamic>)
            .map((t) => (name: (t as Map<String, dynamic>)['theme'] as String, count: t['count'] as int))
            .toList(),
        note = j['note'] as String? ?? '';

  final List<({DateTime day, double? mood, double? heaviness})> days;
  final List<({String name, int count})> tones;
  final List<({String name, int count})> themes;
  final String note;
}

/// MindEase-style companion (features 17 and 19): /mental/companion endpoints.
class CompanionRepository {
  CompanionRepository(this.api);

  final ApiClient api;

  Future<CompanionReply> send(
      {required String message, required String language, String? chatId, String? mood}) async {
    final data = await api.post('/mental/companion/chat', body: {
      'message': message,
      'language': language,
      if (chatId != null) 'chat_id': chatId,
      if (mood != null) 'mood': mood,
    });
    return CompanionReply.fromJson(data as Map<String, dynamic>);
  }

  Future<List<CompanionChatSummary>> chats() async => (await api.get('/mental/companion/chats') as List<dynamic>)
      .map((c) => CompanionChatSummary.fromJson(c as Map<String, dynamic>))
      .toList();

  Future<({String language, String? mood, List<CompanionTurn> turns})> chat(String id) async {
    final d = await api.get('/mental/companion/chats/$id') as Map<String, dynamic>;
    return (
      language: d['language'] as String? ?? 'en',
      mood: d['mood'] as String?,
      turns: (d['turns'] as List<dynamic>).map((t) => CompanionTurn.fromJson(t as Map<String, dynamic>)).toList(),
    );
  }

  Future<({String summary, int turns})> memory() async {
    final d = await api.get('/mental/companion/memory') as Map<String, dynamic>;
    return (summary: d['summary'] as String? ?? '', turns: d['turns'] as int? ?? 0);
  }

  Future<void> forgetMe() => api.delete('/mental/companion/memory');

  Future<CompanionInsights> insights({int days = 14}) async =>
      CompanionInsights.fromJson(await api.get('/mental/companion/insights?days=$days') as Map<String, dynamic>);
}
