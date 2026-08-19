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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: AppColors.gradient), borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: const Text('C', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Discover', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 28, height: 1.0, letterSpacing: -0.7, color: AppColors.ink)),
              const Text('Viral clips, ready for your brand', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.mut, fontSize: 13)),
            ]),
          ),
          IconButton(onPressed: () => homeTab.value = 1, icon: const Icon(Icons.search_rounded, color: AppColors.ink)),
        ],
      ),
    );
  }

  // ---- subscription status banner ----
  Widget _subBanner() {
    final sub = _sub;
    final status = (sub?['status'] as String?)?.toLowerCase();
    final active = status == 'active';
    final expiresRaw = sub?['expires_at'] ?? sub?['current_period_end'] ?? sub?['end_at'];
    DateTime? expires;
    if (expiresRaw is String) expires = DateTime.tryParse(expiresRaw);
    // renewing-soon = active but ending within 5 days
    final soon = active && expires != null && expires.difference(DateTime.now()).inDays <= 5;

    if (active && !soon) {
      final planName = (sub?['plan_name'] ?? sub?['plan'] ?? 'Pro').toString();
      return _banner(
        icon: Icons.verified_rounded,
        gradient: const [Color(0xFF12B76A), Color(0xFF0E9F6E)],
        title: '$planName subscription active',
        subtitle: expires != null ? 'Renews ${_fmtDate(expires)} · unlimited exports' : 'Unlimited exports · no watermark',
        cta: 'Manage',
        onTap: () => context.push('/plans'),
      );
    }
    if (soon) {
      return _banner(
        icon: Icons.autorenew_rounded,
        gradient: const [Color(0xFF7E57DE), Color(0xFFFFC400)],
        title: 'Your subscription ends soon',
        subtitle: expires != null ? 'Renew before ${_fmtDate(expires)} to keep exporting' : 'Renew to keep unlimited exports',
        cta: 'Renew',
        onTap: () => context.push('/plans'),
      );
    }
    // no subscription
    return _banner(
      icon: Icons.workspace_premium_rounded,
      gradient: const [Color(0xFF7B2FF7), Color(0xFF6D45C9)],
      title: 'Unlock every clip',
      subtitle: 'Subscribe for unlimited exports · no watermark',
      cta: 'Subscribe',
      onTap: () => context.push('/plans'),
    );
  }

  Widget _banner({required IconData icon, required List<Color> gradient, required String title, required String subtitle, required String cta, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient, begin: Alignment.centerLeft, end: Alignment.centerRight),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.1)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
              child: Text(cta, style: TextStyle(color: gradient.last, fontWeight: FontWeight.w700, fontSize: 12)),
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

  // ---- featured hero row (big cards) ----
  Widget _featuredRow() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _rowHeader('Featured', 'Hand-picked this week'),
      SizedBox(
        height: 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _featured.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(
            width: 156,
            child: ClipTile(clip: _featured[i], aspect: 156 / 220, showText: true, onTap: () => _openRow(_featured, i)),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ]);
  }

  // ---- one category row ----
  Widget _categoryRow(_CatRow row) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _rowHeader(row.name, null, onSeeAll: () { exploreCategory.value = row.slug; homeTab.value = 1; }),
      SizedBox(
        height: 176,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: row.clips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) => SizedBox(
            width: 118,
            child: ClipTile(clip: row.clips[i], aspect: 118 / 176, onTap: () => _openRow(row.clips, i)),
          ),
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _rowHeader(String title, String? sub, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.3, color: AppColors.ink)),
            if (sub != null) Text(sub, style: const TextStyle(color: AppColors.mut, fontSize: 12.5)),
          ]),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See all', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 13))),
      ]),
    );
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
