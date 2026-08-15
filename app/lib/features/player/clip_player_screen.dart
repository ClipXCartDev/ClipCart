import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/primary_button.dart';

/// Deep-link entry (/clip/:slug): fetch one clip, show it in the reels player.
class ClipPlayerScreen extends StatelessWidget {
  const ClipPlayerScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<Clip>(
        future: context.read<CatalogService>().getClip(slug),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D)));
          }
          if (!snap.hasData) return Center(child: Text('Could not load clip', style: TextStyle(color: Colors.grey.shade400)));
          return ReelsPlayerScreen(clips: [snap.data!], startIndex: 0);
        },
      ),
    );
  }
}

/// Instagram/TikTok-style vertical reels: swipe up/down between clips, each
/// auto-plays a muted looping preview. Tap to pause/play. "Use template" → editor.
class ReelsPlayerScreen extends StatefulWidget {
  const ReelsPlayerScreen({super.key, required this.clips, required this.startIndex});
  final List<Clip> clips;
  final int startIndex;

  @override
  State<ReelsPlayerScreen> createState() => _ReelsPlayerScreenState();
}

class _ReelsPlayerScreenState extends State<ReelsPlayerScreen> {
  late final PageController _pc;
  late int _current;
  final Map<int, VideoPlayerController> _ctrls = {};
  final Map<int, bool> _loading = {};

  @override
  void initState() {
    super.initState();
    _current = widget.startIndex;
    _pc = PageController(initialPage: _current);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _pc.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    // ensure current ±1 exist, play current, dispose far ones
    for (final i in [_current, _current - 1, _current + 1]) {
      if (i >= 0 && i < widget.clips.length) await _ensure(i);
    }
    _ctrls.forEach((i, c) {
      if (i == _current) {
        c.play();
      } else {
        c.pause();
      }
    });
    // drop controllers outside the window
    final keep = {_current, _current - 1, _current + 1};
    final drop = _ctrls.keys.where((i) => !keep.contains(i)).toList();
    for (final i in drop) {
      _ctrls.remove(i)?.dispose();
      _loading.remove(i);
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensure(int i) async {
    if (_ctrls.containsKey(i) || _loading[i] == true) return;
    _loading[i] = true;
    try {
      final url = await context.read<CatalogService>().previewUrl(widget.clips[i].id);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) {
        c.dispose();
        return;
      }
      _ctrls[i] = c;
      if (i == _current) c.play();
      setState(() {});
    } catch (_) {
      // leave gradient/thumb fallback
    } finally {
      _loading[i] = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _pc,
          scrollDirection: Axis.vertical,
          itemCount: widget.clips.length,
          onPageChanged: (i) {
            _current = i;
            _sync();
          },
          itemBuilder: (context, i) => _page(widget.clips[i], i),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30), onPressed: () => context.pop()),
          ),
        ),
      ]),
    );
  }

  Widget _page(Clip clip, int i) {
    final c = _ctrls[i];
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      onTap: () {
        if (c == null) return;
        setState(() => c.value.isPlaying ? c.pause() : c.play());
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // background: video, else thumbnail poster, else gradient
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            )
          else if (clip.thumb != null)
            Image.network(clip.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _grad())
          else
            _grad(),
          if (!ready) const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D))),
          if (ready && !c.value.isPlaying)
            IgnorePointer(child: Center(child: Icon(Icons.play_arrow_rounded, size: 72, color: Colors.white.withOpacity(0.85)))),
          // bottom gradient scrim + meta
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.85)], begin: Alignment.center, end: Alignment.bottomCenter),
                ),
              ),
            ),
          ),
          Positioned(left: 16, right: 16, bottom: 24, child: _meta(clip)),
          const Positioned(right: 12, top: 60, child: Icon(Icons.volume_off_rounded, color: Colors.white70, size: 20)),
        ],
      ),
    );
  }

  Widget _grad() => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A2740), Color(0xFFC0304A)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      );

  Widget _meta(Clip clip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text('@${clip.editorName ?? 'creator'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(width: 8),
          if (clip.isPro)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFF5A623), borderRadius: BorderRadius.circular(6)), child: const Text('PRO', style: TextStyle(color: Color(0xFF3A2600), fontSize: 10, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 6),
        Text(clip.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final t in [clip.category ?? clip.genre ?? 'clip', clip.language, clip.durationLabel])
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)), child: Text('#$t', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 14),
        PrimaryButton(label: 'Use template', icon: Icons.auto_awesome, onPressed: () => context.push('/editor', extra: clip)),
      ],
    );
  }
}
