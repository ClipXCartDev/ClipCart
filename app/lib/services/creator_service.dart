import 'dart:io';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/runtime_config.dart';
import '../models/clip.dart';

/// A subtitle file the server could not read, with the reason in the words
/// it should be shown in.
class SubtitleImportError implements Exception {
  const SubtitleImportError(this.message);
  final String message;
  @override
  String toString() => message;
}

class CreatorService {
  CreatorService(this.api);
  final ApiClient api;

  /// Uploads a base clip to storage (R2/local) via a presigned PUT; returns its key.
  Future<String> uploadBaseClip(String filePath, String filename) =>
      _upload(filePath, filename, 'video/mp4');

  /// The creator's own mark, which travels with the clip and is drawn on every
  /// customer's copy. PNG or WebP: a mark is a logo, and a JPEG logo has a grey
  /// box around it.
  Future<String> uploadMark(String filePath, String filename) => _upload(
        filePath,
        filename,
        filename.toLowerCase().endsWith('.webp') ? 'image/webp' : 'image/png',
      );

  /// Presign, then PUT the bytes straight to storage. The server only ever
  /// hands back the KEY — a URL signed now would have expired long before a
  /// customer opened the clip, so the key is what gets stored.
  Future<String> _upload(String filePath, String filename, String contentType) async {
    final r = await api.dio.post('/creator/upload-url',
        data: {'filename': filename, 'content_type': contentType});
    final url = RuntimeConfig.absolute(r.data['url'] as String);
    final key = r.data['key'] as String;
    final bytes = await File(filePath).readAsBytes();
    await Dio().put(url,
        data: Stream.fromIterable([bytes]),
        options: Options(
            contentType: contentType,
            headers: {Headers.contentLengthHeader: bytes.length}));
    return key;
  }

  /// Caption layers from a subtitle file the creator already has.
  ///
  /// Parsed on the server, not here: the web creator does the same thing, and
  /// two parsers would mean two answers to the same file. Throws
  /// [SubtitleImportError] with the server's own wording when the file cannot
  /// be read, because that message names what was expected.
  Future<List<Map<String, dynamic>>> parseSubtitles(String text, {double? duration}) async {
    try {
      final r = await api.dio.post('/creator/subtitles/parse',
          data: {'text': text, if (duration != null) 'duration': duration});
      return [
        for (final c in (r.data['captions'] as List? ?? []))
          Map<String, dynamic>.from(c as Map),
      ];
    } on DioException catch (e) {
      final d = e.response?.data;
      final detail = d is Map ? d['detail'] : null;
      throw SubtitleImportError(detail is Map && detail['message'] != null
          ? detail['message'].toString()
          : "That subtitle file couldn't be read.");
    }
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
