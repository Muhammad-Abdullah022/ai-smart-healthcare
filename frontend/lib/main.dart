import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'providers/auth_provider.dart';
import 'services/api_client.dart';
import 'services/auth_repository.dart';
import 'services/token_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load(); // server address chosen in the app, if any

  // Build the app's services once and share them.
  final api = ApiClient(tokens: SecureTokenStorage());
  final auth = AuthProvider(AuthRepository(api));

  runApp(HealthcareApp(auth: auth));
}
