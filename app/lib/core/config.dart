/// Build-time constants. Everything server-specific (API base, flags) is loaded at
/// RUNTIME from [bootstrapConfigUrl] via RemoteConfig — so changing the server means
/// editing that JSON, not rebuilding the app.
class AppConfig {
  /// The ONE fixed URL (stable GitHub Pages). Override at build with --dart-define=CONFIG_URL=...
  static const String bootstrapConfigUrl = String.fromEnvironment(
    'CONFIG_URL',
    defaultValue: 'https://clipxcartdev.github.io/ClipCart/app-config.json',
  );

  /// Used only until remote config loads (or if network + cache are both unavailable).
  static const String fallbackApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://clipscart.app/api/v1',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
}
