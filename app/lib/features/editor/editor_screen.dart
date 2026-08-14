import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip.dart';
import '../../models/editor_state.dart';
import '../../services/catalog_service.dart';
import '../../services/export_service.dart';
import '../../services/font_service.dart';
import '../../widgets/primary_button.dart';
import 'subtitle_editor_sheet.dart';

const _kBg = Color(0xFF0B0A0C);
const _kPanel = Color(0xFF161318);
const _kAccent = Color(0xFFFF4D6D);

/// Professional layers-based editor: draggable overlays on a dark canvas, timeline,
/// tools bar. Timed subtitle layers + logo, exported on-device via FFmpeg.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.clip, this.title});
  final Clip? clip;
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

  // selection: a SubtitleSegment, or the sentinel 'logo', or null
  Object? _selected;

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
      _project = EditorProject(baseClipPath: path, defaultFontPath: _defaultFont ?? '');
      _error = null;
    });
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  double get _duration => (_vc?.value.duration.inMilliseconds ?? 0) / 1000.0;
  double get _t => (_vc?.value.position.inMilliseconds ?? 0) / 1000.0;

  Future<void> _addSubtitle() async {
    final start = _t;
    final seg = SubtitleSegment(text: '', start: start, end: (start + 3).clamp(0, _duration));
    final res = await _openSheet(seg);
    if (res != null) {
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
      res.dx = s.dx;
      res.dy = s.dy;
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
      builder: (_) => SubtitleEditorSheet(duration: _duration, fonts: fonts, initial: initial),
    );
  }

  void _deleteSelected() {
    setState(() {
      if (_selected is SubtitleSegment) _project!.subtitles.remove(_selected);
      if (_selected == 'logo') _project!.logoPath = null;
      _selected = null;
    });
  }

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.single.path != null) {
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

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final res = await ExportService().export(_project!);
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Exported 🎉'),
            content: Text(res.savedToGallery
                ? 'Saved to your Gallery (ClipCart album) 📱\nShare it to Instagram from there.'
                : 'Saved on device:\n${res.path}'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
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
        title: Text(widget.title ?? 'Editor', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SizedBox(width: 118, child: PrimaryButton(label: 'Export', icon: Icons.ios_share, loading: _busy, onPressed: _busy ? null : _export)),
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

  // ---- canvas with draggable overlays ----
  Widget _canvas() {
    return Center(
      child: AspectRatio(
        aspectRatio: _vc!.value.aspectRatio == 0 ? 9 / 16 : _vc!.value.aspectRatio,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            final videoH = _vc!.value.size.height == 0 ? 1280.0 : _vc!.value.size.height;
            final scale = h / videoH; // WYSIWYG font scaling
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
                    for (final s in subs) _subOverlay(s, w, h, scale),
                    if (_project!.logoPath != null) _logoOverlay(w, h),
                    if (!v.isPlaying)
                      IgnorePointer(
                        child: Center(child: Icon(Icons.play_arrow_rounded, size: 54, color: Colors.white.withOpacity(0.55))),
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

  Widget _subOverlay(SubtitleSegment s, double w, double h, double scale) {
    final selected = identical(_selected, s);
    return Align(
      alignment: Alignment(s.dx * 2 - 1, s.dy * 2 - 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = s),
        onPanUpdate: (d) => setState(() {
          _selected = s;
          s.dx = (s.dx + d.delta.dx / w).clamp(0.05, 0.95);
          s.dy = (s.dy + d.delta.dy / h).clamp(0.05, 0.95);
        }),
        child: Container(
          constraints: BoxConstraints(maxWidth: w * 0.9),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(4),
            border: selected ? Border.all(color: _kAccent, width: 1.5) : null,
          ),
          child: Text(
            s.text.isEmpty ? 'Text' : s.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: s.fontFamily,
              color: s.uiColor,
              fontSize: (s.fontSize * scale).clamp(10, 60),
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoOverlay(double w, double h) {
    final selected = _selected == 'logo';
    return Align(
      alignment: Alignment(_project!.logoDx * 2 - 1, _project!.logoDy * 2 - 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = 'logo'),
        onPanUpdate: (d) => setState(() {
          _selected = 'logo';
          _project!.logoDx = (_project!.logoDx + d.delta.dx / w).clamp(0.05, 0.95);
          _project!.logoDy = (_project!.logoDy + d.delta.dy / h).clamp(0.05, 0.95);
        }),
        child: Container(
          decoration: BoxDecoration(border: selected ? Border.all(color: _kAccent, width: 1.5) : null),
          child: Image.file(File(_project!.logoPath!), width: w * 0.18),
        ),
      ),
    );
  }

  // ---- playbar ----
  Widget _playbar() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vc!,
      builder: (context, v, _) {
        return Container(
          color: _kBg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            IconButton(
              icon: Icon(v.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: 30),
              onPressed: () => setState(() => v.isPlaying ? _vc!.pause() : _vc!.play()),
            ),
            Text(
              '${_fmt(v.position)} / ${_fmt(v.duration)}',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60)}:${(d.inSeconds.remainder(60)).toString().padLeft(2, '0')}';

  // ---- timeline (subtitle track) ----
  Widget _timeline() {
    final dur = _duration;
    return Container(
      height: 64,
      color: const Color(0xFF0F0D12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        double x(double sec) => dur <= 0 ? 0 : (sec / dur) * w;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _vc!,
          builder: (context, v, _) {
            final ph = x(v.position.inMilliseconds / 1000.0);
            return Stack(children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)))),
              for (final s in _project!.subtitles)
                Positioned(
                  left: x(s.start), width: (x(s.end) - x(s.start)).clamp(28, w), top: 6, bottom: 6,
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = s),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]),
                        borderRadius: BorderRadius.circular(7),
                        border: identical(_selected, s) ? Border.all(color: Colors.white, width: 1.5) : null,
                      ),
                      child: Text(s.text.isEmpty ? 'Text' : s.text, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              Positioned(left: ph.clamp(0, w), top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
            ]);
          },
        );
      }),
    );
  }

  // ---- tools bar (contextual) ----
  Widget _toolbar() {
    final subSel = _selected is SubtitleSegment;
    final logoSel = _selected == 'logo';
    final tools = <Widget>[
      _tool(Icons.text_fields, 'Add text', _addSubtitle),
      _tool(Icons.image_outlined, 'Logo', _pickLogo),
      _tool(Icons.font_download_outlined, 'Font', _uploadFont),
      if (subSel) _tool(Icons.tune, 'Edit', _editSelectedSubtitle),
      if (subSel || logoSel) _tool(Icons.delete_outline, 'Delete', _deleteSelected, danger: true),
    ];
    return Container(
      color: _kPanel,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: tools),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final c = danger ? const Color(0xFFF04438) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFF221D24), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: c.withOpacity(0.9), fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
