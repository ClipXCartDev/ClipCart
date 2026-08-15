import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip.dart' as models;
import '../../models/editor_state.dart';
import '../../services/catalog_service.dart';
import '../../services/export_service.dart';
import '../../services/font_service.dart';
import '../../widgets/primary_button.dart';
import 'subtitle_editor_sheet.dart';

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

  final _undo = <Map<String, dynamic>>[];
  final _redo = <Map<String, dynamic>>[];

  // gesture start state
  double _gDx = 0, _gDy = 0, _gScale = 1, _gRot = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _defaultFont = await context.read<FontService>().ensureDefaultFont();
    } catch (_) {
      _defaultFont = '';
    }
    if (widget.clip != null) {
      try {
        final path = await context.read<CatalogService>().downloadClipFile(widget.clip!.id);
        await _load(path);
      } catch (e) {
        _error = (e is DioException && e.response?.statusCode == 402)
            ? 'Subscribe to use Pro clips'
            : 'Could not load the clip';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickClip() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res != null && res.files.single.path != null) await _load(res.files.single.path!);
  }

  Future<void> _load(String path) async {
    await _vc?.dispose();
    final c = VideoPlayerController.file(File(path));
    await c.initialize();
    await c.setLooping(true);
    if (!mounted) return;
    setState(() {
      _vc = c;
      final dur = c.value.duration.inMilliseconds / 1000.0;
      _project = EditorProject(baseClipPath: path, defaultFontPath: _defaultFont ?? '', duration: dur);
      _error = null;
      _undo.clear();
      _redo.clear();
    });
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  double get _duration => (_vc?.value.duration.inMilliseconds ?? 0) / 1000.0;
  double get _t => (_vc?.value.position.inMilliseconds ?? 0) / 1000.0;

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

  // ---------- subtitle ops ----------
  Future<void> _addSubtitle() async {
    final start = _t;
    final seg = SubtitleSegment(text: '', start: start, end: (start + 3).clamp(0, _duration));
    final res = await _openSheet(seg);
    if (res != null) {
      _snapshot();
      setState(() {
        _project!.subtitles.add(res);
        _project!.subtitles.sort((a, b) => a.start.compareTo(b.start));
        _selected = res;
      });
    }
  }

  Future<void> _editSelectedSubtitle() async {
    if (_selected is! SubtitleSegment) return;
    final s = _selected as SubtitleSegment;
    final res = await _openSheet(s);
    if (res != null) {
      _snapshot();
      res.dx = s.dx;
      res.dy = s.dy;
      res.scale = s.scale;
      setState(() {
        final i = _project!.subtitles.indexOf(s);
        _project!.subtitles[i] = res;
        _selected = res;
        _project!.subtitles.sort((a, b) => a.start.compareTo(b.start));
      });
    }
  }

  Future<SubtitleSegment?> _openSheet(SubtitleSegment initial) {
    final fonts = context.read<FontService>().fonts;
    return showModalBottomSheet<SubtitleSegment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubtitleEditorSheet(duration: _duration, fonts: fonts, initial: initial),
    );
  }

  void _duplicateSelected() {
    if (_selected is! SubtitleSegment) return;
    _snapshot();
    final s = (_selected as SubtitleSegment).copy();
    s.dy = (s.dy + 0.06).clamp(0.05, 0.95);
    setState(() {
      _project!.subtitles.add(s);
      _selected = s;
    });
  }

  void _deleteSelected() {
    _snapshot();
    setState(() {
      if (_selected is SubtitleSegment) _project!.subtitles.remove(_selected);
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

  Future<void> _uploadFont() async {
    final f = await context.read<FontService>().uploadFont();
    if (f != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Font added: ${f.name}')));
    }
  }

  void _mutate(VoidCallback fn) {
    _snapshot();
    setState(fn);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: _kPanel,
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5)),
          SizedBox(width: 18),
          Text('Rendering…', style: TextStyle(color: Colors.white)),
        ]),
      ),
    );
    try {
      final res = await ExportService().export(_project!);
      if (mounted) {
        Navigator.pop(context); // close progress
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
      if (mounted) {
        Navigator.pop(context);
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
                  Text(_error ?? 'Loading…', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
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
      body: Column(
        children: [
          Expanded(child: _canvas()),
          _playbar(),
          _timeline(),
          _toolbar(),
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
                final subs = _project!.subtitles.where((s) => identical(_selected, s) || (t >= s.start && t <= s.end));
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        _selected = null;
                        v.isPlaying ? _vc!.pause() : _vc!.play();
                      }),
                      child: VideoPlayer(_vc!),
                    ),
                    if (_project!.aspect.ratio != null) _cropGuide(w, h),
                    for (final s in subs) _subOverlay(s, w, h, scale),
                    if (_project!.logoPath != null) _logoOverlay(w, h),
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

  Widget _subOverlay(SubtitleSegment s, double w, double h, double scale) {
    final selected = identical(_selected, s);
    return Align(
      alignment: Alignment(s.dx * 2 - 1, s.dy * 2 - 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = s),
        onScaleStart: (d) {
          setState(() => _selected = s);
          _gDx = s.dx;
          _gDy = s.dy;
          _gScale = s.scale;
        },
        onScaleUpdate: (d) => setState(() {
          s.dx = (_gDx + d.focalPointDelta.dx / w).clamp(0.03, 0.97);
          s.dy = (_gDy + d.focalPointDelta.dy / h).clamp(0.03, 0.97);
          if (d.scale != 1.0) s.scale = (_gScale * d.scale).clamp(0.4, 4.0);
        }),
        child: Container(
          constraints: BoxConstraints(maxWidth: w * 0.92),
          padding: EdgeInsets.symmetric(horizontal: s.bgEnabled ? 7 : 2, vertical: s.bgEnabled ? 3 : 1),
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
              fontSize: (s.effectiveSize * scale).clamp(9, 90),
              fontWeight: FontWeight.w800,
              height: 1.15,
              shadows: s.strokeWidth > 0
                  ? [for (final o in const [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)]) Shadow(color: Color(s.strokeColor), offset: o * (s.strokeWidth * scale).clamp(0.5, 4))]
                  : const [Shadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoOverlay(double w, double h) {
    final selected = _selected == 'logo';
    final p = _project!;
    return Align(
      alignment: Alignment(p.logoDx * 2 - 1, p.logoDy * 2 - 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = 'logo'),
        onScaleStart: (d) {
          setState(() => _selected = 'logo');
          _gDx = p.logoDx;
          _gDy = p.logoDy;
          _gScale = p.logoScale;
          _gRot = p.logoRotation;
        },
        onScaleUpdate: (d) => setState(() {
          p.logoDx = (_gDx + d.focalPointDelta.dx / w).clamp(0.03, 0.97);
          p.logoDy = (_gDy + d.focalPointDelta.dy / h).clamp(0.03, 0.97);
          if (d.scale != 1.0) p.logoScale = (_gScale * d.scale).clamp(0.3, 4.0);
          p.logoRotation = _gRot + d.rotation;
        }),
        child: Transform.rotate(
          angle: p.logoRotation,
          child: Container(
            decoration: BoxDecoration(border: selected ? Border.all(color: _kAccent, width: 1.5) : null),
            child: Image.file(File(p.logoPath!), width: w * 0.18 * p.logoScale),
          ),
        ),
      ),
    );
  }

  // ---------- playbar ----------
  Widget _playbar() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vc!,
      builder: (context, v, _) {
        return Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
          child: Row(children: [
            IconButton(
              icon: Icon(v.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: 30),
              onPressed: () => setState(() => v.isPlaying ? _vc!.pause() : _vc!.play()),
            ),
            Text('${_fmt(v.position)} / ${_fmt(v.duration)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            _pill(_project!.aspect.label, Icons.crop, _pickAspect),
            const SizedBox(width: 8),
            _pill(_trimMode ? 'Trim ✓' : 'Trim', Icons.content_cut, () => setState(() => _trimMode = !_trimMode), on: _trimMode),
          ]),
        );
      },
    );
  }

  Widget _pill(String label, IconData icon, VoidCallback onTap, {bool on = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: on ? _kAccent : _kChip, borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  String _fmt(Duration d) => '${d.inMinutes.remainder(60)}:${(d.inSeconds.remainder(60)).toString().padLeft(2, '0')}';

  // ---------- timeline (scrub + trim + subtitle track) ----------
  Widget _timeline() {
    final dur = _duration;
    return Container(
      height: 74,
      color: const Color(0xFF0F0D12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        double x(double sec) => dur <= 0 ? 0 : (sec / dur) * w;
        double sec(double px) => dur <= 0 ? 0 : (px / w) * dur;
        final p = _project!;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _vc!,
          builder: (context, v, _) {
            final ph = x(v.position.inMilliseconds / 1000.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _seek(sec(d.localPosition.dx)),
              onHorizontalDragUpdate: _trimMode ? null : (d) => _seek(sec(d.localPosition.dx.clamp(0, w))),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)))),
                // trimmed-out dim regions
                if (p.trimStart > 0) Positioned(left: 0, width: x(p.trimStart), top: 0, bottom: 0, child: _dim()),
                if (p.outEnd < dur) Positioned(left: x(p.outEnd), right: 0, top: 0, bottom: 0, child: _dim()),
                // subtitle blocks
                for (final s in p.subtitles)
                  Positioned(
                    left: x(s.start), width: (x(s.end) - x(s.start)).clamp(24, w), top: 8, bottom: 26,
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = s),
                      onHorizontalDragUpdate: (d) => setState(() {
                        final len = s.end - s.start;
                        s.start = (s.start + sec(d.delta.dx)).clamp(0, dur - len);
                        s.end = s.start + len;
                      }),
                      child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]),
                          borderRadius: BorderRadius.circular(6),
                          border: identical(_selected, s) ? Border.all(color: Colors.white, width: 1.5) : null,
                        ),
                        child: Text(s.text.isEmpty ? 'Text' : s.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                // trim handles
                if (_trimMode) ..._trimHandles(x, sec, w, p, dur),
                // playhead
                Positioned(left: ph.clamp(0, w) - 1, top: -2, bottom: 18, child: Container(width: 2.5, color: Colors.white)),
              ]),
            );
          },
        );
      }),
    );
  }

  Widget _dim() => DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)));

  List<Widget> _trimHandles(double Function(double) x, double Function(double) sec, double w, EditorProject p, double dur) {
    Widget handle(double left, void Function(double) onDrag) => Positioned(
          left: left - 9, top: -2, bottom: 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
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
    final ms = (s.clamp(0, _duration) * 1000).round();
    _vc!.seekTo(Duration(milliseconds: ms));
  }

  // ---------- toolbar (contextual) ----------
  Widget _toolbar() {
    final tools = <Widget>[];
    if (_selected is SubtitleSegment) {
      final s = _selected as SubtitleSegment;
      tools.addAll([
        _tool(Icons.edit, 'Edit', _editSelectedSubtitle),
        _tool(Icons.format_color_text, 'Color', () => _quickColor(s)),
        _tool(s.bgEnabled ? Icons.check_box : Icons.check_box_outline_blank, 'BG', () => _mutate(() => s.bgEnabled = !s.bgEnabled)),
        _tool(Icons.border_color, 'Outline', () => _mutate(() => s.strokeWidth = s.strokeWidth > 0 ? 0 : 3)),
        _tool(_alignIcon(s.align), 'Align', () => _mutate(() => s.align = TextAlignH.values[(s.align.index + 1) % 3])),
        _tool(Icons.copy, 'Copy', _duplicateSelected),
        _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
      ]);
    } else if (_selected == 'logo') {
      tools.addAll([
        _tool(Icons.rotate_left, 'Rotate', () => _mutate(() => _project!.logoRotation -= math.pi / 12)),
        _tool(Icons.rotate_right, '', () => _mutate(() => _project!.logoRotation += math.pi / 12)),
        _tool(Icons.refresh, 'Reset', () => _mutate(() { _project!.logoRotation = 0; _project!.logoScale = 1; })),
        _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
      ]);
    } else {
      tools.addAll([
        _tool(Icons.text_fields, 'Add text', _addSubtitle),
        _tool(Icons.image_outlined, 'Logo', _pickLogo),
        _tool(Icons.font_download_outlined, 'Font', _uploadFont),
      ]);
    }
    return Container(
      color: _kPanel,
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: tools),
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
      builder: (_) => Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(spacing: 14, runSpacing: 14, children: [
          for (final c in colors)
            GestureDetector(
              onTap: () {
                _mutate(() => s.color = c);
                Navigator.pop(context);
              },
              child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == s.color ? _kAccent : Colors.white24, width: c == s.color ? 3 : 1))),
            ),
        ]),
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

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final c = danger ? const Color(0xFFF04438) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: _kChip, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: c, size: 22)),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(label, style: TextStyle(color: c.withOpacity(0.9), fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }
}
