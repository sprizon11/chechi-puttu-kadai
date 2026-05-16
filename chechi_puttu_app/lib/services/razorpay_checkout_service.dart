import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RazorpayCheckoutResult {
  const RazorpayCheckoutResult({
    required this.sessionId,
    required this.razorpayOrderId,
    required this.amountPaise,
    required this.keyId,
  });

  final String sessionId;
  final String razorpayOrderId;
  final int amountPaise;
  final String keyId;
}

/// Server-side Razorpay order via Firebase Callable + `checkout_sessions` polling.
class RazorpayCheckoutService {
  RazorpayCheckoutService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _fn = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _fn;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<RazorpayCheckoutResult> createCheckout({
    required List<Map<String, Object?>> items,
    required String deliveryLine,
    String? scheduleLine,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Not signed in');
    }

    final callable = _fn.httpsCallable('createRazorpayCheckout');
    final res = await callable.call({
      'items': items,
      'deliveryLine': deliveryLine,
      'scheduleLine': scheduleLine,
    });

    final data = Map<String, dynamic>.from(res.data);
    return RazorpayCheckoutResult(
      sessionId: data['sessionId']! as String,
      razorpayOrderId: data['razorpayOrderId']! as String,
      amountPaise: (data['amountPaise'] as num).toInt(),
      keyId: data['keyId']! as String,
    );
  }

  Future<Map<String, dynamic>?> _fetchSession(String sessionId) async {
    final snap =
        await _db.collection('checkout_sessions').doc(sessionId).get();
    return snap.data();
  }

  /// Waits until webhook marks session paid (returns `order_id`), or failure / timeout.
  Future<String?> waitUntilPaid(
    String sessionId, {
    Duration timeout = const Duration(minutes: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final d0 = await _fetchSession(sessionId);
    if (d0 != null &&
        d0['status'] == 'paid' &&
        d0['order_id'] is String &&
        (d0['order_id'] as String).isNotEmpty) {
      return d0['order_id'] as String;
    }
    if (d0?['status'] == 'failed' || d0?['status'] == 'error') return null;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final d = await _fetchSession(sessionId);
      if (d == null) continue;
      final st = d['status'] as String?;
      if (st == 'paid' &&
          d['order_id'] is String &&
          (d['order_id'] as String).isNotEmpty) {
        return d['order_id'] as String;
      }
      if (st == 'failed' || st == 'error') return null;
    }
    return null;
  }
}
