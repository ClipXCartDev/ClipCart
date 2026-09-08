import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../state/auth_controller.dart';

/// Change-password bottom sheet. Lives in Account → Settings (client §7 moved it
/// out of Help & Support). Preserves the real AuthService.changePassword wiring.
/// Open with `showAppSheet(context, (_) => const ChangePasswordSheet())`.
class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});
  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _pwError, _pwOk;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    setState(() {
      _pwError = null;
      _pwOk = null;
    });
    if (_next.text.length < 8) {
      setState(() => _pwError = 'New password must be at least 8 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthController>().auth.changePassword(_current.text, _next.text);
      if (!mounted) return;
      setState(() {
        _pwOk = 'Password updated.';
        _current.clear();
        _next.clear();
      });
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? (e.response!.data['detail']?.toString()) : null;
      setState(() => _pwError = detail ?? 'Could not update password.');
    } catch (_) {
      setState(() => _pwError = 'Could not update password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Text('Change password', style: T.section),
      const SizedBox(height: 4),
      const Text('At least 8 characters. You stay signed in on this device.', style: T.bodySmall),
      const SizedBox(height: 16),
      TextField(controller: _current, obscureText: true, decoration: const InputDecoration(hintText: 'Current password')),
      const SizedBox(height: 10),
      TextField(controller: _next, obscureText: true, decoration: const InputDecoration(hintText: 'New password')),
      if (_pwError != null) ...[
        const SizedBox(height: 10),
        Text(_pwError!, style: const TextStyle(fontFamily: kSans, color: AppColors.errText, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
      if (_pwOk != null) ...[
        const SizedBox(height: 10),
        Text(_pwOk!, style: const TextStyle(fontFamily: kSans, color: AppColors.okText, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 16),
      PrimaryBtn('Update password', loading: _busy, onTap: _updatePassword),
      const SizedBox(height: 4),
    ]);
  }
}
