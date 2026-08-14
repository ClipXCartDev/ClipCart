import 'config.dart';

/// Mutable, runtime-resolved config. Single source of truth for the API base URL
/// (and any other server-driven values). Set by RemoteConfig on startup.
class RuntimeConfig {
  static String apiBaseUrl = AppConfig.fallbackApiBaseUrl;
  static Map<String, dynamic> values = {};

  /// Origin without the /api/v1 suffix (for building absolute URLs to signed storage links).
  static String get origin => apiBaseUrl.replaceAll('/api/v1', '');

  /// Make a possibly-relative URL (e.g. a signed /api/v1/storage/... link) absolute.
  static String absolute(String url) => url.startsWith('http') ? url : '$origin$url';

  static T get<T>(String key, T fallback) {
    final v = values[key];
    return v is T ? v : fallback;
  }
}
