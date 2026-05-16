import 'dart:convert';

import 'package:chechi_puttu_app/admin/admin_category_edit_screen.dart';
import 'package:chechi_puttu_app/admin/admin_dish_edit_screen.dart';
import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:chechi_puttu_app/services/customer_menu_section_overrides.dart';
import 'package:chechi_puttu_app/services/menu_deleted_dishes.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menu Management tab body (used inside [AdminDashboardScreen]).
/// Lists the same dishes as the customer home menu ([kCustomerMenuSections]).
class AdminMenuManagementBody extends StatefulWidget {
  const AdminMenuManagementBody({super.key});

  @override
  State<AdminMenuManagementBody> createState() =>
      _AdminMenuManagementBodyState();
}

class _AdminMenuManagementBodyState extends State<AdminMenuManagementBody> {
  static const _maroon = Color(0xFF5D1F1A);
  static const _muted = Color(0xFF7A6A62);
  static const _tabSelectedBg = Color(0xFFFFE8EE);
  static const _orange = Color(0xFFEA7A2C);
  static const _customPrefix = '__custom__';

  final TextEditingController _searchCtrl = TextEditingController();

  static const _prefsSnapshotsKey = kAdminDishSnapshotsPrefsKey;
  static const _prefsSectionScheduleKey = 'chechi_menu_section_schedule_v1';
  static const _cloudMenuOverridesCollection = 'admin_public';
  static const _cloudMenuOverridesDoc = 'menu_overrides';
  static const _cloudSnapshotsSubcollection = 'snapshots';
  static const _cloudSectionSnapshotsSubcollection = 'section_snapshots';

  final Map<String, AdminDishEditSnapshot> _snapshots = {};
  final Map<String, AdminSectionEditSnapshot> _sectionSnapshots = {};
  final List<String> _customCategories = [];
  final Map<String, ({int startHour, int endHour})> _sectionSchedules = {};

  int _categoryIndex = 0;
  String _sortBy = 'Name';

  static const _baseCategories = <({IconData icon, String label})>[
    (icon: Icons.grid_view_rounded, label: 'All Items'),
    (icon: Icons.breakfast_dining_rounded, label: 'Puttu'),
    (icon: Icons.soup_kitchen_outlined, label: 'Gravies & Curries'),
    (icon: Icons.icecream_outlined, label: 'Desserts'),
    (icon: Icons.star_outline_rounded, label: 'Our Signature Dishes'),
  ];

  List<({IconData icon, String label})> get _categories => [
    _baseCategories.first,
    ...kCustomerMenuSections.map((s) {
      final t = _thumbForSection(s.title);
      return (icon: t.icon, label: _displayLabelForSectionId(s.title));
    }),
    ..._customCategories.map(
      (c) => (icon: Icons.category_outlined, label: _displayLabelForSectionId(c)),
    ),
  ];

  MenuCatalogSection? _catalogSectionForId(String sectionId) {
    for (final s in kCustomerMenuSections) {
      if (s.title == sectionId) return s;
    }
    return null;
  }

  String _displayLabelForSectionId(String sectionId) {
    final catalog = _catalogSectionForId(sectionId);
    if (catalog != null) {
      return mergeSectionWithCatalog(
        catalog,
        _sectionSnapshots[adminSectionStorageKey(sectionId)],
      ).title;
    }
    final saved = _sectionSnapshots[adminSectionStorageKey(sectionId)];
    if (saved != null && saved.title.trim().isNotEmpty) return saved.title.trim();
    return sectionId;
  }

  AdminSectionEditSnapshot _mergedSection(String sectionId) {
    final catalog = _catalogSectionForId(sectionId);
    if (catalog != null) {
      return mergeSectionWithCatalog(
        catalog,
        _sectionSnapshots[adminSectionStorageKey(sectionId)],
      );
    }
    return _sectionSnapshots[adminSectionStorageKey(sectionId)] ??
        AdminSectionEditSnapshot(
          title: sectionId,
          subtitle: 'Chef curated picks',
        );
  }

  String? _sectionTitleForChip(int chipIndex) {
    return _sectionIdForChip(chipIndex);
  }

