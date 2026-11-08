import 'dart:convert';

import 'package:ai_smart_healthcare/models/assessment.dart';
import 'package:ai_smart_healthcare/screens/symptoms/symptom_checker_screen.dart';
import 'package:ai_smart_healthcare/screens/symptoms/symptom_result_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/assessment_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _json({String level = 'routine', bool emergency = false}) => {
      'id': 'a1',
      'created_at': '2026-11-01T10:00:00Z',
      'emergency': emergency,
      'triage_level': level,
      'triage_reason': 'No danger signs described.',
      'emergency_numbers': emergency
          ? [
              {'name': 'Rescue / Ambulance', 'number': '1122'}
            ]
          : [],
      'possible_causes': emergency
          ? []
          : [
              {'name': 'Viral fever', 'likelihood': 'high', 'reason': 'Fever and aches.'}
            ],
      'next_steps': ['Rest and drink fluids.'],
      'follow_up_questions': emergency ? [] : ['Do you have a rash?'],
      'tests_to_discuss': [],
      'specialist_type': null,
      'warning_signs': [],
      'symptoms': 'fever',
      'explanation': {
        'method': 'AI assessment with safety rules',
        'inputs_used': ['symptoms'],
        'rules_triggered': ['No emergency signs found by the safety rules'],
        'ai_provider': 'gemini',
        'prompt_version': 'symptom-v1',
        'limitations': 'Based only on what you typed.',
      },
      'disclaimer': 'This is health information, not a medical diagnosis.',
    };

void main() {
  test('Assessment parses backend JSON', () {
    final a = Assessment.fromJson(_json());
    expect(a.triageLevel, 'routine');
    expect(a.possibleCauses.single.name, 'Viral fever');
    expect(a.explanation.aiProvider, 'gemini');
  });

  testWidgets('result screen shows triage, causes and explanation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SymptomResultScreen(assessment: Assessment.fromJson(_json()))));
    expect(find.text('Triage: Routine'), findsOneWidget);
    expect(find.text('Viral fever'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Why this result?'), 300);
    expect(find.text('Why this result?'), findsOneWidget);
  });

  testWidgets('emergency result shows 1122 and no causes', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SymptomResultScreen(assessment: Assessment.fromJson(_json(level: 'critical', emergency: true)))));
    expect(find.text('Triage: Critical'), findsOneWidget);
    expect(find.text('1122'), findsOneWidget);
    expect(find.text('Possible causes'), findsNothing);
  });

  testWidgets('chat: symptoms, one follow-up question, then the result', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final repo = AssessmentRepository(ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://t',
      httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        sent.add(body);
        final reply = _json();
        // First call asks a question; second call (with answers) gives the final result.
        if ((body['answers'] as List).isNotEmpty) reply['follow_up_questions'] = <String>[];
        return http.Response(jsonEncode(reply), 201);
      }),
    ));
    await tester.pumpWidget(MaterialApp(home: SymptomCheckerScreen(repository: repo)));

    await tester.enterText(find.byType(TextField), 'fever and body aches');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent.single['symptoms'], 'fever and body aches');
    expect(sent.single.containsKey('severity'), isFalse);
    expect(find.text('Do you have a rash?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'No');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent.length, 2);
    expect(sent.last['answers'], [
      {'question': 'Do you have a rash?', 'answer': 'No'}
    ]);
    expect(find.text('Triage: Routine'), findsOneWidget);
    expect(find.text('• Viral fever'), findsOneWidget);
  });
}
