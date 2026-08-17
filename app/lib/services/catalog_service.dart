import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/runtime_config.dart';
import '../models/clip.dart';

class CatalogService {
  CatalogService(this.api);
  final ApiClient api;

  /// Access-gated download of the base clip, cached on disk so repeat opens are instant.
  Future<String> downloadClipFile(String clipId) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/base_$clipId.mp4';
    final f = File(path);
    if (await f.exists() && await f.length() > 0) return path; // cached -> instant load

    final r = await api.dio.post('/clips/$clipId/download-url');
    final url = RuntimeConfig.absolute(r.data['url'] as String);
    await Dio().download(url, path); // plain Dio: signed URL needs no auth header
    return path;
  }

  /// Presigned muted-preview URL for the reels player (no download recorded).
  Future<String> previewUrl(String clipId) async {
    final r = await api.dio.post('/clips/$clipId/preview-url');
    return RuntimeConfig.absolute(r.data['url'] as String);
  }

  /// Download the FULL-QUALITY raw base clip for EDITING (not the 720p reels
  /// preview) — editing + export must be high quality. Free (no quota/record);
  /// the gate is on export. Atomic (tmp → rename) so a failed download never
  /// leaves a corrupt cache. `fresh: true` forces a re-download.
  Future<String> editClipFile(String clipId, {bool fresh = false}) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/base_$clipId.mp4';
    final f = File(path);
    if (fresh && await f.exists()) await f.delete();
    if (!fresh && await f.exists() && await f.length() > 0) return path;
    final r = await api.dio.post('/clips/$clipId/preview-url');
    // 'raw' = full-quality original; 'url' = 720p preview (reels). Editor uses raw.
    final url = RuntimeConfig.absolute((r.data['raw'] ?? r.data['url']) as String);
    final tmp = '$path.tmp';
    await Dio().download(url, tmp);
    await File(tmp).rename(path);
    return path;
  }

  /// Gate + record one export (Pro-access + monthly quota). Call on export, not on
  /// editor open. Throws DioException (402 = subscribe / quota) if not allowed.
  Future<void> recordExport(String clipId) async {
    await api.dio.post('/clips/$clipId/download-url');
  }

  Future<List<Clip>> listClips({
    String? q,
    String? category,
    String sort = 'trending',
    String? access,
    bool? featured,
    int limit = 20,
    int offset = 0,
  }) async {
    final r = await api.dio.get('/clips', queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (category != null) 'category': category,
      if (access != null) 'access': access,
      if (featured != null) 'featured': featured,
      'sort': sort,
      'limit': limit,
      'offset': offset,
    });
    return ((r.data['items']) as List)
        .map((e) => Clip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Clip> getClip(String slug) async {
    final r = await api.dio.get('/clips/$slug');
    return Clip.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final r = await api.dio.get('/categories');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> favorite(String clipId) => api.dio.post('/clips/$clipId/favorite');
  Future<void> unfavorite(String clipId) => api.dio.delete('/clips/$clipId/favorite');

  Future<List<Clip>> favorites() async {
    final r = await api.dio.get('/me/favorites');
    return (r.data as List).map((e) => Clip.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Set of clip ids the current user has favorited (to seed heart state).
  Future<Set<String>> favoriteIds() async {
    try {
      final favs = await favorites();
      return favs.map((c) => c.id).toSet();
    } catch (_) {
      return {};
    }
  }
}
