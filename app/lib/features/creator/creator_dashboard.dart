import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/creator_service.dart';
import '../../widgets/premium_empty_state.dart';

class CreatorDashboard extends StatefulWidget {
  const CreatorDashboard({super.key});
  @override
  State<CreatorDashboard> createState() => _CreatorDashboardState();
}

class _CreatorDashboardState extends State<CreatorDashboard> {
  late Future<Map<String, dynamic>> _earnings;
  late Future<List<Clip>> _uploads;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final s = context.read<CreatorService>();
    _earnings = s.earnings();
    _uploads = s.myUploads();
  }

  Future<void> _requestPayout(double available) async {
    final ctrl = TextEditingController(text: available.toStringAsFixed(2));
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request payout'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (USD)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)), child: const Text('Request')),
        ],
      ),
    );
    if (amount == null) return;
    try {
      await context.read<CreatorService>().requestPayout(amount);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payout requested')));
        setState(_reload);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  Color _statusColor(String? s) => switch (s) {
        'approved' => const Color(0xFF12B76A),
        'pending' => const Color(0xFFF79009),
        'changes' || 'rejected' => const Color(0xFFF04438),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Creator studio', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/creator/upload');
          setState(_reload);
        },
        backgroundColor: const Color(0xFFFF4D6D),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Upload', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: _earnings,
              builder: (context, snap) {
                final e = snap.data;
                final available = (e?['available'] as num?)?.toDouble() ?? 0;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AVAILABLE BALANCE', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Text('\$${available.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 14),
                      Row(children: [
                        _stat('Earned', '\$${e?['earned'] ?? 0}'),
                        _stat('Downloads', '${e?['downloads'] ?? 0}'),
                        _stat('Pending', '\$${e?['pending'] ?? 0}'),
                      ]),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFE01A48), padding: const EdgeInsets.symmetric(vertical: 12)),
                          onPressed: available > 0 ? () => _requestPayout(available) : null,
                          icon: const Icon(Icons.payments_rounded, size: 18),
                          label: const Text('Request payout', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text('My uploads', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            FutureBuilder<List<Clip>>(
              future: _uploads,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
                }
                final clips = snap.data ?? [];
                if (clips.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: PremiumEmptyState(icon: Icons.cloud_upload_outlined, title: 'No uploads yet', subtitle: 'Tap Upload to submit your first clip.\nApproved clips earn on every download.'),
                  );
                }
                return Column(
                  children: clips.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.withOpacity(0.15))),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: SizedBox(
                              width: 44, height: 56,
                              child: c.thumb != null
                                  ? Image.network(c.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF241E28)))
                                  : const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('${c.category ?? c.genre ?? ''} · ${c.downloads} downloads', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              if (c.reviewNote != null) Text('“${c.reviewNote}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF04438), fontSize: 11, fontStyle: FontStyle.italic)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: _statusColor(c.status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                            child: Text((c.status ?? '').toUpperCase(), style: TextStyle(color: _statusColor(c.status), fontSize: 9.5, fontWeight: FontWeight.w900)),
                          ),
                        ]),
                      )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
