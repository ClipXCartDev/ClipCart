import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'filmstrip.dart';
import 'timeline_geometry.dart';

/// One track's worth of timeline: a kind of layer, or a single layer.
@immutable
class TimelineItem {
  const TimelineItem({
    required this.ref,
    required this.label,
    required this.start,
    required this.end,
    required this.icon,
    required this.colour,
    this.locked = false,
    this.hidden = false,
    this.movable = true,
    this.resizable = true,
  });

  /// Whatever the editor uses to identify this thing. Passed back untouched.
  final Object ref;
  final String label;
  final double start;
  final double end;
  final IconData icon;
  final Color colour;
  final bool locked;
  final bool hidden;
  final bool movable;
  final bool resizable;
}

/// A collapsed group of layers of one kind, or one expanded kind's header.
@immutable
class TimelineGroup {
  const TimelineGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.colour,
    required this.items,
    required this.open,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color colour;
  final List<TimelineItem> items;
  final bool open;
}

/// The editor's timeline.
///
/// The old one fitted the whole clip into the screen's width — about seven
/// pixels per second on a 47-second clip — drew the video as ten identical film
/// icons, and gave every layer a 22-pixel sliver. Nothing could be placed
/// accurately and nothing looked like the footage, which is why it read as a
/// placeholder next to a real editor.
///
/// This one is as wide as the clip needs at the current zoom and scrolls, shows
/// the actual frames, gives each layer a track you can read and grab, snaps
/// edges to the playhead and to other layers, and says so with a guide line and
/// a tick of haptic feedback.
class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.duration,
    required this.position,
    required this.groups,
    required this.filmstrip,
    required this.onSeek,
    required this.onToggleGroup,
    required this.onSelect,
    this.trimStart = 0,
    this.trimEnd,
    this.selected,
    this.onMove,
    this.onResize,
    this.onEditStart,
    this.isPlaying = false,
    this.trimMode = false,
    this.onTrim,
    this.compact = false,
  });

  final double duration;

  /// Playback position in seconds. The panel repaints on this alone, so the
  /// playhead can follow without rebuilding the whole editor.
  final ValueListenable<double> position;

  final List<TimelineGroup> groups;
  final Filmstrip filmstrip;
  final double trimStart;
  final double? trimEnd;
  final Object? selected;
  final bool isPlaying;

  final void Function(double seconds) onSeek;
  final void Function(String groupId) onToggleGroup;
  final void Function(Object? ref) onSelect;

  /// Move a layer so it starts at the given second. Null means moving is off.
  final void Function(Object ref, double start)? onMove;

  /// Resize a layer to the given window.
  final void Function(Object ref, double start, double end)? onResize;

  /// Fired once when a move or resize begins, so the editor can take an undo
  /// snapshot before the value starts changing — one per gesture, not one per
  /// frame of it.
  final VoidCallback? onEditStart;

  /// While true the video track shows trim handles and takes the drag, so a
  /// trim is never fighting a seek for the same gesture.
  final bool trimMode;

  /// A trim handle moved: true for the in point, false for the out point.
  final void Function(bool isStart, double seconds)? onTrim;

  /// Give the picture back its room. Set while a layer's property panel is
  /// open: the timeline keeps every track, but shows fewer at once and
  /// scrolls, instead of squeezing the video into a tenth of the screen.
  final bool compact;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  static const double _rulerH = 20;
  static const double _videoH = 46;
  static const double _rowH = 32;
  static const double _headH = 18;
  static const double _gap = 6;

  /// A small lead-in so the very start of the clip is still grabbable, and the
  /// same at the end. Not half a screen: that belongs to a fixed centre
  /// playhead, and this one moves with the time.
  static const double _pad = 10;

  final _scroll = ScrollController();
  TimelineScale _scale = TimelineScale();
  bool _fitted = false;

  /// Set while a pinch is in progress so the horizontal scroller lets go.
  bool _zooming = false;
  double _zoomStart = 1;

  /// The time a drag is currently snapped to, for the guide line.
  double? _snapGuide;
  bool _snapBuzzed = false;

  /// Which trim handle the finger took at the start of the drag: 0 none,
  /// 1 the in point, 2 the out point.
  int _trimGrab = 0;
  double _trimGrabX = 0;
  double _trimGrabVal = 0;

  /// Where the finger has actually dragged to, before snapping. Snapping is a
  /// display and commit step; if it fed back into the next frame's starting
  /// point the gesture would stall on the first landmark it touched.
  double? _rawDrag;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _end => widget.trimEnd ?? widget.duration;

  /// Everything a dragged edge is allowed to stick to: the playhead, the clip's
  /// ends, the trim points, and every other layer's edges.
  List<double> _landmarks(Object? exclude) => [
        0,
        widget.duration,
        widget.trimStart,
        _end,
        widget.position.value,
        for (final g in widget.groups)
          for (final it in g.items)
            if (!identical(it.ref, exclude)) ...[it.start, it.end],
      ];

  void _buzz(bool snapped) {
    if (snapped && !_snapBuzzed) {
      HapticFeedback.selectionClick();
      _snapBuzzed = true;
    } else if (!snapped) {
      _snapBuzzed = false;
    }
  }

  double _contentW() => _scale.contentWidth(widget.duration) + _pad * 2;

  /// Keep the playhead on screen while it is moving under playback.
  void _followPlayhead() {
    if (!widget.isPlaying || !_scroll.hasClients) return;
    final x = _pad + _scale.xOf(widget.position.value);
    final view = _scroll.position.viewportDimension;
    final left = _scroll.offset, right = left + view;
    if (x < left + 40 || x > right - 40) {
      final target = (x - view / 2).clamp(0.0, math.max(0.0, _contentW() - view)).toDouble();
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rowsHeight();
    final h = (_rulerH + _gap + _videoH + _gap + rows + 16)
        .clamp(110.0, widget.compact ? 215.0 : 300.0)
        .toDouble();
    return Container(
      color: AppColors.surfaceHover,
      height: h,
      child: Column(children: [
        _zoomBar(),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            // Start showing the whole clip; after that the zoom is the user's.
            if (!_fitted && widget.duration > 0 && c.maxWidth > 0) {
              _scale = TimelineScale.fit(widget.duration, c.maxWidth - _pad * 2);
              _fitted = true;
            }
            return GestureDetector(
              // Two fingers zoom; one finger is left to the scroller and to the
              // blocks, which is why the pointer count is checked rather than
              // taking every scale gesture.
              onScaleStart: (d) {
                if (d.pointerCount >= 2) {
                  setState(() {
                    _zooming = true;
                    _zoomStart = _scale.zoom;
                  });
                }
              },
              onScaleUpdate: (d) {
                if (!_zooming || d.pointerCount < 2) return;
                setState(() => _scale = TimelineScale(_zoomStart * d.horizontalScale));
              },
              onScaleEnd: (_) => setState(() => _zooming = false),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: _zooming
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                child: SizedBox(
                  width: _contentW(),
                  child: _tracks(),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  double _rowsHeight() {
    var r = 0.0;
    for (final g in widget.groups) {
      r += g.open ? _headH + _gap + g.items.length * (_rowH + _gap) : _rowH + _gap;
    }
    return r;
  }

  Widget _zoomBar() => SizedBox(
        height: 26,
        child: Row(children: [
          const Spacer(),
          _zoomBtn(Icons.remove_rounded, () => setState(() => _scale = _scale.scaled(1 / 1.6))),
          _zoomBtn(Icons.add_rounded, () => setState(() => _scale = _scale.scaled(1.6))),
          _zoomBtn(Icons.fit_screen_outlined, () {
            setState(() => _fitted = false); // re-fits on the next layout
          }),
          const SizedBox(width: 8),
        ]),
      );

  Widget _zoomBtn(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Icon(i, size: 16, color: AppColors.inkMuted),
        ),
      );

  Widget _tracks() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.position,
      builder: (context, pos, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _followPlayhead());
        final playX = _pad + _scale.xOf(pos);
        final rows = _rowsHeight();
        final totalH = _rulerH + _gap + _videoH + _gap + rows;
        return SizedBox(
          height: totalH,
          child: Stack(clipBehavior: Clip.none, children: [
            // seeking anywhere that is not a block
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (d) => widget.onSeek(_clampTime(_scale.secondsOf(d.localPosition.dx - _pad))),
                onHorizontalDragUpdate: (d) =>
                    widget.onSeek(_clampTime(_scale.secondsOf(d.localPosition.dx - _pad))),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, height: _rulerH, child: _ruler()),
            Positioned(left: _pad, top: _rulerH + _gap, height: _videoH,
                width: _scale.contentWidth(widget.duration),
                // the strip is a picture, not a control: let the tap reach the
                // seek handler underneath instead of being eaten by the track
                child: IgnorePointer(child: _videoTrack())),
            ..._layerRows(_rulerH + _gap + _videoH + _gap),
            if (widget.trimMode && widget.onTrim != null)
              Positioned(
                left: 0, right: 0, top: _rulerH + _gap - 8, height: _videoH + 16,
                child: _trimLayer(),
              ),
            if (_snapGuide != null)
              Positioned(
                left: _pad + _scale.xOf(_snapGuide!) - 0.5, top: 0, height: totalH,
                child: IgnorePointer(child: Container(width: 1, color: AppColors.okIcon)),
              ),
            Positioned(
              left: playX - 1, top: 0, height: totalH,
              child: IgnorePointer(child: Container(width: 2, color: AppColors.ink)),
            ),
            Positioned(
              left: playX - 6, top: -3,
              child: IgnorePointer(
                child: Container(width: 12, height: 12,
                    decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)),
              ),
            ),
          ]),
        );
      },
    );
  }

  /// Handles for the in and out points, over a receiver that spans the track.
  ///
  /// The receiver is deliberately full width and fixed: a handle that moves
  /// under the finger would otherwise drop the gesture the moment it moved.
  Widget _trimLayer() {
    final startX = _pad + _scale.xOf(widget.trimStart);
    final endX = _pad + _scale.xOf(_end);

    Widget bar(double x, bool isStart) => Positioned(
          left: x - 9, top: 0, bottom: 0, width: 18,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: _trimGrab == (isStart ? 1 : 2) ? AppColors.brandPressed : AppColors.brand,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.drag_indicator, size: 15, color: Colors.white),
            ),
          ),
        );

    Widget bubble(double x, double value) => Positioned(
          left: x - 24, top: -24,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(8)),
              child: Text(_fmt(value),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ),
        );

    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) {
            final fx = d.localPosition.dx;
            _trimGrab = (fx - startX).abs() <= (fx - endX).abs() ? 1 : 2;
            _trimGrabX = fx;
            _trimGrabVal = _trimGrab == 1 ? widget.trimStart : _end;
            widget.onEditStart?.call();
            HapticFeedback.selectionClick();
            setState(() {});
          },
          onHorizontalDragUpdate: (d) {
            if (_trimGrab == 0) return;
            final raw = _trimGrabVal + _scale.secondsOf(d.localPosition.dx - _trimGrabX);
            final snapped = _scale.snap(raw, _landmarks(null));
            _buzz(snapped != raw);
            setState(() => _snapGuide = snapped);
            widget.onTrim!(_trimGrab == 1, _clampTime(snapped));
          },
          onHorizontalDragEnd: (_) => setState(() {
            _trimGrab = 0;
            _snapGuide = null;
            _snapBuzzed = false;
          }),
          onHorizontalDragCancel: () => setState(() {
            _trimGrab = 0;
            _snapGuide = null;
          }),
        ),
      ),
      bar(startX, true),
      bar(endX, false),
      if (_trimGrab == 1) bubble(startX, widget.trimStart),
      if (_trimGrab == 2) bubble(endX, _end),
    ]);
  }

  double _clampTime(double s) => s.clamp(0.0, math.max(0.0, widget.duration));

  static String _fmt(double s) {
    final t = s.isFinite && s > 0 ? s : 0.0;
    final m = t ~/ 60, sec = (t % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Widget _ruler() {
    final step = _scale.tickStep();
    final ticks = <Widget>[];
    for (var t = 0.0; t <= widget.duration + 0.001; t += step) {
      ticks.add(Positioned(
        left: _pad + _scale.xOf(t),
        top: 0,
        child: IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 1, height: 5, color: AppColors.line),
            const SizedBox(height: 1),
            Text(_fmt(t),
                style: const TextStyle(fontFamily: kMono, fontSize: 9, height: 1.0, color: AppColors.inkFaint)),
          ]),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: ticks);
  }

  Widget _videoTrack() {
    final strip = widget.filmstrip;
    final w = _scale.contentWidth(widget.duration);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: AppColors.bgAlt),
        if (strip.isReady)
          // Each frame covers the slice of time it was taken from, so what is
          // under the playhead is what is on screen.
          ...List.generate(strip.frames.length, (i) {
            final x = _scale.xOf(i * strip.interval);
            final fw = _scale.xOf(strip.interval);
            if (x > w) return const SizedBox.shrink();
            return Positioned(
              left: x, top: 0, bottom: 0, width: math.min(fw, w - x) + 0.5,
              child: Image.file(strip.frames[i], fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            );
          }),
        // trimmed-away parts, dimmed rather than hidden so the whole clip is
        // still there to drag the trim back out of
        if (widget.trimStart > 0)
          Positioned(left: 0, top: 0, bottom: 0, width: _scale.xOf(widget.trimStart), child: _dim()),
        if (_end < widget.duration)
          Positioned(left: _scale.xOf(_end), top: 0, bottom: 0, right: 0, child: _dim()),
      ]),
    );
  }

  Widget _dim() => const IgnorePointer(child: ColoredBox(color: Color(0xAA0B0A0C)));

  List<Widget> _layerRows(double top) {
    final out = <Widget>[];
    var y = top;
    for (final g in widget.groups) {
      if (!g.open) {
        out.add(_groupRow(g, y));
        y += _rowH + _gap;
        continue;
      }
      out.add(_groupHeader(g, y));
      y += _headH + _gap;
      for (final it in g.items) {
        out.add(_itemRow(it, y));
        y += _rowH + _gap;
      }
    }
    return out;
  }

  /// A collapsed kind: one block spanning everything it holds. Tapping opens it.
  Widget _groupRow(TimelineGroup g, double y) {
    final s = g.items.map((e) => e.start).reduce(math.min);
    final e = g.items.map((x) => x.end).reduce(math.max);
    return Positioned(
      left: _pad + _scale.xOf(s), top: y, height: _rowH,
      width: math.max(26, _scale.xOf(e - s)),
      child: GestureDetector(
        onTap: () => widget.onToggleGroup(g.id),
        child: _block(
          colour: g.colour,
          icon: g.icon,
          label: g.items.length == 1 ? g.label : '${g.label}  ${g.items.length}',
          trailing: const Icon(Icons.expand_more_rounded, size: 14, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _groupHeader(TimelineGroup g, double y) => Positioned(
        left: _pad, top: y, height: _headH, width: 150,
        child: GestureDetector(
          onTap: () => widget.onToggleGroup(g.id),
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Icon(Icons.expand_less_rounded, size: 14, color: g.colour),
            const SizedBox(width: 3),
            Text(g.label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.colour)),
            const SizedBox(width: 5),
            Text('${g.items.length}',
                style: const TextStyle(fontFamily: kMono, fontSize: 10, color: AppColors.inkFaint)),
          ]),
        ),
      );

  Widget _itemRow(TimelineItem it, double y) {
    final selected = widget.selected != null && identical(widget.selected, it.ref);
    final left = _pad + _scale.xOf(it.start);
    final width = math.max(26.0, _scale.xOf(it.end - it.start));
    return Positioned(
      left: left, top: y, height: _rowH, width: width,
      child: GestureDetector(
        onTap: () => widget.onSelect(it.ref),
        onHorizontalDragStart: (it.locked || !it.movable || widget.onMove == null)
            ? null
            : (_) {
                _rawDrag = it.start;
                widget.onEditStart?.call();
              },
        onHorizontalDragUpdate: (it.locked || !it.movable || widget.onMove == null)
            ? null
            : (d) {
                final span = it.end - it.start;
                final raw = (_rawDrag ?? it.start) + _scale.secondsOf(d.delta.dx);
                _rawDrag = raw;

                // either edge may be what lines up, so both are offered and the
                // nearer pull wins
                final marks = _landmarks(it.ref);
                final snappedStart = _scale.snap(raw, marks);
                final snappedEnd = _scale.snap(raw + span, marks);
                double start = raw;
                double? guide;
                if (snappedStart != raw) {
                  start = snappedStart;
                  guide = snappedStart;
                } else if (snappedEnd != raw + span) {
                  start = snappedEnd - span;
                  guide = snappedEnd;
                }
                _buzz(guide != null);
                setState(() => _snapGuide = guide);
                widget.onMove!(it.ref, start.clamp(0.0, math.max(0.0, widget.duration - span)));
              },
        onHorizontalDragEnd: (_) => setState(() {
          _rawDrag = null;
          _snapGuide = null;
          _snapBuzzed = false;
        }),
        child: Stack(clipBehavior: Clip.none, children: [
          Opacity(
            opacity: it.hidden ? 0.35 : 1,
            child: _block(
              colour: it.colour,
              icon: it.locked ? Icons.lock_rounded : it.icon,
              label: it.label,
              selected: selected,
            ),
          ),
          if (selected && it.resizable && !it.locked && widget.onResize != null) ...[
            Positioned(left: -8, top: 0, bottom: 0, child: _grip(it, left: true)),
            Positioned(right: -8, top: 0, bottom: 0, child: _grip(it, left: false)),
          ],
        ]),
      ),
    );
  }

  Widget _grip(TimelineItem it, {required bool left}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _rawDrag = left ? it.start : it.end;
          widget.onEditStart?.call();
        },
        onHorizontalDragUpdate: (d) {
          final raw = (_rawDrag ?? (left ? it.start : it.end)) + _scale.secondsOf(d.delta.dx);
          _rawDrag = raw;
          final snapped = _scale.snap(raw, _landmarks(it.ref));
          _buzz(snapped != raw);
          var start = it.start, end = it.end;
          if (left) {
            start = math.min(it.end - 0.2, snapped);
          } else {
            end = math.max(it.start + 0.2, snapped);
          }
          setState(() => _snapGuide = snapped);
          widget.onResize!(it.ref, start.clamp(0.0, widget.duration), end.clamp(0.0, widget.duration));
        },
        onHorizontalDragEnd: (_) => setState(() {
          _rawDrag = null;
          _snapGuide = null;
          _snapBuzzed = false;
        }),
        child: SizedBox(
          width: 16,
          child: Center(
            child: Container(
              width: 4, height: _rowH - 8,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      );

  Widget _block({
    required Color colour,
    required IconData icon,
    required String label,
    bool selected = false,
    Widget? trailing,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: colour.withValues(alpha: selected ? 1 : 0.82),
          borderRadius: BorderRadius.circular(7),
          border: selected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          if (trailing != null) trailing,
        ]),
      );
}
