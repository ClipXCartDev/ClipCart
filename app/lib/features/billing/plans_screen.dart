import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../models/plan.dart';
import '../../services/billing_service.dart';
import '../../widgets/primary_button.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<List<Plan>> _plans;
  Map<String, dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _plans = context.read<BillingService>().plans();
    _loadSub();
  }

  Future<void> _loadSub() async {
    final s = await context.read<BillingService>().subscription();
    if (mounted) setState(() => _sub = s);
  }

  Future<void> _checkout(Plan plan) async {
    try {
      final order = await context.read<BillingService>().checkout(plan.id);
      if (!mounted) return;
      final payData = (order['qr_content']?.toString().isNotEmpty ?? false)
          ? order['qr_content'].toString()
          : order['checkout_url'].toString();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Pay ${order['amount']} ${order['currency']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Binance Pay (USDT · BEP20)', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: QrImageView(
                    data: payData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    gapless: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Scan with the Binance app to pay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              SelectableText(payData, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 10),
              const Text('Pay in the Binance app. Your plan unlocks automatically once the payment is confirmed — no need to refresh.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checkout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Go Pro', style: TextStyle(fontWeight: FontWeight.w800)), elevation: 0),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF17131F), Color(0xFF2A1330)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFC400), Color(0xFF3B82F6)]), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              const Text('Unlock every Pro clip', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: 6),
              const Text('Unlimited exports · no watermark · priority new drops. Crypto only · Binance Pay.', style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(children: [
              if (_sub != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.ok.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.ok)),
                  child: Row(children: [
                    const Icon(Icons.verified_rounded, color: AppColors.ok),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_sub!['plan_name']} · ${_sub!['status']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('Renews / expires ${(_sub!['expires_at'] ?? '').toString().split('T').first}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              FutureBuilder<List<Plan>>(
                future: _plans,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent)));
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Text("Couldn't load plans."),
                        TextButton(onPressed: () => setState(() => _plans = context.read<BillingService>().plans()), child: const Text('Retry', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800))),
                      ]),
                    );
                  }
                  final plans = snap.data ?? [];
                  if (plans.isEmpty) return const Text('No plans available yet.');
                  final topPrice = plans.map((p) => p.priceUsd).fold<double>(0, (a, b) => b > a ? b : a);
                  return Column(children: [for (final p in plans) _planCard(p, popular: p.priceUsd == topPrice && topPrice > 0)]);
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _planCard(Plan p, {bool popular = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: popular ? const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: popular ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
              const SizedBox(width: 10),
              if (popular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]), borderRadius: BorderRadius.circular(20)),
                  child: const Text('POPULAR', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('\$${p.priceUsd.toStringAsFixed(0)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
              const Text(' / mo', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            _feat(p.exportLabel),
            _feat('${p.quality} · ${p.maxDevices} device${p.maxDevices == 1 ? '' : 's'}'),
            for (final f in p.features) _feat(f),
            const SizedBox(height: 14),
            if (p.priceUsd > 0)
              PrimaryButton(label: popular ? 'Get ${p.name}' : 'Subscribe', icon: Icons.bolt_rounded, onPressed: () => _checkout(p)),
          ],
        ),
      ),
    );
  }

  Widget _feat(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0x2212B76A), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 12, color: AppColors.ok)),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
        ]),
      );
}
