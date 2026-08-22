import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand_logo.dart';
import '../../core/theme.dart';

/// Modern animated splash — a depth-lit "C" monogram (with a play notch)
/// floating over a deep-violet field of drifting glow orbs and glints.
/// Shown while auth resolves (AuthStatus.unknown), so the ambient layer loops
/// while the entrance sequence plays once.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _ambient; // loops forever (orbs, glints, shimmer)
  late final AnimationController _enter;   // plays once (logo + wordmark reveal)

  // entrance sub-animations
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _ringDraw;
  late final Animation<double> _wordFade;
  late final Animation<double> _wordSlide;
  late final Animation<double> _tagFade;
  late final Animation<double> _barFade;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1650))..forward();

    _logoFade = CurvedAnimation(parent: _enter, curve: const Interval(0.00, 0.25, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.62, end: 1.0)
        .animate(CurvedAnimation(parent: _enter, curve: const Interval(0.00, 0.55, curve: Curves.easeOutBack)));
    _ringDraw = CurvedAnimation(parent: _enter, curve: const Interval(0.12, 0.70, curve: Curves.easeOutCubic));
    _wordFade = CurvedAnimation(parent: _enter, curve: const Interval(0.45, 0.75, curve: Curves.easeOut));
    _wordSlide = Tween<double>(begin: 16, end: 0)
        .animate(CurvedAnimation(parent: _enter, curve: const Interval(0.45, 0.80, curve: Curves.easeOutCubic)));
    _tagFade = CurvedAnimation(parent: _enter, curve: const Interval(0.62, 0.92, curve: Curves.easeOut));
    _barFade = CurvedAnimation(parent: _enter, curve: const Interval(0.78, 1.0, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ambient.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A2160),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── ambient background: gradient field + drifting glow orbs ──
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.2, -0.55),
                  radius: 1.35,
                  colors: [Color(0xFF5B45B8), Color(0xFF2E2568), Color(0xFF1B1540)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ambient,
                builder: (_, __) => CustomPaint(painter: _AmbientPainter(_ambient.value), size: Size.infinite),
              ),
            ),
            // ── foreground: logo + wordmark + loader ──
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 3D "C" monogram
                  AnimatedBuilder(
                    animation: Listenable.merge([_enter, _ambient]),
                    builder: (_, __) {
                      // gentle idle float + glow pulse from the ambient loop
                      final t = _ambient.value * 2 * math.pi;
                      final float = math.sin(t) * 4.0;
                      final pulse = 0.5 + 0.5 * math.sin(t);
                      return Opacity(
                        opacity: _logoFade.value,
                        child: Transform.translate(
                          offset: Offset(0, float),
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: Container(
                              width: 128,
                              height: 128,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF8E74FF).withValues(alpha: 0.30 + 0.22 * pulse),
                                    blurRadius: 46 + 12 * pulse,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: CustomPaint(painter: MonogramPainter(_ringDraw.value)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  // wordmark with a shimmer sweep
                  AnimatedBuilder(
                    animation: Listenable.merge([_enter, _ambient]),
                    builder: (_, __) => Opacity(
                      opacity: _wordFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _wordSlide.value),
                        child: _ShimmerText(
                          'ClipCart',
                          phase: _ambient.value,
                          style: const TextStyle(
                            fontFamily: kSans, fontSize: 34, height: 1.0,
                            fontWeight: FontWeight.w700, letterSpacing: -1.0, color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _tagFade,
                    child: Text(
                      'FUNNY MOVIE CLIPS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontFamily: kMono, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 3.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── slim animated loader, pinned near the bottom ──
            Align(
              alignment: const Alignment(0, 0.82),
              child: FadeTransition(
                opacity: _barFade,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _ambient,
                    builder: (_, __) => CustomPaint(
                      size: const Size(120, 3),
                      painter: _LoaderPainter(_ambient.value),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drifting glow orbs + fine glints — the animated background graphics.
class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t);
  final double t; // 0..1 loop

  static const _orbs = [
    (Offset(0.18, 0.24), 150.0, Color(0xFF8E74FF), 0.0),
    (Offset(0.86, 0.20), 120.0, Color(0xFF6A54D8), 0.35),
    (Offset(0.78, 0.82), 170.0, Color(0xFF5238B0), 0.6),
    (Offset(0.14, 0.86), 130.0, Color(0xFF9D8BFF), 0.85),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const tau = 2 * math.pi;
    for (final o in _orbs) {
      final (base, radius, color, phase) = o;
      final a = (t + phase) * tau;
      final dx = math.sin(a) * 0.05;
      final dy = math.cos(a * 0.8) * 0.05;
      final c = Offset((base.dx + dx) * size.width, (base.dy + dy) * size.height);
      final alpha = 0.16 + 0.08 * (0.5 + 0.5 * math.sin(a));
      final paint = Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0.0)])
            .createShader(Rect.fromCircle(center: c, radius: radius));
      canvas.drawCircle(c, radius, paint);
    }

    // fine drifting glints (star specks)
    final glint = Paint()..color = Colors.white;
    const specks = [
      Offset(0.30, 0.16), Offset(0.68, 0.30), Offset(0.50, 0.12),
      Offset(0.24, 0.62), Offset(0.82, 0.56), Offset(0.60, 0.74),
      Offset(0.40, 0.88), Offset(0.90, 0.40),
    ];
    for (var i = 0; i < specks.length; i++) {
      final tw = 0.5 + 0.5 * math.sin((t * 2 * math.pi) + i * 0.9);
      glint.color = Colors.white.withValues(alpha: 0.10 + 0.30 * tw);
      final s = specks[i];
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), 1.0 + 0.8 * tw, glint);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.t != t;
}

/// A thin track with a violet comet that sweeps left→right on the ambient loop.
class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), track);

    // comet: a moving segment (~34% width) that eases across and wraps
    const segFrac = 0.34;
    const speed = 1.0;
    final p = (t * speed) % 1.0;
    final segW = size.width * segFrac;
    final travel = size.width + segW;
    final x = -segW + p * travel;
    final rect = Rect.fromLTWH(x, 0, segW, size.height);
    final comet = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF9D8BFF).withValues(alpha: 0.0),
          const Color(0xFFCFC4FF),
          const Color(0xFF9D8BFF).withValues(alpha: 0.0),
        ],
      ).createShader(rect)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.height;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(size.height)));
    canvas.drawLine(Offset(x, size.height / 2), Offset(x + segW, size.height / 2), comet);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LoaderPainter old) => old.t != t;
}

/// Wordmark with a soft highlight sweep driven by the ambient phase.
class _ShimmerText extends StatelessWidget {
  const _ShimmerText(this.text, {required this.phase, required this.style});
  final String text;
  final double phase; // 0..1
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final p = (phase * 1.6) % 1.6 - 0.3; // sweep position, with a pause off-screen
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Colors.white, Color(0xFFEDE8FF), Colors.white],
          stops: [
            (p - 0.16).clamp(0.0, 1.0),
            p.clamp(0.0, 1.0),
            (p + 0.16).clamp(0.0, 1.0),
          ],
        ).createShader(rect);
      },
      child: Text(text, style: style),
    );
  }
}
