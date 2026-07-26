import 'package:chechi_puttu_app/services/delivery_area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isWithinServiceArea', () {
    test('accepts Coimbatore city and its suburbs', () {
      expect(DeliveryArea.isWithinServiceArea(11.0168, 76.9558), isTrue);
      expect(DeliveryArea.isWithinServiceArea(11.0780, 76.9997), isTrue);
      expect(DeliveryArea.isWithinServiceArea(11.0299, 77.0270), isTrue);
      expect(DeliveryArea.isWithinServiceArea(10.9430, 76.9630), isTrue);
    });

    test('rejects other cities', () {
      expect(DeliveryArea.isWithinServiceArea(11.1085, 77.3411), isFalse);
      expect(DeliveryArea.isWithinServiceArea(11.3410, 77.7172), isFalse);
      expect(DeliveryArea.isWithinServiceArea(13.0827, 80.2707), isFalse);
      expect(DeliveryArea.isWithinServiceArea(12.9716, 77.5946), isFalse);
      expect(DeliveryArea.isWithinServiceArea(10.7867, 76.6548), isFalse);
    });

    test('measures a known distance correctly', () {
      final km = DeliveryArea.distanceFromCentreKm(11.1085, 77.3411);
      expect(km, greaterThan(40));
      expect(km, lessThan(50));
    });
  });

  group('looksOutsideServiceArea', () {
    test('refuses an address naming another city', () {
      expect(
        DeliveryArea.looksOutsideServiceArea('12 Main Rd, Tiruppur, 641601'),
        isTrue,
      );
    });

    test('allows a Coimbatore address even when it names another city road', () {
      expect(
        DeliveryArea.looksOutsideServiceArea(
          'Mettupalayam Road, Coimbatore, 641043',
        ),
        isFalse,
      );
      expect(
        DeliveryArea.looksOutsideServiceArea('Trichy Road, Coimbatore'),
        isFalse,
      );
    });

    test('does not refuse an address that simply omits the city', () {
      expect(
        DeliveryArea.looksOutsideServiceArea('12 Cross Cut Road, 641012'),
        isFalse,
      );
    });
  });
}
