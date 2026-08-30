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
}
