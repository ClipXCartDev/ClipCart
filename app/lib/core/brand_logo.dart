import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The ClipCart brand mark — a play triangle cut clean through on a diagonal.
///
/// The triangle says video; the cut says clip. It is the same mark as the
/// launcher icon, drawn from the same proportions, so the thing on the home
/// screen and the thing on the splash are one identity rather than two.
///
/// Flat, and deliberately so: the design system has no gradients, and a mark
/// that survives being 48 pixels wide is a mark with no lighting in it.
class ClipCartLogo extends StatelessWidget {
  const ClipCartLogo({super.key, this.size = 40, this.draw = 1.0, this.color = Colors.white});
  final double size;

  /// 0..1 reveal. The triangle arrives first, then the cut opens through it.
  final double draw;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: MonogramPainter(draw, color)),
      );
}

/// Paints the mark. Kept as the public painter name the splash already uses.
class MonogramPainter extends CustomPainter {
  MonogramPainter(this.draw, [this.color = Colors.white]);
  final double draw;
  final Color color;

  /// The cut's angle from horizontal, and how far above centre it sits — the
  /// two pieces are deliberately unequal so the cut reads as a decision.
  static const double _cutDegrees = -20;
  static const double _cutOffset = -0.055;

  @override
  void paint(Canvas canvas, Size size) {
    if (draw <= 0) return;
    final s = size.shortestSide;

    // The triangle arrives over the first two thirds, then the cut opens.
    final appear = (draw / 0.66).clamp(0.0, 1.0);
    final slice = ((draw - 0.66) / 0.34).clamp(0.0, 1.0);

    final h = s * 0.54;
    final w = h * 0.86;
    // A triangle's visual centre sits left of its bounding box, so it is nudged
    // right rather than box-centred.
    final c = Offset(size.width * 0.535, size.height * 0.5);
    final tri = _roundedTriangle(
      [
        Offset(c.dx - w / 2, c.dy - h / 2),
        Offset(c.dx - w / 2, c.dy + h / 2),
        Offset(c.dx + w / 2, c.dy),
      ],
      s * 0.052,
    );

    Path path = tri;
    if (slice > 0) {
      final gap = s * 0.030 * slice;
      final a = _cutDegrees * math.pi / 180;
      final band = Path()
        ..addRect(Rect.fromCenter(center: Offset(size.width / 2, size.height / 2 + s * _cutOffset),
            width: s * 3, height: gap));
      final m = Matrix4.identity()
        ..translateByDouble(size.width / 2, size.height / 2 + s * _cutOffset, 0, 1)
        ..rotateZ(a)
        ..translateByDouble(-size.width / 2, -(size.height / 2 + s * _cutOffset), 0, 1);
      path = Path.combine(ui.PathOperation.difference, tri, band.transform(m.storage));
    }

    // The reveal is a scale and a fade from the mark's own centre, so nothing
    // slides in from off-frame and the shape is legible the whole way.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(0.92 + 0.08 * appear);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: color.a * appear));
    canvas.restore();
  }

  /// A polygon with rounded corners, as a real path — an arc at each vertex
  /// between the two points where its edges stop.
  Path _roundedTriangle(List<Offset> pts, double radius) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final cur = pts[i];
      final next = pts[(i + 1) % pts.length];

      final toPrev = (prev - cur);
      final toNext = (next - cur);
      final dp = toPrev / toPrev.distance;
      final dn = toNext / toNext.distance;

      // How far back from the corner the arc has to start for this radius.
      final angle = math.acos((dp.dx * dn.dx + dp.dy * dn.dy).clamp(-1.0, 1.0));
      var back = radius / math.tan(angle / 2);
      // never eat more than half an edge, or adjacent corners collide
      back = math.min(back, math.min(toPrev.distance, toNext.distance) / 2);

      final start = cur + dp * back;
      final end = cur + dn * back;

      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      // A quadratic with the sharp corner as its control point always bulges
      // towards that corner, so it cannot come out concave. arcToPoint can,
      // and did: it needs a sweep direction, and the wrong one bites chunks
      // out of the mark instead of rounding it.
      path.quadraticBezierTo(cur.dx, cur.dy, end.dx, end.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(MonogramPainter old) => old.draw != draw || old.color != color;
}
