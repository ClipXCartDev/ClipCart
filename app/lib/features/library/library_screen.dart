import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/premium_empty_state.dart';
import '../../widgets/skeleton_grid.dart';
import '../home/home_shell.dart';

/// Library (Revision A §3.0, feedback 11) — the 4th tab. A segmented view over
/// two collections the user owns: Saved templates (hearted clips) and My exports
/// (on-device rendered MP4s, each with name · thumbnail · play · share).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.tabIndex = 3});
  final int tabIndex;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _Export {
  _Export(this.file, this.thumb, this.modified, this.sizeMb);
  final File file;
  final File? thumb;
  final DateTime modified;
  final double sizeMb;
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _seg = 0; // 0 = Saved templates, 1 = My exports
  late Future<List<Clip>> _saved;
  late Future<List<_Export>> _exports;

  @override
  void initState() {
    super.initState();
    _reloadSaved();
    _exports = _loadExports();
    homeTab.addListener(_onTab);
  }

  void _onTab() {
    if (homeTab.value == widget.tabIndex && mounted) {
      _reloadSaved();
      setState(() => _exports = _loadExports());
    }
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTab);
    super.dispose();
  }

  void _reloadSaved() => setState(() => _saved = context.read<CatalogService>().favorites());

  Future<List<_Export>> _loadExports() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports');
    if (!dir.existsSync()) return [];
    final out = <_Export>[];
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4'))) {
      final stat = f.statSync();
      final thumb = File(f.path.replaceAll('.mp4', '.jpg'));
      out.add(_Export(f, thumb.existsSync() ? thumb : null, stat.modified, stat.size / (1024 * 1024)));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const ScreenHeader(title: 'Library'),
          // segmented control: Saved templates | My exports
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                _segTab('Saved templates', 0),
                _segTab('My exports', 1),
              ]),
            ),
          ),
          Expanded(child: _seg == 0 ? _savedView() : _exportsView()),
        ]),
      ),
    );
  }

  Widget _segTab(String label, int i) {
    final on = _seg == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _seg = i),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? Colors.white : AppColors.mut)),
        ),
      ),
    );
  }

  // ---- Saved templates ----
  Widget _savedView() {
    return RefreshIndicator(
      onRefresh: () async => _reloadSaved(),
      child: FutureBuilder<List<Clip>>(
        future: _saved,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const SkeletonGrid(count: 6);
          final clips = snap.data ?? [];
          if (clips.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 60),
              PremiumEmptyState(
                icon: Icons.bookmark_border_rounded,
                title: 'No saved templates yet',
                subtitle: 'Tap the heart on any clip to save it\nas a template for quick access later.',
              ),
            ]);
          }
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 7, crossAxisSpacing: 7, childAspectRatio: 9 / 14),
            itemCount: clips.length,
            itemBuilder: (context, i) => ClipTile(clip: clips[i], aspect: 9 / 14, onTap: () => context.push('/player', extra: {'clips': clips, 'index': i})),
          );
        },
      ),
    );
  }

  // ---- My exports ----
  Widget _exportsView() {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _exports = _loadExports()),
      child: FutureBuilder<List<_Export>>(
        future: _exports,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 60),
              PremiumEmptyState(
                icon: Icons.movie_creation_outlined,
                title: 'No exports yet',
                subtitle: 'Customize a clip in the editor and your\nexports will show up here.',
              ),
            ]);
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == items.length) return _exportsInfo();
              return _exportRow(items[i]);
            },
          );
        },
      ),
    );
  }

  Widget _exportRow(_Export e) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 52, height: 72,
            child: e.thumb != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.file(e.thumb!, fit: BoxFit.cover),
                    const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 22)),
                  ])
                : const DecoratedBox(decoration: BoxDecoration(color: AppColors.dark), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_name(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(_meta(e), style: const TextStyle(fontFamily: kMono, fontSize: 11, color: AppColors.mut)),
            const SizedBox(height: 8),
            Row(children: [
              _exportAction(Icons.play_arrow_rounded, 'Play', () => _openDetail(e)),
              const SizedBox(width: 16),
              _exportAction(Icons.ios_share_rounded, 'Share', () => _share(e.file.path)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _exportAction(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: AppColors.brand),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
        ]),
      );

  Widget _exportsInfo() => Container(
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        padding: const EdgeInsets.all(14),
        child: const Text.rich(TextSpan(children: [
          TextSpan(text: 'Every export keeps its name and thumbnail. ', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 13)),
          TextSpan(text: 'Play opens it full screen instantly; Share sends the MP4 anywhere without leaving the app.', style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.55)),
        ])),
      );

  String _name(_Export e) {
    final base = e.file.path.split(Platform.pathSeparator).last;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = e.modified;
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    if (base.startsWith('clip_')) return 'Export · ${d.day} ${m[d.month - 1]}, $hh:${d.minute.toString().padLeft(2, '0')} $ap';
    return base.replaceAll('.mp4', '');
  }

  String _meta(_Export e) {
    const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${e.sizeMb.toStringAsFixed(1)} MB · ${e.modified.day} ${m[e.modified.month - 1]}';
  }

  Future<void> _openDetail(_Export e) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ExportDetail(path: e.file.path, title: _name(e), onShare: () => _share(e.file.path), onDelete: () async {
        await e.file.delete();
        if (e.thumb != null && e.thumb!.existsSync()) await e.thumb!.delete();
      }),
    ));
    if (mounted) setState(() => _exports = _loadExports());
  }

  Future<void> _share(String path) async {
    try {
      await Share.shareXFiles([XFile(path)], text: 'Made with ClipCart');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share — the video is in your Gallery (ClipCart album).')));
    }
  }
}

/// Full-screen player + share/delete for one export.
class _ExportDetail extends StatefulWidget {
  const _ExportDetail({required this.path, required this.title, required this.onShare, required this.onDelete});
  final String path;
  final String title;
  final VoidCallback onShare;
  final Future<void> Function() onDelete;
  @override
  State<_ExportDetail> createState() => _ExportDetailState();
}

class _ExportDetailState extends State<_ExportDetail> {
  VideoPlayerController? _vc;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (!mounted) return;
        _vc!..setLooping(true)..play();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _vc != null && _vc!.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete export?'),
                  content: const Text('This removes the file from the app. It stays in your Gallery.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.err, fontWeight: FontWeight.w700))),
                  ],
                ),
              );
              if (ok == true) { await widget.onDelete(); if (context.mounted) Navigator.pop(context); }
            },
          ),
        ],
      ),
      body: Center(
        child: ready
            ? GestureDetector(
                onTap: () => setState(() => _vc!.value.isPlaying ? _vc!.pause() : _vc!.play()),
                child: AspectRatio(aspectRatio: _vc!.value.aspectRatio, child: VideoPlayer(_vc!)),
              )
            : const CircularProgressIndicator(color: AppColors.brand),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: widget.onShare,
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand, padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ),
      ),
    );
  }
}
