import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-order delivery + packing charges, set by admin in Settings.
class OrderCharges {
  const OrderCharges({
    required this.deliveryRupees,
    required this.packingRupees,
  });

  /// Applied to every order until admin changes them.
  static const defaults = OrderCharges(deliveryRupees: 40, packingRupees: 20);

  final int deliveryRupees;
  final int packingRupees;

  int get totalRupees => deliveryRupees + packingRupees;

  static OrderCharges fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return OrderCharges(
      deliveryRupees:
          _asRupees(data['delivery_rupees'], defaults.deliveryRupees),
      packingRupees: _asRupees(data['packing_rupees'], defaults.packingRupees),
    );
  }

  static int _asRupees(Object? raw, int fallback) {
    final v = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    if (v == null || v < 0) return fallback;
    return v;
  }
}

/// Reads/writes `admin_public/order_charges`. Customers read it at checkout,
/// admin edits it from Settings → Business Settings → Order Charges.
class OrderChargesService {
  OrderChargesService._();

  static const _docId = 'order_charges';

  /// Last value seen this session — lets the cart paint the right amounts on
  /// first frame instead of flashing the defaults.
  static OrderCharges cached = OrderCharges.defaults;

  static DocumentReference<Map<String, dynamic>> get _ref =>
      chechiFirestore.collection('admin_public').doc(_docId);

  static Future<OrderCharges> load() async {
    try {
      final snap = await _ref.get();
      final charges = OrderCharges.fromMap(snap.data());
      cached = charges;
      return charges;
    } catch (_) {
      return cached;
    }
  }

  static Stream<OrderCharges> watch() {
    return _ref.snapshots().map((snap) {
      final charges = OrderCharges.fromMap(snap.data());
      cached = charges;
      return charges;
    });
  }

  static Future<void> save({
    required int deliveryRupees,
    required int packingRupees,
    String? updatedByUid,
  }) async {
    if (deliveryRupees < 0 || packingRupees < 0) {
      throw StateError('Charges cannot be negative');
    }
    await _ref.set({
      'delivery_rupees': deliveryRupees,
      'packing_rupees': packingRupees,
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedByUid != null && updatedByUid.isNotEmpty)
        'updatedBy': updatedByUid,
    }, SetOptions(merge: true));
    cached = OrderCharges(
      deliveryRupees: deliveryRupees,
      packingRupees: packingRupees,
    );
  }
}
