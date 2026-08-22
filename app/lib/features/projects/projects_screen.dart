import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../models/editor_state.dart';
import '../../services/project_store.dart';
import '../../widgets/premium_empty_state.dart';
import '../home/home_shell.dart' show homeTab;

/// §21 Editor tab — saved-but-not-exported editor projects. Continue editing or
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
    // The tab lives in an IndexedStack (kept alive), so refresh whenever the
    // Editor tab is (re)selected — otherwise it shows a stale project list
    // after editing/exporting elsewhere.
    homeTab.addListener(_onTab);
  }

  void _onTab() {
    if (homeTab.value == 2 && mounted) _reload();
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTab);
    super.dispose();
  }

  void _reload() => setState(() { _future = context.read<ProjectStore>().list(); });

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
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.errText, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      await context.read<ProjectStore>().delete(p.id);
      if (mounted) _reload();
    }
  }

  /// "20 Aug 2026, 9:41 AM IST" in the device timezone.
  String _autosaveStamp(DateTime t) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ap = t.hour < 12 ? 'AM' : 'PM';
    final tz = t.timeZoneName; // device-local abbreviation (e.g. IST / GMT+5:30)
    return '${t.day} ${m[t.month - 1]} ${t.year}, $hh:${t.minute.toString().padLeft(2, '0')} $ap $tz';
  }

  /// "5 layers · 9:16 · autosaved" — read from the serialized project data.
  String _summary(SavedProject p) {
    final subs = (p.data['subs'] as List?)?.length ?? 0;
    final stk = (p.data['stk'] as List?)?.length ?? 0;
    final layers = subs + stk;
    final aspectIdx = p.data['aspect'] as int?;
    final aspect = (aspectIdx != null && aspectIdx >= 0 && aspectIdx < AspectOption.all.length)
        ? AspectOption.all[aspectIdx].label
        : 'Original';
    return '$layers ${layers == 1 ? 'layer' : 'layers'} · $aspect · autosaved';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const ScreenHeader(
            title: 'Editor',
            subtitle: 'Saved but not exported. Autosaved times are in your device timezone.',
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<SavedProject>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.brand));
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
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
                    itemCount: projects.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == projects.length) {
                        return const InfoPanel(
                          'Each clip appears once. Exported clips move to My Clips → Created and leave this list.',
                        );
                      }
                      return _projectCard(projects[i]);
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

  Widget _projectCard(SavedProject p) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.media),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              width: 54,
              height: 72,
              child: p.thumb != null
                  ? CachedNetworkImage(imageUrl: p.thumb!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const _ThumbFallback())
                  : const _ThumbFallback(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kSans, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 6),
              Text(_autosaveStamp(p.updatedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kMono, fontSize: 11.5, height: 1.3, color: AppColors.brand)),
              const SizedBox(height: 4),
              Text(_summary(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        const Divider(height: 1, thickness: 1, color: AppColors.line),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _continueBtn(p)),
          const SizedBox(width: 10),
          _deleteBtn(p),
        ]),
      ]),
    );
  }

  Widget _continueBtn(SavedProject p) => Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            HapticFeedback.lightImpact();
            _open(p);
          },
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.edit_outlined, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text('Continue editing', style: TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ),
      );

  Widget _deleteBtn(SavedProject p) => Material(
        color: AppColors.errBg,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _delete(p),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text('Delete', style: TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.errText)),
          ),
        ),
      );
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(color: AppColors.mediaPlaceholder),
        child: Icon(Icons.movie_creation_outlined, color: AppColors.inkGhost, size: 22),
      );
}
