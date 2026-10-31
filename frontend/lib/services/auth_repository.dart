import '../models/profile.dart';
import '../models/user.dart';
import 'api_client.dart';

/// All calls to the backend's /auth and /profile endpoints.
class AuthRepository {
  AuthRepository(this.api);

  final ApiClient api;

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required bool acceptedTerms,
  }) async {
    final data = await api.post('/auth/register', auth: false, body: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'accepted_terms': acceptedTerms,
    }) as Map<String, dynamic>;
    await _saveTokens(data);
  }

  Future<void> login({required String email, required String password}) async {
    final data = await api.post('/auth/login',
        auth: false, body: {'email': email, 'password': password}) as Map<String, dynamic>;
    await _saveTokens(data);
  }

  Future<AppUser> me() async {
    final data = await api.get('/auth/me') as Map<String, dynamic>;
    return AppUser.fromJson(data);
  }

  Future<void> logout() async {
    final refresh = await api.tokens.readRefreshToken();
    try {
      if (refresh != null) {
        await api.post('/auth/logout', auth: false, body: {'refresh_token': refresh});
      }
    } on ApiException {
      // Even if the server is unreachable we still log out on this device.
    } finally {
      await api.tokens.clear();
    }
  }

  Future<Profile> getProfile() async {
    final data = await api.get('/profile') as Map<String, dynamic>;
    return Profile.fromJson(data);
  }

  Future<Profile> updateProfile(Map<String, dynamic> changes) async {
    final data = await api.patch('/profile', body: changes) as Map<String, dynamic>;
    return Profile.fromJson(data);
  }

  Future<void> _saveTokens(Map<String, dynamic> data) => api.tokens.save(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
}
