import 'package:chechi_puttu_app/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateInfo.needFor', () {
    const info = AppUpdateInfo(latestBuild: 60, minBuild: 55);

    test('up to date phones see nothing', () {
      expect(info.needFor(60), AppUpdateNeed.none);
      expect(info.needFor(61), AppUpdateNeed.none);
    });

    test('older than latest is asked, may skip', () {
      expect(info.needFor(59), AppUpdateNeed.optional);
      expect(info.needFor(55), AppUpdateNeed.optional);
    });

    test('older than minimum must update', () {
      expect(info.needFor(54), AppUpdateNeed.required);
    });

    test('no doc, or unknown build, never prompts', () {
      expect(AppUpdateInfo.none.needFor(10), AppUpdateNeed.none);
      expect(info.needFor(0), AppUpdateNeed.none);
    });
  });

  group('AppUpdateInfo.fromMap', () {
    test('reads numbers stored as numbers or strings', () {
      final info = AppUpdateInfo.fromMap({
        'latest_build': '61',
        'min_build': 58.0,
        'message': 'New payment fix',
      });
      expect(info.latestBuild, 61);
      expect(info.minBuild, 58);
      expect(info.displayMessage, 'New payment fix');
    });

    test('falls back to the default message and Play Store link', () {
      final info = AppUpdateInfo.fromMap({'latest_build': 61});
      expect(info.displayMessage, AppUpdateInfo.defaultMessage);
      expect(info.storeUrl(isAndroid: true), AppUpdateInfo.playStoreUrl);
      expect(info.storeUrl(isAndroid: false), '');
    });
  });
}
