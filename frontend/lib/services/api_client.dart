import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import 'token_storage.dart';

/// An error the screens can show directly to the user.
class ApiException implements Exception {
  ApiException(this.message, {this.code = 'error', this.statusCode});

  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Small wrapper around `http` that:
///  * adds the login token to every request,
///  * refreshes the token once when it expires,
///  * turns every failure into a friendly [ApiException].
class ApiClient {
  ApiClient({
    required this.tokens,
    http.Client? httpClient,
    String? baseUrl,
  })  : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final TokenStorage tokens;
  final http.Client _http;
  final String baseUrl;

  /// Called when the session can no longer be refreshed (user must log in again).
  void Function()? onSessionExpired;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);
  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path,
      {Object? body, bool auth = true, bool retried = false}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await tokens.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    final request = http.Request(method, Uri.parse('$baseUrl$path'))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      final streamed = await _http.send(request).timeout(AppConfig.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Please try again.', code: 'timeout');
    } on http.ClientException {
      // Also covers "server not running" on Android, Windows and Chrome.
      throw ApiException('Cannot reach the server. Is the backend running?', code: 'offline');
    }

    // Access token expired: try to refresh once, then repeat the request.
    if (response.statusCode == 401 && auth && !retried) {
      if (await _refreshTokens()) {
        return _send(method, path, body: body, auth: auth, retried: true);
      }
      onSessionExpired?.call();
    }

    return _decode(response);
  }

  Future<bool> _refreshTokens() async {
    final refresh = await tokens.readRefreshToken();
    if (refresh == null) return false;
    try {
      final data = await post('/auth/refresh', body: {'refresh_token': refresh}, auth: false)
          as Map<String, dynamic>;
      await tokens.save(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
      return true;
    } on ApiException {
      await tokens.clear();
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        data = null;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    // Backend errors look like {"error": {"code": "...", "message": "..."}}
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final error = data['error'] as Map<String, dynamic>;
      final details = error['details'];
      var message = error['message'] as String? ?? 'Something went wrong.';
      if (details is List && details.isNotEmpty && details.first is Map) {
        final first = details.first as Map;
        message = '${first['field']}: ${first['message']}';
      }
      throw ApiException(message,
          code: error['code'] as String? ?? 'error', statusCode: response.statusCode);
    }
    throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
  }
}
