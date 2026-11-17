import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

/// First screen: brand gradient, centred animated logo and a small loading indicator.
/// Checks for a saved login, then the router moves on automatically.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final Animation<double> _logo = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.7, curve: Curves.easeOutBack));
  late final Animation<double> _text = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 1, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    // Show the splash for a moment, then check the saved login (the router then moves on).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1900), () {
        if (mounted) context.read<AuthProvider>().initialize();
      });
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.deep, Color(0xFF0B4F4A), AppColors.green],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(children: [
          // One soft glow behind the logo — keeps the screen calm and centred.
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, -0.18),
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withAlpha(30), Colors.white.withAlpha(0)]),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 5),
                    ScaleTransition(
                      scale: _logo,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, child) => Container(
                          padding: EdgeInsets.all(10 + 6 * _pulse.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha((40 * (1 - _pulse.value)).round()),
                          ),
                          child: child,
                        ),
                        child: Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(45), blurRadius: 28, offset: const Offset(0, 12)),
                            ],
                          ),
                          child: const Stack(alignment: Alignment.center, children: [
                            Icon(Icons.favorite_rounded, size: 64, color: AppColors.green),
                            Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Icon(Icons.add_rounded, size: 30, color: Colors.white),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    FadeTransition(
                      opacity: _text,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(_text),
                        child: Column(children: [
                          const Text(
                            AppConfig.appName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: 36,
                            height: 3,
                            decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your AI health companion',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withAlpha(215), fontSize: 15),
                          ),
                        ]),
                      ),
                    ),
                    const Spacer(flex: 6),
                    _Dots(controller: _pulse),
                    const SizedBox(height: 16),
                    Text(
                      'Symptoms  •  Labs  •  Doctors  •  Wellness',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Three dots that grow and fade one after another.
class _Dots extends StatelessWidget {
  const _Dots({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            Builder(builder: (_) {
              final t = ((controller.value - i * 0.2) % 1.0);
              final s = t < 0.5 ? t * 2 : (1 - t) * 2; // 0 -> 1 -> 0
              return Container(
                width: 8 + 4 * s,
                height: 8 + 4 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha((110 + 145 * s).round()),
                ),
              );
            }),
            if (i < 2) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
