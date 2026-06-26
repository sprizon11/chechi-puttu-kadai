import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One meal window for next-day (or later) delivery booking.
class AdvanceMealSlot {
  const AdvanceMealSlot({
    required this.id,
    required this.label,
    required this.startHour,
    required this.endHour,
  });

  final String id;
  final String label;
  final int startHour;
  final int endHour;
}

/// Customer-selected date + meal slot (always at least 1 day ahead).
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

  String get mealName {
    switch (slot.id) {
      case 'breakfast':
        return 'Breakfast';
      case 'lunch':
        return 'Lunch';
      case 'dinner':
        return 'Dinner';
      default:
        return slot.label;
    }
  }
}

/// Chechi Puttu Kadai — all orders must be booked ≥ 1 day before delivery.
class AdvanceOrderSchedule {
  AdvanceOrderSchedule._();

  static const advanceDays = 1;
  static const maxBookAheadDays = 30;

  static const mealSlots = <AdvanceMealSlot>[
    AdvanceMealSlot(
      id: 'breakfast',
      label: 'Breakfast · 8:00–10:00 AM',
      startHour: 8,
      endHour: 10,
    ),
    AdvanceMealSlot(
      id: 'lunch',
      label: 'Lunch · 12:00–2:00 PM',
      startHour: 12,
      endHour: 14,
    ),
    AdvanceMealSlot(
      id: 'dinner',
      label: 'Dinner · 6:00–9:00 PM',
      startHour: 18,
      endHour: 21,
    ),
  ];

  /// Earliest calendar day customers can choose (tomorrow).
  static DateTime earliestDeliveryDay([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.add(const Duration(days: advanceDays));
  }

  /// Returns a hint based on current time.
  static String policySummary() {
    final now = DateTime.now();
    if (now.hour < 12) {
      return 'Order before 12 PM → all slots available tomorrow (breakfast, lunch, dinner).';
    } else if (now.hour < 18) {
      return 'Order after 12 PM → tomorrow breakfast not available. Lunch & dinner available.';
    } else {
      return 'Order after 6 PM → tomorrow dinner only. Pick a later date for more slots.';
    }
  }

  /// Returns which slots are available for the given delivery day.
  /// Rules:
  ///   Before 12 PM  → tomorrow: Breakfast, Lunch, Dinner
  ///   12 PM–6 PM    → tomorrow: Lunch, Dinner only
  ///   After 6 PM    → tomorrow: Dinner only
  ///   Any later date → always all 3 slots
  static List<AdvanceMealSlot> availableSlotsFor(DateTime deliveryDay) {
    final now = DateTime.now();
    final tomorrow = earliestDeliveryDay(now);
    final isTomorrow = deliveryDay.year == tomorrow.year &&
        deliveryDay.month == tomorrow.month &&
        deliveryDay.day == tomorrow.day;
    if (isTomorrow) {
      if (now.hour >= 18) {
        // After 6 PM — dinner only
        return [mealSlots.firstWhere((s) => s.id == 'dinner')];
      } else if (now.hour >= 12) {
        // After 12 PM — no breakfast
        return mealSlots.where((s) => s.id != 'breakfast').toList();
      }
    }
    return mealSlots;
  }

  /// Date picker + breakfast / lunch / dinner sheet.
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
    final slots = availableSlotsFor(deliveryDay);

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
                  policySummary(),
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
                    onTap: () => Navigator.pop(ctx, s),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || slot == null) return null;

    final when = DateTime(
      deliveryDay.year,
      deliveryDay.month,
      deliveryDay.day,
      slot.startHour,
    );
    return AdvanceMealBooking(
      deliveryDate: deliveryDay,
      slot: slot,
      when: when,
    );
  }
}
