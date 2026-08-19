import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/premium_empty_state.dart';
import '../../widgets/skeleton_grid.dart';
import '../home/home_shell.dart';

/// The "Templates" tab — clips the user saved (hearted) for later. In the new
/// nav this is the 4th destination (index 3). Kept alive by the IndexedStack,
/// so it reloads whenever its tab is (re)selected.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, this.tabIndex = 3});
  final int tabIndex;
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late Future<List<Clip>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CatalogService>().favorites();
    homeTab.addListener(_onTab);
  }

  void _onTab() {
    if (homeTab.value == widget.tabIndex && mounted) {
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
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const ScreenHeader(title: 'Templates', subtitle: 'Clips you saved for later'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => setState(() => _future = context.read<CatalogService>().favorites()),
              child: FutureBuilder<List<Clip>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SkeletonGrid(count: 6);
                  }
                  if (snap.hasError) {
                    return ListView(children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Column(children: [
                          Text("Couldn't load your templates.", style: TextStyle(color: AppColors.mut)),
                          TextButton(onPressed: () => setState(() => _future = context.read<CatalogService>().favorites()), child: const Text('Retry', style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.w700))),
                        ]),
                      ),
                    ]);
                  }
                  final clips = snap.data ?? [];
                  if (clips.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 60),
                      PremiumEmptyState(
                        icon: Icons.bookmark_border_rounded,
                        title: 'No saved templates yet',
                        subtitle: 'Tap the heart on any clip to save it\nas a template for quick access later.',
                      ),
                    ]);
                  }
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 11, crossAxisSpacing: 11, childAspectRatio: 9 / 14),
                    itemCount: clips.length,
                    itemBuilder: (context, i) => ClipTile(clip: clips[i], aspect: 9 / 14, showText: true, onTap: () => context.push('/player', extra: {'clips': clips, 'index': i})),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
