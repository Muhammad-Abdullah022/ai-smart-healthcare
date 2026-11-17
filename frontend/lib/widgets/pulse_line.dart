import 'package:flutter/material.dart';

/// A soft heartbeat line drawn once across the home header — the app's signature.
/// It draws itself in when the screen opens (one gentle animation, then still).
class PulseLine extends StatefulWidget {
  const PulseLine({super.key, this.color = const Color(0xFF4CA771), this.height = 56});

  final Color color;
  final double height;

  @override
  State<PulseLine> createState() => _PulseLineState();
}

class _PulseLineState extends State<PulseLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    // Respect "reduce motion": draw the full line immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _PulsePainter(progress: Curves.easeOut.transform(_c.value), color: widget.color),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final mid = h * 0.62;
    final path = Path()..moveTo(0, mid);
    // Flat line, a small bump, the heartbeat spike, then calm again.
    final points = <Offset>[
      Offset(w * 0.40, mid),
      Offset(w * 0.46, mid - h * 0.10),
      Offset(w * 0.50, mid),
      Offset(w * 0.54, mid),
      Offset(w * 0.57, h * 0.06),
      Offset(w * 0.61, h * 0.95),
      Offset(w * 0.64, mid),
      Offset(w * 0.70, mid - h * 0.14),
      Offset(w * 0.75, mid),
      Offset(w, mid),
    ];
    for (final p in points) {
      path.lineTo(p.dx, p.dy);
    }
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * progress);

    canvas.drawPath(
      visible,
      Paint()
        ..color = color.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      visible,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.progress != progress || old.color != color;
}
