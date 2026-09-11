import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A saved text-layer layout — the positions, sizes, fonts, colours, shadows
/// and animations of a project's text/logo overlays, captured once and reused
/// on any other clip. Meme pages very often reuse one exact caption layout
/// across many different source clips; this is that "paste the layout, keep
/// the video" move. Scoped to text layers only (`SubtitleSegment` — the logo
/// mark included, since it's a text layer too): positions are stored as 0..1
/// fractions so they hold on any aspect ratio, and font files already live in
/// a stable app-support path (same as any saved draft), so nothing dangles.
class LayoutTemplate {
  LayoutTemplate(this.name, this.subtitles, {DateTime? savedAt}) : savedAt = savedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final String name;
  final List<Map<String, dynamic>> subtitles; // raw SubtitleSegment.toJson() each
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {'name': name, 'subtitles': subtitles, 'savedAt': savedAt.toIso8601String()};

  factory LayoutTemplate.fromJson(Map<String, dynamic> j) => LayoutTemplate(
        j['name'] as String,
        (j['subtitles'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? ''),
      );
}

class LayoutTemplateService extends ChangeNotifier {
  List<LayoutTemplate> templates = [];
  bool _loaded = false;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/layout_templates.json');
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as List;
        templates = raw.map((e) => LayoutTemplate.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        templates.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      }
    } catch (_) {
      templates = [];
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(templates.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  /// Saves under `name`, replacing any existing template of the same name.
  Future<void> save(String name, List<Map<String, dynamic>> subtitles) async {
    templates.removeWhere((t) => t.name == name);
    templates.insert(0, LayoutTemplate(name, subtitles, savedAt: DateTime.now()));
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String name) async {
    templates.removeWhere((t) => t.name == name);
    await _persist();
    notifyListeners();
  }
}
