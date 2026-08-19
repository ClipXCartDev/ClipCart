import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';

/// A saved editor project on disk — enough metadata to list it (name, thumb,
/// when) plus the full serialized [EditorProject] to reopen and keep editing.
class SavedProject {
  SavedProject({
    required this.id,
    required this.name,
    required this.clipId,
    required this.thumb,
    required this.updatedAt,
    required this.data,
  });

  final String id;
  String name;
  final String? clipId; // catalog clip id (null for picked local files)
  final String? thumb; // network thumbnail url (from the catalog clip)
  final DateTime updatedAt;
  final Map<String, dynamic> data; // EditorProject.toProjectJson()

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'clipId': clipId,
        'thumb': thumb,
        'updatedAt': updatedAt.toIso8601String(),
        'data': data,
      };

  factory SavedProject.fromJson(Map<String, dynamic> j) => SavedProject(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Untitled',
        clipId: j['clipId'] as String?,
        thumb: j['thumb'] as String?,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        data: Map<String, dynamic>.from(j['data'] as Map),
      );

  EditorProject toProject() => EditorProject.fromProjectJson(data);
}

/// On-device store for in-progress editor projects. One JSON file per project
/// under `app-docs/projects/`. Deliberately simple (no DB) per the lean budget —
/// the client wants "saved progress that I can continue OR delete so the app
/// doesn't bloat", which a flat folder of JSON handles perfectly.
class ProjectStore {
  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/projects');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<List<SavedProject>> list() async {
    final dir = await _dir();
    final out = <SavedProject>[];
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        out.add(SavedProject.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {/* skip a corrupt file */}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // newest first
    return out;
  }

  Future<SavedProject?> get(String id) async {
    final f = File('${(await _dir()).path}/$id.json');
    if (!f.existsSync()) return null;
    try {
      return SavedProject.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SavedProject p) async {
    final f = File('${(await _dir()).path}/${p.id}.json');
    await f.writeAsString(jsonEncode(p.toJson()));
  }

  Future<void> delete(String id) async {
    final f = File('${(await _dir()).path}/$id.json');
    if (f.existsSync()) await f.delete();
  }
}
