import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/runtime_config.dart';
import '../core/token_store.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authed, guest }

class AuthController extends ChangeNotifier {
  AuthController(this.auth, this.tokens);
  final AuthService auth;
  final TokenStore tokens;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;

  Future<void> bootstrap() async {
    final token = await tokens.access;
    if (token == null) {
      status = AuthStatus.guest;
    } else {
      try {
        user = await auth.me();
        status = AuthStatus.authed;
      } catch (_) {
        status = AuthStatus.guest;
      }
    }
    notifyListeners();
  }

  /// Update self-profile fields; refreshes [user] on success. Returns an error string or null.
  Future<String?> updateProfile({String? name, int? age, String? gender, String? nationality}) async {
    try {
      user = await auth.updateProfile(name: name, age: age, gender: gender, nationality: nationality);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _message(e);
    } catch (_) {
      return 'Could not save your profile';
    }
  }

  Future<String?> login(String email, String password) =>
      _run(() => auth.login(email, password));

  Future<String?> register(String name, String email, String password) =>
      _run(() => auth.register(name, email, password));

  Future<String?> googleSignIn() async {
    try {
      final serverClientId = RuntimeConfig.get<String>('google_server_client_id', '');
      if (serverClientId.isEmpty) return 'Google login not configured yet';
      final gsi = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: serverClientId,
      );
      // Clear the cached account so the account-chooser always appears
      // (devices with multiple Google accounts were silently reusing the last one).
      try { await gsi.signOut(); } catch (_) {}
      final account = await gsi.signIn();
      if (account == null) return 'Cancelled';
      final tokenData = await account.authentication;
      final idToken = tokenData.idToken;
      if (idToken == null) return 'No Google token';
      return _run(() => auth.google(idToken));
    } catch (e) {
      return 'Google sign-in failed';
    }
  }

  Future<String?> _run(Future<AppUser> Function() fn) async {
    try {
      user = await fn();
      status = AuthStatus.authed;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _message(e);
    } catch (_) {
      return 'Something went wrong';
    }
  }

  String _message(DioException e) {
    final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
    if (detail is String) return detail;
    if (detail is Map && detail['message'] != null) return detail['message'].toString();
    return 'Request failed (${e.response?.statusCode ?? 'network'})';
  }

  Future<void> logout() async {
    await auth.logout();
    user = null;
    status = AuthStatus.guest;
    notifyListeners();
  }
}
