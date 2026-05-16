import 'package:chechi_puttu_app/admin/admin_dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sends a one-time birthday wish in support chat when today is the customer's DOB.
class BirthdayChatWishService {
  BirthdayChatWishService._();
  static final BirthdayChatWishService instance = BirthdayChatWishService._();

  static String profileDobPrefsKey(String uid) => 'chechi_profile_dob_$uid';

  static bool isBirthdayWishMessage(Map<String, dynamic> data) {
    return (data['kind'] as String?) == 'birthday_wish';
  }

  static String todayKey() {
    final n = DateTime.now();
    return '${n.year}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  static bool isBirthdayToday(String? dobStr) {
    if (dobStr == null || dobStr.trim().length < 10) return false;
    final parts = dobStr.trim().split('-');
    if (parts.length < 3) return false;
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (m == null || d == null) return false;
    final now = DateTime.now();
    return m == now.month && d == now.day;
  }

  static String firstNameFrom(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  static String wishMessageFor(String displayName) {
    final first = firstNameFrom(displayName);
    return '🎉 Happy Birthday, $first! 🎂\n\n'
        'Warm wishes from everyone at Chechi Puttu Kadai. '
        'May your day be filled with joy, love, and delicious homestyle food!';
  }

  /// Loads DOB from Firestore, with local profile cache as fallback.
  Future<String?> fetchDateOfBirth(String customerUid) async {
    final uid = customerUid.trim();
    if (uid.isEmpty) return null;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final fromCloud = snap.data()?['dateOfBirth'] as String?;
      if (fromCloud != null && fromCloud.trim().length >= 10) {
        return fromCloud.trim();
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString(profileDobPrefsKey(uid));
    if (local != null && local.trim().length >= 10) return local.trim();
    return null;
  }

  Future<bool> isBirthdayTodayForUid(String customerUid) async {
    final dob = await fetchDateOfBirth(customerUid);
    return isBirthdayToday(dob);
  }

  /// Display name for home banner / greetings.
  Future<String> firstNameForUid(String customerUid) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(customerUid).get();
      final name = (snap.data()?['displayName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return firstNameFrom(name);
    } catch (_) {}
    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid == customerUid) {
      final dn = user?.displayName?.trim();
      if (dn != null && dn.isNotEmpty) return firstNameFrom(dn);
    }
    return 'there';
  }

  /// Calls Cloud Function when available; admins can fall back to direct write.
  /// No-op if today is not the customer's birthday.
  Future<void> ensureForCustomer(String customerUid) async {
    final uid = customerUid.trim();
    if (uid.isEmpty) return;
    if (!await isBirthdayTodayForUid(uid)) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('ensureBirthdayChatWish')
          .call({'customerUid': uid});
      return;
    } catch (_) {
      // Function may be undeployed — try admin-only local write.
    }
    if (isChechiAdminUser(FirebaseAuth.instance.currentUser)) {
      await _ensureLocallyForAdmin(uid);
    }
  }

  Future<void> _ensureLocallyForAdmin(String customerUid) async {
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(customerUid).get();
    final user = userSnap.data();
    final dob = user?['dateOfBirth'] as String?;
    if (!isBirthdayToday(dob)) return;

    final dayKey = todayKey();
    final threadRef =
        FirebaseFirestore.instance.collection('support_inbox').doc(customerUid);
    final thread = await threadRef.get();
    if (thread.data()?['birthday_wish_sent_on'] == dayKey) return;

    final name = (user?['displayName'] as String?)?.trim() ?? 'there';
    final text = wishMessageFor(name);

    await threadRef.collection('messages').add({
      'text': text,
      'sender': 'admin',
      'kind': 'birthday_wish',
      'auto': true,
      'created_at': FieldValue.serverTimestamp(),
    });
    await threadRef.set({
      'customer_uid': customerUid,
      'customer_name': name == 'there' ? null : name,
      'customer_mobile': user?['mobile'],
      'last_message': '🎉 Happy Birthday, ${name.split(RegExp(r'\s+')).first}! 🎂',
      'last_sender': 'admin',
      'last_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'birthday_wish_sent_on': dayKey,
      'unread_customer_to_admin': 0,
    }, SetOptions(merge: true));
  }
}
