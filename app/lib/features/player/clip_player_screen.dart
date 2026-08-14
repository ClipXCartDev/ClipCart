import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/catalog_service.dart';
import '../../widgets/primary_button.dart';

/// Full-screen clip player (Instagram-style). Opens on tap from the gallery.
class ClipPlayerScreen extends StatefulWidget {
  const ClipPlayerScreen({super.key, required this.slug});
  final String slug;
  @override
  State<ClipPlayerScreen> createState() => _ClipPlayerScreenState();
}

class _ClipPlayerScreenState extends State<ClipPlayerScreen> {
  late final Future<Clip> _future = context.read<CatalogService>().getClip(widget.slug);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<Clip>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return Center(child: Text('Could not load clip', style: TextStyle(color: Colors.grey.shade400)));
          }
          final clip = snap.data!;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF1A2740), Color(0xFFC0304A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.82)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30), onPressed: () => context.pop()),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('@${clip.editorName ?? 'creator'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(width: 8),
                            if (clip.isPro)
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFF5A623), borderRadius: BorderRadius.circular(6)), child: const Text('PRO', style: TextStyle(color: Color(0xFF3A2600), fontSize: 10, fontWeight: FontWeight.w900))),
                          ]),
                          const SizedBox(height: 6),
                          Text(clip.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, children: [
                            for (final t in [clip.category ?? clip.genre ?? 'clip', clip.language, clip.durationLabel])
                              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)), child: Text('#$t', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                          ]),
                          const SizedBox(height: 14),
                          PrimaryButton(
                            label: 'Use template',
                            icon: Icons.auto_awesome,
                            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editor — coming in the next sprint'))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
