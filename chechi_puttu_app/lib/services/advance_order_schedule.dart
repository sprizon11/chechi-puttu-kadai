import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One meal window customers can book, with the cut-off that closes it.
///
/// Cut-off is expressed as "[cutoffDaysBefore] day(s) before the delivery day,
/// at [cutoffHour]:[cutoffMinute]":
///   Breakfast → 1 day before, 5:00 PM
///   Lunch     → 1 day before, 7:00 PM
///   Dinner    → same day, 11:00 AM
class AdvanceMealSlot {
  const AdvanceMealSlot({
    required this.id,
    required this.name,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.cutoffDaysBefore,
    required this.cutoffHour,
    required this.cutoffMinute,
  });

  final String id;
  final String name;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  /// 1 = orders close the previous day, 0 = orders close the same morning.
  final int cutoffDaysBefore;
  final int cutoffHour;
  final int cutoffMinute;

  /// e.g. `8:30 – 9:30 AM`
  String get windowLabel =>
      '${_clock(startHour, startMinute)} – ${_clock(endHour, endMinute)}';

  /// e.g. `Breakfast · 8:30 – 9:30 AM`
  String get label => '$name · $windowLabel';

  /// e.g. `Order by 5:00 PM the previous day`
  String get cutoffLabel => cutoffDaysBefore <= 0
      ? 'Order by ${_clock(cutoffHour, cutoffMinute)} the same day'
      : 'Order by ${_clock(cutoffHour, cutoffMinute)} the previous day';

  /// Last moment an order for [deliveryDay] can be placed.
  DateTime cutoffFor(DateTime deliveryDay) {
    final day = DateTime(deliveryDay.year, deliveryDay.month, deliveryDay.day)
        .subtract(Duration(days: cutoffDaysBefore));
    return DateTime(day.year, day.month, day.day, cutoffHour, cutoffMinute);
  }

  /// Delivery start time on [deliveryDay].
  DateTime deliveryStartOn(DateTime deliveryDay) => DateTime(
        deliveryDay.year,
        deliveryDay.month,
        deliveryDay.day,
        startHour,
        startMinute,
      );

  bool isOpenFor(DateTime deliveryDay, [DateTime? now]) =>
      (now ?? DateTime.now()).isBefore(cutoffFor(deliveryDay));

  static String _clock(int hour, int minute) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final mm = minute.toString().padLeft(2, '0');
    return '$h12:$mm $suffix';
  }
}

/// Customer-selected date + meal slot.
class AdvanceMealBooking {
  const AdvanceMealBooking({
    required this.deliveryDate,
    required this.slot,
    required this.when,
  });

  final DateTime deliveryDate;
  final AdvanceMealSlot slot;
  final DateTime when;

  String get displayLine {
    final d = deliveryDate;
    return 'Booked for ${d.day}/${d.month}/${d.year} · ${slot.label}';
  }

  String get mealName => slot.name;
}

/// Chechi Puttu Kadai delivery windows and their order cut-offs.
class AdvanceOrderSchedule {
  AdvanceOrderSchedule._();

  static const maxBookAheadDays = 30;

  static const mealSlots = <AdvanceMealSlot>[
    AdvanceMealSlot(
      id: 'breakfast',
      name: 'Breakfast',
      startHour: 8,
      startMinute: 30,
      endHour: 9,
      endMinute: 30,
      cutoffDaysBefore: 1,
      cutoffHour: 17,
      cutoffMinute: 0,
    ),
    AdvanceMealSlot(
      id: 'lunch',
      name: 'Lunch',
      startHour: 12,
      startMinute: 30,
      endHour: 13,
      endMinute: 30,
      cutoffDaysBefore: 1,
      cutoffHour: 19,
      cutoffMinute: 0,
    ),
    AdvanceMealSlot(
      id: 'dinner',
      name: 'Dinner',
      startHour: 19,
      startMinute: 30,
      endHour: 20,
      endMinute: 30,
      cutoffDaysBefore: 0,
      cutoffHour: 11,
      cutoffMinute: 0,
    ),
  ];

