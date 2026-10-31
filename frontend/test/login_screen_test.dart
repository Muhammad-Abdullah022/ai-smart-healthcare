import 'dart:convert';

import 'package:ai_smart_healthcare/providers/auth_provider.dart';
import 'package:ai_smart_healthcare/screens/auth/login_screen.dart';
import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/auth_repository.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Widget _wrap(AuthProvider auth) => ChangeNotifierProvider.value(
      value: auth,
      child: const MaterialApp(home: LoginScreen()),
    );

AuthProvider _auth(MockClient http) =>
    AuthProvider(AuthRepository(ApiClient(tokens: MemoryTokenStorage(), baseUrl: 'http://t', httpClient: http)));

void main() {
  testWidgets('shows validation errors for empty form', (tester) async {
    await tester.pumpWidget(_wrap(_auth(MockClient((_) async => http.Response('', 500)))));
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('shows server error message on wrong password', (tester) async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({'error': {'code': 'invalid_credentials', 'message': 'Email or password is incorrect.'}}), 401));
    await tester.pumpWidget(_wrap(_auth(client)));
    await tester.enterText(find.byType(TextFormField).at(0), 'ayesha@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'Wrong1234');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('successful login marks user as authenticated', (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'A', 'refresh_token': 'R', 'token_type': 'bearer'}), 200);
      }
      return http.Response(
          jsonEncode({'id': '1', 'email': 'ayesha@example.com', 'full_name': 'Ayesha Khan', 'roles': ['patient'], 'email_verified': false}),
          200);
    });
    final auth = _auth(client);
    await tester.pumpWidget(_wrap(auth));
    await tester.enterText(find.byType(TextFormField).at(0), 'ayesha@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'Secure123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.user?.firstName, 'Ayesha');
  });
}
