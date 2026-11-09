import 'dart:convert';

import 'package:ai_smart_healthcare/screens/mental/companion/companion_chat_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/companion_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:ai_smart_healthcare/services/voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Silent extends VoiceService {
  @override
  Future<void> speak(String text, String languageCode) async {}
  @override
  Future<void> speakNow(String text, String languageCode) async {}
  @override
  Future<void> stopSpeaking() async {}
  @override
  void dispose() {}
}

void main() {
  testWidgets('opener from check-in is sent with the mood; crisis lines are shown', (tester) async {
    Map<String, dynamic>? sent;
    final api = ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'chat_id': 'c1',
              'reply': 'You are not alone. Umang Pakistan listens 24/7.',
              'crisis': true,
              'crisis_lines': [
                {'name': 'Umang Pakistan', 'number': '0317-4288665'}
              ],
              'message_type': 'emotional',
              'tone': 'hopeless',
              'severity': 'crisis',
              'coping_tip': '',
              'speech': '',
            }),
            200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: CompanionChatScreen(
          repository: CompanionRepository(api), language: 'en', mood: 'Sad', opener: 'I feel sad.', voice: _Silent()),
    ));
    await tester.pumpAndSettle();
    expect(sent!['mood'], 'Sad');
    expect(sent!['message'], 'I feel sad.');
    expect(find.text('You can talk to someone now'), findsOneWidget);
    expect(find.text('0317-4288665'), findsOneWidget);
  });
}
