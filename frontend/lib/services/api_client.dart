import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
        _fixedBaseUrl = baseUrl;

  final TokenStorage tokens;
  final http.Client _http;
  final String? _fixedBaseUrl;

  /// The backend address in use (follows the "Server address" setting and automatic fallback).
  String get baseUrl => _fixedBaseUrl ?? AppConfig.apiBaseUrl;

  String get _offlineMessage => 'Cannot reach the server at $baseUrl. Make sure the backend is running and the '
      'phone is on the same Wi-Fi as the laptop, or tap "Server address" on the login screen.';

  /// The current address did not answer: try the other known addresses and switch to one that does.
  Future<bool> _switchServer() async {
    if (_fixedBaseUrl != null) return false;
    final current = baseUrl;
    for (final candidate in AppConfig.candidates) {
      if (candidate == current) continue;
      try {
        final r = await _http.get(Uri.parse('$candidate/health')).timeout(const Duration(seconds: 4));
        if (r.statusCode == 200) {
          AppConfig.useServer(candidate);
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Is a backend answering at [url]? Used by the "Server address" screen.
  Future<bool> ping(String url) async {
    try {
      final r = await _http.get(Uri.parse('$url/health')).timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Called when the session can no longer be refreshed (user must log in again).
  void Function()? onSessionExpired;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);
  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Upload one file (multipart/form-data), e.g. a medical report photo or PDF.
  Future<dynamic> postFile(String path,
      {required List<int> bytes,
      required String filename,
      required String mimeType,
      Map<String, String> fields = const {},
      bool retried = false}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename, contentType: _mediaType(mimeType)));
    final token = await tokens.readAccessToken();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    http.Response response;
    try {
      // Reading a report with AI can take longer than a normal request.
      final streamed = await _http.send(request).timeout(AppConfig.requestTimeout * 2);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Please try again.', code: 'timeout');
    } on http.ClientException {
      throw ApiException(_offlineMessage, code: 'offline');
    }
    if (response.statusCode == 401 && !retried) {
      if (await _refreshTokens()) {
        return postFile(path,
            bytes: bytes, filename: filename, mimeType: mimeType, fields: fields, retried: true);
      }
      onSessionExpired?.call();
    }
    return _decode(response);
  }

  static MediaType _mediaType(String mime) {
    final parts = mime.split('/');
    return parts.length == 2 ? MediaType(parts[0], parts[1]) : MediaType('application', 'octet-stream');
  }

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
      // Also covers "server not running" on Android, Windows and Chrome. Try the other addresses once.
      if (!retried && await _switchServer()) {
        return _send(method, path, body: body, auth: auth, retried: true);
      }
      throw ApiException(_offlineMessage, code: 'offline');
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

  /// GET raw bytes (e.g. a saved prescription photo). Throws ApiException on errors.
  Future<List<int>> getBytes(String path, {bool retried = false}) async {
    final token = await tokens.readAccessToken();
    http.Response response;
    try {
      response = await _http
          .get(Uri.parse('$baseUrl$path'), headers: {if (token != null) 'Authorization': 'Bearer $token'})
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Please try again.', code: 'timeout');
    } on http.ClientException {
      throw ApiException(_offlineMessage, code: 'offline');
    }
    if (response.statusCode == 401 && !retried && await _refreshTokens()) {
      return getBytes(path, retried: true);
    }
    if (response.statusCode >= 400) _decode(response);
    return response.bodyBytes;
  }

  /// POST JSON and get raw bytes back (e.g. MP3 audio). Throws ApiException on errors.
  Future<List<int>> postForBytes(String path, Object body, {bool retried = false}) async {
    final token = await tokens.readAccessToken();
    final request = http.Request('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll({'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'})
      ..body = jsonEncode(body);
    http.Response response;
    try {
      final streamed = await _http.send(request).timeout(AppConfig.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Please try again.', code: 'timeout');
    } on http.ClientException {
      throw ApiException(_offlineMessage, code: 'offline');
    }
    if (response.statusCode == 401 && !retried && await _refreshTokens()) {
      return postForBytes(path, body, retried: true);
    }
    if (response.statusCode >= 400) _decode(response); // throws with the server's message
    return response.bodyBytes;
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
    if (response.statusCode == 404) {
      throw ApiException('The backend is an old version. Close the backend window and run START_BACKEND.bat again.',
          code: 'old_backend', statusCode: 404);
    }
    throw ApiException('Something went wrong (error ${response.statusCode}). Please try again.',
        statusCode: response.statusCode);
  }
}
