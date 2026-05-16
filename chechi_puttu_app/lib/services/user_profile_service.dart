import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Customer profile in Firestore (`users/{uid}`). Used to decide profile gate
/// across devices and to persist name, contact email, location, DOB.
final userProfileService = UserProfileService();

class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _col = 'users';

  Future<bool> isProfileComplete(String uid) async {
    final snap = await _db.collection(_col).doc(uid).get();
    if (!snap.exists) return false;
    final m = snap.data();
    if (m == null) return false;
    return m['profileComplete'] == true;
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
    final uid = user.uid;
    final ref = _db.collection(_col).doc(uid);
    final exists = (await ref.get()).exists;
    final email = contactEmail.trim();
    final y = dateOfBirth.year.toString().padLeft(4, '0');
    final mo = dateOfBirth.month.toString().padLeft(2, '0');
    final d = dateOfBirth.day.toString().padLeft(2, '0');
    final dobStr = '$y-$mo-$d';

    await ref.set(
      {
        'uid': uid,
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
        if (!exists) 'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
