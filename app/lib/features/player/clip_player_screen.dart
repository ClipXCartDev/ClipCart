import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6D45C9)));
          }
          if (snap.hasError || !snap.hasData) {
            return SafeArea(
              child: Stack(children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                  ),
                ),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Could not load clip', style: TextStyle(color: Colors.grey.shade400)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: () => context.go('/home'), child: const Text('Go home', style: TextStyle(color: Color(0xFF6D45C9)))),
                  ]),
                ),
              ]),
            );
          }
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
  final Set<String> _faved = {}; // clip ids saved this session (optimistic)
  bool _muted = true;
  int _gen = 0; // bumps whenever we tear controllers down; stale async _ensure bail on mismatch

  Future<void> _toggleFav(Clip clip) async {
    final id = clip.id;
    final wasFav = _faved.contains(id);
    HapticFeedback.selectionClick();
    setState(() => wasFav ? _faved.remove(id) : _faved.add(id));
    try {
      final cs = context.read<CatalogService>();
      wasFav ? await cs.unfavorite(id) : await cs.favorite(id);
    } catch (_) {
      if (mounted) setState(() => wasFav ? _faved.add(id) : _faved.remove(id)); // revert
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    // Only the current clip carries audio; neighbours stay muted regardless.
    _ctrls.forEach((i, c) => c.setVolume((i == _current && !_muted) ? 1 : 0));
  }

  @override
  void initState() {
    super.initState();
    _current = widget.startIndex;
    _pc = PageController(initialPage: _current);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // seed the heart state from the server so an already-saved clip shows filled
    // (prevents a silent unsave when the user taps a heart that was wrongly empty).
    context.read<CatalogService>().favoriteIds().then((ids) {
      if (mounted && ids.isNotEmpty) setState(() => _faved.addAll(ids));
    });
  }

  @override
  void dispose() {
    _gen++; // invalidate any in-flight _ensure
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _pc.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    // Mute + pause + rewind every non-current controller IMMEDIATELY so a
    // pre-buffered neighbour never bleeds audio for a frame after a swipe
    // (client-reported: "pehli video ka audio 1-2 sec play hota rehta hai").
    _ctrls.forEach((i, c) {
      if (i != _current) {
        c.setVolume(0);
        c.pause();
        c.seekTo(Duration.zero);
      }
    });
    // ensure current ±1 exist, play current, dispose far ones
    for (final i in [_current, _current - 1, _current + 1]) {
      if (i >= 0 && i < widget.clips.length) await _ensure(i);
    }
    _ctrls.forEach((i, c) {
      if (i == _current) {
        c.setVolume(_muted ? 0 : 1); // only the current clip is audible
        c.play();
      } else {
        c.setVolume(0);
        c.pause();
      }
    });
    // drop controllers outside the window. Remove from the map + rebuild FIRST so
    // no VideoPlayer widget is still pointing at a controller we're about to dispose,
    // THEN dispose after the frame (prevents "used after dispose" on fast swipes).
    final keep = {_current, _current - 1, _current + 1};
    final drop = _ctrls.keys.where((i) => !keep.contains(i)).toList();
    final dropped = <VideoPlayerController>[];
    for (final i in drop) {
      final c = _ctrls.remove(i);
      if (c != null) dropped.add(c);
      _loading.remove(i);
    }
    if (mounted) setState(() {});
    if (dropped.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in dropped) {
          c.dispose();
        }
      });
    }
  }

  /// Free ALL reels video decoders before opening the editor — otherwise the
  /// editor's decoder + the reels current±1 decoders exhaust MediaCodec (SIGABRT
  /// "could not create MediaCodec.BufferInfo" on larger clips). Re-init on return.
  Future<void> _openEditor(Clip clip) async {
    _gen++; // invalidate any in-flight _ensure so it can't re-insert a decoder while the editor is open
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _loading.clear();
    if (mounted) setState(() {});
    await context.push('/editor', extra: clip);
    if (mounted) _sync();
  }

  Future<void> _ensure(int i) async {
    if (_ctrls.containsKey(i) || _loading[i] == true) return;
    final gen = _gen; // snapshot: if controllers get torn down mid-init, abandon this one
    _loading[i] = true;
    try {
      final url = await context.read<CatalogService>().previewUrl(widget.clips[i].id);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      // Only the current clip is audible; pre-buffered neighbours stay muted so
      // they can't bleed sound before the user swipes to them.
      await c.setVolume((i == _current && !_muted) ? 1 : 0);
      if (!mounted || gen != _gen) {
        c.dispose(); // screen gone OR a teardown (editor/dispose) happened while we loaded
        return;
      }
      _ctrls[i] = c;
      if (i == _current) {
        c.play();
      } else {
        c.pause();
      }
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
        // §3.2 top bar: close · PREVIEW · WATERMARKED · more
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _circleBtn(Icons.close_rounded, () => context.canPop() ? context.pop() : context.go('/home')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white.withOpacity(0.35))),
                child: Text('PREVIEW · WATERMARKED', style: TextStyle(fontFamily: 'IBMPlexMono', fontSize: 10, color: Colors.white.withOpacity(0.8))),
              ),
              _circleBtn(Icons.more_horiz_rounded, () {}),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

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
          // blurred fill behind — fills the screen with no visible crop of the real video
          if (clip.thumb != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: CachedNetworkImage(imageUrl: clip.thumb!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _grad()),
            )
          else
            _grad(),
          // the actual video/thumbnail — CONTAIN so the WHOLE frame is visible (no crop)
          if (ready)
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            )
          else if (clip.thumb != null)
            CachedNetworkImage(imageUrl: clip.thumb!, fit: BoxFit.contain, errorWidget: (_, __, ___) => const SizedBox.shrink()),
          // only show a spinner when there's no thumbnail to communicate content
          if (!ready && clip.thumb == null) const Center(child: CircularProgressIndicator(color: Color(0xFF6D45C9))),
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
          // right action rail (Save · Share · Sound), above the meta block
          Positioned(
            right: 16,
            bottom: 190 + MediaQuery.of(context).viewPadding.bottom,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _railBtn(
                _faved.contains(clip.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                'Save',
                () => _toggleFav(clip),
                color: _faved.contains(clip.id) ? const Color(0xFF6D45C9) : Colors.white,
              ),
              const SizedBox(height: 14),
              _railBtn(Icons.ios_share_rounded, 'Share', () => _sharePreview(clip)),
              const SizedBox(height: 14),
              _railBtn(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, 'Sound', _toggleMute),
            ]),
          ),
          // meta + CTA sit above the system nav bar (viewPadding.bottom)
          Positioned(left: 18, right: 18, bottom: 22 + MediaQuery.of(context).viewPadding.bottom, child: _meta(clip)),
        ],
      ),
    );
  }

  Widget _railBtn(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      );

  Future<void> _sharePreview(Clip clip) async {
    try {
      await Share.share('Check out "${clip.title}" on ClipCart');
    } catch (_) {}
  }

  Widget _grad() => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A2740), Color(0xFFC0304A)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      );

  Widget _meta(Clip clip) {
    // meta line: CATEGORY · DURATION · RATIO · @handle (mono, §3.2)
    final cat = (clip.category ?? clip.genre ?? 'clip').toUpperCase();
    final metaLine = '$cat · ${clip.durationLabel} · 9:16 · @${clip.editorName ?? 'creator'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(metaLine, style: TextStyle(fontFamily: 'IBMPlexMono', fontSize: 11, color: Colors.white.withOpacity(0.75))),
        const SizedBox(height: 7),
        Text(clip.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.1)),
        const SizedBox(height: 7),
        Text('Preview quality · full HD unlocks in the editor.', style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 14, height: 1.45)),
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _openEditor(clip),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6D45C9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
            child: const Text('Use this template', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
