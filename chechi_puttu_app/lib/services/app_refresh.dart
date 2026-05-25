import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:chechi_puttu_app/services/customer_menu_section_overrides.dart';
import 'package:chechi_puttu_app/services/menu_deleted_dishes.dart';

/// Central refresh actions for pull-to-refresh across the app.
class AppRefresh {
  AppRefresh._();

  static const _minVisible = Duration(milliseconds: 180);

  /// Reload menu overrides from local storage + Firestore listeners.
  static Future<void> refreshMenuData() async {
    await Future.wait([
      CustomerMenuOverrides.instance.reloadFromPrefs(),
      CustomerMenuSectionOverrides.instance.reloadFromPrefs(),
      MenuDeletedDishes.instance.reloadFromPrefs(),
    ]);
  }

  /// Same as [refreshMenuData] — used on admin screens.
  static Future<void> refreshAdminMenuData() => refreshMenuData();

  /// Ensures the refresh indicator is visible long enough to feel responsive.
  static Future<void> run(Future<void> Function() action) async {
    final started = DateTime.now();
    await action();
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minVisible) {
      await Future<void>.delayed(_minVisible - elapsed);
    }
  }
}
