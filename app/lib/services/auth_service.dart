import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../models/user.dart';

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> _device() async {
    const s = FlutterSecureStorage();
    var id = await s.read(key: 'cc_device');
    if (id == null) {
      id = 'dev-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
      await s.write(key: 'cc_device', value: id);
    }
    String os;
    try {
      os = Platform.operatingSystem;
    } catch (_) {
      os = 'unknown';
    }
    return {'device_id': id, 'os': os};
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

  Future<void> logout() => api.tokens.clear();
}
