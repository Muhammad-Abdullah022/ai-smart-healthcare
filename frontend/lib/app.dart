import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';

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
        // On a laptop/Chrome the app is shown at phone width, centred, instead of
        // stretching across the whole window (which makes everything look huge).
        builder: (context, child) => PhoneFrame(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}


/// Keeps the layout at a comfortable phone width on wide screens.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  static const double maxWidth = 440;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width <= maxWidth + 40) return child; // a real phone: use the full screen
    return ColoredBox(
      color: const Color(0xFFE4EAF1),
      child: Center(
        child: Container(
          width: maxWidth,
          margin: const EdgeInsets.symmetric(vertical: 24),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FC),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x2216324F), blurRadius: 40, offset: Offset(0, 16))],
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(maxWidth, MediaQuery.of(context).size.height - 48)),
            child: child,
          ),
        ),
      ),
    );
  }
}
