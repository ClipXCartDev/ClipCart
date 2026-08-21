import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/premium_empty_state.dart';
import '../../widgets/skeleton_grid.dart';
import '../home/home_shell.dart';

/// §05 Explore — a search field + filter button, category chips, then a dense
/// 3-column grid of 9:13 thumbnails. Tiles carry no caption (only a duration
/// readout and a lock badge when gated); text appears only in the player.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialCategory});
  final String? initialCategory;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _page = 30;
  final _q = TextEditingController();
  final _scroll = ScrollController();
  final List<Clip> _grid = [];
  List<Map<String, dynamic>> _cats = [];
  String? _cat;
  String _query = '';
  bool _loading = true, _loadingMore = false, _more = true;
  String? _error;
  int _gen = 0; // bumps on every _reload; in-flight page loads with a stale gen are discarded

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory;
    _scroll.addListener(_onScroll);
    _boot();
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CatalogService get _cs => context.read<CatalogService>();

  Future<void> _boot() async {
    setState(() { _loading = true; _error = null; });
    try {
      try { _cats = await _cs.categories(); } catch (_) {}
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    // New query/category: invalidate any in-flight page load, then start fresh.
    _gen++;
    setState(() { _grid.clear(); _more = true; _loadingMore = false; _error = null; });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    final gen = _gen;
    final firstPage = _grid.isEmpty;
    setState(() => _loadingMore = true);
    try {
      final next = await _cs.listClips(
        q: _query.isEmpty ? null : _query,
        category: _cat,
        limit: _page,
        offset: _grid.length,
        sort: 'trending',
      );
      if (!mounted || gen != _gen) return; // a newer _reload superseded this load
      setState(() {
        _grid.addAll(next);
        if (next.length < _page) _more = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      // First-page failure = surface an error/retry (not a false "no clips").
      // A later-page failure just stops this attempt; scrolling retries.
      setState(() { if (firstPage) _error = '$e'; });
    } finally {
      if (mounted && gen == _gen) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 700) _loadMore();
    final dir = _scroll.position.userScrollDirection;
    if (_scroll.position.pixels < 120) {
      navMinimized.value = false;
    } else if (dir == ScrollDirection.reverse) {
      navMinimized.value = true;
    } else if (dir == ScrollDirection.forward) {
      navMinimized.value = false;
    }
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    setState(() => _query = _q.text.trim());
    _reload();
  }

  void _pickCategory(String? slug) {
    setState(() => _cat = slug);
    _reload();
  }

  String _catName(String? slug) {
    if (slug == null) return 'All';
    for (final c in _cats) {
      if (((c['slug'] as String?) ?? c['name']) == slug) return (c['name'] as String?) ?? slug;
    }
    return slug;
  }

  // ── filter sheet — categories only ─────────────────────────────────────────
  void _openFilter() {
    String? sel = _cat;
    showAppSheet(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setSheet) {
        final rows = <(String?, String)>[(null, 'All clips')];
        for (final c in _cats) {
          rows.add(((c['slug'] as String?) ?? c['name'] as String?, (c['name'] as String?) ?? 'Clips'));
        }
        final label = sel == _cat ? 'Show ${_grid.length} clips' : 'Show clips';
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 4),
            child: Text('Filter by category', style: T.section),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in rows)
                  _CheckRow(
                    label: r.$2,
                    selected: sel == r.$1,
                    onTap: () => setSheet(() => sel = r.$1),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(
              onPressed: () => setSheet(() => sel = null),
              child: const Text('Reset', style: TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(child: PrimaryBtn(label, onTap: () { Navigator.pop(ctx); _pickCategory(sel); })),
          ]),
        ]);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // search field + filter button
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Row(children: [
          Expanded(child: _searchField()),
          const SizedBox(width: 10),
          _filterButton(),
        ]),
      ),
      // category chips — compact, text-centered (no dead space under the label)
      if (_cats.isNotEmpty)
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(padding: const EdgeInsets.only(right: 8), child: PillChip('All', selected: _cat == null, filterStyle: true, onTap: () => _pickCategory(null))),
              for (final c in _cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillChip(
                    (c['name'] as String?) ?? 'Clips',
                    selected: _cat == ((c['slug'] as String?) ?? c['name']),
                    filterStyle: true,
                    onTap: () => _pickCategory((c['slug'] as String?) ?? c['name'] as String),
                  ),
                ),
            ],
          ),
        ),
      Expanded(child: _body()),
    ]);
  }

  Widget _searchField() {
    return Container(
      height: 42,
      decoration: BoxDecoration(color: AppColors.surfaceHover2, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(children: [
        const SizedBox(width: 14),
        const Icon(Icons.search_rounded, size: 20, color: AppColors.inkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
            onChanged: (v) {
              if (v.isEmpty && _query.isNotEmpty) { setState(() => _query = ''); _reload(); }
              setState(() {}); // keep the clear button in sync
            },
            style: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink),
            cursorColor: AppColors.brand,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search clips, movies, moods',
              hintStyle: TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.inkFaint),
            ),
          ),
        ),
        if (_q.text.isNotEmpty)
          GestureDetector(
            onTap: () { _q.clear(); setState(() => _query = ''); _reload(); },
            behavior: HitTestBehavior.opaque,
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.close_rounded, size: 18, color: AppColors.inkFaint)),
          )
        else
          const SizedBox(width: 14),
      ]),
    );
  }

  Widget _filterButton() {
    final active = _cat != null;
    return GestureDetector(
      onTap: _openFilter,
      child: SizedBox(
        width: 42, height: 42,
        child: Stack(children: [
          Container(
            width: 42, height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
            child: const Icon(Icons.tune_rounded, size: 20, color: Colors.white),
          ),
          if (active)
            Positioned(
              right: 0, top: 0,
              child: Container(
                width: 18, height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 1.5)),
                child: const Text('1', style: TextStyle(fontFamily: kMono, fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SkeletonGrid(count: 9);
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Couldn't load clips.", style: T.body),
          TextButton(onPressed: _boot, child: const Text('Retry', style: TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, color: AppColors.brand))),
        ]),
      );
    }
    if (_grid.isEmpty) {
      return PremiumEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No clips found',
        subtitle: _cat != null
            ? 'Nothing in ${_catName(_cat)} yet. Try another category.'
            : 'Try a different word, mood, or category.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      color: AppColors.brand,
      child: GridView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(3, 3, 3, 20 + MediaQuery.of(context).viewPadding.bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3, childAspectRatio: 9 / 13),
        itemCount: _grid.length,
        itemBuilder: (context, i) => _GridThumb(
          clip: _grid[i],
          onTap: () => context.push('/player', extra: {'clips': _grid, 'index': i}),
        ),
      ),
    );
  }
}

/// A dense grid tile — 9:13 media with a duration readout (bottom-left, soft
/// shadow) and a lock badge (top-right) on gated clips. No caption.
class _GridThumb extends StatelessWidget {
  const _GridThumb({required this.clip, this.onTap});
  final Clip clip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
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
          // duration readout (bottom-left, soft shadow)
          Positioned(
            left: 6, bottom: 6,
            child: Text(
              clip.durationLabel,
              style: const TextStyle(
                fontFamily: kMono, fontSize: 10, height: 1.0, fontWeight: FontWeight.w500, color: Colors.white,
                shadows: [Shadow(color: Color(0xB3141129), blurRadius: 4)],
              ),
            ),
          ),
          // lock badge (top-right)
          if (clip.isPro)
            Positioned(
              top: 6, right: 6,
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

/// A single checkbox row used inside the filter sheet.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.inner),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
          child: Row(children: [
            Expanded(child: Text(label, style: T.rowLabel)),
            Container(
              width: 22, height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: selected ? AppColors.brand : AppColors.lineStrong, width: 1.5),
              ),
              child: selected ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
            ),
          ]),
        ),
      ),
    );
  }
}
