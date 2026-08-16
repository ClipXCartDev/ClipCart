import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/premium_empty_state.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _cats = [];
  Future<List<Clip>>? _future; // null = idle (show suggestions)

  static const _ideas = ['Monday', 'weekend', 'reaction', 'crush', 'gym', 'exam', 'boss', 'friends'];

  @override
  void initState() {
    super.initState();
    context.read<CatalogService>().categories().then((c) {
      if (mounted) setState(() => _cats = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _search([String? term]) {
    if (term != null) _q.text = term;
    final query = _q.text.trim();
    if (query.isEmpty) {
      setState(() => _future = null);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _future = context.read<CatalogService>().listClips(q: query, limit: 60));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // premium search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: TextField(
                  controller: _q,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  onChanged: (v) {
                    if (v.isEmpty) setState(() => _future = null);
                  },
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Search clips, movies, moods…',
                    hintStyle: TextStyle(color: Colors.grey.withOpacity(0.8)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFF4D6D)),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () { _q.clear(); setState(() => _future = null); }),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            Expanded(child: _future == null ? _suggestions() : _results()),
          ],
        ),
      ),
    );
  }

  Widget _suggestions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        const SizedBox(height: 6),
        const Text('Browse by category', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in _cats) _chip(c['name'] as String, () => _searchCategory(c)),
        ]),
        const SizedBox(height: 26),
        const Text('Popular searches', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in _ideas) _chip('#$t', () => _search(t), muted: true),
        ]),
      ],
    );
  }

  void _searchCategory(Map<String, dynamic> c) {
    FocusScope.of(context).unfocus();
    _q.text = c['name'] as String;
    setState(() => _future = context.read<CatalogService>().listClips(category: (c['slug'] as String?) ?? c['name'] as String, limit: 60));
  }

  Widget _chip(String label, VoidCallback onTap, {bool muted = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: muted ? null : const LinearGradient(colors: [Color(0x1AFF7A59), Color(0x1AFF4D6D)]),
            color: muted ? Theme.of(context).cardColor : null,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: muted ? Colors.grey.withOpacity(0.25) : const Color(0x33FF4D6D)),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: muted ? null : const Color(0xFFE01A48))),
        ),
      );

  Widget _results() {
    return FutureBuilder<List<Clip>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D)));
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Couldn't search right now.", style: TextStyle(color: Colors.grey.shade600)),
              TextButton(onPressed: () => _search(), child: const Text('Retry', style: TextStyle(color: Color(0xFFE01A48), fontWeight: FontWeight.w800))),
            ]),
          );
        }
        final clips = snap.data ?? [];
        if (clips.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No clips found',
            subtitle: 'Try a different word, mood, or category.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.70),
          itemCount: clips.length,
          itemBuilder: (context, i) => ClipCard(clip: clips[i], onTap: () => context.push('/player', extra: {'clips': clips, 'index': i})),
        );
      },
    );
  }
}
