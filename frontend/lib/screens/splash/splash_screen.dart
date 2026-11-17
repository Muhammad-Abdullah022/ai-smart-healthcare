import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

/// First screen: brand gradient, animated logo and a short loading bar.
/// Checks for a saved login, then the router moves on automatically.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  late final Animation<double> _logo = CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
  late final Animation<double> _text = CurvedAnimation(parent: _c, curve: const Interval(0.3, 0.8, curve: Curves.easeOut));

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
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.deep, Color(0xFF0B5C55), AppColors.green],
          ),
        ),
        child: Stack(children: [
          // Soft decorative circles.
          Positioned(top: -80, right: -60, child: _ring(220, 0.10)),
          Positioned(top: 120, left: -70, child: _ring(150, 0.07)),
          Positioned(bottom: -90, left: -40, child: _blob(260, 0.10)),
          Positioned(bottom: 140, right: -50, child: _blob(120, 0.08)),
          SafeArea(
            child: Column(children: [
              const Spacer(flex: 3),
              ScaleTransition(
                scale: _logo,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(25)),
                  ),
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 30, offset: const Offset(0, 12))],
                    ),
                    child: const Stack(alignment: Alignment.center, children: [
                      Icon(Icons.favorite_rounded, size: 70, color: AppColors.green),
                      Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Icon(Icons.add_rounded, size: 34, color: Colors.white),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 30),
              FadeTransition(
                opacity: _text,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(_text),
                  child: Column(children: [
                    const Text(
                      AppConfig.appName,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Disease assessment & patient support',
                      style: TextStyle(color: Colors.white.withAlpha(210), fontSize: 14),
                    ),
                    const SizedBox(height: 18),
                    Wrap(spacing: 8, children: [
                      for (final t in const ['AI assistant', 'Labs & doctors', 'Mental wellness'])
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.mint.withAlpha(40),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.softGreen.withAlpha(110)),
                          ),
                          child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                    ]),
                  ]),
                ),
              ),
              const Spacer(flex: 4),
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) => Container(
                  width: 160,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.white.withAlpha(45), borderRadius: BorderRadius.circular(3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _c.value.clamp(0.05, 1.0),
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Safe, simple health guidance', style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 12)),
              const SizedBox(height: 28),
            ]),
          ),
        ]),
      ),
    );
  }

  static Widget _ring(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha((alpha * 255).round()), width: 18)),
      );

  static Widget _blob(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.mint.withAlpha((alpha * 255).round())),
      );
}
