import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/clip_card.dart';

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
              return const Center(child: CircularProgressIndicator());
            }
            final clips = snap.data ?? [];
            if (clips.isEmpty) {
              return ListView(children: const [SizedBox(height: 140), Center(child: Text('No saved clips yet', style: TextStyle(color: Colors.grey)))]);
            }
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
    );
  }
}
