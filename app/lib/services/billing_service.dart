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
  Future<Map<String, dynamic>?> subscription() async {
    final r = await api.dio.get('/billing/subscription');
    if (r.data == null) return null;
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<List<Map<String, dynamic>>> payments() async {
    final r = await api.dio.get('/billing/payments');
    return (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
