import 'dart:math' as math;

/// Delivery is Coimbatore-only. Orders outside the service radius are refused
/// at the map picker and again at checkout, because an address can be restored
/// from storage or typed without ever passing through the picker.
abstract final class DeliveryArea {
  /// Coimbatore city centre.
  static const double centerLatitude = 11.0168;
  static const double centerLongitude = 76.9558;

  /// Generous enough to cover the suburbs people actually order from
  /// (Saravanampatti, Peelamedu, Singanallur, Kurichi, Podanur) without
  /// reaching neighbouring cities — Tiruppur is ~50 km out.
  static const double radiusKm = 30;

  static const String cityName = 'Coimbatore';

  /// Shown whenever an address is refused. One wording everywhere.
  static const String outsideMessage =
      'We currently deliver in Coimbatore only. '
      'Please choose a delivery address inside Coimbatore.';

  static const double _earthRadiusKm = 6371.0088;

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Great-circle distance in km. Haversine is well past accurate enough at
  /// city scale, and needs no plugin.
  static double distanceFromCentreKm(double latitude, double longitude) {
    final dLat = _toRadians(latitude - centerLatitude);
    final dLng = _toRadians(longitude - centerLongitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(centerLatitude)) *
            math.cos(_toRadians(latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return _earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static bool isWithinServiceArea(double latitude, double longitude) =>
      distanceFromCentreKm(latitude, longitude) <= radiusKm;

  /// Cities close enough that a customer might plausibly try one, and far
  /// enough that delivery is impossible.
  static const List<String> _knownOutsideCities = [
    'tiruppur',
    'tirupur',
    'erode',
    'salem',
    'madurai',
    'chennai',
    'trichy',
    'tiruchirappalli',
    'palakkad',
    'thrissur',
    'kochi',
    'ernakulam',
    'bengaluru',
    'bangalore',
    'mysuru',
    'mysore',
    'ooty',
    'udhagamandalam',
  ];

  /// Text fallback for addresses saved before coordinates were captured.
  ///
  /// Deliberately one-directional: a missing "Coimbatore" proves nothing (many
  /// valid addresses are just a street and pincode), so this only refuses an
  /// address that *names another city*. Coordinates remain authoritative.
  static bool looksOutsideServiceArea(String address) {
    final lower = address.toLowerCase();
    if (lower.contains(cityName.toLowerCase())) return false;
    return _knownOutsideCities.any(lower.contains);
  }
}
