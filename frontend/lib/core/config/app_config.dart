import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide settings.
///
/// The backend address is chosen automatically, in this order:
///   1. the address typed in the app ("Server address" on the login screen / Settings),
///   2. --dart-define=API_BASE_URL=... (manual override),
///   3. on a phone: the laptop's Wi-Fi address put in by RUN\START_FRONTEND.bat (LAN_SERVER),
///   4. http://localhost:8000 (Chrome/Windows on the same PC, or a phone linked with `adb reverse`).
/// If one address does not answer, the app tries the next one by itself.
///
/// No secret keys are ever stored in the app — they live on the backend.
class AppConfig {
  AppConfig._();

  static const String appName = 'AI Smart Healthcare';
  static const String _override = String.fromEnvironment('API_BASE_URL');
  static const String _lanServer = String.fromEnvironment('LAN_SERVER');
  static const String _localhost = 'http://localhost:8000';
  static const Duration requestTimeout = Duration(seconds: 45);
  static const _prefsKey = 'server_address';

  /// Address saved in the app by the user (null = automatic).
  static String? savedServer;
  static String? _working;

  static bool get _isPhone => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Addresses to try, best first.
  static List<String> get candidates => {
        if ((savedServer ?? '').isNotEmpty) savedServer!,
        if (_override.isNotEmpty) _override,
        if (_isPhone && _lanServer.isNotEmpty) _lanServer,
        _localhost,
      }.toList();

  static String get apiBaseUrl => _working ?? candidates.first;

  static void useServer(String url) => _working = url;

  /// Turns "192.168.1.5" or "192.168.1.5:8000" into "http://192.168.1.5:8000".
  static String normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri != null && !uri.hasPort && uri.scheme == 'http') s = '${uri.scheme}://${uri.host}:8000';
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      savedServer = prefs.getString(_prefsKey);
    } catch (_) {}
  }

  static Future<void> saveServer(String? url) async {
    savedServer = (url ?? '').isEmpty ? null : normalize(url!);
    _working = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (savedServer == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, savedServer!);
      }
    } catch (_) {}
  }
}
