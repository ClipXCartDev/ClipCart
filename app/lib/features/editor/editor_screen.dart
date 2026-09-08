import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/runtime_config.dart';
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

// Editor warm-paper light chrome (v3 spec §12) — the app's warm-paper theme.
const _kBg = AppColors.bg;            // #FCFAF6 canvas backdrop / top bar
const _kPanel = AppColors.surfaceHover; // #F7F5F1 control panels / bottom sheets
const _kChip = AppColors.bgAlt;       // #EFECE5 raised tool tiles / fields
const _kAccent = AppColors.brand;     // #684FC8 brand primary
// Cover-crop overscan (matches ExportService._overscan) — a hair of zoom on a
// cropped frame hides the 1px seam that showed on the aspect-crop edge.
const double _kOverscan = 1.012;

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
  int _textTab = 0; // client §3 text panel sub-tab: 0 Font · 1 Styling · 2 Advance

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

  /// How far the video may pan (fraction of frame) at a given scale. When zoomed
  /// in (>1) it's the croppable margin; when scaled DOWN (<1) it's the empty gap
  /// the video can travel within the frame before hitting an edge.
  double _videoPanLimit(double s) =>
      (s >= 1.0 ? (1 - 1 / s) / 2 : (1 - s) / 2).clamp(0.0, 0.5);

  /// Video display scale for the preview — adds cover overscan on a cropped frame
  /// (only when filling and not scaling down) so the editor matches the export.
  double _effVideoScale() {
    final vz = _project!.videoScale;
    final cropped = _project!.aspect.ratio != null;
    if (cropped && !_project!.videoFitContain && vz >= 1.0) return vz * _kOverscan;
    return vz;
  }

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
      final store = context.read<ProjectStore>();
      final clipId = widget.clip!.id;
      // ONE saved draft per clip (no duplicates): a stable id, resume any existing
      // draft, and collapse older duplicate drafts for the same clip.
      final stableId = 'clip_$clipId';
      List<SavedProject> existing = const [];
      try { existing = (await store.list()).where((p) => p.clipId == clipId).toList(); } catch (_) {}
      // attempt 0 uses any cache; attempt 1 forces a fresh re-download (recovers
      // from a corrupt/partial cache or a transient failure).
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final path = await cs.editClipFile(clipId, fresh: attempt > 0);
          await _load(path);
          if (existing.isNotEmpty) {
            // Continue the existing draft (it already holds any creator overlays
            // the customer was editing, plus their changes).
            final restored = existing.first.toProject(); // list is newest-first
            restored.baseClipPath = _project!.baseClipPath;
            restored.defaultFontPath = _project!.defaultFontPath;
            restored.duration = _project!.duration;
            setState(() => _project = restored);
          } else if (widget.clip!.overlays != null) {
            // First time editing this clip: load the creator's overlays over the
            // raw video — rendered, not burned (the customer edits; export burns).
            await _applyCreatorOverlays(widget.clip!.overlays!);
          }
          _projectId = stableId; // all saves target the one stable file for this clip
          await _saveProject();  // persist under the stable id before pruning
          // collapse older duplicate drafts for this clip
          for (final p in existing) {
            if (p.id != stableId) { try { await store.delete(p.id); } catch (_) {} }
          }
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
      // one stable file per clip → editing the same clip never duplicates.
      _projectId ??= widget.clip != null ? 'clip_${widget.clip!.id}' : 'proj_${DateTime.now().microsecondsSinceEpoch}';
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

  /// Apply creator-authored overlays (snapshot-format JSON) onto the freshly
  /// loaded blank project. Subtitles/stickers are pure data; a `logoUrl` is
  /// downloaded to a local file first so the logo can render.
  Future<void> _applyCreatorOverlays(Map<String, dynamic> overlays) async {
    final p = _project;
    if (p == null) return;
    final data = Map<String, dynamic>.from(overlays);
    final logoUrl = (data['logoUrl'] ?? data['logo_url']) as String?;
    if (logoUrl != null && logoUrl.isNotEmpty && (data['logoPath'] == null)) {
      try {
        final dir = await getTemporaryDirectory();
        final file = '${dir.path}/creatorlogo_${logoUrl.hashCode}.png';
        if (!File(file).existsSync()) {
          await Dio().download(RuntimeConfig.absolute(logoUrl), file);
        }
        data['logoPath'] = file;
      } catch (_) {/* logo download failed — keep other overlays */}
    }
    // restore() non-null-asserts a few keys; supply safe defaults for any the
    // creator payload omits (mirrors EditorProject.fromProjectJson).
    final merged = <String, dynamic>{
      'trimStart': 0.0, 'logoDx': 0.85, 'logoDy': 0.10, 'logoScale': 1.0,
      'logoRotation': 0.0, 'aspect': 0, 'subs': <dynamic>[],
      ...data,
    };
    try {
      p.restore(merged);
      if (mounted) setState(() { _undo.clear(); _redo.clear(); });
    } catch (_) {/* malformed overlays — leave the canvas blank */}
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
    final e0 = (dz <= 0 || dz - s0 < 0.5) ? s0 + 3 : (s0 + 3).clamp(s0 + 0.5, dz);
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: _Grabber()),
                Row(children: [
                  const Text('Font', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final f = await fs.uploadFont();
                      if (f != null) { _mutate(() { s.fontFamily = f.family; s.fontFilePath = f.path; }); setSheet(() {}); }
                    },
                    icon: const Icon(Icons.add, size: 18, color: _kAccent),
                    label: const Text('Import', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600)),
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
          border: Border.all(color: selected ? _kAccent : AppColors.line, width: selected ? 2 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Aa', style: TextStyle(fontFamily: family, color: AppColors.ink, fontSize: 26, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: selected ? _kAccent : AppColors.inkMuted, fontSize: 10, fontWeight: FontWeight.w500)),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: _Grabber()),
                const Text('Adjust', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
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
                Align(alignment: Alignment.centerLeft, child: Text('Text shows from ${s.start.toStringAsFixed(1)}s to ${s.end.toStringAsFixed(1)}s', style: const TextStyle(color: AppColors.inkMuted, fontSize: 11, fontFamily: 'IBMPlexMono'))),
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
          decoration: BoxDecoration(color: on ? AppColors.brandTint : _kChip, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? _kAccent : AppColors.line)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: on ? _kAccent : AppColors.ink, fontSize: 18, fontWeight: FontWeight.w600, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
        ),
      );

  Widget _adjIconToggle(IconData i, String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40, padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: on ? AppColors.brandTint : _kChip, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? _kAccent : AppColors.line)),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16, color: on ? _kAccent : AppColors.ink), const SizedBox(width: 6), Text(label, style: TextStyle(color: on ? _kAccent : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13))]),
        ),
      );

  Widget _fadeRowGeneric(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = ''}) => Row(children: [
        SizedBox(width: 108, child: Text(label, style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w500, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(activeTrackColor: _kAccent, thumbColor: Colors.white, inactiveTrackColor: AppColors.line, trackHeight: 4, overlayColor: _kAccent.withOpacity(0.15), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5, elevation: 1.5)),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 46, child: Text('${value.toStringAsFixed(1)}$suffix', textAlign: TextAlign.right, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 12, fontFamily: 'IBMPlexMono'))),
      ]);

  // ---------- layers panel (CapCut-style: reorder z, select, hide, delete) ----------
  void _openLayers({bool startInSelect = false}) {
    // Multi-select (§4.0 feedback 5): a select mode with per-row checks + batch
    // delete/hide. State lives here so it persists across StatefulBuilder rebuilds.
    // [startInSelect] opens straight into select mode (transport-row "Select").
    final sel = <Object>{};
    var selectMode = startInSelect;
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
          final hidden = _layerHidden(it);
          final locked = _layerLocked(it);
          final selected = isLogo ? _selected == 'logo' : identical(_selected, it);
          return Container(
            key: isLogo ? const ValueKey('logo') : ObjectKey(it),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandTint : _kChip,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _kAccent : AppColors.line),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              horizontalTitleGap: 10,
              leading: selectMode
                  ? Icon(sel.contains(it) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: sel.contains(it) ? _kAccent : AppColors.inkFaint, size: 26)
                  : _layerThumb(it, size: 38, selected: selected),
              title: Text(_layerName(it),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: hidden ? AppColors.inkFaint : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(_layerDurLabel(it),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkFaint, fontSize: 11, fontFamily: 'IBMPlexMono')),
              onTap: () {
                if (selectMode) {
                  setSheet(() => sel.contains(it) ? sel.remove(it) : sel.add(it));
                  return;
                }
                setState(() => _selected = isLogo ? 'logo' : it);
                Navigator.pop(context);
              },
              trailing: selectMode ? null : Row(mainAxisSize: MainAxisSize.min, children: [
                _layerIconBtn(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, AppColors.inkMuted, () { _toggleVis(it); setSheet(() {}); }),
                _layerIconBtn(locked ? Icons.lock_rounded : Icons.lock_open_rounded, locked ? _kAccent : AppColors.inkMuted, () { _toggleLock(it); setSheet(() {}); }),
                if (!isLogo) _layerIconBtn(Icons.copy_rounded, AppColors.inkMuted, () { _duplicateLayer(it); setSheet(() {}); }),
                _layerIconBtn(Icons.delete_outline_rounded, AppColors.err, () { _deleteLayer(it); setSheet(() {}); }),
                const SizedBox(width: 1),
                const Icon(Icons.drag_handle_rounded, color: AppColors.chevron, size: 20),
              ]),
            ),
          );
        }

        return Container(
          decoration: const BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(14, 10, 14, 16 + MediaQuery.of(context).viewPadding.bottom),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: _Grabber()),
            Row(children: [
              const Text('Layers', style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (ordered.isNotEmpty)
                GestureDetector(
                  onTap: () => setSheet(() { selectMode = !selectMode; sel.clear(); }),
                  child: Text(selectMode ? 'Done' : 'Select', style: const TextStyle(color: _kAccent, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
            ]),
            // ── Add layer (relocated from the bottom toolbar per client §4) ──
            if (!selectMode) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 78,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    for (final t in <(IconData, String, VoidCallback, bool)>[
                      (Icons.title_rounded, 'Text', () { Navigator.pop(context); _addSubtitle(); }, false),
                      (Icons.image_outlined, 'Logo', () { Navigator.pop(context); _pickLogo(); }, false),
                      (Icons.emoji_emotions_outlined, 'Emoji', () { Navigator.pop(context); _openEmojiPicker(); }, false),
                      (Icons.auto_awesome_motion, 'Sticker', () { Navigator.pop(context); _pickSticker(); }, false),
                      (Icons.alternate_email_rounded, 'Handle', () { Navigator.pop(context); _addUsername(); }, false),
                      (Icons.campaign_rounded, 'CTA', () { Navigator.pop(context); _addCta(); }, false),
                      (Icons.movie_filter_rounded, 'Outro', () { Navigator.pop(context); _addEndingScreen(); }, false),
                      (Icons.palette_rounded, 'Brand', () { Navigator.pop(context); _openBrandKit(); }, false),
                      (Icons.branding_watermark_outlined, _project!.watermarkOn ? 'Mark on' : 'Mark off', () { Navigator.pop(context); _toggleWatermark(); }, _project!.watermarkOn),
                    ])
                      Padding(padding: const EdgeInsets.only(right: 14), child: _addTile(t.$1, t.$2, t.$3, on: t.$4)),
                  ],
                ),
              ),
              const Divider(height: 20, color: AppColors.line),
            ],
            const SizedBox(height: 8),
            if (ordered.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No layers yet.\nAdd text or a logo.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkMuted))))
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
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.visibility_off_rounded, size: 18),
                  label: const Text('Hide/Show'),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    _snapshot();
                    setState(() {
                      for (final it in sel) {
                        if (_layerLocked(it)) continue; // locked layers are protected from delete
                        if (it is SubtitleSegment) _project!.subtitles.remove(it);
                        else if (it is StickerOverlay) _project!.stickers.remove(it);
                        else _project!.logoPath = null;
                        if (identical(_selected, it)) _selected = null;
                      }
                    });
                    setSheet(() { sel.clear(); selectMode = false; });
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.errText, side: const BorderSide(color: AppColors.errBg), padding: const EdgeInsets.symmetric(vertical: 12)),
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
                Text('Aa', style: TextStyle(fontFamily: s?.fontFamily, color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 3),
                const Icon(Icons.expand_more_rounded, size: 13, color: AppColors.inkFaint),
              ]),
            ),
            _chipDivider(),
            // size steppers (client asked for text size adjust while typing)
            _ghostChip(
              onTap: () { if (s != null) setState(() => s.scale = (s.scale - 0.15).clamp(0.4, 4.0)); },
              child: const Text('A−', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            _ghostChip(
              onTap: () { if (s != null) setState(() => s.scale = (s.scale + 0.15).clamp(0.4, 4.0)); },
              child: const Text('A+', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 15)),
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
                    decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: s?.color == c ? _kAccent : AppColors.line, width: s?.color == c ? 2.5 : 1)),
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
              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 14),
              cursorColor: _kAccent,
              onChanged: (v) => setState(() => s?.text = v),
              decoration: InputDecoration(
                hintText: 'Type your text…  (Enter = new line)',
                hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 14),
                filled: true, fillColor: AppColors.surface, isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _doneTyping,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(10)),
              child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: _Grabber()),
                const Text('Music', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
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
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(vertical: 13)),
                      icon: const Icon(Icons.library_music_rounded, size: 18),
                      label: const Text('Import from device'),
                    ),
                  )
                else ...[
                  // track card
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
                    child: Row(children: [
                      Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.goldBg, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.music_note_rounded, color: AppColors.goldText, size: 20)),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.musicPath!.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        const Text('from your device', style: TextStyle(color: AppColors.inkMuted, fontSize: 11, fontFamily: 'IBMPlexMono')),
                      ])),
                      GestureDetector(
                        onTap: () async {
                          final res = await FilePicker.platform.pickFiles(type: FileType.audio);
                          if (res != null && res.files.single.path != null) { _mutate(() => p.musicPath = res.files.single.path); setSheet(() {}); }
                        },
                        child: const Text('Replace', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _fadeRowGeneric('Music', p.musicVolume, 0, 1, (v) { snapVol(); setSheet(() { p.musicVolume = v; setState(() {}); }); }, suffix: ''),
                  _fadeRowGeneric('Clip audio', p.originalVolume, 0, 1, (v) { snapVol(); setSheet(() { p.originalVolume = v; setState(() {}); }); }, suffix: ''),
                  _fadeRowGeneric('Start at', p.musicStart, 0, 60, (v) { snapVol(); setSheet(() { p.musicStart = v; setState(() {}); }); }, suffix: 's'),
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerLeft, child: Text('Starts at ${fmtStart(p.musicStart)}', style: const TextStyle(color: AppColors.inkMuted, fontSize: 11, fontFamily: 'IBMPlexMono'))),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Text('Fade out at the end', style: TextStyle(color: AppColors.ink, fontSize: 13)),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: _Grabber()),
              const Text('Logo position & size', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
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
              const Text('Or just drag the logo on the canvas.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12)),
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
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: _Grabber()),
              Row(children: [
                const Icon(Icons.palette_rounded, color: _kAccent, size: 20),
                const SizedBox(width: 8),
                const Text('Brand Kit', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                TextButton(onPressed: () async { await bk.saveKit(kit); if (context.mounted) Navigator.pop(context); }, child: const Text('Save', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600))),
              ]),
              Text('Save your colors, font & logo once — apply to any clip in a tap.', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
              const SizedBox(height: 16),
              // palette
              const Text('Colors', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < kit.colors.length; i++)
                  GestureDetector(
                    onTap: () async {
                      final c = await _pickBrandColor(kit.colors[i]);
                      if (c != null) setSheet(() => kit.colors[i] = c);
                    },
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(kit.colors[i]), shape: BoxShape.circle, border: Border.all(color: i == 0 ? _kAccent : AppColors.line, width: i == 0 ? 3 : 1))),
                  ),
                if (kit.colors.length < 4)
                  GestureDetector(
                    onTap: () => setSheet(() => kit.colors.add(0xFF12B76A)),
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: _kChip, shape: BoxShape.circle, border: Border.all(color: AppColors.line)), child: const Icon(Icons.add, color: AppColors.inkMuted, size: 20)),
                  ),
              ]),
              const SizedBox(height: 16),
              // font
              Row(children: [
                const Text('Font', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 12.5)),
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
                            decoration: BoxDecoration(color: kit.fontFamily == f.family ? _kAccent : _kChip, borderRadius: BorderRadius.circular(9), border: Border.all(color: kit.fontFamily == f.family ? _kAccent : AppColors.line)),
                            child: Text('Aa', style: TextStyle(fontFamily: f.family, color: kit.fontFamily == f.family ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // logo
              Row(children: [
                const Text('Logo', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 12.5)),
                const SizedBox(width: 12),
                if (kit.logoPath != null) ...[
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.antiAlias, child: Image.file(File(kit.logoPath!), fit: BoxFit.contain)),
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
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: const BorderSide(color: AppColors.line)),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(spacing: 14, runSpacing: 14, children: [
            for (final c in palette)
              GestureDetector(
                onTap: () => Navigator.pop(context, c),
                child: Container(width: 42, height: 42, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == current ? _kAccent : AppColors.line, width: c == current ? 3 : 1))),
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brand applied')));
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
          color: (tpl['bg'] as bool) ? Color(tpl['bgc'] as int) : AppColors.bgAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.fontFamily == tpl['font'] ? _kAccent : AppColors.line, width: s.fontFamily == tpl['font'] ? 2 : 1),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: _Grabber()),
              const Text('Styles', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 4),
              Text('One-tap caption look. Long-press a saved style to remove.', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
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
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                        alignment: Alignment.center,
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_rounded, color: _kAccent, size: 24),
                          SizedBox(height: 3),
                          Text('Save current', style: TextStyle(color: AppColors.inkMuted, fontSize: 10, fontWeight: FontWeight.w600)),
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
        backgroundColor: AppColors.surface,
        title: const Text('Save style', style: TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: ctl, autofocus: true,
          style: const TextStyle(color: AppColors.ink),
          cursorColor: _kAccent,
          decoration: const InputDecoration(hintText: 'Style name', hintStyle: TextStyle(color: AppColors.inkFaint), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.line))),
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
          decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
          child: child,
        ),
      );

  Widget _chipDivider() => Container(width: 1, height: 18, margin: const EdgeInsets.only(right: 9, top: 6), color: AppColors.line);

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
          color: bg ? Color(p['bgc'] as int) : _kChip,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
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
          decoration: BoxDecoration(color: on ? _kAccent : _kChip, borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? _kAccent : AppColors.line)),
          child: Icon(i, size: 15, color: on ? Colors.white : AppColors.ink),
        ),
      );

  void _duplicateSelected() {
    _snapshot();
    if (_selected is SubtitleSegment) {
      final s = (_selected as SubtitleSegment).copy();
      s.dy = (s.dy + 0.06).clamp(0.05, 0.95);
      s.z = _topZ(); // paint the copy on top (stable z, matches export ordering)
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
    final sel = _selected;
    if (sel != null && _layerLocked(sel)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layer is locked — unlock it first')));
      return;
    }
    _snapshot();
    setState(() {
      if (_selected is SubtitleSegment) _project!.subtitles.remove(_selected);
      if (_selected is StickerOverlay) _project!.stickers.remove(_selected);
      if (_selected == 'logo') _project!.logoPath = null;
      _selected = null;
    });
  }

  // ---------- unified layer helpers (multi-track timeline + pro layers panel) ----------
  // A "layer" is a SubtitleSegment | StickerOverlay | the 'logo' sentinel string.
  double _layerZ(Object it) => it is SubtitleSegment ? it.z : it is StickerOverlay ? it.z : _project!.logoZ;
  bool _layerLocked(Object it) => it is SubtitleSegment ? it.locked : it is StickerOverlay ? it.locked : _project!.logoLocked;
  bool _layerHidden(Object it) => it is SubtitleSegment ? it.hidden : it is StickerOverlay ? it.hidden : _project!.logoHidden;
  Color _layerColor(Object it) => it is SubtitleSegment ? AppColors.brand : it is StickerOverlay ? const Color(0xFF7B61FF) : const Color(0xFF17A2A2);
  IconData? _layerIcon(Object it) =>
      it == 'logo' ? Icons.image_rounded : it is StickerOverlay ? (it.emoji != null ? null : Icons.auto_awesome_motion_rounded) : Icons.title_rounded;

  String _layerName(Object it) {
    if (it == 'logo') return 'Logo';
    if (it is StickerOverlay) return it.emoji != null ? '${it.emoji} Emoji' : 'Sticker';
    if (it is SubtitleSegment) return it.text.trim().isEmpty ? 'Text' : it.text.trim();
    return 'Layer';
  }

  String _layerDurLabel(Object it) {
    final dur = _duration;
    if (it == 'logo') return 'Full clip';
    double st, en;
    if (it is SubtitleSegment) { st = it.start; en = it.end; }
    else if (it is StickerOverlay) { st = it.start >= 9998 ? 0 : it.start; en = it.end >= 9998 ? dur : it.end; }
    else { return ''; }
    String f(double s) => _fmt(Duration(milliseconds: (s * 1000).round()));
    return '${f(st)} – ${f(en)}';
  }

  Widget _layerThumb(Object it, {double size = 36, bool selected = false}) {
    Widget fallback() => Icon(_layerIcon(it) ?? Icons.broken_image_rounded, color: _layerColor(it), size: size * 0.55);
    Widget inner;
    if (it == 'logo' && _project!.logoPath != null) {
      inner = Image.file(File(_project!.logoPath!), fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback());
    } else if (it is StickerOverlay) {
      inner = it.emoji != null
          ? Center(child: Text(it.emoji!, style: TextStyle(fontSize: size * 0.55)))
          : Image.file(File(it.path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback());
    } else if (it is SubtitleSegment) {
      final ch = it.text.trim().isEmpty ? 'T' : it.text.trim()[0].toUpperCase();
      inner = Center(child: Text(ch, style: TextStyle(color: Color(it.color), fontWeight: FontWeight.w800, fontSize: size * 0.5)));
    } else {
      inner = const SizedBox();
    }
    return Container(
      width: size, height: size, clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: selected ? _kAccent : AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: selected ? _kAccent : AppColors.line)),
      child: inner,
    );
  }

  Widget _layerIconBtn(IconData icon, Color color, VoidCallback onTap) => IconButton(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 34),
        icon: Icon(icon, color: color, size: 19),
        onPressed: onTap,
      );

  void _toggleLock(Object it) {
    _snapshot();
    setState(() {
      if (it is SubtitleSegment) it.locked = !it.locked;
      else if (it is StickerOverlay) it.locked = !it.locked;
      else _project!.logoLocked = !_project!.logoLocked;
    });
  }

  void _toggleVis(Object it) {
    _snapshot();
    setState(() {
      if (it is SubtitleSegment) it.hidden = !it.hidden;
      else if (it is StickerOverlay) it.hidden = !it.hidden;
      else _project!.logoHidden = !_project!.logoHidden;
    });
  }

  void _deleteLayer(Object it) {
    if (_layerLocked(it)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layer is locked — unlock it first')));
      return;
    }
    _snapshot();
    setState(() {
      if (it is SubtitleSegment) _project!.subtitles.remove(it);
      else if (it is StickerOverlay) _project!.stickers.remove(it);
      else if (it == 'logo') _project!.logoPath = null;
      if (identical(_selected, it) || (it == 'logo' && _selected == 'logo')) _selected = null;
    });
  }

  /// Duplicate any layer in place (generalised from [_duplicateSelected] so the
  /// Layers-panel row + timeline can duplicate without touching global selection).
  void _duplicateLayer(Object it) {
    _snapshot();
    if (it is SubtitleSegment) {
      final s = it.copy();
      s.dy = (s.dy + 0.06).clamp(0.05, 0.95);
      s.z = _topZ();
      setState(() { _project!.subtitles.add(s); _selected = s; });
    } else if (it is StickerOverlay) {
      final s = it.copy();
      s.dx = (s.dx + 0.05).clamp(0.05, 0.95);
      s.dy = (s.dy + 0.05).clamp(0.05, 0.95);
      s.z = _topZ();
      setState(() { _project!.stickers.add(s); _selected = s; });
    }
    // logo is a single instance in this model — not duplicable.
  }

  // Timeline drag/resize for one layer (shared by every per-layer track row).
  void _dragLayerTime(Object it, double d, double dur) {
    if (it is SubtitleSegment) {
      final len = it.end - it.start;
      it.start = (it.start + d).clamp(0.0, (dur - len).clamp(0.0, dur));
      it.end = it.start + len;
    } else if (it is StickerOverlay) {
      final end = it.end >= 9998 ? dur : it.end;
      final len = end - it.start;
      it.start = (it.start + d).clamp(0.0, (dur - len).clamp(0.0, dur));
      it.end = it.start + len;
    }
  }

  void _resizeLayerStart(Object it, double d, double dur) {
    if (it is SubtitleSegment) {
      final hi = it.end - 0.3;
      it.start = (it.start + d).clamp(0.0, hi < 0 ? 0.0 : hi);
    } else if (it is StickerOverlay) {
      final end = it.end >= 9998 ? dur : it.end;
      it.end = end; // pin a concrete end before trimming the start
      final hi = it.end - 0.3;
      it.start = (it.start + d).clamp(0.0, hi < 0 ? 0.0 : hi);
    }
  }

  void _resizeLayerEnd(Object it, double d, double dur) {
    if (it is SubtitleSegment) {
      final hi = dur <= 0 ? it.end + 5 : dur;
      final lo = it.start + 0.3;
      it.end = (it.end + d).clamp(lo > hi ? hi : lo, hi);
    } else if (it is StickerOverlay) {
      final end = it.end >= 9998 ? dur : it.end;
      final hi = dur <= 0 ? end + 5 : dur;
      final lo = it.start + 0.3;
      it.end = (end + d).clamp(lo > hi ? hi : lo, hi);
    }
  }

  /// Split (client §4): cut the SELECTED text/sticker at the playhead into two
  /// independent layers (left = start→t, right = t→end). With nothing selected,
  /// splits the single layer under the playhead; if that's ambiguous, guides the
  /// user. The base video is a single clip — use Trim to shorten it.
  void _splitAtPlayhead() {
    final t = _t;
    // Resolve a target: the selection, else the one overlay live at the playhead.
    Object? target = (_selected is SubtitleSegment || _selected is StickerOverlay) ? _selected : null;
    if (target == null) {
      final live = <Object>[
        ..._project!.subtitles.where((s) => !s.hidden && t > s.start + 0.05 && t < s.end - 0.05),
        ..._project!.stickers.where((s) => !s.hidden && t > (s.start >= 9998 ? 0 : s.start) + 0.05 && t < (s.end >= 9998 ? _duration : s.end) - 0.05),
      ];
      if (live.length == 1) target = live.first;
    }
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select a text or sticker layer, then move the playhead inside it to split. (Use Trim for the video.)'),
      ));
      return;
    }
    if (_layerLocked(target)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Layer is locked — unlock it first')));
      return;
    }
    if (target is SubtitleSegment) {
      final seg = target; // final promoted local so it stays typed inside setState
      if (t <= seg.start + 0.05 || t >= seg.end - 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Move the playhead inside the layer to split it')));
        return;
      }
      _snapshot();
      final right = seg.copy();
      setState(() {
        seg.end = t;
        right.start = t;
        right.z = _topZ();
        _project!.subtitles.add(right);
        _project!.subtitles.sort((a, b) => a.start.compareTo(b.start));
        _selected = right;
      });
    } else if (target is StickerOverlay) {
      final stk = target; // final promoted local
      final end = stk.end >= 9998 ? _duration : stk.end;
      if (t <= stk.start + 0.05 || t >= end - 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Move the playhead inside the layer to split it')));
        return;
      }
      _snapshot();
      final right = stk.copy();
      setState(() {
        stk.end = t;
        right.start = t;
        right.end = end;
        right.z = _topZ();
        _project!.stickers.add(right);
        _selected = right;
      });
    }
    HapticFeedback.selectionClick();
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
      end: (dz <= 0 || dz - s0 < 0.5) ? 9999.0 : (s0 + 3).clamp(s0 + 0.5, dz),
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
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.of(context).viewPadding.bottom),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Center(child: _Grabber()),
                    const Text('Stickers & emoji', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
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
                                decoration: BoxDecoration(color: tab == i ? _kAccent : _kChip, borderRadius: BorderRadius.circular(18), border: Border.all(color: tab == i ? _kAccent : AppColors.line)),
                                child: Text(cats[i].name, style: TextStyle(color: tab == i ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 12.5)),
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
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(svc.attribution!, style: const TextStyle(color: AppColors.inkFaint, fontSize: 9.5))),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 18 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: _Grabber()),
              const Text('Animation', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Pick a caption look — tap to preview.', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
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
                            border: Border.all(color: getAnim() == a ? _kAccent : AppColors.line),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(a.icon, color: getAnim() == a ? Colors.white : AppColors.inkMuted, size: 22),
                            const SizedBox(height: 5),
                            Text(a.label, style: TextStyle(color: getAnim() == a ? Colors.white : AppColors.ink, fontSize: 10, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Fade', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 12.5)),
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
        SizedBox(width: 78, child: Text(label, style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w500, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(activeTrackColor: _kAccent, thumbColor: Colors.white, inactiveTrackColor: AppColors.line, trackHeight: 4, overlayColor: _kAccent.withOpacity(0.15), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5, elevation: 1.5)),
            child: Slider(value: value.clamp(0, 2), min: 0, max: 2, divisions: 20, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 44, child: Text('${value.toStringAsFixed(1)}s', textAlign: TextAlign.right, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 12, fontFamily: 'IBMPlexMono'))),
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
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        Widget optRow<T>(String title, List<(String, T)> options, T current, ValueChanged<T> onPick) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 12.5, letterSpacing: 0.5)),
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
                            color: current == o.$2 ? _kAccent : _kChip,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: current == o.$2 ? _kAccent : AppColors.line),
                          ),
                          child: Text(o.$1, style: TextStyle(color: current == o.$2 ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
              ],
            );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: _Grabber()),
              const Text('Export settings', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 17)),
              const SizedBox(height: 4),
              Text('Renders on this phone · saves to your Gallery', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
              const SizedBox(height: 18),
              optRow<int>('QUALITY', const [('720p', 720), ('1080p', 1080)], p.resolution.shortEdge,
                  (v) => p.resolution = v == 720 ? ExportResolution.p720 : ExportResolution.p1080),
              optRow<int>('FRAME RATE', const [('30 fps', 30), ('60 fps', 60)], p.fps, (v) => p.fps = v),
              // Watermark (design places it in export settings)
              Row(children: [
                const Text('Watermark', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text(p.watermarkOn ? 'On' : 'Off', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                const Spacer(),
                Switch(value: p.watermarkOn, activeColor: _kAccent, onChanged: (v) => setSheet(() => p.watermarkOn = v)),
              ]),
              const SizedBox(height: 14),
              // §18 gold final-warning notice (display only)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.goldBg, borderRadius: BorderRadius.circular(14)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: AppColors.goldText),
                  SizedBox(width: 10),
                  Expanded(child: Text('Once exported, this clip is final and cannot be re-edited.', style: TextStyle(color: AppColors.goldText, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w500))),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Export now', icon: Icons.ios_share, onPressed: () => Navigator.pop(context, true))),
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
          backgroundColor: AppColors.surface,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rendering your video…', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: v <= 0 ? null : v, // indeterminate until the first frame
                    minHeight: 6,
                    backgroundColor: AppColors.line,
                    valueColor: const AlwaysStoppedAnimation(_kAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(v <= 0 ? 'Preparing…' : '${(v * 100).round()}%  ·  keep the app open',
                    style: const TextStyle(color: AppColors.inkMuted, fontSize: 12, fontWeight: FontWeight.w500)),
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
            backgroundColor: AppColors.surface,
            title: const Text('Exported', style: TextStyle(color: AppColors.ink)),
            content: Text(
              res.savedToGallery
                  ? 'Saved to your Gallery (ClipCart album).\nShare it to Instagram from there.'
                  : 'Saved on device:\n${res.path}',
              style: const TextStyle(color: AppColors.inkMuted),
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
        appBar: AppBar(backgroundColor: _kBg, foregroundColor: AppColors.ink, title: Text(widget.title ?? 'Editor')),
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
                    child: Text(_error ?? 'Loading your clip in full HD…', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkMuted)),
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
        foregroundColor: AppColors.ink,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () async { if (await _confirmDiscard() && mounted) Navigator.of(context).pop(); },
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.title ?? 'Editor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.ink)),
          if (_savedLabel.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.greenDot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(_savedLabel, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 10.5, color: AppColors.inkMuted, fontWeight: FontWeight.w500)),
            ]),
        ]),
        actions: [
          // Undo/Redo/Select/Delete now live on the transport row (client §4).
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
                        // Pinch scales the video 0.25×–4×: below 1 shrinks it and
                        // shows the background around it (client: "scale down").
                        final ns = (_gScale * d.scale).clamp(0.25, 4.0);
                        _project!.videoScale = ns;
                        // Pan range = croppable margin (zoomed in) OR the empty gap
                        // (scaled down) — either way clamp so it can't fly off-frame.
                        final lim = _videoPanLimit(ns);
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
                          // User-controllable frame background (fill gap / letterbox).
                          color: Color(_project!.videoBgColor),
                          child: Transform.translate(
                            offset: Offset(_project!.videoDx * w, _project!.videoDy * h),
                            child: Transform.scale(
                              scale: _effVideoScale(),
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

  /// Live-preview drop shadow derived from the SAME params the export burns
  /// (text_render.dart), scaled to on-screen px so preview matches the export.
  Shadow _paramShadow(SubtitleSegment s, double scale) {
    final ang = s.shadowAngle * math.pi / 180.0;
    final d = (s.shadowDistance / 100.0) * s.effectiveSize * scale;
    return Shadow(
      color: Color(s.shadowColor).withOpacity(s.shadowOpacity.clamp(0.0, 1.0)),
      blurRadius: s.shadowBlur.clamp(0.0, 1.0) * s.effectiveSize * scale * 0.4,
      offset: Offset(math.cos(ang) * d, math.sin(ang) * d),
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
          // WYSIWYG shadow: derive from the same params the export burns, so
          // preview == exported PNG (and it shows even alongside a stroke).
          shadows: s.strokeWidth > 0
              ? [
                  if (s.shadow) _paramShadow(s, scale),
                  for (final o in const [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)]) Shadow(color: Color(s.strokeColor), offset: o * (s.strokeWidth * scale).clamp(0.5, 4)),
                ]
              : (s.shadow ? [_paramShadow(s, scale)] : const [Shadow(color: Colors.black54, blurRadius: 3)]),
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
            if (s.locked) return; // locked layer: no move/scale/rotate
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
        if (selected && !s.locked) ...[
          Positioned(left: -11, top: -11, child: _cornerBtn(Icons.close_rounded, _deleteSelected)),
          Positioned(right: -11, top: -11, child: _cornerBtn(Icons.edit_rounded, () => _startTyping(s))),
          Positioned(left: -11, bottom: -11, child: _cornerBtn(Icons.copy_rounded, _duplicateSelected)),
          Positioned(right: -11, bottom: -11, child: _resizeHandle(s, w, h, rotate: true)),
        ],
        if (selected && s.locked)
          Positioned(right: -11, top: -11, child: _cornerBtn(Icons.lock_rounded, () => _toggleLock(s))),
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
        if (_layerLocked(target)) return; // locked layer: ignore resize/rotate
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
    // Place the logo's CENTER exactly at (logoDx*w, logoDy*h). The old
    // Align(dx*2-1,...) was size-aware (aligned edges), so an off-centre logo
    // lagged the finger while dragging and landed at a different spot than the
    // FFmpeg export (which centres on logoDx). Positioned + a -50%/-50% self
    // shift makes preview == drag == export.
    return Positioned(
      left: p.logoDx * w,
      top: p.logoDy * h,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
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
            if (p.logoLocked) return; // locked logo: no move/scale/rotate
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
        if (selected && !p.logoLocked) ...[
          Positioned(left: -11, top: -11, child: _cornerBtn(Icons.close_rounded, _deleteSelected)),
          Positioned(right: -11, bottom: -11, child: _resizeHandle('logo', w, h, rotate: true)),
        ],
        if (selected && p.logoLocked)
          Positioned(right: -11, top: -11, child: _cornerBtn(Icons.lock_rounded, () => _toggleLock('logo'))),
        ]),
      ),
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
            if (st.locked) return; // locked layer: no move/scale/rotate
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
        if (selected && !st.locked) ...[
          Positioned(left: -11, top: -11, child: _cornerBtn(Icons.close_rounded, _deleteSelected)),
          Positioned(left: -11, bottom: -11, child: _cornerBtn(Icons.copy_rounded, _duplicateSelected)),
          Positioned(right: -11, bottom: -11, child: _resizeHandle(st, w, h, rotate: true)),
        ],
        if (selected && st.locked)
          Positioned(right: -11, top: -11, child: _cornerBtn(Icons.lock_rounded, () => _toggleLock(st))),
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
              icon: Icon(v.isPlaying ? Icons.pause_circle_filled : (ended ? Icons.replay_circle_filled : Icons.play_circle_fill), color: _kAccent, size: 32),
              onPressed: _togglePlay,
            ),
            const SizedBox(width: 2),
            Text('${_fmt(Duration(milliseconds: (v.position.inMilliseconds - _startMs).clamp(0, _endMs - _startMs)))} / ${_fmt(Duration(milliseconds: _endMs - _startMs))}', style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w500, fontSize: 12, fontFamily: 'IBMPlexMono')),
            const Spacer(),
            // Client §4: transport row carries Undo · Redo · Select · Delete.
            _actionIcon('Undo', Icons.undo_rounded, _undo.isEmpty ? null : _undoAction),
            const SizedBox(width: 2),
            _actionIcon('Redo', Icons.redo_rounded, _redo.isEmpty ? null : _redoAction),
            const SizedBox(width: 2),
            _actionIcon('Select', Icons.check_box_outlined, () => _openLayers(startInSelect: true)),
            const SizedBox(width: 2),
            _actionIcon('Delete', Icons.delete_outline_rounded, _selected == null ? null : _deleteSelected, danger: true),
          ]),
        );
      },
    );
  }

  /// Compact labelled icon button for the transport row (icon over a tiny label).
  /// A null [onTap] renders a disabled (greyed) state; [danger] tints red.
  Widget _actionIcon(String label, IconData icon, VoidCallback? onTap, {bool on = false, bool danger = false}) {
    final disabled = onTap == null;
    final fg = on
        ? Colors.white
        : disabled
            ? AppColors.inkGhost
            : danger
                ? AppColors.errText
                : AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(color: on ? _kAccent : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 19, color: fg),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60)}:${(d.inSeconds.remainder(60)).toString().padLeft(2, '0')}';

  // ---------- timeline (scrub + trim + subtitle track) ----------
  Widget _timeline() {
    final dur = _duration;
    final p = _project!;
    final hasLayers = p.subtitles.isNotEmpty || p.stickers.isNotEmpty || p.logoPath != null;
    // Multi-track (CapCut-style): base video filmstrip on top, then ONE ROW PER
    // overlay layer (each text / sticker / logo its own track, top layer first).
    final layers = <Object>[
      for (final s in p.subtitles) s,
      for (final s in p.stickers) s,
      if (p.logoPath != null) 'logo',
    ]..sort((a, b) => _layerZ(b).compareTo(_layerZ(a)));
    const trackH = 26.0;
    const rowH = 22.0;
    const gap = 5.0;
    final contentH = trackH + gap + layers.length * (rowH + gap);
    final viewH = (contentH + 16).clamp(58.0, 196.0); // +16 = container 8+8 vertical pad
    return Container(
      color: AppColors.surfaceHover,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      height: viewH,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final avail = c.maxHeight;
        double x(double sec) => dur <= 0 ? 0 : (sec / dur) * w;
        double sec(double px) => dur <= 0 ? 0 : (px / w) * dur;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _vc!,
          builder: (context, v, _) {
            final ph = x(v.position.inMilliseconds / 1000.0);
            final stack = Stack(clipBehavior: Clip.none, children: [
              // ---- base video track (filmstrip look) ----
              Positioned(
                left: 0, right: 0, top: 0, height: trackH,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    decoration: const BoxDecoration(color: AppColors.bgAlt),
                    child: Row(children: [
                      for (int i = 0; i < 10; i++)
                        Expanded(child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.line))),
                          child: Center(child: Icon(Icons.movie_creation_outlined, size: 12, color: AppColors.inkGhost.withOpacity(0.5))),
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
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
                        child: const Text('Tap Add text, Emoji or Sticker to begin', style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
              // ---- one track ROW per layer (top layer first) ----
              for (int i = 0; i < layers.length; i++)
                _trackRow(layers[i], trackH + gap + i * (rowH + gap), rowH, w, dur, x, sec),
              // playhead spanning the whole stack
              Positioned(left: ph.clamp(0, w) - 1, top: -2, height: contentH + 4, child: IgnorePointer(child: Container(width: 2, color: AppColors.ink))),
              Positioned(left: ph.clamp(0, w) - 5, top: -6, child: IgnorePointer(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)))),
              // trim handles LAST so they sit above the playhead and stay grabbable
              if (_trimMode) ..._trimHandles(x, sec, w, p, dur, trackH),
            ]);
            final content = SizedBox(height: contentH, width: w, child: stack);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // In trim mode the parent must NOT seek — otherwise a tap/drag near a
              // handle steals the gesture and the trim feels broken. onTapUp (not
              // onTapDown) fires only when the parent's tap actually WINS the arena,
              // so a press-hold / hesitant drag-start on a layer block never seeks.
              onTapUp: _trimMode ? null : (d) => _seek(sec(d.localPosition.dx)),
              onHorizontalDragUpdate: _trimMode ? null : (d) => _seek(sec(d.localPosition.dx.clamp(0, w))),
              // Many layers → scroll vertically inside the fixed viewport. The vertical
              // scroller only claims vertical drags, so horizontal drags still seek and
              // per-block horizontal drags still move/trim their layer. Clip.none so the
              // playhead knob / trim bars / time bubble (negative tops) aren't clipped.
              child: contentH > avail
                  ? SingleChildScrollView(scrollDirection: Axis.vertical, clipBehavior: Clip.none, child: content)
                  : content,
            );
          },
        );
      }),
    );
  }

  /// One timeline track ROW for a single overlay layer (text/sticker/logo). The
  /// layer's block is positioned by time; drag = move, edge grips = duration.
  /// A locked layer (or the logo, which has no time window) ignores drag/resize.
  Widget _trackRow(Object it, double top, double rowH, double w, double dur, double Function(double) x, double Function(double) sec) {
    final isLogo = it == 'logo';
    final selected = isLogo ? _selected == 'logo' : identical(_selected, it);
    final locked = _layerLocked(it);
    double st, en;
    if (isLogo) { st = 0; en = dur; }
    else if (it is SubtitleSegment) { st = it.start; en = it.end; }
    else { final s = it as StickerOverlay; st = s.start; en = s.end >= 9998 ? dur : s.end; }
    final left = x(st).clamp(0.0, w);
    final width = (x(en) - x(st)).clamp(28.0, w);
    final canTime = !isLogo && !locked; // logo has no time window; locked = no move
    return Positioned(
      left: 0, right: 0, top: top, height: rowH,
      child: Stack(clipBehavior: Clip.none, children: [
        // faint lane background so the track reads even where the block isn't
        Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.bgAlt.withOpacity(0.45), borderRadius: BorderRadius.circular(6))))),
        Positioned(
          left: left, width: width, top: 0, bottom: 0,
          child: _timelineBlock(
            label: _layerName(it),
            icon: _layerIcon(it),
            selected: selected,
            color: _layerColor(it),
            locked: locked,
            onTap: () => setState(() => _selected = isLogo ? 'logo' : it),
            onDrag: canTime ? (d) => setState(() => _dragLayerTime(it, sec(d), dur)) : (_) {},
            onResizeLeft: canTime ? (d) => setState(() => _resizeLayerStart(it, sec(d), dur)) : null,
            onResizeRight: canTime ? (d) => setState(() => _resizeLayerEnd(it, sec(d), dur)) : null,
          ),
        ),
      ]),
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
    void Function(double)? onResizeLeft,
    void Function(double)? onResizeRight,
    bool locked = false,
  }) {
    // A block is time-draggable only if it isn't locked AND actually has a time
    // window to move (resize grips present). The full-clip logo has neither.
    final draggable = !locked && (onResizeLeft != null || onResizeRight != null);
    final body = GestureDetector(
      onTap: onTap,
      onHorizontalDragStart: draggable ? (_) => _snapshot() : null, // fires once per drag → move is undoable
      onHorizontalDragUpdate: draggable ? (d) => onDrag(d.delta.dx) : null,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 7),
        decoration: BoxDecoration(
          gradient: gradient,
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? Colors.white : Colors.white.withOpacity(0.15), width: selected ? 1.6 : 1),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (locked) ...[const Icon(Icons.lock, size: 10, color: Colors.white), const SizedBox(width: 3)],
          if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 4)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
    // When selected, show drag-to-trim grips at each edge so the user can set how
    // long the layer shows — "jaise video length" (client §2). Delta-based so the
    // gesture survives the block repositioning on each rebuild.
    return Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
      body,
      if (selected && onResizeLeft != null) Positioned(left: 0, top: 0, bottom: 0, child: _trimGrip(onResizeLeft)),
      if (selected && onResizeRight != null) Positioned(right: 0, top: 0, bottom: 0, child: _trimGrip(onResizeRight)),
    ]);
  }

  Widget _trimGrip(void Function(double) onDrag) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _snapshot(),
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Container(
          width: 16, alignment: Alignment.center,
          child: Container(width: 4, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 2)])),
        ),
      );

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
                color: (_trimDrag == (isStart ? 1 : 2)) ? AppColors.brandPressed : _kAccent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 4)]),
              child: const Icon(Icons.drag_indicator, size: 15, color: Colors.white),
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
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: _Grabber()),
            const Text('Add more', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
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
            decoration: BoxDecoration(color: on ? _kAccent : _kChip, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? _kAccent : AppColors.line)),
            child: Icon(icon, color: on ? Colors.white : AppColors.ink, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkMuted, fontSize: 11, fontWeight: FontWeight.w500)),
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
    // Locked layer: hide EVERY editing surface (text panel, sticker/logo tools,
    // Adjust sheets) — offer only Unlock, matching the on-canvas lock badge. This
    // keeps the lock contract airtight (canvas + transport were already gated).
    if (hasSel && _layerLocked(_selected!)) {
      return Container(
        decoration: const BoxDecoration(
          color: _kPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        padding: EdgeInsets.fromLTRB(14, 10, 10, 10 + MediaQuery.of(context).viewPadding.bottom),
        child: Row(children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          const Expanded(child: Text('Layer locked — unlock to edit', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13.5))),
          TextButton.icon(
            onPressed: () => _toggleLock(_selected!),
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Unlock'),
            style: TextButton.styleFrom(foregroundColor: AppColors.brand),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _selected = null),
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
            ),
          ),
        ]),
      );
    }
    // Light tool deck (warm-paper chrome). Selection ends by tapping the canvas or the check.
    return Container(
      decoration: const BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(10, 6, 10, 6 + MediaQuery.of(context).viewPadding.bottom),
      child: !hasSel
          // PROJECT tools — ONE clean row (client §4): Text · Trim · Split ·
          // Aspect · Transform · Layers. Add-tools (Logo/Stickers/Handle/CTA/
          // Outro/Brand) live under Layers → "Add".
          ? SizedBox(
              height: 60,
              child: Row(children: [
                _barTile(Icons.title_rounded, 'Text', _addSubtitle),
                _barTile(Icons.content_cut_rounded, 'Trim', () => setState(() => _trimMode = !_trimMode), on: _trimMode),
                _barTile(Icons.call_split_rounded, 'Split', _splitAtPlayhead),
                _barTile(Icons.crop_rounded, _project!.aspect.isOriginal ? 'Aspect' : _project!.aspect.label, _pickAspect, on: !_project!.aspect.isOriginal),
                _barTile(Icons.open_with_rounded, 'Transform', _openTransform,
                    on: _project!.videoScale != 1.0 || _project!.videoDx != 0 || _project!.videoDy != 0),
                _barTile(Icons.layers_rounded, 'Layers', _openLayers),
              ]),
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
    const ink = AppColors.ink, mut = AppColors.inkMuted, line = AppColors.line, brand = _kAccent;
    const tile = _kChip;
    Widget subTab(String label, int i) {
      final on = _textTab.clamp(0, 2) == i;
      return GestureDetector(
        onTap: () => setState(() => _textTab = i),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? brand : Colors.transparent,
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
              subTab('Font', 0), const SizedBox(width: 7),
              subTab('Styling', 1), const SizedBox(width: 7),
              subTab('Advance', 2),
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
          child: switch (_textTab.clamp(0, 2)) {
            0 => _textFont(s, ink, mut, tile, line, brand),
            1 => _textStyling(s, ink, mut, tile, line, brand),
            _ => _textAdvance(s, mut, tile, line, brand),
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
        SizedBox(width: labelW, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted))),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(activeTrackColor: _kAccent, thumbColor: Colors.white, inactiveTrackColor: AppColors.line, trackHeight: 4, overlayShape: RoundSliderOverlayShape(overlayRadius: 14), thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7.5, elevation: 1.5)),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: (_) => _gestureSnapped = false),
          ),
        ),
        SizedBox(width: 44, child: Text(display, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 11, color: AppColors.ink))),
      ]);

  // A horizontal row of colour swatches (shadow / stroke / background fill).
  Widget _swatchRow(int current, ValueChanged<int> onPick, Color brand, Color line, {bool bg = false}) {
    final swatches = bg
        ? const [0x80000000, 0xFF000000, 0xFFFFFFFF, 0xFF0E9E6E, 0xFFFFC400, 0xFF2D7FF9, 0xFFDC2626]
        : const [0xFF000000, 0xFFFFFFFF, 0xFF0E9E6E, 0xFFDC2626, 0xFF2D7FF9, 0xFFD89A3C, 0xFFFFC400];
    return SizedBox(
      height: 28,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final c in swatches)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: Color(c), borderRadius: BorderRadius.circular(7), border: Border.all(color: current == c ? brand : line, width: current == c ? 2.5 : 1)),
              ),
            ),
          ),
      ]),
    );
  }

  // A shadow preset chip (client §5 images 5 & 6): one tap turns the shadow on
  // with an exact opacity / blur / distance / angle set.
  Widget _shadowPresetBtn(SubtitleSegment s, String label, double op, double blur, double dist, double angle, Color tile, Color line, Color brand) {
    final on = s.shadow && (s.shadowOpacity - op).abs() < 0.02 && (s.shadowBlur - blur).abs() < 0.02 && (s.shadowDistance - dist).abs() < 0.5 && (s.shadowAngle - angle).abs() < 1;
    return GestureDetector(
      onTap: () => _mutate(() {
        s.shadow = true;
        s.shadowOpacity = op; s.shadowBlur = blur; s.shadowDistance = dist; s.shadowAngle = angle;
        s.shadowColor = 0xFF000000;
      }),
      child: Container(
        height: 38, alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? brand : tile, borderRadius: BorderRadius.circular(9), border: Border.all(color: on ? brand : line)),
        child: Text(label, style: TextStyle(fontSize: 12.5, color: on ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ---- FONT tab (client §3): family selection + size + alignment ----
  Widget _textFont(SubtitleSegment s, Color ink, Color mut, Color tile, Color line, Color brand) {
    Widget bi(String t, bool on, VoidCallback tap, {bool italic = false}) => GestureDetector(
          onTap: tap,
          child: Container(
            width: 44, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? AppColors.brandSurface : tile, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? brand : line)),
            child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontStyle: italic ? FontStyle.italic : FontStyle.normal, color: on ? brand : ink)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: GestureDetector(onTap: _openFontPicker, child: Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)), child: Row(children: [Text('Aa', style: TextStyle(fontFamily: s.fontFamily, fontSize: 17, color: ink, fontWeight: FontWeight.w700)), const SizedBox(width: 10), Expanded(child: Text(s.fontFamily ?? 'Default', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: s.fontFamily, fontSize: 14, color: ink))), const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.mut)])))),
        const SizedBox(width: 7),
        bi('B', s.bold, () => _mutate(() => s.bold = !s.bold)),
        const SizedBox(width: 7),
        bi('I', s.italic, () => _mutate(() => s.italic = !s.italic), italic: true),
      ]),
      const SizedBox(height: 14),
      _lightSlider('Size', s.scale, 0.4, 4.0, (v) => setState(() { if (!_gestureSnapped) { _snapshot(); _gestureSnapped = true; } s.scale = v; }), display: '${(s.fontSize * s.scale).round()}', labelW: 40),
      const SizedBox(height: 14),
      Row(children: [
        for (final a in TextAlignH.values) ...[
          Expanded(child: GestureDetector(
            onTap: () => _mutate(() => s.align = a),
            child: Container(height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: s.align == a ? AppColors.brandSurface : tile, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.align == a ? brand : line)), child: Icon(_alignIcon(a), size: 19, color: s.align == a ? brand : ink)),
          )),
          if (a != TextAlignH.right) const SizedBox(width: 8),
        ],
      ]),
    ]);
  }

  // ---- STYLING tab (client §3+§5): presets · colour · shadow · stroke · background ----
  Widget _textStyling(SubtitleSegment s, Color ink, Color mut, Color tile, Color line, Color brand) {
    void snap() { if (!_gestureSnapped) { _snapshot(); _gestureSnapped = true; } }
    const swatches = [0xFFFFFFFF, 0xFF000000, 0xFF0E9E6E, 0xFFD89A3C, 0xFFDC2626, 0xFF2D7FF9, 0xFFFFC400, 0xFF9B5DE5];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Preset "looks" (font+colour+bg+stroke+anim in one tap)
      const Text('Presets', style: TextStyle(fontSize: 11.5, color: AppColors.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 7),
      SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final tpl in _styleTemplates)
          Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
            onTap: () => _applyStyle(s, tpl),
            child: Container(
              width: 90, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: (tpl['bg'] as bool) ? Color(tpl['bgc'] as int) : AppColors.bgAlt, borderRadius: BorderRadius.circular(9), border: Border.all(color: s.fontFamily == tpl['font'] ? brand : line, width: s.fontFamily == tpl['font'] ? 2 : 1)),
              child: Text(tpl['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: tpl['font'] as String?, color: Color(tpl['color'] as int), fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          )),
      ])),
      const SizedBox(height: 12),
      // Colour
      Row(children: [
        const SizedBox(width: 62, child: Text('Colour', style: TextStyle(fontSize: 12, color: AppColors.mut))),
        Expanded(child: SizedBox(height: 30, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in swatches) Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => _mutate(() => s.color = c), child: Container(width: 30, height: 30, decoration: BoxDecoration(color: Color(c), borderRadius: BorderRadius.circular(8), border: Border.all(color: s.color == c ? brand : line, width: s.color == c ? 2 : 1))))),
          GestureDetector(onTap: () => _quickColor(s), child: Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: line)), child: const Icon(Icons.add_rounded, size: 16, color: AppColors.mut))),
        ]))),
      ]),
      const SizedBox(height: 14),
      // Shadow — enable + the two client presets
      Row(children: [
        Expanded(child: _textFootBtn(s.shadow ? 'Shadow ✓' : 'Shadow', s.shadow ? brand : tile, s.shadow ? brand : line, s.shadow ? Colors.white : AppColors.ink, () => _mutate(() => s.shadow = !s.shadow))),
        const SizedBox(width: 8),
        Expanded(child: _shadowPresetBtn(s, 'Soft', 1.0, 0.5, 0.0, 45, tile, line, brand)),
        const SizedBox(width: 8),
        Expanded(child: _shadowPresetBtn(s, 'Drop', 0.65, 0.0, 8.0, -45, tile, line, brand)),
      ]),
      if (s.shadow) ...[
        const SizedBox(height: 8),
        _lightSlider('Opacity', s.shadowOpacity, 0.0, 1.0, (v) => setState(() { snap(); s.shadowOpacity = v; }), display: '${(s.shadowOpacity * 100).round()}%'),
        _lightSlider('Blur', s.shadowBlur, 0.0, 1.0, (v) => setState(() { snap(); s.shadowBlur = v; }), display: '${(s.shadowBlur * 100).round()}%'),
        _lightSlider('Distance', s.shadowDistance, 0.0, 20.0, (v) => setState(() { snap(); s.shadowDistance = v; }), display: s.shadowDistance.toStringAsFixed(0)),
        _lightSlider('Angle', s.shadowAngle, -180.0, 180.0, (v) => setState(() { snap(); s.shadowAngle = v; }), display: '${s.shadowAngle.round()}°'),
        const SizedBox(height: 6),
        Row(children: [const SizedBox(width: 62, child: Text('Shadow', style: TextStyle(fontSize: 12, color: AppColors.mut))), Expanded(child: _swatchRow(s.shadowColor, (c) => _mutate(() => s.shadowColor = c), brand, line))]),
      ],
      const SizedBox(height: 14),
      // Stroke
      _lightSlider('Stroke', s.strokeWidth, 0, 12, (v) => setState(() { snap(); s.strokeWidth = v; }), display: s.strokeWidth.toStringAsFixed(0)),
      if (s.strokeWidth > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [const SizedBox(width: 62, child: Text('Stroke', style: TextStyle(fontSize: 12, color: AppColors.mut))), Expanded(child: _swatchRow(s.strokeColor, (c) => _mutate(() => s.strokeColor = c), brand, line))])),
      const SizedBox(height: 14),
      // Background (renamed from "Box" per client §5) + its fill colour
      Row(children: [
        Expanded(child: _textFootBtn(s.bgEnabled ? 'Background ✓' : 'Background', s.bgEnabled ? brand : tile, s.bgEnabled ? brand : line, s.bgEnabled ? Colors.white : AppColors.ink, () => _mutate(() => s.bgEnabled = !s.bgEnabled))),
      ]),
      if (s.bgEnabled) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const SizedBox(width: 62, child: Text('Fill', style: TextStyle(fontSize: 12, color: AppColors.mut))), Expanded(child: _swatchRow(s.bgColor, (c) => _mutate(() => s.bgColor = c), brand, line, bg: true))])),
      const SizedBox(height: 16),
      const Divider(height: 1, color: AppColors.line),
      const SizedBox(height: 12),
      // Fine tuning + Motion — moved here so the Advance tab stays position+scale ONLY (client §3).
      const Text('Fine tuning', style: TextStyle(fontSize: 11.5, color: AppColors.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      _lightSlider('Rotate', s.rotation * 180 / math.pi, -180, 180, (v) => setState(() { snap(); s.rotation = v * math.pi / 180; }), display: '${(s.rotation * 180 / math.pi).round()}°'),
      _lightSlider('Opacity', s.opacity, 0.1, 1.0, (v) => setState(() { snap(); s.opacity = v; }), display: '${(s.opacity * 100).round()}%'),
      _lightSlider('Letter', s.letterSpacing, -3, 12, (v) => setState(() { snap(); s.letterSpacing = v; }), display: s.letterSpacing.toStringAsFixed(1)),
      _lightSlider('Line', s.lineHeight, 0.8, 2.0, (v) => setState(() { snap(); s.lineHeight = v; }), display: s.lineHeight.toStringAsFixed(2)),
      const SizedBox(height: 12),
      const Text('Motion', style: TextStyle(fontSize: 11.5, color: AppColors.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 7),
      Row(children: [
        _animChip(s, 'None', OverlayAnim.none, tile, line, brand), const SizedBox(width: 6),
        _animChip(s, 'Fade', OverlayAnim.fade, tile, line, brand), const SizedBox(width: 6),
        _animChip(s, 'Pop', OverlayAnim.popIn, tile, line, brand), const SizedBox(width: 6),
        _animChip(s, 'Slide', OverlayAnim.slideUp, tile, line, brand), const SizedBox(width: 6),
        _animChip(s, 'Zoom', OverlayAnim.zoomIn, tile, line, brand),
      ]),
    ]);
  }

  Widget _animChip(SubtitleSegment s, String label, OverlayAnim a, Color tile, Color line, Color brand) => Expanded(
        child: GestureDetector(
          onTap: () => _mutate(() => s.anim = a),
          child: Container(height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: s.anim == a ? AppColors.brandSurface : tile, borderRadius: BorderRadius.circular(9), border: Border.all(color: s.anim == a ? brand : line)), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: s.anim == a ? brand : AppColors.ink))),
        ),
      );

  // ---- ADVANCE tab (client §3): ONLY text position + scale ----
  Widget _textAdvance(SubtitleSegment s, Color mut, Color tile, Color line, Color brand) {
    void snap() { if (!_gestureSnapped) { _snapshot(); _gestureSnapped = true; } }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _NumFieldLight(label: 'X %', value: s.dx * 100, min: 0, max: 100, onChanged: (v) => _mutate(() => s.dx = (v / 100).clamp(0.0, 1.0)))),
        const SizedBox(width: 8),
        Expanded(child: _NumFieldLight(label: 'Y %', value: s.dy * 100, min: 0, max: 100, onChanged: (v) => _mutate(() => s.dy = (v / 100).clamp(0.0, 1.0)))),
      ]),
      const SizedBox(height: 12),
      _lightSlider('Scale', s.scale, 0.4, 4.0, (v) => setState(() { snap(); s.scale = v; }), display: '${(s.scale * 100).round()}%'),
      const SizedBox(height: 8),
      const Text('Position and scale only. Colour, shadow, stroke, motion & fine typography live in the Styling tab.',
          style: TextStyle(fontSize: 11, color: AppColors.inkFaint, height: 1.3)),
    ]);
  }

  /// One cell of the single-row project toolbar (client §4). Expanded so the six
  /// tools split the width evenly; icon over a tiny label, brand-fill when active.
  Widget _barTile(IconData icon, String label, VoidCallback onTap, {bool on = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: BoxDecoration(
                color: on ? AppColors.brand : _kChip,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? AppColors.brand : AppColors.line),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: on ? Colors.white : AppColors.ink, size: 20),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? Colors.white : AppColors.ink, fontSize: 10, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
      );

  /// A tile for the Layers → Add grid (secondary add-tools that used to crowd the
  /// bottom toolbar). Fixed square so the grid stays tidy.
  Widget _addTile(IconData icon, String label, VoidCallback onTap, {bool on = false}) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 50, height: 50, alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? AppColors.brand : _kChip, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? AppColors.brand : AppColors.line)),
            child: Icon(icon, color: on ? Colors.white : AppColors.ink, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
        ]),
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
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: _Grabber()),
              const Text('Text color', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final c in swatches)
                  GestureDetector(
                    onTap: () { _mutate(() => s.color = c); setSheet(() {}); },
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == s.color ? _kAccent : AppColors.line, width: c == s.color ? 3 : 1))),
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
            color: on ? _kAccent : _kChip,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? _kAccent : AppColors.line),
          ),
          child: Text(label, style: TextStyle(color: on ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );

  Widget _bgSwatch(int color, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle, border: Border.all(color: on ? _kAccent : AppColors.line, width: on ? 2.5 : 1)),
        ),
      );

  /// Transform tool (client §1): explicit controls to SCALE (down or up) and
  /// POSITION the video inside the frame, plus the frame background for any gap.
  /// Mirrors the canvas pinch/drag but discoverable and precise. WYSIWYG on export.
  Future<void> _openTransform() async {
    final p = _project!;
    var snapped = false;
    void snap() { if (!snapped) { _snapshot(); snapped = true; } }
    Widget posSlider(String label, double value, double lim, ValueChanged<double> onChanged) {
      final enabled = lim > 0.0001;
      final l = enabled ? lim : 0.5;
      return Row(children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w500, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(activeTrackColor: _kAccent, thumbColor: Colors.white, inactiveTrackColor: AppColors.line, trackHeight: 4, overlayColor: _kAccent.withOpacity(0.15), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5, elevation: 1.5)),
            child: Slider(value: value.clamp(-l, l), min: -l, max: l, onChanged: enabled ? onChanged : null),
          ),
        ),
        SizedBox(width: 46, child: Text('${(value * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 12, fontFamily: 'IBMPlexMono'))),
      ]);
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        final lim = _videoPanLimit(p.videoScale);
        final changed = p.videoScale != 1.0 || p.videoDx != 0 || p.videoDy != 0 || p.videoFitContain;
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 16 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: _Grabber()),
                const Text('Transform', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Scale and position the video inside the frame.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                const SizedBox(height: 14),
                // Scale — now goes BELOW 1× (client: scale the video down).
                _fadeRowGeneric('Scale', p.videoScale, 0.25, 4.0, (v) {
                  snap();
                  setSheet(() {
                    p.videoScale = v;
                    final l = _videoPanLimit(v);
                    p.videoDx = p.videoDx.clamp(-l, l);
                    p.videoDy = p.videoDy.clamp(-l, l);
                    setState(() {});
                  });
                }, suffix: 'x'),
                posSlider('Position X', p.videoDx, lim, (v) { snap(); setSheet(() { p.videoDx = v; setState(() {}); }); }),
                posSlider('Position Y', p.videoDy, lim, (v) { snap(); setSheet(() { p.videoDy = v; setState(() {}); }); }),
                if (lim <= 0.0001)
                  const Padding(padding: EdgeInsets.only(top: 2), child: Text('Zoom in or scale down to reposition.', style: TextStyle(color: AppColors.inkFaint, fontSize: 11, fontFamily: 'IBMPlexMono'))),
                const SizedBox(height: 14),
                // Fit vs Fill + the background fill shown behind a scaled-down / letterboxed video.
                Row(children: [
                  _fitChip('Fill', !p.videoFitContain, () { _mutate(() => p.videoFitContain = false); setSheet(() {}); }),
                  const SizedBox(width: 10),
                  _fitChip('Fit', p.videoFitContain, () { _mutate(() => p.videoFitContain = true); setSheet(() {}); }),
                  const Spacer(),
                  const Text('BG', style: TextStyle(color: AppColors.inkMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  _bgSwatch(0xFF000000, p.videoBgColor == 0xFF000000, () { _mutate(() => p.videoBgColor = 0xFF000000); setSheet(() {}); }),
                  const SizedBox(width: 8),
                  _bgSwatch(0xFFFFFFFF, p.videoBgColor == 0xFFFFFFFF, () { _mutate(() => p.videoBgColor = 0xFFFFFFFF); setSheet(() {}); }),
                ]),
                if (changed) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () { _mutate(() { p.videoScale = 1.0; p.videoDx = 0; p.videoDy = 0; p.videoFitContain = false; }); setSheet(() {}); },
                      icon: const Icon(Icons.restart_alt_rounded, size: 18, color: _kAccent),
                      label: const Text('Reset', style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700)),
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

  Future<void> _pickAspect() async {
    final p = _project!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 16 + MediaQuery.of(context).viewPadding.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: _Grabber()),
                const Text('Aspect ratio', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Pick a ratio & fit. Use Transform to scale and position the video.', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                const SizedBox(height: 14),
                // Ratio pills
                Wrap(spacing: 9, runSpacing: 9, children: [
                  for (final opt in AspectOption.all)
                    GestureDetector(
                      onTap: () { _mutate(() => p.aspect = opt); setSheet(() {}); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: opt == p.aspect ? _kAccent : _kChip,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: opt == p.aspect ? _kAccent : AppColors.line),
                        ),
                        child: Text(opt.label, style: TextStyle(color: opt == p.aspect ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13.5)),
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
                    const Text('BG', style: TextStyle(color: AppColors.inkMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    _bgSwatch(0xFF000000, p.videoBgColor == 0xFF000000, () { _mutate(() => p.videoBgColor = 0xFF000000); setSheet(() {}); }),
                    const SizedBox(width: 8),
                    _bgSwatch(0xFFFFFFFF, p.videoBgColor == 0xFFFFFFFF, () { _mutate(() => p.videoBgColor = 0xFFFFFFFF); setSheet(() {}); }),
                  ],
                ]),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', icon: Icons.check, onPressed: () => Navigator.pop(context))),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool danger = false, bool active = false}) {
    final c = danger ? AppColors.errText : (active ? Colors.white : AppColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: active ? AppColors.brand : _kChip,
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

/// Spec §4.6 sheet grabber — 38×4 lineStrong pill.
class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) => Container(
        width: 38, height: 4, margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(999)),
      );
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
        decoration: BoxDecoration(color: Color(preview), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: TextField(
          controller: _ctl,
          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontFamily: 'monospace', letterSpacing: 1),
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
            hintStyle: const TextStyle(color: AppColors.inkFaint),
            filled: true, fillColor: AppColors.surface, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
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
      Text(widget.label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 11, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      TextField(
        controller: _c,
        focusNode: _f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'IBMPlexMono'),
        cursorColor: _kAccent,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
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
      Text(widget.label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        controller: _c, focusNode: _f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'IBMPlexMono'),
        cursorColor: _kAccent,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          filled: true, fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
        ),
      ),
    ]);
  }
}
