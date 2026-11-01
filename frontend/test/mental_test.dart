import 'dart:convert';

import 'package:ai_smart_healthcare/screens/mental/crisis_screen.dart';
import 'package:ai_smart_healthcare/screens/mental/mood_screen.dart';
import 'package:ai_smart_healthcare/screens/mental/screening_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/mental_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MentalRepository _repo(Future<http.Response> Function(http.Request) handler) =>
    MentalRepository(ApiClient(tokens: MemoryTokenStorage(), baseUrl: 'http://t', httpClient: MockClient(handler)));

void main() {
  testWidgets('crisis screen still shows 1122 when the server is down', (tester) async {
    final repo = _repo((_) async => throw http.ClientException('down'));
    await tester.pumpWidget(MaterialApp(home: CrisisScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('1122'), findsOneWidget);
    expect(find.text('You are not alone'), findsOneWidget);
  });

  testWidgets('GAD-7 screening: all questions required, then result shown', (tester) async {
    Map<String, dynamic>? sent;
    final repo = _repo((req) async {
      if (req.url.path == '/mental/instruments') {
        return http.Response(
            jsonEncode({
              'gad7': {
                'title': 'Anxiety check (GAD-7)',
                'intro': 'Over the last 2 weeks...',
                'questions': ['Q1', 'Q2'],
                'options': ['Not at all', 'Several days', 'More than half the days', 'Nearly every day'],
              },
              'phq9': {'title': 'Mood', 'intro': 'x', 'questions': ['P1'], 'options': ['Not at all']},
            }),
            200);
      }
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'title': 'Anxiety check (GAD-7)', 'score': 3, 'max_score': 6, 'severity': 'minimal',
            'advice': 'Few symptoms.', 'crisis': false, 'note': 'Screening tool, not a diagnosis.',
            'created_at': '2026-11-01T10:00:00Z', 'id': 'x', 'instrument': 'gad7', 'crisis_resources': null,
          }),
          201);
    });
    await tester.pumpWidget(MaterialApp(home: ScreeningScreen(repository: repo, initialInstrument: 'gad7')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Several days').first);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('See my result'), 200);
    await tester.tap(find.text('See my result'));
    await tester.pump();
    expect(find.text('Please answer all 2 questions.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Nearly every day').last, -200);
    await tester.tap(find.text('Nearly every day').last);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('See my result'), 200);
    await tester.tap(find.text('See my result'));
    await tester.pumpAndSettle();
    expect(sent, {'instrument': 'gad7', 'answers': [1, 3]});
    expect(find.text('3 / 6'), findsOneWidget);
  });

  testWidgets('mood chart shows average', (tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MoodChart(entries: [MoodEntry(today, 4, ''), MoodEntry(today.subtract(const Duration(days: 1)), 2, '')]),
      ),
    ));
    expect(find.text('Average: 3.0 / 5 over 2 days'), findsOneWidget);
  });
}
