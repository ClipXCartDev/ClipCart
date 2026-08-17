import 'package:flutter/material.dart';
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

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late Future<List<Clip>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CatalogService>().favorites();
    // reload whenever the Saved tab (index 2) is (re)selected — the tab is kept
    // alive by the IndexedStack, so a fresh favorite won't show without this.
    homeTab.addListener(_onTab);
  }

  void _onTab() {
    if (homeTab.value == 2 && mounted) {
      setState(() => _future = context.read<CatalogService>().favorites());
    }
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liked', style: TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = context.read<CatalogService>().favorites()),
        child: FutureBuilder<List<Clip>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SkeletonGrid(count: 9);
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(
                  child: Column(children: [
                    Text("Couldn't load your saved clips.", style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(onPressed: () => setState(() => _future = context.read<CatalogService>().favorites()), child: const Text('Retry', style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ]);
            }
            final clips = snap.data ?? [];
            if (clips.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                PremiumEmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: 'No liked clips yet',
                  subtitle: 'Tap the heart on any clip to like it\nfor quick access later.',
                ),
              ]);
            }
            return MasonryGridView.count(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 80 + MediaQuery.of(context).viewPadding.bottom),
              crossAxisCount: 3,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              itemCount: clips.length,
              itemBuilder: (context, i) => ClipTile(clip: clips[i], onTap: () => context.push('/player', extra: {'clips': clips, 'index': i})),
            );
          },
        ),
      ),
    );
  }
}
