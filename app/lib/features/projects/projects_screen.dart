import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/project_store.dart';
import '../../widgets/premium_empty_state.dart';

/// The "Editor" tab: saved in-progress editor projects. Continue editing or
/// delete (client: "jin videos mein kaam kiya hai unki saved progress dikhe,
/// continue OR delete kar sake warna app size badh jayega").
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<SavedProject>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ProjectStore>().list();
  }

  void _reload() => setState(() => _future = context.read<ProjectStore>().list());

  Future<void> _open(SavedProject p) async {
    await context.push('/editor', extra: p);
    if (mounted) _reload(); // re-saving updates timestamps/thumbs
  }

  Future<void> _delete(SavedProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete project?', style: TextStyle(fontWeight: FontWeight.w600)),
        content: Text('“${p.name}” and its saved edits will be removed. This frees up space.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.err, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) {
      await context.read<ProjectStore>().delete(p.id);
      _reload();
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const ScreenHeader(title: 'Editor', subtitle: 'Your saved projects — continue or delete'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<SavedProject>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            final projects = snap.data ?? [];
            if (projects.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 70),
                PremiumEmptyState(
                  icon: Icons.video_settings_outlined,
                  title: 'No saved projects',
                  subtitle: 'Open a clip in the editor and your\nin-progress edits will be saved here.',
                ),
              ]);
            }
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 90 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = projects[i];
                return Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    await _delete(p);
                    return false; // _delete handles removal + reload itself
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(color: AppColors.errBg, borderRadius: BorderRadius.circular(R.card)),
                    child: const Icon(Icons.delete_outline_rounded, color: AppColors.err),
                  ),
                  child: GestureDetector(
                    onTap: () { HapticFeedback.lightImpact(); _open(p); },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(R.card),
                        border: Border.all(color: AppColors.line),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        // thumbnail (network clip thumb) or flat fallback
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: SizedBox(
                            width: 54, height: 54,
                            child: p.thumb != null
                                ? CachedNetworkImage(imageUrl: p.thumb!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const _ThumbFallback())
                                : const _ThumbFallback(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text('Edited ${_ago(p.updatedAt)} · tap to continue', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mut, fontSize: 12)),
                          ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.err),
                          onPressed: () => _delete(p),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.play_circle_fill_rounded, color: AppColors.accent, size: 30),
                        ),
                      ]),
                    ),
                  ),
                );
              },
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

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(color: AppColors.dark2),
        child: Icon(Icons.movie_creation_outlined, color: AppColors.mut, size: 22),
      );
}
