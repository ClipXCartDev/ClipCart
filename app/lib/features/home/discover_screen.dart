import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import 'home_shell.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _page = 30;
  final _scroll = ScrollController();
  final List<Clip> _grid = [];
  List<Clip> _featured = [];
  List<Map<String, dynamic>> _cats = [];
  String? _cat;
  String _sort = 'trending';
  String? _access; // null | free | pro
  bool _loading = true, _loadingMore = false, _more = true;
  String? _error;

  bool get _filtered => _cat != null || _sort != 'trending' || _access != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _boot();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  CatalogService get _cs => context.read<CatalogService>();

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final featured = await _cs.listClips(featured: true, limit: 10, sort: 'trending');
      List<Map<String, dynamic>> cats = [];
      try {
        cats = await _cs.categories();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _featured = featured.where((c) => c.thumb != null).toList();
        _cats = cats;
      });
      await _reloadGrid();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadGrid() async {
    setState(() {
      _grid.clear();
      _more = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _cs.listClips(category: _cat, access: _access, limit: _page, offset: _grid.length, sort: _sort);
      if (!mounted) return;
      setState(() {
        _grid.addAll(next);
        if (next.length < _page) _more = false;
      });
    } catch (_) {
      if (mounted) setState(() => _more = false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 700) _loadMore();
  }

  void _open(List<Clip> list, int i) => context.push('/player', extra: {'clips': list, 'index': i});

  // ------- glassy filter & sort sheet -------
  Future<void> _openFilters() async {
    var cat = _cat, sort = _sort, access = _access;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: StatefulBuilder(builder: (ctx, setSheet) {
          Widget pill(String label, bool on, VoidCallback tap) => GestureDetector(
                onTap: () => setSheet(tap),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: on ? const LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFFF4D6D)]) : null,
                    color: on ? null : Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: on ? Colors.transparent : Colors.white24),
                  ),
                  child: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              );
          Widget section(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
                child: Text(t, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 1)),
              );
          return Container(
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
            padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(ctx).padding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(9)))),
              const SizedBox(height: 14),
              Row(children: [
                const Text('Sort & filter', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                const Spacer(),
                if (cat != null || sort != 'trending' || access != null)
                  GestureDetector(onTap: () => setSheet(() { cat = null; sort = 'trending'; access = null; }), child: const Text('Reset', style: TextStyle(color: Color(0xFFFF8A9B), fontWeight: FontWeight.w700))),
              ]),
              section('SORT BY'),
              Wrap(spacing: 9, runSpacing: 9, children: [
                pill('🔥 Trending', sort == 'trending', () => sort = 'trending'),
                pill('🆕 Newest', sort == 'newest', () => sort = 'newest'),
                pill('⭐ Popular', sort == 'popular', () => sort = 'popular'),
              ]),
              section('ACCESS'),
              Wrap(spacing: 9, runSpacing: 9, children: [
                pill('All', access == null, () => access = null),
                pill('Free', access == 'free', () => access = 'free'),
                pill('Pro', access == 'pro', () => access = 'pro'),
              ]),
              section('CATEGORY'),
              Wrap(spacing: 9, runSpacing: 9, children: [
                pill('All', cat == null, () => cat = null),
                for (final c in _cats) pill(c['name'] as String, cat == (c['slug'] as String? ?? c['name']), () => cat = c['slug'] as String? ?? c['name'] as String),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() { _cat = cat; _sort = sort; _access = access; });
                    Navigator.pop(ctx);
                    _reloadGrid();
                  },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4D6D), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('Show results', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _boot,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D)))
              : _error != null
                  ? _Message('Could not load clips.', onRetry: _boot)
                  : CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(child: _header()),
                        if (_featured.isNotEmpty && !_filtered) ...[
                          SliverToBoxAdapter(child: _sectionTitle('🔥 Trending now', 'Fresh drops this week')),
                          SliverToBoxAdapter(child: _featuredRow()),
                        ],
                        SliverToBoxAdapter(child: _resultsBar()),
                        // dense masonry gallery — small varied tiles, minimal gaps, no white space
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                          sliver: SliverMasonryGrid.count(
                            crossAxisCount: 3,
                            mainAxisSpacing: 5,
                            crossAxisSpacing: 5,
                            childCount: _grid.length,
                            itemBuilder: (context, i) => ClipTile(clip: _grid[i], onTap: () => _open(_grid, i)),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 24 + MediaQuery.of(context).viewPadding.bottom),
                            child: Center(
                              child: _more
                                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFFF4D6D)))
                                  : Text(_grid.isEmpty ? 'No clips match your filters' : "That's all ${_grid.length} clips", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 4),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: const Text('C', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Discover', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, height: 1.0)),
              Text('Viral clips, ready for your brand', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          IconButton(onPressed: () => homeTab.value = 1, icon: const Icon(Icons.search_rounded)),
          // minimal filter icon — dot shows when a filter is active
          Stack(children: [
            IconButton(onPressed: _openFilters, icon: const Icon(Icons.tune_rounded)),
            if (_filtered) const Positioned(right: 8, top: 8, child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFFF4D6D))),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ]),
    );
  }

  // results bar — shows the active filter as removable chips, else a clean title
  Widget _resultsBar() {
    if (!_filtered) return _sectionTitle('All clips', _more ? 'Scroll to explore more' : '${_grid.length} templates');
    final chips = <Widget>[];
    void chip(String label, VoidCallback onClear) => chips.add(GestureDetector(
          onTap: () { onClear(); _reloadGrid(); },
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)), const SizedBox(width: 5), const Icon(Icons.close_rounded, color: Colors.white, size: 15)]),
          ),
        ));
    if (_sort != 'trending') chip(_sort == 'newest' ? 'Newest' : 'Popular', () => _sort = 'trending');
    if (_access != null) chip(_access == 'free' ? 'Free' : 'Pro', () => _access = null);
    if (_cat != null) chip(_cats.firstWhere((c) => (c['slug'] ?? c['name']) == _cat, orElse: () => {'name': _cat})['name'] as String, () => _cat = null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
      child: Row(children: [
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips))),
      ]),
    );
  }

  Widget _featuredRow() {
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _featured.length,
        separatorBuilder: (_, __) => const SizedBox(width: 13),
        itemBuilder: (context, i) => _FeaturedCard(clip: _featured[i], onTap: () => _open(_featured, i)),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.clip, this.onTap});
  final Clip clip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 178,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (clip.thumb != null)
                Image.network(clip.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF241E28)))
              else
                const ColoredBox(color: Color(0xFF241E28)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.transparent, Color(0x11000000), Color(0xE6000000)], stops: [0.28, 0.58, 1.0], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                ),
              ),
              Positioned(
                top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: clip.isPro ? const Color(0xFFF5A623) : const Color(0xFF12B76A), borderRadius: BorderRadius.circular(7)),
                  child: Text(clip.isPro ? 'PRO' : 'FREE', style: TextStyle(color: clip.isPro ? const Color(0xFF3A2600) : Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                ),
              ),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
              ),
              Positioned(
                left: 13, right: 13, bottom: 13,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(clip.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, height: 1.15)),
                  const SizedBox(height: 4),
                  Text('${clip.category ?? clip.genre ?? 'clip'} · ${clip.durationLabel}', style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ),
      ),
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
