import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/runtime_config.dart';

/// Keeps the installed app at or above the build the server says is current.
///
/// There is no app store in the loop: the APK is handed out directly, so
/// without this a client stays on whatever build they were sent and every
/// later fix has to be re-sent by hand, with no way to know whether they
/// installed it. Shipping is now: put the APK where the config points and
/// raise `min_build`.
///
/// The check is deliberately cheap and failure-tolerant — it reads numbers the
/// config already carries, and if anything is missing or unreachable the app
/// starts normally. An update mechanism that can lock people out of a working
/// app when a config is briefly wrong is worse than no update mechanism.
class UpdateService extends ChangeNotifier {
  UpdateService();

  /// The version running right now, from the package itself rather than a
  /// constant somebody has to remember to bump twice.
  String installedVersion = '';

  /// Shown beside the version; NOT what the comparison uses. A split-per-ABI
  /// release offsets the Android version code by its architecture (arm64
  /// build 2 ships as 2002), so build numbers are not comparable across the
  /// APKs of one release and a rule written against them would either never
  /// fire or lock out one architecture.
  int installedBuild = 0;

  /// What the server says, '' until the config has been read.
  String latestVersion = '';

  /// The oldest version still allowed to run. Equal to [latestVersion] means
  /// everyone older must update before they can carry on.
  String minVersion = '';

  String? apkUrl;
  String notes = '';

  /// 0..1 while the APK is downloading, null when it is not.
  double? downloadProgress;
  String? downloadError;

  bool get required =>
      minVersion.isNotEmpty &&
      installedVersion.isNotEmpty &&
      compareVersions(installedVersion, minVersion) < 0;

  bool get available =>
      latestVersion.isNotEmpty &&
      installedVersion.isNotEmpty &&
      compareVersions(installedVersion, latestVersion) < 0;

  /// Compare two dotted version strings: negative when [a] is older.
  ///
  /// Missing parts count as zero, so 3.1 and 3.1.0 are the same version, and
  /// anything unparsable in a part counts as zero rather than throwing - a
  /// typo in the config must not take the app down.
  static int compareVersions(String a, String b) {
    // Build metadata and pre-release tags are dropped before comparing, the
    // way semver orders versions: a '+7' on the end is a different build of
    // the SAME version, and letting it read as newer would walk an install
    // straight past the floor it was supposed to be stopped at.
    List<int> parts(String v) => v
        .trim()
        .split(RegExp(r'[+-]'))
        .first
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final l = i < x.length ? x[i] : 0;
      final r = i < y.length ? y[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      installedBuild = int.tryParse(info.buildNumber) ?? 0;
      installedVersion = info.version;
    } catch (_) {/* an unknown build is treated as current, not as outdated */}

    latestVersion = RuntimeConfig.get<String>('latest_version', '');
    minVersion = RuntimeConfig.get<String>('min_version', '');
    notes = RuntimeConfig.get<String>('update_notes', '');
    apkUrl = await _apkUrlForThisDevice();

    // A config that demands a build it does not say where to get is a config
    // that locks the app shut. Treat it as no requirement at all.
    if (apkUrl == null) minVersion = '';
    notifyListeners();
  }

  /// Which APK this phone can actually install.
  ///
  /// A release is split per architecture - one universal APK carrying every
  /// ABI is well over 200 MB, which is not something to push down a phone
  /// line. So the config names one build per architecture and the device
  /// picks; handing a 64-bit build to a 32-bit phone produces an install that
  /// simply fails, with nothing on screen to say why.
  Future<String?> _apkUrlForThisDevice() async {
    final arm64 = RuntimeConfig.get<String>('apk_url', '');
    final arm32 = RuntimeConfig.get<String>('apk_url_arm32', '');
    if (!Platform.isAndroid) return arm64.isEmpty ? null : arm64;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis.map((a) => a.toLowerCase()).toList();
      final is64 = abis.any((a) => a.contains('arm64') || a.contains('x86_64'));
      if (!is64) return arm32.isEmpty ? null : arm32;
    } catch (_) {/* unknown architecture: the 64-bit build covers most phones */}
    return arm64.isEmpty ? null : arm64;
  }

  /// Fetch the APK and hand it to the system installer.
  ///
  /// Android shows its own confirmation — this cannot install anything behind
  /// the user's back, and it does not try to.
  Future<void> downloadAndInstall() async {
    final url = apkUrl;
    if (url == null || downloadProgress != null) return;
    downloadError = null;
    downloadProgress = 0;
    notifyListeners();
    try {
      final dir = await getTemporaryDirectory();
      // A fixed name, so a retry overwrites instead of filling the cache with
      // half-downloaded copies.
      final path = '${dir.path}/clipcart-update.apk';
      final f = File(path);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {/* overwritten below anyway */}
      }
      await Dio().download(
        url,
        path,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (got, total) {
          if (total > 0) {
            downloadProgress = got / total;
            notifyListeners();
          }
        },
      );
      downloadProgress = 1;
      notifyListeners();
      final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        downloadError = 'Could not open the installer. Open the file from Downloads to finish.';
      }
    } catch (e) {
      debugPrint('[update] $e');
      downloadError = 'The download did not finish. Check your connection and try again.';
    } finally {
      downloadProgress = null;
      notifyListeners();
    }
  }
}
