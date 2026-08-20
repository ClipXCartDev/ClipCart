import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart' show AppColors;
import '../../models/clip.dart' as models;
import '../../models/editor_state.dart';
import '../../services/brand_kit_service.dart';
import '../../services/catalog_service.dart';
import '../../services/export_service.dart';
import '../../services/font_service.dart';
import '../../services/project_store.dart';
import '../../services/sticker_service.dart';
import '../../services/text_render.dart';
import '../../widgets/primary_button.dart';

// Editor dark chrome — the design's "room you enter and leave" (warm near-black).
const _kBg = Color(0xFF101114);   // editor canvas backdrop
const _kPanel = Color(0xFF191B1F); // --dk control panels
const _kChip = Color(0xFF23262C);  // raised tool tiles
const _kAccent = Color(0xFF34D399); // brighter violet on dark chrome (--brl proxy)

/// Pro layers editor: draggable / pinch-scalable / rotatable overlays on a dark
/// canvas, scrubbable timeline with trim, undo/redo, aspect crop, on-device export.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.clip, this.title, this.resume});
  final models.Clip? clip;
  final String? title;
  final SavedProject? resume; // reopen a saved in-progress project

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
  int _textTab = 0; // §4.1 text panel sub-tab: 0 Style · 1 Advanced · 2 Timing · 3 Presets

  // Stable id for this project's on-disk save (reused when resuming so re-saving
  // updates the same file rather than piling up duplicates).
  String? _projectId;
  // Autosave (§4.0 feedback 8): every edit is written automatically — there is no
  // save button and no discard prompt; leaving never loses work.
  Timer? _autosaveTimer;
  DateTime? _lastSaved;
  bool _saving = false;

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
    // RESUME a saved in-progress project: reopen its base clip + restore all edits.
    if (widget.resume != null) {
      _projectId = widget.resume!.id;
      final saved = widget.resume!;
      try {
        final restored = saved.toProject();
        // Re-fetch the base clip file if the cached path is gone (app reinstall / cache clear).
        var basePath = restored.baseClipPath;
        if (!File(basePath).existsSync() && saved.clipId != null) {
          basePath = await context.read<CatalogService>().editClipFile(saved.clipId!);
        }
        await _load(basePath);
        // Overlay the restored edits on top of the freshly-loaded project.
        if (_project != null) {
          restored.baseClipPath = _project!.baseClipPath;
          restored.defaultFontPath = _project!.defaultFontPath;
          restored.duration = _project!.duration;
          setState(() => _project = restored);
        }
        _error = null;
      } catch (_) {
        _error = 'Could not reopen this project.';
      }
      if (mounted) setState(() {});
      return;
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

  /// Persist the current project to the on-device store so it appears in the
  /// Editor tab and can be resumed. Returns true on success.
  Future<bool> _saveProject() async {
    final p = _project;
    if (p == null) return false;
    try {
      _projectId ??= 'proj_${DateTime.now().microsecondsSinceEpoch}';
      final name = (widget.title ?? widget.clip?.title ?? widget.resume?.name ?? 'My project').trim();
      await context.read<ProjectStore>().save(SavedProject(
            id: _projectId!,
            name: name.isEmpty ? 'My project' : name,
            clipId: widget.clip?.id ?? widget.resume?.clipId,
            thumb: widget.clip?.thumb ?? widget.resume?.thumb,
            updatedAt: DateTime.now(),
            data: p.toProjectJson(),
          ));
      return true;
    } catch (_) {
      return false;
    }
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
    _autosaveTimer?.cancel();
    _vc?.removeListener(_playbackTick);
    _vc?.dispose();
    _textCtl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  double get _duration => (_vc?.value.duration.inMilliseconds ?? 0) / 1000.0;
  double get _t => (_vc?.value.position.inMilliseconds ?? 0) / 1000.0;

  /// Has the user made ANY edit worth warning about before discarding (back)?
  bool get _hasEdits {
    final p = _project;
    if (p == null) return false;
    return p.subtitles.isNotEmpty ||
        p.stickers.isNotEmpty ||
        p.logoPath != null ||
        p.trimStart > 0.01 ||
        (p.trimEnd != null && p.trimEnd! < p.duration - 0.01) ||
        !p.aspect.isOriginal ||
        _undo.isNotEmpty;
  }

  /// Autosave means back never loses work (§4.0 feedback 8) — no dialog. Flush a
  /// final save on the way out and pop. Always safe to leave.
  Future<bool> _confirmDiscard() async {
    _autosaveTimer?.cancel();
    if (_hasEdits && !_busy) await _saveProject();
    return true;
  }

  /// Debounced autosave — every meaningful edit reschedules a quiet write to the
  /// draft store ~1.2s later. No spinner, no button.
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1200), () async {
      if (!mounted || _project == null || _busy) return;
      final ok = await _saveProject();
      if (ok && mounted) setState(() => _lastSaved = DateTime.now());
    });
  }

  /// Human "Saved just now / Xm ago" label for the top bar.
  String get _savedLabel {
    final t = _lastSaved;
    if (_saving) return 'Saving…';
    if (t == null) return _hasEdits ? 'Saving…' : '';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 5) return 'Saved just now';
    if (d.inMinutes < 1) return 'Saved ${d.inSeconds}s ago';
    if (d.inMinutes < 60) return 'Saved ${d.inMinutes}m ago';
    return 'Saved';
  }

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
    _scheduleAutosave(); // every meaningful edit triggers a quiet autosave
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

  /// Client-required overlay presets. All reuse SubtitleSegment (styled text that
  /// exports through the same PNG-overlay path) so they're fully editable after.
  void _addUsername() {
    _snapshot();
    final seg = SubtitleSegment(
      text: '@yourhandle', start: 0, end: _duration <= 0 ? 3 : _duration,
      fontSize: 34, dx: 0.5, dy: 0.93, bold: true,
      bgEnabled: true, bgColor: 0x99000000, color: 0xFFFFFFFF, z: _topZ(),
    );
    setState(() { _project!.subtitles.add(seg); _selected = seg; });
    _startTyping(seg);
  }

  void _addCta() {
    _snapshot();
    final dz = _duration;
    // last ~2.5s call-to-action pill
    final s0 = dz <= 0 ? 0.0 : (dz - 2.5).clamp(0.0, dz);
    final seg = SubtitleSegment(
      text: 'Follow for more', start: s0, end: dz <= 0 ? 3 : dz,
      fontSize: 40, dx: 0.5, dy: 0.5, bold: true,
      bgEnabled: true, bgColor: 0xFF0E9E6E, color: 0xFFFFFFFF,
      anim: OverlayAnim.popIn, z: _topZ(),
    );
    setState(() { _project!.subtitles.add(seg); _selected = seg; });
    _startTyping(seg);
  }

  void _addEndingScreen() {
    _snapshot();
    final dz = _duration <= 0 ? 3.0 : _duration;
    final s0 = (dz - 2.5).clamp(0.0, dz);
    // Full-width dark outro card with big centered text over the last ~2.5s.
    final card = SubtitleSegment(
      text: 'Thanks for watching', start: s0, end: dz,
      fontSize: 52, dx: 0.5, dy: 0.5, bold: true,
      bgEnabled: true, bgColor: 0xE60B0A0C, color: 0xFFFFFFFF,
      anim: OverlayAnim.fade, fadeIn: 0.3, z: _topZ(),
    );
    setState(() { _project!.subtitles.add(card); _selected = card; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Outro card added to the last 2.5s — tap to edit')));
    _startTyping(card);
  }

  void _toggleWatermark() {
    _mutate(() => _project!.watermarkOn = !_project!.watermarkOn);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_project!.watermarkOn ? 'Watermark on' : 'Watermark removed'),
      ));
    }
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
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _adjToggle('B', s.bold, () { snap(); setSheet(() { s.bold = !s.bold; setState(() {}); }); }, bold: true),
                  _adjToggle('I', s.italic, () { snap(); setSheet(() { s.italic = !s.italic; setState(() {}); }); }, italic: true),
                  _adjIconToggle(Icons.format_color_fill, 'Shadow', s.shadow, () { snap(); setSheet(() { s.shadow = !s.shadow; setState(() {}); }); }),
                  _adjIconToggle(Icons.title, 'BG', s.bgEnabled, () { snap(); setSheet(() { s.bgEnabled = !s.bgEnabled; setState(() {}); }); }),
                  _adjIconToggle(_alignIcon(s.align), 'Align', false, () { snap(); setSheet(() { s.align = TextAlignH.values[(s.align.index + 1) % 3]; setState(() {}); }); }),
                ]),
                const SizedBox(height: 16),
                // Text SIZE slider (client-requested: length/size adjust). Drives the
                // same scale as pinch; range matches the pinch clamp (0.4–4.0).
                _fadeRowGeneric('Size', s.scale, 0.4, 4.0, (v) { snap(); setSheet(() { s.scale = v; setState(() {}); }); }, suffix: 'x'),
                _fadeRowGeneric('Opacity', s.opacity, 0.1, 1.0, (v) { snap(); setSheet(() { s.opacity = v; setState(() {}); }); }, suffix: ''),
                _fadeRowGeneric('Outline', s.strokeWidth, 0, 12, (v) { snap(); setSheet(() { s.strokeWidth = v; setState(() {}); }); }, suffix: 'px'),
                _fadeRowGeneric('Letter spacing', s.letterSpacing, -3, 12, (v) { snap(); setSheet(() { s.letterSpacing = v; setState(() {}); }); }, suffix: 'px'),
                _fadeRowGeneric('Line height', s.lineHeight, 0.8, 2.0, (v) { snap(); setSheet(() { s.lineHeight = v; setState(() {}); }); }, suffix: 'x'),
                const SizedBox(height: 14),
                // Exact numeric entry (feedback 5): size + X/Y position (%) + scale.
                Row(children: [
                  Expanded(child: _NumField(label: 'Size', value: s.fontSize, min: 8, max: 400, onChanged: (v) { snap(); setSheet(() { s.fontSize = v; setState(() {}); }); })),
                  const SizedBox(width: 10),
                  Expanded(child: _NumField(label: 'X %', value: s.dx * 100, min: 0, max: 100, onChanged: (v) { snap(); setSheet(() { s.dx = (v / 100).clamp(0.0, 1.0); setState(() {}); }); })),
                  const SizedBox(width: 10),
                  Expanded(child: _NumField(label: 'Y %', value: s.dy * 100, min: 0, max: 100, onChanged: (v) { snap(); setSheet(() { s.dy = (v / 100).clamp(0.0, 1.0); setState(() {}); }); })),
                  const SizedBox(width: 10),
                  Expanded(child: _NumField(label: 'Scale', value: s.scale, min: 0.4, max: 4.0, decimals: 2, onChanged: (v) { snap(); setSheet(() { s.scale = v; setState(() {}); }); })),
                ]),
                const SizedBox(height: 14),
                // Timing — the text appears only between Start and End (seconds).
                Row(children: [
                  Expanded(child: _NumField(label: 'Start (s)', value: s.start, min: 0, max: (_duration <= 0 ? 9999 : _duration), decimals: 1, onChanged: (v) { snap(); setSheet(() { s.start = v.clamp(0.0, s.end - 0.2); setState(() {}); }); })),
                  const SizedBox(width: 10),
                  Expanded(child: _NumField(label: 'End (s)', value: s.end, min: 0, max: (_duration <= 0 ? 9999 : _duration), decimals: 1, onChanged: (v) { snap(); setSheet(() { s.end = v.clamp(s.start + 0.2, _duration <= 0 ? 9999 : _duration); setState(() {}); }); })),
                  const Spacer(flex: 2),
                ]),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text('Text shows from ${s.start.toStringAsFixed(1)}s to ${s.end.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'IBMPlexMono'))),
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
    // Multi-select (§4.0 feedback 5): a select mode with per-row checks + batch
    // delete/hide. State lives here so it persists across StatefulBuilder rebuilds.
    final sel = <Object>{};
    var selectMode = false;
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
              leading: selectMode
                  ? Icon(sel.contains(it) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: sel.contains(it) ? _kAccent : Colors.white38, size: 26)
                  : Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, color: Colors.white70, size: 18),
                    ),
              title: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: hidden ? Colors.white38 : Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              onTap: () {
                if (selectMode) {
                  setSheet(() => sel.contains(it) ? sel.remove(it) : sel.add(it));
                  return;
                }
                setState(() => _selected = isLogo ? 'logo' : it);
                Navigator.pop(context);
              },
              trailing: selectMode ? null : Row(mainAxisSize: MainAxisSize.min, children: [
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
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.err, size: 20),
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
            Row(children: [
              const Text('Layers', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (ordered.isNotEmpty)
                GestureDetector(
                  onTap: () => setSheet(() { selectMode = !selectMode; sel.clear(); }),
                  child: Text(selectMode ? 'Done' : 'Select', style: const TextStyle(color: _kAccent, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
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
            // batch action bar (multi-select)
            if (selectMode && sel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    _snapshot();
                    setState(() {
                      for (final it in sel) {
                        if (it is SubtitleSegment) it.hidden = !it.hidden;
                        else if (it is StickerOverlay) it.hidden = !it.hidden;
                        else _project!.logoHidden = !_project!.logoHidden;
                      }
                    });
                    setSheet(() {});
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.visibility_off_rounded, size: 18),
                  label: const Text('Hide/Show'),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    _snapshot();
                    setState(() {
                      for (final it in sel) {
                        if (it is SubtitleSegment) _project!.subtitles.remove(it);
                        else if (it is StickerOverlay) _project!.stickers.remove(it);
                        else _project!.logoPath = null;
                        if (identical(_selected, it)) _selected = null;
                      }
                    });
                    setSheet(() { sel.clear(); selectMode = false; });
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.err, side: const BorderSide(color: Color(0x55F04438)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Delete (${sel.length})'),
                )),
              ]),
            ],
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
    const colors = [0xFFFFFFFF, 0xFF000000, 0xFF0E9E6E, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFF12B886, 0xFF9B5DE5];
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
            // size steppers (client asked for text size adjust while typing)
            _ghostChip(
              onTap: () { if (s != null) setState(() => s.scale = (s.scale - 0.15).clamp(0.4, 4.0)); },
              child: const Text('A−', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            _ghostChip(
              onTap: () { if (s != null) setState(() => s.scale = (s.scale + 0.15).clamp(0.4, 4.0)); },
              child: const Text('A+', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
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
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            // Multi-line: the keyboard shows a return key that inserts a newline
            // (client: "text ko next line mein le jaane ka option nahi hai").
            child: TextField(
              controller: _textCtl,
              focusNode: _textFocus,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              cursorColor: _kAccent,
              onChanged: (v) => setState(() => s?.text = v),
              decoration: InputDecoration(
                hintText: 'Type your text…  (Enter = new line)',
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    {'name': 'Neon', 'color': 0xFF0E9E6E, 'bg': false, 'bgc': 0x80000000, 'sw': 4.0, 'sc': 0xFFFFFFFF},
    {'name': 'Mint', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF12B76A, 'sw': 0.0, 'sc': 0xFF000000},
    {'name': 'Ink', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF3B9EFF, 'sw': 0.0, 'sc': 0xFF000000},
  ];

  /// Full "caption look" style templates — bundle font + color + stroke + bg +
  /// animation into one named tap (RenderForest-style). Applied via _applyStyle.
  static const _styleTemplates = [
    {'name': 'Bold Meme', 'font': 'Anton', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 6.0, 'sc': 0xFF000000, 'anim': OverlayAnim.popIn},
    {'name': 'Subtitle', 'font': 'Montserrat', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xB3000000, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Impact', 'font': 'Archivo Black', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 5.0, 'sc': 0xFF000000, 'anim': OverlayAnim.zoomIn},
    {'name': 'Neon Pop', 'font': 'Bebas Neue', 'color': 0xFF0E9E6E, 'bg': false, 'bgc': 0x00000000, 'sw': 4.0, 'sc': 0xFFFFFFFF, 'anim': OverlayAnim.bounce},
    {'name': 'Sunshine', 'font': 'Poppins', 'color': 0xFF17131F, 'bg': true, 'bgc': 0xFFFFC400, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.slideUp},
    {'name': 'Marker', 'font': 'Permanent Marker', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF000000, 'anim': OverlayAnim.shake},
    {'name': 'Retro', 'font': 'Lobster', 'color': 0xFFFFC400, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF3A2600, 'anim': OverlayAnim.slideDown},
    {'name': 'Headline', 'font': 'Oswald', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF0E9E6E, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.typewriter},
    {'name': 'Handwrite', 'font': 'Caveat', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Party', 'font': 'Shrikhand', 'color': 0xFF12B886, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFFFFFFFF, 'anim': OverlayAnim.pulse},
    {'name': 'Clean', 'font': 'Inter', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.none},
    {'name': 'Boxed', 'font': 'Montserrat', 'color': 0xFF000000, 'bg': true, 'bgc': 0xFFFFFFFF, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.popIn},
    {'name': 'Fire', 'font': 'Anton', 'color': 0xFFFFC400, 'bg': false, 'bgc': 0x00000000, 'sw': 5.0, 'sc': 0xFFC2272D, 'anim': OverlayAnim.zoomIn},
    {'name': 'Mint', 'font': 'Poppins', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF12B76A, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.slideUp},
    {'name': 'Ocean', 'font': 'Oswald', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFF2D7FF9, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.slideDown},
    {'name': 'Glow', 'font': 'Bebas Neue', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 2.0, 'sc': 0xFF0E9E6E, 'anim': OverlayAnim.pulse},
    {'name': 'Comic', 'font': 'Bungee', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 5.0, 'sc': 0xFF000000, 'anim': OverlayAnim.bounce},
    {'name': 'Script', 'font': 'Pacifico', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 3.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Serif', 'font': 'Playfair Display', 'color': 0xFFFFFFFF, 'bg': false, 'bgc': 0x00000000, 'sw': 2.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Sport', 'font': 'Passion One', 'color': 0xFFFFC400, 'bg': false, 'bgc': 0x00000000, 'sw': 4.0, 'sc': 0xFF000000, 'anim': OverlayAnim.popIn},
    {'name': 'Coral', 'font': 'Anton', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xFFFF4D6D, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.zoomIn},
    {'name': 'Night', 'font': 'Montserrat', 'color': 0xFFFFFFFF, 'bg': true, 'bgc': 0xE6000000, 'sw': 0.0, 'sc': 0xFF000000, 'anim': OverlayAnim.fade},
    {'name': 'Gold', 'font': 'Playfair Display', 'color': 0xFFD89A3C, 'bg': false, 'bgc': 0x00000000, 'sw': 2.0, 'sc': 0xFF3A2600, 'anim': OverlayAnim.slideUp},
  ];

  // ---------- Music (§4.0 feedback 6 — import from device, mix + start offset) ----------
  Future<void> _openMusicSheet() async {
    final p = _project!;
    var volSnapped = false;
    void snapVol() { if (!volSnapped) { _snapshot(); volSnapped = true; } }
    String fmtStart(double s) {
      final m = s ~/ 60, sec = (s % 60);
      return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
    }
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
                const Text('Music', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 14),
                if (p.musicPath == null)
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
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 13)),
                      icon: const Icon(Icons.library_music_rounded, size: 18),
                      label: const Text('Import from device'),
                    ),
                  )
                else ...[
                  // track card
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(11), border: Border.all(color: Colors.white12)),
                    child: Row(children: [
                      Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFF3A2E12), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.music_note_rounded, color: Color(0xFFD89A3C), size: 20)),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.musicPath!.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        const Text('from your device', style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'IBMPlexMono')),
                      ])),
                      GestureDetector(
                        onTap: () async {
                          final res = await FilePicker.platform.pickFiles(type: FileType.audio);
                          if (res != null && res.files.single.path != null) { _mutate(() => p.musicPath = res.files.single.path); setSheet(() {}); }
                        },
                        child: const Text('Replace', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _fadeRowGeneric('Music', p.musicVolume, 0, 1, (v) { snapVol(); setSheet(() { p.musicVolume = v; setState(() {}); }); }, suffix: ''),
                  _fadeRowGeneric('Clip audio', p.originalVolume, 0, 1, (v) { snapVol(); setSheet(() { p.originalVolume = v; setState(() {}); }); }, suffix: ''),
                  _fadeRowGeneric('Start at', p.musicStart, 0, 60, (v) { snapVol(); setSheet(() { p.musicStart = v; setState(() {}); }); }, suffix: 's'),
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerLeft, child: Text('Starts at ${fmtStart(p.musicStart)}', style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'IBMPlexMono'))),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Text('Fade out at the end', style: TextStyle(color: Colors.white, fontSize: 13)),
                    const Spacer(),
                    Switch(value: p.musicFadeOut, activeColor: _kAccent, onChanged: (v) { _mutate(() => p.musicFadeOut = v); setSheet(() {}); }),
                  ]),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () { _mutate(() => p.musicPath = null); setSheet(() {}); },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.err),
                      label: const Text('Remove music', style: TextStyle(color: AppColors.err, fontWeight: FontWeight.w700)),
                    ),
                  ),
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

  /// Logo Adjust — exact X / Y (%) + Scale + Rotation numeric boxes.
  Future<void> _openLogoAdjust() async {
    final p = _project!;
    var snapped = false;
    void snap() { if (!snapped) { _snapshot(); snapped = true; } }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Logo position & size', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _NumField(label: 'X %', value: p.logoDx * 100, min: 0, max: 100, onChanged: (v) { snap(); setSheet(() { p.logoDx = (v / 100).clamp(0.0, 1.0); setState(() {}); }); })),
                const SizedBox(width: 10),
                Expanded(child: _NumField(label: 'Y %', value: p.logoDy * 100, min: 0, max: 100, onChanged: (v) { snap(); setSheet(() { p.logoDy = (v / 100).clamp(0.0, 1.0); setState(() {}); }); })),
                const SizedBox(width: 10),
                Expanded(child: _NumField(label: 'Scale', value: p.logoScale, min: 0.2, max: 4.0, decimals: 2, onChanged: (v) { snap(); setSheet(() { p.logoScale = v; setState(() {}); }); })),
                const SizedBox(width: 10),
                Expanded(child: _NumField(label: 'Angle°', value: p.logoRotation * 180 / math.pi, min: -180, max: 180, onChanged: (v) { snap(); setSheet(() { p.logoRotation = v * math.pi / 180; setState(() {}); }); })),
              ]),
              const SizedBox(height: 8),
              const Text('Or just drag the logo on the canvas.', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', icon: Icons.check, onPressed: () => Navigator.pop(context))),
            ]),
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
    const palette = [0xFFFFFFFF, 0xFF000000, 0xFF0E9E6E, 0xFF12B886, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFF9B5DE5, 0xFF17131F, 0xFF0E9E6E];
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

  /// Export settings sheet — resolution + fps (client-requested "export at
  /// 720p/1080p, 30/60fps"). Returns true if the user hit Export.
  Future<bool> _openExportSettings() async {
    final p = _project!;
    return await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        Widget optRow<T>(String title, List<(String, T)> options, T current, ValueChanged<T> onPick) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final o in options)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheet(() => onPick(o.$2)),
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: current == o.$2 ? _kAccent : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: current == o.$2 ? _kAccent : Colors.white12),
                          ),
                          child: Text(o.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
              ],
            );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Export settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text('Renders on this phone · saves to your Gallery', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              const SizedBox(height: 18),
              optRow<int>('QUALITY', const [('720p', 720), ('1080p', 1080)], p.resolution.shortEdge,
                  (v) => p.resolution = v == 720 ? ExportResolution.p720 : ExportResolution.p1080),
              optRow<int>('FRAME RATE', const [('30 fps', 30), ('60 fps', 60)], p.fps, (v) => p.fps = v),
              // Watermark (design places it in export settings)
              Row(children: [
                const Text('Watermark', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text(p.watermarkOn ? 'On' : 'Off', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const Spacer(),
                Switch(value: p.watermarkOn, activeColor: _kAccent, onChanged: (v) => setSheet(() => p.watermarkOn = v)),
              ]),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Export video', icon: Icons.ios_share, onPressed: () => Navigator.pop(context, true))),
              const SizedBox(height: 8),
            ]),
          ),
        );
      }),
    ) ?? false;
  }

  Future<void> _export() async {
    // Quota/Pro gating only applies to catalog clips (there's a creator to pay
    // and a server-side monthly quota). A picked local file (widget.clip == null)
    // is the user's own content with no creator to pay, so it stays ungated.
    if (!await _openExportSettings()) return;
    setState(() => _busy = true);
    // Progress dialog with a REAL bar driven by FFmpeg frame statistics (honest
    // progress — no fake loop). Capture the ROOT navigator so we always pop the
    // dialog itself (never the editor screen), and block the Android back button.
    final rootNav = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double>(0.0);
    var dialogOpen = true;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: _kPanel,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rendering your video…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: v <= 0 ? null : v, // indeterminate until the first frame
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(_kAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(v <= 0 ? 'Preparing…' : '${(v * 100).round()}%  ·  keep the app open',
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
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
      final res = await ExportService().export(_project!, onProgress: (v) => progress.value = v);
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
      progress.dispose();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async { if (await _confirmDiscard() && mounted) Navigator.of(context).pop(); },
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.title ?? 'Editor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (_savedLabel.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF4FB477)),
              const SizedBox(width: 4),
              Text(_savedLabel, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 10.5, color: Colors.white54, fontWeight: FontWeight.w500)),
            ]),
        ]),
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
            // Compact control deck — playbar + timeline + the property panel. The
            // panel handles its own bottom (gesture) inset, so no extra padding here.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _playbar(),
                _timeline(),
                _toolbar(),
              ],
            ),
        ],
      ),
      ),
    );
  }

  Widget _iconBtn(IconData i, VoidCallback? onTap) => IconButton(
        icon: Icon(i, size: 22, color: onTap == null ? Colors.white24 : Colors.white),
        onPressed: onTap,
      );

  // ---------- canvas ----------
  Widget _canvas() {
    final nativeAr = _vc!.value.aspectRatio == 0 ? 9 / 16 : _vc!.value.aspectRatio;
    // When an aspect crop is chosen, the CANVAS itself becomes that ratio and the
    // video is cover-cropped to fill it — so the editor shows the REAL cropped
    // result live (client: "actual crop hoke editor mai dikhna chahiye"), and
    // overlays are positioned on the cropped frame = perfectly WYSIWYG with export.
    final canvasAr = _project!.aspect.ratio ?? nativeAr;
    return Center(
      child: AspectRatio(
        aspectRatio: canvasAr,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            // video→canvas px scale: the cropped frame height maps to the source
            // crop height. With a crop, the visible source height = min(ih, iw/ar).
            final srcW = _vc!.value.size.width == 0 ? 720.0 : _vc!.value.size.width;
            final srcH = _vc!.value.size.height == 0 ? 1280.0 : _vc!.value.size.height;
            final ar = _project!.aspect.ratio;
            final cropSrcH = ar == null ? srcH : (srcH < srcW / ar ? srcH : srcW / ar);
            final scale = h / cropSrcH; // WYSIWYG video→canvas px on the cropped frame
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
                      // Pan/zoom the VIDEO inside the frame (client: "video ko scale +
                      // position karne ka option"). Active only when no overlay is
                      // selected so it never fights an overlay drag. Two-finger pinch
                      // zooms; one/two-finger drag pans. Baked into export identically.
                      onScaleStart: _selected == null ? (d) {
                        _gestureSnapped = false;
                        _gScale = _project!.videoScale;
                        _gDx = _project!.videoDx;
                        _gDy = _project!.videoDy;
                      } : null,
                      onScaleUpdate: _selected == null ? (d) => setState(() {
                        if (d.scale == 1.0 && d.focalPointDelta == Offset.zero) return;
                        if (!_gestureSnapped) { _snapshot(); _gestureSnapped = true; }
                        final ns = (_gScale * d.scale).clamp(1.0, 4.0);
                        _project!.videoScale = ns;
                        // pan is meaningful only when zoomed in; clamp so the frame
                        // never shows empty edges. Range shrinks as (1 - 1/scale)/2.
                        final lim = ((1 - 1 / ns) / 2).clamp(0.0, 0.5);
                        _project!.videoDx = (_gDx + d.focalPointDelta.dx / w).clamp(-lim, lim);
                        _project!.videoDy = (_gDy + d.focalPointDelta.dy / h).clamp(-lim, lim);
                        _hint = 'Video ${(ns * 100).round()}%';
                      }) : null,
                      onScaleEnd: _selected == null ? (_) => setState(() { _gestureSnapped = false; _hint = null; }) : null,
                      // Cover-crop the video into the (possibly cropped) canvas so the
                      // editor shows exactly what exports. ClipRect keeps overflow out.
                      // videoScale/videoDx/videoDy apply the user's pan+zoom on top.
                      // 'fit' letterboxes the whole video onto a bg fill; 'fill'
                      // cover-crops. Scale/reposition apply to both.
                      child: ClipRect(
                        child: ColoredBox(
                          color: _project!.videoFitContain ? Color(_project!.videoBgColor) : Colors.black,
                          child: Transform.translate(
                            offset: Offset(_project!.videoDx * w, _project!.videoDy * h),
                            child: Transform.scale(
                              scale: _project!.videoScale,
                              child: FittedBox(
                                fit: _project!.videoFitContain ? BoxFit.contain : BoxFit.cover,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox(
                                  width: _vc!.value.size.width == 0 ? 720 : _vc!.value.size.width,
                                  height: _vc!.value.size.height == 0 ? 1280 : _vc!.value.size.height,
                                  child: VideoPlayer(_vc!),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ...overlays.map((e) => e.value),
                    if (_snapX) Positioned(left: w / 2 - 0.5, top: 0, bottom: 0, child: const IgnorePointer(child: SizedBox(width: 1, child: ColoredBox(color: Color(0x880E9E6E))))),
                    if (_snapY) Positioned(top: h / 2 - 0.5, left: 0, right: 0, child: const IgnorePointer(child: SizedBox(height: 1, child: ColoredBox(color: Color(0x880E9E6E))))),
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
                    // App watermark (Pro can turn it off via the 'Mark' tool)
                    if (_project!.watermarkOn)
                      Positioned(
                        right: 8, bottom: 8,
                        child: IgnorePointer(child: Text('ClipCart',
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: (h * 0.028).clamp(9, 20),
                            fontWeight: FontWeight.w800, letterSpacing: 0.3,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)]))),
                      ),
                  ],
                );
              },
            );
          },
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
            final op = ((selected ? 1.0 : s.opacityAt(t) * af.opacity) * s.opacity).clamp(0.06, 1.0);
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
              // In trim mode the parent must NOT seek — otherwise a tap/drag near a
              // handle steals the gesture and the trim feels broken.
              onTapDown: _trimMode ? null : (d) => _seek(sec(d.localPosition.dx)),
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
                      gradient: const LinearGradient(colors: [Color(0xFF12B886), Color(0xFF0E9E6E)]),
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
                // playhead across the whole timeline
                Positioned(left: ph.clamp(0, w) - 1, top: -2, bottom: -2, child: IgnorePointer(child: Container(width: 2, color: Colors.white))),
                Positioned(left: ph.clamp(0, w) - 5, top: -6, child: IgnorePointer(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))),
                // trim handles LAST so they sit above the playhead and stay grabbable
                if (_trimMode) ..._trimHandles(x, sec, w, p, dur, trackH),
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

  // Which trim handle is being dragged (null = none). Kept in State so the drag
  // receiver — a STABLE full-width layer that never moves during the gesture — can
  // route absolute finger position to the right edge. A moving GestureDetector (the
  // old per-handle approach) lost the pointer on the rebuild that repositioned it,
  // which is why the client's trim "didn't adjust in one swipe".
  int _trimDrag = 0; // 0 none, 1 start, 2 end
  double _trimStartX = 0; // finger x at drag start (local)
  double _trimStartVal = 0; // trim value at drag start

  List<Widget> _trimHandles(double Function(double) x, double Function(double) sec, double w, EditorProject p, double dur, double trackH) {
    const barW = 18.0;
    final startX = x(p.trimStart).clamp(0.0, w);
    final endX = x(p.outEnd).clamp(0.0, w);

    Widget bar(double leftPx, bool isStart) => Positioned(
          left: (leftPx - barW / 2).clamp(0.0, w - barW),
          top: -6, height: trackH + 12, width: barW,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: (_trimDrag == (isStart ? 1 : 2)) ? Colors.white : _kAccent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4)]),
              child: Icon(Icons.drag_indicator, size: 15, color: (_trimDrag == (isStart ? 1 : 2)) ? _kAccent : Colors.white),
            ),
          ),
        );

    // STABLE full-width drag receiver — spans the whole track, never moves, so the
    // gesture is never lost mid-drag. On start it grabs the nearer handle; on update
    // it maps the finger's ABSOLUTE local x → time (pins the handle to the finger).
    final receiver = Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (d) {
          final fx = d.localPosition.dx;
          _trimDrag = (fx - startX).abs() <= (fx - endX).abs() ? 1 : 2;
          _trimStartX = fx;
          _trimStartVal = _trimDrag == 1 ? p.trimStart : p.outEnd;
          _snapshot();
          HapticFeedback.selectionClick();
          setState(() {});
        },
        onHorizontalDragUpdate: (d) => setState(() {
          final target = (_trimStartVal + sec(d.localPosition.dx - _trimStartX));
          if (_trimDrag == 1) {
            p.trimStart = target.clamp(0, p.outEnd - 0.3);
            _vc?.seekTo(Duration(milliseconds: (p.trimStart * 1000).round()));
          } else if (_trimDrag == 2) {
            p.trimEnd = target.clamp(p.trimStart + 0.3, dur);
            _vc?.seekTo(Duration(milliseconds: (p.outEnd * 1000).round()));
          }
        }),
        onHorizontalDragEnd: (_) { setState(() => _trimDrag = 0); HapticFeedback.selectionClick(); },
        onHorizontalDragCancel: () => setState(() => _trimDrag = 0),
      ),
    );

    Widget bubble(double leftPx, double secVal) => Positioned(
          left: (leftPx - 24).clamp(0.0, w - 48), top: -28,
          child: IgnorePointer(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(8)),
            child: Text(_fmtSec(secVal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
          )),
        );

    return [
      receiver, // must be first so the bars paint on top
      bar(startX, true),
      bar(endX, false),
      if (_trimDrag == 1) bubble(startX, p.trimStart),
      if (_trimDrag == 2) bubble(endX, p.outEnd),
    ];
  }

  String _fmtSec(double s) {
    final m = (s ~/ 60), sec = (s % 60);
    return '${m}:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }

  void _seek(double s) {
    // Clamp tap/drag seeks to the trim window so the preview stays inside the cut.
    final lo = _startMs / 1000.0, hi = _endMs / 1000.0;
    final ms = (s.clamp(lo, hi) * 1000).round();
    _vc!.seekTo(Duration(milliseconds: ms));
  }

  /// "More" tools sheet — the less-frequent add options in a compact grid so the
  /// main toolbar stays short and easy to use (client: editor compact + easy).
  Future<void> _openMoreTools() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(9)))),
            const SizedBox(height: 14),
            const Text('Add more', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
              children: [
                _moreTile(Icons.music_note_rounded, 'Music', () { Navigator.pop(context); _openMusicSheet(); }, on: _project!.musicPath != null),
                _moreTile(Icons.alternate_email_rounded, 'Username', () { Navigator.pop(context); _addUsername(); }),
                _moreTile(Icons.campaign_rounded, 'CTA', () { Navigator.pop(context); _addCta(); }),
                _moreTile(Icons.movie_filter_rounded, 'Outro', () { Navigator.pop(context); _addEndingScreen(); }),
                _moreTile(Icons.palette_rounded, 'Brand', () { Navigator.pop(context); _openBrandKit(); }),
                _moreTile(_project!.watermarkOn ? Icons.branding_watermark : Icons.branding_watermark_outlined, _project!.watermarkOn ? 'Mark on' : 'Mark off', () { Navigator.pop(context); _toggleWatermark(); }, on: _project!.watermarkOn),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _moreTile(IconData icon, String label, VoidCallback onTap, {bool on = false}) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: on ? _kAccent : _kChip, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  // ---------- toolbar (contextual) ----------
  Widget _toolbar() {
    final tools = <Widget>[];
    if (_selected is SubtitleSegment) {
      final s = _selected as SubtitleSegment;
      // Compact: the 6 core text actions. BG/Outline/Align live inside Adjust; the
      // inline bar (while typing) also carries color/size/toggles.
      tools.addAll([
        _tool(Icons.edit, 'Edit', _editSelectedSubtitle),
        _tool(Icons.font_download_rounded, 'Font', _openFontPicker),
        _tool(Icons.format_color_text, 'Color', () => _quickColor(s)),
        _tool(Icons.tune_rounded, 'Adjust', _openStyleSheet),
        _tool(Icons.auto_awesome_rounded, 'Style', _openStyleGallery),
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
        _tool(Icons.tune_rounded, 'Adjust', _openLogoAdjust),
        _tool(Icons.rotate_left, 'Left', () => _mutate(() => _project!.logoRotation -= math.pi / 12)),
        _tool(Icons.rotate_right, 'Right', () => _mutate(() => _project!.logoRotation += math.pi / 12)),
        _tool(Icons.refresh, 'Reset', () => _mutate(() { _project!.logoRotation = 0; _project!.logoScale = 1; })),
        _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
      ]);
    } else {
      final layerCount = _project!.subtitles.length + _project!.stickers.length + (_project!.logoPath != null ? 1 : 0);
      // COMPACT: only the 5 most-used tools stay in the always-visible row (no
      // horizontal scrolling). Everything else (Username/CTA/Outro/Watermark/
      // Brand) lives one tap deeper under "More".
      tools.addAll([
        _tool(Icons.text_fields, 'Text', _addSubtitle),
        _tool(Icons.emoji_emotions_outlined, 'Emoji', _openEmojiPicker),
        _tool(Icons.auto_awesome_motion, 'Sticker', _pickSticker),
        _tool(Icons.image_outlined, 'Logo', _pickLogo),
        _tool(Icons.layers_rounded, layerCount > 0 ? 'Layers ($layerCount)' : 'Layers', _openLayers, active: layerCount > 0),
        _tool(Icons.more_horiz_rounded, 'More', _openMoreTools),
      ]);
    }
    final hasSel = _selected != null;
    // WHITE tool deck — clean light menu with dark items (least spacing, no
    // heading). Selection state ends by tapping the canvas or the small ✓ chip.
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.of(context).viewPadding.bottom),
      child: !hasSel
          // PROJECT tools — 8-tile 4-column grid, compact (short tiles, no scroll)
          ? GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.7,
              children: [
                _projTile(Icons.title_rounded, 'Text', _addSubtitle),
                _projTile(Icons.image_outlined, 'Logo', _pickLogo, onLongPress: _openBrandKit),
                _projTile(Icons.crop_rounded, 'Ratio & trim', _pickAspect),
                _projTile(Icons.emoji_emotions_outlined, 'Stickers', _openEmojiPicker),
                _projTile(Icons.alternate_email_rounded, 'Handle', _addUsername),
                _projTile(Icons.campaign_rounded, 'CTA', _addCta),
                _projTile(Icons.movie_filter_rounded, 'Outro', _addEndingScreen),
                _projTile(Icons.layers_rounded, 'Layers', _openLayers),
              ],
            )
          : _selected is SubtitleSegment
              // §4.1 Text property panel with inline sub-tabs
              ? _textPanel(_selected as SubtitleSegment)
              : Row(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: tools),
                    ),
                  ),
                  // minimal round ✓ to finish editing this layer (deselect)
                  GestureDetector(
                    onTap: () => setState(() => _selected = null),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 40, height: 40,
                      decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                    ),
                  ),
                ]),
    );
  }

  // ================= §4.1 Text property panel (inline sub-tabs) =================
  Widget _textPanel(SubtitleSegment s) {
    const ink = AppColors.ink, mut = AppColors.mut, line = AppColors.line, brand = AppColors.brand;
    const tile = Color(0xFFF3F3F1);
    Widget subTab(String label, int i) {
      final on = _textTab == i;
      return GestureDetector(
        onTap: () => setState(() => _textTab = i),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? ink : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: on ? null : Border.all(color: line),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, color: on ? Colors.white : ink, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      // header: sub-tab pills + round ✓ done
      Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              subTab('Style', 0), const SizedBox(width: 7),
              subTab('Advanced', 1), const SizedBox(width: 7),
              subTab('Timing', 2), const SizedBox(width: 7),
              subTab('Presets', 3),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _selected = null),
          child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: brand, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 18, color: Colors.white)),
        ),
      ]),
      const SizedBox(height: 12),
      // sub-tab content (fixed-ish height, scrolls if needed)
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 210),
        child: SingleChildScrollView(
          child: switch (_textTab) {
            0 => _textStyle(s, ink, mut, tile, line, brand),
            1 => _textAdvanced(s, mut, tile, line, brand),
            2 => _textTiming(s, ink, mut, tile, line, brand),
            _ => _textPresetsTab(s, ink, tile, line, brand),
          },
        ),
      ),
      const SizedBox(height: 10),
      // footer: Duplicate · Hide · Delete
      Row(children: [
        Expanded(child: _textFootBtn('Duplicate', tile, line, ink, _duplicateSelected)),
        const SizedBox(width: 7),
        Expanded(child: _textFootBtn(s.hidden ? 'Show' : 'Hide', tile, line, ink, () => _mutate(() => s.hidden = !s.hidden))),
        const SizedBox(width: 7),
        Expanded(child: _textFootBtn('Delete', AppColors.errBg, AppColors.errBg, AppColors.err, _deleteSelected)),
      ]),
    ]);
  }

  Widget _textFootBtn(String label, Color bg, Color border, Color fg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: border)),
          child: Text(label, style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500)),
        ),
      );

  // light slider row (dark text on the white deck)
  Widget _lightSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {required String display, double labelW = 66}) => Row(children: [
        SizedBox(width: labelW, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.mut))),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(activeTrackColor: AppColors.brand, thumbColor: AppColors.brand, inactiveTrackColor: Color(0xFFE3E3DF), trackHeight: 3, overlayShape: RoundSliderOverlayShape(overlayRadius: 14)),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: (_) => _gestureSnapped = false),
          ),
        ),
        SizedBox(width: 44, child: Text(display, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 11, color: AppColors.ink))),
      ]);

  // ---- Style tab: font · B/I · size · colours · align ----
  Widget _textStyle(SubtitleSegment s, Color ink, Color mut, Color tile, Color line, Color brand) {
    Widget bi(String t, bool on, VoidCallback tap, {bool italic = false}) => GestureDetector(
          onTap: tap,
          child: Container(
            width: 44, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? AppColors.brandSurface : tile, borderRadius: BorderRadius.circular(9), border: Border.all(color: on ? brand : line)),
            child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontStyle: italic ? FontStyle.italic : FontStyle.normal, color: on ? brand : ink)),
          ),
        );
    const swatches = [0xFFFFFFFF, 0xFF000000, 0xFF0E9E6E, 0xFFD89A3C, 0xFFDC2626, 0xFF2D7FF9, 0xFFFFC400, 0xFF9B5DE5];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: GestureDetector(onTap: _openFontPicker, child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 11), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(9), border: Border.all(color: line)), child: Row(children: [Text(s.fontFamily ?? 'Default', style: TextStyle(fontFamily: s.fontFamily, fontSize: 13, color: ink)), const Spacer(), const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.mut)])))),
        const SizedBox(width: 7),
        bi('B', s.bold, () => _mutate(() => s.bold = !s.bold)),
        const SizedBox(width: 7),
        bi('I', s.italic, () => _mutate(() => s.italic = !s.italic), italic: true),
      ]),
      const SizedBox(height: 11),
      _lightSlider('Size', s.scale, 0.4, 4.0, (v) => setState(() { if (!_gestureSnapped) { _snapshot(); _gestureSnapped = true; } s.scale = v; }), display: '${(s.fontSize * s.scale).round()}', labelW: 40),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 40, child: Text('Colour', style: TextStyle(fontSize: 12, color: AppColors.mut))),
        Expanded(child: SizedBox(height: 30, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in swatches) Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => _mutate(() => s.color = c), child: Container(width: 30, height: 30, decoration: BoxDecoration(color: Color(c), borderRadius: BorderRadius.circular(8), border: Border.all(color: s.color == c ? brand : line, width: s.color == c ? 2 : 1))))),
          GestureDetector(onTap: () => _quickColor(s), child: Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: line)), child: const Icon(Icons.add_rounded, size: 16, color: AppColors.mut))),
        ]))),
      ]),
      const SizedBox(height: 11),
      Row(children: [
        for (final a in TextAlignH.values) ...[
          Expanded(child: GestureDetector(
            onTap: () => _mutate(() => s.align = a),
            child: Container(height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: s.align == a ? AppColors.brandSurface : tile, borderRadius: BorderRadius.circular(9), border: Border.all(color: s.align == a ? brand : line)), child: Icon(_alignIcon(a), size: 18, color: s.align == a ? brand : ink)),
          )),
          if (a != TextAlignH.right) const SizedBox(width: 7),
        ],
      ]),
    ]);
  }

  // ---- Advanced tab: stroke · shadow(toggle) · box(toggle) · opacity · letter · line · rotation ----
  Widget _textAdvanced(SubtitleSegment s, Color mut, Color tile, Color line, Color brand) {
    void snap() { if (!_gestureSnapped) { _snapshot(); _gestureSnapped = true; } }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lightSlider('Stroke', s.strokeWidth, 0, 12, (v) => setState(() { snap(); s.strokeWidth = v; }), display: s.strokeWidth.toStringAsFixed(0)),
      const SizedBox(height: 8),
      _lightSlider('Opacity', s.opacity, 0.1, 1.0, (v) => setState(() { snap(); s.opacity = v; }), display: '${(s.opacity * 100).round()}%'),
      const SizedBox(height: 8),
      _lightSlider('Letter', s.letterSpacing, -3, 12, (v) => setState(() { snap(); s.letterSpacing = v; }), display: s.letterSpacing.toStringAsFixed(1)),
      const SizedBox(height: 8),
      _lightSlider('Line', s.lineHeight, 0.8, 2.0, (v) => setState(() { snap(); s.lineHeight = v; }), display: s.lineHeight.toStringAsFixed(2)),
      const SizedBox(height: 11),
      Row(children: [
        Expanded(child: _textFootBtn(s.shadow ? 'Shadow ✓' : 'Shadow', s.shadow ? AppColors.brandSurface : tile, s.shadow ? brand : line, s.shadow ? brand : AppColors.ink, () => _mutate(() => s.shadow = !s.shadow))),
        const SizedBox(width: 7),
        Expanded(child: _textFootBtn(s.bgEnabled ? 'Box ✓' : 'Box', s.bgEnabled ? AppColors.brandSurface : tile, s.bgEnabled ? brand : line, s.bgEnabled ? brand : AppColors.ink, () => _mutate(() => s.bgEnabled = !s.bgEnabled))),
        const SizedBox(width: 7),
        Expanded(child: _NumFieldLight(label: 'X %', value: s.dx * 100, min: 0, max: 100, onChanged: (v) => _mutate(() => s.dx = (v / 100).clamp(0.0, 1.0)))),
        const SizedBox(width: 7),
        Expanded(child: _NumFieldLight(label: 'Y %', value: s.dy * 100, min: 0, max: 100, onChanged: (v) => _mutate(() => s.dy = (v / 100).clamp(0.0, 1.0)))),
      ]),
    ]);
  }

  // ---- Timing tab: start/end fields + animation quick-select ----
  Widget _textTiming(SubtitleSegment s, Color ink, Color mut, Color tile, Color line, Color brand) {
    final dz = _duration <= 0 ? 9999.0 : _duration;
    Widget anim(String label, OverlayAnim a) => Expanded(
          child: GestureDetector(
            onTap: () => _mutate(() => s.anim = a),
            child: Container(height: 38, alignment: Alignment.center, decoration: BoxDecoration(color: s.anim == a ? AppColors.brandSurface : tile, borderRadius: BorderRadius.circular(9), border: Border.all(color: s.anim == a ? brand : line)), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: s.anim == a ? brand : ink))),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _NumFieldLight(label: 'Starts (s)', value: s.start, min: 0, max: dz, decimals: 1, onChanged: (v) => _mutate(() => s.start = v.clamp(0.0, s.end - 0.2)))),
        const SizedBox(width: 9),
        Expanded(child: _NumFieldLight(label: 'Ends (s)', value: s.end, min: 0, max: dz, decimals: 1, onChanged: (v) => _mutate(() => s.end = v.clamp(s.start + 0.2, dz)))),
      ]),
      const SizedBox(height: 11),
      Row(children: [
        anim('None', OverlayAnim.none), const SizedBox(width: 7),
        anim('Fade', OverlayAnim.fade), const SizedBox(width: 7),
        anim('Pop', OverlayAnim.popIn), const SizedBox(width: 7),
        anim('Type', OverlayAnim.typewriter),
      ]),
    ]);
  }

  // ---- Presets tab: horizontal preset strip ----
  Widget _textPresetsTab(SubtitleSegment s, Color ink, Color tile, Color line, Color brand) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final tpl in _styleTemplates)
        GestureDetector(
          onTap: () => _applyStyle(s, tpl),
          child: Container(
            width: 100, height: 52, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (tpl['bg'] as bool) ? Color(tpl['bgc'] as int) : tile,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: s.fontFamily == tpl['font'] ? brand : line, width: s.fontFamily == tpl['font'] ? 2 : 1),
            ),
            child: Text(tpl['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: tpl['font'] as String?, color: Color(tpl['color'] as int), fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
    ]);
  }

  /// A 64px project-tool tile (§4.1 PROJECT grid): icon over label on a dark tile.
  Widget _projTile(IconData icon, String label, VoidCallback onTap, {bool on = false, VoidCallback? onLongPress}) => GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: on ? AppColors.brandSurface : const Color(0xFFF3F3F1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: on ? AppColors.brand : AppColors.line),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: on ? AppColors.brand : AppColors.ink, size: 18),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? AppColors.brand : AppColors.ink, fontSize: 10.5, fontWeight: FontWeight.w500)),
          ]),
        ),
      );

  IconData _alignIcon(TextAlignH a) => switch (a) {
        TextAlignH.left => Icons.format_align_left,
        TextAlignH.center => Icons.format_align_center,
        TextAlignH.right => Icons.format_align_right,
      };

  void _quickColor(SubtitleSegment s) {
    const swatches = [0xFFFFFFFF, 0xFF000000, 0xFF0E9E6E, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFF12B886, 0xFF9B5DE5, 0xFF12B886, 0xFF0E9E6E, 0xFF00D1B2, 0xFF17131F];
    showModalBottomSheet(
      context: context,
      backgroundColor: _kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Text color', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final c in swatches)
                  GestureDetector(
                    onTap: () { _mutate(() => s.color = c); setSheet(() {}); },
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == s.color ? _kAccent : Colors.white24, width: c == s.color ? 3 : 1))),
                  ),
              ]),
              const SizedBox(height: 18),
              // Hex code entry (client: "color code daalne ka option ho to sahi rahega")
              _HexColorField(
                value: s.color,
                onChanged: (c) { _mutate(() => s.color = c); setSheet(() {}); },
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _fitChip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: on ? _kAccent : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? _kAccent : Colors.white12),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      );

  Widget _bgSwatch(int color, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle, border: Border.all(color: on ? _kAccent : Colors.white24, width: on ? 2.5 : 1)),
        ),
      );

  Future<void> _pickAspect() async {
    final p = _project!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        var vidSnapped = false;
        void snapVid() { if (!vidSnapped) { _snapshot(); vidSnapped = true; } }
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Ratio & fit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Pick a ratio, then pinch/drag the video to scale & position it.', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
                const SizedBox(height: 14),
                // Ratio pills
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final opt in AspectOption.all)
                    GestureDetector(
                      onTap: () { _mutate(() => p.aspect = opt); setSheet(() {}); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: opt == p.aspect ? _kAccent : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: opt == p.aspect ? _kAccent : Colors.white12),
                        ),
                        child: Text(opt.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                // Fill / Fit — Fit letterboxes onto a black or white background.
                Row(children: [
                  _fitChip('Fill', !p.videoFitContain, () { _mutate(() => p.videoFitContain = false); setSheet(() {}); }),
                  const SizedBox(width: 10),
                  _fitChip('Fit', p.videoFitContain, () { _mutate(() => p.videoFitContain = true); setSheet(() {}); }),
                  const Spacer(),
                  if (p.videoFitContain) ...[
                    const Text('BG', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    _bgSwatch(0xFF000000, p.videoBgColor == 0xFF000000, () { _mutate(() => p.videoBgColor = 0xFF000000); setSheet(() {}); }),
                    const SizedBox(width: 8),
                    _bgSwatch(0xFFFFFFFF, p.videoBgColor == 0xFFFFFFFF, () { _mutate(() => p.videoBgColor = 0xFFFFFFFF); setSheet(() {}); }),
                  ],
                ]),
                const SizedBox(height: 18),
                // Video scale + reposition (pan is easiest by dragging on the canvas)
                _fadeRowGeneric('Video zoom', p.videoScale, 1.0, 4.0, (v) {
                  snapVid();
                  setSheet(() {
                    p.videoScale = v;
                    final lim = ((1 - 1 / v) / 2).clamp(0.0, 0.5);
                    p.videoDx = p.videoDx.clamp(-lim, lim);
                    p.videoDy = p.videoDy.clamp(-lim, lim);
                    setState(() {});
                  });
                }, suffix: 'x'),
                if (p.videoScale > 1.001 || p.videoDx.abs() > 0.001 || p.videoDy.abs() > 0.001) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () { _mutate(() { p.videoScale = 1.0; p.videoDx = 0; p.videoDy = 0; }); setSheet(() {}); },
                      icon: const Icon(Icons.restart_alt_rounded, size: 18, color: _kAccent),
                      label: const Text('Reset video position', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', icon: Icons.check, onPressed: () => Navigator.pop(context))),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool danger = false, bool active = false}) {
    final c = danger ? AppColors.err : (active ? AppColors.brand : AppColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: active ? AppColors.brandSurface : const Color(0xFFF3F3F1),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: active ? AppColors.brand : AppColors.line),
            ),
            child: Icon(icon, color: c, size: 20),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
    );
  }
}

