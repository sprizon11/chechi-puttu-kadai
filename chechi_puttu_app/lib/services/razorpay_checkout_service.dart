import 'dart:async';

import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What the server needs the app to open the Razorpay checkout with.
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

  /// Razorpay public key id passed to the SDK.
  final String keyId;
}

/// Server-side Razorpay order via Firebase Callables + `checkout_sessions`.
///
/// Flow: [createCheckout] → app opens the Razorpay SDK → on SDK success the app
/// calls [verifyPayment] (authoritative, webhook-independent). [confirmPayment]
/// polls the webhook-updated session doc as a backup.
class RazorpayCheckoutService {
  RazorpayCheckoutService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _fn = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? chechiFirestore,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _fn;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<RazorpayCheckoutResult> createCheckout({
    required List<Map<String, Object?>> items,
    required String deliveryLine,
    String? scheduleLine,
    DateTime? scheduledAt,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Not signed in');
    }

    final callable = _fn.httpsCallable('createRazorpayCheckout');
    final res = await callable.call({
      'items': items,
      'deliveryLine': deliveryLine,
      'scheduleLine': scheduleLine,
      'scheduledAtIso': scheduledAt?.toUtc().toIso8601String(),
    });

    final data = Map<String, dynamic>.from(res.data as Map);
    final sessionId = data['sessionId'] as String? ?? '';
    final razorpayOrderId = data['razorpayOrderId'] as String? ?? '';
    final amountPaise = (data['amountPaise'] as num?)?.toInt() ?? 0;
    final keyId = data['keyId'] as String? ?? '';
    if (sessionId.isEmpty ||
        razorpayOrderId.isEmpty ||
        keyId.isEmpty ||
        amountPaise <= 0) {
      throw StateError('Invalid response from payment server — missing fields');
    }
    return RazorpayCheckoutResult(
      sessionId: sessionId,
      razorpayOrderId: razorpayOrderId,
      amountPaise: amountPaise,
      keyId: keyId,
    );
  }

  /// Sends the SDK success (payment id + signature) to the server, which
  /// verifies the HMAC signature and creates the order. Never throws — a failed
  /// call maps to `pending` so the caller can fall back to [confirmPayment].
  Future<RazorpayPaymentOutcome> verifyPayment({
    required String sessionId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final callable = _fn.httpsCallable('verifyRazorpayPayment');
      final res = await callable.call({
        'sessionId': sessionId,
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final status = (data['status'] as String?) ?? 'pending';
      final orderId = data['orderId'] as String?;
      if (status == 'paid' && orderId != null && orderId.isNotEmpty) {
        return RazorpayPaymentOutcome.paid(orderId);
      }
      return const RazorpayPaymentOutcome.pending();
    } catch (_) {
      return const RazorpayPaymentOutcome.pending();
    }
  }

  Future<Map<String, dynamic>?> _fetchSession(String sessionId) async {
    final snap =
        await _db.collection('checkout_sessions').doc(sessionId).get();
    return snap.data();
  }

  RazorpayPaymentOutcome _outcomeFromSession(Map<String, dynamic>? d) {
    if (d == null) return const RazorpayPaymentOutcome.pending();
    final st = d['status'] as String?;
    if (st == 'paid' &&
        d['order_id'] is String &&
        (d['order_id'] as String).isNotEmpty) {
      return RazorpayPaymentOutcome.paid(d['order_id'] as String);
    }
    if (st == 'failed' || st == 'error') {
      return const RazorpayPaymentOutcome.failed();
    }
    return const RazorpayPaymentOutcome.pending();
  }

  /// Polls the webhook-updated session doc for a terminal status. Backup for
  /// when the immediate [verifyPayment] call didn't return a confirmed order.
  Future<RazorpayPaymentOutcome> confirmPayment(
    String sessionId, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final first = _outcomeFromSession(await _fetchSession(sessionId));
    if (first.isTerminal) return first;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final o = _outcomeFromSession(await _fetchSession(sessionId));
      if (o.isTerminal) return o;
    }
    return const RazorpayPaymentOutcome.unconfirmed();
  }
}

/// Result of confirming a Razorpay payment.
/// - paid: order created, [orderId] set.
/// - failed: the payment did not complete (safe to say so).
/// - unconfirmed: timed out without a definite answer (money may be debited —
///   never tell the user "no order placed").
/// - pending: still in progress (internal; not surfaced to the UI).
class RazorpayPaymentOutcome {
  const RazorpayPaymentOutcome.paid(this.orderId) : status = 'paid';
  const RazorpayPaymentOutcome.failed()
      : status = 'failed',
        orderId = null;
  const RazorpayPaymentOutcome.unconfirmed()
      : status = 'unconfirmed',
        orderId = null;
  const RazorpayPaymentOutcome.pending()
      : status = 'pending',
        orderId = null;

  final String status;
  final String? orderId;

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';

  /// A definite answer that ends polling (paid or failed).
  bool get isTerminal => status == 'paid' || status == 'failed';
}
