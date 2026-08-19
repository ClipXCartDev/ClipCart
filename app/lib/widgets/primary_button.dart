import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Primary CTA — flat violet, radius 10 (design system). The one violet accent
/// that carries every commit action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: enabled ? AppColors.brand : const Color(0xFFDAD5E2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: loading ? null : onPressed,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, color: enabled ? Colors.white : const Color(0xFF94909C), size: 19), const SizedBox(width: 8)],
                      Text(label, style: TextStyle(color: enabled ? Colors.white : const Color(0xFF94909C), fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, this.onPressed, this.label = 'Continue with Google'});
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Secondary/outlined style per the design: white, 1px --ln, ink text w500,
    // with a small conic-gradient dot standing in for the Google mark.
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 18, height: 18,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [AppColors.err, AppColors.gold, AppColors.ok, AppColors.brand, AppColors.err]),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: AppColors.ink)),
      ]),
    );
  }
}
