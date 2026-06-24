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

class BulkOrderEnrollment {
  const BulkOrderEnrollment({
    this.contactName = '',
    this.phone = '',
    this.alternatePhone = '',
    this.organizationName = '',
    this.orderPersonName = '',
    this.preferredTime = '',
    this.scheduleMode = BulkScheduleMode.allDays,
    this.days = const [],
    this.enrollmentComplete = false,
  });

  final String contactName;
  final String phone;
  final String alternatePhone;
  final String organizationName;
  final String orderPersonName;
  final String preferredTime;
  final BulkScheduleMode scheduleMode;
  final List<String> days;
  final bool enrollmentComplete;

  BulkOrderEnrollment copyWith({
    String? contactName,
    String? phone,
    String? alternatePhone,
    String? organizationName,
    String? orderPersonName,
    String? preferredTime,
    BulkScheduleMode? scheduleMode,
    List<String>? days,
    bool? enrollmentComplete,
  }) {
    return BulkOrderEnrollment(
      contactName: contactName ?? this.contactName,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      organizationName: organizationName ?? this.organizationName,
      orderPersonName: orderPersonName ?? this.orderPersonName,
      preferredTime: preferredTime ?? this.preferredTime,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      days: days ?? this.days,
      enrollmentComplete: enrollmentComplete ?? this.enrollmentComplete,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'contactName': contactName.trim(),
        'phone': phone.trim(),
        'alternatePhone': alternatePhone.trim(),
        'organizationName': organizationName.trim(),
        'orderPersonName': orderPersonName.trim(),
        'preferredTime': preferredTime.trim(),
        'scheduleMode': scheduleMode.firestoreValue,
        'days': days,
        'enrollmentComplete': enrollmentComplete,
      };

  factory BulkOrderEnrollment.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BulkOrderEnrollment();
    final rawDays = m['days'];
    final days = rawDays is List
        ? rawDays.map((e) => e.toString()).toList()
        : <String>[];
    return BulkOrderEnrollment(
      contactName: m['contactName'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      alternatePhone: m['alternatePhone'] as String? ?? '',
      organizationName: m['organizationName'] as String? ?? '',
      orderPersonName: m['orderPersonName'] as String? ?? '',
      preferredTime: m['preferredTime'] as String? ?? '',
      scheduleMode: BulkScheduleMode.fromFirestore(
        m['scheduleMode'] as String?,
      ),
      days: days,
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
