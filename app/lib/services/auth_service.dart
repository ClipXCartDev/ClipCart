import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../models/user.dart';

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  /// The device identity sent to the backend for the 2-device limit.
  ///
  /// We prefer a HARDWARE-derived id (Android `Settings.Secure.ANDROID_ID`,
  /// iOS `identifierForVendor`) because it survives uninstall / reinstall /
  /// "clear data" — so the same physical phone keeps the same slot instead of
  /// silently burning a new one. A random id in secure storage does NOT survive
  /// an uninstall, which is what wrongly consumed device slots before.
  ///
  /// Note: no app-readable id survives a factory reset (OS privacy limit) — a
  /// reset or a new phone yields a new id by design; the backend reclaims the
  /// stale slot (oldest-inactive / user removal). The random id remains a
  /// last-resort fallback for platforms/devices that expose no stable id.
  Future<Map<String, dynamic>> _device() async {
    final os = _osName();
    final stable = await _stableHardwareId();
    if (stable != null && stable.isNotEmpty && stable.toLowerCase() != 'unknown') {
      return {'device_id': '$os:$stable', 'os': os};
    }
    // Fallback: persisted random id (survives app runs, not uninstall).
    const s = FlutterSecureStorage();
    var id = await s.read(key: 'cc_device');
    if (id == null) {
      id = 'dev-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
      await s.write(key: 'cc_device', value: id);
    }
    return {'device_id': id, 'os': os};
  }

  String _osName() {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Reinstall-stable per-device id, or null if the platform exposes none.
  Future<String?> _stableHardwareId() async {
    try {
      if (Platform.isAndroid) {
        return await const AndroidId().getId();
      }
      if (Platform.isIOS) {
        final ios = await DeviceInfoPlugin().iosInfo;
        return ios.identifierForVendor;
      }
    } catch (_) {/* fall through to the random fallback */}
    return null;
  }

  Future<AppUser> _consume(dynamic data) async {
    await api.tokens.save(
      data['tokens']['access_token'] as String,
      data['tokens']['refresh_token'] as String,
    );
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AppUser> register(String name, String email, String password) async {
    final r = await api.dio.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'device': await _device(),
    });
    return _consume(r.data);
  }

  Future<AppUser> login(String email, String password) async {
    final r = await api.dio.post('/auth/login', data: {
      'email': email,
      'password': password,
      'device': await _device(),
    });
    return _consume(r.data);
  }

  Future<AppUser> google(String idToken) async {
    final r = await api.dio.post('/auth/google', data: {
      'id_token': idToken,
      'device': await _device(),
    });
    return _consume(r.data);
  }

  Future<AppUser> me() async {
    final r = await api.dio.get('/auth/me');
    return AppUser.fromJson(r.data as Map<String, dynamic>);
  }

  /// Update self-profile fields (name/age/gender/nationality). Email is not editable.
  Future<AppUser> updateProfile({String? name, int? age, String? gender, String? nationality}) async {
    final r = await api.dio.patch('/auth/me', data: {
      if (name != null) 'name': name,
      'age': age,
      'gender': gender,
      'nationality': nationality,
    });
    return AppUser.fromJson(r.data as Map<String, dynamic>);
  }

  /// Devices bound to the account (max-2 anti-piracy control).
  Future<List<Map<String, dynamic>>> devices() async {
    final r = await api.dio.get('/auth/devices');
    final list = r.data as List;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Unbind a device by its server id, freeing a slot.
  Future<void> removeDevice(String id) async {
    await api.dio.delete('/auth/devices/$id');
  }

  /// Change the account password. Throws DioException on a wrong current password
  /// (400) or a Google-only account (400).
  Future<void> changePassword(String current, String newPassword) async {
    await api.dio.post('/auth/change-password', data: {
      'current_password': current,
      'new_password': newPassword,
    });
  }

  Future<void> logout() => api.tokens.clear();
}
