import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  VideoPlayerController? _bg;

  @override
  void initState() {
    super.initState();
    _initBg();
  }

  Future<void> _initBg() async {
    try {
      final c = VideoPlayerController.asset('assets/video/onboarding_bg.mp4');
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted) setState(() => _bg = c);
    } catch (_) {/* gradient fallback */}
  }

  @override
  void dispose() {
    _bg?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final ready = _bg != null && _bg!.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // fallback gradient (always painted, shows while the clip loads)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF2D6B), Color(0xFFB81D54)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
          ),
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _bg!.value.size.width,
                height: _bg!.value.size.height,
                child: VideoPlayer(_bg!),
              ),
            ),
          // legibility scrim
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x22000000), Color(0x66000000), Color(0xE6000000)],
                stops: [0.0, 0.45, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(9)),
                      alignment: Alignment.center,
                      child: const Text('C', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                    const SizedBox(width: 9),
                    const Text('ClipCart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                  ]),
                  const Spacer(),
                  const Text('BROWSE · CUSTOMIZE · EXPORT', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 11)),
                  const SizedBox(height: 10),
                  const Text('Turn viral clips\ninto your brand', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.04)),
                  const SizedBox(height: 12),
                  const Text('Browse trending meme & movie clips, drop in your text, logo & subtitles, and export in seconds.',
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.35)),
                  const SizedBox(height: 24),
                  PrimaryButton(label: 'Get started', onPressed: () => context.go('/register')),
                  const SizedBox(height: 10),
                  GoogleButton(onPressed: () async {
                    final err = await auth.googleSignIn();
                    if (err != null && err != 'Cancelled' && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('I already have an account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
