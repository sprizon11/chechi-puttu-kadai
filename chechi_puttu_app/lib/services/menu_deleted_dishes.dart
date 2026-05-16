import 'dart:convert';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDeletedDishKeysPrefsKey = 'chechi_menu_deleted_dish_keys_v1';

/// Dishes removed from the menu (admin delete) — hidden on admin + customer Home.
class MenuDeletedDishes extends ChangeNotifier {
  MenuDeletedDishes._();
  static final MenuDeletedDishes instance = MenuDeletedDishes._();

  Set<String> _keys = {};

  Set<String> get keys => Set.unmodifiable(_keys);

  bool isDeleted(String sectionTitle, String catalogDishTitle) =>
      _keys.contains(catalogDishStorageKey(sectionTitle, catalogDishTitle));

  Future<void> reloadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(kDeletedDishKeysPrefsKey);
    if (raw == null || raw.isEmpty) {
      if (_keys.isNotEmpty) {
        _keys = {};
        notifyListeners();
      }
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _keys = list.map((e) => e as String).toSet();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistKeys() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kDeletedDishKeysPrefsKey, jsonEncode(_keys.toList()));
  }

  Future<void> _removeSnapshotForDishKey(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(kAdminDishSnapshotsPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!map.containsKey(key)) return;
      map.remove(key);
      await p.setString(kAdminDishSnapshotsPrefsKey, jsonEncode(map));
    } catch (_) {}
  }

  /// Permanently hides this catalog dish on admin + customer until keys are cleared.
  Future<void> markDeleted(String sectionTitle, String catalogDishTitle) async {
    final key = catalogDishStorageKey(sectionTitle, catalogDishTitle);
    _keys.add(key);
    await _persistKeys();
    await _removeSnapshotForDishKey(key);
    await CustomerMenuOverrides.instance.reloadFromPrefs();
    notifyListeners();
  }
}
