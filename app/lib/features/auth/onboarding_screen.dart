import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/runtime_config.dart';
import '../../core/theme.dart';
import '../../core/ui_kit.dart';

/// §01 Splash — full-bleed clip, glass overlay, paper zone. Straight to Auth;
/// there is no onboarding carousel (spec §5).
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
    try {
      final r = await Dio().get('${RuntimeConfig.apiBaseUrl}/showcase');
      final items = (r.data['items'] as List?) ?? [];
      if (items.isEmpty) return;
      final it = items.first as Map;
      if (mounted) setState(() => _thumb = it['thumb'] as String?);
      final c = VideoPlayerController.networkUrl(Uri.parse((it['preview'] ?? it['raw']) as String));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _vc = c);
    } catch (_) {/* image / flat fallback */}
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  Widget _chip(String label, Color dot) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
              decoration: BoxDecoration(color: const Color(0x57221F19), borderRadius: BorderRadius.circular(R.pill)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 9),
                Text(label, style: const TextStyle(fontFamily: kSans, fontSize: 11.5, fontWeight: FontWeight.w500, color: Colors.white)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ready = _vc != null && _vc!.value.isInitialized;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // full-bleed media
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: _vc!.value.size.width, height: _vc!.value.size.height, child: VideoPlayer(_vc!)),
            )
          else if (_thumb != null)
            Image.network(_thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.mediaPlaceholder))
          else
            const ColoredBox(color: AppColors.mediaPlaceholder),
          // vignette
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.56), radius: 1.1,
                colors: [Color(0x00221F19), Color(0x57221F19)], stops: [0.38, 1.0],
              ),
            ),
          ),
          // top scrim
          const Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x73141129), Color(0x00141129)]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // glass logo + eyebrow
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          width: 30, height: 30, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0x29FCFAF6), borderRadius: BorderRadius.circular(9)),
                          child: const Icon(Icons.play_arrow_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text('CLIPCART', style: TextStyle(fontFamily: kMono, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 3, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 118),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    _chip('Your caption, your font', AppColors.brand),
                    _chip('Your logo on every clip', AppColors.goldAccent),
                    _chip('Any ratio, one tap', AppColors.greenDot),
                  ]),
                ),
                const Spacer(),
                // paper zone — solid paper that fades in over the video at its top edge
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Color(0x00FCFAF6), AppColors.bg, AppColors.bg], stops: [0.0, 0.22, 1.0],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(30, 48, 30, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Clip.\nCaption.\nExport.', style: T.display),
                    Container(width: 38, height: 2, margin: const EdgeInsets.fromLTRB(0, 22, 0, 18), decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.pill))),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text('Licensed movie clips that arrive raw. Every element — text, logo, ratio — stays yours to change.',
                          style: T.body.copyWith(fontSize: 15, height: 1.6)),
                    ),
                    const SizedBox(height: 26),
                    PrimaryBtn('Get started', onTap: () => context.go('/register')),
                    const SizedBox(height: 6),
                    GhostBtn('I already have an account', onTap: () => context.go('/login')),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
