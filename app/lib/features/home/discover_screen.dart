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

  bool get _hasPlan => (_sub?['status']?.toString())?.toLowerCase() == 'active';

  Future<void> _refreshSub() async {
    try {
      final s = await context.read<BillingService>().subscription();
      if (mounted) setState(() => _sub = s);
    } catch (_) {}
  }

  Future<void> _boot({bool force = false}) async {
    setState(() { _loading = true; _error = null; });
    if (force) _cs.clearCache(); // pull-to-refresh → fresh, else cache = instant
    try {
      // subscription (banner) — non-fatal
      _refreshSub();
      // Featured + categories run CONCURRENTLY (was serial → slow refresh).
      // Gather via Future.wait so both futures get a listener synchronously — a
      // categories() error can't land unlistened (no spurious unhandled-async).
      final fFeat = _cs.listClips(featured: true, limit: 10, force: force).catchError((_) => <Clip>[]);
      final fCats = _cs.categories(force: force);
      final gathered = await Future.wait<Object?>([fFeat, fCats]);
      _featured = gathered[0] as List<Clip>;
      final cats = gathered[1] as List<Map<String, dynamic>>;
      // One rail per category, all fetched IN PARALLEL (was a serial await loop
      // per category — the main cause of the long refresh the client saw).
      final rowFutures = cats.map((c) {
        final slug = (c['slug'] as String?) ?? c['name'] as String?;
        final name = (c['name'] as String?) ?? 'Clips';
        return _cs
            .listClips(category: slug, limit: 12, sort: 'trending', force: force)
            .then<_CatRow?>((clips) => clips.isNotEmpty ? _CatRow(name, slug, clips) : null)
            .catchError((_) => null);
      }).toList();
      var rows = (await Future.wait(rowFutures)).whereType<_CatRow>().toList();
      // fallback: if no categories produced rows, show one "Trending" rail
      if (rows.isEmpty) {
        final all = await _cs.listClips(limit: 18, sort: 'trending', force: force);
        if (all.isNotEmpty) rows = [_CatRow('Trending', null, all)];
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
      onRefresh: () => _boot(force: true),
      color: AppColors.brand,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _header(),
          _searchEntry(),
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

  /// How close to expiry the plan has to be before the pill starts warning.
  /// A week is enough notice to renew without the pill crying wolf all month.
  static const int _endingSoonDays = 7;

  // Compact plan pill for the header, in the three states Revision A asks for:
  // a gold "Subscribe" with no plan, an amber "Renew" while one is running out,
  // and a brand-violet "Pro" the rest of the time. The amber state is the point
  // of having three — without it an expiring plan reads exactly like a healthy
  // one, and the user only finds out when a clip refuses to open.
  Widget _subPill() {
    final active = _hasPlan;
    final expiresRaw = _sub?['expires_at'] ?? _sub?['current_period_end'] ?? _sub?['end_at'];
    DateTime? expires;
    if (expiresRaw is String) expires = DateTime.tryParse(expiresRaw);
    final daysLeft = expires?.difference(DateTime.now()).inDays;

    if (active) {
      final ending = daysLeft != null && daysLeft >= 0 && daysLeft <= _endingSoonDays;
      final String sub = (daysLeft != null && daysLeft >= 0)
          ? (daysLeft == 0 ? 'ends today' : '$daysLeft days left')
          : 'active';
      // Amber while it is running out, violet while it is healthy. The label
      // changes too: colour alone is not a state anyone can act on, and the
      // accessibility rule in the contract says as much.
      final Color c1 = ending ? const Color(0xFFE0A040) : const Color(0xFF7A62D6);
      final Color c2 = ending ? AppColors.goldAccent : AppColors.brand;
      final Color glow = ending ? AppColors.goldAccent : AppColors.brand;
      final Color fg = ending ? const Color(0xFF3B2A05) : Colors.white;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async { await context.push('/plans'); if (mounted) _refreshSub(); },
        child: Container(
          height: 34,
          padding: const EdgeInsets.fromLTRB(9, 0, 13, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
            borderRadius: BorderRadius.circular(R.pill),
            boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.34), blurRadius: 11, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 20, height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fg.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: Icon(ending ? Icons.schedule_rounded : Icons.verified_rounded, size: 13, color: fg),
            ),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ending ? 'Renew' : 'Pro',
                  style: TextStyle(fontFamily: kSans, fontSize: 12.5, height: 1.05, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: fg)),
              Text(sub, style: TextStyle(fontFamily: kMono, fontSize: 8.5, height: 1.05, fontWeight: FontWeight.w500, color: fg.withValues(alpha: 0.82))),
            ]),
          ]),
        ),
      );
    }

    // no plan → gold Subscribe CTA
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async { await context.push('/plans'); if (mounted) _refreshSub(); },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: AppColors.goldAccent,
          borderRadius: BorderRadius.circular(R.pill),
          boxShadow: [BoxShadow(color: AppColors.goldAccent.withValues(alpha: 0.38), blurRadius: 11, offset: const Offset(0, 3))],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt_rounded, size: 15, color: Color(0xFF3B2A05)),
          SizedBox(width: 5),
          Text('Subscribe', style: TextStyle(fontFamily: kSans, fontSize: 13, height: 1.0, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: Color(0xFF3B2A05))),
        ]),
      ),
    );
  }

  /// A search field on Home, as the client's mockup has it.
  ///
  /// It is a button dressed as a field rather than a second search
  /// implementation: tapping it opens Explore, which already owns the query,
  /// the filters and the results. Two search boxes that behave differently is
  /// worse than one that is reachable from both places.
  Widget _searchEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          exploreCategory.value = null;
          homeTab.value = 1;
        },
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgAlt,
            borderRadius: BorderRadius.circular(R.button),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 19, color: AppColors.inkFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Search clips, movies, moods',
                  style: TextStyle(fontFamily: kSans, fontSize: 14, color: AppColors.inkFaint)),
            ),
            const Icon(Icons.tune_rounded, size: 18, color: AppColors.inkFaint),
          ]),
        ),
      ),
    );
  }

  /// A face for each shelf, so the rails are scannable before the words are
  /// read. Matched on the category name because categories are admin-managed
  /// and have no emoji of their own; anything unrecognised gets the neutral
  /// one rather than nothing, so a newly added category never looks broken.
  static const Map<String, String> _railEmoji = {
    'newly released': '✨',
    'trending': '🔥',
    'anime': '🌸',
    'comedy': '😂',
    'movie edits': '🎬',
    'reactions': '😮',
    'wholesome': '💛',
  };

  String _emojiFor(String title) => _railEmoji[title.trim().toLowerCase()] ?? '🎞️';

  // ── one rail — heading row + horizontal 9:16 cards with caption below ──────
  Widget _rail(String title, List<Clip> clips, VoidCallback? onSeeAll) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          Text(_emojiFor(title), style: const TextStyle(fontSize: 17, height: 1.1)),
          const SizedBox(width: 8),
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
                    style: const TextStyle(fontFamily: kSans, fontSize: 12, height: 1.3, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
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
          // uses — bottom-right, mirroring the duration pill opposite it
          if (clip.usesLabel != null)
            Positioned(
              right: 7, bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xB8141129), borderRadius: BorderRadius.circular(R.pill)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome_rounded, size: 9, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(clip.usesLabel!,
                      style: const TextStyle(fontFamily: kMono, fontSize: 10, height: 1.0, fontWeight: FontWeight.w500, color: Colors.white)),
                ]),
              ),
            ),
          // play badge, with the lock beside it on gated clips — same treatment
          // as the Explore grid so a clip looks the same wherever it appears
          Positioned(
            top: 7, right: 7,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const _CornerBadge(icon: Icons.play_arrow_rounded),
              if (locked) ...[
                const SizedBox(width: 4),
                const _CornerBadge(icon: Icons.lock_outline_rounded),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A small translucent chip in a card's corner — play, or the lock on a gated
/// clip. Matches the Explore grid's badge so the same clip reads the same in
/// both places.
class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 24, height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0x8C141129), borderRadius: BorderRadius.circular(R.pill)),
        child: Icon(icon, size: 13, color: Colors.white),
      );
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
