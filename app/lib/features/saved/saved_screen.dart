import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/premium_empty_state.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved', style: TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = context.read<CatalogService>().favorites()),
        child: FutureBuilder<List<Clip>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D)));
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(
                  child: Column(children: [
                    Text("Couldn't load your saved clips.", style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(onPressed: () => setState(() => _future = context.read<CatalogService>().favorites()), child: const Text('Retry', style: TextStyle(color: Color(0xFFE01A48), fontWeight: FontWeight.w800))),
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
                  title: 'No saved clips yet',
                  subtitle: 'Tap the heart on any clip to save it here\nfor quick access later.',
                ),
              ]);
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.60),
              itemCount: clips.length,
              itemBuilder: (context, i) => ClipCard(clip: clips[i], onTap: () => context.push('/player', extra: {'clips': clips, 'index': i})),
            );
          },
        ),
      ),
    );
  }
}
