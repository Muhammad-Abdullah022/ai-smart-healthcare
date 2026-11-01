import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/home/main_shell.dart';
import '../../screens/mental/breathing_screen.dart';
import '../../screens/mental/crisis_screen.dart';
import '../../screens/mental/mood_screen.dart';
import '../../screens/mental/screening_screen.dart';
import '../../screens/modules/feature_screen.dart';
import '../../screens/modules/module_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/onboarding/onboarding_screen.dart';
import '../../screens/profile/edit_profile_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/records/records_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/settings/consent_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/symptoms/symptom_checker_screen.dart';

/// Screens anyone can open without logging in.
const _publicRoutes = {'/onboarding', '/login', '/register', '/forgot-password'};

/// Decides where the user is allowed to be. Kept separate so it can be unit tested.
String? authRedirect({
  required AuthStatus status,
  required bool onboardingSeen,
  required String location,
}) {
  if (status == AuthStatus.unknown) {
    return location == '/splash' ? null : '/splash';
  }
  if (status == AuthStatus.unauthenticated) {
    if (!onboardingSeen) return location == '/onboarding' ? null : '/onboarding';
    if (_publicRoutes.contains(location) && location != '/onboarding') return null;
    return '/login';
  }
  // Logged in: keep the user out of splash / login / onboarding.
  if (location == '/splash' || _publicRoutes.contains(location)) return '/home';
  return null;
}

GoRouter createRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(
      status: auth.status,
      onboardingSeen: auth.onboardingSeen,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/records', builder: (_, __) => const RecordsScreen())]),
          StatefulShellBranch(
              routes: [GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (_, state) => EditProfileScreen(profile: state.extra! as Profile),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/settings/consent', builder: (_, __) => const ConsentScreen()),
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(
        path: '/module/:id',
        builder: (_, state) => ModuleScreen(moduleId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/feature/:number',
        builder: (_, state) {
          final number = int.tryParse(state.pathParameters['number']!) ?? 0;
          // Features that are built get their own screen; the rest show "being built".
          return switch (number) {
            1 || 2 || 4 => const SymptomCheckerScreen(),
            16 => const ScreeningScreen(),
            18 => const ScreeningScreen(initialInstrument: 'gad7'),
            22 => const BreathingScreen(),
            24 => const MoodScreen(),
            25 => const CrisisScreen(),
            _ => FeatureScreen(number: number),
          };
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('Page not found')),
    ),
  );
}
