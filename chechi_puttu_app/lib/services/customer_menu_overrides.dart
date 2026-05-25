import 'dart:convert';
import 'dart:async';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:chechi_puttu_app/services/customer_menu_section_overrides.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads admin-saved dish snapshots (text, image, availability) for the customer Home menu.
class CustomerMenuOverrides extends ChangeNotifier {
  CustomerMenuOverrides._();
  static final CustomerMenuOverrides instance = CustomerMenuOverrides._();
  static const _cloudMenuOverridesCollection = 'admin_public';
  static const _cloudMenuOverridesDoc = 'menu_overrides';
  static const _cloudSnapshotsSubcollection = 'snapshots';

  Map<String, AdminDishEditSnapshot> _map = {};
  Map<String, AdminDishEditSnapshot> _localCache = {};
  bool _cloudSyncStarted = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cloudSub;
  Timer? _cloudRetryTimer;

  AdminDishEditSnapshot? snapshotFor(
    String sectionTitle,
    String catalogDishTitle,
  ) {
    return _map[adminDishStorageKey(sectionTitle, catalogDishTitle)];
  }

  Map<String, AdminDishEditSnapshot> snapshotMapForBuild() =>
      Map<String, AdminDishEditSnapshot>.from(_map);

  Future<void> reloadFromPrefs() async {
    final local = await _readLocalSnapshots();
    _localCache = local;
    _map = Map<String, AdminDishEditSnapshot>.from(local);
    notifyListeners();
    CustomerMenuSectionOverrides.instance.rebuildFromDishOverrides();
    unawaited(_refreshFromCloudOnce());
    unawaited(_ensureCloudSyncStarted());
  }

  Future<void> _refreshFromCloudOnce() async {
    final cloud = await _readCloudSnapshotsOnce();
    if (cloud == null) return;
    _localCache = Map<String, AdminDishEditSnapshot>.from(cloud);
    _map = Map<String, AdminDishEditSnapshot>.from(cloud);
    notifyListeners();
    CustomerMenuSectionOverrides.instance.rebuildFromDishOverrides();
    await _persistLocalSnapshots(cloud);
  }

  Future<Map<String, AdminDishEditSnapshot>> _readLocalSnapshots() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(kAdminDishSnapshotsPrefsKey);
    if (raw == null || raw.isEmpty) return <String, AdminDishEditSnapshot>{};
    try {
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      final next = <String, AdminDishEditSnapshot>{};
      for (final e in jsonMap.entries) {
        final v = e.value;
        if (v is! Map<String, dynamic>) continue;
        next[e.key] = AdminDishEditSnapshot.fromJson(v);
      }
      return next;
    } catch (_) {
      return <String, AdminDishEditSnapshot>{};
    }
  }

  Future<Map<String, AdminDishEditSnapshot>?> _readCloudSnapshotsOnce() async {
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
      if (raw is! Map) return out;
      for (final e in raw.entries) {
        final key = e.key.toString();
        final val = e.value;
        if (val is! Map) continue;
        out[key] = AdminDishEditSnapshot.fromJson(Map<String, dynamic>.from(val));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureCloudSyncStarted() async {
    if (_cloudSyncStarted) return;
    _cloudSyncStarted = true;
    _cloudRetryTimer?.cancel();
    final root = FirebaseFirestore.instance
        .collection(_cloudMenuOverridesCollection)
        .doc(_cloudMenuOverridesDoc);
    _cloudSub?.cancel();
    _cloudSub = root.collection(_cloudSnapshotsSubcollection).snapshots().listen((snap) async {
          final out = <String, AdminDishEditSnapshot>{};
          var legacyReadFailed = false;
          for (final d in snap.docs) {
            final m = d.data();
            final key = (m['key'] as String?)?.trim();
            final data = m['data'];
            if (key == null || key.isEmpty || data is! Map) continue;
            out[key] = AdminDishEditSnapshot.fromJson(
              Map<String, dynamic>.from(data),
            );
          }

          // Backward-compatible fallback for legacy map doc if subcollection empty.
          if (out.isEmpty) {
            try {
              final legacyDoc = await root.get();
              final raw = legacyDoc.data()?['snapshots'];
              if (raw is Map) {
                for (final e in raw.entries) {
                  final key = e.key.toString();
                  final val = e.value;
                  if (val is! Map) continue;
                  out[key] = AdminDishEditSnapshot.fromJson(
                    Map<String, dynamic>.from(val),
                  );
                }
              }
            } catch (_) {
              legacyReadFailed = true;
            }
          }

          // Prefer cloud as source of truth whenever we can read it.
          // If cloud read fails, keep local cache so UI still has data offline.
          final next = (out.isEmpty && legacyReadFailed)
              ? Map<String, AdminDishEditSnapshot>.from(_localCache)
              : out;
          _localCache = Map<String, AdminDishEditSnapshot>.from(next);
          _map = Map<String, AdminDishEditSnapshot>.from(next);
          notifyListeners();
          CustomerMenuSectionOverrides.instance.rebuildFromDishOverrides();
          await _persistLocalSnapshots(next);
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
    // Auto-reconnect so customer devices continue receiving admin image updates.
    _cloudRetryTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_ensureCloudSyncStarted());
    });
  }

  Future<void> _persistLocalSnapshots(
    Map<String, AdminDishEditSnapshot> snapshots,
  ) async {
    final p = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    snapshots.forEach((k, v) => out[k] = v.toJson());
    await p.setString(kAdminDishSnapshotsPrefsKey, jsonEncode(out));
  }
}
