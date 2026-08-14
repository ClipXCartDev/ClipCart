import '../core/api_client.dart';
import '../models/clip.dart';

class CreatorService {
  CreatorService(this.api);
  final ApiClient api;

  Future<List<Clip>> myUploads() async {
    final r = await api.dio.get('/creator/clips');
    return (r.data as List).map((e) => Clip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Clip> createClip(Map<String, dynamic> body) async {
    final r = await api.dio.post('/creator/clips', data: body);
    return Clip.fromJson(r.data as Map<String, dynamic>);
  }

  /// {downloads, rate, earned, pending, paid, available}
  Future<Map<String, dynamic>> earnings() async {
    final r = await api.dio.get('/creator/earnings');
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<List<Map<String, dynamic>>> payouts() async {
    final r = await api.dio.get('/creator/payouts');
    return (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> requestPayout(double amount) async {
    await api.dio.post('/creator/payouts', data: {'amount': amount});
  }
}
