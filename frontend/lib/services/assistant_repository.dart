import 'api_client.dart';

/// One message in a saved health chat.
class ChatMessage {
  ChatMessage({required this.fromUser, required this.text, this.emergency = false});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        fromUser: j['role'] == 'user',
        text: j['text'] as String? ?? '',
        emergency: j['emergency'] as bool? ?? false,
      );

  final bool fromUser;
  final String text;
  final bool emergency;
}

class AssistantReply {
  AssistantReply(
      {required this.chatId, required this.message, required this.suggestSymptomCheck, this.speech = ''});

  final String chatId;

  /// Same reply in Devanagari, only for reading aloud with a Hindi voice.
  final String speech;
  final ChatMessage message;
  final bool suggestSymptomCheck;
}

class ChatSummary {
  ChatSummary({required this.id, required this.title, required this.language, required this.updatedAt, required this.messages});

  factory ChatSummary.fromJson(Map<String, dynamic> j) => ChatSummary(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Chat',
        language: j['language'] as String? ?? 'en',
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
        messages: j['messages'] as int? ?? 0,
      );

  final String id;
  final String title;
  final String language;
  final DateTime updatedAt;
  final int messages;
}

class SavedChat {
  SavedChat({required this.id, required this.language, required this.messages});

  final String id;
  final String language;
  final List<ChatMessage> messages;
}

/// Calls the backend's /assistant endpoints (the AI runs on the backend only).
class AssistantRepository {
  AssistantRepository(this.api);

  final ApiClient api;

  Future<AssistantReply> send({required String message, required String language, String? chatId}) async {
    final data = await api.post('/assistant/chat', body: {
      'message': message,
      'language': language,
      if (chatId != null) 'chat_id': chatId,
    }) as Map<String, dynamic>;
    return AssistantReply(
      chatId: data['chat_id'] as String,
      message: ChatMessage.fromJson(data['reply'] as Map<String, dynamic>),
      suggestSymptomCheck: data['suggest_symptom_check'] as bool? ?? false,
      speech: data['speech'] as String? ?? '',
    );
  }

  /// Save symptom-check messages into the chat. Returns the chat id.
  Future<String> log({String? chatId, required String language, required List<ChatMessage> messages}) async {
    final data = await api.post('/assistant/log', body: {
      if (chatId != null) 'chat_id': chatId,
      'language': language,
      'messages': [
        for (final m in messages) {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text}
      ],
    }) as Map<String, dynamic>;
    return data['chat_id'] as String;
  }

  /// Urdu / Roman Urdu text written in Devanagari, for a Hindi voice to read aloud.
  Future<String?> speech(String text) async {
    final data = await api.post('/assistant/speech', body: {'text': text}) as Map<String, dynamic>;
    return data['speech'] as String?;
  }

  Future<List<ChatSummary>> chats() async {
    final data = await api.get('/assistant/chats') as List<dynamic>;
    return data.map((e) => ChatSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SavedChat> chat(String id) async {
    final d = await api.get('/assistant/chats/$id') as Map<String, dynamic>;
    return SavedChat(
      id: d['id'] as String,
      language: d['language'] as String? ?? 'en',
      messages: (d['messages'] as List<dynamic>)
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
