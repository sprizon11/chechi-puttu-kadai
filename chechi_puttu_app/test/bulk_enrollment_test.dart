import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BulkOrderEnrollment.fromMap', () {
    test('backfills quantities for plans saved before quantities existed', () {
      final e = BulkOrderEnrollment.fromMap({
        'selectedDishes': ['Rice Puttu', 'Kadala Curry'],
      });
      expect(e.dishQuantities, {
        'Rice Puttu': kDefaultDishQuantity,
        'Kadala Curry': kDefaultDishQuantity,
      });
      expect(e.totalPortions, kDefaultDishQuantity * 2);
    });

    test('reads stored quantities and keeps titles in sync', () {
      final e = BulkOrderEnrollment.fromMap({
        'selectedDishes': ['Rice Puttu'],
        'dishQuantities': {'Rice Puttu': 60},
      });
      expect(e.dishQuantities['Rice Puttu'], 60);
      expect(e.totalPortions, 60);
    });

    test('drops non-positive and unparseable quantities', () {
      final e = BulkOrderEnrollment.fromMap({
        'selectedDishes': <String>[],
        'dishQuantities': {'A': 0, 'B': -5, 'C': 'abc', 'D': 12},
      });
      expect(e.dishQuantities, {'D': 12});
    });

    test('round-trips through toFirestore', () {
      const original = BulkOrderEnrollment(
        selectedDishes: ['Rice Puttu'],
        dishQuantities: {'Rice Puttu': 25},
      );
      final restored = BulkOrderEnrollment.fromMap(original.toFirestore());
      expect(restored.dishQuantities, {'Rice Puttu': 25});
    });
  });

  group('BulkOrderEnrollment meal times', () {
    test('reads a per-meal time map', () {
      final e = BulkOrderEnrollment.fromMap({
        'mealSlots': ['breakfast', 'dinner'],
        'mealTimes': {'breakfast': '8:00 AM', 'dinner': '8:00 PM'},
      });
      expect(e.mealSlots, ['breakfast', 'dinner']);
      expect(e.mealTimes, {'breakfast': '8:00 AM', 'dinner': '8:00 PM'});
    });

    test('drops blank times so a meal never looks scheduled when it is not',
        () {
      final e = BulkOrderEnrollment.fromMap({
        'mealSlots': ['breakfast', 'lunch'],
        'mealTimes': {'breakfast': '8:00 AM', 'lunch': '   '},
      });
      expect(e.mealTimes, {'breakfast': '8:00 AM'});
    });

    test('plans saved before per-meal times keep their single time', () {
      final e = BulkOrderEnrollment.fromMap({
        'mealSlots': ['lunch'],
        'preferredTime': '1:00 PM',
      });
      expect(e.mealTimes, isEmpty);
      expect(e.preferredTime, '1:00 PM');
    });

    test('round-trips meal times through toFirestore', () {
      const original = BulkOrderEnrollment(
        mealSlots: ['breakfast'],
        mealTimes: {'breakfast': '7:30 AM'},
        preferredTime: 'Breakfast 7:30 AM',
      );
      final restored = BulkOrderEnrollment.fromMap(original.toFirestore());
      expect(restored.mealTimes, {'breakfast': '7:30 AM'});
      expect(restored.preferredTime, 'Breakfast 7:30 AM');
    });
  });
}
