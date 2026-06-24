import 'dart:async';
import 'dart:convert';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:chechi_puttu_app/services/menu_deleted_dishes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kAdminCustomCategoriesPrefsKey = 'chechi_admin_custom_categories_v1';

/// Resolves customer-facing menu categories (built-in + custom) with admin edits.
class CustomerMenuSectionOverrides extends ChangeNotifier {
  CustomerMenuSectionOverrides._();
  static final CustomerMenuSectionOverrides instance =
      CustomerMenuSectionOverrides._();

  static const _cloudCollection = 'admin_public';
  static const _cloudDoc = 'menu_overrides';
  static const _cloudSubcollection = 'section_snapshots';
  static const _cloudCustomCategoriesField = 'customCategoryIds';

  Map<String, AdminSectionEditSnapshot> _sectionMap = {};
  List<String> _customCategories = [];
  List<String> _sectionIds = [];
  bool _cloudSyncStarted = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cloudSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _menuDocSub;
  Timer? _cloudRetryTimer;

  List<MenuCatalogSection> _sections = kCustomerMenuSections;

  List<MenuCatalogSection> get sections => _sections;

  List<String> get customCategoryIds => List.unmodifiable(_customCategories);

  String sectionIdAt(int index) {
    if (index >= 0 && index < _sectionIds.length) return _sectionIds[index];
    return '';
  }

  AdminSectionEditSnapshot? sectionOverrideFor(String sectionId) {
    return _sectionMap[adminSectionStorageKey(sectionId)];
  }

  /// Rebuild custom-category dishes after dish override changes.
  void rebuildFromDishOverrides() {
    _rebuildSections();
    notifyListeners();
  }

