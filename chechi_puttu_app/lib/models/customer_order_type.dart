/// How the customer uses Chechi Puttu after sign-in.
enum CustomerOrderType {
  normal,
  hospital,
  corporate;

  String get firestoreValue => name;

  static CustomerOrderType? fromFirestore(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'normal':
        return CustomerOrderType.normal;
      case 'hospital':
        return CustomerOrderType.hospital;
      case 'corporate':
        return CustomerOrderType.corporate;
      default:
        return null;
    }
  }

  String get title {
    switch (this) {
      case CustomerOrderType.normal:
        return 'Normal orders';
      case CustomerOrderType.hospital:
        return 'Hospital orders';
      case CustomerOrderType.corporate:
        return 'Corporate orders';
    }
  }

  String get subtitle {
    switch (this) {
      case CustomerOrderType.normal:
        return 'Order puttu & meals for yourself or family';
      case CustomerOrderType.hospital:
        return 'Recurring meals for patients & staff';
      case CustomerOrderType.corporate:
        return 'Office breakfast & team catering';
    }
  }

  bool get needsBulkEnrollment =>
      this == CustomerOrderType.hospital || this == CustomerOrderType.corporate;
}

/// Weekday keys stored in Firestore (`monday` … `sunday`).
const kBulkOrderWeekdays = <String>[
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const kBulkOrderWeekdayLabels = <String, String>{
  'monday': 'Mon',
  'tuesday': 'Tue',
  'wednesday': 'Wed',
  'thursday': 'Thu',
  'friday': 'Fri',
  'saturday': 'Sat',
  'sunday': 'Sun',
};

/// Portions a dish starts at when first added to a bulk plan.
const int kDefaultDishQuantity = 10;

/// The most a single dish can carry on a plan.
const int kMaxDishQuantity = 999;

class BulkOrderEnrollment {
  const BulkOrderEnrollment({
    this.contactName = '',
    this.phone = '',
    this.alternatePhone = '',
    this.organizationName = '',
    this.orderPersonName = '',
    this.orderPersonDesignation = '',
    this.preferredTime = '',
    this.mealSlots = const [],
    this.mealTimes = const {},
    this.totalQuantity = 0,
    this.scheduleMode = BulkScheduleMode.allDays,
    this.days = const [],
    this.selectedDishes = const [],
    this.dishQuantities = const {},
    this.enrollmentComplete = false,
  });

  final String contactName;
  final String phone;
  final String alternatePhone;
  final String organizationName;
  final String orderPersonName;

  /// Job title / designation of the person who places orders (corporate only).
  final String orderPersonDesignation;
  final String preferredTime;

  /// Meal windows this plan is delivered in — `breakfast` / `lunch` / `dinner`
  /// (ids from [AdvanceOrderSchedule.mealSlots]).
  final List<String> mealSlots;

  /// Delivery time the organisation asked for, per meal id, e.g.
  /// `{'breakfast': '8:30 AM', 'dinner': '7:00 PM'}`. Bulk plans are delivered
  /// at the time agreed per meal rather than in the standard windows. Empty
  /// for plans saved before per-meal times existed — those carry a single
  /// [preferredTime] instead.
  final Map<String, String> mealTimes;

  /// Portions the organisation books per delivery. Dish quantities must add up
  /// to exactly this when set; 0 means "not specified" (older plans).
  final int totalQuantity;

  final BulkScheduleMode scheduleMode;
  final List<String> days;

  /// Dish titles (from the customer menu catalog) the organisation wants on
  /// its recurring meal plan. Kept in sync with [dishQuantities] keys so
  /// readers that predate per-dish quantities (Cloud Functions, admin) still
  /// see the plan.
  final List<String> selectedDishes;

  /// Portions per delivery, keyed by dish title. Empty for plans saved before
  /// quantities existed — treat a missing entry as [kDefaultDishQuantity].
  final Map<String, int> dishQuantities;
  final bool enrollmentComplete;

  /// Total portions per delivery across every dish on the plan.
  int get totalPortions =>
      dishQuantities.values.fold(0, (sum, qty) => sum + qty);

  BulkOrderEnrollment copyWith({
    String? contactName,
    String? phone,
    String? alternatePhone,
    String? organizationName,
    String? orderPersonName,
    String? orderPersonDesignation,
    String? preferredTime,
    List<String>? mealSlots,
    Map<String, String>? mealTimes,
    int? totalQuantity,
    BulkScheduleMode? scheduleMode,
    List<String>? days,
    List<String>? selectedDishes,
    Map<String, int>? dishQuantities,
    bool? enrollmentComplete,
  }) {
    return BulkOrderEnrollment(
      contactName: contactName ?? this.contactName,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      organizationName: organizationName ?? this.organizationName,
      orderPersonName: orderPersonName ?? this.orderPersonName,
      orderPersonDesignation:
          orderPersonDesignation ?? this.orderPersonDesignation,
      preferredTime: preferredTime ?? this.preferredTime,
      mealSlots: mealSlots ?? this.mealSlots,
      mealTimes: mealTimes ?? this.mealTimes,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      days: days ?? this.days,
      selectedDishes: selectedDishes ?? this.selectedDishes,
      dishQuantities: dishQuantities ?? this.dishQuantities,
      enrollmentComplete: enrollmentComplete ?? this.enrollmentComplete,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'contactName': contactName.trim(),
        'phone': phone.trim(),
        'alternatePhone': alternatePhone.trim(),
        'organizationName': organizationName.trim(),
        'orderPersonName': orderPersonName.trim(),
        'orderPersonDesignation': orderPersonDesignation.trim(),
        'preferredTime': preferredTime.trim(),
        'mealSlots': mealSlots,
        'mealTimes': mealTimes,
        'totalQuantity': totalQuantity,
        'scheduleMode': scheduleMode.firestoreValue,
        'days': days,
        'selectedDishes': selectedDishes,
        'dishQuantities': dishQuantities,
        'enrollmentComplete': enrollmentComplete,
      };

  factory BulkOrderEnrollment.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BulkOrderEnrollment();
    final rawDays = m['days'];
    final days = rawDays is List
        ? rawDays.map((e) => e.toString()).toList()
        : <String>[];
    final rawDishes = m['selectedDishes'];
    final selectedDishes = rawDishes is List
        ? rawDishes.map((e) => e.toString()).toList()
        : <String>[];
    final rawQuantities = m['dishQuantities'];
    final dishQuantities = <String, int>{};
    if (rawQuantities is Map) {
      rawQuantities.forEach((key, value) {
        final qty = value is num ? value.toInt() : int.tryParse('$value');
        if (qty != null && qty > 0) dishQuantities[key.toString()] = qty;
      });
    }
    // Plans saved before quantities existed carry titles only.
    for (final title in selectedDishes) {
      dishQuantities.putIfAbsent(title, () => kDefaultDishQuantity);
    }
    final rawSlots = m['mealSlots'];
    final mealSlots = rawSlots is List
        ? rawSlots.map((e) => e.toString()).toList()
        : <String>[];
    final rawTimes = m['mealTimes'];
    final mealTimes = <String, String>{};
    if (rawTimes is Map) {
      rawTimes.forEach((key, value) {
        final t = value?.toString().trim() ?? '';
        if (t.isNotEmpty) mealTimes[key.toString()] = t;
      });
    }
    final rawTotal = m['totalQuantity'];
    final totalQuantity =
        rawTotal is num ? rawTotal.toInt() : int.tryParse('${rawTotal ?? ''}') ?? 0;
    return BulkOrderEnrollment(
      contactName: m['contactName'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      alternatePhone: m['alternatePhone'] as String? ?? '',
      organizationName: m['organizationName'] as String? ?? '',
      orderPersonName: m['orderPersonName'] as String? ?? '',
      orderPersonDesignation: m['orderPersonDesignation'] as String? ?? '',
      preferredTime: m['preferredTime'] as String? ?? '',
      mealSlots: mealSlots,
      mealTimes: mealTimes,
      totalQuantity: totalQuantity < 0 ? 0 : totalQuantity,
      scheduleMode: BulkScheduleMode.fromFirestore(
        m['scheduleMode'] as String?,
      ),
      days: days,
      selectedDishes: selectedDishes,
      dishQuantities: dishQuantities,
      enrollmentComplete: m['enrollmentComplete'] as bool? ?? false,
    );
  }
}

enum BulkScheduleMode {
  allDays,
  specificDays;

  String get firestoreValue =>
      this == BulkScheduleMode.allDays ? 'all_days' : 'specific_days';

  static BulkScheduleMode fromFirestore(String? raw) {
    if (raw == 'specific_days') return BulkScheduleMode.specificDays;
    return BulkScheduleMode.allDays;
  }

  String get label {
    switch (this) {
      case BulkScheduleMode.allDays:
        return 'All 7 days';
      case BulkScheduleMode.specificDays:
        return 'Specific days only';
    }
  }
}

class CustomerOrderTypeState {
  const CustomerOrderTypeState({
    this.orderType,
    this.typeSelected = false,
    this.bulkEnrollment = const BulkOrderEnrollment(),
  });

  final CustomerOrderType? orderType;
  final bool typeSelected;
  final BulkOrderEnrollment bulkEnrollment;

  bool get needsOrderTypeSelection => !typeSelected;

  bool get needsBulkEnrollment {
    final t = orderType;
    if (t == null || !t.needsBulkEnrollment) return false;
    return !bulkEnrollment.enrollmentComplete;
  }
}