/// A hex color code input (e.g. `#0E9E6E`) with a live swatch. Lets the user
/// type any exact color — client asked for a "color code daalne ka option".
class _HexColorField extends StatefulWidget {
  const _HexColorField({required this.value, required this.onChanged});
  final int value; // ARGB
  final ValueChanged<int> onChanged;

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: _toHex(widget.value));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static String _toHex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  int? _parse(String raw) {
    var h = raw.trim().replaceAll('#', '').replaceAll('0x', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join(); // #abc → #aabbcc
    if (h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return 0xFF000000 | v;
    }
    if (h.length == 8) return int.tryParse(h, radix: 16);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _parse(_ctl.text) ?? widget.value;
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: Color(preview), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: TextField(
          controller: _ctl,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'monospace', letterSpacing: 1),
          cursorColor: _kAccent,
          textCapitalization: TextCapitalization.characters,
          onChanged: (v) {
            final c = _parse(v);
            setState(() {});
            if (c != null) widget.onChanged(c);
          },
          decoration: InputDecoration(
            prefixText: '',
            hintText: '#0E9E6E',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true, fillColor: Colors.white.withOpacity(0.06), isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ),
    ]);
  }
}

/// A compact numeric entry field for the editor (exact size / X / Y / scale).
/// Holds its own controller so typing is stable; commits on submit or focus loss.
class _NumField extends StatefulWidget {
  const _NumField({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.decimals = 0});
  final String label;
  final double value, min, max;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c;
  late final FocusNode _f;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _fmt(widget.value));
    _f = FocusNode()..addListener(() { if (!_f.hasFocus) _commit(); });
  }

  @override
  void didUpdateWidget(covariant _NumField old) {
    super.didUpdateWidget(old);
    // reflect external changes (slider/drag) only while not being edited
    if (!_f.hasFocus && (widget.value - old.value).abs() > 0.001) _c.text = _fmt(widget.value);
  }

  String _fmt(double v) => widget.decimals == 0 ? v.round().toString() : v.toStringAsFixed(widget.decimals);

  void _commit() {
    final v = double.tryParse(_c.text.trim());
    if (v != null) {
      final clamped = v.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      _c.text = _fmt(clamped);
    } else {
      _c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: _c,
        focusNode: _f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, fontFamily: 'IBMPlexMono'),
        cursorColor: _kAccent,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide.none),
        ),
      ),
    ]);
  }
}

