import 'dart:async';

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
  // Trending is what everyone else is already using; Newest is the one lever
  // a page that wants to be FIRST to a clip actually needs. Both are already
  // supported server-side — this was just never wired to anything.
  String _sort = 'trending';
  // The rest of section 7.3's filters. All of these were already understood by
  // the server; the app simply never sent them.
  String? _genre;
  String? _language;
  String? _movie;
  int? _maxDuration; // seconds
  String? _access;   // 'free' | 'pro'
  Map<String, List<String>> _facets = const {};
  /// The search field and chips fold away while the grid is moving. Driven by a
  /// settle timer rather than scroll direction, because the ask was that they
  /// come back when scrolling stops — direction alone would keep them hidden
  /// through a long flick that never reverses.
  bool _headerHidden = false;
  Timer? _headerSettle;
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

  /// Hide while moving, show once still. Near the top they always stay: folding
  /// them away there would flicker on the smallest nudge.
  void _headerOnScroll() {
    const settle = Duration(milliseconds: 320);
    _headerSettle?.cancel();
    if (_scroll.position.pixels <= 60) {
      if (_headerHidden) setState(() => _headerHidden = false);
      return;
    }
    if (!_headerHidden) setState(() => _headerHidden = true);
    _headerSettle = Timer(settle, () {
      if (mounted && _headerHidden) setState(() => _headerHidden = false);
    });
  }

  @override
  void dispose() {
    _headerSettle?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CatalogService get _cs => context.read<CatalogService>();

  Future<void> _boot() async {
    setState(() { _loading = true; _error = null; });
    try {
      try { _cats = await _cs.categories(); } catch (_) {}
      // non-fatal: without facets the sheet simply offers fewer rows
      try { _facets = await _cs.facets(); } catch (_) {}
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
        genre: _genre,
        language: _language,
        movie: _movie,
        maxDuration: _maxDuration,
        access: _access,
        limit: _page,
        offset: _grid.length,
        sort: _sort,
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
    _headerOnScroll();
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

  void _pickSort(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
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
  /// Search field and chips, folded away while the grid is being scrolled so
  /// the clips get the whole screen.
  Widget _collapsingHeader() {
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.bottomCenter,
        heightFactor: _headerHidden ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _headerHidden ? 0 : 1,
          duration: const Duration(milliseconds: 140),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 10),
                _filterButton(),
              ]),
            ),
            // sort + category chips — thin pills, brand-fill on select. Sort is
            // always shown; category chips wait for the category list.
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                children: [
                  _SortChip('Trending', Icons.local_fire_department_rounded, selected: _sort == 'trending', onTap: () => _pickSort('trending')),
                  _SortChip('Newest', Icons.bolt_rounded, selected: _sort == 'newest', onTap: () => _pickSort('newest')),
                  if (_cats.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: SizedBox(height: 18, child: VerticalDivider(width: 1, thickness: 1, color: AppColors.line)),
                    ),
                    const SizedBox(width: 4),
                    _CatChip('All', selected: _cat == null, onTap: () => _pickCategory(null)),
                    for (final c in _cats)
                      _CatChip(
                        (c['name'] as String?) ?? 'Clips',
                        selected: _cat == ((c['slug'] as String?) ?? c['name']),
                        onTap: () => _pickCategory((c['slug'] as String?) ?? c['name'] as String),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  /// Every filter currently narrowing the grid, as removable chips.
  /// "Active filters must be visible and removable" is the PRD's wording, and
  /// a filter you cannot see is the reason an empty grid looks like an empty
  /// catalogue.
  List<(String, VoidCallback)> _activeFilters() => [
        if (_cat != null) (_catName(_cat), () => _applyFilters(cat: null, clearCat: true)),
        if (_genre != null) (_genre!, () => _applyFilters(genre: null, clearGenre: true)),
        if (_language != null) (_language!, () => _applyFilters(language: null, clearLanguage: true)),
        if (_movie != null) (_movie!, () => _applyFilters(movie: null, clearMovie: true)),
        if (_maxDuration != null) ('Under ${_maxDuration}s', () => _applyFilters(maxDuration: null, clearDuration: true)),
        if (_access != null) (_access == 'free' ? 'Free' : 'Pro', () => _applyFilters(access: null, clearAccess: true)),
      ];

  /// One way in and out of a filter change, so nothing can set a filter without
  /// also resetting the paging that depends on it.
  void _applyFilters({
    String? cat, String? genre, String? language, String? movie,
    int? maxDuration, String? access,
    bool clearCat = false, bool clearGenre = false, bool clearLanguage = false,
    bool clearMovie = false, bool clearDuration = false, bool clearAccess = false,
  }) {
    setState(() {
      if (cat != null || clearCat) _cat = cat;
      if (genre != null || clearGenre) _genre = genre;
      if (language != null || clearLanguage) _language = language;
      if (movie != null || clearMovie) _movie = movie;
      if (maxDuration != null || clearDuration) _maxDuration = maxDuration;
      if (access != null || clearAccess) _access = access;
    });
    _reload();
  }

  void _clearAllFilters() => _applyFilters(
        clearCat: true, clearGenre: true, clearLanguage: true,
        clearMovie: true, clearDuration: true, clearAccess: true,
      );

  void _openFilter() {
    // local copies so Cancel is a real cancel
    String? cat = _cat, genre = _genre, language = _language, movie = _movie, access = _access;
    int? maxDur = _maxDuration;
    showAppSheet(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setSheet) {
        Widget section(String title, List<Widget> children) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(left: 2, top: 14, bottom: 6), child: Text(title, style: T.section)),
                Wrap(spacing: 8, runSpacing: 8, children: children),
              ],
            );

        Widget chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setSheet(onTap),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.brand : AppColors.bgAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: selected ? AppColors.brand : AppColors.line),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.ink)),
              ),
            );

        final genres = _facets['genres'] ?? const <String>[];
        final languages = _facets['languages'] ?? const <String>[];
        final movies = _facets['movies'] ?? const <String>[];

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(left: 2), child: Text('Filters', style: T.section)),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                section('Category', [
                  chip('All', cat == null, () => cat = null),
                  for (final c in _cats)
                    chip((c['name'] as String?) ?? 'Clips',
                        cat == ((c['slug'] as String?) ?? c['name'] as String?),
                        () => cat = (c['slug'] as String?) ?? c['name'] as String?),
                ]),
                if (genres.isNotEmpty)
                  section('Genre', [
                    chip('Any', genre == null, () => genre = null),
                    for (final g in genres) chip(g, genre == g, () => genre = g),
                  ]),
                if (languages.isNotEmpty)
                  section('Language', [
                    chip('Any', language == null, () => language = null),
                    for (final l in languages) chip(l, language == l, () => language = l),
                  ]),
                if (movies.isNotEmpty)
                  section('Movie', [
                    chip('Any', movie == null, () => movie = null),
                    for (final m in movies) chip(m, movie == m, () => movie = m),
                  ]),
                section('Length', [
                  chip('Any', maxDur == null, () => maxDur = null),
                  for (final d in const [10, 15, 30, 60])
                    chip('Under ${d}s', maxDur == d, () => maxDur = d),
                ]),
                section('Access', [
                  chip('Any', access == null, () => access = null),
                  chip('Free', access == 'free', () => access = 'free'),
                  chip('Pro', access == 'pro', () => access = 'pro'),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(
              onPressed: () => setSheet(() {
                cat = null; genre = null; language = null; movie = null; maxDur = null; access = null;
              }),
              child: const Text('Reset', style: TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryBtn('Show clips', onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _cat = cat; _genre = genre; _language = language;
                  _movie = movie; _maxDuration = maxDur; _access = access;
                });
                _reload();
              }),
            ),
          ]),
        ]);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _collapsingHeader(),
      // The active-filter bar is deliberately NOT part of the collapse: it is
      // the only thing explaining why the grid is short, and hiding it mid-
      // scroll would make a filtered grid look like an empty catalogue.
      if (_activeFilters().isNotEmpty) _activeFilterBar(),
      Expanded(child: _body()),
    ]);
  }

  Widget _searchField() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        const Icon(Icons.search_rounded, size: 20, color: AppColors.inkMuted),
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
            // flat: no fill / no border of its own — the pill IS the field
            decoration: const InputDecoration(
              isCollapsed: true,
              isDense: true,
              filled: false,
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 42, height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.brand : AppColors.brandTint,
              shape: BoxShape.circle,
              border: active ? null : Border.all(color: AppColors.brandBorder),
              boxShadow: active ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 3))] : null,
            ),
            child: Icon(Icons.tune_rounded, size: 20, color: active ? Colors.white : AppColors.brand),
          ),
          if (active)
            Positioned(
              right: 0, top: 0,
              child: Container(
                width: 16, height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 1.5)),
                child: const Text('1', style: TextStyle(fontFamily: kMono, fontSize: 8.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
              ),
            ),
        ]),
      ),
    );
  }

  /// The filters currently applied, each with a cross that removes just that
  /// one, plus a clear-all. Without this an over-filtered grid is
  /// indistinguishable from a catalogue with nothing in it.
  Widget _activeFilterBar() {
    final active = _activeFilters();
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        physics: const BouncingScrollPhysics(),
        children: [
          for (final f in active)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: f.$2,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(11, 0, 7, 0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brandTint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(f.$1,
                        style: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand)),
                    const SizedBox(width: 3),
                    const Icon(Icons.close_rounded, size: 14, color: AppColors.brand),
                  ]),
                ),
              ),
            ),
          if (active.length > 1)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clearAllFilters,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: const Text('Clear all',
                    style: TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    // Show the skeleton not just on first boot but whenever a (re)load is in
    // flight with nothing yet — otherwise a category switch / pull-to-refresh
    // briefly cleared the grid and flashed "No clips found" (client bug).
    if (_loading || (_loadingMore && _grid.isEmpty)) return const SkeletonGrid(count: 9, aspect: 9 / 13); // same shape as the real grid
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Couldn't load clips.", style: T.body),
          TextButton(onPressed: _boot, child: const Text('Retry', style: TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, color: AppColors.brand))),
        ]),
      );
    }
    if (_grid.isEmpty) {
      // An empty grid under filters is nearly always too many filters, not an
      // empty catalogue — so say which way out there is rather than leaving the
      // user to guess whether anything exists at all.
      final active = _activeFilters();
      if (active.isNotEmpty) {
        return PremiumEmptyState(
          icon: Icons.filter_alt_off_rounded,
          title: _query.isEmpty ? 'Nothing matches those filters' : 'Nothing matches "$_query" with those filters',
          subtitle: active.length == 1
              ? 'Remove the filter to see more clips.'
              : 'Remove a filter to see more clips.',
          cta: active.length == 1 ? 'Remove filter' : 'Clear filters',
          onCta: _clearAllFilters,
        );
      }
      return PremiumEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No clips found',
        subtitle: 'Try a different word, mood, or category.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async { _cs.clearCache(); await _reload(); },
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

/// Trending / Newest — the one control a page that wants to be first to a
/// clip actually needs; both sorts already existed server-side with nothing
/// on Explore to reach them. Same compact-pill language as the category
/// chips it sits beside, distinguished by a small leading glyph.
class _SortChip extends StatelessWidget {
  const _SortChip(this.label, this.icon, {required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: selected ? AppColors.brand : AppColors.line),
            boxShadow: selected
                ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.26), blurRadius: 9, offset: const Offset(0, 3))]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: selected ? Colors.white : AppColors.inkMuted),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Colors.white : AppColors.inkMuted)),
          ]),
        ),
      ),
    );
  }
}

/// Modern, compact Explore category chip. Thin pill; brand-fill + subtle glow
/// when selected, quiet outlined surface otherwise. Animates on selection.
class _CatChip extends StatelessWidget {
  const _CatChip(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: selected ? AppColors.brand : AppColors.line),
            boxShadow: selected
                ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.26), blurRadius: 9, offset: const Offset(0, 3))]
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 170),
            style: TextStyle(
              fontFamily: kSans,
              fontSize: 12.5,
              height: 1.0,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
            child: Text(label),
          ),
        ),
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
