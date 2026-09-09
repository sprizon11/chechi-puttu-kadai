import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Google Analytics (Firebase) events.
///
/// The SDK collects first_open, session_start and screen views on its own once
/// it is in the app. This class adds the commerce events, which are the ones
/// worth reporting on: what people add, where they drop out, and what they buy.
///
/// Like [MetaEvents] in meta_events_service.dart, every call here is best
/// effort and swallows its own failures. Reporting must never be able to fail
/// an order, so no call site awaits these on the path to the customer's
/// confirmation. The two services are deliberately called side by side rather
/// than wrapped in one helper — Meta and Google want different event shapes,
/// and hiding that behind a single call makes both harder to change.
abstract final class AppAnalytics {
  static FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  static Future<void> _run(String label, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      debugPrint('AppAnalytics.$label failed: $e');
    }
  }

  /// A completed, paid-for order. Fires once per real order, never on a failed
  /// or abandoned one.
  static Future<void> logPurchase({
    required int totalRupees,
    required int itemCount,
    required String paymentMode,
    String? orderId,
  }) {
    return _run('logPurchase', () async {
      await _fa.logPurchase(
        currency: 'INR',
        value: totalRupees.toDouble(),
        transactionId: orderId,
        parameters: <String, Object>{
          'item_count': itemCount,
          'payment_mode': paymentMode,
        },
      );
    });
  }

  /// A dish added to the cart.
  static Future<void> logAddToCart({
    required String dishName,
    required int priceRupees,
  }) {
    return _run('logAddToCart', () async {
      await _fa.logAddToCart(
        currency: 'INR',
        value: priceRupees.toDouble(),
        items: <AnalyticsEventItem>[
          AnalyticsEventItem(
            itemName: dishName,
            price: priceRupees.toDouble(),
            currency: 'INR',
            quantity: 1,
          ),
        ],
      );
    });
  }

  /// The customer reached checkout with a cart. Fires before payment, so
  /// abandoned checkouts are counted too.
  static Future<void> logBeginCheckout({
    required int totalRupees,
    required int itemCount,
  }) {
    return _run('logBeginCheckout', () async {
      await _fa.logBeginCheckout(
        currency: 'INR',
        value: totalRupees.toDouble(),
        parameters: <String, Object>{'item_count': itemCount},
      );
    });
  }
}
