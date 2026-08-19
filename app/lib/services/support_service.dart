import '../core/api_client.dart';

class SupportMessage {
  SupportMessage(this.id, this.fromUser, this.body, this.at);
  final String id;
  final bool fromUser; // true = me, false = support agent
  final String body;
  final DateTime at;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        j['id'] as String,
        (j['sender'] as String) == 'user',
        j['body'] as String,
        DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

/// In-app support chat client — talks to our backend (a CS agent replies from
/// the admin console). The screen polls [thread] for new agent replies.
class SupportService {
  SupportService(this.api);
  final ApiClient api;

  Future<List<SupportMessage>> thread() async {
    final r = await api.dio.get('/support/thread');
    final list = (r.data['messages'] as List?) ?? [];
    return list.map((e) => SupportMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<SupportMessage> send(String body) async {
    final r = await api.dio.post('/support/thread/messages', data: {'body': body});
    return SupportMessage.fromJson(Map<String, dynamic>.from(r.data as Map));
  }

  Future<void> markRead() async {
    try {
      await api.dio.post('/support/thread/read');
    } catch (_) {}
  }
}
