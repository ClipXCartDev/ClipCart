import 'dart:io';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/runtime_config.dart';
import '../models/clip.dart';

class CreatorService {
  CreatorService(this.api);
  final ApiClient api;

  /// Uploads a base clip to storage (R2/local) via a presigned PUT; returns its key.
  Future<String> uploadBaseClip(String filePath, String filename) async {
    final r = await api.dio.post('/creator/upload-url', data: {'filename': filename, 'content_type': 'video/mp4'});
    final url = RuntimeConfig.absolute(r.data['url'] as String);
    final key = r.data['key'] as String;
    final bytes = await File(filePath).readAsBytes();
    await Dio().put(url, data: Stream.fromIterable([bytes]),
        options: Options(contentType: 'video/mp4', headers: {Headers.contentLengthHeader: bytes.length}));
    return key;
  }

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
