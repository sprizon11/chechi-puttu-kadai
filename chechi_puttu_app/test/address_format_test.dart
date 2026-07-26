import 'package:chechi_puttu_app/services/address_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatNominatimAddress', () {
    test('assembles road, area, city, postcode, state', () {
      final line = formatNominatimAddress({
        'house_number': '12',
        'road': 'Cross Cut Road',
        'suburb': 'Gandhipuram',
        'city': 'Coimbatore',
        'postcode': '641012',
        'state': 'Tamil Nadu',
      });
      expect(line, '12 Cross Cut Road, Gandhipuram, Coimbatore, 641012, Tamil Nadu');
    });

    test('keeps a POI name ahead of the road', () {
      final line = formatNominatimAddress({
        'hospital': 'KG Hospital',
        'road': 'Arts College Road',
        'city': 'Coimbatore',
      });
      expect(line, startsWith('KG Hospital, Arts College Road'));
    });

    test('drops Plus codes', () {
      final line = formatNominatimAddress({
        'road': '2G7Q+8X',
        'suburb': 'Peelamedu',
        'city': 'Coimbatore',
      });
      expect(line, 'Peelamedu, Coimbatore');
    });

    test('de-duplicates repeated names', () {
      final line = formatNominatimAddress({
        'city': 'Coimbatore',
        'state_district': 'Coimbatore',
        'state': 'Tamil Nadu',
      });
      expect(line, 'Coimbatore, Tamil Nadu');
    });

    test('returns empty when nothing usable', () {
      expect(formatNominatimAddress({'country': 'India'}), '');
    });
  });

  group('formatPlacemarkParts', () {
    test('joins road with area and city, dropping duplicate name', () {
      final line = formatPlacemarkParts(
        name: 'Cross Cut Road',
        thoroughfare: 'Cross Cut Road',
        subLocality: 'Gandhipuram',
        locality: 'Coimbatore',
        postalCode: '641012',
        administrativeArea: 'Tamil Nadu',
      );
      expect(line, 'Cross Cut Road, Gandhipuram, Coimbatore, 641012, Tamil Nadu');
    });

    test('keeps a distinct POI name', () {
      final line = formatPlacemarkParts(
        name: 'Brookefields Mall',
        thoroughfare: 'Brookebond Road',
        locality: 'Coimbatore',
      );
      expect(line, startsWith('Brookefields Mall, Brookebond Road'));
    });
  });
}
