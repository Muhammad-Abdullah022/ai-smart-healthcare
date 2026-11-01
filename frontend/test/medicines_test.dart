import 'dart:convert';

import 'package:ai_smart_healthcare/screens/medicines/medicines_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/medicine_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('today tab: marking a due dose as taken sends the intake', (tester) async {
    var status = 'due';
    String? loggedPath;
    final repo = MedicineRepository(ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://t',
      httpClient: MockClient((req) async {
        if (req.url.path == '/medicines/today') {
          return http.Response(
              jsonEncode([
                {'medicine_id': 'm1', 'name': 'Panadol', 'strength': '500 mg', 'time': '08:00', 'status': status}
              ]),
              200);
        }
        if (req.url.path == '/medicines') return http.Response('[]', 200);
        loggedPath = req.url.path;
        status = 'taken';
        return http.Response(
            jsonEncode({'medicine_id': 'm1', 'name': 'Panadol', 'strength': '500 mg', 'time': '08:00', 'status': 'taken'}),
            200);
      }),
    ));
    await tester.pumpWidget(MaterialApp(home: MedicinesScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Due now'), findsOneWidget);

    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();
    expect(loggedPath, '/medicines/m1/intake');
    expect(find.text('Due now'), findsNothing);
    expect(find.text('Taken'), findsOneWidget); // status label, button gone
  });

  test('Dose parses JSON', () {
    final d = Dose.fromJson({'medicine_id': 'm', 'name': 'X', 'strength': '', 'time': '09:00', 'status': 'missed'});
    expect(d.status, 'missed');
  });
}
