import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/clip.dart';

const _cardGradients = [
  [Color(0xFFFF7A59), Color(0xFFFF4D8D)],
  [Color(0xFF12C7A0), Color(0xFF3B9EFF)],
  [Color(0xFFFF9247), Color(0xFFFF2D6B)],
  [Color(0xFFF5A623), Color(0xFFFF4D6D)],
  [Color(0xFF7B61FF), Color(0xFF4C9AFF)],
  [Color(0xFF1A2740), Color(0xFFC0304A)],
];

/// RenderForest-style gallery card.
class ClipCard extends StatelessWidget {
  const ClipCard({super.key, required this.clip, this.onTap});

  final Clip clip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = _cardGradients[clip.id.hashCode.abs() % _cardGradients.length];
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                children: [
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _Badge(clip.isPro ? 'PRO' : 'FREE', clip.isPro ? AppColors.gold : AppColors.ok, clip.isPro ? const Color(0xFF3A2600) : Colors.white),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                      child: Text(clip.durationLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const Positioned(top: 8, right: 8, child: CircleAvatar(radius: 13, backgroundColor: Colors.white24, child: Icon(Icons.play_arrow, color: Colors.white, size: 16))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clip.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${clip.category ?? clip.genre ?? clip.language} · ${clip.downloads}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w900)),
      );
}
