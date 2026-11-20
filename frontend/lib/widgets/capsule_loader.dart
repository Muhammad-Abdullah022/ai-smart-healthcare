import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Loading animation: a medicine capsule whose two halves open (small granules appear in the gap)
/// and close again, on a loop.
class CapsuleLoader extends StatefulWidget {
  const CapsuleLoader({super.key, this.size = 64});

  /// Total width of the closed capsule.
  final double size;

  @override
  State<CapsuleLoader> createState() => _CapsuleLoaderState();
}

class _CapsuleLoaderState extends State<CapsuleLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0 = closed, 1 = fully open. Opens, pauses, closes, pauses.
  double _open(double t) {
    if (t < 0.35) return Curves.easeOutBack.transform(t / 0.35).clamp(0.0, 1.15);
    if (t < 0.5) return 1;
    if (t < 0.85) return 1 - Curves.easeInCubic.transform((t - 0.5) / 0.35);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    final h = w * 0.42;
    final half = w / 2;
    final maxGap = w * 0.38;
    return SizedBox(
      width: w + maxGap + 8,
      height: w * 0.8,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final open = _open(t);
          final gap = maxGap * open;
          final tilt = -0.35 + 0.12 * math.sin(t * 2 * math.pi);
          // A small "bump" when the halves snap closed.
          final squash = t > 0.85 && t < 0.95 ? 1 - 0.06 * math.sin((t - 0.85) / 0.1 * math.pi) : 1.0;
          return Center(
            child: Transform.rotate(
              angle: tilt,
              child: Transform.scale(
                scaleX: 1 / squash,
                scaleY: squash,
                child: SizedBox(
                  width: w + gap,
                  height: h * 1.8,
                  child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                    // Granules that appear in the gap while the capsule is open.
                    for (var i = 0; i < 3; i++)
                      Transform.translate(
                        offset: Offset(
                          (i - 1) * gap * 0.22,
                          -h * 0.55 * open * math.sin((t * 2 + i * 0.33) * math.pi).abs() + (i - 1).abs() * 2,
                        ),
                        child: Opacity(
                          opacity: open.clamp(0.0, 1.0),
                          child: Container(
                            width: h * 0.28,
                            height: h * 0.28,
                            decoration: BoxDecoration(
                              color: i.isEven ? AppColors.softGreen : AppColors.green.withAlpha(150),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    // Left half (green).
                    Transform.translate(
                      offset: Offset(-(half + gap) / 2, 0),
                      child: _Half(width: half, height: h, left: true),
                    ),
                    // Right half (dark).
                    Transform.translate(
                      offset: Offset((half + gap) / 2, 0),
                      child: _Half(width: half, height: h, left: false),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({required this.width, required this.height, required this.left});

  final double width;
  final double height;
  final bool left;

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(height / 2);
    final edge = Radius.circular(height * 0.12);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: left ? r : edge,
          bottomLeft: left ? r : edge,
          topRight: left ? edge : r,
          bottomRight: left ? edge : r,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: left
              ? const [Color(0xFF34D399), AppColors.green]
              : const [Color(0xFF1E4A5F), AppColors.deep],
        ),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      // Shine line along the top.
      child: Align(
        alignment: const Alignment(0, -0.45),
        child: Container(
          width: width * 0.55,
          height: height * 0.12,
          decoration: BoxDecoration(color: Colors.white.withAlpha(90), borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}
