import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Consistent premium "nothing here yet" state — gradient icon ring, title,
/// subtitle, optional CTA.
class PremiumEmptyState extends StatelessWidget {
  const PremiumEmptyState({super.key, required this.icon, required this.title, required this.subtitle, this.cta, this.onCta});
  final IconData icon;
  final String title;
  final String subtitle;
  final String? cta;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: const BoxDecoration(color: AppColors.brandSurface, shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: AppColors.brand),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mut, fontSize: 14, height: 1.5)),
            if (cta != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onCta,
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text(cta!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
