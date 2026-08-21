import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';

/// §27 States — a UI showcase of the app's edge states (offline, empty search,
/// empty editor, out of credits, crash recovery). Buttons here are illustrative.
class StatesScreen extends StatelessWidget {
  const StatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 20, 10),
            child: Row(children: [
              CircleIconBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              const Text('States', style: T.pageTitle),
            ]),
          ),
          // offline banner
          Container(
            width: double.infinity,
            color: AppColors.warnBg,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: AppColors.warnIcon, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              const Text(
                "You're offline — showing cached clips",
                style: TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.warnText),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                const FieldLabel('Empty search', topGap: 8),
                _StateCard(
                  iconTileColor: AppColors.bgAlt,
                  iconColor: AppColors.inkMuted,
                  icon: Icons.search_rounded,
                  title: 'No clips for "hera 4k"',
                  body: 'Try a shorter search or clear your categories.',
                  action: _GhostBrandBtn('Clear filters', onTap: () {}),
                ),

                const FieldLabel('Nothing in the editor'),
                _StateCard(
                  iconTileColor: AppColors.bgAlt,
                  iconColor: AppColors.inkMuted,
                  icon: Icons.layers_outlined,
                  title: 'No unfinished clips',
                  body: 'Clips you start editing will wait for you here until you export them.',
                  action: _FilledBrandBtn('Browse clips', onTap: () {}),
                ),

                const FieldLabel('No edit credits left'),
                _StateCard(
                  iconTileColor: AppColors.errBg,
                  iconColor: AppColors.errText,
                  icon: Icons.error_outline_rounded,
                  smallTile: true,
                  title: '0 of 30 credits left',
                  body: 'Your plan ends on 19 Sep. Renew or upgrade to keep editing.',
                  action: _FullBrandBtn('Renew plan', onTap: () {}),
                ),

                const FieldLabel('Restored after a crash'),
                _StateCard(
                  iconTileColor: AppColors.brandTint,
                  iconColor: AppColors.brand,
                  icon: Icons.save_outlined,
                  smallTile: true,
                  title: 'We recovered your last edit',
                  body: '"Tea stall standoff" was autosaved at 9:41. No credit was charged again.',
                  action: _FullSurfaceBtn('Resume editing', onTap: () {}),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── the shared state card ────────────────────────────────────────────────────

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.iconTileColor,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.action,
    this.smallTile = false,
  });
  final IconData icon;
  final Color iconTileColor, iconColor;
  final String title, body;
  final Widget action;
  final bool smallTile;

  @override
  Widget build(BuildContext context) {
    final tile = smallTile ? 34.0 : 44.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.large),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: tile,
          height: tile,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: iconTileColor, borderRadius: BorderRadius.circular(R.tile)),
          child: Icon(icon, size: smallTile ? 18 : 22, color: iconColor),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: kSans, fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center, style: T.body),
        const SizedBox(height: 16),
        action,
      ]),
    );
  }
}

// ── small buttons for the showcase ───────────────────────────────────────────

/// A compact brandTint ghost button.
class _GhostBrandBtn extends StatelessWidget {
  const _GhostBrandBtn(this.label, {required this.onTap});
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(label,
                style: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
          ),
        ),
      );
}

/// A compact solid brand button.
class _FilledBrandBtn extends StatelessWidget {
  const _FilledBrandBtn(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(label,
                style: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      );
}

/// A full-width solid brand button, h44 r12.
class _FullBrandBtn extends StatelessWidget {
  const _FullBrandBtn(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 44,
        child: Material(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(R.inner),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.inner),
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
      );
}

/// A full-width surface + 1px line button, h44 r12.
class _FullSurfaceBtn extends StatelessWidget {
  const _FullSurfaceBtn(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 44,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.inner),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.inner),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.inner),
                border: Border.all(color: AppColors.line),
              ),
              child: Center(
                child: Text(label,
                    style: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
            ),
          ),
        ),
      );
}