  /// Returns which slots can still be ordered for [deliveryDay].
  static List<AdvanceMealSlot> availableSlotsFor(
    DateTime deliveryDay, [
    DateTime? from,
  ]) {
    final now = from ?? DateTime.now();
    return mealSlots.where((s) => s.isOpenFor(deliveryDay, now)).toList();
  }

  /// Earliest calendar day that still has at least one open slot. Dinner closes
  /// at 11 AM the same day, so today qualifies before 11 AM.
  static DateTime earliestDeliveryDay([DateTime? from]) {
    final now = from ?? DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    for (var i = 0; i <= maxBookAheadDays; i++) {
      if (availableSlotsFor(day, now).isNotEmpty) return day;
      day = day.add(const Duration(days: 1));
    }
    return DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
  }

  /// True while [booking] can still be placed.
  ///
  /// The picker checks the cut-off when the slot is chosen, but choosing a
  /// payment method and completing it can take minutes. Call this again
  /// immediately before money is taken or the order is written — a slot that
  /// closed in between is one the kitchen cannot cook.
  static bool isBookingOpen(AdvanceMealBooking booking, [DateTime? now]) =>
      booking.slot.isOpenFor(booking.deliveryDate, now);

  /// The three fixed rules, for info panels.
  static List<String> ruleLines() => [
        for (final s in mealSlots) '${s.name} ${s.windowLabel} — ${s.cutoffLabel}',
      ];

  /// Short hint for the cart: what can still be booked next.
  static String policySummary([DateTime? from]) {
    final now = from ?? DateTime.now();
    final day = earliestDeliveryDay(now);
    final slots = availableSlotsFor(day, now);
    if (slots.isEmpty) return 'Delivery slots open again soon.';
    final names = slots.map((s) => s.name.toLowerCase()).join(', ');
    return 'Next delivery ${_dayWord(day, now).toLowerCase()} — $names. '
        'Breakfast/lunch close 5 PM/7 PM the day before; dinner closes 11 AM same day.';
  }

  static String _dayWord(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(day.year, day.month, day.day).difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${day.day}/${day.month}/${day.year}';
  }

  /// Date picker + meal sheet. Days with no open slot are not selectable.
  static Future<AdvanceMealBooking?> pickMealBooking(BuildContext context) async {
    final now = DateTime.now();
    final firstDay = earliestDeliveryDay(now);
    final lastDay = firstDay.add(const Duration(days: maxBookAheadDays));

    final date = await showDatePicker(
      context: context,
      initialDate: firstDay,
      firstDate: firstDay,
      lastDate: lastDay,
      helpText: 'Pick delivery day',
      cancelText: 'Cancel',
      confirmText: 'Next',
      selectableDayPredicate: (d) => availableSlotsFor(d, now).isNotEmpty,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: const Color(0xFF7C1D1B),
                ),
          ),
          child: child!,
        );
      },
    );
    if (!context.mounted || date == null) return null;

    final deliveryDay = DateTime(date.year, date.month, date.day);
    final slots = availableSlotsFor(deliveryDay, now);

    final slot = await showModalBottomSheet<AdvanceMealSlot>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final dayLabel =
            '${deliveryDay.day}/${deliveryDay.month}/${deliveryDay.year}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose meal for $dayLabel',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ruleLines().join('\n'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                for (final s in slots) ...[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    leading: Icon(
                      s.id == 'breakfast'
                          ? Icons.wb_sunny_outlined
                          : s.id == 'lunch'
                              ? Icons.lunch_dining_outlined
                              : Icons.nightlight_round,
                      color: const Color(0xFF7C1D1B),
                    ),
                    title: Text(
                      s.label,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      s.cutoffLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, s),
                  ),
                  const SizedBox(height: 8),
                ],
                if (slots.isEmpty)
                  Text(
                    'Ordering has closed for this day. Please pick a later date.',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || slot == null) return null;

    // Re-check the cut-off: the sheet may have been open across it.
    if (!slot.isOpenFor(deliveryDay)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ordering for ${slot.name.toLowerCase()} on that day just closed. '
            'Please pick another slot.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return null;
    }

    return AdvanceMealBooking(
      deliveryDate: deliveryDay,
      slot: slot,
      when: slot.deliveryStartOn(deliveryDay),
    );
  }
}
