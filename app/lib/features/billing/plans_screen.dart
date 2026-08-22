import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../models/plan.dart';
import '../../services/billing_service.dart';

// ── shared chrome ────────────────────────────────────────────────────────────

/// A 44×44 tappable nav glyph (back / close).
Widget _navIcon(IconData icon, VoidCallback onTap) => Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: AppColors.ink)),
      ),
    );

/// Nav row — leading glyph + page title (19/600).
Widget _navBar(BuildContext context, String title, {IconData leading = Icons.arrow_back_rounded}) => SizedBox(
      height: H.nav,
      child: Row(children: [
        _navIcon(leading, () => Navigator.of(context).maybePop()),
        const SizedBox(width: 2),
        Text(title, style: T.pageTitle),
      ]),
    );

/// Sticky footer block — top hairline, bg fill, stretched children.
Widget _footer({required List<Widget> children}) => Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

String _fmtPrice(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ══════════════════════════════ §07 Paywall ══════════════════════════════════

/// The entry a free user reaches when they tap Unlock. Close (X), a gold star
/// tile, the benefit list, and a sticky "See plans" CTA into the plan list.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  static const _benefits = [
    ('Every layer editable', 'Text, logo, username, CTA and stickers stay separate.'),
    ('No watermark', 'Clean renders straight to your gallery.'),
    ('A set number of edits', 'One credit per clip, valid through your plan window.'),
    ('Two devices', 'Phone and tablet on one account.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: H.nav,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _navIcon(Icons.close_rounded, () => Navigator.of(context).maybePop()),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Container(
                  width: 56, height: 56, alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.goldAccent, borderRadius: BorderRadius.circular(R.media)),
                  child: const Icon(Icons.star_rounded, size: 30, color: AppColors.ink),
                ),
                const SizedBox(height: 22),
                const Text('Subscribe to edit and export',
                    style: TextStyle(fontFamily: kSans, fontSize: 30, height: 1.08, fontWeight: FontWeight.w600, letterSpacing: -1.2, color: AppColors.ink)),
                const SizedBox(height: 12),
                const Text(
                  'Browsing and previews stay free. Editing layers and watermark-free rendering need an active plan.',
                  style: TextStyle(fontFamily: kSans, fontSize: 14.5, height: 1.55, fontWeight: FontWeight.w400, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 28),
                for (final b in _benefits) _benefitRow(b.$1, b.$2),
              ],
            ),
          ),
          _footer(children: [
            PrimaryBtn('See plans', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansListScreen()));
            }),
            const SizedBox(height: 12),
            const Text('Paid in USDT via Binance Pay · 30 calendar days',
                textAlign: TextAlign.center, style: T.caption),
          ]),
        ]),
      ),
    );
  }

  Widget _benefitRow(String title, String desc) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.brandTint, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 14, color: AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontFamily: kSans, fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 3),
              Text(desc, style: const TextStyle(fontFamily: kSans, fontSize: 13, height: 1.5, fontWeight: FontWeight.w400, color: AppColors.inkMuted)),
            ]),
          ),
        ]),
      );
}

// ══════════════════════════════ §08 Plans ════════════════════════════════════

/// The plan list — real plans fetched from BillingService, one selectable card
/// each, an info panel, and a sticky "Continue — N USDT" CTA into checkout.
class PlansListScreen extends StatefulWidget {
  const PlansListScreen({super.key});
  @override
  State<PlansListScreen> createState() => _PlansListScreenState();
}

