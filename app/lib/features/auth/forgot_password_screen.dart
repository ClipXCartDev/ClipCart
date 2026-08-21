import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';

/// §03 Reset password. There is no email service wired (lean, crypto-only infra),
/// so a self-service email code isn't sent — password resets are verified by
/// support. This screen gives a real, working path (contact support from the
/// registered email) instead of a dead-end OTP form.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  static const _supportEmail = 'support@clipcart.app';

  @override
  Widget build(BuildContext context) {
    void copyEmail() {
      Clipboard.setData(const ClipboardData(text: _supportEmail));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support email copied')));
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 20, 8),
            child: Row(children: [
              CircleIconBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              const Text('Reset password', style: T.pageTitle),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              children: [
                Container(
                  width: 52, height: 52, alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(R.inner)),
                  child: const Icon(Icons.lock_reset_rounded, size: 26, color: AppColors.brand),
                ),
                const SizedBox(height: 20),
                const Text('Reset your password',
                    style: TextStyle(fontFamily: kSans, fontSize: 24, height: 1.15, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: AppColors.ink)),
                const SizedBox(height: 12),
                const Text(
                  'For your security we verify resets manually. Email us from the address on your account and we’ll reset your password — usually within 6 working hours.',
                  style: TextStyle(fontFamily: kSans, fontSize: 14.5, height: 1.55, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 22),
                // support email card
                DesignCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 42, height: 42, alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.surfaceHover2, borderRadius: BorderRadius.circular(R.tile)),
                      child: const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.ink),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('Email support', style: TextStyle(fontFamily: kSans, fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        SizedBox(height: 4),
                        Text(_supportEmail, style: TextStyle(fontFamily: kMono, fontSize: 12.5, color: AppColors.inkMuted)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                const InfoPanel('Send the email from your registered address and mention your account name so we can find you faster.'),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PrimaryBtn('Copy support email', icon: Icons.copy_rounded, onTap: copyEmail),
            ]),
          ),
        ]),
      ),
    );
  }
}
