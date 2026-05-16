import 'dart:async';
import 'dart:convert';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  static const _customPrefix = '__custom__';

  Map<String, AdminSectionEditSnapshot> _sectionMap = {};
  List<String> _customCategories = [];
  bool _cloudSyncStarted = false;

  List<MenuCatalogSection> _sections = kCustomerMenuSections;

  List<MenuCatalogSection> get sections => _sections;

  List<String> get customCategoryIds => List.unmodifiable(_customCategories);

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
    unawaited(_ensureCloudSyncStarted());
  }

  void _rebuildSections() {
    final dishMap = CustomerMenuOverrides.instance.snapshotMapForBuild();
    _sections = buildResolvedMenuSections(
      sectionOverrides: _sectionMap,
      customCategoryIds: _customCategories,
      dishSnapshots: dishMap,
    );
  }

  Future<void> _ensureCloudSyncStarted() async {
    if (_cloudSyncStarted) return;
    _cloudSyncStarted = true;
    final root = FirebaseFirestore.instance
        .collection(_cloudCollection)
        .doc(_cloudDoc);
    root.collection(_cloudSubcollection).snapshots().listen((snap) async {
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
      final p = await SharedPreferences.getInstance();
      Map<String, AdminSectionEditSnapshot> local = {};
      final raw = p.getString(kAdminSectionOverridesPrefsKey);
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
      _sectionMap = {...local, ...out};
      await _persistLocal(_sectionMap);
      _rebuildSections();
      notifyListeners();
    }, onError: (_) {});
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

  final out = kCustomerMenuSections.map(resolveCatalog).toList();

  for (final catId in customCategoryIds) {
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
  }
  return out;
}

/// Customer Home / menu tab — resolved categories with admin edits.
List<MenuCatalogSection> get customerMenuSections =>
    CustomerMenuSectionOverrides.instance.sections;

/// Stable storage id for a section index (catalog title or custom category id).
String customerMenuSectionIdAt(int index) {
  if (index < kCustomerMenuSections.length) {
    return kCustomerMenuSections[index].title;
  }
  final customIdx = index - kCustomerMenuSections.length;
  final custom = CustomerMenuSectionOverrides.instance.customCategoryIds;
  if (customIdx >= 0 && customIdx < custom.length) return custom[customIdx];
  final sections = CustomerMenuSectionOverrides.instance.sections;
  if (index >= 0 && index < sections.length) return sections[index].title;
  return '';
}

/// Default cover images for built-in catalog categories (customer UI fallback).
const kCustomerMenuSectionDefaultImageAssets = <String>[
  'assets/images/menus/puttu.png',
  'assets/images/menus/gravies.png',
  'assets/images/menus/desserts.png',
  'assets/images/menus/signature.png',
];
