import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../models/plan.dart';
import '../../services/billing_service.dart';

/// Plans — one DesignCard per plan, a recommended card, and a footer line.
/// Checkout is a real screen (not a dialog) with four designed payment states.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<List<Plan>> _plans;

  @override
  void initState() {
    super.initState();
    _plans = context.read<BillingService>().plans();
  }

  void _reload() => setState(() => _plans = context.read<BillingService>().plans());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: FutureBuilder<List<Plan>>(
        future: _plans,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Couldn't load plans.", style: TextStyle(color: AppColors.mut)),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ]),
            );
          }
          final plans = snap.data ?? [];
          if (plans.isEmpty) return const Center(child: Text('No plans available yet.', style: TextStyle(color: AppColors.mut)));
          final topPrice = plans.map((p) => p.priceUsd).fold<double>(0, (a, b) => b > a ? b : a);
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + MediaQuery.of(context).viewPadding.bottom),
            children: [
              for (final p in plans) _planCard(p, recommended: p.priceUsd == topPrice && topPrice > 0),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Paid in USDT. Your plan unlocks automatically once the payment is confirmed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.mut, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _planCard(Plan p, {bool recommended = false}) {
    final card = Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: recommended ? AppColors.brand : AppColors.line, width: recommended ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: AppColors.ink))),
          Text('MONTHLY', style: eyebrow(AppColors.mut)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(p.priceUsd.toStringAsFixed(2), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1.0, color: AppColors.ink)),
          const SizedBox(width: 6),
          const Text('USDT / mo', style: TextStyle(fontSize: 14, color: AppColors.mut)),
        ]),
        const SizedBox(height: 14),
        _feat(p.exportLabel),
        _feat('${p.quality} · ${p.maxDevices} device${p.maxDevices == 1 ? '' : 's'}'),
        for (final f in p.features) _feat(f),
        const SizedBox(height: 16),
        if (p.priceUsd > 0)
          recommended
              ? SizedBox(height: 48, child: FilledButton(onPressed: () => _openCheckout(p), child: Text('Get ${p.name}')))
              : SizedBox(height: 44, child: OutlinedButton(onPressed: () => _openCheckout(p), child: const Text('Subscribe'))),
      ]),
    );
    if (!recommended) return card;
    // "MOST CHOSEN" pill overlapping the top-left edge
    return Stack(clipBehavior: Clip.none, children: [
      card,
      Positioned(
        left: 14, top: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.pill)),
          child: const Text('MOST CHOSEN', style: TextStyle(color: Colors.white, fontFamily: kMono, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        ),
      ),
    ]);
  }

  Widget _feat(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.check_rounded, size: 16, color: AppColors.ok)),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.35))),
        ]),
      );

  Future<void> _openCheckout(Plan p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckoutScreen(plan: p)));
    _reload();
  }
}

// ============================ Checkout screen ============================

enum _PayState { starting, waiting, confirmed, expired, failed }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.plan});
  final Plan plan;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  _PayState _state = _PayState.starting;
  Map<String, dynamic>? _order;
  String _payData = '';
  String _address = '';
  double _amount = 0;
  Duration _left = const Duration(minutes: 15);
  Timer? _tick, _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _state = _PayState.starting);
    try {
      final order = await context.read<BillingService>().checkout(widget.plan.id);
      if (!mounted) return;
      _order = order;
      _payData = (order['qr_content']?.toString().isNotEmpty ?? false) ? order['qr_content'].toString() : (order['checkout_url']?.toString() ?? '');
      _address = order['address']?.toString() ?? _payData;
      _amount = (order['amount'] as num?)?.toDouble() ?? widget.plan.priceUsd;
      setState(() {
        _state = _PayState.waiting;
        _left = const Duration(minutes: 15);
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _left - const Duration(seconds: 1);
        if (next.isNegative || next.inSeconds == 0) {
          setState(() { _left = Duration.zero; _state = _PayState.expired; });
          _tick?.cancel();
          _poll?.cancel();
        } else {
          setState(() => _left = next);
        }
      });
      // Poll the server (the ONLY authority on payment state) for confirmation.
      _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
        try {
          final sub = await context.read<BillingService>().subscription();
          if (!mounted) return;
          if ((sub?['status'] as String?)?.toLowerCase() == 'active') {
            setState(() => _state = _PayState.confirmed);
            _tick?.cancel();
            _poll?.cancel();
          }
        } catch (_) {}
      });
    } catch (_) {
      if (mounted) setState(() => _state = _PayState.failed);
    }
  }

  String get _timer {
    final m = _left.inMinutes, s = _left.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pay ${_amount == 0 ? widget.plan.priceUsd.toStringAsFixed(2) : _amount.toStringAsFixed(2)} USDT')),
      body: switch (_state) {
        _PayState.starting => const Center(child: CircularProgressIndicator(color: AppColors.brand)),
        _PayState.failed => _failed(),
        _PayState.confirmed => _confirmed(),
        _PayState.expired => _expired(),
        _PayState.waiting => _waiting(),
      },
    );
  }

  Widget _waiting() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // status banner
        _statusBanner(AppColors.warnBg, AppColors.warn, 'Waiting for confirmation', 'Expires in $_timer', dot: true),
        const SizedBox(height: 16),
        // QR card
        Center(
          child: Container(
            width: 212, height: 212,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(R.surface), border: Border.all(color: AppColors.line)),
            child: _payData.isEmpty
                ? const Center(child: Text('—'))
                : QrImageView(data: _payData, version: QrVersions.auto, backgroundColor: Colors.white, gapless: true),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Scan with your wallet app\nUSDT · BEP20', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.mut, height: 1.4)),
        const SizedBox(height: 16),
        // address card
        DesignCard(
          child: Row(children: [
            Expanded(child: Text(_short(_address), style: const TextStyle(fontFamily: kMono, fontSize: 12.5, color: AppColors.ink))),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _address));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
              },
              child: const Text('Copy', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // reassurance card
        DesignCard(
          child: RichText(
            text: const TextSpan(children: [
              TextSpan(text: 'You can close this screen. ', style: TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 13.5)),
              TextSpan(text: 'Your plan unlocks by itself the moment the payment is confirmed — there is nothing to refresh.', style: TextStyle(fontFamily: kSans, color: AppColors.mut, fontSize: 13.5, height: 1.5)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _confirmed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DesignCard(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 38, height: 38, decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 22)),
            const SizedBox(height: 12),
            const Text('Pro is active', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 4),
            const Text('Unlimited exports · renews next month', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.mut)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))),
          ]),
        ),
      ),
    );
  }

  Widget _expired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.errBg, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: AppColors.errBg)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Payment window expired', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.errText)),
            const SizedBox(height: 4),
            const Text('Nothing was charged.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.mut)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _start, child: const Text('Start again'))),
          ]),
        ),
      ),
    );
  }

  Widget _failed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DesignCard(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Checkout could not start', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text('We couldn’t reach the payment service. Please check your connection and try again.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.mut, height: 1.5)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _start, child: const Text('Retry'))),
          ]),
        ),
      ),
    );
  }

  Widget _statusBanner(Color bg, Color fg, String title, String sub, {bool dot = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.card)),
        child: Row(children: [
          if (dot) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: fg)),
              Text(sub, style: const TextStyle(fontSize: 12.5, color: AppColors.mut)),
            ]),
          ),
        ]),
      );

  String _short(String a) => a.length <= 22 ? a : '${a.substring(0, 12)}…${a.substring(a.length - 8)}';
}
