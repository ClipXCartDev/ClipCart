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
  double _snapAngle(double rad) {
    const step = 15 * 3.1415926535 / 180;
    final n = (rad / step).round();
    return ((rad - n * step).abs() < 0.05) ? n * step : rad;
  }

  // gesture start state
  double _gDx = 0, _gDy = 0, _gScale = 1, _gRot = 0, _gDist = 1, _gAngle = 0;

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
      _defaultFont = await context.read<FontService>().ensureDefaultFont();
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
    await _vc?.dispose();
    final c = VideoPlayerController.file(File(path));
    await c.initialize();
    await c.setLooping(true);
    if (!mounted) {
      await c.dispose(); // backed out during init — don't leak the decoder
      return;
    }
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
    _textCtl.dispose();
    _textFocus.dispose();
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

  // ---------- subtitle ops (inline, CapCut-style — video stays visible) ----------
  double _topZ() {
    var m = _project!.logoPath != null ? _project!.logoZ : 0.0;
    for (final s in _project!.subtitles) {
      if (s.z > m) m = s.z;
    }
    return m + 1;
  }

  void _addSubtitle() {
    _snapshot();
    final seg = SubtitleSegment(text: '', start: _t, end: (_t + 3).clamp(0, _duration), z: _topZ());
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

  /// Advanced font/timing sheet (opened from the Font tool), not the primary flow.
  Future<void> _openStyleSheet() async {
    if (_selected is! SubtitleSegment) return;
    final s = _selected as SubtitleSegment;
    final fonts = context.read<FontService>().fonts;
    final res = await showModalBottomSheet<SubtitleSegment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubtitleEditorSheet(duration: _duration, fonts: fonts, initial: s),
    );
    if (res != null) {
      _snapshot();
      res.dx = s.dx;
      res.dy = s.dy;
      res.scale = s.scale;
      res.rotation = s.rotation;
      setState(() {
        final i = _project!.subtitles.indexOf(s);
        if (i >= 0) _project!.subtitles[i] = res;
        _selected = res;
      });
    }
  }

  // ---------- layers panel (CapCut-style: reorder z, select, hide, delete) ----------
  void _openLayers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        final ordered = <MapEntry<double, Object>>[
          for (final s in _project!.subtitles) MapEntry(s.z, s),
          if (_project!.logoPath != null) MapEntry(_project!.logoZ, 'logo'),
        ]..sort((a, b) => b.key.compareTo(a.key)); // top layer first

        void reassign() {
          for (var i = 0; i < ordered.length; i++) {
            final z = (ordered.length - i).toDouble();
            final it = ordered[i].value;
            if (it is SubtitleSegment) {
              it.z = z;
            } else {
              _project!.logoZ = z;
            }
          }
        }

        Widget rowFor(Object it) {
          final isLogo = it == 'logo';
          final s = it is SubtitleSegment ? it : null;
          final hidden = isLogo ? _project!.logoHidden : (s?.hidden ?? false);
          final selected = isLogo ? _selected == 'logo' : identical(_selected, s);
          return Container(
            key: isLogo ? const ValueKey('logo') : ObjectKey(s),
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
                child: Icon(isLogo ? Icons.image_outlined : Icons.title, color: Colors.white70, size: 18),
              ),
              title: Text(isLogo ? 'Logo' : (s!.text.trim().isEmpty ? 'Text' : s.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: hidden ? Colors.white38 : Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              onTap: () {
                setState(() => _selected = isLogo ? 'logo' : s);
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
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 22),
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
  Widget _inlineTextEditor() {
    final s = _selected is SubtitleSegment ? _selected as SubtitleSegment : null;
    const colors = [0xFFFFFFFF, 0xFF000000, 0xFFFF4D6D, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFFFF7A00, 0xFF9B5DE5];
    return Container(
      color: _kPanel,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // one-tap style presets
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final p in _textPresets) _presetChip(s, p),
          ]),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in colors)
              GestureDetector(
                onTap: () => setState(() => s?.color = c),
                child: Container(
                  width: 30, height: 30, margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: s?.color == c ? _kAccent : Colors.white24, width: s?.color == c ? 3 : 1)),
                ),
              ),
            _miniToggle(Icons.border_color, (s?.strokeWidth ?? 0) > 0, () => setState(() => s?.strokeWidth = (s.strokeWidth) > 0 ? 0 : 4)),
            _miniToggle(Icons.title, s?.bgEnabled ?? false, () => setState(() => s?.bgEnabled = !(s.bgEnabled))),
            _miniToggle(_alignIcon(s?.align ?? TextAlignH.center), true, () => setState(() => s?.align = TextAlignH.values[((s.align.index) + 1) % 3])),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _textCtl,
              focusNode: _textFocus,
              autofocus: true,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              cursorColor: _kAccent,
              textInputAction: TextInputAction.done,
              onChanged: (v) => setState(() => s?.text = v),
              onSubmitted: (_) => _doneTyping(),
              decoration: InputDecoration(
                hintText: 'Type your text…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true, fillColor: Colors.white10, isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _doneTyping,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A59), _kAccent]), borderRadius: BorderRadius.circular(12)),
              child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
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
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg ? Color(p['bgc'] as int) : Colors.white10,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white24),
        ),
        child: Text('Aa', style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 16,
          shadows: sw > 0 ? [for (final o in const [Offset(-1, -1), Offset(1, 1), Offset(1, -1), Offset(-1, 1)]) Shadow(color: Color(p['sc'] as int), offset: o)] : null,
        )),
      ),
    );
  }

  Widget _miniToggle(IconData i, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 30, margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: on ? _kAccent : _kChip, borderRadius: BorderRadius.circular(8)),
          child: Icon(i, size: 16, color: Colors.white),
        ),
      );

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
    // Gate (Pro-access + monthly quota) at export time, not on editor open.
    if (widget.clip != null) {
      try {
        await context.read<CatalogService>().recordExport(widget.clip!.id);
      } on DioException catch (e) {
        final detail = e.response?.data is Map ? (e.response!.data['detail']) : null;
        final msg = e.response?.statusCode == 402
            ? (detail is Map && detail['message'] != null ? detail['message'].toString() : 'Subscribe to export this clip')
            : 'Could not start export. Try again.';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error ?? 'Loading…', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
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
      body: Column(
        children: [
          Expanded(child: _canvas()),
          if (_typing)
            _inlineTextEditor()
          else ...[
            _playbar(),
            _timeline(),
            _toolbar(),
          ],
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
                final overlays = <MapEntry<double, Widget>>[
                  for (final s in subs) MapEntry(s.z, _subOverlay(s, w, h, scale)),
                  if (_project!.logoPath != null && !_project!.logoHidden) MapEntry(_project!.logoZ, _logoOverlay(w, h)),
                ]..sort((a, b) => a.key.compareTo(b.key));
                return Stack(
                  key: _canvasKey,
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

  Widget _subOverlay(SubtitleSegment s, double w, double h, double scale) {
    final selected = identical(_selected, s);
    bool moved = false;
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
          fontSize: (s.effectiveSize * scale).clamp(9, 90),
          fontWeight: FontWeight.w800,
          height: 1.15,
          shadows: s.strokeWidth > 0
              ? [for (final o in const [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)]) Shadow(color: Color(s.strokeColor), offset: o * (s.strokeWidth * scale).clamp(0.5, 4))]
              : const [Shadow(color: Colors.black54, blurRadius: 3)],
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
            moved = false;
            _gDx = s.dx;
            _gDy = s.dy;
            _gScale = s.scale;
            _gRot = s.rotation;
          },
          onScaleUpdate: (d) => setState(() {
            if (!moved) {
              _snapshot();
              moved = true;
            }
            _gDx = (_gDx + d.focalPointDelta.dx / w).clamp(0.0, 1.0).toDouble();
            _gDy = (_gDy + d.focalPointDelta.dy / h).clamp(0.0, 1.0).toDouble();
            s.dx = _snap(_gDx, 0.5).clamp(0.03, 0.97).toDouble();
            s.dy = _snap(_gDy, 0.5).clamp(0.03, 0.97).toDouble();
            _snapX = (s.dx - 0.5).abs() < 0.001;
            _snapY = (s.dy - 0.5).abs() < 0.001;
            if (d.scale != 1.0) s.scale = (_gScale * d.scale).clamp(0.4, 4.0);
            if (d.rotation != 0) s.rotation = _snapAngle(_gRot + d.rotation);
            _hint = '${(s.scale * 100).round()}%   ${_deg(s.rotation)}°';
          }),
          onScaleEnd: (_) => setState(() {
            _snapX = _snapY = false;
            _hint = null;
          }),
          child: Transform.rotate(angle: s.rotation, child: text),
        ),
        if (selected) Positioned(right: -11, bottom: -11, child: _resizeHandle(s, w, h, rotate: true)),
      ]),
    );
  }

  /// One-finger corner handle: drag to scale (text) or scale+rotate (logo).
  Widget _resizeHandle(Object target, double w, double h, {required bool rotate}) {
    Offset center() {
      if (target is SubtitleSegment) return Offset(target.dx * w, target.dy * h);
      return Offset(_project!.logoDx * w, _project!.logoDy * h);
    }

    bool moved = false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) {
        moved = false;
        final f = _toCanvas(d.globalPosition);
        final c = center();
        _gDist = f == null ? 1 : math.max(8, (f - c).distance);
        _gAngle = f == null ? 0 : math.atan2(f.dy - c.dy, f.dx - c.dx);
        _gScale = target is SubtitleSegment ? target.scale : _project!.logoScale;
        _gRot = target is SubtitleSegment ? target.rotation : _project!.logoRotation;
      },
      onPanUpdate: (d) => setState(() {
        if (!moved) {
          _snapshot();
          moved = true;
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
        } else {
          _project!.logoScale = ns;
          _project!.logoRotation = nr;
        }
        _hint = '${(ns * 100).round()}%   ${_deg(nr)}°';
      }),
      onPanEnd: (_) => setState(() => _hint = null),
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
    bool moved = false;
    return Align(
      alignment: Alignment(p.logoDx * 2 - 1, p.logoDy * 2 - 1),
      child: Stack(clipBehavior: Clip.none, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = 'logo'),
          onScaleStart: (d) {
            setState(() => _selected = 'logo');
            moved = false;
            _gDx = p.logoDx;
            _gDy = p.logoDy;
            _gScale = p.logoScale;
            _gRot = p.logoRotation;
          },
          onScaleUpdate: (d) => setState(() {
            if (!moved) {
              _snapshot();
              moved = true;
            }
            _gDx = (_gDx + d.focalPointDelta.dx / w).clamp(0.0, 1.0).toDouble();
            _gDy = (_gDy + d.focalPointDelta.dy / h).clamp(0.0, 1.0).toDouble();
            p.logoDx = _snap(_gDx, 0.5).clamp(0.03, 0.97).toDouble();
            p.logoDy = _snap(_gDy, 0.5).clamp(0.03, 0.97).toDouble();
            _snapX = (p.logoDx - 0.5).abs() < 0.001;
            _snapY = (p.logoDy - 0.5).abs() < 0.001;
            if (d.scale != 1.0) p.logoScale = (_gScale * d.scale).clamp(0.3, 4.0);
            p.logoRotation = _snapAngle(_gRot + d.rotation);
            _hint = '${(p.logoScale * 100).round()}%   ${_deg(p.logoRotation)}°';
          }),
          onScaleEnd: (_) => setState(() {
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
        if (selected) Positioned(right: -11, bottom: -11, child: _resizeHandle('logo', w, h, rotate: true)),
      ]),
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
            _pill('Layers', Icons.layers_rounded, _openLayers),
            const SizedBox(width: 8),
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
        _tool(Icons.text_format, 'Font', _openStyleSheet),
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
