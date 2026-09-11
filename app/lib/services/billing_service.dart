import '../core/api_client.dart';
import '../models/plan.dart';

class BillingService {
  BillingService(this.api);
  final ApiClient api;

  Future<List<Plan>> plans() async {
    final r = await api.dio.get('/billing/plans');
    return (r.data as List).map((e) => Plan.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns {payment_id, order_id, checkout_url, qr_content, amount, currency}.
  Future<Map<String, dynamic>> checkout(String planId) async {
    final r = await api.dio.post('/billing/checkout', data: {'plan_id': planId});
    return Map<String, dynamic>.from(r.data as Map);
  }

  /// null when the user has no active subscription.
  Map<String, dynamic>? _subCache;
  DateTime? _subAt;
  static const _subTtl = Duration(seconds: 45);

  /// Forget the cached subscription (after checkout / plan change).
  void invalidate() { _subCache = null; _subAt = null; }

  Future<Map<String, dynamic>?> subscription({bool force = false}) async {
    // Home already fetched it; the player/account reuse it instantly instead of
    // flashing the logged-out state while a second request is in flight.
    if (!force && _subAt != null && DateTime.now().difference(_subAt!) < _subTtl) return _subCache;
    final r = await api.dio.get('/billing/subscription');
    _subAt = DateTime.now();
    _subCache = r.data == null ? null : Map<String, dynamic>.from(r.data as Map);
    return _subCache;
  }

  Future<List<Map<String, dynamic>>> payments() async {
    final r = await api.dio.get('/billing/payments');
    return (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
