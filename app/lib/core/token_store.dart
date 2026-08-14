import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure JWT storage (decisions §6.4 — secure token storage).
class TokenStore {
  static const _kAccess = 'cc_access';
  static const _kRefresh = 'cc_refresh';
  final FlutterSecureStorage _s = const FlutterSecureStorage();

  Future<void> save(String access, String refresh) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
  }

  Future<String?> get access => _s.read(key: _kAccess);
  Future<String?> get refresh => _s.read(key: _kRefresh);

  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
  }
}
