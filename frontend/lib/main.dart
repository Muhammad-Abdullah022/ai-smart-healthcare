import 'package:flutter/material.dart';

import 'app.dart';
import 'providers/auth_provider.dart';
import 'services/api_client.dart';
import 'services/auth_repository.dart';
import 'services/token_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Build the app's services once and share them.
  final api = ApiClient(tokens: SecureTokenStorage());
  final auth = AuthProvider(AuthRepository(api));

  runApp(HealthcareApp(auth: auth));
}
