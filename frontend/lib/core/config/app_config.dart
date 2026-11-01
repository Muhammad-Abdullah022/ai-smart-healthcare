import 'package:flutter/foundation.dart';

/// App-wide settings.
///
/// The backend address is chosen automatically:
///   * Android emulator -> http://10.0.2.2:8000 (the emulator's name for your PC)
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }
}
