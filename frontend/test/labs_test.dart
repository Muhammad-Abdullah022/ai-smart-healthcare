import 'dart:convert';

import 'package:ai_smart_healthcare/screens/labs/lab_options_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/lab_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows English test name and labs with published prices', (tester) async {
    final api = ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        if (req.url.path == '/profile') return http.Response(jsonEncode({'city': 'Lahore'}), 200);
        return http.Response(
            jsonEncode({
              'city': 'Lahore',
              'known_city': true,
              'tests': [
                {
                  'asked': 'TSH',
                  'family': 'thyroid',
                  'name_en': 'Thyroid tests (TSH / T3 / T4)',
                  'offers': [
                    {'lab': 'Punjab Rangers Teaching Hospital', 'branch': '', 'address': 'Lahore', 'phone': '',
                     'lab_type': 'Hospital', 'published_name': 'TSH', 'price_pkr': 720,
                     'source_url': 'https://prth.com.pk/testpanels/', 'checked': '2026-11-08', 'notes': ''}
                  ],
                }
              ],
              'labs_without_prices': [],
              'note': 'Please confirm with the lab.',
              'directory_url': 'https://os.phc.org.pk/Registered_Labs.aspx',
            }),
            200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: LabOptionsScreen(tests: const ['TSH'], repository: LabRepository(api))));
    await tester.pumpAndSettle();
    expect(find.text('Thyroid tests (TSH / T3 / T4)'), findsOneWidget);
    expect(find.text('Rs 720'), findsOneWidget);
    expect(find.text('Punjab Rangers Teaching Hospital'), findsOneWidget);
  });
}
