import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
            final files = snap.data ?? [];
            if (files.isEmpty) {
              return ListView(children: const [SizedBox(height: 140), Center(child: Text('No exports yet.\nEdit a clip and export.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: files.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final f = files[i];
                final name = f.path.split(Platform.pathSeparator).last;
                return ListTile(
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.movie, color: Colors.white),
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size(f)),
                  trailing: const Icon(Icons.play_circle_outline),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