class _PlansListScreenState extends State<PlansListScreen> {
  late Future<List<Plan>> _plans;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _plans = context.read<BillingService>().plans();
  }

  void _reload() => setState(() { _plans = context.read<BillingService>().plans(); });

  String? _popularId(List<Plan> plans) {
    for (final p in plans) {
      if (p.name.toLowerCase().contains('pro')) return p.id;
    }
    if (plans.length >= 2) return plans[1].id;
    return plans.isNotEmpty ? plans.first.id : null;
  }

  Future<void> _openCheckout(Plan p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckoutScreen(plan: p)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          _navBar(context, 'Choose a plan'),
          Expanded(
            child: FutureBuilder<List<Plan>>(
              future: _plans,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.brand));
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text("Couldn't load plans.", style: T.body),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _reload, child: const Text('Retry')),
                    ]),
                  );
                }
                final plans = snap.data ?? [];
                if (plans.isEmpty) {
                  return const Center(child: Text('No plans available yet.', style: T.body));
                }
                final popularId = _popularId(plans);
                final selectedId = _selectedId ?? popularId ?? plans.first.id;
                final selected = plans.firstWhere((p) => p.id == selectedId, orElse: () => plans.first);

                return Column(children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        for (final p in plans)
                          _planCard(p, selected: p.id == selectedId, popular: p.id == popularId, onTap: () => setState(() => _selectedId = p.id)),
                        const SizedBox(height: 6),
                        const InfoPanel(
                          'Your 30 days start on the day you pay, not on the 1st. One edit credit is used the moment a clip opens in the editor.',
                        ),
                      ],
                    ),
                  ),
                  _footer(children: [
                    PrimaryBtn('Continue — ${_fmtPrice(selected.priceUsd)} USDT', onTap: () => _openCheckout(selected)),
                  ]),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _planCard(Plan p, {required bool selected, required bool popular, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.large),
          border: Border.all(color: selected ? AppColors.brand : AppColors.line, width: selected ? 1.5 : 1),
          boxShadow: selected ? const [BoxShadow(color: AppColors.brandTint, blurRadius: 0, spreadRadius: 3)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Row(children: [
                Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kSans, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink))),
                if (popular) ...[const SizedBox(width: 8), _popularPill()],
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtPrice(p.priceUsd), style: T.price),
              const SizedBox(height: 2),
              const Text('USDT', style: T.caption),
            ]),
          ]),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.bgAlt),
          const SizedBox(height: 10),
          _kv('Duration', _durationLabel(p)),
          _kv('Edits included', _editsLabel(p)),
          _kv('Quality', p.quality),
          _kv('Devices', '${p.maxDevices}'),
        ]),
      ),
    );
  }

  Widget _popularPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.pill)),
        child: const Text('Popular', style: TextStyle(fontFamily: kSans, fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(k, style: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.inkMuted)),
          const Spacer(),
          Text(v, style: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ]),
      );

  String _durationLabel(Plan p) {
    for (final f in p.features) {
      final l = f.toLowerCase();
      if (l.contains('day') || l.contains('week') || l.contains('month')) return f;
    }
    return '30 days';
  }

  String _editsLabel(Plan p) => p.exportLimit == null ? 'Unlimited' : '${p.exportLimit} edits';
}

