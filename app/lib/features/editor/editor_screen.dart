import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip.dart' as models;
import '../../models/editor_state.dart';
import '../../services/brand_kit_service.dart';
import '../../services/catalog_service.dart';
import '../../services/export_service.dart';
import '../../services/font_service.dart';
import '../../services/sticker_service.dart';
import '../../services/text_render.dart';
import '../../widgets/primary_button.dart';

const _kBg = Color(0xFF0B0A0C);
const _kPanel = Color(0xFF161318);
const _kChip = Color(0xFF221D24);
const _kAccent = Color(0xFFFF4D6D);

/// Pro layers editor: draggable / pinch-scalable / rotatable overlays on a dark
/// canvas, scrubbable timeline with trim, undo/redo, aspect crop, on-device export.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.clip, this.title});
  final models.Clip? clip;
  final String? title;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  VideoPlayerController? _vc;
  EditorProject? _project;
  String? _defaultFont;
  bool _busy = false;
  String? _error;

  Object? _selected; // SubtitleSegment | 'logo' | null
  bool _trimMode = false;

  // inline text editing (CapCut-style — video stays visible, live updates)
  bool _typing = false;
  final _textCtl = TextEditingController();
  final _textFocus = FocusNode();

  final _undo = <Map<String, dynamic>>[];
  final _redo = <Map<String, dynamic>>[];

  final _canvasKey = GlobalKey();
  bool _snapX = false, _snapY = false;
  String? _hint; // live scale%/angle° readout during manipulation

  String _deg(double rad) => (rad * 180 / math.pi).round().toString();
  bool _wasAngleSnapped = false, _wasXSnapped = false, _wasYSnapped = false;
  double _snapAngle(double rad) {
    const step = 45 * 3.1415926535 / 180; // CapCut snaps at 45° increments
    final n = (rad / step).round();
    final snapped = (rad - n * step).abs() < 0.06;
    if (snapped && !_wasAngleSnapped) HapticFeedback.selectionClick();
    _wasAngleSnapped = snapped;
    return snapped ? n * step : rad;
  }
  void _snapHaptic(bool x, bool y) {
    if (x && !_wasXSnapped) HapticFeedback.selectionClick();
    if (y && !_wasYSnapped) HapticFeedback.selectionClick();
    _wasXSnapped = x; _wasYSnapped = y;
  }

  // gesture start state
  double _gDx = 0, _gDy = 0, _gScale = 1, _gRot = 0, _gDist = 1, _gAngle = 0;
  // One-shot guard so a whole drag/pinch pushes exactly ONE undo snapshot.
  // MUST be a State field (not a per-build local) — every onScaleUpdate calls
  // setState → rebuild → a fresh local would reset to false every frame and
  // flood the undo stack (one snapshot per frame). Reset in every gesture start.
  bool _gestureSnapped = false;

  Offset? _toCanvas(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  double _snap(double v, double target, [double tol = 0.02]) => (v - target).abs() < tol ? target : v;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final fs = context.read<FontService>();
      _defaultFont = await fs.ensureDefaultFont();
      fs.loadBuiltins(); // load the full bundled family for the font picker (bg)
    } catch (_) {
      _defaultFont = '';
    }
    if (widget.clip != null) {
      final cs = context.read<CatalogService>();
      // attempt 0 uses any cache; attempt 1 forces a fresh re-download (recovers
      // from a corrupt/partial cache or a transient failure).
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final path = await cs.editClipFile(widget.clip!.id, fresh: attempt > 0);
          await _load(path);
          _error = null;
          break;
        } catch (_) {
          _error = 'Could not load the clip. Check your connection and retry.';
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _retry() async {
    setState(() => _error = null);
    await _init();
  }

  Future<void> _pickClip() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res != null && res.files.single.path != null) await _load(res.files.single.path!);
  }

  Future<void> _load(String path) async {
    _vc?.removeListener(_playbackTick);
    await _vc?.dispose();
    final c = VideoPlayerController.file(File(path));
    await c.initialize();
    await c.setLooping(false); // stop at the end like a real editor (not an endless loop)
    if (!mounted) {
      await c.dispose(); // backed out during init — don't leak the decoder
      return;
    }
    c.addListener(_playbackTick);
    setState(() {
      _vc = c;
      final dur = c.value.duration.inMilliseconds / 1000.0;
      _project = EditorProject(baseClipPath: path, defaultFontPath: _defaultFont ?? '', duration: dur);
      _error = null;
      _undo.clear();
      _redo.clear();
    });
  }

  bool _endHandled = false;
  // Trim window in ms. When no trim is set, outEnd == full duration and trimStart
  // == 0, so all of this collapses to normal full-clip behavior.
  int get _startMs => ((_project?.trimStart ?? 0) * 1000).round();
  int get _endMs => ((_project?.outEnd ?? _duration) * 1000).round();

  /// Playback respects the trim window: stop + rewind to trimStart at outEnd so the
  /// preview matches the exported cut (which is -ss trimStart -t outDuration).
  void _playbackTick() {
    final vc = _vc;
    final v = vc?.value;
    if (vc == null || v == null || !v.isInitialized) return;
    final pos = v.position.inMilliseconds;
    final atEnd = pos >= _endMs - 60;
    if (atEnd) {
      // Stop at the trim end (video may still have footage past outEnd) and rewind.
      if (v.isPlaying) {
        vc.pause();
        vc.seekTo(Duration(milliseconds: _startMs));
        _endHandled = true;
      } else if (!_endHandled) {
        _endHandled = true;
        vc.seekTo(Duration(milliseconds: _startMs));
      }
    } else if (pos < _startMs - 60) {
      // Scrubbed/seeked before the window start → clamp forward.
      vc.seekTo(Duration(milliseconds: _startMs));
    } else {
      _endHandled = false;
    }
  }

  @override
  void dispose() {
    _vc?.removeListener(_playbackTick);
    _vc?.dispose();
    _textCtl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  double get _duration => (_vc?.value.duration.inMilliseconds ?? 0) / 1000.0;
  double get _t => (_vc?.value.position.inMilliseconds ?? 0) / 1000.0;

  /// Play/pause. Restarts from trimStart when parked at/outside the trim window.
  void _togglePlay() {
    final vc = _vc;
    if (vc == null) return;
    final v = vc.value;
    if (v.isPlaying) {
      vc.pause();
    } else {
      final pos = v.position.inMilliseconds;
      if (pos >= _endMs - 80 || pos < _startMs) {
        vc.seekTo(Duration(milliseconds: _startMs));
      }
      vc.play();
    }
    setState(() {});
  }

  // ---------- undo / redo ----------
  void _snapshot() {
    _undo.add(_project!.snapshot());
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(_project!.snapshot());
    setState(() {
      _project!.restore(_undo.removeLast());
      _selected = null;
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(_project!.snapshot());
    setState(() {
      _project!.restore(_redo.removeLast());
      _selected = null;
    });
  }

  // ---------- subtitle ops (inline, CapCut-style — video stays visible) ----------
  double _topZ() {
    var m = _project!.logoPath != null ? _project!.logoZ : 0.0;
    for (final s in _project!.subtitles) {
      if (s.z > m) m = s.z;
    }
    for (final s in _project!.stickers) {
      if (s.z > m) m = s.z;
    }
    return m + 1;
  }

  void _addSubtitle() {
    _snapshot();
    // Guarantee a usable, non-degenerate window even when parked at/near the end
    // (the common "punchline" case). Back-shift start so [start,end] is >= 0.5s;
    // otherwise a zero-length caption silently never renders in preview or export.
    final dz = _duration;
    final s0 = dz <= 0 ? _t : _t.clamp(0.0, (dz - 0.5).clamp(0.0, dz));
    final e0 = dz <= 0 ? s0 + 3 : (s0 + 3).clamp(s0 + 0.5, dz);
    final seg = SubtitleSegment(text: '', start: s0, end: e0, z: _topZ());
    setState(() {
      _project!.subtitles.add(seg);
      _project!.subtitles.sort((a, b) => a.start.compareTo(b.start));
      _selected = seg;
    });
    _startTyping(seg);
  }

  void _editSelectedSubtitle() {
    if (_selected is SubtitleSegment) _startTyping(_selected as SubtitleSegment);
  }

  void _startTyping(SubtitleSegment s) {
    _vc?.pause();
    _textCtl.text = s.text;
    _textCtl.selection = TextSelection.collapsed(offset: s.text.length);
    setState(() {
      _selected = s;
      _typing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _textFocus.requestFocus());
  }

  void _doneTyping() {
    _textFocus.unfocus();
    setState(() {
      _typing = false;
      if (_selected is SubtitleSegment && (_selected as SubtitleSegment).text.trim().isEmpty) {
        _project!.subtitles.remove(_selected);
        _selected = null;
      }
    });
  }

  /// CapCut-style font picker: live "Aa" chips (bundled + uploaded) + import.
  Future<void> _openFontPicker() async {
    if (_selected is! SubtitleSegment) return;
    final s = _selected as SubtitleSegment;
    final fs = context.read<FontService>();
    await fs.loadBuiltins();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Font', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final f = await fs.uploadFont();
                      if (f != null) { _mutate(() { s.fontFamily = f.family; s.fontFilePath = f.path; }); setSheet(() {}); }
                    },
                    icon: const Icon(Icons.add, size: 18, color: _kAccent),
                    label: const Text('Import', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 10),
                Flexible(
                  child: GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                    children: [
                      // Default (system) option
                      _fontChip('Default', null, null, s, setSheet),
                      for (final f in fs.all) _fontChip(f.name, f.family, f.path, s, setSheet),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fontChip(String label, String? family, String? path, SubtitleSegment s, void Function(void Function()) setSheet) {
    final selected = s.fontFamily == family;
    return GestureDetector(
      onTap: () { _mutate(() { s.fontFamily = family; s.fontFilePath = path; }); setSheet(() {}); },
      child: Container(
        decoration: BoxDecoration(
          color: _kChip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _kAccent : Colors.white12, width: selected ? 2 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Aa', style: TextStyle(fontFamily: family, color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: selected ? _kAccent : Colors.white60, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  /// Advanced font/timing sheet (opened from the Font tool), not the primary flow.
  /// Adjust sheet — fine typography controls: bold / italic / shadow toggles +
  /// letter-spacing and line-height sliders (live, applied to the selected text).
  Future<void> _openStyleSheet() async {
    if (_selected is! SubtitleSegment) return;
    final s = _selected as SubtitleSegment;
    // Snapshot lazily on the FIRST edit only — opening + closing without touching
    // anything must not pollute the undo stack.
    var snapped = false;
    void snap() { if (!snapped) { _snapshot(); snapped = true; } }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Adjust', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 14),
                Row(children: [
                  _adjToggle('B', s.bold, () { snap(); setSheet(() { s.bold = !s.bold; setState(() {}); }); }, bold: true),
                  const SizedBox(width: 10),
                  _adjToggle('I', s.italic, () { snap(); setSheet(() { s.italic = !s.italic; setState(() {}); }); }, italic: true),
                  const SizedBox(width: 10),
                  _adjIconToggle(Icons.format_color_fill, 'Shadow', s.shadow, () { snap(); setSheet(() { s.shadow = !s.shadow; setState(() {}); }); }),
                ]),
                const SizedBox(height: 16),
                _fadeRowGeneric('Letter spacing', s.letterSpacing, -3, 12, (v) { snap(); setSheet(() { s.letterSpacing = v; setState(() {}); }); }, suffix: 'px'),
                _fadeRowGeneric('Line height', s.lineHeight, 0.8, 2.0, (v) { snap(); setSheet(() { s.lineHeight = v; setState(() {}); }); }, suffix: 'x'),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', icon: Icons.check, onPressed: () => Navigator.pop(context))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _adjToggle(String label, bool on, VoidCallback onTap, {bool bold = false, bool italic = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46, height: 40,
          decoration: BoxDecoration(color: on ? _kAccent : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? _kAccent : Colors.white12)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
        ),
      );

  Widget _adjIconToggle(IconData i, String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40, padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: on ? _kAccent : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? _kAccent : Colors.white12)),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16, color: Colors.white), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))]),
        ),
      );

  Widget _fadeRowGeneric(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = ''}) => Row(children: [
        SizedBox(width: 108, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(activeTrackColor: _kAccent, thumbColor: _kAccent, inactiveTrackColor: Colors.white24, overlayColor: _kAccent.withOpacity(0.15)),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 46, child: Text('${value.toStringAsFixed(1)}$suffix', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12))),
      ]);

  // ---------- layers panel (CapCut-style: reorder z, select, hide, delete) ----------
  void _openLayers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        final ordered = <MapEntry<double, Object>>[
          for (final s in _project!.subtitles) MapEntry(s.z, s),
          for (final s in _project!.stickers) MapEntry(s.z, s),
          if (_project!.logoPath != null) MapEntry(_project!.logoZ, 'logo'),
        ]..sort((a, b) => b.key.compareTo(a.key)); // top layer first

        void reassign() {
          for (var i = 0; i < ordered.length; i++) {
            final z = (ordered.length - i).toDouble();
            final it = ordered[i].value;
            if (it is SubtitleSegment) {
              it.z = z;
            } else if (it is StickerOverlay) {
              it.z = z;
            } else {
              _project!.logoZ = z;
            }
          }
        }

        Widget rowFor(Object it) {
          final isLogo = it == 'logo';
          final s = it is SubtitleSegment ? it : null;
          final stk = it is StickerOverlay ? it : null;
          final hidden = isLogo ? _project!.logoHidden : (s?.hidden ?? stk?.hidden ?? false);
          final selected = isLogo ? _selected == 'logo' : identical(_selected, it);
          final label = isLogo ? 'Logo' : stk != null ? (stk.emoji != null ? '${stk.emoji} Emoji' : 'Sticker') : (s!.text.trim().isEmpty ? 'Text' : s.text);
          final icon = isLogo ? Icons.image_outlined : stk != null ? Icons.auto_awesome_motion : Icons.title;
          return Container(
            key: isLogo ? const ValueKey('logo') : ObjectKey(it),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: selected ? _kAccent.withOpacity(0.18) : _kChip,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _kAccent : Colors.transparent),
            ),
            child: ListTile(
              dense: true,
              leading: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: Colors.white70, size: 18),
              ),
              title: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: hidden ? Colors.white38 : Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              onTap: () {
                setState(() => _selected = isLogo ? 'logo' : it);
                Navigator.pop(context);
              },
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white54, size: 20),
                  onPressed: () {
                    _snapshot();
                    setState(() {
                      if (isLogo) {
                        _project!.logoHidden = !_project!.logoHidden;
                      } else if (stk != null) {
                        stk.hidden = !stk.hidden;
                      } else {
                        s!.hidden = !s.hidden;
                      }
                    });
                    setSheet(() {});
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF04438), size: 20),
                  onPressed: () {
                    _snapshot();
                    setState(() {
                      if (isLogo) {
                        _project!.logoPath = null;
                      } else if (stk != null) {
                        _project!.stickers.remove(stk);
                      } else {
                        _project!.subtitles.remove(s);
                      }
                      if (identical(_selected, it) || (isLogo && _selected == 'logo')) _selected = null;
                    });
                    setSheet(() {});
                  },
                ),
                const Icon(Icons.drag_handle_rounded, color: Colors.white30),
              ]),
            ),
          );
        }

        return Container(
          decoration: const BoxDecoration(color: _kPanel, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: EdgeInsets.fromLTRB(14, 16, 14, 16 + MediaQuery.of(context).viewPadding.bottom),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(9)))),
            const SizedBox(height: 14),
            Row(children: const [
              Text('Layers', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              Spacer(),
              Text('Drag to reorder', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            if (ordered.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No layers yet.\nAdd text or a logo.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))))
            else
              Flexible(
                child: ReorderableListView(
                  shrinkWrap: true,
                  buildDefaultDragHandles: true,
                  onReorder: (oldI, newI) {
                    _snapshot();
                    setSheet(() {
                      if (newI > oldI) newI--;
                      final it = ordered.removeAt(oldI);
                      ordered.insert(newI, it);
                      reassign();
                    });
                    setState(() {});
                  },
                  children: [for (final e in ordered) rowFor(e.value)],
                ),
              ),
          ]),
        );
      }),
    );
  }

  // Inline text bar (docked above the keyboard; video + live text stay visible).
  // Minimal / compact: one scrollable row of small transparent chips, then a
  // slim input + Done. Everything uses the same subtle chip language.
  Widget _inlineTextEditor() {
    final s = _selected is SubtitleSegment ? _selected as SubtitleSegment : null;
    const colors = [0xFFFFFFFF, 0xFF000000, 0xFFFF4D6D, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFFFF7A00, 0xFF9B5DE5];
    return Container(
      color: _kPanel,
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // single compact control row: font · presets · colors · toggles
        SizedBox(
          height: 30,
          child: ListView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), children: [
            // font chip
            _ghostChip(
              onTap: () async { _textFocus.unfocus(); await _openFontPicker(); if (mounted && _typing) WidgetsBinding.instance.addPostFrameCallback((_) => _textFocus.requestFocus()); },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Aa', style: TextStyle(fontFamily: s?.fontFamily, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(width: 3),
                const Icon(Icons.expand_more_rounded, size: 13, color: Colors.white38),
              ]),
            ),
            _chipDivider(),
            for (final p in _textPresets) _presetChip(s, p),
            _chipDivider(),
            // color dots (undoable)
            for (final c in colors)
              GestureDetector(
                onTap: () { if (s != null) _mutate(() => s.color = c); },
                child: Container(
                  width: 22, height: 22, margin: const EdgeInsets.only(right: 7),
                  alignment: Alignment.center,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: s?.color == c ? _kAccent : Colors.white24, width: s?.color == c ? 2.5 : 1)),
                  ),
                ),
              ),
            _chipDivider(),
            // Outline stroke matches the toolbar 'Outline' width (3) for consistency.
            _miniToggle(Icons.border_color, (s?.strokeWidth ?? 0) > 0, () { if (s != null) _mutate(() => s.strokeWidth = s.strokeWidth > 0 ? 0 : 3); }),
            _miniToggle(Icons.title, s?.bgEnabled ?? false, () { if (s != null) _mutate(() => s.bgEnabled = !s.bgEnabled); }),
            _miniToggle(_alignIcon(s?.align ?? TextAlignH.center), true, () { if (s != null) _mutate(() => s.align = TextAlignH.values[(s.align.index + 1) % 3]); }),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _textCtl,
              focusNode: _textFocus,
              autofocus: true,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              cursorColor: _kAccent,
              textInputAction: TextInputAction.done,
              onChanged: (v) => setState(() => s?.text = v),
              onSubmitted: (_) => _doneTyping(),
              decoration: InputDecoration(
                hintText: 'Type your text…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                filled: true, fillColor: Colors.white.withOpacity(0.06), isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _doneTyping,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(10)),
              child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
          ),
        ]),
      ]),
    );
  }

  static const _textPresets = [
    {'name': 'Clean', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0x80000000, 'sw': 0.0, 'sc': 0xFF000000},
    {'name': 'Outline', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x80000000, 'sw': 5.0, 'sc': 0xFF000000},
    {'name': 'Sunny', 'color': 0xFF17131F, 'bg': true, 'bgc': 0xFFFFC400, 'sw': 0.0, 'sc': 0xFF000000},
    {'name': 'Neon', 'color': 0xFFFF4D6D, 'bg': false, 'bgc': 0x80000000, 'sw': 4.0, 'sc': 0xFFFFFFFF},
    {'name': 'Mint', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF12B76A, 'sw': 0.0, 'sc': 0xFF000000},
    {'name': 'Ink', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF3B9EFF, 'sw': 0.0, 'sc': 0xFF000000},
  ];

  /// Full "caption look" style templates — bundle font + color + stroke + bg +
  /// animation into one named tap (RenderForest-style). Applied via _applyStyle.
  static const _styleTemplates = [
    {'name': 'Bold Meme', 'font': 'Anton', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 6.0, 'sc': 0xFF000000, 'anim': OverlayAnim.popIn},
    {'name': 'Subtitle', 'font': 'Montserrat', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xB3000000, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Impact', 'font': 'ArchivoBlack', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 5.0, 'sc': 0xFF000000, 'anim': OverlayAnim.zoomIn},
    {'name': 'Neon Pop', 'font': 'BebasNeue', 'color': 0xFFFF4D6D, 'bg': false, 'bgc': 0x00000000, 'sw': 4.0, 'sc': 0xFFFFFFFF, 'anim': OverlayAnim.bounce},
    {'name': 'Sunshine', 'font': 'Poppins', 'color': 0xFF17131F, 'bg': true, 'bgc': 0xFFFFC400, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.slideUp},
    {'name': 'Marker', 'font': 'PermanentMarker', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF000000, 'anim': OverlayAnim.shake},
    {'name': 'Retro', 'font': 'Lobster', 'color': 0xFFFFC400, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF3A2600, 'anim': OverlayAnim.slideDown},
    {'name': 'Headline', 'font': 'Oswald', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFFFF4D6D, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.typewriter},
    {'name': 'Handwrite', 'font': 'Caveat', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Party', 'font': 'Shrikhand', 'color': 0xFFFF7A00, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFFFFFFFF, 'anim': OverlayAnim.pulse},
  ];

  // ---------- Music ----------
  Future<void> _openMusicSheet() async {
    final p = _project!;
    var volSnapped = false; // one snapshot for a whole volume-adjust session
    void snapVol() { if (!volSnapped) { _snapshot(); volSnapped = true; } }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.music_note_rounded, color: _kAccent, size: 20),
                const SizedBox(width: 8),
                const Text('Music', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const Spacer(),
                if (p.musicPath != null)
                  TextButton(onPressed: () { _mutate(() => p.musicPath = null); setSheet(() {}); }, child: const Text('Remove', style: TextStyle(color: Color(0xFFF04438), fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              Text(p.musicPath == null ? 'Add a music track — mixed under the clip audio on export.' : 'Music: ${p.musicPath!.split('/').last}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    FilePickerResult? res;
                    try {
                      res = await FilePicker.platform.pickFiles(type: FileType.audio);
                    } catch (_) {
                      res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg']);
                    }
                    if (res != null && res.files.single.path != null) {
                      _mutate(() => p.musicPath = res!.files.single.path);
                      setSheet(() {});
                    }
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.library_music_rounded, size: 18),
                  label: Text(p.musicPath == null ? 'Choose from device' : 'Change track'),
                ),
              ),
              if (p.musicPath != null) ...[
                const SizedBox(height: 16),
                _fadeRowGeneric('Music vol', p.musicVolume, 0, 1, (v) { snapVol(); setSheet(() { p.musicVolume = v; setState(() {}); }); }, suffix: ''),
                _fadeRowGeneric('Clip vol', p.originalVolume, 0, 1, (v) { snapVol(); setSheet(() { p.originalVolume = v; setState(() {}); }); }, suffix: ''),
                // Start offset into the track (seek in). Range 0..30s is plenty for
                // picking the "drop"; export already seeks via -ss musicStart.
                _fadeRowGeneric('Start at', p.musicStart, 0, 30, (v) { snapVol(); setSheet(() { p.musicStart = v; setState(() {}); }); }, suffix: 's'),
              ],
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', icon: Icons.check, onPressed: () => Navigator.pop(context))),
            ]),
          ),
          ),
        ),
      ),
    );
  }

  // ---------- Brand Kit ----------
  Future<void> _openBrandKit() async {
    final bk = context.read<BrandKitService>();
    await bk.ensureLoaded();
    await context.read<FontService>().loadBuiltins();
    // Work on a DEEP COPY so dismissing the sheet (tap-outside / back) does NOT
    // leak unsaved color/font/logo edits into the shared service kit. Only Save
    // / Apply commit the copy via bk.saveKit.
    final kit = bk.kit != null ? BrandKit.fromJson(bk.kit!.toJson()) : BrandKit();
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.palette_rounded, color: _kAccent, size: 20),
                const SizedBox(width: 8),
                const Text('Brand Kit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const Spacer(),
                TextButton(onPressed: () async { await bk.saveKit(kit); if (context.mounted) Navigator.pop(context); }, child: const Text('Save', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w800))),
              ]),
              Text('Save your colors, font & logo once — apply to any clip in a tap.', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              const SizedBox(height: 16),
              // palette
              const Text('Colors', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < kit.colors.length; i++)
                  GestureDetector(
                    onTap: () async {
                      final c = await _pickBrandColor(kit.colors[i]);
                      if (c != null) setSheet(() => kit.colors[i] = c);
                    },
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(kit.colors[i]), shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: i == 0 ? 3 : 1))),
                  ),
                if (kit.colors.length < 4)
                  GestureDetector(
                    onTap: () => setSheet(() => kit.colors.add(0xFF12B76A)),
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: const Icon(Icons.add, color: Colors.white54, size: 20)),
                  ),
              ]),
              const SizedBox(height: 16),
              // font
              Row(children: [
                const Text('Font', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final f in context.read<FontService>().all)
                        GestureDetector(
                          onTap: () => setSheet(() { kit.fontFamily = f.family; kit.fontPath = f.path; }),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: kit.fontFamily == f.family ? _kAccent : Colors.white10, borderRadius: BorderRadius.circular(9), border: Border.all(color: kit.fontFamily == f.family ? _kAccent : Colors.white12)),
                            child: Text('Aa', style: TextStyle(fontFamily: f.family, color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // logo
              Row(children: [
                const Text('Logo', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(width: 12),
                if (kit.logoPath != null) ...[
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.antiAlias, child: Image.file(File(kit.logoPath!), fit: BoxFit.contain)),
                  const SizedBox(width: 10),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    final res = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (res != null && res.files.single.path != null) {
                      final p = await bk.persistLogo(res.files.single.path!);
                      setSheet(() => kit.logoPath = p);
                    }
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: Text(kit.logoPath == null ? 'Add logo' : 'Change'),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Apply brand to clip', icon: Icons.auto_fix_high, onPressed: () async { await bk.saveKit(kit); _applyBrand(kit); if (context.mounted) Navigator.pop(context); })),
            ]),
          ),
        ),
      ),
    );
  }

  Future<int?> _pickBrandColor(int current) async {
    const palette = [0xFFFFFFFF, 0xFF000000, 0xFFFF4D6D, 0xFFFF7A00, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFF9B5DE5, 0xFF17131F, 0xFFFF2D6B];
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: _kPanel,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(spacing: 14, runSpacing: 14, children: [
            for (final c in palette)
              GestureDetector(
                onTap: () => Navigator.pop(context, c),
                child: Container(width: 42, height: 42, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == current ? _kAccent : Colors.white24, width: c == current ? 3 : 1))),
              ),
          ]),
        ),
      ),
    );
  }

  /// One-tap: recolor all text to the brand primary, set the brand font, and
  /// drop the brand logo in (top-right) if not already present.
  void _applyBrand(BrandKit kit) {
    _mutate(() {
      for (final s in _project!.subtitles) {
        s.color = kit.primary;
        if (kit.fontFamily != null) { s.fontFamily = kit.fontFamily; s.fontFilePath = kit.fontPath; }
      }
      if (kit.logoPath != null && File(kit.logoPath!).existsSync()) {
        _project!.logoPath = kit.logoPath;
        _project!.logoHidden = false;
      }
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brand applied ✨')));
  }

  void _applyStyle(SubtitleSegment s, Map<String, dynamic> t) {
    _mutate(() {
      s.fontFamily = t['font'] as String?;
      // resolve font file path for FFmpeg export from the loaded builtins
      if (s.fontFamily != null) {
        final match = context.read<FontService>().all.where((f) => f.family == s.fontFamily);
        s.fontFilePath = match.isNotEmpty ? match.first.path : s.fontFilePath;
      }
      s.color = t['color'] as int;
      s.bgEnabled = t['bg'] as bool;
      s.bgColor = t['bgc'] as int;
      s.strokeWidth = t['sw'] as double;
      s.strokeColor = t['sc'] as int;
      s.anim = t['anim'] as OverlayAnim;
    });
  }

  Widget _styleTile(SubtitleSegment s, Map<String, dynamic> tpl, VoidCallback onTap, {VoidCallback? onLong}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        decoration: BoxDecoration(
          color: (tpl['bg'] as bool) ? Color(tpl['bgc'] as int) : Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.fontFamily == tpl['font'] ? _kAccent : Colors.white12, width: s.fontFamily == tpl['font'] ? 2 : 1),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Aa', style: TextStyle(
            fontFamily: tpl['font'] as String?,
            color: Color(tpl['color'] as int),
            fontSize: 26, fontWeight: FontWeight.w900,
            shadows: (tpl['sw'] as double) > 0 ? [for (final o in const [Offset(-1, -1), Offset(1, 1), Offset(1, -1), Offset(-1, 1)]) Shadow(color: Color(tpl['sc'] as int), offset: o)] : null,
          )),
          const SizedBox(height: 3),
          Text(tpl['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  /// "Styles" gallery — one tap applies a full caption look (font+color+stroke+bg+anim).
  /// Shows the user's saved styles first (long-press to delete) + a "Save current" tile.
  Future<void> _openStyleGallery() async {
    if (_selected is! SubtitleSegment) return;
    final s = _selected as SubtitleSegment;
    await context.read<FontService>().loadBuiltins();
    final bk = context.read<BrandKitService>();
    await bk.ensureLoaded();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Styles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text('One-tap caption look. Long-press a saved style to remove.', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [
                    // "Save current" tile
                    GestureDetector(
                      onTap: () async {
                        final name = await _promptStyleName();
                        if (name == null || name.trim().isEmpty) return;
                        await bk.addStyle(SavedStyle(name.trim(), {
                          'name': name.trim(), 'font': s.fontFamily, 'color': s.color, 'bg': s.bgEnabled,
                          'bgc': s.bgColor, 'sw': s.strokeWidth, 'sc': s.strokeColor, 'anim': s.anim.index,
                        }));
                        setSheet(() {});
                      },
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24, style: BorderStyle.solid)),
                        alignment: Alignment.center,
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_rounded, color: _kAccent, size: 24),
                          SizedBox(height: 3),
                          Text('Save current', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    // user-saved styles
                    for (final st in bk.styles)
                      _styleTile(s, _savedToTpl(st),
                        () { _applyStyle(s, _savedToTpl(st)); setSheet(() {}); },
                        onLong: () async { await bk.removeStyle(st.name); setSheet(() {}); },
                      ),
                    // built-in templates
                    for (final tpl in _styleTemplates)
                      _styleTile(s, tpl, () { _applyStyle(s, tpl); setSheet(() {}); }),
                  ],
                ),
              ),
            ]),
          ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _savedToTpl(SavedStyle st) => {
        'name': st.name,
        'font': st.data['font'] as String?,
        'color': st.data['color'] as int,
        'bg': st.data['bg'] as bool,
        'bgc': st.data['bgc'] as int,
        'sw': (st.data['sw'] as num).toDouble(),
        'sc': st.data['sc'] as int,
        'anim': OverlayAnim.values[st.data['anim'] as int],
      };

  Future<String?> _promptStyleName() {
    final ctl = TextEditingController(text: 'My style');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kPanel,
        title: const Text('Save style', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: _kAccent,
          decoration: const InputDecoration(hintText: 'Style name', hintStyle: TextStyle(color: Colors.white38), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Save', style: TextStyle(color: _kAccent))),
        ],
      ),
    );
  }

  /// A minimal transparent pill used across the inline text bar.
  Widget _ghostChip({required Widget child, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          margin: const EdgeInsets.only(right: 7),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
          child: child,
        ),
      );

  Widget _chipDivider() => Container(width: 1, height: 18, margin: const EdgeInsets.only(right: 9, top: 6), color: Colors.white12);

  Widget _presetChip(SubtitleSegment? s, Map<String, dynamic> p) {
    final bg = p['bg'] as bool;
    final color = Color(p['color'] as int);
    final sw = p['sw'] as double;
    return GestureDetector(
      onTap: () {
        if (s == null) return;
        _snapshot();
        setState(() {
          s.color = p['color'] as int;
          s.bgEnabled = bg;
          s.bgColor = p['bgc'] as int;
          s.strokeWidth = sw;
          s.strokeColor = p['sc'] as int;
        });
      },
      child: Container(
        width: 30, height: 30,
        margin: const EdgeInsets.only(right: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg ? Color(p['bgc'] as int) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Text('Aa', style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 13,
          shadows: sw > 0 ? [for (final o in const [Offset(-0.8, -0.8), Offset(0.8, 0.8), Offset(0.8, -0.8), Offset(-0.8, 0.8)]) Shadow(color: Color(p['sc'] as int), offset: o)] : null,
        )),
      ),
    );
  }

  Widget _miniToggle(IconData i, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30, margin: const EdgeInsets.only(right: 7),
          decoration: BoxDecoration(color: on ? _kAccent : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? _kAccent : Colors.white12)),
          child: Icon(i, size: 15, color: Colors.white),
        ),
      );

  void _duplicateSelected() {
    _snapshot();
    if (_selected is SubtitleSegment) {
      final s = (_selected as SubtitleSegment).copy();
      s.dy = (s.dy + 0.06).clamp(0.05, 0.95);
      setState(() {
        _project!.subtitles.add(s);
        _selected = s;
      });
    } else if (_selected is StickerOverlay) {
      final s = (_selected as StickerOverlay).copy();
      s.dx = (s.dx + 0.05).clamp(0.05, 0.95);
      s.dy = (s.dy + 0.05).clamp(0.05, 0.95);
      s.z = _topZ();
      setState(() {
        _project!.stickers.add(s);
        _selected = s;
      });
    }
  }

  void _deleteSelected() {
    _snapshot();
    setState(() {
      if (_selected is SubtitleSegment) _project!.subtitles.remove(_selected);
      if (_selected is StickerOverlay) _project!.stickers.remove(_selected);
      if (_selected == 'logo') _project!.logoPath = null;
      _selected = null;
    });
  }

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.single.path != null) {
      _snapshot();
      setState(() {
        _project!.logoPath = res.files.single.path;
        _selected = 'logo';
      });
    }
  }


  // ---------- stickers / emoji ----------
  Future<void> _pickSticker() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.single.path != null) {
      _addSticker(res.files.single.path!);
    }
  }

  void _addSticker(String path, {String? emoji}) {
    _snapshot();
    // Same near-end guard as text. Keep the 9999 sentinel when duration is unknown
    // (export maps it to outEnd); otherwise back-shift start for a >= 0.5s window.
    final dz = _duration;
    final s0 = dz <= 0 ? _t : _t.clamp(0.0, (dz - 0.5).clamp(0.0, dz));
    final st = StickerOverlay(
      path: path,
      emoji: emoji,
      start: s0,
      end: dz <= 0 ? 9999.0 : (s0 + 3).clamp(s0 + 0.5, dz),
      z: _topZ(),
    );
    setState(() {
      _project!.stickers.add(st);
      _selected = st;
    });
  }

  static const _emojiSet = [
    '😂','🤣','😭','😍','🥰','😎','🤔','😳','😱','🤯','🥶','🤨','😏','🙄','😤','🤡',
    '🔥','💯','✨','⭐','💥','🎉','🎊','❤️','💔','💀','👀','👍','👎','🙏','👏','🤝',
    '💪','🧠','👑','🚀','⚡','💰','💎','🏆','🎯','📈','🤑','😴','🥳','😇','😈','🤙',
  ];

  /// Rich emoji/sticker library picker — category tabs + grid loaded from R2
  /// (StickerService), with a local-emoji fallback if the catalog is unreachable.
  Future<void> _openEmojiPicker() async {
    final svc = context.read<StickerService>();
    svc.ensureLoaded();
    int tab = 0;
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          return AnimatedBuilder(
            animation: svc,
            builder: (context, _) {
              final cats = svc.categories;
              final useR2 = cats.isNotEmpty;
              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                  child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, 10 + MediaQuery.of(context).viewPadding.bottom),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Stickers & emoji', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 10),
                    if (svc.loading && !useR2)
                      const SizedBox(height: 280, child: Center(child: CircularProgressIndicator(color: _kAccent)))
                    else if (useR2) ...[
                      // category tabs
                      SizedBox(
                        height: 34,
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                          for (var i = 0; i < cats.length; i++)
                            GestureDetector(
                              onTap: () => setSheet(() => tab = i),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(color: tab == i ? _kAccent : _kChip, borderRadius: BorderRadius.circular(18)),
                                child: Text(cats[i].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: GridView.count(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          children: [
                            for (final it in cats[tab.clamp(0, cats.length - 1)].items)
                              InkWell(
                                onTap: () { Navigator.pop(context); _addR2Sticker(it); },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(10)),
                                  child: Image.network(it.url, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Center(child: Text(it.emoji ?? '', style: const TextStyle(fontSize: 24)))),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else
                      // fallback: local platform emoji set (rendered to PNG)
                      Flexible(
                        child: GridView.count(
                          crossAxisCount: 6, mainAxisSpacing: 6, crossAxisSpacing: 6,
                          children: [
                            for (final e in _emojiSet)
                              InkWell(
                                onTap: () async { Navigator.pop(context); try { final p = await TextRenderService.renderEmojiToPng(e); if (mounted) _addSticker(p, emoji: e); } catch (_) {} },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(10)), child: Center(child: Text(e, style: const TextStyle(fontSize: 28)))),
                              ),
                          ],
                        ),
                      ),
                    if (svc.attribution != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(svc.attribution!, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9.5))),
                  ]),
                ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Downloads the crisp R2 PNG for a picked sticker and adds it to the canvas.
  Future<void> _addR2Sticker(StickerItem it) async {
    try {
      final path = await context.read<StickerService>().download(it);
      if (mounted) _addSticker(path, emoji: it.emoji);
    } catch (_) {
      // fallback to platform-rendered emoji if download fails
      if (it.emoji != null) {
        try { final p = await TextRenderService.renderEmojiToPng(it.emoji!); if (mounted) _addSticker(p, emoji: it.emoji); } catch (_) {}
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add sticker')));
      }
    }
  }

  /// Animation preset picker ("caption looks") + in/out fade timing for the
  /// selected text or sticker overlay. Tapping a preset previews it live.
  Future<void> _openFadeSheet() async {
    final sel = _selected;
    if (sel is! SubtitleSegment && sel is! StickerOverlay) return;
    double getFI() => sel is SubtitleSegment ? sel.fadeIn : (sel as StickerOverlay).fadeIn;
    double getFO() => sel is SubtitleSegment ? sel.fadeOut : (sel as StickerOverlay).fadeOut;
    void setFI(double v) => sel is SubtitleSegment ? sel.fadeIn = v : (sel as StickerOverlay).fadeIn = v;
    void setFO(double v) => sel is SubtitleSegment ? sel.fadeOut = v : (sel as StickerOverlay).fadeOut = v;
    OverlayAnim getAnim() => sel is SubtitleSegment ? sel.anim : (sel as StickerOverlay).anim;
    void setAnim(OverlayAnim a) => sel is SubtitleSegment ? sel.anim = a : (sel as StickerOverlay).anim = a;
    final segStart = sel is SubtitleSegment ? sel.start : ((sel as StickerOverlay).start >= 9998 ? 0.0 : sel.start);
    var snapped = false;
    void snap() { if (!snapped) { _snapshot(); snapped = true; } }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 18 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Animation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Pick a caption look — tap to preview.', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                height: 168,
                child: GridView.count(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.82,
                  children: [
                    for (final a in OverlayAnim.values)
                      GestureDetector(
                        onTap: () {
                          snap();
                          setSheet(() { setAnim(a); });
                          setState(() {});
                          _previewAnimFrom(segStart); // play the entry so the user sees it
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: getAnim() == a ? _kAccent : _kChip,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: getAnim() == a ? _kAccent : Colors.white12),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(a.icon, color: Colors.white, size: 22),
                            const SizedBox(height: 5),
                            Text(a.label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Fade', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(height: 6),
              _fadeRow('Fade in', getFI(), (v) { snap(); setSheet(() { setFI(v); setState(() {}); }); }),
              _fadeRow('Fade out', getFO(), (v) { snap(); setSheet(() { setFO(v); setState(() {}); }); }),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', icon: Icons.check, onPressed: () => Navigator.pop(context))),
            ]),
          ),
          ),
        ),
      ),
    );
  }

  /// Seeks to just before the overlay's start and plays ~1.2s so the entry
  /// animation is visible as a live preview.
  void _previewAnimFrom(double startSec) {
    final vc = _vc;
    if (vc == null) return;
    final to = (startSec - 0.05).clamp(0.0, _duration);
    vc.seekTo(Duration(milliseconds: (to * 1000).round()));
    vc.play();
    Future.delayed(const Duration(milliseconds: 1300), () { if (mounted && vc.value.isInitialized) vc.pause(); });
    setState(() {});
  }

  Widget _fadeRow(String label, double value, ValueChanged<double> onChanged) => Row(children: [
        SizedBox(width: 78, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(activeTrackColor: _kAccent, thumbColor: _kAccent, inactiveTrackColor: Colors.white24, overlayColor: _kAccent.withOpacity(0.15)),
            child: Slider(value: value.clamp(0, 2), min: 0, max: 2, divisions: 20, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 44, child: Text('${value.toStringAsFixed(1)}s', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12))),
      ]);

  void _mutate(VoidCallback fn) {
    _snapshot();
    setState(fn);
  }

  Future<void> _export() async {
    // Quota/Pro gating only applies to catalog clips (there's a creator to pay
    // and a server-side monthly quota). A picked local file (widget.clip == null)
    // is the user's own content with no creator to pay, so it stays ungated.
    setState(() => _busy = true);
    // Progress dialog. Capture the ROOT navigator so we always pop the dialog
    // itself (never the editor screen), and block the Android back button from
    // dismissing it mid-render (which previously left a stuck spinner + double-pop).
    final rootNav = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: _kPanel,
          content: Row(children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5)),
            SizedBox(width: 18),
            Text('Rendering…', style: TextStyle(color: Colors.white)),
          ]),
        ),
      ),
    ).then((_) => dialogOpen = false);
    void closeProgress() {
      if (dialogOpen) {
        dialogOpen = false;
        rootNav.pop();
      }
    }
    try {
      final res = await ExportService().export(_project!);
      // Only charge the monthly quota / creator download AFTER a successful
      // render, so a failed FFmpeg render never costs the user a quota slot.
      // For a picked local file (clip == null) there is nothing to record.
      if (widget.clip != null) {
        try {
          await context.read<CatalogService>().recordExport(widget.clip!.id);
        } on DioException catch (e) {
          final detail = e.response?.data is Map ? (e.response!.data['detail']) : null;
          final msg = e.response?.statusCode == 402
              ? (detail is Map && detail['message'] != null ? detail['message'].toString() : 'Subscribe to export this clip')
              : 'Could not record this export.';
          closeProgress();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$msg (Your video was rendered and saved on this device.)')),
            );
          }
          return;
        }
      }
      closeProgress();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _kPanel,
            title: const Text('Exported 🎉', style: TextStyle(color: Colors.white)),
            content: Text(
              res.savedToGallery
                  ? 'Saved to your Gallery (ClipCart album) 📱\nShare it to Instagram from there.'
                  : 'Saved on device:\n${res.path}',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      closeProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _project != null && _vc != null && _vc!.value.isInitialized;
    if (!ready) {
      return Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(backgroundColor: _kBg, foregroundColor: Colors.white, title: Text(widget.title ?? 'Editor')),
        body: Center(
          child: _defaultFont == null
              ? const CircularProgressIndicator(color: _kAccent)
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error == null) ...[
                    const CircularProgressIndicator(color: _kAccent),
                    const SizedBox(height: 16),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error ?? 'Loading your clip in full HD…', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null && widget.clip != null)
                    SizedBox(width: 220, child: PrimaryButton(label: 'Retry', icon: Icons.refresh, onPressed: _retry)),
                  if (_error != null && widget.clip != null) const SizedBox(height: 10),
                  SizedBox(width: 220, child: PrimaryButton(label: 'Choose video', icon: Icons.video_library, onPressed: _pickClip)),
                ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Text(widget.title ?? 'Editor', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        actions: [
          _iconBtn(Icons.undo_rounded, _undo.isEmpty ? null : _undoAction),
          _iconBtn(Icons.redo_rounded, _redo.isEmpty ? null : _redoAction),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SizedBox(width: 104, child: PrimaryButton(label: 'Export', icon: Icons.ios_share, loading: _busy, onPressed: _busy ? null : _export)),
          ),
        ],
      ),
      // Don't use SafeArea here — the control-deck panel paints its own colour
      // behind the nav bar (bottom padding = viewPadding.bottom) so there is no
      // black gap, and _toolbar/_inlineTextEditor already add the bottom inset.
      body: Column(
        children: [
          Expanded(child: SafeArea(top: false, bottom: false, child: _canvas())),
          if (_typing)
            _inlineTextEditor()
          else
            // Fixed-height control deck so the tools never get squeezed/truncated
            // by a tall canvas. Playbar + timeline + one scrollable tool row.
            Container(
              color: _kPanel,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _playbar(),
                  _timeline(),
                  _toolbar(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData i, VoidCallback? onTap) => IconButton(
        icon: Icon(i, size: 22, color: onTap == null ? Colors.white24 : Colors.white),
        onPressed: onTap,
      );

  // ---------- canvas ----------
  Widget _canvas() {
    return Center(
      child: AspectRatio(
        aspectRatio: _vc!.value.aspectRatio == 0 ? 9 / 16 : _vc!.value.aspectRatio,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            final videoH = _vc!.value.size.height == 0 ? 1280.0 : _vc!.value.size.height;
            final scale = h / videoH; // WYSIWYG video→canvas px
            return ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _vc!,
              builder: (context, v, _) {
                final t = v.position.inMilliseconds / 1000.0;
                final subs = _project!.subtitles.where((s) => !s.hidden && (identical(_selected, s) || (t >= s.start && t <= s.end)));
                final stks = _project!.stickers.where((s) => !s.hidden && (identical(_selected, s) || (t >= s.start && t <= s.end)));
                final overlays = <MapEntry<double, Widget>>[
                  for (final s in subs) MapEntry(s.z, _subOverlay(s, w, h, scale, t)),
                  for (final s in stks) MapEntry(s.z, _stickerOverlay(s, w, h, t)),
                  if (_project!.logoPath != null && !_project!.logoHidden) MapEntry(_project!.logoZ, _logoOverlay(w, h)),
                ]..sort((a, b) => a.key.compareTo(b.key));
                return Stack(
                  key: _canvasKey,
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: () {
                        // tap on empty canvas: if something is selected, just deselect
                        // (lets the user "finish" one edit and start another); else play/pause.
                        if (_selected != null) {
                          setState(() => _selected = null);
                        } else {
                          _togglePlay();
                        }
                      },
                      child: VideoPlayer(_vc!),
                    ),
                    if (_project!.aspect.ratio != null) _cropGuide(w, h),
                    ...overlays.map((e) => e.value),
                    if (_snapX) Positioned(left: w / 2 - 0.5, top: 0, bottom: 0, child: const IgnorePointer(child: SizedBox(width: 1, child: ColoredBox(color: Color(0x88FF4D6D))))),
                    if (_snapY) Positioned(top: h / 2 - 0.5, left: 0, right: 0, child: const IgnorePointer(child: SizedBox(height: 1, child: ColoredBox(color: Color(0x88FF4D6D))))),
                    if (_hint != null)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.72), borderRadius: BorderRadius.circular(20)),
                              child: Text(_hint!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
                            ),
                          ),
                        ),
                      ),
                    if (!v.isPlaying && _selected == null)
                      IgnorePointer(child: Center(child: Icon(Icons.play_arrow_rounded, size: 54, color: Colors.white.withOpacity(0.5)))),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _cropGuide(double w, double h) {
    final ar = _project!.aspect.ratio!;
    final frameAr = w / h;
    double cw, ch;
    if (ar < frameAr) {
      ch = h;
      cw = h * ar;
    } else {
      cw = w;
      ch = w / ar;
    }
    return IgnorePointer(
      child: Center(
        child: Container(
          width: cw,
          height: ch,
          decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.75), width: 1.5)),
        ),
      ),
    );
  }

  Widget _subOverlay(SubtitleSegment s, double w, double h, double scale, double t) {
    final selected = identical(_selected, s);
    final text = Container(
      constraints: BoxConstraints(maxWidth: w * 0.92),
      padding: EdgeInsets.symmetric(horizontal: s.bgEnabled ? 7 : 3, vertical: s.bgEnabled ? 3 : 2),
      decoration: BoxDecoration(
        color: s.bgEnabled ? Color(s.bgColor) : null,
        borderRadius: BorderRadius.circular(5),
        border: selected ? Border.all(color: _kAccent, width: 1.5) : null,
      ),
      child: Text(
        s.text.isEmpty ? 'Text' : s.text,
        textAlign: switch (s.align) { TextAlignH.left => TextAlign.left, TextAlignH.right => TextAlign.right, TextAlignH.center => TextAlign.center },
        style: TextStyle(
          fontFamily: s.fontFamily,
          color: s.uiColor,
          // Only a lower legibility floor — no upper cap, so the on-screen size
          // tracks the export 1:1 (export composites the PNG at effectiveSize,
          // no ceiling). A hard 90px cap here made big text look smaller than it
          // exported on short clips / large canvases (WYSIWYG break).
          fontSize: (s.effectiveSize * scale).clamp(9, double.infinity),
          fontWeight: s.bold ? FontWeight.w800 : FontWeight.w500,
          fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: s.letterSpacing * scale,
          height: s.lineHeight,
          shadows: s.strokeWidth > 0
              ? [for (final o in const [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)]) Shadow(color: Color(s.strokeColor), offset: o * (s.strokeWidth * scale).clamp(0.5, 4))]
              : (s.shadow ? const [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1.5, 1.5))] : const [Shadow(color: Colors.black54, blurRadius: 3)]),
        ),
      ),
    );
    return Align(
      alignment: Alignment(s.dx * 2 - 1, s.dy * 2 - 1),
      child: Stack(clipBehavior: Clip.none, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = s),
          onScaleStart: (d) {
            setState(() => _selected = s);
            _gestureSnapped = false;
            _gDx = s.dx;
            _gDy = s.dy;
            _gScale = s.scale;
            _gRot = s.rotation;
          },
          onScaleUpdate: (d) => setState(() {
            if (!_gestureSnapped) {
              _snapshot();
              _gestureSnapped = true;
            }
            _gDx = (_gDx + d.focalPointDelta.dx / w).clamp(0.0, 1.0).toDouble();
            _gDy = (_gDy + d.focalPointDelta.dy / h).clamp(0.0, 1.0).toDouble();
            s.dx = _snap(_gDx, 0.5).clamp(0.03, 0.97).toDouble();
            s.dy = _snap(_gDy, 0.5).clamp(0.03, 0.97).toDouble();
            _snapX = (s.dx - 0.5).abs() < 0.001;
            _snapY = (s.dy - 0.5).abs() < 0.001;
            _snapHaptic(_snapX, _snapY);
            if (d.scale != 1.0) s.scale = (_gScale * d.scale).clamp(0.4, 4.0);
            if (d.rotation != 0) s.rotation = _snapAngle(_gRot + d.rotation);
            _hint = '${(s.scale * 100).round()}%   ${_deg(s.rotation)}°';
          }),
          onScaleEnd: (_) => setState(() {
            _gestureSnapped = false;
            _snapX = _snapY = false;
            _hint = null;
          }),
          child: Builder(builder: (_) {
            final af = selected ? const AnimFrame() : s.animAt(t);
            final op = (selected ? 1.0 : s.opacityAt(t) * af.opacity).clamp(0.15, 1.0);
            return Opacity(
              opacity: op,
              child: Transform.translate(
                offset: Offset(af.ox * w, af.oy * h),
                child: Transform.scale(
                  scale: af.scale,
                  child: Transform.rotate(angle: s.rotation, child: text),
                ),
              ),
            );
          }),
        ),
        if (selected) ...[
          Positioned(left: -11, top: -11, child: _cornerBtn(Icons.close_rounded, _deleteSelected)),
          Positioned(right: -11, top: -11, child: _cornerBtn(Icons.edit_rounded, () => _startTyping(s))),
          Positioned(left: -11, bottom: -11, child: _cornerBtn(Icons.copy_rounded, _duplicateSelected)),
          Positioned(right: -11, bottom: -11, child: _resizeHandle(s, w, h, rotate: true)),
        ],
      ]),
    );
  }

  /// A CapCut-style round corner action button on a selected overlay.
  Widget _cornerBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.72), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.4)),
          child: Icon(icon, size: 13, color: Colors.white),
        ),
      );

  /// One-finger corner handle: drag to scale (text) or scale+rotate (logo).
  Widget _resizeHandle(Object target, double w, double h, {required bool rotate}) {
    Offset center() {
      if (target is SubtitleSegment) return Offset(target.dx * w, target.dy * h);
      if (target is StickerOverlay) return Offset(target.dx * w, target.dy * h);
      return Offset(_project!.logoDx * w, _project!.logoDy * h);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) {
        _gestureSnapped = false;
        final f = _toCanvas(d.globalPosition);
        final c = center();
        _gDist = f == null ? 1 : math.max(8, (f - c).distance);
        _gAngle = f == null ? 0 : math.atan2(f.dy - c.dy, f.dx - c.dx);
        _gScale = target is SubtitleSegment
            ? target.scale
            : target is StickerOverlay
                ? target.scale
                : _project!.logoScale;
        _gRot = target is SubtitleSegment
            ? target.rotation
            : target is StickerOverlay
                ? target.rotation
                : _project!.logoRotation;
      },
      onPanUpdate: (d) => setState(() {
        if (!_gestureSnapped) {
          _snapshot();
          _gestureSnapped = true;
        }
        final f = _toCanvas(d.globalPosition);
        if (f == null) return;
        final c = center();
        final dist = math.max(8, (f - c).distance);
        final ns = (_gScale * dist / _gDist).clamp(0.3, 5.0);
        final nr = rotate ? _snapAngle(_gRot + (math.atan2(f.dy - c.dy, f.dx - c.dx) - _gAngle)) : _gRot;
        if (target is SubtitleSegment) {
          target.scale = ns;
          target.rotation = nr;
        } else if (target is StickerOverlay) {
          target.scale = ns;
          target.rotation = nr;
        } else {
          _project!.logoScale = ns;
          _project!.logoRotation = nr;
        }
        _hint = '${(ns * 100).round()}%   ${_deg(nr)}°';
      }),
      onPanEnd: (_) => setState(() { _gestureSnapped = false; _hint = null; }),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: _kAccent, width: 2)),
        child: Icon(rotate ? Icons.open_with : Icons.zoom_out_map, size: 13, color: _kAccent),
      ),
    );
  }

  Widget _logoOverlay(double w, double h) {
    final selected = _selected == 'logo';
    final p = _project!;
    return Align(
      alignment: Alignment(p.logoDx * 2 - 1, p.logoDy * 2 - 1),
      child: Stack(clipBehavior: Clip.none, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = 'logo'),
          onScaleStart: (d) {
            setState(() => _selected = 'logo');
            _gestureSnapped = false;
            _gDx = p.logoDx;
            _gDy = p.logoDy;
            _gScale = p.logoScale;
            _gRot = p.logoRotation;
          },
          onScaleUpdate: (d) => setState(() {
            if (!_gestureSnapped) {
              _snapshot();
              _gestureSnapped = true;
            }
            _gDx = (_gDx + d.focalPointDelta.dx / w).clamp(0.0, 1.0).toDouble();
            _gDy = (_gDy + d.focalPointDelta.dy / h).clamp(0.0, 1.0).toDouble();
            p.logoDx = _snap(_gDx, 0.5).clamp(0.03, 0.97).toDouble();
            p.logoDy = _snap(_gDy, 0.5).clamp(0.03, 0.97).toDouble();
            _snapX = (p.logoDx - 0.5).abs() < 0.001;
            _snapY = (p.logoDy - 0.5).abs() < 0.001;
            _snapHaptic(_snapX, _snapY);
            if (d.scale != 1.0) p.logoScale = (_gScale * d.scale).clamp(0.3, 4.0);
            p.logoRotation = _snapAngle(_gRot + d.rotation);
            _hint = '${(p.logoScale * 100).round()}%   ${_deg(p.logoRotation)}°';
          }),
          onScaleEnd: (_) => setState(() {
            _gestureSnapped = false;
            _snapX = _snapY = false;
            _hint = null;
          }),
          child: Transform.rotate(
            angle: p.logoRotation,
            child: Container(
              decoration: BoxDecoration(border: selected ? Border.all(color: _kAccent, width: 1.5) : null),
              child: Image.file(File(p.logoPath!), width: w * 0.18 * p.logoScale),
            ),
          ),
        ),
        if (selected) ...[
          Positioned(left: -11, top: -11, child: _cornerBtn(Icons.close_rounded, _deleteSelected)),
          Positioned(right: -11, bottom: -11, child: _resizeHandle('logo', w, h, rotate: true)),
        ],
      ]),
    );
  }

  Widget _stickerOverlay(StickerOverlay st, double w, double h, double t) {
    final selected = identical(_selected, st);
    return Align(
      alignment: Alignment(st.dx * 2 - 1, st.dy * 2 - 1),
      child: Stack(clipBehavior: Clip.none, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = st),
          onScaleStart: (d) {
            setState(() => _selected = st);
            _gestureSnapped = false;
            _gDx = st.dx;
            _gDy = st.dy;
            _gScale = st.scale;
            _gRot = st.rotation;
          },
          onScaleUpdate: (d) => setState(() {
            if (!_gestureSnapped) {
              _snapshot();
              _gestureSnapped = true;
            }
            _gDx = (_gDx + d.focalPointDelta.dx / w).clamp(0.0, 1.0).toDouble();
            _gDy = (_gDy + d.focalPointDelta.dy / h).clamp(0.0, 1.0).toDouble();
            st.dx = _snap(_gDx, 0.5).clamp(0.03, 0.97).toDouble();
            st.dy = _snap(_gDy, 0.5).clamp(0.03, 0.97).toDouble();
            _snapX = (st.dx - 0.5).abs() < 0.001;
            _snapY = (st.dy - 0.5).abs() < 0.001;
            _snapHaptic(_snapX, _snapY);
            if (d.scale != 1.0) st.scale = (_gScale * d.scale).clamp(0.3, 5.0);
            st.rotation = _snapAngle(_gRot + d.rotation);
            _hint = '${(st.scale * 100).round()}%   ${_deg(st.rotation)}°';
          }),
          onScaleEnd: (_) => setState(() {
            _gestureSnapped = false;
            _snapX = _snapY = false;
            _hint = null;
          }),
          child: Builder(builder: (_) {
            final af = selected ? const AnimFrame() : st.animAt(t);
            final op = (selected ? 1.0 : st.opacityAt(t) * af.opacity).clamp(0.15, 1.0);
            return Opacity(
              opacity: op,
              child: Transform.translate(
                offset: Offset(af.ox * w, af.oy * h),
                child: Transform.scale(
                  scale: af.scale,
                  child: Transform.rotate(
                    angle: st.rotation,
                    child: Container(
                      decoration: BoxDecoration(border: selected ? Border.all(color: _kAccent, width: 1.5) : null),
                      child: Image.file(File(st.path), width: w * st.baseWidthFrac * st.scale),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        if (selected) ...[
          Positioned(left: -11, top: -11, child: _cornerBtn(Icons.close_rounded, _deleteSelected)),
          Positioned(left: -11, bottom: -11, child: _cornerBtn(Icons.copy_rounded, _duplicateSelected)),
          Positioned(right: -11, bottom: -11, child: _resizeHandle(st, w, h, rotate: true)),
        ],
      ]),
    );
  }

  // ---------- transport row (play + timer, left) | action pills (right) ----------
  Widget _playbar() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vc!,
      builder: (context, v, _) {
        final ended = v.position.inMilliseconds >= _endMs - 80 && !v.isPlaying;
        return Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          child: Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(v.isPlaying ? Icons.pause_circle_filled : (ended ? Icons.replay_circle_filled : Icons.play_circle_fill), color: Colors.white, size: 32),
              onPressed: _togglePlay,
            ),
            const SizedBox(width: 2),
            Text('${_fmt(Duration(milliseconds: (v.position.inMilliseconds - _startMs).clamp(0, _endMs - _startMs)))} / ${_fmt(Duration(milliseconds: _endMs - _startMs))}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            // Compact icon-only action buttons — never truncate, always fit.
            _actionIcon('Layers', Icons.layers_rounded, _openLayers),
            const SizedBox(width: 4),
            _actionIcon(_project!.aspect.label, Icons.crop_rounded, _pickAspect),
            const SizedBox(width: 4),
            _actionIcon('Trim', Icons.content_cut_rounded, () => setState(() => _trimMode = !_trimMode), on: _trimMode),
          ]),
        );
      },
    );
  }

  /// Compact labelled icon button for the transport row (icon over a tiny label).
  Widget _actionIcon(String label, IconData icon, VoidCallback onTap, {bool on = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(color: on ? _kAccent : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 19, color: Colors.white),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  String _fmt(Duration d) => '${d.inMinutes.remainder(60)}:${(d.inSeconds.remainder(60)).toString().padLeft(2, '0')}';

  // ---------- timeline (scrub + trim + subtitle track) ----------
  Widget _timeline() {
    final dur = _duration;
    final p = _project!;
    final hasLayers = p.subtitles.isNotEmpty || p.stickers.isNotEmpty;
    // Height adapts: base track always, + a lane for text, + a lane for stickers.
    final laneCount = (p.subtitles.isNotEmpty ? 1 : 0) + (p.stickers.isNotEmpty ? 1 : 0);
    final trackH = 26.0;
    final laneH = 20.0;
    final totalH = 8 + trackH + (laneCount * (laneH + 4)) + 8;
    return Container(
      color: const Color(0xFF0F0D12),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      height: totalH.clamp(50.0, 130.0),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        double x(double sec) => dur <= 0 ? 0 : (sec / dur) * w;
        double sec(double px) => dur <= 0 ? 0 : (px / w) * dur;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _vc!,
          builder: (context, v, _) {
            final ph = x(v.position.inMilliseconds / 1000.0);
            double laneTop = trackH + 4;
            final textTop = laneTop;
            if (p.subtitles.isNotEmpty) laneTop += laneH + 4;
            final stkTop = laneTop;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _seek(sec(d.localPosition.dx)),
              onHorizontalDragUpdate: _trimMode ? null : (d) => _seek(sec(d.localPosition.dx.clamp(0, w))),
              child: Stack(clipBehavior: Clip.none, children: [
                // ---- base video track (filmstrip look) ----
                Positioned(
                  left: 0, right: 0, top: 0, height: trackH,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2A2430), Color(0xFF1C1822)])),
                      child: Row(children: [
                        for (int i = 0; i < 10; i++)
                          Expanded(child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                            decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05)))),
                            child: Center(child: Icon(Icons.movie_creation_outlined, size: 12, color: Colors.white.withOpacity(0.10))),
                          )),
                      ]),
                    ),
                  ),
                ),
                // trimmed-out dim regions (over the base track)
                if (p.trimStart > 0) Positioned(left: 0, width: x(p.trimStart), top: 0, height: trackH, child: _dim()),
                if (p.outEnd < dur) Positioned(left: x(p.outEnd), right: 0, top: 0, height: trackH, child: _dim()),
                // empty hint (sits ON the base track so it never overflows below)
                if (!hasLayers)
                  Positioned(
                    left: 0, right: 0, top: 0, height: trackH,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(10)),
                          child: Text('Tap Add text, Emoji or Sticker to begin', style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 10.5, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                // ---- text lane ----
                for (final s in p.subtitles)
                  Positioned(
                    left: x(s.start), width: (x(s.end) - x(s.start)).clamp(30, w), top: textTop, height: laneH,
                    child: _timelineBlock(
                      label: s.text.isEmpty ? 'Text' : s.text,
                      icon: Icons.title_rounded,
                      selected: identical(_selected, s),
                      gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]),
                      onTap: () => setState(() => _selected = s),
                      onDrag: (dx) => setState(() {
                        final len = s.end - s.start;
                        s.start = (s.start + sec(dx)).clamp(0, dur - len);
                        s.end = s.start + len;
                      }),
                    ),
                  ),
                // ---- sticker/emoji lane ----
                for (final s in p.stickers)
                  Positioned(
                    left: x(s.start), width: (x((s.end >= 9998 ? dur : s.end)) - x(s.start)).clamp(30, w), top: stkTop, height: laneH,
                    child: _timelineBlock(
                      label: s.emoji != null ? '${s.emoji}  Emoji' : 'Sticker',
                      icon: s.emoji != null ? null : Icons.auto_awesome_motion_rounded,
                      selected: identical(_selected, s),
                      color: const Color(0xFF7B61FF),
                      onTap: () => setState(() => _selected = s),
                      onDrag: (dx) => setState(() {
                        final end = s.end >= 9998 ? dur : s.end;
                        final len = end - s.start;
                        s.start = (s.start + sec(dx)).clamp(0, dur - len);
                        s.end = s.start + len;
                      }),
                    ),
                  ),
                // trim handles (only affect the base track region)
                if (_trimMode) ..._trimHandles(x, sec, w, p, dur, trackH),
                // playhead across the whole timeline
                Positioned(left: ph.clamp(0, w) - 1, top: -2, bottom: -2, child: IgnorePointer(child: Container(width: 2, color: Colors.white))),
                Positioned(left: ph.clamp(0, w) - 5, top: -6, child: IgnorePointer(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))),
              ]),
            );
          },
        );
      }),
    );
  }

  Widget _timelineBlock({
    required String label,
    IconData? icon,
    required bool selected,
    LinearGradient? gradient,
    Color? color,
    required VoidCallback onTap,
    required void Function(double) onDrag,
  }) {
    return GestureDetector(
      onTap: onTap,
      onHorizontalDragStart: (_) => _snapshot(), // fires once per drag → move is undoable
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          gradient: gradient,
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? Colors.white : Colors.white.withOpacity(0.15), width: selected ? 1.6 : 1),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 4)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _dim() => DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(7)));

  List<Widget> _trimHandles(double Function(double) x, double Function(double) sec, double w, EditorProject p, double dur, double trackH) {
    Widget handle(double left, void Function(double) onDrag) => Positioned(
          left: left - 9, top: 0, height: trackH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _snapshot(), // trim change is undoable
            onHorizontalDragUpdate: (d) => setState(() => onDrag(d.delta.dx)),
            child: Container(
              width: 18,
              decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.drag_indicator, size: 14, color: Colors.white),
            ),
          ),
        );
    return [
      handle(x(p.trimStart), (dx) => p.trimStart = (p.trimStart + sec(dx)).clamp(0, p.outEnd - 0.3)),
      handle(x(p.outEnd), (dx) => p.trimEnd = (p.outEnd + sec(dx)).clamp(p.trimStart + 0.3, dur)),
    ];
  }

  void _seek(double s) {
    // Clamp tap/drag seeks to the trim window so the preview stays inside the cut.
    final lo = _startMs / 1000.0, hi = _endMs / 1000.0;
    final ms = (s.clamp(lo, hi) * 1000).round();
    _vc!.seekTo(Duration(milliseconds: ms));
  }

  // ---------- toolbar (contextual) ----------
  Widget _toolbar() {
    final tools = <Widget>[];
    if (_selected is SubtitleSegment) {
      final s = _selected as SubtitleSegment;
      tools.addAll([
        _tool(Icons.edit, 'Edit', _editSelectedSubtitle),
        _tool(Icons.auto_awesome_rounded, 'Styles', _openStyleGallery),
        _tool(Icons.font_download_rounded, 'Font', _openFontPicker),
        _tool(Icons.tune_rounded, 'Adjust', _openStyleSheet),
        _tool(Icons.format_color_text, 'Color', () => _quickColor(s)),
        _tool(s.bgEnabled ? Icons.check_box : Icons.check_box_outline_blank, 'BG', () => _mutate(() => s.bgEnabled = !s.bgEnabled)),
        _tool(Icons.border_color, 'Outline', () => _mutate(() => s.strokeWidth = s.strokeWidth > 0 ? 0 : 3)),
        _tool(_alignIcon(s.align), 'Align', () => _mutate(() => s.align = TextAlignH.values[(s.align.index + 1) % 3])),
        _tool(Icons.animation, 'Animate', _openFadeSheet, active: s.anim != OverlayAnim.none || s.fadeIn > 0 || s.fadeOut > 0),
        _tool(Icons.copy, 'Copy', _duplicateSelected),
        _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
      ]);
    } else if (_selected is StickerOverlay) {
      final st = _selected as StickerOverlay;
      tools.addAll([
        _tool(Icons.rotate_left, 'Left', () => _mutate(() => st.rotation -= math.pi / 12)),
        _tool(Icons.rotate_right, 'Right', () => _mutate(() => st.rotation += math.pi / 12)),
        _tool(Icons.flip, 'Reset', () => _mutate(() { st.rotation = 0; st.scale = 1; })),
        _tool(Icons.animation, 'Animate', _openFadeSheet, active: st.anim != OverlayAnim.none || st.fadeIn > 0 || st.fadeOut > 0),
        _tool(Icons.copy, 'Copy', _duplicateSelected),
        _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
      ]);
    } else if (_selected == 'logo') {
      tools.addAll([
        _tool(Icons.rotate_left, 'Left', () => _mutate(() => _project!.logoRotation -= math.pi / 12)),
        _tool(Icons.rotate_right, 'Right', () => _mutate(() => _project!.logoRotation += math.pi / 12)),
        _tool(Icons.refresh, 'Reset', () => _mutate(() { _project!.logoRotation = 0; _project!.logoScale = 1; })),
        _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
      ]);
    } else {
      tools.addAll([
        _tool(Icons.text_fields, 'Add text', _addSubtitle),
        _tool(Icons.emoji_emotions_outlined, 'Emoji', _openEmojiPicker),
        _tool(Icons.auto_awesome_motion, 'Sticker', _pickSticker),
        _tool(Icons.music_note_rounded, 'Music', _openMusicSheet, active: _project!.musicPath != null),
        _tool(Icons.image_outlined, 'Logo', _pickLogo),
        _tool(Icons.palette_rounded, 'Brand', _openBrandKit),
      ]);
    }
    final hasSel = _selected != null;
    final selLabel = _selected is SubtitleSegment
        ? 'Text'
        : _selected is StickerOverlay
            ? ((_selected as StickerOverlay).emoji != null ? 'Emoji' : 'Sticker')
            : _selected == 'logo'
                ? 'Logo'
                : '';
    return Container(
      color: _kPanel,
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // When a layer is selected: a clear header with a Done button so the user
          // can finish editing this layer and go back to adding another.
          if (hasSel)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 6),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('Editing $selLabel', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _selected = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    ]),
                  ),
                ),
              ]),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: tools),
          ),
        ],
      ),
    );
  }

  IconData _alignIcon(TextAlignH a) => switch (a) {
        TextAlignH.left => Icons.format_align_left,
        TextAlignH.center => Icons.format_align_center,
        TextAlignH.right => Icons.format_align_right,
      };

  void _quickColor(SubtitleSegment s) {
    const colors = [0xFFFFFFFF, 0xFF000000, 0xFFFF4D6D, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFFFF7A00, 0xFF9B5DE5];
    showModalBottomSheet(
      context: context,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Text color', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 14),
            Wrap(spacing: 14, runSpacing: 14, children: [
              for (final c in colors)
                GestureDetector(
                  onTap: () {
                    _mutate(() => s.color = c);
                    Navigator.pop(context);
                  },
                  child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == s.color ? _kAccent : Colors.white24, width: c == s.color ? 3 : 1))),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickAspect() async {
    final a = await showModalBottomSheet<AspectOption>(
      context: context,
      backgroundColor: _kPanel,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final opt in AspectOption.all)
            ListTile(
              leading: Icon(Icons.crop, color: opt == _project!.aspect ? _kAccent : Colors.white54),
              title: Text(opt.label, style: TextStyle(color: opt == _project!.aspect ? _kAccent : Colors.white, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(context, opt),
            ),
        ]),
      ),
    );
    if (a != null) _mutate(() => _project!.aspect = a);
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool danger = false, bool active = false}) {
    final c = danger ? const Color(0xFFF04438) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: active ? _kAccent : _kChip,
              borderRadius: BorderRadius.circular(12),
              border: active ? Border.all(color: _kAccent, width: 1) : null,
            ),
            child: Icon(icon, color: c, size: 22),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(label, style: TextStyle(color: c.withOpacity(0.9), fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }
}
