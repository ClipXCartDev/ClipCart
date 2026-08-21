import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../models/clip.dart';
import '../../services/billing_service.dart';
import '../../services/catalog_service.dart';

/// Deep-link entry (/clip/:slug): fetch one clip, show it in the player.
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
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
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
                    TextButton(onPressed: () => context.go('/home'), child: const Text('Go home', style: TextStyle(color: AppColors.brand))),
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

/// §06 Video — a full-bleed clip player: swipe up/down between clips, each
/// auto-plays a looping preview. Tap to pause/play. Editing a clip spends one
/// credit (§11 credit-confirm sheet) before opening the editor.
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
  Map<String, dynamic>? _sub; // active subscription (drives editable / credit count) or null

  // ── plan / credit state ────────────────────────────────────────────────────
  bool get _editable => (_sub?['status']?.toString())?.toLowerCase() == 'active';

  int get _creditsLeft {
    final v = _sub?['edit_credits'] ?? _sub?['credits_left'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return n;
    }
    return 17; // spec placeholder when the server sends no quota
  }

  Future<void> _loadSub() async {
    try {
      final s = await context.read<BillingService>().subscription();
      if (mounted) setState(() => _sub = s);
    } catch (_) {
      // leave _sub null → "Preview only" / Unlock affordance
    }
  }

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
    // clamp the start index so a bad/out-of-range index never crashes the build.
    _current = widget.clips.isEmpty ? 0 : widget.startIndex.clamp(0, widget.clips.length - 1);
    _pc = PageController(initialPage: _current);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    _loadSub();
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
    // Play the CURRENT clip first — don't make its playback wait on the
    // neighbour prefetch network calls (that caused a 1-2s freeze on swipe).
    await _ensure(_current);
    final cur = _ctrls[_current];
    if (cur != null) {
      cur.setVolume(_muted ? 0 : 1); // only the current clip is audible
      cur.play();
    }
    if (mounted) setState(() {}); // refresh chrome (heart / Edit bar) immediately
    // Then pre-buffer the neighbours (±1), kept muted+paused.
    for (final i in [_current - 1, _current + 1]) {
      if (i >= 0 && i < widget.clips.length) await _ensure(i);
    }
    _ctrls.forEach((i, c) {
      if (i != _current) {
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
    if (mounted) {
      _sync();
      _loadSub(); // refresh the credit count after an edit session
    }
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
    if (widget.clips.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: TextButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
            child: const Text('Could not load clip', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }
    final clip = widget.clips[_current.clamp(0, widget.clips.length - 1)];
    final saved = _faved.contains(clip.id);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(children: [
        PageView.builder(
          controller: _pc,
          scrollDirection: Axis.vertical,
          itemCount: widget.clips.length,
          onPageChanged: (i) {
            setState(() => _current = i); // refresh chrome for the new page at once
            _sync();
          },
          itemBuilder: (context, i) => _page(widget.clips[i], i),
        ),
        // ── top scrim: status-bar legibility (media scrim — the only allowed gradient) ──
        const Positioned(
          top: 0, left: 0, right: 0,
          child: IgnorePointer(
            child: SizedBox(
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73141129), Color(0x00141129)],
                  ),
                ),
              ),
            ),
          ),
        ),
        // ── top row (h48): glass back · glass mute · glass heart ──
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 48,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                CircleIconBtn(
                  Icons.arrow_back_rounded,
                  size: H.mediaIconBtn,
                  glass: true,
                  onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                ),
                Row(children: [
                  CircleIconBtn(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: H.mediaIconBtn,
                    glass: true,
                    onTap: _toggleMute,
                  ),
                  const SizedBox(width: 8),
                  CircleIconBtn(
                    saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: H.mediaIconBtn,
                    glass: true,
                    iconColor: saved ? AppColors.brand : Colors.white,
                    onTap: () => _toggleFav(clip),
                  ),
                ]),
              ]),
            ),
          ),
        ),
          ]),
        ),
        // ── bottom bar on paper: status block + single Edit/Unlock button ──
        _bottomBar(clip),
      ]),
    );
  }

  // The clip fills the whole screen; the caption + scrubber ride on the video
  // just above the paper bottom bar.
  Widget _page(Clip clip, int i) {
    final c = _ctrls[i];
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      onTap: () {
        if (c == null) return;
        setState(() { c.value.isPlaying ? c.pause() : c.play(); });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // blurred fill behind — fills the screen with no black bars
          if (clip.thumb != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: CachedNetworkImage(imageUrl: clip.thumb!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _fill()),
            )
          else
            _fill(),
          // the actual video/thumbnail — CONTAIN so the WHOLE frame is visible (no crop)
          if (ready)
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            )
          else if (clip.thumb != null)
            CachedNetworkImage(imageUrl: clip.thumb!, fit: BoxFit.contain, errorWidget: (_, __, ___) => const SizedBox.shrink())
          else
            const Center(child: CircularProgressIndicator(color: AppColors.brand)),
          // subtle bottom fade for caption/scrubber legibility (allowed media scrim)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00141129), Color(0x8C141129)],
                  ),
                ),
              ),
            ),
          ),
          // centred 60px play/pause button
          if (ready)
            Center(
              child: GestureDetector(
                onTap: () => setState(() { c.value.isPlaying ? c.pause() : c.play(); }),
                child: Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(color: Color(0xF0FCFAF6), shape: BoxShape.circle),
                  child: Icon(c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32, color: AppColors.ink),
                ),
              ),
            ),
          // caption + scrubber, directly on the video near the bottom
          Positioned(
            left: 20, right: 20, bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  clip.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kSans, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w600, color: Colors.white,
                    shadows: [Shadow(color: Color(0x80000000), blurRadius: 4, offset: Offset(0, 1))],
                  ),
                ),
                const SizedBox(height: 12),
                if (ready) _scrubber(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3px track (white .35) + white fill + 11px knob + mono timecode. Real seek.
  Widget _scrubber(VideoPlayerController c) {
    void seekTo(double frac, int durMs) {
      c.seekTo(Duration(milliseconds: (frac.clamp(0.0, 1.0) * durMs).round()));
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, v, _) {
        final durMs = v.duration.inMilliseconds;
        final posMs = durMs == 0 ? 0 : v.position.inMilliseconds.clamp(0, durMs);
        final frac = durMs == 0 ? 0.0 : posMs / durMs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => seekTo(d.localPosition.dx / w, durMs),
                  onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx / w, durMs),
                  child: SizedBox(
                    height: 16, // touch target around the 3px track
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                        ),
                        Container(
                          height: 3,
                          width: (w * frac).clamp(0.0, w),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                        ),
                        Positioned(
                          left: (w * frac - 5.5).clamp(0.0, w - 11),
                          child: Container(
                            width: 11, height: 11,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmt(v.position)} / ${_fmt(v.duration)}',
              style: const TextStyle(fontFamily: kMono, fontSize: 10.5, color: Colors.white),
            ),
          ],
        );
      },
    );
  }

  Widget _bottomBar(Clip clip) {
    final editable = _editable;
    final title = editable ? 'Ready to edit' : 'Preview only';
    final sub = editable ? 'Opening the editor uses 1 credit' : 'Subscribe to edit and export';
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          // Explicit widths via LayoutBuilder — the surrounding Column ([Expanded
          // video, bar]) can trigger intrinsic sizing of a Row+Expanded, which
          // measured the text at 1-char width (it rendered vertically). Sizing the
          // text column explicitly sidesteps that entirely.
          child: LayoutBuilder(builder: (context, cons) {
            const btnW = 104.0, gap = 16.0;
            final textW = cons.maxWidth.isFinite ? (cons.maxWidth - btnW - gap).clamp(0.0, double.infinity) : 180.0;
            return Row(mainAxisSize: MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(
                width: textW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kSans, fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w400, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: btnW, height: 50,
                child: FilledButton(
                  onPressed: editable ? () => _showCreditSheet(clip) : () => context.push('/plans'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                  ),
                  child: Text(editable ? 'Edit' : 'Unlock', style: const TextStyle(fontFamily: kSans, fontSize: 15.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  // ── §11 credit confirm ──────────────────────────────────────────────────────
  void _showCreditSheet(Clip clip) {
    final left = _creditsLeft;
    final after = left > 0 ? left - 1 : left;
    showAppSheet(context, (ctx) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.toll_outlined, size: 22, color: AppColors.brand),
          ),
          const SizedBox(height: 16),
          const Text(
            'Opening the editor uses 1 credit',
            style: TextStyle(fontFamily: kSans, fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          const Text(
            'The credit is charged once for this clip. You can keep editing it as long as you like — but once you export, this clip is final and cannot be re-edited.',
            style: TextStyle(fontFamily: kSans, fontSize: 13.5, height: 1.55, fontWeight: FontWeight.w400, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: AppColors.brandTint,
              borderRadius: BorderRadius.circular(R.thumb),
            ),
            child: Column(children: [
              _creditRow('Credits left now', '$left', AppColors.ink),
              const Divider(height: 1, thickness: 1, color: AppColors.brandBorder, indent: 16, endIndent: 16),
              _creditRow('After opening', '$after', AppColors.brand),
            ]),
          ),
          const SizedBox(height: 20),
          PrimaryBtn('Use 1 credit and edit', onTap: () {
            Navigator.of(ctx).pop();
            _openEditor(clip);
          }),
          const SizedBox(height: 4),
          GhostBtn('Not now', onTap: () => Navigator.of(ctx).pop()),
        ],
      );
    });
  }

  Widget _creditRow(String label, String value, Color valueColor) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.brandInk))),
          Text(value, style: TextStyle(fontFamily: kMono, fontSize: 14, fontWeight: FontWeight.w600, color: valueColor)),
        ]),
      );

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _fill() => const DecoratedBox(decoration: BoxDecoration(color: AppColors.mediaPlaceholder));
}
