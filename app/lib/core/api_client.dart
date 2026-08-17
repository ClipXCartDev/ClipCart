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
        // Only the pre-auth endpoints go WITHOUT a token; authenticated /auth/*
        // routes (me, devices, logout) still need it. (Bug: excluding all /auth/
        // stripped the token from /auth/devices → 403, and from /auth/me.)
        if (token != null && !_noAuthHeader(options.path)) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        // Don't try to refresh for the login/refresh calls themselves.
        final isPreAuth = _noAuthHeader(e.requestOptions.path);
        if (e.response?.statusCode == 401 && !isPreAuth) {
          // Concurrent 401s all await the SAME refresh future (no lost refreshes,
          // no spurious logout when two requests 401 at once).
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
  Future<bool>? _refreshFuture; // shared in-flight refresh

  // Endpoints that must be called WITHOUT an access token (they issue/rotate one).
  static bool _noAuthHeader(String path) =>
      path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/google');

  Future<bool> _refresh() {
    // If a refresh is already running, everyone waits on it.
    return _refreshFuture ??= _doRefresh().whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final rt = await tokens.refresh;
      if (rt == null) return false;
      final resp = await dio.post('/auth/refresh', data: {'refresh_token': rt});
      await tokens.save(resp.data['access_token'] as String, resp.data['refresh_token'] as String);
      return true;
    } catch (_) {
      await tokens.clear();
      return false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions ro) async {
    // Drop the stale Authorization header so the request interceptor re-adds the
    // freshly-refreshed token (was retrying with the old, still-401 token).
    final headers = Map<String, dynamic>.from(ro.headers)..remove('Authorization');
    return dio.request(
      ro.path,
      data: ro.data,
      queryParameters: ro.queryParameters,
      options: Options(method: ro.method, headers: headers),
    );
  }
}
