import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../widgets/premium_empty_state.dart';

class _Export {
  _Export(this.file, this.thumb, this.modified, this.sizeMb);
  final File file;
  final File? thumb; // poster-frame sidecar
  final DateTime modified;
  final double sizeMb;
}

/// My exports — on-device rendered MP4s with a name + poster thumbnail. Tapping
/// opens a player/detail (client: exports mein name+thumbnail dikhe, tap par
/// direct share na ho — pehle dikhe kaunsi video hai).
class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key});
  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  late Future<List<_Export>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Export>> _load() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports');
    if (!dir.existsSync()) return [];
    final out = <_Export>[];
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4'))) {
      final stat = f.statSync();
      final thumbPath = f.path.replaceAll('.mp4', '.jpg');
      final thumb = File(thumbPath);
      out.add(_Export(f, thumb.existsSync() ? thumb : null, stat.modified, stat.size / (1024 * 1024)));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  String _name(_Export e) {
    final base = e.file.path.split(Platform.pathSeparator).last;
    // clip_1699999999999.mp4 → "Export · 24 Aug, 3:14 PM"-ish readable label
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = e.modified;
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    final t = '$hh:${d.minute.toString().padLeft(2, '0')} $ap';
    if (base.startsWith('clip_')) return 'Export · ${d.day} ${m[d.month - 1]}, $t';
    return base.replaceAll('.mp4', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My exports', style: TextStyle(fontWeight: FontWeight.w700)), centerTitle: false),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: FutureBuilder<List<_Export>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(child: Column(children: [
                  Text("Couldn't load your exports.", style: TextStyle(color: AppColors.mut)),
                  TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Retry', style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.w800))),
                ])),
              ]);
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                PremiumEmptyState(
                  icon: Icons.movie_creation_outlined,
                  title: 'No exports yet',
                  subtitle: 'Pick a clip, customize it in the editor,\nand your exports will show up here.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = items[i];
                return GestureDetector(
                  onTap: () => _openDetail(e),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      // poster thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: SizedBox(
                          width: 60, height: 60,
                          child: e.thumb != null
                              ? Stack(fit: StackFit.expand, children: [
                                  Image.file(e.thumb!, fit: BoxFit.cover),
                                  const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 26)),
                                ])
                              : const DecoratedBox(
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: AppColors.gradient)),
                                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_name(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                          const SizedBox(height: 3),
                          Text('${e.sizeMb.toStringAsFixed(1)} MB · saved to Gallery', style: TextStyle(color: AppColors.mut, fontSize: 12)),
                        ]),
                      ),
                      IconButton(icon: const Icon(Icons.ios_share_rounded, color: AppColors.accent), onPressed: () => _share(e.file.path)),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDetail(_Export e) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ExportDetail(path: e.file.path, title: _name(e), onShare: () => _share(e.file.path), onDelete: () async {
        await e.file.delete();
        if (e.thumb != null && e.thumb!.existsSync()) await e.thumb!.delete();
      }),
    ));
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _share(String path) async {
    try {
      await Share.shareXFiles([XFile(path)], text: 'Made with ClipCart');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share — the video is in your Gallery (ClipCart album).')));
    }
  }
}

/// Full-screen player + share/delete for one export. Opening this is what makes
/// tapping an export show the video FIRST (not immediately share it).
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
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFF04438), fontWeight: FontWeight.w800))),
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
            : const CircularProgressIndicator(color: AppColors.accent),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: widget.onShare,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
      ),
    );
  }
}
