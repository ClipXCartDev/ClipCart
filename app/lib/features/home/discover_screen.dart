import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/clip.dart';
import '../../services/billing_service.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/skeleton_grid.dart';
import 'home_shell.dart';

/// Home / Discover — clips grouped into CATEGORY ROWS (RenderForest template-
/// section style) with a subscription status banner pinned at the top. Grid
/// tiles show NO caption (client point 2/13); text appears only in the player.
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
      // featured hero row
      try { _featured = await _cs.listClips(featured: true, limit: 10); } catch (_) {}
      // categories → one row each
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
      // fallback: if no categories produced rows, show one "Trending" row
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _boot,
          child: _loading
              ? Column(children: [_header(), const Expanded(child: SkeletonGrid(count: 12))])
              : _error != null
                  ? _Message('Could not load clips.', onRetry: _boot)
                  : ListView(
                      controller: _scroll,
                      padding: EdgeInsets.only(bottom: 90 + MediaQuery.of(context).viewPadding.bottom),
                      children: [
                        _header(),
                        _subBanner(),
                        if (_featured.isNotEmpty) _featuredRow(),
                        for (final row in _rows) _categoryRow(row),
                        const SizedBox(height: 8),
                      ],
                    ),
        ),
      ),
    );
  }

  // §3.0 Home header — "ClipCart" wordmark + a notification bell with a dot.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(
        children: [
          const Expanded(
            child: Text('ClipCart', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 26, height: 1.0, letterSpacing: -0.65, color: AppColors.ink)),
          ),
          GestureDetector(
            onTap: () => homeTab.value = 1,
            child: SizedBox(
              width: 38, height: 38,
              child: Stack(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.notifications_none_rounded, size: 20, color: AppColors.ink),
                ),
                Positioned(right: 7, top: 8, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.err, shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 1.5)))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // §3.0 plan banner — one slot under the header, three states (no-plan · ending
  // soon · active). Subtle light cards, exact copy from the design.
  Widget _subBanner() {
    final sub = _sub;
    final status = (sub?['status'] as String?)?.toLowerCase();
    final active = status == 'active';
    final expiresRaw = sub?['expires_at'] ?? sub?['current_period_end'] ?? sub?['end_at'];
    DateTime? expires;
    if (expiresRaw is String) expires = DateTime.tryParse(expiresRaw);
    final daysLeft = expires?.difference(DateTime.now()).inDays;
    final soon = active && daysLeft != null && daysLeft <= 5;

    if (soon) {
      // ending soon — amber
      return _banner(
        border: const Color(0xFFE7CBA1), bg: const Color(0xFFFDF7F0),
        icon: '◆', iconColor: AppColors.warn,
        title: 'Creator plan ends in ${daysLeft <= 0 ? 'under a day' : '$daysLeft day${daysLeft == 1 ? '' : 's'}'}',
        subtitle: 'Renew to keep clean 1080p exports',
        cta: 'Renew', onTap: () => context.push('/plans'),
      );
    }
    if (active) {
      // active — green; quota if the server sends it
      final used = sub?['exports_used'] ?? sub?['used'];
      final quota = sub?['export_quota'] ?? sub?['quota'];
      final left = (quota is num && used is num) ? '${(quota - used).toInt()} of ${quota.toInt()} exports left' : 'Exports available';
      final renews = expires != null ? ' · renews ${_fmtDate(expires)}' : '';
      return _banner(
        border: const Color(0xFFCFE6D6), bg: const Color(0xFFF5FBF7),
        dot: AppColors.ok,
        title: 'Creator plan active',
        subtitle: '$left$renews',
        cta: 'Manage', ctaAsText: true, onTap: () => context.push('/plans'),
      );
    }
    // no plan — neutral card
    return _banner(
      border: AppColors.line, bg: AppColors.surface,
      icon: '◆', iconColor: AppColors.mut,
      title: 'Unlock exports from 6.00 USDT',
      subtitle: 'Browse free · export with a plan',
      cta: 'See plans', onTap: () => context.push('/plans'),
    );
  }

  Widget _banner({
    required Color border, required Color bg, required String title, required String subtitle,
    required String cta, required VoidCallback onTap,
    String? icon, Color? iconColor, Color? dot, bool ctaAsText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: Row(children: [
            if (dot != null)
              Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))
            else if (icon != null)
              Text(icon, style: TextStyle(fontSize: 14, color: iconColor)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13, height: 1.35)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mut, fontSize: 13, height: 1.35)),
              ]),
            ),
            const SizedBox(width: 10),
            if (ctaAsText)
              Text(cta, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 13))
            else
              Container(
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(9)),
                child: Text(cta, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
          ]),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  // ---- featured shelf (first shelf, "Newly released" feel) ----
  Widget _featuredRow() => _shelf('Newly released', _featured, null);

  // ---- one category shelf ----
  Widget _categoryRow(_CatRow row) =>
      _shelf(row.name, row.clips, () { exploreCategory.value = row.slug; homeTab.value = 1; });

  // §3.0 shelf: 16px/600 header + "See all", horizontal 108×168 tiles with the
  // caption BELOW the thumbnail (feedback 2 — no text overlaid on the media).
  Widget _shelf(String title, List<Clip> clips, VoidCallback? onSeeAll) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 9),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.ink)),
          if (onSeeAll != null)
            GestureDetector(onTap: onSeeAll, child: const Text('See all', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
      ),
      SizedBox(
        height: 198,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: clips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, i) => SizedBox(
            width: 108,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 108, height: 168, child: ClipTile(clip: clips[i], aspect: 108 / 168, onTap: () => _openRow(clips, i))),
              const SizedBox(height: 6),
              Text(clips[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.ink)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
  final String text;
  final Future<void> Function()? onRetry;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))),
        const SizedBox(height: 12),
        if (onRetry != null) Center(child: TextButton(onPressed: onRetry, child: const Text('Retry'))),
      ],
    );
  }
}
