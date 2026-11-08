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

const _assessment = {
  'id': 'a1',
  'created_at': '2026-11-08T10:00:00Z',
  'emergency': false,
  'triage_level': 'routine',
  'triage_reason': 'No danger signs.',
  'emergency_numbers': [],
  'possible_causes': [],
  'next_steps': [],
  'follow_up_questions': ['Kab se bukhar hai?'],
  'tests_to_discuss': [],
  'specialist_type': null,
  'warning_signs': [],
  'symptoms': 'bukhar',
  'explanation': {
    'method': 'AI', 'inputs_used': [], 'rules_triggered': [], 'ai_provider': 'gemini',
    'prompt_version': 'symptom-v1', 'limitations': '',
  },
  'disclaimer': 'Not a diagnosis.',
};

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
    String? checkLanguage;
    final api = ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        if (req.url.path == '/assistant/log') return http.Response(jsonEncode({'chat_id': 'c1'}), 200);
        if (req.url.path == '/assessments/symptoms') {
          checkLanguage = (jsonDecode(req.body) as Map<String, dynamic>)['language'] as String;
          return http.Response(jsonEncode(_assessment), 200);
        }
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
    expect(voice.spoken.single, startsWith('roman_ur:Theek hai'));

    await tester.enterText(find.byType(TextField), 'bukhar mein kya karein?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent!['language'], 'roman_ur');
    expect(find.text('Pani zyada piyein.'), findsOneWidget);
    // Symptoms described -> the symptom check starts in the same chat, in the same language.
    expect(checkLanguage, 'roman_ur');
    expect(find.text('Kab se bukhar hai?'), findsOneWidget);
    expect(voice.spoken, contains('roman_ur:Pani zyada piyein.'));
    expect(voice.spoken.last, 'roman_ur:Kab se bukhar hai?');
  });
}
