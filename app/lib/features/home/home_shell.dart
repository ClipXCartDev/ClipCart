import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../exports/exports_screen.dart';
import '../saved/saved_screen.dart';
import '../search/search_screen.dart';
import 'discover_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Lets child tabs request a tab switch (e.g. Discover's search icon → Search).
final ValueNotifier<int> homeTab = ValueNotifier<int>(0);

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
    const tabs = [
      DiscoverScreen(),
      SearchScreen(),
      SavedScreen(),
      ExportsScreen(),
      _AccountTab(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) { homeTab.value = i; setState(() => _index = i); },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Saved'),
          NavigationDestination(icon: Icon(Icons.download_outlined), label: 'Exports'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
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
              gradient: LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFFF4D6D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(children: [
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 2)),
                alignment: Alignment.center,
                child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
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
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFC400), Color(0xFFFF7A00)]), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Upgrade to Pro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
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
                _MenuRow(Icons.download_rounded, 'My exports', () => homeTab.value = 3),
                _MenuRow(Icons.phone_android_rounded, 'Devices', () => context.push('/plans')),
              ]),
              const SizedBox(height: 14),
              _MenuCard(children: [
                _MenuRow(Icons.help_outline_rounded, 'Help & support', () => _infoDialog(context, 'Help & support', 'Need a hand? Email us at clipxcart@gmail.com and we\'ll get back within 48 hours.')),
                _MenuRow(Icons.privacy_tip_outlined, 'Privacy & terms', () => _infoDialog(context, 'Privacy & terms', 'Your account data is used only to run ClipCart and is never sold. Exports render on your device. Full details at clipscart.app. Questions: clipxcart@gmail.com')),
              ]),
              const SizedBox(height: 14),
              _MenuCard(children: [
                _MenuRow(Icons.logout_rounded, 'Log out', () => context.read<AuthController>().logout(), danger: true),
              ]),
              const SizedBox(height: 20),
              const Text('ClipCart · v1.0', style: TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: 20),
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
      leading: Icon(icon, color: c ?? const Color(0xFFFF4D6D), size: 22),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: c)),
      trailing: danger ? null : Icon(Icons.chevron_right_rounded, color: Colors.grey.withOpacity(0.5)),
      onTap: onTap,
    );
  }
}
