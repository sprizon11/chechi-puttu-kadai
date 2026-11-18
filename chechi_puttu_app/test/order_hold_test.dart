import 'package:chechi_puttu_app/services/order_hold_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderHold.isHoldingAt', () {
    test('is off when admin never turned it on', () {
      expect(const OrderHold().isHoldingAt(DateTime(2026, 9, 1)), false);
    });

    test('holds indefinitely when no resume date is set', () {
      const hold = OrderHold(active: true, message: 'Kitchen on leave');
      expect(hold.isHoldingAt(DateTime(2027, 1, 1)), true);
    });

    test('holds right up to midnight on the resume day', () {
      final hold = OrderHold(active: true, resumeOn: DateTime(2026, 9, 3));
      expect(hold.isHoldingAt(DateTime(2026, 9, 2, 23, 59)), true);
    });

    test('lifts by itself on the resume day', () {
      final hold = OrderHold(active: true, resumeOn: DateTime(2026, 9, 3));
      expect(hold.isHoldingAt(DateTime(2026, 9, 3, 0, 1)), false);
      expect(hold.isHoldingAt(DateTime(2026, 9, 4)), false);
    });

    test('a resume time of day does not delay the lift', () {
      final hold =
          OrderHold(active: true, resumeOn: DateTime(2026, 9, 3, 18, 30));
      expect(hold.isHoldingAt(DateTime(2026, 9, 3, 6)), false);
    });
  });

  group('OrderHold message', () {
    test('falls back to a default when admin typed nothing', () {
      expect(
        const OrderHold(active: true).customerMessage,
        OrderHold.defaultMessage,
      );
      expect(
        const OrderHold(active: true, message: '   ').customerMessage,
        OrderHold.defaultMessage,
      );
    });

    test('uses the admin reason when there is one', () {
      expect(
        const OrderHold(active: true, message: ' Orders full  ').customerMessage,
        'Orders full',
      );
    });
  });

  group('OrderHold.fromMap', () {
    test('reads an ISO string resume date', () {
      final hold = OrderHold.fromMap({
        'active': true,
        'message': 'Back Thursday',
        'resume_on': '2026-09-03T00:00:00.000',
      });
      expect(hold.active, true);
      expect(hold.resumeOn, DateTime(2026, 9, 3));
    });

    test('an unreadable resume date leaves the hold manual, not off', () {
      final hold = OrderHold.fromMap({'active': true, 'resume_on': 'soon'});
      expect(hold.active, true);
      expect(hold.resumeOn, isNull);
      expect(hold.isHoldingAt(DateTime(2030, 1, 1)), true);
    });

    test('a missing doc means orders are open', () {
      expect(OrderHold.fromMap(null).isHoldingAt(DateTime(2026, 9, 1)), false);
    });

    test('caps an over-long message', () {
      final hold = OrderHold.fromMap({
        'active': true,
        'message': 'x' * 500,
      });
      expect(hold.message.length, OrderHold.maxMessageLength);
    });
  });

  group('OrderHold advance bookings', () {
    final hold = OrderHold(
      active: true,
      resumeOn: DateTime(2026, 12, 1),
      allowAdvanceBooking: true,
    );
    final now = DateTime(2026, 11, 18, 10);

    test('refuses delivery days before the resume date', () {
      expect(hold.allowsDeliveryOn(DateTime(2026, 11, 30), now), false);
    });

    test('accepts the resume day and later', () {
      expect(hold.allowsDeliveryOn(DateTime(2026, 12, 1), now), true);
      expect(hold.allowsDeliveryOn(DateTime(2026, 12, 9), now), true);
    });

    test('refuses every day when advance bookings are off', () {
      final strict = hold.copyWith(allowAdvanceBooking: false);
      expect(strict.allowsDeliveryOn(DateTime(2026, 12, 5), now), false);
      expect(strict.takesAdvanceBookings, false);
    });

    test('an open-ended hold never takes advance bookings', () {
      const open = OrderHold(active: true, allowAdvanceBooking: true);
      expect(open.takesAdvanceBookings, false);
      expect(open.allowsDeliveryOn(DateTime(2027, 1, 1), now), false);
    });

    test('every day is fine once the hold has lifted', () {
      expect(
        hold.allowsDeliveryOn(DateTime(2026, 12, 2), DateTime(2026, 12, 1, 7)),
        true,
      );
    });

    test('reads allow_advance_booking from Firestore', () {
      final read = OrderHold.fromMap({
        'active': true,
        'resume_on': '2026-12-01T00:00:00.000',
        'allow_advance_booking': true,
      });
      expect(read.takesAdvanceBookings, true);
      expect(read.resumeDay, DateTime(2026, 12, 1));
    });
  });
}