  Future<void> reloadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final custom =
        p.getStringList(kAdminCustomCategoriesPrefsKey) ?? const <String>[];
    _customCategories = custom
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final raw = p.getString(kAdminSectionOverridesPrefsKey);
    final local = <String, AdminSectionEditSnapshot>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          final v = e.value;
          if (v is! Map<String, dynamic>) continue;
          local[e.key] = AdminSectionEditSnapshot.fromJson(v);
        }
      } catch (_) {}
    }
    _sectionMap = local;
    _rebuildSections();
    notifyListeners();
    unawaited(_refreshFromCloudOnce());
    unawaited(_refreshMenuOverridesDocOnce());
    unawaited(_ensureCloudSyncStarted());
  }

  /// Admin: save custom categories locally + push to Firestore for all devices.
  Future<void> setCustomCategoriesAndSync(List<String> ids) async {
    _customCategories = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(kAdminCustomCategoriesPrefsKey, _customCategories);
    await _syncCustomCategoriesToCloud();
    _rebuildSections();
    notifyListeners();
  }

  Future<void> _syncCustomCategoriesToCloud() async {
    try {
      await chechiFirestore
          .collection(_cloudCollection)
          .doc(_cloudDoc)
          .set(
        <String, dynamic>{
          _cloudCustomCategoriesField: _customCategories,
          'customCategoryIdsUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _refreshMenuOverridesDocOnce() async {
    try {
      final snap = await chechiFirestore
          .collection(_cloudCollection)
          .doc(_cloudDoc)
          .get();
      await _applyMenuOverridesDoc(snap.data());
    } catch (_) {}
  }

  Future<void> _applyMenuOverridesDoc(Map<String, dynamic>? data) async {
    if (data == null) return;
    final list = data[_cloudCustomCategoriesField];
    if (list is! List) return;
    final next = list
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (listEquals(_customCategories, next)) return;
    _customCategories = next;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(kAdminCustomCategoriesPrefsKey, _customCategories);
    _rebuildSections();
    notifyListeners();
  }

  Future<void> _refreshFromCloudOnce() async {
    final cloud = await _readCloudSectionOverridesOnce();
    if (cloud == null) return;
    _sectionMap = Map<String, AdminSectionEditSnapshot>.from(cloud);
    _rebuildSections();
    notifyListeners();
    await _persistLocal(_sectionMap);
  }

  Future<Map<String, AdminSectionEditSnapshot>?> _readCloudSectionOverridesOnce() async {
    try {
      final root = chechiFirestore
          .collection(_cloudCollection)
          .doc(_cloudDoc);
      final snapDocs = await root.collection(_cloudSubcollection).get();
      final out = <String, AdminSectionEditSnapshot>{};
      for (final d in snapDocs.docs) {
        final m = d.data();
        final key = (m['key'] as String?)?.trim();
        final data = m['data'];
        if (key == null || key.isEmpty || data is! Map) continue;
        out[key] = AdminSectionEditSnapshot.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  void _rebuildSections() {
    final dishMap = CustomerMenuOverrides.instance.snapshotMapForBuild();
    final built = buildResolvedMenuSectionsWithIds(
      sectionOverrides: _sectionMap,
      customCategoryIds: _customCategories,
      dishSnapshots: dishMap,
      deletedDishKeys: MenuDeletedDishes.instance.keys,
      deletedSectionIds: MenuDeletedDishes.instance.deletedSectionIds,
    );
    _sections = built.sections;
    _sectionIds = built.sectionIds;
  }

  Future<void> _ensureCloudSyncStarted() async {
    if (_cloudSyncStarted) return;
    _cloudSyncStarted = true;
    _cloudRetryTimer?.cancel();
    final root = chechiFirestore
        .collection(_cloudCollection)
        .doc(_cloudDoc);
    _cloudSub?.cancel();
    _cloudSub = root.collection(_cloudSubcollection).snapshots().listen((snap) async {
      final out = <String, AdminSectionEditSnapshot>{};
      for (final d in snap.docs) {
        final m = d.data();
        final key = (m['key'] as String?)?.trim();
        final data = m['data'];
        if (key == null || key.isEmpty || data is! Map) continue;
        out[key] = AdminSectionEditSnapshot.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
      _sectionMap = Map<String, AdminSectionEditSnapshot>.from(out);
      await _persistLocal(_sectionMap);
      _rebuildSections();
      notifyListeners();
    }, onError: (_) {
      _scheduleCloudResubscribe();
    }, onDone: () {
      _scheduleCloudResubscribe();
    });

    _menuDocSub?.cancel();
    _menuDocSub = root.snapshots().listen((snap) async {
      await _applyMenuOverridesDoc(snap.data());
    }, onError: (_) {
      _scheduleCloudResubscribe();
    }, onDone: () {
      _scheduleCloudResubscribe();
    });
  }

  void _scheduleCloudResubscribe() {
    _cloudSub?.cancel();
    _cloudSub = null;
    _menuDocSub?.cancel();
    _menuDocSub = null;
    _cloudSyncStarted = false;
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_ensureCloudSyncStarted());
    });
  }

  Future<void> _persistLocal(
    Map<String, AdminSectionEditSnapshot> snapshots,
  ) async {
    final p = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    snapshots.forEach((k, v) => out[k] = v.toJson());
    await p.setString(kAdminSectionOverridesPrefsKey, jsonEncode(out));
  }
}

/// Builds the full customer menu section list (catalog + custom categories).
List<MenuCatalogSection> buildResolvedMenuSections({
  required Map<String, AdminSectionEditSnapshot> sectionOverrides,
  required List<String> customCategoryIds,
  required Map<String, AdminDishEditSnapshot> dishSnapshots,
  Set<String> deletedDishKeys = const {},
  Set<String> deletedSectionIds = const {},
}) {
  return buildResolvedMenuSectionsWithIds(
    sectionOverrides: sectionOverrides,
    customCategoryIds: customCategoryIds,
    dishSnapshots: dishSnapshots,
    deletedDishKeys: deletedDishKeys,
    deletedSectionIds: deletedSectionIds,
  ).sections;
}

({List<MenuCatalogSection> sections, List<String> sectionIds})
    buildResolvedMenuSectionsWithIds({
  required Map<String, AdminSectionEditSnapshot> sectionOverrides,
  required List<String> customCategoryIds,
  required Map<String, AdminDishEditSnapshot> dishSnapshots,
  Set<String> deletedDishKeys = const {},
  Set<String> deletedSectionIds = const {},
}) {
  const customPrefix = '__custom__';

  MenuCatalogSection resolveCatalog(MenuCatalogSection s) {
    final saved = sectionOverrides[adminSectionStorageKey(s.title)];
    final merged = mergeSectionWithCatalog(s, saved);
    return MenuCatalogSection(
      title: merged.title,
      subtitle: merged.subtitle,
      dishes: s.dishes,
    );
  }

  final out = <MenuCatalogSection>[];
  final ids = <String>[];

  for (final s in kCustomerMenuSections) {
    if (deletedSectionIds.contains(s.title)) continue;
    if (!s.dishes.any(
      (d) => !deletedDishKeys.contains(
        catalogDishStorageKey(s.title, d.title),
      ),
    )) {
      continue;
    }
    out.add(resolveCatalog(s));
    ids.add(s.title);
  }

  for (final catId in customCategoryIds) {
    if (deletedSectionIds.contains(catId)) continue;
    final prefix = '$customPrefix$catId\u001f';
    final dishes = <MenuCatalogDish>[];
    for (final e in dishSnapshots.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final snap = e.value;
      if (!snap.available) continue;
      if (snap.title.trim().isEmpty) continue;
      dishes.add(
        MenuCatalogDish(
          snap.title,
          snap.subtitle,
          snap.price,
          badge: snap.badge,
        ),
      );
    }
    if (dishes.isEmpty) continue;
    final base = MenuCatalogSection(
      title: catId,
      subtitle: 'Chef curated picks',
      dishes: const [],
    );
    final saved = sectionOverrides[adminSectionStorageKey(catId)];
    final merged = mergeSectionWithCatalog(base, saved);
    out.add(
      MenuCatalogSection(
        title: merged.title,
        subtitle: merged.subtitle,
        dishes: dishes,
      ),
    );
    ids.add(catId);
  }
  return (sections: out, sectionIds: ids);
}

/// Customer Home / menu tab — resolved categories with admin edits.
List<MenuCatalogSection> get customerMenuSections =>
    CustomerMenuSectionOverrides.instance.sections;

/// Section indices that still have at least one visible dish.
List<int> customerVisibleMenuSectionIndices() {
  final sections = customerMenuSections;
  final out = <int>[];
  for (var i = 0; i < sections.length; i++) {
    final id = customerMenuSectionIdAt(i);
    if (MenuDeletedDishes.instance.sectionHasVisibleDishes(sections[i], id)) {
      out.add(i);
    }
  }
  return out;
}

/// Stable storage id for a section index (catalog title or custom category id).
String customerMenuSectionIdAt(int index) =>
    CustomerMenuSectionOverrides.instance.sectionIdAt(index);

/// Default cover images for built-in catalog categories (customer UI fallback).
const kCustomerMenuSectionDefaultImageAssets = <String>[
  'assets/images/menus/puttu.png',
  'assets/images/menus/gravies.png',
  'assets/images/menus/desserts.png',
  'assets/images/menus/signature.png',
  'assets/images/offer.png',
];

/// Cover image for a menu category card (stable per catalog title).
String? menuSectionFallbackAsset(String sectionId) {
  final catalogIdx =
      kCustomerMenuSections.indexWhere((s) => s.title == sectionId);
  if (catalogIdx >= 0 &&
      catalogIdx < kCustomerMenuSectionDefaultImageAssets.length) {
    return kCustomerMenuSectionDefaultImageAssets[catalogIdx];
  }
  return 'assets/images/offer.png';
}
