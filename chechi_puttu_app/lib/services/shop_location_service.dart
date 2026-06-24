import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Kadai / shop pin saved by admin — used as map default center and delivery routes.
class ShopLocation {
  const ShopLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;

  static ShopLocation? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final address = (data['address'] as String?)?.trim() ?? '';
    if (address.isEmpty) return null;
    final name = (data['name'] as String?)?.trim();
    return ShopLocation(
      name: (name != null && name.isNotEmpty) ? name : 'Chechi Puttu Kadai',
      address: address,
      latitude: lat,
      longitude: lng,
    );
  }
}

class ShopLocationService {
  ShopLocationService._();

  static const _docId = 'shop_location';

  static DocumentReference<Map<String, dynamic>> get _ref =>
      chechiFirestore.collection('admin_public').doc(_docId);

  static Future<ShopLocation?> load() async {
    try {
      final snap = await _ref.get();
      return ShopLocation.fromMap(snap.data());
    } catch (_) {
      return null;
    }
  }

  static Stream<ShopLocation?> watch() {
    return _ref.snapshots().map((snap) => ShopLocation.fromMap(snap.data()));
  }

  static Future<void> save({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    String? updatedByUid,
  }) async {
    final cleanName = name.trim().isEmpty ? 'Chechi Puttu Kadai' : name.trim();
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) {
      throw StateError('Address is required');
    }
    await _ref.set({
      'name': cleanName,
      'address': cleanAddress,
      'latitude': latitude,
      'longitude': longitude,
      'location_geo': GeoPoint(latitude, longitude),
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedByUid != null && updatedByUid.isNotEmpty)
        'updatedBy': updatedByUid,
    }, SetOptions(merge: true));
  }
}
