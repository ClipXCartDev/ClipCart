import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
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
          // Instagram-style search bar (client point 9)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                onChanged: (v) { if (v.isEmpty && _query.isNotEmpty) { setState(() => _query = ''); _reload(); } },
                style: const TextStyle(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Search clips, movies, moods…',
                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.8)),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.accent),
                  suffixIcon: _q.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () { _q.clear(); setState(() => _query = ''); _reload(); }),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          // category chips row
          if (_cats.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 9),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: AppColors.gradient) : null,
            color: on ? null : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? Colors.transparent : Colors.grey.withOpacity(0.25)),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: on ? Colors.white : null)),
        ),
      );

  Widget _body() {
    if (_loading) return const SkeletonGrid(count: 12);
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Couldn't load clips.", style: TextStyle(color: Colors.grey.shade600)),
          TextButton(onPressed: _boot, child: const Text('Retry', style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.w800))),
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
      child: MasonryGridView.count(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(8, 8, 8, 90 + MediaQuery.of(context).viewPadding.bottom),
        crossAxisCount: 3,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
        itemCount: _grid.length,
        itemBuilder: (context, i) => ClipTile(clip: _grid[i], onTap: () => context.push('/player', extra: {'clips': _grid, 'index': i})),
      ),
    );
  }
}
