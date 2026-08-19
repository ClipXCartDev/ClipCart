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
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.g_mobiledata, size: 26, color: Colors.redAccent),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F1F1F),
        side: const BorderSide(color: Color(0xFFEAE8EE)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
