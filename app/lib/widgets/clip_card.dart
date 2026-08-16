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

/// Next-gen gallery card: full-bleed thumbnail with a gradient scrim, overlaid
/// title/meta (Instagram/TikTok style), floating badges, soft depth shadow.
class ClipCard extends StatelessWidget {
  const ClipCard({super.key, required this.clip, this.onTap, this.isFav = false, this.onFav});

  final Clip clip;
  final VoidCallback? onTap;
  final bool isFav;
  final VoidCallback? onFav;

  @override
  Widget build(BuildContext context) {
    final g = _cardGradients[clip.id.hashCode.abs() % _cardGradients.length];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 3 / 4.2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // base gradient (shows while/if thumb missing)
                DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                if (clip.thumb != null)
                  Image.network(
                    clip.thumb!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    loadingBuilder: (ctx, child, prog) => prog == null
                        ? child
                        : DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                  ),
                // bottom scrim for legible overlaid text
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.transparent, Color(0xE6000000)],
                      stops: [0.0, 0.45, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                // PRO/FREE badge
                Positioned(
                  top: 10, left: 10,
                  child: _Badge(clip.isPro ? 'PRO' : 'FREE', clip.isPro ? AppColors.gold : AppColors.ok, clip.isPro ? const Color(0xFF3A2600) : Colors.white),
                ),
                // heart (optional)
                if (onFav != null)
                  Positioned(
                    top: 6, right: 6,
                    child: GestureDetector(
                      onTap: onFav,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? AppColors.accent : Colors.white, size: 22,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
                      ),
                    ),
                  ),
                // center play affordance
                Center(
                  child: Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5)),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
                // duration pill (top-right, next to heart if present)
                Positioned(
                  top: 10, right: onFav != null ? 44 : 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                    child: Text(clip.durationLabel, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ),
                // title + meta overlaid on the scrim
                Positioned(
                  left: 12, right: 12, bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(clip.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.15, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                      const SizedBox(height: 3),
                      Text('${clip.category ?? clip.genre ?? clip.language}${clip.downloads > 0 ? ' · ${clip.downloads} uses' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 11, fontWeight: FontWeight.w600, shadows: const [Shadow(color: Colors.black54, blurRadius: 3)])),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 4)]),
        child: Text(text, style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
      );
}
