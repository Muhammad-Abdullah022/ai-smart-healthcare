import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class TrendPoint {
  const TrendPoint(this.date, this.values);
  final DateTime date;
  final List<double> values; // 1 value, or 2 for blood pressure (upper/lower)
}

/// Simple line chart drawn with CustomPaint (no extra package).
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.unit = '', this.color = AppColors.records});

  final List<TrendPoint> points;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('Add at least two readings to see your trend.',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final last = points.last.values.map((v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1)).join('/');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(last, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('$unit  latest', style: const TextStyle(color: AppColors.textMuted)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(points, color)),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_d(points.first.date), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text(_d(points.last.date), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }

  static String _d(DateTime d) => '${d.day}/${d.month}';
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.color);

  final List<TrendPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final p in points) ...p.values];
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    if (hi - lo < 1) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.15;
    lo -= pad;
    hi += pad;

    final grid = Paint()
      ..color = const Color(0xFFEDF1F4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final series = points.first.values.length;
    for (var s = 0; s < series; s++) {
      final c = s == 0 ? color : color.withAlpha(120);
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        if (points[i].values.length <= s) continue;
        final x = size.width * i / (points.length - 1);
        final y = size.height * (1 - (points[i].values[s] - lo) / (hi - lo));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = c);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.points != points;
}
