import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ClipCart brand mark — a depth-lit "C" monogram with a play notch.
/// Shared by the splash and the onboarding hero so the identity stays consistent
/// across the whole first-run experience.
class ClipCartLogo extends StatelessWidget {
  const ClipCartLogo({super.key, this.size = 40, this.draw = 1.0});
  final double size;
  final double draw; // 0..1 sweep-in progress (1 = fully drawn)

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: MonogramPainter(draw)),
      );
}

/// The extruded ring-arc "C" (shadow → body → highlight) open on the right, with
/// a play triangle nested in the opening.
class MonogramPainter extends CustomPainter {
  MonogramPainter(this.draw);
  final double draw;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width * 0.34;
    final rect = Rect.fromCircle(center: center, radius: r);
    final stroke = size.width * 0.155;

    // C geometry: ~280° arc, ~80° gap centred on the right
    const start = 40 * math.pi / 180;
    final sweep = (280 * math.pi / 180) * draw;

    final shadowOff = size.width * 0.024;
    // back shadow (extrusion) — offset down-right, dark violet
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF2A1E63);
    canvas.drawArc(rect.shift(Offset(shadowOff, shadowOff * 1.4)), start, sweep, false, shadow);

    // main body — lit gradient (top-left light → bottom-right deep)
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF3EFFF), Color(0xFF9D86FF), Color(0xFF6A4FE0)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, body);

    // top bevel highlight — thin bright arc on the upper edge
    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.28
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.55 * draw);
    canvas.drawArc(rect.shift(Offset(-size.width * 0.01, -size.width * 0.012)), start + 0.20, sweep * 0.62, false, hi);

    // play triangle nested in the C opening
    if (draw > 0.55) {
      final tri = ((draw - 0.55) / 0.45).clamp(0.0, 1.0);
      final tp = Paint()..color = Colors.white.withValues(alpha: 0.95 * tri);
      final s = r * 0.42;
      final cx = center.dx + r * 0.16;
      final cy = center.dy;
      final path = Path()
        ..moveTo(cx - s * 0.5, cy - s * 0.62)
        ..lineTo(cx - s * 0.5, cy + s * 0.62)
        ..lineTo(cx + s * 0.72, cy)
        ..close();
      canvas.drawShadow(path, const Color(0xFF1B1540), 2.0, false);
      canvas.drawPath(path, tp);
    }
  }

  @override
  bool shouldRepaint(MonogramPainter old) => old.draw != draw;
}
