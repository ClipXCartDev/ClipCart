import '../core/api_client.dart';
import '../models/clip.dart';

class CatalogService {
  CatalogService(this.api);
  final ApiClient api;

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
}
