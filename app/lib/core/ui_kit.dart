import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

/// CLIPCART_DESIGN_SPEC.md §4 — the reusable component vocabulary.
/// Line icons use Material outlined/rounded glyphs (the closest match to the
/// spec's 1.9-stroke lucide set without adding a dependency).

// ── §4.1 buttons ───────────────────────────────────────────────────────────

/// Primary — full width, h54, r14, brand fill, label 16/600 white.
class PrimaryBtn extends StatelessWidget {
  const PrimaryBtn(this.label, {super.key, this.onTap, this.icon, this.loading = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: H.primaryBtn,
        width: double.infinity,
        child: FilledButton(
          onPressed: loading ? null : onTap,
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(label),
                ]),
        ),
      );
}

/// Ghost — full width, h48, transparent, label 14.5/500 mut.
class GhostBtn extends StatelessWidget {
  const GhostBtn(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: H.ghostBtn,
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.inkMuted,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
            textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w500, fontSize: 14.5),
          ),
          child: Text(label),
        ),
      );
}

/// Secondary — full width, h52, surface + 1px line, label 15/600 ink.
class SecondaryBtn extends StatelessWidget {
  const SecondaryBtn(this.label, {super.key, this.onTap, this.icon, this.height = H.field});
  final String label;
  final VoidCallback? onTap;
  final Widget? icon;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[icon!, const SizedBox(width: 11)],
            Text(label),
          ]),
        ),
      );
}

/// Danger — h40, r11, errBg, label 13/600 err.
class DangerBtn extends StatelessWidget {
  const DangerBtn(this.label, {super.key, this.onTap, this.expand = false});
  final String label;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: AppColors.errBg,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Text(label, style: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.errText)),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Editor pill — h36, r999, brand, label 13.5/600 white.
class EditorPill extends StatelessWidget {
  const EditorPill(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: onTap,
          child: Container(
            height: H.editorPill,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(label, style: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      );
}

/// Circular icon button — 40×40 (36 on media), surfaceHover2 (or glass on media).
class CircleIconBtn extends StatelessWidget {
  const CircleIconBtn(this.icon, {super.key, this.onTap, this.size = H.iconBtn, this.glass = false, this.iconSize = 18, this.iconColor});
  final IconData icon;
  final VoidCallback? onTap;
  final double size, iconSize;
  final bool glass;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: glass ? const Color(0x6B141129) : AppColors.surfaceHover2,
        shape: BoxShape.circle,
        border: glass ? null : Border.all(color: AppColors.line),
      ),
      child: Icon(icon, size: iconSize, color: iconColor ?? (glass ? Colors.white : AppColors.ink)),
    );
    final content = glass
        ? ClipOval(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: btn))
        : btn;
    return onTap == null
        ? content
        : Material(color: Colors.transparent, shape: const CircleBorder(), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: content));
  }
}

// ── §4.3 segmented control ──────────────────────────────────────────────────

class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.items, required this.onChanged});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.bgAlt, borderRadius: BorderRadius.circular(R.inner)),
        child: Row(
          children: items.map((it) {
            final on = it.$1 == value;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(it.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: on ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.28), blurRadius: 4, offset: const Offset(0, 1))] : null,
                  ),
                  child: Text(it.$2, style: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? Colors.white : AppColors.inkMuted)),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

// ── §4.4 chip ───────────────────────────────────────────────────────────────

class PillChip extends StatelessWidget {
  const PillChip(this.label, {super.key, this.selected = false, this.onTap, this.filterStyle = false});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Kept for call-site compatibility; selection is now uniformly brand violet.
  final bool filterStyle;

  @override
  Widget build(BuildContext context) {
    final selBg = AppColors.brand; // uniform brand selection everywhere (was ink for filter chips)
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selBg : AppColors.surfaceHover2,
          borderRadius: BorderRadius.circular(R.pill),
          border: selected ? null : Border.all(color: AppColors.line),
        ),
        child: Text(label, style: TextStyle(fontFamily: kSans, fontSize: 12.5, height: 1.0, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Colors.white : AppColors.inkMuted)),
      ),
    );
  }
}

