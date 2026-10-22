import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';

/// The screen someone looks at while their video renders.
///
/// A render takes tens of seconds on a phone, and for that whole time this is
/// the app. A spinner in a dialog says only "something is happening"; this says
/// which clip, how far along, roughly how much longer, and that leaving will
/// cost the render — then gets out of the way.
///
/// Everything on it is measured. The bar is real frame counts from the encoder,
/// and the time remaining only appears once enough of the render has happened
/// for the estimate to mean anything. Nothing here invents reassurance.
class ExportProgressScreen extends StatefulWidget {
  const ExportProgressScreen({
    super.key,
    required this.progress,
    required this.phase,
    required this.title,
    this.posterUrl,
    this.onCancel,
  });

  /// 0..1, driven by the encoder's own frame statistics.
  final ValueListenable<double> progress;

  /// Preparing / Rendering / Saving — the stage, in the user's words.
  final ValueListenable<String> phase;

  final String title;

  /// A frame of the clip, so the screen is about their video and not about us.
  final String? posterUrl;

  /// Null while cancelling is not safe; otherwise called after the user
  /// confirms. The screen does not pop itself — the export flow owns that.
  final Future<void> Function()? onCancel;

  @override
  State<ExportProgressScreen> createState() => _ExportProgressScreenState();
}

class _ExportProgressScreenState extends State<ExportProgressScreen> {
  /// When the bar first moved, and from where — the two numbers an estimate
  /// needs. Taken at first real progress rather than at open, so the time spent
  /// fetching the original does not drag the estimate out.
  DateTime? _startedAt;
  double _startedFrom = 0;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    final v = widget.progress.value;
    if (_startedAt == null && v > 0.01) {
      _startedAt = DateTime.now();
      _startedFrom = v;
    }
  }

  /// Seconds left, or null when we cannot say honestly yet.
  ///
  /// Needs both a few seconds of history and some distance covered: estimating
  /// from the first flicker of the bar produces a number that swings wildly and
  /// is worse than no number at all.
  int? _secondsLeft() {
    final v = widget.progress.value;
    final t0 = _startedAt;
    if (t0 == null || v <= _startedFrom + 0.02) return null;
    final elapsed = DateTime.now().difference(t0).inMilliseconds / 1000.0;
    if (elapsed < 2) return null;
    final rate = (v - _startedFrom) / elapsed; // progress per second
    if (rate <= 0) return null;
    final left = (1.0 - v) / rate;
    if (left.isNaN || left.isInfinite || left > 3600) return null;
    return left.round();
  }

  String _etaLabel(int s) {
    if (s < 10) return 'Almost done';
    if (s < 60) return 'About ${(s / 5).round() * 5} seconds left';
    final m = (s / 60).ceil();
    return m == 1 ? 'About a minute left' : 'About $m minutes left';
  }

  Future<void> _confirmCancel() async {
    final cancel = widget.onCancel;
    if (cancel == null || _cancelling) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Stop the export?', style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w600)),
        content: const Text(
          'Your edit is saved and you can export again whenever you like. This export will be discarded.',
          style: TextStyle(color: AppColors.inkMuted, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop', style: TextStyle(color: AppColors.errText, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _cancelling = true);
    await cancel();
  }

  @override
  Widget build(BuildContext context) {
    // Back must not leave: the render is tied to this screen, and a stray
    // swipe part-way through a minute of work is the worst thing that could
    // happen here. Stopping is deliberate, through the button.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(children: [
              const Spacer(flex: 2),
              _poster(),
              const SizedBox(height: 28),
              ValueListenableBuilder<double>(
                valueListenable: widget.progress,
                builder: (_, v, __) {
                  final pct = (v * 100).clamp(0, 99).round();
                  final eta = _secondsLeft();
                  return Column(children: [
                    ValueListenableBuilder<String>(
                      valueListenable: widget.phase,
                      builder: (_, p, __) => Text(
                        _cancelling ? 'Stopping…' : p,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: kSans, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$pct',
                            style: const TextStyle(fontFamily: kMono, fontSize: 46, height: 1.0, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        const Text('%',
                            style: TextStyle(fontFamily: kMono, fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(R.pill),
                      child: LinearProgressIndicator(
                        // indeterminate until the encoder reports a frame, rather
                        // than a bar sitting at zero pretending to be stuck
                        value: v <= 0 ? null : v,
                        minHeight: 6,
                        backgroundColor: AppColors.line,
                        valueColor: const AlwaysStoppedAnimation(AppColors.brand),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 18,
                      child: Text(
                        eta == null ? '' : _etaLabel(eta),
                        style: const TextStyle(fontFamily: kSans, fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ),
                  ]);
                },
              ),
              const Spacer(flex: 3),
              const Text(
                'Please don’t close this screen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: kSans, fontSize: 12.5, height: 1.5, color: AppColors.inkFaint),
              ),
              const SizedBox(height: 14),
              if (widget.onCancel != null)
                TextButton(
                  onPressed: _cancelling ? null : _confirmCancel,
                  child: Text(_cancelling ? 'Stopping…' : 'Stop',
                      style: TextStyle(
                          fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600,
                          color: _cancelling ? AppColors.inkFaint : AppColors.inkMuted)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// The clip itself, so the wait is visibly about their video. Falls back to a
  /// plain tile rather than an empty hole when no frame is available.
  Widget _poster() {
    final url = widget.posterUrl;
    // An empty rectangle reads as something that failed to load, so the
    // fallback is a deliberate tile rather than a hole.
    const blank = ColoredBox(
      color: AppColors.mediaPlaceholder,
      child: Center(child: Icon(Icons.movie_outlined, size: 30, color: AppColors.inkFaint)),
    );
    final Widget inner = url == null || url.isEmpty
        ? blank
        : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => blank);
    return Column(children: [
      SizedBox(
        width: 132, height: 188,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.media),
          child: Stack(fit: StackFit.expand, children: [
            inner,
            // a soft scrim keeps the white type above it legible on any frame
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x66000000)],
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Text(widget.title,
          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkMuted)),
    ]);
  }
}
