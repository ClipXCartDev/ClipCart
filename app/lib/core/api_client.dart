import 'package:dio/dio.dart';

import 'runtime_config.dart';
import 'token_store.dart';

/// Dio wrapper: attaches the access token and transparently refreshes on 401.
class ApiClient {
  ApiClient(this.tokens) {
    dio = Dio(BaseOptions(
      baseUrl: RuntimeConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokens.access;
        if (token != null && !options.path.contains('/auth/')) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final isAuthCall = e.requestOptions.path.contains('/auth/');
        if (e.response?.statusCode == 401 && !isAuthCall && !_refreshing) {
          if (await _refresh()) {
            try {
              final r = await _retry(e.requestOptions);
              return handler.resolve(r);
            } catch (_) {/* fall through */}
          }
        }
        handler.next(e);
      },
    ));
  }

  late final Dio dio;
  final TokenStore tokens;
  bool _refreshing = false;

  Future<bool> _refresh() async {
    _refreshing = true;
    try {
      final rt = await tokens.refresh;
      if (rt == null) return false;
      final resp = await dio.post('/auth/refresh', data: {'refresh_token': rt});
      await tokens.save(resp.data['access_token'], resp.data['refresh_token']);
      return true;
    } catch (_) {
      await tokens.clear();
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions ro) {
    return dio.request(
      ro.path,
      data: ro.data,
      queryParameters: ro.queryParameters,
      options: Options(method: ro.method, headers: ro.headers),
    );
  }
}
