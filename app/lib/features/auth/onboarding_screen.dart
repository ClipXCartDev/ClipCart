import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/runtime_config.dart';

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

  Widget _dot(bool active) => Container(
        width: 26, height: 3,
        decoration: BoxDecoration(color: active ? Colors.white : Colors.white30, borderRadius: BorderRadius.circular(999)),
      );

  @override
  Widget build(BuildContext context) {
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
          // §3.1 onboarding: bottom-anchored content over a full-bleed scrim.
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 3-dot progress (slide 1 active)
                      Row(children: [
                        _dot(true), const SizedBox(width: 6), _dot(false), const SizedBox(width: 6), _dot(false),
                      ]),
                      const SizedBox(height: 14),
                      const Text('Every clip is already edited.',
                          style: TextStyle(color: Colors.white, fontSize: 38, height: 1.05, letterSpacing: -1.1, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 14),
                      const Text(
                        'You only change the words, your handle and your logo. The cut, the timing and the look stay as the creator built them.',
                        style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.go('/login'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF191B1F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                          child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: GestureDetector(
                          onTap: () => context.go('/login'),
                          child: const Text('Skip', style: TextStyle(color: Colors.white60, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
