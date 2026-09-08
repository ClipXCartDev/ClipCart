import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
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

  void _copyWebsite() {
    Clipboard.setData(const ClipboardData(text: 'https://clipcart.app/help'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
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
                // ── dark CTA card → live chat ──────────────────────────────
                _QueryCta(onTap: _openQuery),

                // ── FAQ (expandable, real answers) ─────────────────────────
                const FieldLabel('FAQ'),
                ListCard(children: const [
                  _FaqItem(
                    q: 'Why does my export have no sound?',
                    a: 'Some source clips arrive without an audio track, so the export is silent. Check the clip plays with sound in the player before editing.',
                  ),
                  _FaqItem(
                    q: 'How do edit credits work?',
                    a: 'One credit is used the moment you open a clip in the editor. You can keep editing that clip as long as you like — a different clip uses another credit.',
                  ),
                  _FaqItem(
                    q: 'Can I use clips commercially?',
                    a: 'Clips are licensed for personal and social use. For commercial or paid promotions, message support first.',
                  ),
                  _FaqItem(
                    q: 'How do I change my plan?',
                    a: 'Go to Account → Plans & subscription. A new plan starts the day you pay and runs 30 calendar days.',
                  ),
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
                    label: 'Help centre',
                    value: 'clipcart.app/help',
                    chevron: false,
                    onTap: _copyWebsite,
                    trailing: _RowAction(label: 'Copy', onTap: _copyWebsite),
                  ),
                ]),

                // Change password lives in Account → Settings now (client §7).
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
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B54C9), Color(0xFF4A38A6)],
          ),
          borderRadius: BorderRadius.circular(R.large),
          boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.26), blurRadius: 16, offset: const Offset(0, 7))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
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
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(R.inner)),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Chat with support',
                        style: TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('A real person replies here · within 6 working hours',
                        style: TextStyle(fontFamily: kSans, fontSize: 11.5, color: Colors.white.withValues(alpha: 0.75))),
                  ]),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.75), size: 22),
              ]),
            ),
          ),
        ),
      );
}

// ── FAQ item (tap to expand the answer) ──────────────────────────────────────

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.q, required this.a});
  final String q, a;
  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(widget.q,
                      style: const TextStyle(fontFamily: kSans, fontSize: 14, height: 1.35, fontWeight: FontWeight.w500, color: AppColors.ink)),
                ),
                const SizedBox(width: 12),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.chevron),
                ),
              ]),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 160),
                crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Text(widget.a,
                      style: const TextStyle(fontFamily: kSans, fontSize: 13, height: 1.5, color: AppColors.inkMuted)),
                ),
              ),
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
