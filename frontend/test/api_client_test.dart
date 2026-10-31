import 'dart:convert';

import 'package:ai_smart_healthcare/services/api_client.dart';
import 'package:ai_smart_healthcare/services/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('sends the access token and decodes JSON', () async {
    final tokens = MemoryTokenStorage();
    await tokens.save(accessToken: 'A1', refreshToken: 'R1');
    final client = ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer A1');
        return _json(200, {'ok': true});
      }),
    );
    expect(await client.get('/x'), {'ok': true});
  });

  test('backend error becomes a friendly ApiException', () async {
    final client = ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => _json(401, {
            'error': {'code': 'invalid_credentials', 'message': 'Email or password is incorrect.'}
          })),
    );
    await expectLater(
      client.post('/auth/login', body: {}, auth: false),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'invalid_credentials')
          .having((e) => e.message, 'message', 'Email or password is incorrect.')),
    );
  });

  test('expired access token is refreshed once, then request is repeated', () async {
    final tokens = MemoryTokenStorage();
    await tokens.save(accessToken: 'old', refreshToken: 'R1');
    var calls = 0;
    final client = ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        calls++;
        if (req.url.path == '/auth/refresh') {
          return _json(200, {'access_token': 'new', 'refresh_token': 'R2'});
        }
        if (req.headers['Authorization'] == 'Bearer old') {
          return _json(401, {'error': {'code': 'token_expired', 'message': 'expired'}});
        }
        return _json(200, {'me': 'ok'});
      }),
    );
    expect(await client.get('/auth/me'), {'me': 'ok'});
    expect(calls, 3);
    expect(await tokens.readAccessToken(), 'new');
    expect(await tokens.readRefreshToken(), 'R2');
  });

  test('failed refresh clears tokens and reports session expired', () async {
    final tokens = MemoryTokenStorage();
    await tokens.save(accessToken: 'old', refreshToken: 'bad');
    var expired = false;
    final client = ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => _json(401, {'error': {'code': 'invalid_token', 'message': 'Please log in again.'}})),
    )..onSessionExpired = () => expired = true;

    await expectLater(client.get('/auth/me'), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
    expect(await tokens.readAccessToken(), isNull);
  });

  test('network failure becomes an offline error', () async {
    final client = ApiClient(
      tokens: MemoryTokenStorage(),
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(
      client.get('/health'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'offline')),
    );
  });
}
