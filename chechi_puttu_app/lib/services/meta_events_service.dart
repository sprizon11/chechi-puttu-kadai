import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

import 'package:chechi_puttu_app/app_secrets.dart';

/// Meta (Facebook) app events, used by the ads team for install and purchase
/// attribution.
///
/// Every method here is best effort. Ad reporting is never worth failing an
/// order over, so nothing throws: a missing configuration, an offline phone or
/// an SDK error all end up as a silent no-op. Call sites deliberately do not
/// await these calls on the path that shows the customer their confirmation.
abstract final class MetaEvents {
  static final FacebookAppEvents _fb = FacebookAppEvents();

  /// Standard event names, spelled the way Meta's dashboard expects them.
  static const String _purchase = 'fb_mobile_purchase';
  static const String _addToCart = 'fb_mobile_add_to_cart';
  static const String _initiateCheckout = 'fb_mobile_initiated_checkout';

  static Future<void> _run(String label, Future<void> Function() body) async {
    if (!MetaConfig.isConfigured) return;
    try {
      await body();
    } catch (e) {
      // Swallow: analytics must never surface to the customer or abort an
      // order. Logged only in debug so integration problems stay findable.
      debugPrint('MetaEvents.$label failed: $e');
    }
  }

  /// A completed, paid-for order. This is the event the ad campaigns optimise
  /// against, so it must fire once per real order and never on a failed or
  /// abandoned one.
  ///
  /// [totalRupees] is the amount the customer actually pays, including delivery
  /// and packing, matching what the order document records.
  static Future<void> logPurchase({
    required int totalRupees,
    required int itemCount,
    required String paymentMode,
    String? orderId,
  }) {
    return _run('logPurchase', () async {
      await _fb.logPurchase(
        amount: totalRupees.toDouble(),
        currency: 'INR',
        parameters: <String, dynamic>{
          'fb_num_items': itemCount,
          'payment_mode': paymentMode,
          if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
        },
      );
    });
  }

  /// A dish added to the cart. Useful to Meta as an upper-funnel signal while
  /// purchase volume is still too low to optimise on.
  static Future<void> logAddToCart({
    required String dishName,
    required int priceRupees,
  }) {
    return _run('logAddToCart', () async {
      await _fb.logEvent(
        name: _addToCart,
        parameters: <String, dynamic>{
          'fb_content_type': 'product',
          'fb_content_id': dishName,
          'fb_currency': 'INR',
        },
        valueToSum: priceRupees.toDouble(),
      );
    });
  }

  /// The customer reached checkout with a cart. Fires before payment, so it
  /// counts abandoned checkouts too — that is intentional.
  static Future<void> logInitiateCheckout({
    required int totalRupees,
    required int itemCount,
  }) {
    return _run('logInitiateCheckout', () async {
      await _fb.logEvent(
        name: _initiateCheckout,
        parameters: <String, dynamic>{
          'fb_num_items': itemCount,
          'fb_currency': 'INR',
        },
        valueToSum: totalRupees.toDouble(),
      );
    });
  }

  /// Named so the constants above are not flagged as unused while only some of
  /// the events are wired up.
  static const String purchaseEventName = _purchase;
  static const String addToCartEventName = _addToCart;
  static const String initiateCheckoutEventName = _initiateCheckout;
}
