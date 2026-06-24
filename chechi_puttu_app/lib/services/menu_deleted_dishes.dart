import 'dart:async';
import 'dart:convert';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDeletedDishKeysPrefsKey = 'chechi_menu_deleted_dish_keys_v1';
const kDeletedSectionIdsPrefsKey = 'chechi_menu_deleted_section_ids_v1';

/// Dishes removed from the menu (admin delete) — hidden on admin + customer UI.
/// Synced via Firestore so all customer devices see removals.
class MenuDeletedDishes extends ChangeNotifier {
  MenuDeletedDishes._();
  static final MenuDeletedDishes instance = MenuDeletedDishes._();

  static const _cloudCollection = 'admin_public';
  static const _cloudDoc = 'menu_overrides';
  static const _cloudField = 'deletedDishKeys';
  static const _cloudDeletedSectionsField = 'deletedSectionIds';

  Set<String> _keys = {};
  Set<String> _deletedSectionIds = {};
  bool _cloudSyncStarted = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cloudSub;
  Timer? _cloudRetryTimer;

  Set<String> get keys => Set.unmodifiable(_keys);

  Set<String> get deletedSectionIds => Set.unmodifiable(_deletedSectionIds);

  bool isDeleted(String sectionTitle, String catalogDishTitle) =>
      _keys.contains(catalogDishStorageKey(sectionTitle, catalogDishTitle));

  bool isSectionDeleted(String sectionId) =>
      _deletedSectionIds.contains(sectionId);

  /// True when every catalog dish in this section is deleted (hide category on customer UI).
  bool isCatalogSectionFullyHidden(String sectionTitle) {
    if (isSectionDeleted(sectionTitle)) return true;
    for (final s in kCustomerMenuSections) {
      if (s.title != sectionTitle) continue;
      if (s.dishes.isEmpty) return true;
      return s.dishes.every((d) => isDeleted(sectionTitle, d.title));
    }
    return false;
  }

  bool sectionHasVisibleDishes(MenuCatalogSection section, String sectionId) {
    if (isSectionDeleted(sectionId)) return false;
    if (section.dishes.isEmpty) return false;
    return section.dishes.any((d) => !isDeleted(sectionId, d.title));
  }

  Future<void> reloadFromPrefs() async {
    await _loadLocal();
    unawaited(_refreshFromCloudOnce());
    unawaited(_ensureCloudSyncStarted());
  }

  /// Pushes this device's delete list to Firestore (admin menu screen on open).
  Future<void> syncLocalToCloud() => _syncToCloud();

