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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _defaultFont = await context.read<FontService>().ensureDefaultFont();
    if (widget.clip != null) {
      try {
        final path = await context.read<CatalogService>().downloadClipFile(widget.clip!.id);
        await _load(path);
      } catch (e) {
        final gated = e is DioException && e.response?.statusCode == 402;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(gated ? 'Subscribe to use Pro clips' : 'Could not load clip — pick a video')));
        }
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
    setState(() {
      _vc = c;
      _project = EditorProject(baseClipPath: path, defaultFontPath: _defaultFont!);
    });
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  double get _duration => (_vc?.value.duration.inMilliseconds ?? 0) / 1000.0;

  Future<void> _addOrEdit([SubtitleSegment? existing]) async {
    final fonts = context.read<FontService>().fonts;
    final res = await showModalBottomSheet<SubtitleSegment>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SubtitleEditorSheet(duration: _duration, fonts: fonts, initial: existing),
    );
    if (res == null) return;
    setState(() {
      if (existing != null) {
        final i = _project!.subtitles.indexOf(existing);
        _project!.subtitles[i] = res;
      } else {
        _project!.subtitles.add(res);
      }
      _project!.subtitles.sort((a, b) => a.start.compareTo(b.start));
    });
  }

  Future<void> _uploadFont() async {
    final font = await context.read<FontService>().uploadFont();
    if (font != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Font added: ${font.name}')));
    }
  }

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.single.path != null) {
      setState(() => _project!.logoPath = res.files.single.path);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final out = await ExportService().export(_project!);
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Exported 🎉'),
            content: Text('Saved on device:\n$out'),
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
    if (_project == null || _vc == null || !_vc!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'Editor')),
        body: Center(
          child: _defaultFont == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pick a base clip to edit', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    SizedBox(width: 220, child: PrimaryButton(label: 'Choose video', icon: Icons.video_library, onPressed: _pickClip)),
                  ],
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Editor', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SizedBox(
              width: 130,
              child: PrimaryButton(label: 'Export', icon: Icons.download, loading: _busy, onPressed: _busy ? null : _export),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- preview with time-synced subtitle overlay ----
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _vc!.value.aspectRatio == 0 ? 9 / 16 : _vc!.value.aspectRatio,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _vc!,
                  builder: (context, value, _) {
                    final t = value.position.inMilliseconds / 1000.0;
                    final active = _project!.activeAt(t);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(_vc!),
                        if (_project!.logoPath != null)
                          Positioned(top: 10, right: 10, child: Image.file(File(_project!.logoPath!), width: 54)),
                        if (active.isNotEmpty)
                          Positioned(
                            left: 12, right: 12, bottom: 26,
                            child: Text(
                              active.last.text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: active.last.fontFamily,
                                color: active.last.uiColor,
                                fontSize: active.last.fontSize.clamp(14, 34),
                                fontWeight: FontWeight.w800,
                                shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                                backgroundColor: Colors.black45,
                              ),
                            ),
                          ),
                        Center(
                          child: IconButton(
                            iconSize: 54,
                            icon: Icon(value.isPlaying ? Icons.pause_circle : Icons.play_circle, color: Colors.white70),
                            onPressed: () => setState(() => value.isPlaying ? _vc!.pause() : _vc!.play()),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // ---- timeline (subtitle track) ----
          _Timeline(vc: _vc!, project: _project!, onTapSegment: _addOrEdit),
          // ---- tools ----
          Container(
            color: const Color(0xFF161318),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Tool(icon: Icons.subtitles, label: 'Subtitle', onTap: () => _addOrEdit()),
                _Tool(icon: Icons.font_download, label: 'Upload font', onTap: _uploadFont),
                _Tool(icon: Icons.image, label: 'Logo', onTap: _pickLogo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.vc, required this.project, required this.onTapSegment});
  final VideoPlayerController vc;
  final EditorProject project;
  final void Function(SubtitleSegment) onTapSegment;

  @override
  Widget build(BuildContext context) {
    final dur = vc.value.duration.inMilliseconds / 1000.0;
    return Container(
      height: 66,
      color: const Color(0xFF0F0D12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          double x(double sec) => dur <= 0 ? 0 : (sec / dur) * w;
          return ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: vc,
            builder: (context, value, _) {
              final playhead = x(value.position.inMilliseconds / 1000.0);
              return Stack(
                children: [
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)))),
                  for (final s in project.subtitles)
                    Positioned(
                      left: x(s.start),
                      width: (x(s.end) - x(s.start)).clamp(26, w),
                      top: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: () => onTapSegment(s),
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(7)),
                          child: Text(s.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  Positioned(left: playhead.clamp(0, w), top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
