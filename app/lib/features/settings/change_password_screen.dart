import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

/// Change the account password (client: "password change karne ka option bhi
/// nahi hai"). Verifies the current password server-side.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_next.text.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthController>().auth.changePassword(_current.text, _next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed ✓')));
      context.pop();
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? (e.response!.data['detail']?.toString()) : null;
      setState(() => _error = detail ?? 'Could not change password. Try again.');
    } catch (_) {
      setState(() => _error = 'Could not change password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field('Current password', _current),
          const SizedBox(height: 14),
          _field('New password', _next),
          const SizedBox(height: 14),
          _field('Confirm new password', _confirm),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF04438).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFF04438), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFF04438), fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(label: 'Update password', icon: Icons.lock_reset_rounded, loading: _busy, onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 6),
      TextField(
        controller: ctl,
        obscureText: _obscure,
        decoration: InputDecoration(
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    ]);
  }
}
