import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand_logo.dart';
import '../../core/theme.dart';

/// §01 Onboarding — a minimal, premium brand intro. Deep-violet field, a large
/// depth-lit "C" logo with a breathing glow, the wordmark + tagline, and the two
/// auth CTAs. No video, no chips — the mark is the hero (spec §5, no carousel).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  late final AnimationController _ambient; // loops (glow pulse + drifting orbs)
  late final AnimationController _enter;   // one-shot staged reveal

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _ringDraw;
  late final Animation<double> _wordFade;
  late final Animation<double> _wordSlide;
  late final Animation<double> _tagFade;
  late final Animation<double> _ctaFade;
  late final Animation<double> _ctaSlide;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();

    _logoFade = CurvedAnimation(parent: _enter, curve: const Interval(0.00, 0.28, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.66, end: 1.0)
        .animate(CurvedAnimation(parent: _enter, curve: const Interval(0.00, 0.56, curve: Curves.easeOutBack)));
    _ringDraw = CurvedAnimation(parent: _enter, curve: const Interval(0.10, 0.66, curve: Curves.easeOutCubic));
    _wordFade = CurvedAnimation(parent: _enter, curve: const Interval(0.42, 0.68, curve: Curves.easeOut));
    _wordSlide = Tween<double>(begin: 18, end: 0)
        .animate(CurvedAnimation(parent: _enter, curve: const Interval(0.42, 0.74, curve: Curves.easeOutCubic)));
    _tagFade = CurvedAnimation(parent: _enter, curve: const Interval(0.56, 0.82, curve: Curves.easeOut));
    _ctaFade = CurvedAnimation(parent: _enter, curve: const Interval(0.70, 1.0, curve: Curves.easeOut));
    _ctaSlide = Tween<double>(begin: 22, end: 0)
        .animate(CurvedAnimation(parent: _enter, curve: const Interval(0.70, 1.0, curve: Curves.easeOutCubic)));
  }

  @override
  void dispose() {
    _ambient.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: const Color(0xFF1B1540),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── background: violet field + drifting glow orbs ──
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.28),
                  radius: 1.25,
                  colors: [Color(0xFF4B3AA0), Color(0xFF2A2160), Color(0xFF15102F)],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ambient,
                builder: (_, __) => CustomPaint(painter: _OrbPainter(_ambient.value), size: Size.infinite),
              ),
            ),

            // ── content ──
            Padding(
              padding: EdgeInsets.fromLTRB(28, pad.top + 8, 28, pad.bottom + 22),
              child: Column(
                children: [
                  const Spacer(flex: 5),
                  // hero: big depth-lit "C" with a breathing glow
                  AnimatedBuilder(
                    animation: Listenable.merge([_enter, _ambient]),
                    builder: (_, __) {
                      final t = _ambient.value * 2 * math.pi;
                      final float = math.sin(t) * 4.5;
                      final pulse = 0.5 + 0.5 * math.sin(t);
                      return Opacity(
                        opacity: _logoFade.value,
                        child: Transform.translate(
                          offset: Offset(0, float),
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: Container(
                              width: 148,
                              height: 148,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF9077FF).withValues(alpha: 0.32 + 0.24 * pulse),
                                    blurRadius: 54 + 16 * pulse,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: ClipCartLogo(size: 148, draw: _ringDraw.value),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  // wordmark
                  AnimatedBuilder(
                    animation: _enter,
                    builder: (_, __) => Opacity(
                      opacity: _wordFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _wordSlide.value),
                        child: const Text(
                          'ClipCart',
                          style: TextStyle(fontFamily: kSans, fontSize: 38, height: 1.0, fontWeight: FontWeight.w700, letterSpacing: -1.0, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // tagline
                  FadeTransition(
                    opacity: _tagFade,
                    child: Column(children: [
                      Text('CLIP · CAPTION · EXPORT',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: kMono, fontSize: 11.5, height: 1.0, fontWeight: FontWeight.w600, letterSpacing: 3.0, color: const Color(0xFFB6A6FF).withValues(alpha: 0.95))),
                      const SizedBox(height: 16),
                      Text(
                        'Licensed movie clips that arrive raw.\nEvery caption, logo and ratio stays yours.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: kSans, fontSize: 14.5, height: 1.55, fontWeight: FontWeight.w400, color: Colors.white.withValues(alpha: 0.66)),
                      ),
                    ]),
                  ),
                  const Spacer(flex: 6),
                  // CTAs
                  AnimatedBuilder(
                    animation: _enter,
                    builder: (_, __) => Opacity(
                      opacity: _ctaFade.value,
                      child: Transform.translate(
                        offset: Offset(0, _ctaSlide.value),
                        child: Column(children: [
                          _GetStartedButton(onTap: () => context.go('/register')),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: Colors.white,
                              overlayColor: Colors.white24,
                            ),
                            child: Text('I already have an account',
                                style: TextStyle(fontFamily: kSans, fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.82))),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary CTA — a white pill with brand-violet label; reads as the one bright
/// action on the violet field.
class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(R.button),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.button),
        onTap: onTap,
        overlayColor: WidgetStateProperty.all(AppColors.brandTint),
        child: Container(
          height: H.primaryBtn,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.button),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Get started',
                style: TextStyle(fontFamily: kSans, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.brand)),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 19, color: AppColors.brand),
          ]),
        ),
      ),
    );
  }
}

/// A few soft drifting glow orbs behind the mark — quiet ambient motion.
class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t);
  final double t;

  static const _orbs = [
    (Offset(0.22, 0.30), 150.0, Color(0xFF8E74FF), 0.0),
    (Offset(0.82, 0.26), 120.0, Color(0xFF6A54D8), 0.4),
    (Offset(0.80, 0.74), 160.0, Color(0xFF5238B0), 0.7),
    (Offset(0.18, 0.80), 130.0, Color(0xFF9D8BFF), 0.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const tau = 2 * math.pi;
    for (final o in _orbs) {
      final (base, radius, color, phase) = o;
      final a = (t + phase) * tau;
      final c = Offset((base.dx + math.sin(a) * 0.04) * size.width, (base.dy + math.cos(a * 0.8) * 0.04) * size.height);
      final alpha = 0.12 + 0.06 * (0.5 + 0.5 * math.sin(a));
      final paint = Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0.0)])
            .createShader(Rect.fromCircle(center: c, radius: radius));
      canvas.drawCircle(c, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
