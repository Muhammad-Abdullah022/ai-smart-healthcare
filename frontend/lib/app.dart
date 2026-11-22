import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'services/live_notifications.dart';

/// The root widget. It owns the router and the theme.
class HealthcareApp extends StatefulWidget {
  const HealthcareApp({super.key, required this.auth});

  final AuthProvider auth;

  @override
  State<HealthcareApp> createState() => _HealthcareAppState();
}

class _HealthcareAppState extends State<HealthcareApp> {
  late final GoRouter _router = createRouter(widget.auth);

  @override
  void initState() {
    super.initState();
    // Tapping a phone notification opens the right screen (e.g. the consultation chat).
    LiveNotifications.instance.onOpen = (link) => _router.push(link);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: widget.auth,
      child: MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
