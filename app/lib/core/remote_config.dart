import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'runtime_config.dart';

/// Fetches app config from the stable bootstrap URL at startup, so the API base URL
/// and feature flags are backend-driven (no rebuild to switch servers). Falls back to
/// the last cached config, then to the baked default.
class RemoteConfig {
  static const _cacheKey = 'cc_remote_config';
  static const _store = FlutterSecureStorage();

  static Future<void> load() async {
    await _loadBootstrap();
    await _loadFromApi();
  }

  /// The config that lives beside the API.
  ///
  /// The bootstrap URL's job is to say where the server is, and it is hosted
  /// somewhere that outlives any server; this one is deployed WITH the server,
  /// so it is what carries values that change release to release. Merged over
  /// the bootstrap, except for the pointer itself - taking the API's address
  /// from the API would defeat the whole arrangement.
  static Future<void> _loadFromApi() async {
    try {
      final r = await Dio().get(
        '${RuntimeConfig.origin}/app-config.json',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = jsonDecode(r.data as String) as Map<String, dynamic>;
      data.remove('api_base_url');
      RuntimeConfig.values = {...RuntimeConfig.values, ...data};
    } catch (_) {/* the bootstrap values stand */}
  }

  static Future<void> _loadBootstrap() async {
    // 1) network
    try {
      final r = await Dio().get(
        AppConfig.bootstrapConfigUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = jsonDecode(r.data as String) as Map<String, dynamic>;
      _apply(data);
      await _store.write(key: _cacheKey, value: jsonEncode(data));
      return;
    } catch (_) {/* fall through */}

    // 2) cached
    try {
      final cached = await _store.read(key: _cacheKey);
      if (cached != null) {
        _apply(jsonDecode(cached) as Map<String, dynamic>);
        return;
      }
    } catch (_) {/* fall through */}

    // 3) baked fallback (RuntimeConfig already holds it)
  }

  static void _apply(Map<String, dynamic> data) {
    RuntimeConfig.values = data;
    final api = data['api_base_url'];
    if (api is String && api.isNotEmpty) {
      RuntimeConfig.apiBaseUrl = api.replaceAll(RegExp(r'/+$'), '');
    }
  }
}
