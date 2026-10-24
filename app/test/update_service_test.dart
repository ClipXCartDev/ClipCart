import 'package:clipcart/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two ways this can go wrong are opposites and both are bad: a rule that
/// never fires leaves every client on an old build for good, and one that
/// fires too eagerly locks people out of a working app. So the comparison it
/// turns on is pinned here rather than trusted.
void main() {
  int cmp(String a, String b) => UpdateService.compareVersions(a, b);

  group('comparing versions', () {
    test('older is older, newer is newer, same is same', () {
      expect(cmp('3.0.0', '3.1.0'), lessThan(0));
      expect(cmp('3.1.0', '3.0.0'), greaterThan(0));
      expect(cmp('3.1.0', '3.1.0'), 0);
    });

    test('it compares numbers, not text', () {
      // the classic: '10' sorts before '9' as a string
      expect(cmp('3.9.0', '3.10.0'), lessThan(0));
      expect(cmp('2.0.0', '10.0.0'), lessThan(0));
    });

    test('a missing part is zero, so 3.1 and 3.1.0 are one version', () {
      expect(cmp('3.1', '3.1.0'), 0);
      expect(cmp('3', '3.0.1'), lessThan(0));
    });

    test('a build suffix does not make a version newer than itself', () {
      expect(cmp('3.1.0+7', '3.1.0'), 0);
    });

    test('nonsense in the config counts as zero rather than throwing', () {
      // A typo must not take the app down, and must not read as "newer".
      expect(cmp('', '3.1.0'), lessThan(0));
      expect(cmp('v3.1.0', '3.1.0'), 0);
      expect(() => cmp('not a version', 'also not'), returnsNormally);
    });
  });

  group('when an update is demanded', () {
    UpdateService svc({String installed = '3.0.0', String min = '', String latest = '', String? url = 'https://x/y.apk'}) {
      return UpdateService()
        ..installedVersion = installed
        ..minVersion = min
        ..latestVersion = latest
        ..apkUrl = url;
    }

    test('an older install than the floor is stopped', () {
      expect(svc(installed: '3.0.0', min: '3.1.0').required, isTrue);
    });

    test('the floor itself is allowed through', () {
      expect(svc(installed: '3.1.0', min: '3.1.0').required, isFalse);
    });

    test('a newer install than the floor is left alone', () {
      // A developer build ahead of the config must not be blocked.
      expect(svc(installed: '3.2.0', min: '3.1.0').required, isFalse);
    });

    test('no floor set means nothing is blocked', () {
      expect(svc(installed: '1.0.0', min: '').required, isFalse);
    });

    test('an unknown installed version is treated as current', () {
      // PackageInfo failing must not lock somebody out of the app.
      expect(svc(installed: '', min: '3.1.0').required, isFalse);
    });

    test('a newer version on offer is noticed without being demanded', () {
      final u = svc(installed: '3.0.0', min: '', latest: '3.1.0');
      expect(u.available, isTrue);
      expect(u.required, isFalse);
    });
  });
}
