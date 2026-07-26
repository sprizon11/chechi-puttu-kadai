import 'dart:convert';

import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

final customerOrderTypeService = CustomerOrderTypeService();

class CustomerOrderTypeService {
  CustomerOrderTypeService({FirebaseFirestore? firestore})
      : _db = firestore ?? chechiFirestore;

  final FirebaseFirestore _db;

  static const _usersCol = 'users';
  static const _prefsPrefix = 'chechi_order_type_v1_';

  String _prefsKey(String uid) => '$_prefsPrefix$uid';

  Future<CustomerOrderTypeState> loadState(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey(uid));
    CustomerOrderTypeState local = const CustomerOrderTypeState();
    if (cached != null && cached.isNotEmpty) {
      try {
        local = _stateFromJson(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }

    try {
      final snap = await _db.collection(_usersCol).doc(uid).get();
      final m = snap.data();
      if (m == null) return local;
      final remote = CustomerOrderTypeState(
        orderType: CustomerOrderType.fromFirestore(m['orderType'] as String?),
        typeSelected: m['orderTypeSelected'] == true,
        bulkEnrollment: BulkOrderEnrollment.fromMap(
          m['bulkOrder'] is Map
              ? Map<String, dynamic>.from(m['bulkOrder'] as Map)
              : null,
        ),
      );
      await _cacheState(uid, remote);
      return remote;
    } catch (_) {
      return local;
    }
  }

  CustomerOrderTypeState _stateFromJson(Map<String, dynamic> j) {
    final days = j['days'];
    final selectedDishes = j['selectedDishes'];
    final titles = selectedDishes is List
        ? selectedDishes.map((e) => e.toString()).toList()
        : const <String>[];
    final rawQuantities = j['dishQuantities'];
    final dishQuantities = <String, int>{};
    if (rawQuantities is Map) {
      rawQuantities.forEach((key, value) {
        final qty = value is num ? value.toInt() : int.tryParse('$value');
        if (qty != null && qty > 0) dishQuantities[key.toString()] = qty;
      });
    }
    for (final title in titles) {
      dishQuantities.putIfAbsent(title, () => kDefaultDishQuantity);
    }
    return CustomerOrderTypeState(
      orderType: CustomerOrderType.fromFirestore(j['orderType'] as String?),
      typeSelected: j['typeSelected'] as bool? ?? false,
      bulkEnrollment: BulkOrderEnrollment(
        contactName: j['contactName'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        alternatePhone: j['alternatePhone'] as String? ?? '',
        organizationName: j['organizationName'] as String? ?? '',
        orderPersonName: j['orderPersonName'] as String? ?? '',
        orderPersonDesignation: j['orderPersonDesignation'] as String? ?? '',
        preferredTime: j['preferredTime'] as String? ?? '',
        scheduleMode: BulkScheduleMode.fromFirestore(
          j['scheduleMode'] as String?,
        ),
        days: days is List ? days.map((e) => e.toString()).toList() : const [],
        selectedDishes: titles,
        dishQuantities: dishQuantities,
        enrollmentComplete: j['enrollmentComplete'] as bool? ?? false,
      ),
    );
  }

  Future<void> _cacheState(String uid, CustomerOrderTypeState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey(uid),
      jsonEncode({
        'orderType': state.orderType?.firestoreValue,
        'typeSelected': state.typeSelected,
        'contactName': state.bulkEnrollment.contactName,
        'phone': state.bulkEnrollment.phone,
        'alternatePhone': state.bulkEnrollment.alternatePhone,
        'organizationName': state.bulkEnrollment.organizationName,
        'orderPersonName': state.bulkEnrollment.orderPersonName,
        'orderPersonDesignation': state.bulkEnrollment.orderPersonDesignation,
        'preferredTime': state.bulkEnrollment.preferredTime,
        'scheduleMode': state.bulkEnrollment.scheduleMode.firestoreValue,
        'days': state.bulkEnrollment.days,
        'selectedDishes': state.bulkEnrollment.selectedDishes,
        'dishQuantities': state.bulkEnrollment.dishQuantities,
        'enrollmentComplete': state.bulkEnrollment.enrollmentComplete,
      }),
    );
  }

  Future<void> saveOrderType({
    required User user,
    required CustomerOrderType type,
  }) async {
    final uid = user.uid;
    final state = CustomerOrderTypeState(
      orderType: type,
      typeSelected: true,
      bulkEnrollment: type.needsBulkEnrollment
          ? const BulkOrderEnrollment()
          : const BulkOrderEnrollment(enrollmentComplete: true),
    );
    await _cacheState(uid, state);
    try {
      await _db.collection(_usersCol).doc(uid).set(
        {
          'uid': uid,
          'orderType': type.firestoreValue,
          'orderTypeSelected': true,
          if (!type.needsBulkEnrollment)
            'bulkOrder': FieldValue.delete()
          else
            'bulkOrder': {
              'enrollmentComplete': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          'orderTypeUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> clearOrderTypeSelection(String uid) async {
    await _cacheState(uid, const CustomerOrderTypeState());
    try {
      await _db.collection(_usersCol).doc(uid).set(
        {
          'orderTypeSelected': false,
          'bulkOrder': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> saveBulkEnrollment({
    required User user,
    required CustomerOrderType type,
    required BulkOrderEnrollment enrollment,
  }) async {
    final uid = user.uid;
    final complete = enrollment.copyWith(enrollmentComplete: true);
    final state = CustomerOrderTypeState(
      orderType: type,
      typeSelected: true,
      bulkEnrollment: complete,
    );
    await _cacheState(uid, state);
    try {
      await _db.collection(_usersCol).doc(uid).set(
        {
          'uid': uid,
          'orderType': type.firestoreValue,
          'orderTypeSelected': true,
          'bulkOrder': {
            ...complete.toFirestore(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'orderTypeUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
