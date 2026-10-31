/// App-wide settings.
///
/// The backend address can be changed without editing code:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
///
/// Default `10.0.2.2` is how the Android emulator reaches your PC's localhost.
/// No secret keys are ever stored in the app — they live on the backend.
class AppConfig {
  AppConfig._();

  static const String appName = 'AI Smart Healthcare';
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const Duration requestTimeout = Duration(seconds: 20);
}
