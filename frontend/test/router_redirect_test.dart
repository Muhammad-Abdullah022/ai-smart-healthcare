import 'package:ai_smart_healthcare/core/router/app_router.dart';
import 'package:ai_smart_healthcare/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? go(AuthStatus s, String loc, {bool seen = true}) =>
      authRedirect(status: s, onboardingSeen: seen, location: loc);

  test('unknown status always shows splash', () {
    expect(go(AuthStatus.unknown, '/home'), '/splash');
    expect(go(AuthStatus.unknown, '/splash'), isNull);
  });

  test('first launch goes to onboarding', () {
    expect(go(AuthStatus.unauthenticated, '/splash', seen: false), '/onboarding');
    expect(go(AuthStatus.unauthenticated, '/onboarding', seen: false), isNull);
  });

  test('logged-out users cannot open private screens', () {
    expect(go(AuthStatus.unauthenticated, '/home'), '/login');
    expect(go(AuthStatus.unauthenticated, '/profile'), '/login');
    expect(go(AuthStatus.unauthenticated, '/feature/1'), '/login');
    expect(go(AuthStatus.unauthenticated, '/onboarding'), '/login');
  });

  test('logged-out users can open auth screens', () {
    expect(go(AuthStatus.unauthenticated, '/login'), isNull);
    expect(go(AuthStatus.unauthenticated, '/register'), isNull);
    expect(go(AuthStatus.unauthenticated, '/forgot-password'), isNull);
  });

  test('logged-in users skip auth screens', () {
    expect(go(AuthStatus.authenticated, '/login'), '/home');
    expect(go(AuthStatus.authenticated, '/splash'), '/home');
    expect(go(AuthStatus.authenticated, '/profile'), isNull);
  });
}
