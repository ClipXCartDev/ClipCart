/// App configuration. Override at build: --dart-define=API_BASE_URL=https://api.clipcart.app/api/v1
class AppConfig {
  /// Android emulator reaches the host machine via 10.0.2.2.
  /// iOS simulator / desktop can use http://127.0.0.1:8000.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Signed storage URLs may be relative (local dev) or absolute (R2). Make absolute.
  static String absolute(String url) =>
      url.startsWith('http') ? url : '${apiBaseUrl.replaceAll('/api/v1', '')}$url';
}
