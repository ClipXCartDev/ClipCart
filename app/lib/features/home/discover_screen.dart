import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Clip> _all = [];
  List<Clip> _featured = [];
  List<Map<String, dynamic>> _cats = [];
  String? _cat;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cs = context.read<CatalogService>();
      final all = await cs.listClips(limit: 60, sort: 'trending');
      List<Map<String, dynamic>> cats = [];
      try {
        cats = await cs.categories();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _all = all;
        _featured = all.where((c) => c.thumb != null).take(6).toList();
        _cats = cats;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Clip> get _filtered {
    if (_cat == null) return _all;
    return _all.where((c) => (c.category ?? '').toLowerCase() == _cat!.toLowerCase()).toList();
  }

  void _open(List<Clip> list, int i) => context.push('/player', extra: {'clips': list, 'index': i});

  @override
  Widget build(BuildContext context) {
    final grid = _filtered;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D)))
              : _error != null
                  ? _Message('Could not load clips.', onRetry: _load)
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _header()),
                        if (_featured.isNotEmpty) ...[
                          SliverToBoxAdapter(child: _sectionTitle('🔥 Trending now', 'Fresh drops this week')),
                          SliverToBoxAdapter(child: _featuredRow()),
                        ],
                        SliverToBoxAdapter(child: _catChips()),
                        SliverToBoxAdapter(child: _sectionTitle(_cat == null ? 'All clips' : _cat!, '${grid.length} ready-to-use templates')),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.60,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => ClipCard(clip: grid[i], onTap: () => _open(grid, i)),
                              childCount: grid.length,
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
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 4),
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
              Text('Discover', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, height: 1.0)),
              Text('Viral clips, ready for your brand', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.search_rounded)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ]),
    );
  }

  Widget _featuredRow() {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _featured.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _FeaturedCard(clip: _featured[i], onTap: () => _open(_featured, i)),
      ),
    );
  }

  Widget _catChips() {
    final chips = <(String?, String)>[(null, 'All'), for (final c in _cats) (c['slug'] as String? ?? c['name'] as String, c['name'] as String)];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = _cat == chips[i].$1 || (i == 0 && _cat == null);
          return GestureDetector(
            onTap: () => setState(() => _cat = chips[i].$1),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: on ? const LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFFF4D6D)]) : null,
                color: on ? null : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: on ? Colors.transparent : Colors.grey.withOpacity(0.3)),
              ),
              child: Text(chips[i].$2, style: TextStyle(color: on ? Colors.white : null, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          );
        },
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
        width: 168,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (clip.thumb != null)
                Image.network(clip.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF241E28)))
              else
                const ColoredBox(color: Color(0xFF241E28)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.transparent, Color(0x11000000), Color(0xE0000000)], stops: [0.3, 0.6, 1.0], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                ),
              ),
              Positioned(
                top: 10, left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: clip.isPro ? const Color(0xFFF5A623) : const Color(0xFF12B76A), borderRadius: BorderRadius.circular(6)),
                  child: Text(clip.isPro ? 'PRO' : 'FREE', style: TextStyle(color: clip.isPro ? const Color(0xFF3A2600) : Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                ),
              ),
              const Positioned(
                top: 8, right: 8,
                child: CircleAvatar(radius: 15, backgroundColor: Colors.white24, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20)),
              ),
              Positioned(
                left: 12, right: 12, bottom: 12,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(clip.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, height: 1.15)),
                  const SizedBox(height: 3),
                  Text('${clip.category ?? clip.genre ?? 'clip'} · ${clip.durationLabel}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
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