/// Light-styled numeric field for the white text panel (dark text on light).
class _NumFieldLight extends StatefulWidget {
  const _NumFieldLight({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.decimals = 0});
  final String label;
  final double value, min, max;
  final int decimals;
  final ValueChanged<double> onChanged;
  @override
  State<_NumFieldLight> createState() => _NumFieldLightState();
}

class _NumFieldLightState extends State<_NumFieldLight> {
  late final TextEditingController _c;
  late final FocusNode _f;
  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _fmt(widget.value));
    _f = FocusNode()..addListener(() { if (!_f.hasFocus) _commit(); });
  }
  @override
  void didUpdateWidget(covariant _NumFieldLight old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && (widget.value - old.value).abs() > 0.001) _c.text = _fmt(widget.value);
  }
  String _fmt(double v) => widget.decimals == 0 ? v.round().toString() : v.toStringAsFixed(widget.decimals);
  void _commit() {
    final v = double.tryParse(_c.text.trim());
    if (v != null) { final cl = v.clamp(widget.min, widget.max); widget.onChanged(cl); _c.text = _fmt(cl); }
    else { _c.text = _fmt(widget.value); }
  }
  @override
  void dispose() { _c.dispose(); _f.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(color: AppColors.mut, fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        controller: _c, focusNode: _f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'IBMPlexMono'),
        cursorColor: AppColors.brand,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          filled: true, fillColor: const Color(0xFFF3F3F1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.brand)),
        ),
      ),
    ]);
  }
}
