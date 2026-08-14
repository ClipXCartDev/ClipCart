import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/clip.dart';
import '../../services/creator_service.dart';
import '../../widgets/primary_button.dart';

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
                      const Text('Available balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                      Text('\$${available.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                      Text('Earned \$${(e?['earned'] ?? 0)} · ${e?['downloads'] ?? 0} downloads · pending \$${e?['pending'] ?? 0}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 180,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFE01A48)),
                          onPressed: available > 0 ? () => _requestPayout(available) : null,
                          icon: const Icon(Icons.payments, size: 18),
                          label: const Text('Request payout'),
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
                if (clips.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Text('No uploads yet.', style: TextStyle(color: Colors.grey)));
                return Column(
                  children: clips.map((c) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(width: 42, height: 54, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(8))),
                        title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${c.category ?? c.genre ?? ''} · ${c.downloads} downloads${c.reviewNote != null ? '\n“${c.reviewNote}”' : ''}'),
                        isThreeLine: c.reviewNote != null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _statusColor(c.status).withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                          child: Text((c.status ?? '').toUpperCase(), style: TextStyle(color: _statusColor(c.status), fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
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
