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

/// Result of creating a Cashfree Payment Link.
class CashfreeLinkResult {
  const CashfreeLinkResult({
    required this.sessionId,
    required this.linkUrl,
    required this.mode,
    required this.amountRupees,
  });

  final String sessionId;
  final String linkUrl;
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

  /// Creates a Cashfree Payment Link. The app opens [linkUrl] in the browser —
  /// the payment page is on Cashfree's own domain, so no whitelisting is needed.
  Future<CashfreeLinkResult> createPaymentLink({
    required List<Map<String, Object?>> items,
    required String deliveryLine,
    String? scheduleLine,
    DateTime? scheduledAt,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Not signed in');
    }

    final callable = _fn.httpsCallable('createCashfreePaymentLink');
    final res = await callable.call({
      'items': items,
      'deliveryLine': deliveryLine,
      'scheduleLine': scheduleLine,
      'scheduledAtIso': scheduledAt?.toUtc().toIso8601String(),
    });

    final data = Map<String, dynamic>.from(res.data as Map);
    final sessionId = data['sessionId'] as String? ?? '';
    final linkUrl = data['linkUrl'] as String? ?? '';
    if (sessionId.isEmpty || linkUrl.isEmpty) {
      throw StateError('Invalid response from payment server — missing fields');
    }
    return CashfreeLinkResult(
      sessionId: sessionId,
      linkUrl: linkUrl,
      mode: (data['mode'] as String?) ?? 'sandbox',
      amountRupees: (data['amountRupees'] as num?) ?? 0,
    );
  }

  Future<Map<String, dynamic>?> _fetchSession(String sessionId) async {
    final snap =
        await _db.collection('checkout_sessions').doc(sessionId).get();
    return snap.data();
  }

  /// Reads the session doc (updated by the webhook) and maps it to an outcome.
  CashfreePaymentOutcome _outcomeFromSession(Map<String, dynamic>? d) {
    if (d == null) return const CashfreePaymentOutcome.pending();
    final st = d['status'] as String?;
    if (st == 'paid' &&
        d['order_id'] is String &&
        (d['order_id'] as String).isNotEmpty) {
      return CashfreePaymentOutcome.paid(d['order_id'] as String);
    }
    if (st == 'failed' || st == 'error') {
      return const CashfreePaymentOutcome.failed();
    }
    return const CashfreePaymentOutcome.pending();
  }

  /// Actively asks the server to query Cashfree for the authoritative payment
  /// status (does not depend on webhook delivery). Returns paid / failed /
  /// pending. Never throws — network errors map to `pending` so polling
  /// continues.
  Future<CashfreePaymentOutcome> reconcile(String sessionId) async {
    try {
      final callable = _fn.httpsCallable('reconcileCashfreeOrder');
      final res = await callable.call({'sessionId': sessionId});
      final data = Map<String, dynamic>.from(res.data as Map);
      final status = (data['status'] as String?) ?? 'pending';
      final orderId = data['orderId'] as String?;
      if (status == 'paid' && orderId != null && orderId.isNotEmpty) {
        return CashfreePaymentOutcome.paid(orderId);
      }
      if (status == 'failed') return const CashfreePaymentOutcome.failed();
      return const CashfreePaymentOutcome.pending();
    } catch (_) {
      return const CashfreePaymentOutcome.pending();
    }
  }

  /// Confirms payment reliably on both platforms.
  ///
  /// Polls the webhook-updated session doc every 2s AND actively reconciles
  /// against Cashfree every ~4s. Active reconciliation is what makes Android
  /// correct: its SDK reports onError even on success, so we cannot trust the
  /// SDK callback — only the server's view of Cashfree. A genuine cancellation
  /// resolves to `failed` within a few seconds (no long blank wait); a real
  /// payment is confirmed even if the webhook is slow or never arrives.
  Future<CashfreePaymentOutcome> confirmPayment(
    String sessionId, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);

    // Fast path: webhook may already have landed.
    final first = _outcomeFromSession(await _fetchSession(sessionId));
    if (first.isTerminal) return first;

    var tick = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));

      final fromDoc = _outcomeFromSession(await _fetchSession(sessionId));
      if (fromDoc.isTerminal) return fromDoc;

      // Every other tick (~4s) pull the authoritative status from Cashfree.
      if (tick.isOdd) {
        final fromServer = await reconcile(sessionId);
        if (fromServer.isTerminal) return fromServer;
      }
      tick++;
    }
    return const CashfreePaymentOutcome.unconfirmed();
  }
}

/// Result of confirming a Cashfree payment.
/// - paid: order created, [orderId] set.
/// - failed: Cashfree confirms the payment did not complete (safe to say so).
/// - unconfirmed: timed out without a definite answer (money may be debited —
///   never tell the user "no order placed").
/// - pending: still in progress (internal; not surfaced to the UI).
class CashfreePaymentOutcome {
  const CashfreePaymentOutcome.paid(this.orderId) : status = 'paid';
  const CashfreePaymentOutcome.failed()
      : status = 'failed',
        orderId = null;
  const CashfreePaymentOutcome.unconfirmed()
      : status = 'unconfirmed',
        orderId = null;
  const CashfreePaymentOutcome.pending()
      : status = 'pending',
        orderId = null;

  final String status;
  final String? orderId;

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';

  /// A definite answer that ends polling (paid or failed).
  bool get isTerminal => status == 'paid' || status == 'failed';
}