// ══════════════════════════ §09 Checkout (Binance Pay) ═══════════════════════
// The state machine below (enum, timers, polling of subscription() → 'active',
// and the BillingService.checkout call) is preserved exactly — only restyled.

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
  // countdown lives in a ValueNotifier so per-second ticks refresh ONLY the
  // timer text — not the whole waiting tree (which re-encoded the QR each tick).
  final ValueNotifier<Duration> _leftVN = ValueNotifier(const Duration(minutes: 15));
  Timer? _tick, _poll;
  bool _agree = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _leftVN.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _tick?.cancel(); // never leave a previous countdown/poll running
    _poll?.cancel();
    setState(() => _state = _PayState.starting);
    try {
      final order = await context.read<BillingService>().checkout(widget.plan.id);
      if (!mounted) return;
      _order = order;
      _payData = (order['qr_content']?.toString().isNotEmpty ?? false) ? order['qr_content'].toString() : (order['checkout_url']?.toString() ?? '');
      _address = order['address']?.toString() ?? _payData;
      _amount = (order['amount'] as num?)?.toDouble() ?? widget.plan.priceUsd;
      _leftVN.value = const Duration(minutes: 15);
      setState(() => _state = _PayState.waiting);
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _leftVN.value - const Duration(seconds: 1);
        if (next.isNegative) {
          _leftVN.value = Duration.zero;
          setState(() => _state = _PayState.expired); // 0:00 was shown last tick
          _tick?.cancel();
          _poll?.cancel();
        } else {
          _leftVN.value = next; // no setState → QR/order card don't rebuild
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

  static String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  double get _shownAmount => _amount == 0 ? widget.plan.priceUsd : _amount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          _navBar(context, 'Checkout'),
          Expanded(
            child: switch (_state) {
              _PayState.starting => const Center(child: CircularProgressIndicator(color: AppColors.brand)),
              _PayState.failed => _failed(),
              _PayState.confirmed => _confirmed(),
              _PayState.expired => _expired(),
              _PayState.waiting => _waiting(),
            },
          ),
        ]),
      ),
    );
  }

  // ── waiting: full order review + QR + sticky Pay button ────────────────────
  Widget _waiting() {
    final orderId = _order?['order_id']?.toString() ?? '—';
    final activeUntil = _fmtDate(DateTime.now().add(const Duration(days: 30)));
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            // waiting banner + countdown
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: BorderRadius.circular(R.thumb)),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.warnIcon, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Waiting for confirmation', style: TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.warnText))),
                ValueListenableBuilder<Duration>(
                  valueListenable: _leftVN,
                  builder: (_, d, __) => Text('Expires in ${_fmt(d)}', style: const TextStyle(fontFamily: kMono, fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.warnText)),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // order summary
            DesignCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Order summary', style: T.fieldLabel),
                const SizedBox(height: 14),
                _summaryRow('${widget.plan.name} · 30 days', '${_fmtPrice(_shownAmount)} USDT'),
                const SizedBox(height: 10),
                _summaryRow('Network fee (BSC)', '0.00'),
                const SizedBox(height: 12),
                Container(height: 1, color: AppColors.line),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Total', style: TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                  const Spacer(),
                  Text('${_fmtPrice(_shownAmount)} USDT', style: const TextStyle(fontFamily: kMono, fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink)),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // selected payment method
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.large),
                border: Border.all(color: AppColors.brand, width: 1.5),
                boxShadow: const [BoxShadow(color: AppColors.brandTint, blurRadius: 0, spreadRadius: 3)],
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40, alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFF3BA2F), borderRadius: BorderRadius.circular(R.tile)),
                  child: const Text('B', style: TextStyle(fontFamily: kSans, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Binance Pay', style: TextStyle(fontFamily: kSans, fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    SizedBox(height: 2),
                    Text('USDT · scan QR or copy the pay link', style: TextStyle(fontFamily: kSans, fontSize: 12.5, color: AppColors.inkMuted)),
                  ]),
                ),
                Container(
                  width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // dashed order id / active-until card
            CustomPaint(
              painter: const _DashedBorderPainter(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    const Text('Order ID', style: T.bodySmall),
                    const Spacer(),
                    Flexible(child: Text(orderId, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: T.data)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('Active until', style: T.bodySmall),
                    const Spacer(),
                    Text(activeUntil, style: T.data),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // QR
            Center(
              child: Container(
                width: 212, height: 212,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(R.media), border: Border.all(color: AppColors.line)),
                child: _payData.isEmpty
                    ? const Center(child: Text('—', style: T.body))
                    : QrImageView(data: _payData, version: QrVersions.auto, backgroundColor: Colors.white, gapless: true),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Scan with the Binance app\nUSDT · BEP20', textAlign: TextAlign.center, style: T.bodySmall),
            const SizedBox(height: 14),

            // address + copy
            DesignCard(
              child: Row(children: [
                Expanded(child: Text(_short(_address), style: T.data)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _address));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
                  },
                  child: const Text('Copy', style: TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.brand)),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // terms
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _agree = !_agree),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20, height: 20, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _agree ? AppColors.brand : AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _agree ? AppColors.brand : AppColors.lineStrong, width: 1.5),
                  ),
                  child: _agree ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Text('I agree to the terms and understand the plan is non-refundable once active.', style: T.bodySmall),
                ),
              ]),
            ),
          ],
        ),
      ),
      _footer(children: [
        PrimaryBtn('Pay with Binance Pay', onTap: _agree ? _payTap : null),
      ]),
    ]);
  }

  void _payTap() {
    final link = (_order?['checkout_url']?.toString().isNotEmpty ?? false) ? _order!['checkout_url'].toString() : _payData;
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment link copied — open it in the Binance app')));
  }

  Widget _summaryRow(String label, String value) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.inkMuted))),
        const SizedBox(width: 10),
        Text(value, style: const TextStyle(fontFamily: kMono, fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink)),
      ]);

  // ── confirmed ──────────────────────────────────────────────────────────────
  Widget _confirmed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56, alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.okBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: AppColors.okIcon, size: 30),
          ),
          const SizedBox(height: 16),
          Text('${widget.plan.name} is active', style: const TextStyle(fontFamily: kSans, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: AppColors.ink)),
          const SizedBox(height: 6),
          const Text('Payment confirmed on-chain. You can start editing right away.', textAlign: TextAlign.center, style: T.body),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: PrimaryBtn('Continue', onTap: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => PaidScreen(plan: widget.plan, amount: _shownAmount)),
              );
            }),
          ),
        ]),
      ),
    );
  }

  // ── expired ────────────────────────────────────────────────────────────────
  Widget _expired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.errBg, borderRadius: BorderRadius.circular(R.large)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Payment window expired', style: TextStyle(fontFamily: kSans, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.errText)),
            const SizedBox(height: 6),
            const Text('Nothing was charged.', textAlign: TextAlign.center, style: TextStyle(fontFamily: kSans, fontSize: 13.5, height: 1.45, color: AppColors.errTextDark)),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: PrimaryBtn('Start again', onTap: _start)),
          ]),
        ),
      ),
    );
  }

  // ── could-not-start (never a raw exception) ────────────────────────────────
  Widget _failed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DesignCard(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Checkout could not start', style: TextStyle(fontFamily: kSans, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text("We couldn't reach the payment service. Check your connection and try again.", textAlign: TextAlign.center, style: T.body),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: PrimaryBtn('Retry', onTap: _start)),
          ]),
        ),
      ),
    );
  }

  String _short(String a) => a.length <= 22 ? a : '${a.substring(0, 12)}…${a.substring(a.length - 8)}';
}

