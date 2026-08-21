import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/clip.dart';
import '../../services/billing_service.dart';
import '../../services/catalog_service.dart';
import '../../widgets/skeleton_grid.dart';
import 'home_shell.dart';

/// §04 Home — "ClipCart" wordmark header, a subscription banner, then category
/// RAILS of 9:16 thumbnails. Thumbnails carry no text overlay (only a duration
/// pill and a lock badge when gated); the caption sits BELOW each card.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _CatRow {
  _CatRow(this.name, this.slug, this.clips);
  final String name;
  final String? slug;
  final List<Clip> clips;
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _scroll = ScrollController();
  List<_CatRow> _rows = [];
  List<Clip> _featured = [];
  Map<String, dynamic>? _sub; // active subscription or null
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _boot();
    homeTab.addListener(_onTab);
  }

  void _onTab() {
    if (homeTab.value == 0 && mounted && !_loading) _refreshSub();
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTab);
    _scroll.dispose();
    super.dispose();
  }

  CatalogService get _cs => context.read<CatalogService>();

  bool get _hasPlan => (_sub?['status'] as String?)?.toLowerCase() == 'active';

  Future<void> _refreshSub() async {
    try {
      final s = await context.read<BillingService>().subscription();
      if (mounted) setState(() => _sub = s);
    } catch (_) {}
  }

  Future<void> _boot() async {
    setState(() { _loading = true; _error = null; });
    try {
      // subscription (banner) — non-fatal
      _refreshSub();
      // featured hero rail
      try { _featured = await _cs.listClips(featured: true, limit: 10); } catch (_) {}
      // categories → one rail each
      final cats = await _cs.categories();
      final rows = <_CatRow>[];
      for (final c in cats) {
        final slug = (c['slug'] as String?) ?? c['name'] as String?;
        final name = (c['name'] as String?) ?? 'Clips';
        try {
          final clips = await _cs.listClips(category: slug, limit: 12, sort: 'trending');
          if (clips.isNotEmpty) rows.add(_CatRow(name, slug, clips));
        } catch (_) {}
      }
      // fallback: if no categories produced rows, show one "Trending" rail
      if (rows.isEmpty) {
        final all = await _cs.listClips(limit: 18, sort: 'trending');
        if (all.isNotEmpty) rows.add(_CatRow('Trending', null, all));
      }
      if (!mounted) return;
      setState(() { _rows = rows; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    final dir = _scroll.position.userScrollDirection;
    if (_scroll.position.pixels < 120) {
      navMinimized.value = false;
    } else if (dir == ScrollDirection.reverse) {
      navMinimized.value = true;
    } else if (dir == ScrollDirection.forward) {
      navMinimized.value = false;
    }
  }

  void _openRow(List<Clip> list, int i) => context.push('/player', extra: {'clips': list, 'index': i});

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(children: [_header(), const Expanded(child: SkeletonGrid(count: 12))]);
    }
    if (_error != null) {
      return _ErrorState(onRetry: _boot);
    }
    return RefreshIndicator(
      onRefresh: _boot,
      color: AppColors.brand,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _header(),
          const SizedBox(height: 4),
          if (_featured.isNotEmpty) _rail('Newly released', _featured, null),
          for (final row in _rows)
            _rail(row.name, row.clips, () { exploreCategory.value = row.slug; homeTab.value = 1; }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── header (h56) — wordmark · subscribe pill · compact bell ────────────────
  // Profile is reached only from the bottom Account tab (removed the duplicate
  // top-right avatar). The subscription CTA lives inline in the header now
  // (replaces the old full-width banner) — a gold "Subscribe" pill, or a green
  // "Pro" state when active.
  Widget _header() {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
        child: Row(children: [
          const Text('ClipCart',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: kSans, fontSize: 21, height: 1.0, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: AppColors.ink)),
          const Spacer(),
          _subPill(),
          const SizedBox(width: 4),
          // compact notification bell (no heavy circle chrome)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/notifications'),
            child: SizedBox(
              width: 40, height: 40,
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.notifications_none_rounded, size: 23, color: AppColors.ink),
                Positioned(
                  right: 9, top: 9,
                  child: Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 1.5))),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // Compact subscribe / Pro pill for the header — gold (premium contrast on
  // paper) when there's no plan, green when active.
  Widget _subPill() {
    final active = _hasPlan;
    final expiresRaw = _sub?['expires_at'] ?? _sub?['current_period_end'] ?? _sub?['end_at'];
    DateTime? expires;
    if (expiresRaw is String) expires = DateTime.tryParse(expiresRaw);
    final daysLeft = expires?.difference(DateTime.now()).inDays;

    final Color bg = active ? AppColors.okBg : AppColors.goldAccent;
    final Color fg = active ? AppColors.okText : const Color(0xFF3B2A05);
    final IconData icon = active ? Icons.verified_rounded : Icons.bolt_rounded;
    final String label = active
        ? (daysLeft != null && daysLeft > 0 ? 'Pro · ${daysLeft}d' : 'Pro')
        : 'Subscribe';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/plans'),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(R.pill),
          boxShadow: active ? null : [BoxShadow(color: AppColors.goldAccent.withValues(alpha: 0.38), blurRadius: 11, offset: const Offset(0, 3))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontFamily: kSans, fontSize: 13, height: 1.0, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: fg)),
        ]),
      ),
    );
  }

  // ── one rail — heading row + horizontal 9:16 cards with caption below ──────
  Widget _rail(String title, List<Clip> clips, VoidCallback? onSeeAll) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.section)),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('See all', style: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
              ),
            ),
        ]),
      ),
      SizedBox(
        height: 232,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: clips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final clip = clips[i];
            return SizedBox(
              width: 112,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () => _openRow(clips, i),
                  child: _RailThumb(clip: clip, locked: clip.isPro && !_hasPlan),
                ),
                const SizedBox(height: 8),
                Text(clip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: kSans, fontSize: 12, height: 1.3, fontWeight: FontWeight.w500, color: Color(0xFF4A463F))),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

/// 9:16 thumbnail (radius 14) with a duration pill (bottom-left) and, when the
/// clip is gated, a lock badge (top-right). No text is drawn on the media.
class _RailThumb extends StatelessWidget {
  const _RailThumb({required this.clip, required this.locked});
  final Clip clip;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.thumb),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: AppColors.mediaPlaceholder),
          if (clip.thumb != null)
            CachedNetworkImage(
              imageUrl: clip.thumb!,
              fit: BoxFit.cover,
              memCacheWidth: 320,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (_, __) => const ColoredBox(color: AppColors.mediaPlaceholder),
              errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.mediaPlaceholder),
            ),
          // duration pill (bottom-left)
          Positioned(
            left: 7, bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xB8141129), borderRadius: BorderRadius.circular(R.pill)),
              child: Text(clip.durationLabel, style: const TextStyle(fontFamily: kMono, fontSize: 10, height: 1.0, fontWeight: FontWeight.w500, color: Colors.white)),
            ),
          ),
          // lock badge (top-right)
          if (locked)
            Positioned(
              top: 7, right: 7,
              child: Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0x8C141129), borderRadius: BorderRadius.circular(R.pill)),
                child: const Icon(Icons.lock_outline_rounded, size: 11, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 140),
        const Center(child: Text('Could not load clips.', textAlign: TextAlign.center, style: T.body)),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, color: AppColors.brand)),
          ),
        ),
      ],
    );
  }
}
