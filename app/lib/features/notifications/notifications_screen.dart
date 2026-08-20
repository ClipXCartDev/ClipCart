import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/billing_service.dart';

/// Notifications (Mobile §3.4) — carbon-copy chrome (header, filter pills, colored
/// vs dimmed rows). Rows are derived from real state (subscription + latest
/// export) so nothing is fabricated; empty state when there is nothing.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _Notif {
  _Notif(this.kind, this.icon, this.title, this.body, this.time);
  final String kind; // 'ok' | 'brand' | 'warn' | 'quiet'
  final IconData icon;
  final String title, body, time;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _filter = 0; // 0 All · 1 Account · 2 Clips
  late Future<List<_Notif>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Notif>> _load() async {
    final out = <_Notif>[];
    // subscription-derived row (account)
    try {
      final sub = await context.read<BillingService>().subscription();
      final status = (sub?['status'] as String?)?.toLowerCase();
      if (status == 'active') {
        out.add(_Notif('ok', Icons.check_rounded, 'Your subscription is active', 'Browse and export without a watermark.', 'RECENTLY'));
      }
    } catch (_) {}
    // latest export row (clips)
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports');
      if (dir.existsSync()) {
        final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList()
          ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        if (files.isNotEmpty) {
          out.add(_Notif('brand', Icons.play_arrow_rounded, 'Your video is ready', 'Open Library to play or share it.', 'TODAY'));
        }
      }
    } catch (_) {}
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Notifications', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.65, color: AppColors.ink)),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Text('Mark all read', style: TextStyle(fontSize: 13, color: AppColors.brand, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          // filter pills
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(children: [
              _pill('All', 0), const SizedBox(width: 7), _pill('Account', 1), const SizedBox(width: 7), _pill('Clips', 2),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<_Notif>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.brand));
                }
                var items = snap.data ?? [];
                if (_filter == 1) items = items.where((n) => n.kind == 'ok' || n.kind == 'warn').toList();
                if (_filter == 2) items = items.where((n) => n.kind == 'brand' || n.kind == 'quiet').toList();
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 90),
                    child: Column(children: [
                      Icon(Icons.notifications_none_rounded, size: 44, color: AppColors.mut),
                      SizedBox(height: 12),
                      Text("You're all caught up", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      SizedBox(height: 6),
                      Text('Account and clip updates will appear here.', style: TextStyle(fontSize: 14, color: AppColors.mut)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _row(items[i]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String label, int i) {
    final on = _filter == i;
    return GestureDetector(
      onTap: () => setState(() => _filter = i),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: on ? null : Border.all(color: AppColors.line),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, color: on ? Colors.white : AppColors.ink, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _row(_Notif n) {
    final (Color tileBg, Color tileFg, Color? cardBg, Color? cardBorder, bool dim) = switch (n.kind) {
      'ok' => (AppColors.okBg, AppColors.okText, const Color(0xFFF5FBF7), const Color(0xFFCFE6D6), false),
      'brand' => (AppColors.brandSurface, AppColors.brand, null, null, false),
      'warn' => (AppColors.warnBg, AppColors.warnText, null, null, false),
      _ => (const Color(0xFFF1EFEC), AppColors.mut, null, null, true),
    };
    return Opacity(
      opacity: dim ? 0.72 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg ?? AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder ?? AppColors.line),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(n.icon, size: 17, color: tileFg),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: TextStyle(fontSize: 15, fontWeight: dim ? FontWeight.w500 : FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(n.body, style: const TextStyle(fontSize: 13, color: AppColors.mut, height: 1.5)),
              const SizedBox(height: 6),
              Text(n.time, style: const TextStyle(fontFamily: kMono, fontSize: 11, color: AppColors.mut)),
            ]),
          ),
        ]),
      ),
    );
  }
}
