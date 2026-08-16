import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../widgets/premium_empty_state.dart';

/// On-device export history — lists MP4 files written by ExportService.
class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key});
  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  late Future<List<FileSystemEntity>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FileSystemEntity>> _load() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports');
    if (!dir.existsSync()) return [];
    final files = dir.listSync().where((f) => f.path.endsWith('.mp4')).toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  String _size(FileSystemEntity f) {
    final bytes = f.statSync().size;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My exports', style: TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: FutureBuilder<List<FileSystemEntity>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(child: Column(children: [
                  Text("Couldn't load your exports.", style: TextStyle(color: Colors.grey.shade600)),
                  TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Retry', style: TextStyle(color: Color(0xFFE01A48), fontWeight: FontWeight.w800))),
                ])),
              ]);
            }
            final files = snap.data ?? [];
            if (files.isEmpty) {
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
              itemCount: files.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final f = files[i];
                final name = f.path.split(Platform.pathSeparator).last;
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    leading: Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                    ),
                    title: Text(name.replaceAll('clip_', 'Export ').replaceAll('.mp4', ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text('${_size(f)} · saved to Gallery', style: const TextStyle(fontSize: 12)),
                    trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.withOpacity(0.5)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
