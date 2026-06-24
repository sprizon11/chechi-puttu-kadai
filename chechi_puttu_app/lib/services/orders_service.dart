import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrdersService {
  OrdersService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? chechiFirestore,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<String> createOrder({
    required List<Map<String, Object?>> items,
    required int totalRupees,
    required String deliveryLine,
    required String paymentMode,
    required String scheduleLine,
    DateTime? scheduledAt,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }

    String? customerName = user.displayName?.trim();
    String? customerMobile = user.phoneNumber?.trim();
    try {
      final userSnap = await _db.collection('users').doc(user.uid).get();
      final um = userSnap.data();
      if (um != null) {
        final fromProfileName = (um['displayName'] as String?)?.trim();
        final fromProfileMobile = (um['mobile'] as String?)?.trim();
        if (fromProfileName != null && fromProfileName.isNotEmpty) {
          customerName = fromProfileName;
        }
        if (fromProfileMobile != null && fromProfileMobile.isNotEmpty) {
          customerMobile = fromProfileMobile;
        }
      }
    } catch (_) {
      // Best effort only; order should still be placed.
    }

    final doc = await _db.collection('orders').add({
      'uid': user.uid,
      'customer_name': customerName,
      'customer_mobile': customerMobile,
      'status': 'placed',
      'total_rupees': totalRupees,
      'delivery_line': deliveryLine,
      'payment_mode': paymentMode,
      'schedule_line': scheduleLine,
      if (scheduledAt != null)
        'scheduled_at': Timestamp.fromDate(scheduledAt),
      'items': items,
      'created_at': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  /// Admin kitchen flow — requires Firestore rules allowing admin updates.
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _db.collection('orders').doc(orderId).update({'status': status});
  }
}
