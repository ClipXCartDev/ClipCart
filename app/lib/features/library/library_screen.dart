import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/premium_empty_state.dart';
import '../../widgets/skeleton_grid.dart';
import '../home/home_shell.dart';

/// §22 My Clips — the tab body (no bottom nav; lives inside home_shell). A
/// segmented view over two collections the user owns: Created (on-device
/// rendered exports) and Liked (hearted catalog clips).
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
  int _seg = 0; // 0 = Created (exports), 1 = Liked (favorites)
  late Future<List<Clip>> _liked;
  late Future<List<_Export>> _exports;

  @override
  void initState() {
    super.initState();
    _reloadLiked();
    _exports = _loadExports();
    homeTab.addListener(_onTab);
  }

  void _onTab() {
    if (homeTab.value == widget.tabIndex && mounted) {
      _reloadLiked();
      setState(() { _exports = _loadExports(); });
    }
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTab);
    super.dispose();
  }

  void _reloadLiked() => setState(() { _liked = context.read<CatalogService>().favorites(); });

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
          const ScreenHeader(title: 'My Clips'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Segmented<int>(
              value: _seg,
              items: const [(0, 'Created'), (1, 'Liked')],
              onChanged: (v) => setState(() => _seg = v),
            ),
          ),
          Expanded(child: _seg == 0 ? _createdView() : _likedView()),
        ]),
      ),
    );
  }

  // ── Created (on-device exports) ────────────────────────────────────────────
  Widget _createdView() {
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () async => setState(() { _exports = _loadExports(); }),
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
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _createdRow(items[i]),
          );
        },
      ),
    );
  }

  Widget _createdRow(_Export e) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.media),
        onTap: () => _openDetail(e),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.media),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _createdThumb(e),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_name(e),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                const SizedBox(height: 5),
                Text(_meta(e), style: T.dataMuted),
                const SizedBox(height: 9),
                StatusPill.gold('Exported · final'),
              ]),
            ),
            const SizedBox(width: 4),
            CircleIconBtn(Icons.more_horiz_rounded, onTap: () => _showExportMenu(e)),
          ]),
        ),
      ),
    );
  }

  Widget _createdThumb(_Export e) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 54,
        height: 72,
        child: Stack(fit: StackFit.expand, children: [
          if (e.thumb != null)
            Image.file(e.thumb!, fit: BoxFit.cover)
          else
            const DecoratedBox(decoration: BoxDecoration(color: AppColors.mediaPlaceholder)),
          Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(color: Color(0xF2FFFFFF), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.ink),
            ),
          ),
        ]),
      ),
    );
  }

  void _showExportMenu(_Export e) {
    showAppSheet(context, (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerLeft, child: Text(_name(e), style: T.section)),
        const SizedBox(height: 14),
        ListCard(children: [
          ListRowTile(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            chevron: false,
            onTap: () {
              Navigator.of(ctx).pop();
              _openDetail(e);
            },
          ),
          ListRowTile(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            chevron: false,
            onTap: () {
              Navigator.of(ctx).pop();
              _share(e.file.path);
            },
          ),
          ListRowTile(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            danger: true,
            chevron: false,
            onTap: () async {
              Navigator.of(ctx).pop();
              await _deleteExport(e);
            },
          ),
        ]),
      ]);
    });
  }

  Future<void> _deleteExport(_Export e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete export?'),
        content: const Text('This removes the file from the app. It stays in your Gallery.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.errText, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await e.file.delete();
      if (e.thumb != null && e.thumb!.existsSync()) await e.thumb!.delete();
    } catch (_) {}
    if (mounted) setState(() { _exports = _loadExports(); });
  }

  // ── Liked (favorited catalog clips) ────────────────────────────────────────
  Widget _likedView() {
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () async => _reloadLiked(),
      child: FutureBuilder<List<Clip>>(
        future: _liked,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SkeletonGrid(count: 6, padding: EdgeInsets.fromLTRB(20, 4, 20, 20));
          }
          final clips = snap.data ?? [];
          if (clips.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 60),
              PremiumEmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'No liked clips yet',
                subtitle: 'Tap the heart on any clip to save it\nhere for quick access later.',
              ),
            ]);
          }
          return LayoutBuilder(builder: (context, c) {
            final itemW = (c.maxWidth - 40 - 14) / 2;
            final extent = itemW * 13 / 9 + 60;
            return GridView.builder(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: extent,
              ),
              itemCount: clips.length,
              itemBuilder: (context, i) => _likedCell(clips, i),
            );
          });
        },
      ),
    );
  }

  Widget _likedCell(List<Clip> clips, int i) {
    final clip = clips[i];
    return GestureDetector(
      onTap: () => context.push('/player', extra: {'clips': clips, 'index': i}),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.media),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(R.media)),
            child: AspectRatio(
            aspectRatio: 9 / 13,
            child: Stack(fit: StackFit.expand, children: [
              const DecoratedBox(decoration: BoxDecoration(color: AppColors.mediaPlaceholder)),
              if (clip.thumb != null)
                CachedNetworkImage(
                  imageUrl: clip.thumb!,
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, __) => const DecoratedBox(decoration: BoxDecoration(color: AppColors.mediaPlaceholder)),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              // filled-heart badge (top-right)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(color: Color(0x99141129), shape: BoxShape.circle),
                  child: const Icon(Icons.favorite_rounded, size: 13, color: Colors.white),
                ),
              ),
              // duration pill (bottom-left)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(color: const Color(0x80000000), borderRadius: BorderRadius.circular(6)),
                  child: Text(clip.durationLabel,
                      style: const TextStyle(color: Colors.white, fontFamily: kMono, fontSize: 9, fontWeight: FontWeight.w500)),
                ),
              ),
            ]),
          ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(clip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 3),
              Text(clip.category ?? clip.genre ?? clip.language,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption),
            ]),
          ),
        ]),
      ),
    );
  }

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
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${e.sizeMb.toStringAsFixed(1)} MB · ${e.modified.day} ${m[e.modified.month - 1]}';
  }

  Future<void> _openDetail(_Export e) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ExportDetail(
          path: e.file.path,
          title: _name(e),
          onShare: () => _share(e.file.path),
          onDelete: () async {
            await e.file.delete();
            if (e.thumb != null && e.thumb!.existsSync()) await e.thumb!.delete();
          }),
    ));
    if (mounted) setState(() { _exports = _loadExports(); });
  }

  Future<void> _share(String path) async {
    try {
      await Share.shareXFiles([XFile(path)], text: 'Made with ClipCart');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not share — the video is in your Gallery (ClipCart album).')));
      }
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
        _vc!
          ..setLooping(true)
          ..play();
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
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete', style: TextStyle(color: AppColors.errText, fontWeight: FontWeight.w700))),
                  ],
                ),
              );
              if (ok == true) {
                await widget.onDelete();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: ready
            ? GestureDetector(
                onTap: () => setState(() { _vc!.value.isPlaying ? _vc!.pause() : _vc!.play(); }),
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
