import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../state/auth_controller.dart';
import '../../widgets/premium_empty_state.dart';

const _kAccent = AppColors.accent;

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
  String? _thisId; // the current device's device_id — never removable from here

  @override
  void initState() {
    super.initState();
    _load();
    context.read<AuthController>().auth.currentDeviceId().then((id) {
      if (mounted) setState(() => _thisId = id);
    }).catchError((_) {});
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.large)),
        title: const Text('Remove device?', style: T.section),
        content: Text('“${_deviceName(device)}” will be signed out and its slot freed.', style: T.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, color: AppColors.inkMuted))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(fontFamily: kSans, color: AppColors.errText, fontWeight: FontWeight.w700)),
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
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // nav row (design-system, matches Support/Notifications)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 20, 10),
            child: Row(children: [
              CircleIconBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              const Text('Devices', style: T.pageTitle),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 12),
                        child: Text('You can be signed in on up to 2 devices. Remove one to free a slot.', style: T.bodySmall),
                      ),
                      for (final d in devices) _deviceCard(d),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _deviceCard(Map<String, dynamic> d) {
    final id = d['id']?.toString();
    final removing = _removingId != null && _removingId == id;
    final isCurrent = _thisId != null && d['device_id']?.toString() == _thisId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.large),
          border: Border.all(color: isCurrent ? AppColors.brandBorder : AppColors.line),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(R.tile)),
            child: const Icon(Icons.phone_android_rounded, color: AppColors.brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_deviceName(d), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cardTitle),
              const SizedBox(height: 4),
              Text(_lastSeen(d), style: T.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          // You can't sign yourself out from the device list — remove it from the
          // OTHER device instead. Prevents an accidental self-deauth.
          if (isCurrent)
            StatusPill.ok('This device')
          else if (removing)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2.5))
          else
            _RemoveBtn(onTap: _removingId != null ? null : () => _remove(d)),
        ]),
      ),
    );
  }
}

class _RemoveBtn extends StatelessWidget {
  const _RemoveBtn({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.errBg,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text('Remove',
                style: TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600, color: onTap == null ? AppColors.inkGhost : AppColors.errTextDark)),
          ),
        ),
      );
}
