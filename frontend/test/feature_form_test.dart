import 'dart:convert';

import 'package:ai_smart_healthcare/core/router/feature_screens.dart';
import 'package:ai_smart_healthcare/models/feature_catalog.dart';
import 'package:ai_smart_healthcare/screens/modules/feature_form_screen.dart';
import 'package:ai_smart_healthcare/screens/modules/feature_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/entries_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('every one of the 50 features has a real screen', () {
    expect(allFeatures.length, 50);
    for (final f in allFeatures) {
      expect(screenForFeature(f.number), isNot(isA<FeatureScreen>()), reason: 'feature ${f.number}');
    }
  });

  testWidgets('feature form validates, saves to /entries and lists the entry', (tester) async {
    final saved = <Map<String, dynamic>>[];
    final repo = EntriesRepository(ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://t',
      httpClient: MockClient((req) async {
        if (req.method == 'POST') {
          final data = (jsonDecode(req.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
          saved.add(data);
          return http.Response(jsonEncode({'id': 'e1', 'feature': 39, 'data': data, 'created_at': '2026-11-01T10:00:00Z'}), 201);
        }
        return http.Response(
            jsonEncode([for (final d in saved) {'id': 'e1', 'feature': 39, 'data': d, 'created_at': '2026-11-01T10:00:00Z'}]),
            200);
      }),
    ));
    await tester.pumpWidget(MaterialApp(home: FeatureFormScreen(number: 39, repository: repo)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Add to history'), 200);
    await tester.tap(find.text('Add to history'));
    await tester.pump();
    expect(find.text('Please fill this in'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.scrollUntilVisible(find.text('Condition'), -200);
    await tester.tap(find.text('Condition'));
    await tester.enterText(find.byType(TextFormField).first, 'Asthma');
    await tester.scrollUntilVisible(find.text('Add to history'), 200);
    await tester.tap(find.text('Add to history'));
    await tester.pumpAndSettle();
    expect(saved.single, {'kind': 'Condition', 'name': 'Asthma'});
    await tester.scrollUntilVisible(find.textContaining('Asthma'), 200);
    expect(find.textContaining('Asthma'), findsOneWidget);
  });
}