  String? _sectionIdForChip(int chipIndex) {
    if (chipIndex <= 0) return null;
    final idx = chipIndex - 1;
    if (idx < kCustomerMenuSections.length) {
      return kCustomerMenuSections[idx].title;
    }
    final customIdx = idx - kCustomerMenuSections.length;
    if (customIdx >= 0 && customIdx < _customCategories.length) {
      return _customCategories[customIdx];
    }
    return null;
  }

  bool _isCustomSectionId(String sectionId) =>
      !_baseCatalogSectionIds.contains(sectionId);

  Set<String> get _baseCatalogSectionIds =>
      kCustomerMenuSections.map((s) => s.title).toSet();

  ({IconData icon, Color tint}) _thumbForSection(String sectionTitle) {
    switch (sectionTitle) {
      case 'Puttu':
        return (
          icon: Icons.breakfast_dining_rounded,
          tint: const Color(0xFFFFF0E6),
        );
      case 'Gravies & Curries':
        return (
          icon: Icons.soup_kitchen_outlined,
          tint: const Color(0xFFE8F5E9),
        );
      case 'Desserts':
        return (
          icon: Icons.icecream_outlined,
          tint: const Color(0xFFF3E5F5),
        );
      case 'Our Signature Dishes':
        return (
          icon: Icons.star_outline_rounded,
          tint: const Color(0xFFFFECB3),
        );
      default:
        return (
          icon: Icons.restaurant_rounded,
          tint: const Color(0xFFFFF8E1),
        );
    }
  }

  AdminDishEditSnapshot _merged(
    String sectionTitle,
    MenuCatalogDish dish,
  ) {
    final key = adminDishStorageKey(sectionTitle, dish.title);
    return mergeWithCatalog(dish, _snapshots[key]);
  }

  String _customKey(String sectionTitle, String id) =>
      '$_customPrefix$sectionTitle\u001f$id';

  bool _isCustomKey(String key) => key.startsWith(_customPrefix);

  String _customSectionFromKey(String key) {
    final body = key.substring(_customPrefix.length);
    final idx = body.indexOf('\u001f');
    if (idx <= 0) return '';
    return body.substring(0, idx);
  }

  Future<void> _onPullToRefresh() async {
    await _loadCustomCategories();
    await _loadSectionSchedules();
    await _loadSectionOverrides();
    await _loadSnapshots();
    if (mounted) setState(() {});
  }

  Future<void> _loadSnapshots() async {
    final local = await _readLocalSnapshots();
    final cloud = await _readCloudSnapshots();
    final merged = <String, AdminDishEditSnapshot>{...local, ...cloud};
    if (!mounted) return;
    setState(() {
      _snapshots
        ..clear()
        ..addAll(merged);
    });
    if (merged.isNotEmpty) {
      await _persistSnapshots();
    }
    await CustomerMenuOverrides.instance.reloadFromPrefs();
  }

