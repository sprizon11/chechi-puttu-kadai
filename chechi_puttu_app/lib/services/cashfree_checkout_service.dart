import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CashfreeCheckoutResult {
  const CashfreeCheckoutResult({
    required this.sessionId,
    required this.paymentSessionId,
    required this.cfOrderId,
    required this.orderId,
    required this.mode,
    required this.amountRupees,
  });

  final String sessionId;
  final String paymentSessionId;
  final String cfOrderId;

  /// The order id Cashfree expects in the SDK session (== sessionId).
  final String orderId;

  /// 'production' or 'sandbox'.
  final String mode;
  final num amountRupees;

  bool get isProduction => mode == 'production';
}

/// Server-side Cashfree order via Firebase Callable + `checkout_sessions` polling.
class CashfreeCheckoutService {
  CashfreeCheckoutService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _fn = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? chechiFirestore,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _fn;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<CashfreeCheckoutResult> createCheckout({
    required List<Map<String, Object?>> items,
    required String deliveryLine,
    String? scheduleLine,
    DateTime? scheduledAt,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Not signed in');
    }

    final callable = _fn.httpsCallable('createCashfreeCheckout');
    final res = await callable.call({
      'items': items,
      'deliveryLine': deliveryLine,
      'scheduleLine': scheduleLine,
      'scheduledAtIso': scheduledAt?.toUtc().toIso8601String(),
    });

    final data = Map<String, dynamic>.from(res.data as Map);
    final sessionId = data['sessionId'] as String? ?? '';
    final paymentSessionId = data['paymentSessionId'] as String? ?? '';
    final cfOrderId = data['cfOrderId'] as String? ?? '';
    final orderId = data['orderId'] as String? ?? '';
    if (sessionId.isEmpty || paymentSessionId.isEmpty || orderId.isEmpty) {
      throw StateError('Invalid response from payment server — missing fields');
    }
    return CashfreeCheckoutResult(
      sessionId: sessionId,
      paymentSessionId: paymentSessionId,
      cfOrderId: cfOrderId,
      orderId: orderId,
      mode: (data['mode'] as String?) ?? 'sandbox',
      amountRupees: (data['amountRupees'] as num?) ?? 0,
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
    Duration timeout = const Duration(minutes: 2),
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
