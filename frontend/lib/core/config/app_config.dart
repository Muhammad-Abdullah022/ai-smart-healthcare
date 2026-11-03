import 'package:flutter/foundation.dart';

/// App-wide settings.
///
/// The backend address is chosen automatically:
///   * Android phone/emulator -> http://localhost:8000 (linked to the PC with `adb reverse`)
///   * Chrome / Windows -> http://localhost:8000
/// Override it for a real phone:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
///
/// No secret keys are ever stored in the app — they live on the backend.
class AppConfig {
  AppConfig._();

  static const String appName = 'AI Smart Healthcare';
  static const String _override = String.fromEnvironment('API_BASE_URL');
  static const Duration requestTimeout = Duration(seconds: 20);

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    return 'http://localhost:8000';
  }
}
