import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/premium_empty_state.dart';
import '../../widgets/skeleton_grid.dart';
import '../home/home_shell.dart';

/// Explore — an Instagram-style browse grid with a search bar pinned on top.
/// Shows all clips by default; typing filters. Category chips scroll under the
/// search bar. Grid tiles hide their caption (text shows only in the player).
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
    setState(() { _grid.clear(); _more = true; });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _cs.listClips(
        q: _query.isEmpty ? null : _query,
        category: _cat,
        limit: _page,
        offset: _grid.length,
        sort: 'trending',
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const ScreenHeader(title: 'Explore'),
          // search bar — design spec: 46px, radius 12, --ln border, --mut icon
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                onChanged: (v) { if (v.isEmpty && _query.isNotEmpty) { setState(() => _query = ''); _reload(); } },
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search clips, movies, moods…',
                  hintStyle: const TextStyle(color: AppColors.mut, fontSize: 16, fontWeight: FontWeight.w400),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.mut, size: 22),
                  suffixIcon: _q.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.mut), onPressed: () { _q.clear(); setState(() => _query = ''); _reload(); }),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brand, width: 1.5)),
                ),
              ),
            ),
          ),
          // category chips row (34px pills, radius 999)
          if (_cats.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _chip('All', _cat == null, () => _pickCategory(null)),
                  for (final c in _cats)
                    _chip(c['name'] as String, _cat == ((c['slug'] as String?) ?? c['name']), () => _pickCategory((c['slug'] as String?) ?? c['name'] as String)),
                ],
              ),
            ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  // design chip: h34, radius 999; selected = ink fill / white text, unselected = --ln border
  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? AppColors.brand : AppColors.line),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : AppColors.ink)),
        ),
      );

  Widget _body() {
    if (_loading) return const SkeletonGrid(count: 6);
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Couldn't load clips.", style: TextStyle(color: AppColors.mut)),
          TextButton(onPressed: _boot, child: const Text('Retry', style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.w700))),
        ]),
      );
    }
    if (_grid.isEmpty) {
      return const PremiumEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No clips found',
        subtitle: 'Try a different word, mood, or category.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: GridView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 7, crossAxisSpacing: 7, childAspectRatio: 9 / 14),
        itemCount: _grid.length,
        // Explore tiles are caption-less (feedback 2) — text shows only when opened.
        itemBuilder: (context, i) => ClipTile(clip: _grid[i], aspect: 9 / 14, onTap: () => context.push('/player', extra: {'clips': _grid, 'index': i})),
      ),
    );
  }
}
