import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import 'support_chat_screen.dart';

/// Help & support (Revision A §3.0, feedback 12) — online status + a greeting,
/// "Start live chat", contact details, and change password, all in one screen.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
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
    setState(() { _pwError = null; _pwOk = null; });
    if (_next.text.length < 8) {
      setState(() => _pwError = 'New password must be at least 8 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthController>().auth.changePassword(_current.text, _next.text);
      if (!mounted) return;
      setState(() { _pwOk = 'Password updated.'; _current.clear(); _next.clear(); });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // --- live chat card ---
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              const Text('Support is online', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const Spacer(),
              const Text('replies in ~2 min', style: TextStyle(fontSize: 12, color: AppColors.mut)),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: const Text('Hi — how can we help? Your account and last payment reference attach automatically.', style: TextStyle(fontSize: 13, color: AppColors.mut, height: 1.5)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportChatScreen())),
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Start live chat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ])),
          const SizedBox(height: 12),
          // --- contacts card ---
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _contactRow('Email', 'clipxcart@gmail.com', divider: true),
              _contactRow('WhatsApp', '+91 98··· ···10', divider: true),
              _contactRow('Hours', '9:00–21:00 IST, daily', divider: false),
            ]),
          ),
          const SizedBox(height: 12),
          // --- change password card ---
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Change password', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 11),
            TextField(controller: _current, obscureText: true, decoration: const InputDecoration(hintText: 'Current password')),
            const SizedBox(height: 10),
            TextField(controller: _next, obscureText: true, decoration: const InputDecoration(hintText: 'New password')),
            const SizedBox(height: 8),
            const Text('At least 8 characters. You stay signed in on this device.', style: TextStyle(fontSize: 12, color: AppColors.mut)),
            if (_pwError != null) ...[const SizedBox(height: 8), Text(_pwError!, style: const TextStyle(color: AppColors.err, fontSize: 12.5, fontWeight: FontWeight.w600))],
            if (_pwOk != null) ...[const SizedBox(height: 8), Text(_pwOk!, style: const TextStyle(color: AppColors.ok, fontSize: 12.5, fontWeight: FontWeight.w600))],
            const SizedBox(height: 11),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _updatePassword,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: const BorderSide(color: AppColors.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                    : const Text('Update password', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ])),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        padding: const EdgeInsets.all(16),
        child: child,
      );

  Widget _contactRow(String label, String value, {required bool divider}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: AppColors.line)) : null),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.mut)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink)),
        ]),
      );
}