  Future<void> _loadLocal() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(kDeletedDishKeysPrefsKey);
    if (raw == null || raw.isEmpty) {
      _applyKeys(const {}, notify: false);
    } else {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _applyKeys(list.map((e) => e.toString()).toSet(), notify: false);
      } catch (_) {}
    }
    final rawSections = p.getString(kDeletedSectionIdsPrefsKey);
    if (rawSections == null || rawSections.isEmpty) {
      _applyDeletedSections(const {}, notify: false);
    } else {
      try {
        final list = jsonDecode(rawSections) as List<dynamic>;
        _applyDeletedSections(list.map((e) => e.toString()).toSet(), notify: false);
      } catch (_) {}
    }
  }

  void _applyKeys(Set<String> next, {required bool notify}) {
    if (setEquals(_keys, next)) return;
    _keys = next;
    if (notify) notifyListeners();
  }

  void _applyDeletedSections(Set<String> next, {required bool notify}) {
    if (setEquals(_deletedSectionIds, next)) return;
    _deletedSectionIds = next;
    if (notify) notifyListeners();
  }

  Future<void> _persistKeys() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kDeletedDishKeysPrefsKey, jsonEncode(_keys.toList()));
    unawaited(_syncToCloud());
  }

  Future<void> _persistDeletedSections() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      kDeletedSectionIdsPrefsKey,
      jsonEncode(_deletedSectionIds.toList()),
    );
    unawaited(_syncToCloud());
  }

  Future<void> _syncToCloud() async {
    try {
      await chechiFirestore
          .collection(_cloudCollection)
          .doc(_cloudDoc)
          .set(
        <String, dynamic>{
          _cloudField: _keys.toList()..sort(),
          _cloudDeletedSectionsField: _deletedSectionIds.toList()..sort(),
          'deletedDishKeysUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _refreshFromCloudOnce() async {
    try {
      final snap = await chechiFirestore
          .collection(_cloudCollection)
          .doc(_cloudDoc)
          .get();
      final data = snap.data();
      final list = data?[_cloudField];
      if (list is List) {
        final cloud = list.map((e) => e.toString()).toSet();
        final merged = {..._keys, ...cloud};
        if (!setEquals(_keys, merged)) {
          _keys = merged;
          final p = await SharedPreferences.getInstance();
          await p.setString(kDeletedDishKeysPrefsKey, jsonEncode(_keys.toList()));
          notifyListeners();
        }
      }
      final sections = data?[_cloudDeletedSectionsField];
      if (sections is List) {
        final cloudSections = sections.map((e) => e.toString()).toSet();
        if (!setEquals(_deletedSectionIds, cloudSections)) {
          _deletedSectionIds = cloudSections;
          final p = await SharedPreferences.getInstance();
          await p.setString(
            kDeletedSectionIdsPrefsKey,
            jsonEncode(_deletedSectionIds.toList()),
          );
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureCloudSyncStarted() async {
    if (_cloudSyncStarted) return;
    _cloudSyncStarted = true;
    _cloudRetryTimer?.cancel();
    _cloudSub?.cancel();
    _cloudSub = chechiFirestore
        .collection(_cloudCollection)
        .doc(_cloudDoc)
        .snapshots()
        .listen((snap) async {
      final data = snap.data();
      var changed = false;
      final list = data?[_cloudField];
      if (list is List) {
        final cloud = list.map((e) => e.toString()).toSet();
        if (!setEquals(_keys, cloud)) {
          _keys = cloud;
          changed = true;
        }
      }
      final sections = data?[_cloudDeletedSectionsField];
      if (sections is List) {
        final cloudSections = sections.map((e) => e.toString()).toSet();
        if (!setEquals(_deletedSectionIds, cloudSections)) {
          _deletedSectionIds = cloudSections;
          changed = true;
        }
      }
      if (!changed) return;
      final p = await SharedPreferences.getInstance();
      await p.setString(kDeletedDishKeysPrefsKey, jsonEncode(_keys.toList()));
      await p.setString(
        kDeletedSectionIdsPrefsKey,
        jsonEncode(_deletedSectionIds.toList()),
      );
      notifyListeners();
    }, onError: (_) {
      _scheduleCloudResubscribe();
    }, onDone: () {
      _scheduleCloudResubscribe();
    });
  }

  void _scheduleCloudResubscribe() {
    _cloudSub?.cancel();
    _cloudSub = null;
    _cloudSyncStarted = false;
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_ensureCloudSyncStarted());
    });
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
    if (!_keys.add(key)) return;
    await _persistKeys();
    await _removeSnapshotForDishKey(key);
    notifyListeners();
  }

  /// Hides every catalog dish in a section (used when admin deletes a category).
  Future<void> markAllCatalogDishesDeleted(
    String sectionTitle,
    Iterable<String> catalogDishTitles,
  ) async {
    var changed = false;
    for (final title in catalogDishTitles) {
      final key = catalogDishStorageKey(sectionTitle, title);
      if (_keys.add(key)) changed = true;
      await _removeSnapshotForDishKey(key);
    }
    if (!changed) return;
    await _persistKeys();
    notifyListeners();
  }

  /// Permanently hides a whole menu category on admin + customer (synced via cloud).
  Future<void> markSectionDeleted(String sectionId) async {
    if (!_deletedSectionIds.add(sectionId)) return;
    await _persistDeletedSections();
    notifyListeners();
  }
}
