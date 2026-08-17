import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shimmer/shimmer.dart';

import 'clip_card.dart' show masonryAspect;

/// A shimmering masonry skeleton that matches the gallery tile shape — shown
/// while clips load so the layout feels present instantly (premium vs a spinner).
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 12, this.padding});
  final int count;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF201B26) : const Color(0xFFECE9F0);
    final hi = dark ? const Color(0xFF2C2632) : const Color(0xFFF7F5F9);
    // stable pseudo-random aspect per index so the skeleton staggers like real tiles
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: hi,
      period: const Duration(milliseconds: 1100),
      child: MasonryGridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.all(8),
        crossAxisCount: 3,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
        itemCount: count,
        itemBuilder: (context, i) => AspectRatio(
          aspectRatio: masonryAspect('sk$i'),
          child: DecoratedBox(
            decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
