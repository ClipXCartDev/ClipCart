import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/runtime_config.dart';
import '../models/clip.dart';

class CatalogService {
  CatalogService(this.api);
  final ApiClient api;

  // ── lightweight in-memory cache ────────────────────────────────────────────
  // Categories rarely change; clip queries are cached briefly so switching tabs
  // (Home ↔ Explore) or coming back is instant instead of re-hitting the network
  // and flashing an empty state (client: "refresh pe bahut delay + no clip found").
  List<Map<String, dynamic>>? _catCache;
  DateTime? _catAt;
  final Map<String, (DateTime, List<Clip>)> _clipCache = {};
  static const _catTtl = Duration(minutes: 5);
  static const _clipTtl = Duration(seconds: 45);

  /// Drop all cached catalog data (called on pull-to-refresh for fresh results).
  void clearCache() {
    _catCache = null;
    _catAt = null;
    _clipCache.clear();
  }

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
  /// preview) — editing + export must be high quality.
  ///
  /// One edit == one purchase: the server charges ONE credit the first time this
  /// clip is opened in the period and never again for the same clip, so the
  /// gate is always consulted first (a cached file must not bypass it). Throws
  /// DioException 402 (subscribe / no credits left) when not allowed. Atomic
  /// (tmp → rename) so a failed download never leaves a corrupt cache.
  /// `fresh: true` forces a re-download.
  Future<String> editClipFile(
    String clipId, {
    bool fresh = false,
    void Function(int received, int total)? onProgress,
  }) async {
    final r = await api.dio.post('/clips/$clipId/download-url');
    final url = RuntimeConfig.absolute(r.data['url'] as String);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/base_$clipId.mp4';
    final f = File(path);
    if (fresh && await f.exists()) await f.delete();
    if (!fresh && await f.exists() && await f.length() > 0) return path;
    final tmp = '$path.tmp';
    await Dio().download(url, tmp, onReceiveProgress: onProgress);
    await File(tmp).rename(path);
    return path;
  }

  /// Where the signed-in customer stands with this clip:
  /// `charged` (credit already spent → reopening is free), `exported` (final),
  /// `credits_left` (null = unlimited), `subscribed`.
  Future<Map<String, dynamic>> editState(String clipId) async {
    final r = await api.dio.get('/clips/$clipId/edit-state');
    return Map<String, dynamic>.from(r.data as Map);
  }

  /// Mark the paid edit as exported — the clip is final for this customer.
  /// Idempotent. Throws DioException 409 if the clip was never opened.
  Future<Map<String, dynamic>> finalizeExport(String clipId) async {
    final r = await api.dio.post('/clips/$clipId/finalize');
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<List<Clip>> listClips({
    String? q,
    String? category,
    String sort = 'trending',
    String? access,
    bool? featured,
    int limit = 20,
    int offset = 0,
    bool force = false,
  }) async {
    final key = 'q=$q|c=$category|a=$access|f=$featured|s=$sort|l=$limit|o=$offset';
    if (!force) {
      final hit = _clipCache[key];
      if (hit != null && DateTime.now().difference(hit.$1) < _clipTtl) return hit.$2;
    }
    final r = await api.dio.get('/clips', queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (category != null) 'category': category,
      if (access != null) 'access': access,
      if (featured != null) 'featured': featured,
      'sort': sort,
      'limit': limit,
      'offset': offset,
    });
    final items = ((r.data['items']) as List)
        .map((e) => Clip.fromJson(e as Map<String, dynamic>))
        .toList();
    _clipCache[key] = (DateTime.now(), items);
    return items;
  }

  Future<Clip> getClip(String slug) async {
    final r = await api.dio.get('/clips/$slug');
    return Clip.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> categories({bool force = false}) async {
    if (!force && _catCache != null && _catAt != null && DateTime.now().difference(_catAt!) < _catTtl) {
      return _catCache!;
    }
    final r = await api.dio.get('/categories');
    final cats = (r.data as List).cast<Map<String, dynamic>>();
    _catCache = cats;
    _catAt = DateTime.now();
    return cats;
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
