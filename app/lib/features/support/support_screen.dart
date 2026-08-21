import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../state/auth_controller.dart';
import 'support_chat_screen.dart';

/// §25 Help & support — a query-first support hub: a dark CTA to open a new
/// request, the user's ticket list, FAQ, contact details, and account security.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  void _openQuery() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportChatScreen()));
  }

  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: 'support@clipcart.app'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _NavRow(title: 'Help & support', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                // ── dark CTA card ──────────────────────────────────────────
                _QueryCta(onTap: _openQuery),

                // ── your requests ──────────────────────────────────────────
                const FieldLabel('Your requests'),
                ListCard(children: [
                  _TicketRow(
                    subject: 'Export freezes at 90% on long clips',
                    ref: 'CC-4821 · 20 Aug',
                    pill: const StatusPill('Open', AppColors.brandTint, AppColors.brandInk),
                    onTap: _openQuery,
                  ),
                  _TicketRow(
                    subject: 'Payment went through but plan not active',
                    ref: 'CC-4790 · 14 Aug',
                    pill: StatusPill.ok('Answered'),
                    onTap: _openQuery,
                  ),
                ]),

                // ── FAQ ────────────────────────────────────────────────────
                const FieldLabel('FAQ'),
                ListCard(children: [
                  ListRowTile(label: 'Why does my export have no sound?', onTap: _openQuery),
                  ListRowTile(label: 'How do edit credits work?', onTap: _openQuery),
                  ListRowTile(label: 'Can I use clips commercially?', onTap: _openQuery),
                  ListRowTile(label: 'How do I change my plan?', onTap: _openQuery),
                ]),

                // ── contact ────────────────────────────────────────────────
                const FieldLabel('Contact'),
                ListCard(children: [
                  ListRowTile(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    value: 'support@clipcart.app',
                    chevron: false,
                    onTap: _copyEmail,
                    trailing: _RowAction(label: 'Copy', onTap: _copyEmail),
                  ),
                  ListRowTile(
                    icon: Icons.public_rounded,
                    label: 'Website',
                    value: 'clipcart.app/help',
                    chevron: false,
                    onTap: () => ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Opening clipcart.app/help'))),
                    trailing: _RowAction(
                      label: 'Open',
                      onTap: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Opening clipcart.app/help'))),
                    ),
                  ),
                ]),

                // ── account security ───────────────────────────────────────
                const FieldLabel('Account security'),
                ListCard(children: [
                  ListRowTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change password',
                    value: '4 months ago',
                    onTap: _openChangePassword,
                  ),
                ]),

                const SizedBox(height: 22),
                const Center(
                  child: Text('Support hours: Mon–Sat, 10:00–19:00 IST', style: T.caption),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  void _openChangePassword() {
    showAppSheet(context, (_) => const _ChangePasswordSheet());
  }
}

// ── nav row ──────────────────────────────────────────────────────────────────

class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 20, 10),
        child: Row(children: [
          CircleIconBtn(Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 12),
          Text(title, style: T.pageTitle),
        ]),
      );
}

// ── dark CTA card ────────────────────────────────────────────────────────────

class _QueryCta extends StatelessWidget {
  const _QueryCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(R.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.large),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.inner)),
                child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Send a query to support',
                      style: TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkDark)),
                  SizedBox(height: 4),
                  Text('Typical reply within 6 working hours',
                      style: TextStyle(fontFamily: kSans, fontSize: 11.5, color: AppColors.mutDark)),
                ]),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.mutDark, size: 22),
            ]),
          ),
        ),
      );
}

// ── ticket row ───────────────────────────────────────────────────────────────

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.subject, required this.ref, required this.pill, this.onTap});
  final String subject, ref;
  final Widget pill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(subject,
                      style: const TextStyle(fontFamily: kSans, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500, color: AppColors.ink)),
                  const SizedBox(height: 6),
                  Text(ref, style: T.dataMuted),
                ]),
              ),
              const SizedBox(width: 12),
              pill,
            ]),
          ),
        ),
      );
}

// ── small text action (Copy / Open) ─────────────────────────────────────────

class _RowAction extends StatelessWidget {
  const _RowAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brandTint,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label,
                style: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brandInk)),
          ),
        ),
      );
}

// ── change password sheet (preserves the real changePassword wiring) ─────────

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
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
