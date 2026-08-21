import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../services/billing_service.dart';

/// §23 Notifications — a pushed route with its own Scaffold and nav row. Rows are
/// derived from real state (subscription + latest export) so nothing is
/// fabricated; empty state when there is nothing.
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
  bool _allRead = false;
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
          out.add(_Notif('brand', Icons.play_arrow_rounded, 'Your video is ready', 'Open My Clips to play or share it.', 'TODAY'));
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
          // nav row: back · title · Mark read
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 20, 14),
            child: Row(children: [
              CircleIconBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              const Expanded(child: Text('Notifications', style: T.screenTitle)),
              GestureDetector(
                onTap: () => setState(() => _allRead = true),
                behavior: HitTestBehavior.opaque,
                child: const Text('Mark read', style: TextStyle(fontFamily: kSans, fontSize: 14, color: AppColors.brand, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          // filter pills
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              _pill('All', 0),
              const SizedBox(width: 8),
              _pill('Account', 1),
              const SizedBox(width: 8),
              _pill('Clips', 2),
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
                      Icon(Icons.notifications_none_rounded, size: 44, color: AppColors.inkGhost),
                      SizedBox(height: 14),
                      Text("You're all caught up", style: TextStyle(fontFamily: kSans, fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      SizedBox(height: 6),
                      Text('Account and clip updates will appear here.', style: TextStyle(fontFamily: kSans, fontSize: 14, color: AppColors.inkMuted)),
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.ink : AppColors.surfaceHover2,
          borderRadius: BorderRadius.circular(R.pill),
          border: on ? null : Border.all(color: AppColors.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: kSans, fontSize: 12.5, color: on ? Colors.white : AppColors.inkMuted, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
      ),
    );
  }

  Widget _row(_Notif n) {
    final (Color tileBg, Color tileFg) = switch (n.kind) {
      'ok' => (AppColors.okBg, AppColors.okIcon),
      'brand' => (AppColors.brandTint, AppColors.brand),
      'warn' => (AppColors.warnBg, AppColors.warnIcon),
      'gold' => (AppColors.goldBg, AppColors.goldText),
      _ => (AppColors.bgAlt, AppColors.inkMuted),
    };
    final unread = !_allRead; // derived rows are all fresh until "Mark read"
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.media),
        border: Border.all(color: unread ? AppColors.brandBorder : AppColors.line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(R.tile)),
          child: Icon(n.icon, size: 18, color: tileFg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: const TextStyle(fontFamily: kSans, fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 3),
            Text(n.body, style: const TextStyle(fontFamily: kSans, fontSize: 12.5, height: 1.5, color: AppColors.inkMuted)),
            const SizedBox(height: 8),
            Text(n.time, style: const TextStyle(fontFamily: kMono, fontSize: 11, color: AppColors.inkGhost)),
          ]),
        ),
        if (unread)
          Container(
            margin: const EdgeInsets.only(left: 10, top: 4),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
          ),
      ]),
    );
  }
}
