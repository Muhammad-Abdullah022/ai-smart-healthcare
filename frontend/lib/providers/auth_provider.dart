import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_repository.dart';
import '../services/consultation_repository.dart';
import '../services/live_notifications.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Holds "who is logged in" for the whole app.
/// Screens listen to it, and the router uses it to decide where to go.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo) {
    _repo.api.onSessionExpired = _handleSessionExpired;
  }

  final AuthRepository _repo;
  static const _onboardingKey = 'onboarding_seen';

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;
  bool onboardingSeen = false;

  AuthRepository get repository => _repo;

  /// Runs once on the splash screen.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    onboardingSeen = prefs.getBool(_onboardingKey) ?? false;
    final token = await _repo.api.tokens.readAccessToken();
    if (token == null) {
      status = AuthStatus.unauthenticated;
    } else {
      try {
        user = await _repo.me();
        status = AuthStatus.authenticated;
        _startLive();
      } on ApiException catch (e) {
        // Offline with saved tokens: keep the user out until the server is reachable.
        status = AuthStatus.unauthenticated;
        if (e.code != 'offline') await _repo.api.tokens.clear();
      }
    }
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboardingSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await _repo.login(email: email.trim(), password: password);
    await _loadUser();
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required bool acceptedTerms,
  }) async {
    await _repo.register(
      fullName: fullName.trim(),
      email: email.trim(),
      password: password,
      acceptedTerms: acceptedTerms,
    );
    await _loadUser();
  }

  Future<void> refreshUser() async {
    user = await _repo.me();
    notifyListeners();
  }

  Future<void> logout() async {
    LiveNotifications.instance.stop();
    LiveEvents.instance.disconnect();
    await _repo.logout();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> _loadUser() async {
    user = await _repo.me();
    status = AuthStatus.authenticated;
    _startLive();
    notifyListeners();
  }

  /// Live chat connection + phone notifications for the logged-in user, on every screen.
  void _startLive() {
    LiveNotifications.instance.start(_repo.api, isDoctor: user?.isDoctor ?? false);
  }

  void _handleSessionExpired() {
    if (status == AuthStatus.authenticated) {
      user = null;
      status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }
}
