import 'package:flutter/material.dart';

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
              width: 92, height: 92,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0x22FF7A59), Color(0x22FF4D6D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: const Color(0xFFFF4D6D)),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13.5, height: 1.45)),
            if (cta != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onCta,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4D6D), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(cta!, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
