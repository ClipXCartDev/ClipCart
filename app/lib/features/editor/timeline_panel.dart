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
  static const double _rowH = 34;
  /// Lanes sit flush, like tracks. A gap between them reads as separate
  /// objects; touching bands read as a stack.
  static const double _gap = 2;

  /// The fixed column of lane tiles down the left. It does not scroll with the
  /// time, which is what makes it a track header rather than a label.
  static const double _gutterW = 46;

  /// A small lead-in so the very start of the clip is still grabbable, and the
  /// same at the end. Not half a screen: that belongs to a fixed centre
  /// playhead, and this one moves with the time.
  static const double _pad = 10;

  /// The zoom row above the tracks. It is part of the panel, so the panel's
  /// height has to include it - left out, it ate the bottom of the last lane,
  /// and the lane that gets selected is usually the last one.
  static const double _zoomH = 26;

  final _scroll = ScrollController();
  TimelineScale _scale = TimelineScale();

  /// The width the current fit was computed for, and whether the user has
  /// since chosen a zoom. A fit taken at the wrong width must not survive;
  /// a zoom the user picked must.
  double _fitWidth = 0;
  bool _userZoomed = false;

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
    final h = (_zoomH + _rulerH + _gap + _videoH + _gap + rows + 12)
        .clamp(136.0, widget.compact ? 241.0 : 326.0)
        .toDouble();
    return Container(
      color: AppColors.surfaceHover,
      height: h,
      child: Column(children: [
        _zoomBar(),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            // Start showing the whole clip; after that the zoom is the user's.
            if (!_userZoomed &&
                widget.duration > 0 &&
                c.maxWidth > 0 &&
                (c.maxWidth - _fitWidth).abs() > 8) {
              _scale = TimelineScale.fit(widget.duration, c.maxWidth - _pad * 2);
              _fitWidth = c.maxWidth;
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: _gutterW, child: _gutter()),
              Expanded(child: GestureDetector(
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
                setState(() {
                  _userZoomed = true;
                  _scale = TimelineScale(_zoomStart * d.horizontalScale);
                });
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
              )),
            ]);
          }),
        ),
      ]),
    );
  }

  /// Every layer, with where it sits. The gutter and the tracks both read
  /// this, so a tile can never drift from the lane it names.
  ///
  /// Layers of one kind share a band. A caption that ends before the next one
  /// starts costs no height at all — six captions down a clip are six blocks
  /// on one track, not six tracks, which is how every editor draws them and
  /// what makes the whole set readable at once. A second row appears only
  /// where two of them are genuinely on screen together.
  List<({double top, TimelineGroup group, TimelineItem? item})> _lanes() {
    final out = <({double top, TimelineGroup group, TimelineItem? item})>[];
    var y = _rulerH + _gap + _videoH + _gap;
    for (final g in widget.groups) {
      if (!g.open) {
        out.add((top: y, group: g, item: null));
        y += _rowH + _gap;
        continue;
      }
      final rows = packRows([for (final it in g.items) (it.start, it.end)]);
      for (var i = 0; i < g.items.length; i++) {
        out.add((top: y + rows[i] * (_rowH + _gap), group: g, item: g.items[i]));
      }
      y += (rows.isEmpty ? 1 : rows.reduce(math.max) + 1) * (_rowH + _gap);
    }
    return out;
  }

  /// The distinct bands, top to bottom. Several layers can share one, so this
  /// is what the gutter labels and what the lane colour is painted on.
  List<({double top, TimelineGroup group})> _bands() {
    final seen = <double>{};
    final out = <({double top, TimelineGroup group})>[];
    for (final l in _lanes()) {
      if (seen.add(l.top)) out.add((top: l.top, group: l.group));
    }
    return out;
  }

  /// Where two layers of one kind are on screen at the same time, and over
  /// which rows. Drawn as a marker: overlapping captions are usually a
  /// mistake, and until now nothing said so.
  List<({double from, double to, double top, double bottom})> _overlaps() {
    final byGroup = <String, List<({double top, TimelineItem item})>>{};
    for (final l in _lanes()) {
      if (l.item == null) continue;
      (byGroup[l.group.id] ??= []).add((top: l.top, item: l.item!));
    }
    final out = <({double from, double to, double top, double bottom})>[];
    for (final lanes in byGroup.values) {
      for (var i = 0; i < lanes.length; i++) {
        for (var j = i + 1; j < lanes.length; j++) {
          final a = lanes[i], b = lanes[j];
          final from = math.max(a.item.start, b.item.start);
          final to = math.min(a.item.end, b.item.end);
          if (to - from <= 1e-6) continue;
          out.add((
            from: from,
            to: to,
            top: math.min(a.top, b.top),
            bottom: math.max(a.top, b.top) + _rowH,
          ));
        }
      }
    }
    return out;
  }

  double _rowsHeight() {
    final l = _lanes();
    if (l.isEmpty) return 0;
    final deepest = l.map((e) => e.top).reduce(math.max);
    return (deepest + _rowH + _gap) - (_rulerH + _gap + _videoH + _gap);
  }

  Widget _zoomBar() => SizedBox(
        height: _zoomH,
        child: Row(children: [
          const Spacer(),
          _zoomBtn(Icons.remove_rounded, () => setState(() {
                _userZoomed = true;
                _scale = _scale.scaled(1 / 1.6);
              })),
          _zoomBtn(Icons.add_rounded, () => setState(() {
                _userZoomed = true;
                _scale = _scale.scaled(1.6);
              })),
          _zoomBtn(Icons.fit_screen_outlined, () {
            // back to automatic: re-fits on the next layout and tracks width again
            setState(() {
              _userZoomed = false;
              _fitWidth = 0;
            });
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

  /// One tile per lane, fixed while the time scrolls past it.
  ///
  /// It names the lane and, on a kind that holds more than one layer, carries
  /// the chevron that folds them into a single row. Without it the lanes were
  /// unlabelled strips and a layer looked like it was floating.
  Widget _gutter() {
    final lanes = _bands();
    return Stack(clipBehavior: Clip.none, children: [
      // aligns with the video track, so the column starts where the tracks do
      Positioned(
        left: 4, right: 4, top: _rulerH + _gap, height: _videoH,
        child: _gutterTile(Icons.movie_outlined, AppColors.inkMuted, null, null),
      ),
      for (var i = 0; i < lanes.length; i++)
        Positioned(
          left: 4, right: 4, top: lanes[i].top, height: _rowH,
          child: _gutterTile(
            lanes[i].group.icon,
            lanes[i].group.colour,
            // the fold control belongs to the kind, so it shows once per kind
            i == 0 || lanes[i].group.id != lanes[i - 1].group.id
                ? (lanes[i].group.items.length > 1 || !lanes[i].group.open)
                : false,
            lanes[i].group,
          ),
        ),
    ]);
  }

  Widget _gutterTile(IconData icon, Color colour, bool? foldable, TimelineGroup? g) {
    final tile = Container(
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: colour),
        if (foldable == true)
          Icon(g!.open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 12, color: AppColors.inkFaint),
      ]),
    );
    if (g == null || foldable != true) return tile;
    return GestureDetector(
      onTap: () => widget.onToggleGroup(g.id),
      behavior: HitTestBehavior.opaque,
      child: tile,
    );
  }

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
            // the bands first: a layer should sit ON a track, not float
            for (final band in _bands())
              Positioned(
                left: _pad, top: band.top, height: _rowH,
                width: _scale.contentWidth(widget.duration),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: band.group.colour.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            // under the blocks, so it marks them without hiding them
            for (final o in _overlaps())
              Positioned(
                left: _pad + _scale.xOf(o.from),
                top: o.top - 2,
                width: math.max(2.0, _scale.xOf(o.to - o.from)),
                height: o.bottom - o.top + 4,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.warnIcon.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: AppColors.warnIcon.withValues(alpha: 0.75), width: 1),
                    ),
                  ),
                ),
              ),
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
          // Tiles the width of a whole frame, each showing the one nearest its
          // own position. Sizing a tile to the time it covers meant squeezing a
          // 16:9 picture into sixteen pixels, which shredded the strip into
          // slivers; this is the shape a filmstrip is supposed to have.
          ...() {
            final tileW = math.max(24.0, _videoH * strip.aspect);
            final count = (w / tileW).ceil();
            return List.generate(count, (i) {
              final x = i * tileW;
              final f = strip.frameAt(_scale.secondsOf(x));
              if (f == null) return const SizedBox.shrink();
              return Positioned(
                left: x, top: 0, bottom: 0,
                width: math.min(tileW, w - x) + 0.5,
                child: Image.file(f, fit: BoxFit.cover,
                    alignment: Alignment.centerLeft,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              );
            });
          }(),
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
    for (final lane in _lanes()) {
      out.add(lane.item == null ? _groupRow(lane.group, lane.top) : _itemRow(lane.item!, lane.top));
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
          Positioned.fill(child: Opacity(
            opacity: it.hidden ? 0.35 : 1,
            child: _block(
              colour: it.colour,
              icon: it.locked ? Icons.lock_rounded : it.icon,
              label: it.label,
              selected: selected,
            ),
          )),
          if (selected && it.resizable && !it.locked && widget.onResize != null) ...[
            Positioned(left: 0, top: 0, bottom: 0, child: _grip(it, left: true)),
            Positioned(right: 0, top: 0, bottom: 0, child: _grip(it, left: false)),
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
        // The target is 22 wide; the handle drawn inside it is 11 and sits on
        // the block's own edge, so the frame reads as one shape rather than a
        // block held between two posts.
        child: SizedBox(
          width: 22,
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 11,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(left ? 7 : 0),
                  right: Radius.circular(left ? 0 : 7),
                ),
              ),
              child: Center(
                child: Container(
                  width: 2, height: _rowH * 0.42,
                  decoration: BoxDecoration(
                    color: AppColors.inkFaint, borderRadius: BorderRadius.circular(1)),
                ),
              ),
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
          // Sharing a track means neighbours can touch. The dark seam is what
          // keeps "two captions back to back" from reading as one long one.
          border: selected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: AppColors.bg, width: 1),
        ),
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 7),
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
