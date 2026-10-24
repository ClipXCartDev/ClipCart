import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../services/update_service.dart';

/// Stands in front of the whole app when the installed build is too old.
///
/// Blocking on purpose: the client is handed the APK directly, so an old build
/// keeps talking to a server that has moved on, and a dismissible nag is one
/// people learn to dismiss. There is nothing to do here but update, so there
/// is nothing else on the screen.
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    if (!u.required) return child;
    return const _UpdateRequiredScreen();
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final busy = u.downloadProgress != null;
    final pct = ((u.downloadProgress ?? 0) * 100).round();
    return PopScope(
      // Back must not get past it either.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Container(
                  width: 56, height: 56, alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.brandTint, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.system_update_rounded, size: 28, color: AppColors.brand),
                ),
                const SizedBox(height: 22),
                const Text('A newer ClipCart is ready',
                    style: TextStyle(
                        fontFamily: kSans, fontSize: 26, height: 1.2,
                        fontWeight: FontWeight.w600, letterSpacing: -0.8, color: AppColors.ink)),
                const SizedBox(height: 12),
                Text(
                  u.notes.trim().isNotEmpty
                      ? u.notes.trim()
                      : 'This version is out of date. Update to carry on — your saved clips and drafts stay where they are.',
                  style: const TextStyle(
                      fontFamily: kSans, fontSize: 14, height: 1.6,
                      fontWeight: FontWeight.w400, color: AppColors.inkMuted),
                ),
                if (u.latestVersion.isNotEmpty &&
                    UpdateService.compareVersions(u.installedVersion, u.latestVersion) < 0) ...[
                  const SizedBox(height: 18),
                  Row(children: [
                    Text('Installed ${u.installedVersion}',
                        style: const TextStyle(fontFamily: kMono, fontSize: 12, color: AppColors.inkFaint)),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.inkFaint),
                    const SizedBox(width: 10),
                    Text(u.latestVersion,
                        style: const TextStyle(
                            fontFamily: kMono, fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand)),
                  ]),
                ],
                if (busy) ...[
                  const SizedBox(height: 26),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: u.downloadProgress,
                      minHeight: 6,
                      backgroundColor: AppColors.line,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Downloading — $pct%',
                      style: const TextStyle(fontFamily: kMono, fontSize: 12, color: AppColors.inkMuted)),
                ],
                if (u.downloadError != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.errBg, borderRadius: BorderRadius.circular(R.thumb)),
                    child: Text(u.downloadError!,
                        style: const TextStyle(fontFamily: kSans, fontSize: 13, height: 1.5, color: AppColors.errText)),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryBtn(
                    busy ? 'Downloading…' : 'Update now',
                    onTap: busy ? null : () => context.read<UpdateService>().downloadAndInstall(),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'Android asks you to confirm the install. The first time, it also asks '
                    'you to allow installs from ClipCart — tap Settings and turn it on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: kSans, fontSize: 11.5, height: 1.45, color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
