
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../projects/projects_screen.dart';
import '../saved/saved_screen.dart';
import '../search/search_screen.dart';
import 'discover_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Lets child tabs request a tab switch (e.g. Home's search icon → Explore).
final ValueNotifier<int> homeTab = ValueNotifier<int>(0);

/// Set by Home's "See all" to pre-filter the Explore tab to a category.
final ValueNotifier<String?> exploreCategory = ValueNotifier<String?>(null);

/// Scroll-heavy screens (the gallery) set this true on scroll-down so the dock
/// minimizes to a pill, and false on scroll-up so it springs back.
final ValueNotifier<bool> navMinimized = ValueNotifier<bool>(false);

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    homeTab.addListener(_onTabRequest);
  }

  void _onTabRequest() {
    if (mounted && homeTab.value != _index) setState(() => _index = homeTab.value);
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTabRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // New 5-tab structure (client): Home · Explore · Editor · Templates · Me.
    const tabs = [
      DiscoverScreen(),      // 0 Home — category rows + subscription banner
      _ExploreTab(),         // 1 Explore — search grid (reacts to exploreCategory)
      ProjectsScreen(),      // 2 Editor — saved in-progress projects
      SavedScreen(tabIndex: 3), // 3 Templates — saved (hearted) clips
      _AccountTab(),         // 4 Me — account + exports + help
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _LiquidDock(
          index: _index,
          onSelect: (i) { navMinimized.value = false; homeTab.value = i; setState(() => _index = i); },
        ),
      ),
    );
  }
}

/// Explore tab wrapper — rebuilds the SearchScreen with a fresh initialCategory
/// whenever Home's "See all" sets [exploreCategory].
class _ExploreTab extends StatelessWidget {
  const _ExploreTab();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: exploreCategory,
      builder: (_, cat, __) => SearchScreen(key: ValueKey(cat), initialCategory: cat),
    );
  }
}

// Icon set per destination: (unselected, selected, label).
const _dockItems = [
  (Icons.home_outlined, Icons.home_rounded, 'Home'),
  (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
  (Icons.video_settings_outlined, Icons.video_settings_rounded, 'Editor'),
  (Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Templates'),
  (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
];

/// Compact bottom nav bar — matches the design system: a clean solid bar with a
/// small pill indicator (brandSurface) behind the ACTIVE icon, icon over a tiny
/// label. Not a big floating capsule.
class _LiquidDock extends StatelessWidget {
  const _LiquidDock({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.surfaceDark : Colors.white;
    final inactive = dark ? AppColors.mutDark : AppColors.mut;
    final n = _dockItems.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(top: BorderSide(color: dark ? AppColors.lineDark : AppColors.line)),
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); onSelect(i); },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // M3 active-indicator pill (56×30, brandSurface) behind the icon
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: 56, height: 30,
                        decoration: BoxDecoration(
                          color: index == i ? AppColors.brandSurface : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          index == i ? _dockItems[i].$2 : _dockItems[i].$1,
                          color: index == i ? AppColors.brand : inactive,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _dockItems[i].$3,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: index == i ? FontWeight.w600 : FontWeight.w500,
                          color: index == i ? AppColors.brand : inactive,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void _infoDialog(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final initial = user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : '?';
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // gradient profile header
          Container(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 24, 20, 26),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF7E57DE), Color(0xFF6D45C9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(children: [
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 2)),
                alignment: Alignment.center,
                child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(user?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(20)),
                    child: Text((user?.role ?? 'customer').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // subscription upsell card
              GestureDetector(
                onTap: () => context.push('/plans'),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17131F),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFD89A3C), Color(0xFFEBAA2D)]), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Upgrade to Pro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        SizedBox(height: 2),
                        Text('All Pro clips · unlimited exports · no watermark', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white54),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              _MenuCard(children: [
                _MenuRow(Icons.star_rounded, 'Plans & subscription', () => context.push('/plans')),
                if (user?.isEditor == true) _MenuRow(Icons.video_camera_back_rounded, 'Creator studio', () => context.push('/creator')),
                _MenuRow(Icons.download_rounded, 'My exports', () => context.push('/exports')),
                _MenuRow(Icons.phone_android_rounded, 'Devices', () => context.push('/devices')),
              ]),
              const SizedBox(height: 14),
              _MenuCard(children: [
                _MenuRow(Icons.lock_outline_rounded, 'Change password', () => context.push('/change-password')),
                _MenuRow(Icons.support_agent_rounded, 'Help & support', () => context.push('/support')),
                _MenuRow(Icons.privacy_tip_outlined, 'Privacy & terms', () => _infoDialog(context, 'Privacy & terms', 'Your account data is used only to run ClipCart and is never sold. Exports render on your device. Full details at clipscart.app. Questions: clipxcart@gmail.com')),
              ]),
              const SizedBox(height: 14),
              _MenuCard(children: [
                _MenuRow(Icons.logout_rounded, 'Log out', () => context.read<AuthController>().logout(), danger: true),
              ]),
              const SizedBox(height: 18),
              const Text('ClipCart · v1.0', style: TextStyle(color: AppColors.mut, fontSize: 11)),
              // clear the floating dock so Log out / footer never overlaps it
              SizedBox(height: 96 + MediaQuery.of(context).viewPadding.bottom),
            ]),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final c = danger ? const Color(0xFFF04438) : null;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon, color: c ?? AppColors.accent, size: 22),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: c)),
      trailing: danger ? null : Icon(Icons.chevron_right_rounded, color: Colors.grey.withOpacity(0.5)),
      onTap: onTap,
    );
  }
}
