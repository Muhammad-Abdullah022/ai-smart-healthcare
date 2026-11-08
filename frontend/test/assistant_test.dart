import 'dart:convert';

import 'package:ai_smart_healthcare/screens/assistant/assistant_chat_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/assistant_repository.dart';
import 'package:ai_smart_healthcare/services/report_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:ai_smart_healthcare/services/voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// No real speech engine in tests.
class _SilentVoice extends VoiceService {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, String locale) async => spoken.add('$locale:$text');
  @override
  Future<void> stopSpeaking() async {}
  @override
  Future<bool> listen(String locale, void Function(String, bool) onText, {void Function()? onDone}) async => false;
  @override
  Future<void> stopListening() async {}
  @override
  void dispose() {}
}

void main() {
  test('report comparison parses rows', () {
    final c = ReportComparison.fromJson({
      'rows': [
        {'name': 'Hb', 'unit': 'g/dL', 'old_value': '10', 'new_value': '12', 'old_flag': 'low',
         'new_flag': 'normal', 'change': 'up', 'now_normal': true, 'now_abnormal': false}
      ],
      'note': 'Ask your doctor.',
    });
    expect(c.rows.single.nowNormal, isTrue);
    expect(mimeTypeFor('scan.PDF'), 'application/pdf');
  });

  testWidgets('asks language first, then chats in Roman Urdu and reads the reply aloud', (tester) async {
    Map<String, dynamic>? sent;
    final api = ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'chat_id': 'c1',
              'reply': {'role': 'assistant', 'text': 'Pani zyada piyein.', 'emergency': false, 'at': '2026-11-08T10:00:00Z'},
              'suggest_symptom_check': true,
              'emergency_numbers': [],
            }),
            200);
      }),
    );
    final voice = _SilentVoice();
    await tester.pumpWidget(MaterialApp(
      home: AssistantChatScreen(repository: AssistantRepository(api), reports: ReportRepository(api), voice: voice),
    ));
    expect(find.text('Roman Urdu'), findsOneWidget);
    await tester.tap(find.text('Roman Urdu'));
    await tester.pump();
    expect(voice.spoken.single, startsWith('en-IN:Theek hai'));

    await tester.enterText(find.byType(TextField), 'bukhar mein kya karein?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent!['language'], 'roman_ur');
    expect(find.text('Pani zyada piyein.'), findsOneWidget);
    expect(find.text('Start a symptom check'), findsOneWidget);
    expect(voice.spoken.last, 'en-IN:Pani zyada piyein.');
  });
}
