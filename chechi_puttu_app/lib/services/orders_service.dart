import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrdersService {
  OrdersService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? chechiFirestore,
        _auth = auth ?? FirebaseAuth.instance,
        _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _fn;

  /// Places a cash-on-delivery order through the `placeCashOrder` function,
  /// which prices the cart on the server and checks the order hold. Firestore
  /// rules no longer accept orders written from the app.
  ///
  /// Returns the order id and the total the server charged. Throws
  /// [FirebaseFunctionsException] — `failed-precondition` while orders are on
  /// hold (its message is the admin's hold message).
  Future<({String orderId, int totalRupees})> createCashOrder({
    required List<Map<String, Object?>> items,
    required String deliveryLine,
    required String scheduleLine,
    DateTime? scheduledAt,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Not signed in');
    }
    // Same id on a retry, so a call that timed out after the order was saved
    // cannot create it twice.
    final requestId = _db.collection('orders').doc().id;
    final res = await _fn.httpsCallable('placeCashOrder').call({
      'requestId': requestId,
      'items': items,
      'deliveryLine': deliveryLine,
      'scheduleLine': scheduleLine,
      'scheduledAtIso': scheduledAt?.toUtc().toIso8601String(),
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    final orderId = (data['orderId'] as String?) ?? '';
    if (orderId.isEmpty) {
      throw StateError('Invalid response from order server');
    }
    return (
      orderId: orderId,
      totalRupees: (data['totalRupees'] as num?)?.toInt() ?? 0,
    );
  }

  /// Admin kitchen flow — requires Firestore rules allowing admin updates.
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _db.collection('orders').doc(orderId).update({'status': status});
  }
}
