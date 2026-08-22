import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../services/billing_service.dart';
import '../../state/auth_controller.dart';
import '../library/library_screen.dart';
import '../projects/projects_screen.dart';
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

/// Legacy — the dock no longer minimizes; kept so callers still compile.
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
    // §4.7 five tabs: Home · Explore · Editor · My Clips · Account.
    const tabs = [
      DiscoverScreen(),           // 0 Home — category rails + plan banner
      _ExploreTab(),              // 1 Explore — search grid
      ProjectsScreen(),           // 2 Editor — unfinished drafts (§21)
      LibraryScreen(tabIndex: 3), // 3 My Clips — Created | Liked (§22)
      _AccountTab(),              // 4 Account (§24)
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(bottom: false, child: IndexedStack(index: _index, children: tabs)),
      bottomNavigationBar: _TabBar(
        index: _index,
        onSelect: (i) {
          HapticFeedback.selectionClick();
          homeTab.value = i;
          setState(() => _index = i);
        },
      ),
    );
  }
}

class _ExploreTab extends StatelessWidget {
  const _ExploreTab();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: exploreCategory,
        builder: (_, cat, __) => SearchScreen(key: ValueKey(cat), initialCategory: cat),
      );
}

// §4.7 bottom tab bar.
const _tabItems = [
  (Icons.home_outlined, Icons.home_rounded, 'Home'),
  (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Explore'),
  (Icons.auto_fix_high_outlined, Icons.auto_fix_high_rounded, 'Editor'),
  (Icons.folder_outlined, Icons.folder_rounded, 'My Clips'),
  (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
];

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Row(
            children: [
              for (var i = 0; i < _tabItems.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(index == i ? _tabItems[i].$2 : _tabItems[i].$1, size: 20, color: index == i ? AppColors.brand : AppColors.inkFaint),
                      const SizedBox(height: 6),
                      Text(_tabItems[i].$3,
                          style: T.tab.copyWith(fontWeight: index == i ? FontWeight.w600 : FontWeight.w500, color: index == i ? AppColors.brand : AppColors.inkFaint)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTab extends StatefulWidget {
  const _AccountTab();
  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  late Future<Map<String, dynamic>?> _sub;
  int? _deviceCount;

  @override
  void initState() {
    super.initState();
    _sub = context.read<BillingService>().subscription().catchError((_) => null);
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final list = await context.read<AuthController>().auth.devices();
      if (mounted) setState(() => _deviceCount = list.length);
    } catch (_) {/* leave as unknown */}
  }

  /// Re-fetch plan + device count (e.g. after returning from checkout or the
  /// devices screen) so the Account card never shows stale state.
  void _refresh() {
    if (!mounted) return;
    setState(() => _sub = context.read<BillingService>().subscription().catchError((_) => null));
    _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final initial = (user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : '?';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
      children: [
        const Text('Account', style: T.screenTitle),
        const SizedBox(height: 16),
        // profile card
        DesignCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 52, height: 52, alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: Text(initial, style: const TextStyle(fontFamily: kSans, fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(user?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kSans, fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                const SizedBox(height: 7),
                Text(user?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySmall),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 11),
        // dark plan card (§24)
        FutureBuilder<Map<String, dynamic>?>(
          future: _sub,
          builder: (context, snap) {
            final sub = snap.data;
            final active = (sub?['status']?.toString())?.toLowerCase() == 'active';
            final planName = active ? (sub?['plan_name'] ?? sub?['plan'] ?? 'Pro · 30 days').toString() : 'No plan';
            final until = (sub?['expires_at'] ?? sub?['active_until'] ?? sub?['current_period_end'])?.toString();
            // backend sends edit_credits (null = unlimited plan)
            final credits = active
                ? (sub != null && sub.containsKey('edit_credits') && sub['edit_credits'] == null ? 'Unlimited' : (sub?['edit_credits'] ?? sub?['credits_left'])?.toString())
                : null;
            return _PlanCard(planName: planName, active: active, until: until, credits: credits, isEditor: user?.isEditor == true);
          },
        ),
        const FieldLabel('Devices'),
        ListCard(children: [
          ListRowTile(icon: Icons.phone_android_rounded, label: 'This device', value: 'Active now', onTap: () async { await context.push('/devices'); _refresh(); }),
          ListRowTile(icon: Icons.devices_other_rounded, label: 'Manage devices', value: _deviceCount == null ? '—' : '$_deviceCount of 2', onTap: () async { await context.push('/devices'); _refresh(); }),
        ]),
        const FieldLabel('Settings'),
        ListCard(children: [
          ListRowTile(label: 'Help & support', onTap: () => context.push('/support')),
          ListRowTile(label: 'Notifications', onTap: () => context.push('/notifications')),
          ListRowTile(label: 'Plans & subscription', onTap: () async { await context.push('/plans'); _refresh(); }),
          if (user?.isEditor == true) ListRowTile(label: 'Creator studio', onTap: () => context.push('/creator')),
          ListRowTile(label: 'Log out', danger: true, chevron: false, onTap: () => context.read<AuthController>().logout()),
        ]),
        const SizedBox(height: 20),
        const Center(child: Text('ClipCart 3.0.0 · Android + iOS', style: TextStyle(fontFamily: kMono, fontSize: 11, color: AppColors.inkGhost))),
      ],
    );
  }
}

/// Dark plan contrast card (§24) — `ink` fill, light copy, brand pill.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.planName, required this.active, required this.until, required this.credits, required this.isEditor});
  final String planName;
  final bool active;
  final String? until, credits;
  final bool isEditor;

  @override
  Widget build(BuildContext context) {
    String fmtDate(String? s) {
      if (s == null) return '—';
      final d = DateTime.tryParse(s);
      if (d == null) return s.length > 10 ? s.substring(0, 10) : s;
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${m[d.month - 1]}';
    }

    Widget stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontFamily: kSans, fontSize: 11, color: Color(0xFF8E8880))),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontFamily: kMono, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkDark)),
        ]);

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B54C9), Color(0xFF4A38A6)],
        ),
        borderRadius: BorderRadius.circular(R.large),
        boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Your plan', style: TextStyle(fontFamily: kSans, fontSize: 11.5, color: AppColors.mutDark)),
              const SizedBox(height: 9),
              Text(planName, style: const TextStyle(fontFamily: kSans, fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: AppColors.inkDark)),
            ]),
          ),
          active ? StatusPill.ok('Active') : StatusPill.err('Inactive'),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          stat('Edit credits', active ? (credits ?? '—') : '0 / 0'),
          const SizedBox(width: 26),
          stat('Active until', active ? fmtDate(until) : '—'),
          const Spacer(),
          EditorPill(active ? 'Manage' : 'Subscribe', onTap: () => context.push('/plans')),
        ]),
      ]),
    );
  }
}