// ── §4.5 list container + row ────────────────────────────────────────────────

/// Rounded surface list container (radius 18, 1px line, clipped).
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) rows.add(const Divider(height: 1, thickness: 1, color: AppColors.bgAlt));
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.large),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// Standard settings/menu row — icon tile · label · value · chevron.
class ListRowTile extends StatelessWidget {
  const ListRowTile({super.key, this.icon, required this.label, this.value, this.onTap, this.danger = false, this.trailing, this.chevron = true});
  final IconData? icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger, chevron;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = danger ? AppColors.errText : AppColors.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(children: [
            if (icon != null) ...[
              Container(
                width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.bgAlt, borderRadius: BorderRadius.circular(R.tile)),
                child: Icon(icon, size: 16, color: AppColors.inkMuted),
              ),
              const SizedBox(width: 11),
            ],
            Expanded(child: Text(label, style: T.rowLabel.copyWith(color: ink))),
            if (value != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(value!, style: T.bodySmall.copyWith(color: AppColors.inkFaint))),
            if (trailing != null) trailing!,
            if (chevron && onTap != null && trailing == null) const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.chevron),
          ]),
        ),
      ),
    );
  }
}

// ── §4.6 bottom sheet ────────────────────────────────────────────────────────

class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 38, height: 4, margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(R.pill)),
      );
}

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder, {bool grabber = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    barrierColor: AppColors.scrimModal,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Padding(
        // clear the system nav bar (viewPadding.bottom) so buttons never overlap it
        padding: EdgeInsets.fromLTRB(22, 10, 22, 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (grabber) const Center(child: SheetGrabber()),
          Flexible(child: builder(ctx)),
        ]),
      ),
    ),
  );
}

// ── field label + info panel ─────────────────────────────────────────────────

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.topGap = 20});
  final String text;
  final double topGap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: topGap, bottom: 10),
        child: Text(text, style: T.fieldLabel),
      );
}

/// Info panel — brandTint fill, brandInk copy, optional info glyph.
class InfoPanel extends StatelessWidget {
  const InfoPanel(this.text, {super.key, this.icon = Icons.info_outline_rounded});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(R.thumb)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: AppColors.brand), const SizedBox(width: 10)],
          Expanded(child: Text(text, style: const TextStyle(fontFamily: kSans, fontSize: 12.5, height: 1.5, color: AppColors.brandInk))),
        ]),
      );
}

// ── stepper + slider row (editor controls) ──────────────────────────────────

/// A labelled slider with −/+ steppers, mono readout. Used across the editor.
class StepperSliderRow extends StatelessWidget {
  const StepperSliderRow({super.key, required this.label, required this.value, required this.min, required this.max, required this.readout, required this.onChanged, this.dark = false});
  final String label;
  final double value, min, max;
  final String readout;
  final ValueChanged<double> onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Colors.white : AppColors.ink;
    final mut = dark ? Colors.white70 : AppColors.inkMuted;
    final track = dark ? AppColors.dark3 : AppColors.line;
    final chipBg = dark ? AppColors.dark3 : AppColors.bgAlt;
    Widget step(String g, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(width: 32, height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(9)), child: Text(g, style: TextStyle(fontFamily: kSans, fontSize: 16, color: ink))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontFamily: kSans, fontSize: 11.5, fontWeight: FontWeight.w500, color: mut)),
        Text(readout, style: TextStyle(fontFamily: kMono, fontSize: 11, color: ink)),
      ]),
      const SizedBox(height: 9),
      Row(children: [
        step('–', () => onChanged((value - (max - min) / 20).clamp(min, max))),
        const SizedBox(width: 11),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: AppColors.brand,
              inactiveTrackColor: track,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5, elevation: 1.5),
            ),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ),
        const SizedBox(width: 11),
        step('+', () => onChanged((value + (max - min) / 20).clamp(min, max))),
      ]),
    ]);
  }
}
