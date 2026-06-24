import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Customer profile in Firestore (`users/{uid}`). Used to decide profile gate
/// across devices and to persist name, contact email, location, DOB.
final userProfileService = UserProfileService();

class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore})
      : _db = firestore ?? chechiFirestore;

  final FirebaseFirestore _db;

  static const _col = 'users';
  static const _pendingProfilePrefix = 'chechi_pending_profile_v1_';

  static const Duration _opTimeout = Duration(seconds: 8);

  static bool _isRetryableFirestoreError(FirebaseException e) =>
      e.code == 'unavailable' ||
      e.code == 'deadline-exceeded' ||
      e.code == 'aborted';

  /// Retries transient Firestore outages (common on mobile data).
  Future<T> _withRetry<T>(Future<T> Function() action) async {
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await action().timeout(_opTimeout);
      } on FirebaseException catch (e) {
        lastError = e;
        if (!_isRetryableFirestoreError(e) || attempt == maxAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (attempt + 1)),
        );
      } on TimeoutException {
        lastError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'deadline-exceeded',
          message: 'Firestore timed out',
        );
        if (attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (attempt + 1)),
        );
      }
    }
    throw lastError ?? StateError('Firestore retry failed');
  }

  String _pendingKey(String uid) => '$_pendingProfilePrefix$uid';

  Future<void> _queuePending(String uid, Map<String, dynamic> data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_pendingKey(uid), jsonEncode(data));
  }

  Future<void> _clearPending(String uid) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pendingKey(uid));
  }

  Map<String, dynamic> _profilePayload({
    required User user,
    required String displayName,
    required String contactEmail,
    required String mobile,
    required String homeAddress,
    required String officeAddress,
    required String otherAddress,
    required String dobStr,
    required bool isCreate,
  }) {
    final email = contactEmail.trim();
    return {
      'uid': user.uid,
      'displayName': displayName,
      'contactEmail': email,
      'mobile': mobile,
      'location': homeAddress,
      'addresses': {
        'home': homeAddress,
        'office': officeAddress,
        'other': otherAddress,
      },
      'dateOfBirth': dobStr,
      'authPhone': user.phoneNumber,
      'authEmail': user.email,
      'profileComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
      if (isCreate) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<bool> isProfileComplete(String uid) async {
    final snap = await _withRetry(
      () => _db.collection(_col).doc(uid).get(),
    );
    if (!snap.exists) return false;
    final m = snap.data();
    if (m == null) return false;
    return m['profileComplete'] == true;
  }

  /// Saves profile to Firestore. Returns `false` if server is temporarily down
  /// (caller may continue with local profile flags).
  Future<bool> trySaveCustomerProfile({
    required User user,
    required String displayName,
    required String contactEmail,
    required String mobile,
    required String homeAddress,
    required String officeAddress,
    required String otherAddress,
    required DateTime dateOfBirth,
  }) async {
    final uid = user.uid;
    final ref = _db.collection(_col).doc(uid);
    final y = dateOfBirth.year.toString().padLeft(4, '0');
    final mo = dateOfBirth.month.toString().padLeft(2, '0');
    final d = dateOfBirth.day.toString().padLeft(2, '0');
    final dobStr = '$y-$mo-$d';

    final pending = {
      'displayName': displayName,
      'contactEmail': contactEmail.trim(),
      'mobile': mobile,
      'homeAddress': homeAddress,
      'officeAddress': officeAddress,
      'otherAddress': otherAddress,
      'dateOfBirth': dobStr,
    };

    try {
      final exists = (await _withRetry(() => ref.get())).exists;
      await _withRetry(
        () => ref.set(
          _profilePayload(
            user: user,
            displayName: displayName,
            contactEmail: contactEmail,
            mobile: mobile,
            homeAddress: homeAddress,
            officeAddress: officeAddress,
            otherAddress: otherAddress,
            dobStr: dobStr,
            isCreate: !exists,
          ),
          SetOptions(merge: true),
        ),
      );
      await _clearPending(uid);
      return true;
    } on FirebaseException catch (e) {
      if (!_isRetryableFirestoreError(e)) rethrow;
      await _queuePending(uid, pending);
      return false;
    } on TimeoutException {
      await _queuePending(uid, pending);
      return false;
    }
  }

  Future<void> saveCustomerProfile({
    required User user,
    required String displayName,
    required String contactEmail,
    required String mobile,
    required String homeAddress,
    required String officeAddress,
    required String otherAddress,
    required DateTime dateOfBirth,
  }) async {
    final ok = await trySaveCustomerProfile(
      user: user,
      displayName: displayName,
      contactEmail: contactEmail,
      mobile: mobile,
      homeAddress: homeAddress,
      officeAddress: officeAddress,
      otherAddress: otherAddress,
      dateOfBirth: dateOfBirth,
    );
    if (!ok) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Firestore is temporarily unavailable',
      );
    }
  }

  /// Uploads a profile that was saved locally when Firestore was down.
  Future<void> syncPendingProfileIfAny(User? user) async {
    final u = user;
    if (u == null) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_pendingKey(u.uid));
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final dobParts = (map['dateOfBirth'] as String? ?? '').split('-');
      DateTime dob = DateTime(2000, 1, 1);
      if (dobParts.length == 3) {
        dob = DateTime(
          int.tryParse(dobParts[0]) ?? 2000,
          int.tryParse(dobParts[1]) ?? 1,
          int.tryParse(dobParts[2]) ?? 1,
        );
      }
      await trySaveCustomerProfile(
        user: u,
        displayName: map['displayName'] as String? ?? '',
        contactEmail: map['contactEmail'] as String? ?? '',
        mobile: map['mobile'] as String? ?? '',
        homeAddress: map['homeAddress'] as String? ?? '',
        officeAddress: map['officeAddress'] as String? ?? '',
        otherAddress: map['otherAddress'] as String? ?? '',
        dateOfBirth: dob,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[UserProfileService] pending sync failed: $e\n$st');
      }
    }
  }
}
