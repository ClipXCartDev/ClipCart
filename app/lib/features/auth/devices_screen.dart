import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../../widgets/premium_empty_state.dart';

const _kAccent = Color(0xFFFF4D6D);

/// Lists the devices bound to the account (max-2 anti-piracy control) and lets
/// the user unbind one to free a slot. Backed by AuthService.devices() /
/// removeDevice(), which call GET/DELETE /auth/devices.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _removingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context.read<AuthController>().auth.devices();
  }

  Future<void> _remove(Map<String, dynamic> device) async {
    final id = device['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove device?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('“${_deviceName(device)}” will be signed out and its slot freed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Color(0xFFF04438), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _removingId = id);
    try {
      await context.read<AuthController>().auth.removeDevice(id);
      if (!mounted) return;
      setState(() {
        _removingId = null;
        _load();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _removingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove device. Try again.')),
      );
    }
  }

  String _deviceName(Map<String, dynamic> d) {
    final os = (d['os'] as String?)?.trim();
    if (os != null && os.isNotEmpty) return os;
    return 'Unknown device';
  }

  String _lastSeen(Map<String, dynamic> d) {
    final raw = (d['last_active'] ?? d['last_login'])?.toString();
    if (raw == null) return 'Never active';
    final ts = DateTime.tryParse(raw);
    if (ts == null) return raw;
    final diff = DateTime.now().difference(ts.toLocal());
    if (diff.inMinutes < 1) return 'Active just now';
    if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
    if (diff.inDays < 30) return 'Active ${diff.inDays}d ago';
    return 'Active ${(diff.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kAccent));
          }
          if (snap.hasError) {
            return PremiumEmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Couldn’t load devices',
              subtitle: 'Check your connection and try again.',
              cta: 'Retry',
              onCta: () => setState(_load),
            );
          }
          final devices = snap.data ?? const [];
          if (devices.isEmpty) {
            return const PremiumEmptyState(
              icon: Icons.phone_android_rounded,
              title: 'No devices yet',
              subtitle: 'Devices you sign in on will appear here. You can be signed in on up to 2 devices.',
            );
          }
          return RefreshIndicator(
            color: _kAccent,
            onRefresh: () async => setState(_load),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final d = devices[i];
                final id = d['id']?.toString();
                final removing = _removingId != null && _removingId == id;
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: const Icon(Icons.phone_android_rounded, color: _kAccent),
                    title: Text(_deviceName(d), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    subtitle: Text(_lastSeen(d), style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
                    trailing: removing
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5),
                          )
                        : TextButton(
                            onPressed: _removingId != null ? null : () => _remove(d),
                            child: const Text('Remove', style: TextStyle(color: Color(0xFFF04438), fontWeight: FontWeight.w800)),
                          ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
