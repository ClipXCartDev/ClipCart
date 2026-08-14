import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';

const _cats = [
  ('All', null),
  ('Comedy', 'comedy'),
  ('Reactions', 'reactions'),
  ('Movie edits', 'movie-edits'),
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  String? _category;
  String _sort = 'trending';
  late Future<List<Clip>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Clip>> _load() =>
      context.read<CatalogService>().listClips(q: _q.text.trim(), category: _category, sort: _sort);

  void _run() => setState(() => _future = _load());

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            initialValue: _sort,
            onSelected: (v) {
              _sort = v;
              _run();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'trending', child: Text('Trending')),
              PopupMenuItem(value: 'newest', child: Text('Newest')),
              PopupMenuItem(value: 'popular', child: Text('Most used')),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: 'Search clips, movies, creators…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _run),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _cats.map((c) {
                final on = _category == c.$2;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(c.$1),
                    selected: on,
                    onSelected: (_) {
                      _category = c.$2;
                      _run();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Clip>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final clips = snap.data ?? [];
                if (clips.isEmpty) return const Center(child: Text('No results', style: TextStyle(color: Colors.grey)));
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 13, childAspectRatio: 0.60),
                  itemCount: clips.length,
                  itemBuilder: (context, i) => ClipCard(clip: clips[i], onTap: () => context.push('/clip/${clips[i].slug}')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
