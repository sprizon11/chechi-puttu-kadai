/// Turns a reverse-geocode result into a human address line.
///
/// The picker showed "only the road" because it stopped at the first couple of
/// fields; this walks the full India-relevant hierarchy (POI → house/road →
/// neighbourhood → area → city → district → postcode → state), skips Plus
/// codes, and de-duplicates repeated names so the customer sees road *and*
/// area *and* city rather than a bare street.
library;

final RegExp _plusCode = RegExp(r'^[0-9A-Z]{4}\+[0-9A-Z]{2,}$');

bool _isPlusCode(String s) => _plusCode.hasMatch(s);

/// Formats a Nominatim `address` object (from `/reverse?addressdetails=1`).
/// Returns an empty string when nothing usable is present, so callers can fall
/// back to `display_name` or the OS geocoder.
String formatNominatimAddress(Map<String, dynamic> address) {
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = address[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  // A house number is only meaningful glued to its road.
  final houseNumber = pick(['house_number']);
  final road = pick(['road', 'pedestrian', 'residential', 'footway']);
  final houseAndRoad = <String>[
    ?houseNumber,
    ?road,
  ].join(' ');

  final ordered = <String?>[
    pick(['amenity', 'shop', 'building', 'office', 'hospital', 'college']),
    houseAndRoad.isEmpty ? null : houseAndRoad,
    pick(['neighbourhood', 'suburb', 'quarter', 'hamlet']),
    pick(['city_district', 'district']),
    pick(['village', 'town', 'city', 'municipality']),
    pick(['county', 'state_district']),
    pick(['postcode']),
    pick(['state']),
  ];

  return _joinDedup(ordered);
}

/// Joins OS-geocoder placemark fields, in the same India-friendly order.
String formatPlacemarkParts({
  String? name,
  String? subThoroughfare,
  String? thoroughfare,
  String? subLocality,
  String? locality,
  String? subAdministrativeArea,
  String? administrativeArea,
  String? postalCode,
}) {
  final houseAndRoad = <String>[
    if (_ok(subThoroughfare)) subThoroughfare!.trim(),
    if (_ok(thoroughfare)) thoroughfare!.trim(),
  ].join(' ');

  return _joinDedup(<String?>[
    // `name` often duplicates the road; only keep it when it adds a POI.
    (_ok(name) && name!.trim() != thoroughfare?.trim()) ? name.trim() : null,
    houseAndRoad.isEmpty ? null : houseAndRoad,
    subLocality,
    locality,
    subAdministrativeArea,
    postalCode,
    administrativeArea,
  ]);
}

bool _ok(String? s) => s != null && s.trim().isNotEmpty;

/// Joins non-empty parts with ", ", dropping Plus codes and any part whose
/// text already appears in an earlier part (case-insensitive).
String _joinDedup(List<String?> parts) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in parts) {
    if (raw == null) continue;
    final t = raw.trim();
    if (t.isEmpty || _isPlusCode(t)) continue;
    final key = t.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(t);
  }
  return out.join(', ');
}
