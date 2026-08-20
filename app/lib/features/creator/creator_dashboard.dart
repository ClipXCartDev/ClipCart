import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
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
    final amount = await Navigator.of(context).push<double>(
      MaterialPageRoute(builder: (_) => _PayoutScreen(available: available)),
    );
    if (amount == null) return;
    if (amount <= 0 || amount > available) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter an amount between \$0 and \$${available.toStringAsFixed(2)}')));
      return;
    }
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
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      );

  StatusPill _statusPill(String? s) => switch (s) {
        'approved' => StatusPill.ok('APPROVED'),
        'pending' => StatusPill.warn('PENDING'),
        'changes' => StatusPill.warn('CHANGES'),
        'rejected' => StatusPill.err('REJECTED'),
        _ => StatusPill.warn((s ?? 'DRAFT').toUpperCase()),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Creator studio', style: TextStyle(fontWeight: FontWeight.w600))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/creator/upload');
          setState(_reload);
        },
        backgroundColor: AppColors.accent,
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
                if (snap.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 176,
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(R.surface)),
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  );
                }
                if (snap.hasError) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.surface), border: Border.all(color: AppColors.line)),
                    child: Row(children: [
                      const Expanded(child: Text("Couldn't load your balance.", style: TextStyle(fontWeight: FontWeight.w600))),
                      TextButton(onPressed: () => setState(_reload), child: const Text('Retry', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600))),
                    ]),
                  );
                }
                final e = snap.data;
                final available = (e?['available'] as num?)?.toDouble() ?? 0;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(R.surface)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AVAILABLE BALANCE', style: const TextStyle(color: Colors.white70, fontFamily: kMono, fontWeight: FontWeight.w500, fontSize: 11, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text('\$${available.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
                      const SizedBox(height: 14),
                      Row(children: [
                        _stat('Earned', '\$${e?['earned'] ?? 0}'),
                        _stat('Downloads', '${e?['downloads'] ?? 0}'),
                        _stat('Pending', '\$${e?['pending'] ?? 0}'),
                      ]),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm))),
                          onPressed: available > 0 ? () => _requestPayout(available) : null,
                          icon: const Icon(Icons.payments_rounded, size: 18),
                          label: const Text('Request payout', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text('My uploads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.ink)),
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
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: AppColors.line)),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: SizedBox(
                              width: 44, height: 56,
                              child: c.thumb != null
                                  ? Image.network(c.thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.dark2))
                                  : const DecoratedBox(decoration: BoxDecoration(color: AppColors.dark2)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
                              const SizedBox(height: 2),
                              Text('${c.category ?? c.genre ?? ''} · ${c.downloads} downloads', style: const TextStyle(color: AppColors.mut, fontSize: 12)),
                              if (c.reviewNote != null) Text('“${c.reviewNote}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.err, fontSize: 11, fontStyle: FontStyle.italic)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          _statusPill(c.status),
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

/// Payout is a full screen, not a dialog (REBUILD §Step 12) — the amount is
/// returned via Navigator.pop so the dashboard can submit and refresh.
class _PayoutScreen extends StatefulWidget {
  const _PayoutScreen({required this.available});
  final double available;
  @override
  State<_PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends State<_PayoutScreen> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.available.toStringAsFixed(2));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount <= 0 || amount > widget.available) {
      setState(() => _error = 'Enter an amount between \$0 and \$${widget.available.toStringAsFixed(2)}.');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request payout', style: TextStyle(fontWeight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(R.surface)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AVAILABLE BALANCE', style: TextStyle(color: Colors.white70, fontFamily: kMono, fontWeight: FontWeight.w500, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text('\$${widget.available.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('Amount (USD)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
            decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.errBg, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: const Color(0xFFF3C7C7))),
              child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.errText)),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Payouts are sent in USDT to your saved address, usually within 3 business days.',
              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.mut)),
          const SizedBox(height: 20),
          SizedBox(height: 48, child: FilledButton(onPressed: _submit, child: const Text('Request payout'))),
        ],
      ),
    );
  }
}
