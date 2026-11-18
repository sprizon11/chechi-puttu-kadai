import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether the kitchen is currently taking orders, and what to tell customers
/// when it is not.
///
/// Used when the kitchen is on leave, or already full for the next few days —
/// the shop stays browsable, but checkout is refused with [message].
class OrderHold {
  const OrderHold({
    this.active = false,
    this.message = '',
    this.resumeOn,
    this.allowAdvanceBooking = false,
  });

  static const off = OrderHold();

  /// Shown when admin turned the hold on without typing anything.
  static const defaultMessage =
      'We are not accepting new orders right now. Please check back soon.';

  /// Longest message admin can save — long enough for a real explanation,
  /// short enough to read in a dialog.
  static const maxMessageLength = 500;

  /// Admin flipped the switch on. Not the same as [isHoldingAt] — a hold with
  /// a [resumeOn] date in the past is over.
  final bool active;

  /// Reason customers see. Empty means [defaultMessage] is shown instead.
  final String message;

  /// Date the kitchen starts taking orders again, at midnight. Null means the
  /// hold stays until admin turns it off by hand.
  final DateTime? resumeOn;

  /// While held, customers may still book a delivery on or after [resumeOn].
  /// Ignored when there is no resume date — an open-ended hold refuses all.
  final bool allowAdvanceBooking;

  /// Midnight on the resume day, or null.
  DateTime? get resumeDay {
    final r = resumeOn;
    return r == null ? null : DateTime(r.year, r.month, r.day);
  }

  /// True when a held kitchen still takes bookings for [resumeDay] onwards.
  bool get takesAdvanceBookings => allowAdvanceBooking && resumeOn != null;

  /// Whether a delivery on [deliveryDay] can be booked at [now]. Outside a
  /// hold every day is fine; inside one only days from [resumeDay] on, and
  /// only when [allowAdvanceBooking] is on.
  bool allowsDeliveryOn(DateTime deliveryDay, [DateTime? now]) {
    if (!isHoldingAt(now)) return true;
    final resume = resumeDay;
    if (!allowAdvanceBooking || resume == null) return false;
    final day = DateTime(deliveryDay.year, deliveryDay.month, deliveryDay.day);
    return !day.isBefore(resume);
  }

  /// The text a customer should actually be shown.
  String get customerMessage =>
      message.trim().isEmpty ? defaultMessage : message.trim();

  /// True while orders must be refused. A [resumeOn] date lifts the hold on
  /// its own that morning, so admin does not have to remember to switch it
  /// back — which is the whole point for a planned leave.
  bool isHoldingAt([DateTime? now]) {
    if (!active) return false;
    final resume = resumeOn;
    if (resume == null) return true;
    final at = now ?? DateTime.now();
    final startOfResumeDay = DateTime(resume.year, resume.month, resume.day);
    return at.isBefore(startOfResumeDay);
  }

  OrderHold copyWith({
    bool? active,
    String? message,
    DateTime? resumeOn,
    bool clearResumeOn = false,
    bool? allowAdvanceBooking,
  }) {
    return OrderHold(
      active: active ?? this.active,
      message: message ?? this.message,
      resumeOn: clearResumeOn ? null : (resumeOn ?? this.resumeOn),
      allowAdvanceBooking: allowAdvanceBooking ?? this.allowAdvanceBooking,
    );
  }

  static OrderHold fromMap(Map<String, dynamic>? data) {
    if (data == null) return off;
    final rawResume = data['resume_on'];
    DateTime? resume;
    if (rawResume is Timestamp) {
      resume = rawResume.toDate();
    } else if (rawResume is String && rawResume.trim().isNotEmpty) {
      resume = DateTime.tryParse(rawResume.trim());
    }
    final rawMessage = data['message'];
    return OrderHold(
      active: data['active'] == true,
      message: rawMessage is String
          ? rawMessage.trim().substring(
              0,
              rawMessage.trim().length > maxMessageLength
                  ? maxMessageLength
                  : rawMessage.trim().length,
            )
          : '',
      resumeOn: resume,
      allowAdvanceBooking: data['allow_advance_booking'] == true,
    );
  }
}

/// Reads/writes `admin_public/order_hold`. Customers read it before checkout,
/// admin edits it from Settings -> Business Settings -> Order hold.
class OrderHoldService {
  OrderHoldService._();

  static const _docId = 'order_hold';

  /// Last value seen this session, so the cart and home banner can decide on
  /// the first frame instead of flashing the wrong state.
  static OrderHold cached = OrderHold.off;

  static DocumentReference<Map<String, dynamic>> get _ref =>
      chechiFirestore.collection('admin_public').doc(_docId);

  static Future<OrderHold> load() async {
    try {
      final snap = await _ref.get();
      final hold = OrderHold.fromMap(snap.data());
      cached = hold;
      return hold;
    } catch (_) {
      return cached;
    }
  }

  /// Read straight from the server before refusing an order, so a customer is
  /// never turned away on a stale cache — and never let through on one.
  static Future<OrderHold> loadFresh() async {
    final snap = await _ref.get(const GetOptions(source: Source.server));
    final hold = OrderHold.fromMap(snap.data());
    cached = hold;
    return hold;
  }

  static Stream<OrderHold> watch() {
    return _ref.snapshots().map((snap) {
      final hold = OrderHold.fromMap(snap.data());
      cached = hold;
      return hold;
    });
  }

  static Future<void> save(OrderHold hold, {String? updatedByUid}) async {
    final message = hold.message.trim();
    if (message.length > OrderHold.maxMessageLength) {
      throw StateError('Message is too long');
    }
    final resume = hold.resumeOn;
    await _ref.set({
      'active': hold.active,
      'message': message,
      'resume_on': resume == null
          ? null
          : Timestamp.fromDate(
              DateTime(resume.year, resume.month, resume.day),
            ),
      'allow_advance_booking': hold.allowAdvanceBooking && resume != null,
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedByUid != null && updatedByUid.isNotEmpty)
        'updatedBy': updatedByUid,
    }, SetOptions(merge: true));
    cached = OrderHold(
      active: hold.active,
      message: message,
      resumeOn: resume,
      allowAdvanceBooking: hold.allowAdvanceBooking && resume != null,
    );
  }
}
