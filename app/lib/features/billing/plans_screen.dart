import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Pay ${order['amount']} ${order['currency']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Binance Pay (USDT · BEP20)', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText(order['qr_content']?.toString() ?? order['checkout_url'].toString(), style: const TextStyle(fontSize: 12)),
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
      appBar: AppBar(title: const Text('Plans', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_sub != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.accent)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_sub!['plan_name']} · ${_sub!['status']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('Expires ${(_sub!['expires_at'] ?? '').toString().split('T').first}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          const Text('Crypto only · Binance Pay · manual renewal', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          FutureBuilder<List<Plan>>(
            future: _plans,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
              }
              final plans = snap.data ?? [];
              if (plans.isEmpty) return const Text('No plans available yet.');
              return Column(children: plans.map(_planCard).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _planCard(Plan p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('\$${p.priceUsd.toStringAsFixed(0)} / mo', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _feat(p.exportLabel),
          _feat('${p.quality} · ${p.maxDevices} devices'),
          for (final f in p.features) _feat(f),
          const SizedBox(height: 12),
          if (p.priceUsd > 0) PrimaryButton(label: 'Subscribe', icon: Icons.bolt, onPressed: () => _checkout(p)),
        ],
      ),
    );
  }

  Widget _feat(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [const Icon(Icons.check, size: 16, color: AppColors.ok), const SizedBox(width: 8), Expanded(child: Text(t, style: const TextStyle(fontSize: 13)))]),
      );
}