  Future<void> _persistSnapshots() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    _snapshots.forEach((k, v) => out[k] = v.toJson());
    await p.setString(_prefsSnapshotsKey, jsonEncode(out));
    await _syncSnapshotsToCloud(out);
  }

  Future<Map<String, AdminDishEditSnapshot>> _readLocalSnapshots() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsSnapshotsKey);
    if (raw == null || raw.isEmpty) return <String, AdminDishEditSnapshot>{};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, AdminDishEditSnapshot>{};
      for (final e in map.entries) {
        final v = e.value;
        if (v is! Map<String, dynamic>) continue;
        out[e.key] = AdminDishEditSnapshot.fromJson(v);
      }
      return out;
    } catch (_) {
      return <String, AdminDishEditSnapshot>{};
    }
  }

  Future<Map<String, AdminDishEditSnapshot>> _readCloudSnapshots() async {
    try {
      final root = FirebaseFirestore.instance
          .collection(_cloudMenuOverridesCollection)
          .doc(_cloudMenuOverridesDoc);
      final snapDocs = await root.collection(_cloudSnapshotsSubcollection).get();
      final out = <String, AdminDishEditSnapshot>{};
      for (final d in snapDocs.docs) {
        final m = d.data();
        final key = (m['key'] as String?)?.trim();
        final data = m['data'];
        if (key == null || key.isEmpty || data is! Map) continue;
        out[key] = AdminDishEditSnapshot.fromJson(Map<String, dynamic>.from(data));
      }
      if (out.isNotEmpty) return out;
      // Backward-compatible fallback for legacy single-document map.
      final legacyDoc = await root.get();
      final raw = legacyDoc.data()?['snapshots'];
      if (raw is! Map) return <String, AdminDishEditSnapshot>{};
      for (final e in raw.entries) {
        final key = e.key.toString();
        final val = e.value;
        if (val is! Map) continue;
        out[key] = AdminDishEditSnapshot.fromJson(Map<String, dynamic>.from(val));
      }
      return out;
    } catch (_) {
      return <String, AdminDishEditSnapshot>{};
    }
  }

  Future<void> _syncSnapshotsToCloud(Map<String, dynamic> snapshotsJson) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final root = firestore
          .collection(_cloudMenuOverridesCollection)
          .doc(_cloudMenuOverridesDoc);
      await root.set({
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final snapsColl = root.collection(_cloudSnapshotsSubcollection);
      final existing = await snapsColl.get();
      final keepIds = <String>{};
      final failedKeys = <String>[];

      for (final e in snapshotsJson.entries) {
        final key = e.key;
        final val = e.value;
        if (val is! Map) continue;
        final docId = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
        keepIds.add(docId);
        final data = Map<String, dynamic>.from(val);
        final img = data['imageBase64'];
        if (img is String && img.length > 780000) {
          // Skip only this dish image payload if too large for Firestore doc size.
          // Admin can re-upload a smaller compressed image.
          failedKeys.add(key);
          continue;
        }
        try {
          await snapsColl.doc(docId).set({
            'key': key,
            'data': data,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {
          // Continue syncing remaining dishes even if one image is too large.
          failedKeys.add(key);
        }
      }
      WriteBatch batch = firestore.batch();
      var ops = 0;
      for (final d in existing.docs) {
        if (keepIds.contains(d.id)) continue;
        batch.delete(d.reference);
        ops++;
      }
      if (ops > 0) {
        await batch.commit();
      }
      if (mounted && failedKeys.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${failedKeys.length} dish image(s) are too large for cloud sync. '
              'Please re-upload those images from admin.',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    } catch (_) {
      // Keep local save as source of truth when offline/network fails.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cloud sync failed. Check internet and Firestore rules.',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadSectionOverrides() async {
    final p = await SharedPreferences.getInstance();
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
    final cloud = await _readCloudSectionOverrides();
    if (!mounted) return;
    setState(() {
      _sectionSnapshots
        ..clear()
        ..addAll({...local, ...cloud});
    });
    if (_sectionSnapshots.isNotEmpty) {
      final p = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      _sectionSnapshots.forEach((k, v) => out[k] = v.toJson());
      await p.setString(kAdminSectionOverridesPrefsKey, jsonEncode(out));
    }
    await CustomerMenuSectionOverrides.instance.reloadFromPrefs();
  }

  Future<Map<String, AdminSectionEditSnapshot>> _readCloudSectionOverrides() async {
    try {
      final root = FirebaseFirestore.instance
          .collection(_cloudMenuOverridesCollection)
          .doc(_cloudMenuOverridesDoc);
      final snapDocs =
          await root.collection(_cloudSectionSnapshotsSubcollection).get();
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
      return <String, AdminSectionEditSnapshot>{};
    }
  }

  Future<void> _persistSectionOverrides({bool syncCloud = true}) async {
    final p = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    _sectionSnapshots.forEach((k, v) => out[k] = v.toJson());
    await p.setString(kAdminSectionOverridesPrefsKey, jsonEncode(out));
    if (syncCloud) {
      await _syncSectionOverridesToCloud(out);
    }
  }

  String _cloudSyncErrorMessage(Object e, {required String label}) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return '$label denied. Sign in as admin and deploy Firestore rules '
            '(section_snapshots).';
      }
      if (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'network-request-failed') {
        return '$label failed. Check your internet connection.';
      }
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty) {
        return '$label failed: $msg';
      }
      return '$label failed (${e.code}).';
    }
    return '$label failed. Check internet and Firestore rules.';
  }

  Future<bool> _syncSectionOverridesToCloud(Map<String, dynamic> json) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final root = firestore
          .collection(_cloudMenuOverridesCollection)
          .doc(_cloudMenuOverridesDoc);
      await root.set({
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final coll = root.collection(_cloudSectionSnapshotsSubcollection);
      final existing = await coll.get();
      final keepIds = <String>{};
      final failed = <String>[];

      for (final e in json.entries) {
        final key = e.key;
        final val = e.value;
        if (val is! Map) continue;
        final docId = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
        keepIds.add(docId);
        final data = Map<String, dynamic>.from(val);
        final img = data['imageBase64'];
        if (img is String && img.length > 780000) {
          failed.add(key);
          continue;
        }
        try {
          await coll.doc(docId).set({
            'key': key,
            'data': data,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {
          failed.add(key);
        }
      }
      try {
        WriteBatch batch = firestore.batch();
        var ops = 0;
        for (final d in existing.docs) {
          if (keepIds.contains(d.id)) continue;
          batch.delete(d.reference);
          ops++;
        }
        if (ops > 0) await batch.commit();
      } catch (_) {
        // Uploads succeeded; stale cloud docs are harmless.
      }
      if (mounted && failed.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${failed.length} category image(s) too large for cloud sync. '
              'Use a smaller photo (under ~250 KB).',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
      return failed.isEmpty;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _cloudSyncErrorMessage(
                e,
                label: 'Category cloud sync',
              ),
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _migrateSectionId(String oldId, String newId) async {
    if (oldId == newId) return;
    final idx = _customCategories.indexOf(oldId);
    if (idx >= 0) _customCategories[idx] = newId;

    final sched = _sectionSchedules.remove(oldId);
    if (sched != null) _sectionSchedules[newId] = sched;

    final oldKey = adminSectionStorageKey(oldId);
    final snap = _sectionSnapshots.remove(oldKey);
    if (snap != null) {
      _sectionSnapshots[adminSectionStorageKey(newId)] = snap;
    }

    final prefix = '$_customPrefix$oldId\u001f';
    final keysToMove =
        _snapshots.keys.where((k) => k.startsWith(prefix)).toList(growable: false);
    for (final k in keysToMove) {
      final v = _snapshots.remove(k)!;
      final newK = k.replaceFirst(prefix, '$_customPrefix$newId\u001f');
      _snapshots[newK] = v;
    }
    await _persistCustomCategories();
    await _persistSectionSchedules();
  }

  Future<void> _openCategoryEditor(String sectionId) async {
    final isCustom = _isCustomSectionId(sectionId);
    final initial = _mergedSection(sectionId);
    final result = await Navigator.of(context).push<AdminCategorySaveResult>(
      MaterialPageRoute(
        builder: (ctx) => AdminCategoryEditScreen(
          sectionId: sectionId,
          initial: initial,
          isCustomCategory: isCustom,
        ),
      ),
    );
    if (!mounted || result == null) return;

    var effectiveId = sectionId;
    if (result.renamedSectionId != null &&
        result.renamedSectionId!.trim().isNotEmpty &&
        result.renamedSectionId != sectionId) {
      await _migrateSectionId(sectionId, result.renamedSectionId!.trim());
      effectiveId = result.renamedSectionId!.trim();
    }

    setState(() {
      _sectionSnapshots[adminSectionStorageKey(effectiveId)] = result.snapshot;
    });
    await _persistSectionOverrides(syncCloud: false);
    final storageKey = adminSectionStorageKey(effectiveId);
    final cloudOk = await _syncSectionOverridesToCloud({
      storageKey: result.snapshot.toJson(),
    });
    await CustomerMenuSectionOverrides.instance.reloadFromPrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cloudOk
              ? 'Category updated and synced.'
              : 'Category saved on this device. Cloud sync did not complete.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<void> _loadCustomCategories() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(kAdminCustomCategoriesPrefsKey) ?? const [];
    if (!mounted) return;
    setState(() {
      _customCategories
        ..clear()
        ..addAll(
          list
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList(),
        );
    });
  }

  Future<void> _persistCustomCategories() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(kAdminCustomCategoriesPrefsKey, _customCategories);
    await CustomerMenuSectionOverrides.instance.reloadFromPrefs();
  }

  Future<void> _loadSectionSchedules() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsSectionScheduleKey);
    if (raw == null || raw.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _sectionSchedules.clear());
      return;
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return;
      final out = <String, ({int startHour, int endHour})>{};
      for (final e in parsed.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final sh = v['startHour'];
        final eh = v['endHour'];
        if (sh is num && eh is num) {
          out[e.key] = (startHour: sh.toInt(), endHour: eh.toInt());
        }
      }
      if (!mounted) return;
      setState(() {
        _sectionSchedules
          ..clear()
          ..addAll(out);
      });
    } catch (_) {}
  }

  Future<void> _persistSectionSchedules() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, Map<String, int>>{};
    for (final e in _sectionSchedules.entries) {
      out[e.key] = {
        'startHour': e.value.startHour,
        'endHour': e.value.endHour,
      };
    }
    await p.setString(_prefsSectionScheduleKey, jsonEncode(out));
  }

  String _slotTextFor(String sectionTitle) {
    final slot = _sectionSchedules[sectionTitle];
    if (slot == null) return 'Always available';
    String fmt(int hour) {
      final h = hour % 12 == 0 ? 12 : hour % 12;
      final ampm = hour >= 12 ? 'PM' : 'AM';
      return '$h $ampm';
    }
    return '${fmt(slot.startHour)} - ${fmt(slot.endHour)}';
  }

  Future<void> _openSectionScheduleEditor() async {
    String? section = _sectionTitleForChip(_categoryIndex);
    if (section == null || section.trim().isEmpty) {
      section = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Text(
                  'Choose menu section',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _maroon,
                  ),
                ),
              ),
              for (final c in _categories.skip(1))
                ListTile(
                  title: Text(
                    c.label,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _slotTextFor(c.label),
                    style: GoogleFonts.poppins(fontSize: 12, color: _muted),
                  ),
                  onTap: () => Navigator.pop(ctx, c.label),
                ),
            ],
          ),
        ),
      );
    }
    if (!mounted || section == null || section.trim().isEmpty) return;
    final sectionTitle = section;

    final picks = [
      (start: 6, end: 11, label: 'Breakfast (6 AM - 11 AM)'),
      (start: 11, end: 16, label: 'Lunch (11 AM - 4 PM)'),
      (start: 16, end: 22, label: 'Evening (4 PM - 10 PM)'),
      (start: 0, end: 24, label: 'All Day'),
    ];
    final pick = await showModalBottomSheet<({int start, int end})>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                '$sectionTitle availability',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _maroon,
                ),
              ),
            ),
            for (final s in picks)
              ListTile(
                title: Text(
                  s.label,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(ctx, (start: s.start, end: s.end)),
              ),
            ListTile(
              title: Text(
                'Clear schedule (always available)',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade700,
                ),
              ),
              onTap: () => Navigator.pop(ctx, (start: -1, end: -1)),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    setState(() {
      if (pick.start < 0) {
        _sectionSchedules.remove(sectionTitle);
      } else {
        _sectionSchedules[sectionTitle] = (
          startHour: pick.start,
          endHour: pick.end,
        );
      }
    });
    await _persistSectionSchedules();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${sectionTitle.trim()} availability updated.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<String?> _promptNewCategory() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Add category',
          style: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _maroon,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Category name',
            hintStyle: GoogleFonts.poppins(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result?.trim();
  }

  Future<void> _openDishEditor(
    BuildContext context, {
    required String sectionTitle,
    required MenuCatalogDish dish,
    required String storageKey,
    required AdminDishEditSnapshot initial,
  }) async {
    final result = await Navigator.of(context).push<AdminDishEditSnapshot>(
      MaterialPageRoute(
        builder: (ctx) => AdminDishEditScreen(
          sectionTitle: sectionTitle,
          catalogDish: dish,
          initial: initial,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _snapshots[storageKey] = result);
    await _persistSnapshots();
    await CustomerMenuOverrides.instance.reloadFromPrefs();
  }

  Future<void> _onDishMoreAction(
    BuildContext context, {
    required _MenuRow row,
    required String action,
  }) async {
    final key = row.storageKey;
    switch (action) {
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'Remove dish from menu?',
              style: GoogleFonts.playfairDisplay(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: _maroon,
              ),
            ),
            content: Text(
              'This hides the dish on the customer Home menu and in this admin list '
              'on this device (saved locally). Edits for this dish are cleared.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                height: 1.4,
                color: _muted,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'Delete',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
        if (!mounted || ok != true) return;
        setState(() => _snapshots.remove(key));
        await _persistSnapshots();
        if (!row.isCustom) {
          await MenuDeletedDishes.instance
              .markDeleted(row.sectionTitle, row.dish.title);
        }
        break;
      case 'unavailable':
        final cur = _snapshots[key] ?? row.snapshot;
        setState(() {
          _snapshots[key] = cur.copyWith(available: false);
        });
        await _persistSnapshots();
        await CustomerMenuOverrides.instance.reloadFromPrefs();
        break;
      case 'available':
        final cur2 = _snapshots[key] ?? row.snapshot;
        setState(() {
          _snapshots[key] = cur2.copyWith(available: true);
        });
        await _persistSnapshots();
        await CustomerMenuOverrides.instance.reloadFromPrefs();
        break;
    }
  }

  Future<void> _addItemFlow() async {
    String? section = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final options = _categories.skip(1).toList();
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Text(
                  'Choose category',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _maroon,
                  ),
                ),
              ),
              for (final s in options)
                ListTile(
                  leading: Icon(Icons.category_outlined, color: cs.primary),
                  title: Text(
                    s.label,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.pop(ctx, s.label),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: Text(
                  'Add Category',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(ctx, '__add_category__'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
    if (!mounted || section == null) return;
    if (section == '__add_category__') {
      final created = await _promptNewCategory();
      if (!mounted || created == null || created.isEmpty) return;
      final existing = _categories
          .map((e) => e.label.toLowerCase())
          .contains(created.toLowerCase());
      if (existing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category already exists.')),
        );
        return;
      }
      setState(() => _customCategories.add(created));
      await _persistCustomCategories();
      section = created;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final storageKey = _customKey(section, id);
    const blankDish = MenuCatalogDish(
      'New Dish',
      'Describe this dish',
      '₹0',
    );
    const blankSnapshot = AdminDishEditSnapshot(
      title: '',
      subtitle: '',
      price: '₹0',
      badge: null,
      imageBase64: null,
      available: true,
    );
    if (!mounted) return;
    await _openDishEditor(
      context,
      sectionTitle: section,
      dish: blankDish,
      storageKey: storageKey,
      initial: blankSnapshot,
    );
  }

  List<_MenuRow> _visibleRows() {
    final rows = <_MenuRow>[
      ...menuCatalogAllDishesHidingDeleted(
        MenuDeletedDishes.instance.keys,
      ).map(
        (e) => _MenuRow(
          sectionTitle: e.sectionTitle,
          dish: e.dish,
          storageKey: adminDishStorageKey(e.sectionTitle, e.dish.title),
          snapshot: _merged(e.sectionTitle, e.dish),
          isCustom: false,
        ),
      ),
      ..._snapshots.entries.where((e) => _isCustomKey(e.key)).map((e) {
        final sectionTitle = _customSectionFromKey(e.key);
        final s = e.value;
        final dish = MenuCatalogDish(
          s.title,
          s.subtitle,
          s.price,
          badge: s.badge,
        );
        return _MenuRow(
          sectionTitle: sectionTitle,
          dish: dish,
          storageKey: e.key,
          snapshot: s,
          isCustom: true,
        );
      }),
    ];

    final sectionKey = _sectionTitleForChip(_categoryIndex);
    if (sectionKey != null) {
      rows.removeWhere((e) => e.sectionTitle != sectionKey);
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows.removeWhere((e) {
        final m = e.snapshot;
        final hay =
            '${m.title} ${m.subtitle} ${e.sectionTitle}'.toLowerCase();
        return !hay.contains(q);
      });
    }

    int priceFor(_MenuRow e) => menuCatalogParseRupees(e.snapshot.price);

    switch (_sortBy) {
      case 'Price: Low to High':
        rows.sort((a, b) => priceFor(a).compareTo(priceFor(b)));
        break;
      case 'Price: High to Low':
        rows.sort((a, b) => priceFor(b).compareTo(priceFor(a)));
        break;
      case 'Popularity':
        rows.sort((a, b) {
          final ma = a.snapshot;
          final mb = b.snapshot;
          final ba = ma.badge != null ? 0 : 1;
          final bb = mb.badge != null ? 0 : 1;
          final c = ba.compareTo(bb);
          if (c != 0) return c;
          return ma.title.toLowerCase().compareTo(mb.title.toLowerCase());
        });
        break;
      case 'Name':
      default:
        rows.sort(
          (a, b) =>
              a.snapshot.title.toLowerCase().compareTo(b.snapshot.title.toLowerCase()),
        );
    }
    return rows;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await MenuDeletedDishes.instance.reloadFromPrefs();
      await _loadCustomCategories();
      await _loadSectionSchedules();
      await _loadSectionOverrides();
      await _loadSnapshots();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxChip = _categories.length - 1;
    if (_categoryIndex > maxChip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryIndex = maxChip);
      });
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        CustomerMenuOverrides.instance,
        CustomerMenuSectionOverrides.instance,
        MenuDeletedDishes.instance,
      ]),
      builder: (context, _) {
        final rowsLive = _visibleRows();
        final catalogActive = menuCatalogAllDishesHidingDeleted(
          MenuDeletedDishes.instance.keys,
        ).length;
        final cs = Theme.of(context).colorScheme;
        final bodyMuted = cs.onSurfaceVariant;
        final chipBorder = cs.outlineVariant;
        final chipUnselectedBg = cs.surface;
        final chipSelectedBg = Theme.of(context).brightness == Brightness.dark
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : _tabSelectedBg;
        return AppPullToRefresh(
          onRefresh: _onPullToRefresh,
          child: SingleChildScrollView(
            physics: AppPullToRefresh.scrollPhysics,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Menu Management',
            style: GoogleFonts.playfairDisplay(
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w700,
              color: _maroon,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$catalogActive dishes in catalog (after removals on this device). '
            'Edits sync to the customer Home menu on this device (saved locally). '
            'Use Firestore later for multi-device sync.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: bodyMuted,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search dishes (customer menu)...',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: bodyMuted.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: bodyMuted, size: 22),
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: chipBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: chipBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _maroon, width: 1.5),
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _searchCtrl.clear()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _maroon,
                  side: BorderSide(color: chipBorder),
                  backgroundColor: chipUnselectedBg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: Text(
                  'Clear',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addItemFlow(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(
                    'Add Item',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openSectionScheduleEditor,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: BorderSide(color: chipBorder),
                    backgroundColor: chipUnselectedBg,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.schedule_rounded, size: 19),
                  label: Text(
                    'Set Schedule',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final c = _categories[i];
                final sel = _categoryIndex == i;
                return InkWell(
                  onTap: () => setState(() => _categoryIndex = i),
                  onLongPress: i == 0
                      ? null
                      : () => _openCategoryEditor(_sectionIdForChip(i)!),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: sel ? chipSelectedBg : chipUnselectedBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? _orange.withValues(alpha: 0.35)
                            : chipBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          c.icon,
                          size: 18,
                          color: sel ? _maroon : bodyMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.label,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel ? _maroon : bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_sectionTitleForChip(_categoryIndex) != null) ...[
            const SizedBox(height: 8),
            Text(
              'Availability: ${_slotTextFor(_sectionTitleForChip(_categoryIndex)!)}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: bodyMuted,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  _openCategoryEditor(_sectionTitleForChip(_categoryIndex)!),
              style: OutlinedButton.styleFrom(
                foregroundColor: _maroon,
                side: BorderSide(color: chipBorder),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                'Edit category (name, subtitle, image)',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Menu items (${rowsLive.length})',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _maroon,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() => _sortBy = v),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'Name', child: Text('Name')),
                  PopupMenuItem(
                    value: 'Popularity',
                    child: Text('Popularity (badges first)'),
                  ),
                  PopupMenuItem(
                    value: 'Price: Low to High',
                    child: Text('Price: Low to High'),
                  ),
                  PopupMenuItem(
                    value: 'Price: High to Low',
                    child: Text('Price: High to Low'),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sort: ',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                    Text(
                      _sortBy,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _maroon,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _maroon,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (rowsLive.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                'No dishes match your search.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...rowsLive.expand((row) {
            final m = row.snapshot;
            final t = _thumbForSection(row.sectionTitle);
            return [
              _MenuItemCard(
                name: m.title,
                subtitle: '${row.sectionTitle} · ${m.subtitle}',
                price: m.price,
                badge: m.badge,
                imageBase64: m.imageBase64,
                available: m.available,
                thumbIcon: t.icon,
                thumbTint: t.tint,
                onEdit: () => _openDishEditor(
                  context,
                  sectionTitle: row.sectionTitle,
                  dish: row.dish,
                  storageKey: row.storageKey,
                  initial: row.snapshot,
                ),
                onMore: (action) => _onDishMoreAction(
                  context,
                  row: row,
                  action: action,
                ),
              ),
              const SizedBox(height: 10),
            ];
          }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({
    required this.name,
    required this.subtitle,
    required this.price,
    required this.thumbIcon,
    required this.thumbTint,
    required this.available,
    required this.onEdit,
    required this.onMore,
    this.badge,
    this.imageBase64,
  });

  final String name;
  final String subtitle;
  final String price;
  final IconData thumbIcon;
  final Color thumbTint;
  final bool available;
  final VoidCallback onEdit;
  final ValueChanged<String> onMore;
  final String? badge;
  final String? imageBase64;

  static const _maroon = Color(0xFF5D1F1A);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardBg = cs.surface;
    final borderCol = cs.outlineVariant;
    final titleCol = cs.onSurface;
    final mutedCol = cs.onSurfaceVariant;
    return Material(
      color: cardBg,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderCol),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: _DishThumb(
                      imageBase64: imageBase64,
                      thumbIcon: thumbIcon,
                      thumbTint: thumbTint,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _maroon,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFFFB74D),
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFE65100),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: mutedCol,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            price,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: titleCol,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (available)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF2E7D32),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Available',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF2E7D32),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: mutedCol,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Unavailable',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: mutedCol,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: _maroon,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: mutedCol,
                        size: 20,
                      ),
                      onSelected: onMore,
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Colors.red.shade800,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Delete',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: available ? 'unavailable' : 'available',
                          child: Text(
                            available
                                ? 'Mark unavailable'
                                : 'Mark available',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DishThumb extends StatelessWidget {
  const _DishThumb({
    required this.imageBase64,
    required this.thumbIcon,
    required this.thumbTint,
  });

  final String? imageBase64;
  final IconData thumbIcon;
  final Color thumbTint;

  static const _maroon = Color(0xFF5D1F1A);

  @override
  Widget build(BuildContext context) {
    final b64 = imageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 72,
          height: 72,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(),
        );
      } catch (_) {
        return _fallback();
      }
    }
    return _fallback();
  }

  Widget _fallback() {
    return ColoredBox(
      color: thumbTint,
      child: Center(
        child: Icon(
          thumbIcon,
          size: 36,
          color: _maroon.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _MenuRow {
  const _MenuRow({
    required this.sectionTitle,
    required this.dish,
    required this.storageKey,
    required this.snapshot,
    required this.isCustom,
  });

  final String sectionTitle;
  final MenuCatalogDish dish;
  final String storageKey;
  final AdminDishEditSnapshot snapshot;
  final bool isCustom;
}
