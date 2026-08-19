import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/runtime_config.dart';
import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  VideoPlayerController? _vc;
  String? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Public showcase (no auth) — a live featured clip streamed from Cloudflare.
    try {
      final r = await Dio().get('${RuntimeConfig.apiBaseUrl}/showcase');
      final items = (r.data['items'] as List?) ?? [];
      if (items.isEmpty) return;
      final it = items.first as Map;
      if (mounted) setState(() => _thumb = it['thumb'] as String?);
      final c = VideoPlayerController.networkUrl(Uri.parse((it['preview'] ?? it['raw']) as String)); // 720p preview (raw removed from public showcase)
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose(); // unmounted mid-init (auth redirect) — don't leak
        return;
      }
      setState(() => _vc = c);
    } catch (_) {/* gradient fallback */}
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final ready = _vc != null && _vc!.value.isInitialized;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A0C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ambient blurred backdrop for a full-bleed live feel
          if (ready)
            Opacity(
              opacity: 0.5,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: _vc!.value.size.width, height: _vc!.value.size.height, child: VideoPlayer(_vc!)),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xCC0B0A0C), Color(0x660B0A0C), Color(0xF20B0A0C)],
                stops: [0.0, 0.4, 0.92],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7E57DE), Color(0xFF6D45C9)]), borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: const Text('C', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
                    ),
                    const SizedBox(width: 10),
                    const Text('ClipCart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
                  ]),
                  const SizedBox(height: 18),
                  // crisp native-aspect hero card of the live clip
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: ready ? _vc!.value.aspectRatio : 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_thumb != null) Image.network(_thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF161318))),
                              if (ready) VideoPlayer(_vc!),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [Colors.transparent, Color(0x55000000)], begin: Alignment.center, end: Alignment.bottomCenter),
                                ),
                              ),
                              Positioned(
                                left: 12, bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(20)),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.bolt_rounded, color: Color(0xFFFFC400), size: 15),
                                    SizedBox(width: 4),
                                    Text('Trending now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('BROWSE · CUSTOMIZE · EXPORT', style: TextStyle(color: Color(0xFF846EEA), fontWeight: FontWeight.w800, letterSpacing: 2.5, fontSize: 11)),
                  const SizedBox(height: 8),
                  const Text('Turn viral clips\ninto your brand', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.05)),
                  const SizedBox(height: 10),
                  const Text('Browse trending meme & movie clips, drop in your text, logo & subtitles, and export in seconds.',
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.35)),
                  const SizedBox(height: 20),
                  PrimaryButton(label: 'Get started', onPressed: () => context.go('/register')),
                  const SizedBox(height: 10),
                  GoogleButton(onPressed: () async {
                    final err = await auth.googleSignIn();
                    if (err != null && err != 'Cancelled' && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }),
                  const SizedBox(height: 12),
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
