import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';

class StickerItem {
  StickerItem({required this.emoji, required this.cp, required this.url});
  final String? emoji;
  final String cp; // codepoint key
  final String url; // R2 presigned
}

class StickerCategory {
  StickerCategory(this.name, this.items);
  final String name;
  final List<StickerItem> items;
}

/// Loads the R2-hosted emoji/sticker library (GET /assets/stickers) and caches
/// downloaded PNGs on disk so the same sticker is fetched once. Used for the
/// picker grid and to get a crisp PNG for compositing into the export.
class StickerService extends ChangeNotifier {
  StickerService(this._api);
  final ApiClient _api;

  List<StickerCategory> categories = [];
  String? attribution;
  bool _loaded = false;
  bool loading = false;
  String? error;

  Future<void> ensureLoaded() async {
    if (_loaded || loading) return;
    loading = true;
    notifyListeners();
    try {
      final r = await _api.dio.get('/assets/stickers');
      final data = r.data as Map<String, dynamic>;
      attribution = data['attribution'] as String?;
      categories = [
        for (final c in (data['categories'] as List? ?? []))
          StickerCategory(
            c['name'] as String,
            [
              for (final it in (c['items'] as List? ?? []))
                StickerItem(emoji: it['emoji'] as String?, cp: it['cp'] as String, url: it['url'] as String),
            ],
          ),
      ];
      _loaded = categories.isNotEmpty;
      error = null;
    } catch (e) {
      error = 'Could not load stickers';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Downloads (once, cached) the sticker PNG to disk and returns its path.
  Future<String> download(StickerItem it) async {
    final dir = await getApplicationSupportDirectory();
    final d = Directory('${dir.path}/stickers')..createSync(recursive: true);
    final path = '${d.path}/${it.cp}.png';
    final f = File(path);
    if (f.existsSync() && f.lengthSync() > 0) return path;
    await Dio().download(it.url, path); // signed URL — no auth header needed
    return path;
  }
}