// ══════════════════════════════ §10 Paid ═════════════════════════════════════

/// Success screen — a green tick, the receipt card, and two ways forward.
class PaidScreen extends StatelessWidget {
  const PaidScreen({super.key, required this.plan, required this.amount});
  final Plan plan;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final activeUntil = _fmtDate(DateTime.now().add(const Duration(days: 30)));
    final credits = plan.exportLimit ?? 30;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              children: [
                Center(
                  child: Container(
                    width: 62, height: 62, alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.okBg, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 34, color: AppColors.okIcon),
                  ),
                ),
                const SizedBox(height: 22),
                const Text('Subscription active',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: kSans, fontSize: 27, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -1, color: AppColors.ink)),
                const SizedBox(height: 10),
                Text('Payment confirmed on-chain. ${plan.name} is live on this device for the next 30 days.',
                    textAlign: TextAlign.center, style: T.body),
                const SizedBox(height: 26),
                DesignCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(children: [
                    _row('Plan', Text(plan.name, style: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink))),
                    _divider(),
                    _row('Amount', Text('${_fmtPrice(amount)} USDT', style: const TextStyle(fontFamily: kMono, fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink))),
                    _divider(),
                    _row('Active until', Text(activeUntil, style: const TextStyle(fontFamily: kMono, fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink))),
                    _divider(),
                    _row('Edit credits', Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(R.pill)),
                      child: Text('$credits added', style: const TextStyle(fontFamily: kSans, fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.okText)),
                    )),
                  ]),
                ),
              ],
            ),
          ),
          _footer(children: [
            PrimaryBtn('Start editing', onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
            const SizedBox(height: 6),
            GhostBtn('Back to home', onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
          ]),
        ]),
      ),
    );
  }

  Widget _row(String key, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Text(key, style: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.inkMuted)),
          const Spacer(),
          value,
        ]),
      );

  Widget _divider() => Container(height: 1, color: AppColors.bgAlt);
}

// ── dashed rounded-rect border painter ───────────────────────────────────────
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  static const double _dash = 5, _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(R.large)));
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        dashed.addPath(metric.extractPath(dist, dist + _dash), Offset.zero);
        dist += _dash + _gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}
