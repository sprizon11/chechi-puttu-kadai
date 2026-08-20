import 'dart:convert';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:chechi_puttu_app/services/advance_order_schedule.dart';
import 'package:chechi_puttu_app/services/auth_service.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:chechi_puttu_app/services/customer_menu_section_overrides.dart';
import 'package:chechi_puttu_app/services/customer_order_type_service.dart';
import 'package:chechi_puttu_app/services/menu_deleted_dishes.dart';
import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:chechi_puttu_app/widgets/fssai_license_footer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hospital / corporate recurring-order enrollment form.
class BulkOrderSetupScreen extends StatefulWidget {
  const BulkOrderSetupScreen({
    super.key,
    required this.orderType,
    required this.onCompleted,
    this.onChangeOrderType,
    this.initial,
  });

  final CustomerOrderType orderType;
  final VoidCallback onCompleted;
  final VoidCallback? onChangeOrderType;
  final BulkOrderEnrollment? initial;

  @override
  State<BulkOrderSetupScreen> createState() => _BulkOrderSetupScreenState();
}

class _BulkOrderSetupScreenState extends State<BulkOrderSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _altPhoneCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _personCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();

  BulkScheduleMode _scheduleMode = BulkScheduleMode.allDays;
  final Set<String> _selectedDays = {};

  /// Meal windows this plan is delivered in (breakfast / lunch / dinner).
  final Set<String> _selectedMealSlots = {};

  /// Delivery time picked for each selected meal, e.g. `breakfast -> 8:30 AM`.
  /// Kept in step with [_selectedMealSlots]: deselecting a meal drops its time
  /// so a stale time can never be submitted.
  final Map<String, String> _mealTimes = {};
  final Map<String, TimeOfDay> _mealTimeOfDay = {};

  /// Dish title -> portions per delivery. Presence in this map *is* selection,
  /// so there is no separate selected-set that could disagree with it.
  final Map<String, int> _dishQuantities = {};

  /// Per-dish text fields, created lazily and kept across rebuilds so typing
  /// never loses the cursor.
  final Map<String, TextEditingController> _dishQtyCtrls = {};
  final _totalQtyCtrl = TextEditingController();
  final _dishSearchCtrl = TextEditingController();
  String _dishQuery = '';
  bool _busy = false;

  /// Set once the plan is saved — swaps the form for the confirmation screen
  /// instead of letting the gate jump straight to the next setup step.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final user = authService.currentUser;
    final init = widget.initial;
    if (init != null) {
      _nameCtrl.text = init.contactName;
      _phoneCtrl.text = init.phone;
      _altPhoneCtrl.text = init.alternatePhone;
      _orgCtrl.text = init.organizationName;
      _personCtrl.text = init.orderPersonName;
      _designationCtrl.text = init.orderPersonDesignation;
      _scheduleMode = init.scheduleMode;
      _selectedDays.addAll(init.days);
      _selectedMealSlots.addAll(init.mealSlots);
      _mealTimes.addAll(init.mealTimes);
      // Plans saved before per-meal times carry one time for the whole plan —
      // seed every selected meal with it so nothing looks blank on reopen.
      if (_mealTimes.isEmpty && init.preferredTime.trim().isNotEmpty) {
        for (final id in init.mealSlots) {
          _mealTimes[id] = init.preferredTime.trim();
        }
      }
      _dishQuantities.addAll(init.dishQuantities);
      if (init.totalQuantity > 0) {
        _totalQtyCtrl.text = '${init.totalQuantity}';
      }
      for (final e in init.dishQuantities.entries) {
        _dishQtyCtrls[e.key] = TextEditingController(text: '${e.value}');
      }
    } else {
      _prefillFromAuth(user);
    }
    // Menu edits/deletes sync in from Firestore while this form is open.
    MenuDeletedDishes.instance.addListener(_onMenuChanged);
    CustomerMenuOverrides.instance.addListener(_onMenuChanged);
    CustomerMenuSectionOverrides.instance.addListener(_onMenuChanged);
    // Enrollment can be reached before Home has loaded the menu, so make sure
    // the resolved catalog (and delete list) is populated here too.
    MenuDeletedDishes.instance.reloadFromPrefs();
    CustomerMenuOverrides.instance.reloadFromPrefs();
    CustomerMenuSectionOverrides.instance.reloadFromPrefs();
  }

  void _onMenuChanged() {
    if (mounted) setState(() {});
  }

  void _prefillFromAuth(User? user) {
    final n = user?.displayName?.trim();
    if (n != null && n.isNotEmpty) _nameCtrl.text = n;
    final phone = user?.phoneNumber?.trim();
    if (phone != null && phone.isNotEmpty) {
      final p = AuthService.normalizePhoneForFirebase(phone);
      final digits = p.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        _phoneCtrl.text = digits.length > 10
            ? digits.substring(digits.length - 10)
            : digits;
      }
    }
  }

  @override
  void dispose() {
    MenuDeletedDishes.instance.removeListener(_onMenuChanged);
    CustomerMenuOverrides.instance.removeListener(_onMenuChanged);
    CustomerMenuSectionOverrides.instance.removeListener(_onMenuChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _orgCtrl.dispose();
    _personCtrl.dispose();
    _designationCtrl.dispose();
    _totalQtyCtrl.dispose();
    _dishSearchCtrl.dispose();
    for (final c in _dishQtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _orgLabel => widget.orderType == CustomerOrderType.hospital
      ? 'Hospital name'
      : 'Company / organisation name';

  /// Sensible starting point for each meal's picker, so the customer is
  /// nudging a plausible time rather than scrolling from midnight.
  static const Map<String, TimeOfDay> _defaultMealTime = {
    'breakfast': TimeOfDay(hour: 8, minute: 0),
    'lunch': TimeOfDay(hour: 13, minute: 0),
    'dinner': TimeOfDay(hour: 20, minute: 0),
  };

  static String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  Future<void> _pickMealTime(String slotId) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _mealTimeOfDay[slotId] ??
          _defaultMealTime[slotId] ??
          const TimeOfDay(hour: 8, minute: 0),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: ChechiBrand.maroonDeep,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _mealTimeOfDay[slotId] = picked;
      _mealTimes[slotId] = _formatTime(picked);
    });
  }

  /// Selecting a meal opens its time picker straight away; deselecting drops
  /// the time so [_mealTimes] never outlives its meal.
  void _toggleMealSlot(String slotId) {
    final wasSelected = _selectedMealSlots.contains(slotId);
    setState(() {
      if (wasSelected) {
        _selectedMealSlots.remove(slotId);
        _mealTimes.remove(slotId);
        _mealTimeOfDay.remove(slotId);
      } else {
        _selectedMealSlots.add(slotId);
      }
    });
    if (!wasSelected && !_mealTimes.containsKey(slotId)) {
      _pickMealTime(slotId);
    }
  }

  /// e.g. `Breakfast 8:00 AM · Dinner 8:00 PM` — one line for the kitchen
  /// sheet and the chat summary, in meal order.
  String get _mealTimeSummary => [
        for (final s in AdvanceOrderSchedule.mealSlots)
          if (_selectedMealSlots.contains(s.id))
            '${s.name} ${_mealTimes[s.id] ?? ''}'.trim(),
      ].join(' · ');

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduleMode == BulkScheduleMode.specificDays &&
        _selectedDays.isEmpty) {
      _showSnack('Select at least one delivery day');
      return;
    }
    if (_selectedMealSlots.isEmpty) {
      _showSnack('Select at least one meal (breakfast, lunch or dinner)');
      return;
    }
    // Every chosen meal needs its own delivery time — the kitchen schedules
    // each one separately, so one missing time makes the plan unusable.
    for (final slot in AdvanceOrderSchedule.mealSlots) {
      if (_selectedMealSlots.contains(slot.id) &&
          (_mealTimes[slot.id] ?? '').trim().isEmpty) {
        _showSnack('Pick a delivery time for ${slot.name}');
        return;
      }
    }
    if (_dishQuantities.isEmpty) {
      _showSnack('Add at least one dish to the plan');
      return;
    }
    // A stated plan total must be fully allocated across dishes — the cap
    // already prevents going over, so this only catches under-allocation.
    if (_requestedTotal > 0 && _totalPortions != _requestedTotal) {
      _showSnack(
        'Assign all $_requestedTotal portions — $_remainingPortions still left.',
      );
      return;
    }
    final user = authService.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final days = _scheduleMode == BulkScheduleMode.allDays
          ? List<String>.from(kBulkOrderWeekdays)
          : _selectedDays.toList()..sort(
              (a, b) => kBulkOrderWeekdays.indexOf(a) -
                  kBulkOrderWeekdays.indexOf(b),
            );
      final enrollment = BulkOrderEnrollment(
        contactName: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        alternatePhone: _altPhoneCtrl.text.trim(),
        organizationName: _orgCtrl.text.trim(),
        orderPersonName: _personCtrl.text.trim(),
        orderPersonDesignation: _designationCtrl.text.trim(),
        // Kept as a readable one-liner so the kitchen sheet column and any
        // reader predating per-meal times still shows every time.
        preferredTime: _mealTimeSummary,
        mealSlots: [
          for (final s in AdvanceOrderSchedule.mealSlots)
            if (_selectedMealSlots.contains(s.id)) s.id,
        ],
        mealTimes: {
          for (final s in AdvanceOrderSchedule.mealSlots)
            if (_selectedMealSlots.contains(s.id))
              s.id: (_mealTimes[s.id] ?? '').trim(),
        },
        totalQuantity: _requestedTotal > 0 ? _requestedTotal : _totalPortions,
        scheduleMode: _scheduleMode,
        days: days,
        selectedDishes: _dishQuantities.keys.toList(),
        dishQuantities: Map<String, int>.from(_dishQuantities),
      );
      await customerOrderTypeService.saveBulkEnrollment(
        user: user,
        type: widget.orderType,
        enrollment: enrollment,
      );
      if (!mounted) return;
      // Confirmation first — `onCompleted` advances the sign-in gate, so
      // calling it here would replace this screen before anything is read.
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Could not send your booking. Please check your internet and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHospital = widget.orderType == CustomerOrderType.hospital;
    final dishCount = _dishQuantities.length;
    if (_submitted) {
      return _BookingSentScreen(
        organisation: _orgCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        portions: _totalPortions,
        dishCount: dishCount,
        meals: [
          for (final s in AdvanceOrderSchedule.mealSlots)
            if (_selectedMealSlots.contains(s.id))
              '${s.name} ${(_mealTimes[s.id] ?? '').trim()}'.trim(),
        ],
        onDone: widget.onCompleted,
      );
    }
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: ChechiPremium.brandGradient()),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                isHospital: isHospital,
                orderType: widget.orderType,
                busy: _busy,
                onBack: widget.onChangeOrderType,
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      ChechiFadeIn(
                        delay: chechiStagger(0),
                        child: _sectionCard(
                          icon: Icons.badge_outlined,
                          title: 'Contact details',
                          children: [
                            _field(
                              controller: _nameCtrl,
                              label: 'Your name',
                              icon: Icons.person_outline_rounded,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            _field(
                              controller: _phoneCtrl,
                              label: 'Phone number',
                              icon: Icons.phone_outlined,
                              keyboard: TextInputType.phone,
                              validator: (v) {
                                final d = (v ?? '').replaceAll(
                                  RegExp(r'\D'),
                                  '',
                                );
                                if (d.length != 10) {
                                  return 'Enter valid 10-digit number';
                                }
                                if (!RegExp(r'^[6-9]').hasMatch(d)) {
                                  return 'Enter a valid Indian mobile number';
                                }
                                return null;
                              },
                            ),
                            _field(
                              controller: _altPhoneCtrl,
                              label: 'Alternate phone',
                              icon: Icons.phone_callback_outlined,
                              keyboard: TextInputType.phone,
                              validator: (v) {
                                final d = (v ?? '').replaceAll(
                                  RegExp(r'\D'),
                                  '',
                                );
                                if (d.length != 10) {
                                  return 'Enter valid 10-digit number';
                                }
                                if (!RegExp(r'^[6-9]').hasMatch(d)) {
                                  return 'Enter a valid Indian mobile number';
                                }
                                final primary = _phoneCtrl.text.replaceAll(
                                  RegExp(r'\D'),
                                  '',
                                );
                                if (d == primary) {
                                  return 'Must differ from the primary number';
                                }
                                return null;
                              },
                              last: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      ChechiFadeIn(
                        delay: chechiStagger(1),
                        child: _sectionCard(
                          icon: isHospital
                              ? Icons.local_hospital_outlined
                              : Icons.apartment_rounded,
                          title: 'Organisation',
                          children: [
                            _field(
                              controller: _orgCtrl,
                              label: _orgLabel,
                              icon: isHospital
                                  ? Icons.local_hospital_outlined
                                  : Icons.apartment_rounded,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            _field(
                              controller: _personCtrl,
                              label: 'Order contact person name',
                              icon: Icons.badge_outlined,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            _field(
                              controller: _designationCtrl,
                              label: isHospital
                                  ? 'Order person designation'
                                  : 'Order person job position',
                              icon: Icons.work_outline_rounded,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                              last: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      ChechiFadeIn(
                        delay: chechiStagger(2),
                        child: _sectionCard(
                          icon: Icons.schedule_rounded,
                          title: 'Schedule',
                          children: [
                            Text(
                              'Meals',
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: ChechiBrand.maroonDeep,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pick a meal, then set the time you want it '
                              'delivered.',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                height: 1.35,
                                color: const Color(0xFF7A6A62),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _mealSlotTiles(),
                            const SizedBox(height: 10),
                            Text(
                              'Delivery days',
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: ChechiBrand.maroonDeep,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _scheduleModeChips(),
                            if (_scheduleMode ==
                                BulkScheduleMode.specificDays) ...[
                              const SizedBox(height: 12),
                              _weekdayChips(),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      ChechiFadeIn(
                        delay: chechiStagger(3),
                        child: _sectionCard(
                          icon: Icons.restaurant_menu_rounded,
                          title: 'Select dishes',
                          trailing: _DishCountBadge(
                            count: dishCount,
                            portions: _totalPortions,
                          ),
                          children: [
                            Text(
                              'Enter the total portions you need per delivery, '
                              'then type how many of each dish make up that '
                              'total. You can update dishes later from support '
                              'chat.',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                height: 1.35,
                                color: const Color(0xFF7A6A62),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _totalQuantityField(),
                            const SizedBox(height: 10),
                            _allocationBar(),
                            const SizedBox(height: 12),
                            _dishSearchField(),
                            const SizedBox(height: 4),
                            ..._dishSectionBlocks(),
                          ],
                        ),
                      ),
                      const FssaiLicenseFooter(padding: EdgeInsets.only(top: 20)),
                    ],
                  ),
                ),
              ),
              _BottomBar(
                busy: _busy,
                dishCount: dishCount,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int get _totalPortions =>
      _dishQuantities.values.fold(0, (sum, qty) => sum + qty);

  /// The plan-wide quantity the customer typed (0 = not set yet).
  int get _requestedTotal => int.tryParse(_totalQtyCtrl.text.trim()) ?? 0;

  /// Portions still unassigned against [_requestedTotal].
  int get _remainingPortions => _requestedTotal - _totalPortions;

  /// Largest quantity [title] may take without the plan exceeding the total.
  int _maxQuantityFor(String title) {
    final budget = _requestedTotal;
    if (budget <= 0) return kMaxDishQuantity;
    final others = _totalPortions - (_dishQuantities[title] ?? 0);
    final left = budget - others;
    return left < 0 ? 0 : left.clamp(0, kMaxDishQuantity);
  }

  TextEditingController _dishQtyController(String title) {
    return _dishQtyCtrls.putIfAbsent(
      title,
      () => TextEditingController(
        text: _dishQuantities[title] == null ? '' : '${_dishQuantities[title]}',
      ),
    );
  }

  /// Applies a typed quantity, capped to what the plan total still allows.
  /// Returns the value actually stored so the field can be corrected.
  int _setDishQuantity(String title, int qty) {
    final capped = qty <= 0 ? 0 : qty.clamp(1, _maxQuantityFor(title));
    setState(() {
      if (capped <= 0) {
        _dishQuantities.remove(title);
      } else {
        _dishQuantities[title] = capped;
      }
    });
    return capped;
  }

  void _onDishQtyTyped(String title, String raw) {
    final ctrl = _dishQtyController(title);
    final typed = int.tryParse(raw.trim());
    if (raw.trim().isEmpty || typed == null) {
      _setDishQuantity(title, 0);
      return;
    }
    final applied = _setDishQuantity(title, typed);
    if (applied != typed) {
      // Over budget (or above the per-dish ceiling) — snap the field back to
      // what was actually stored instead of silently disagreeing with it.
      final text = applied <= 0 ? '' : '$applied';
      ctrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _showSnack(
        _requestedTotal > 0
            ? 'Plan total is $_requestedTotal — only $applied left for this dish.'
            : 'Maximum $kMaxDishQuantity portions per dish.',
      );
    }
  }

  /// Lowering the plan total can strand quantities above it; trim the largest
  /// dishes down until the plan fits again.
  void _onTotalQuantityChanged() {
    final budget = _requestedTotal;
    setState(() {});
    if (budget <= 0 || _totalPortions <= budget) return;
    final titles = _dishQuantities.keys.toList()
      ..sort((a, b) => _dishQuantities[b]!.compareTo(_dishQuantities[a]!));
    for (final title in titles) {
      if (_totalPortions <= budget) break;
      final excess = _totalPortions - budget;
      final next = _dishQuantities[title]! - excess;
      setState(() {
        if (next <= 0) {
          _dishQuantities.remove(title);
        } else {
          _dishQuantities[title] = next;
        }
      });
      final ctrl = _dishQtyCtrls[title];
      if (ctrl != null) ctrl.text = next <= 0 ? '' : '$next';
    }
  }

  /// Breakfast / lunch / dinner. Bulk plans are delivered at the time agreed
  /// in the quotation, so the standard windows and cut-offs are not shown —
  /// only the meal itself is picked here.
  Widget _mealSlotTiles() {
    return Column(
      children: [
        for (final slot in AdvanceOrderSchedule.mealSlots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _mealSlotTile(slot),
          ),
      ],
    );
  }

  /// One meal row. Selected meals grow a time row underneath, inside the same
  /// bordered block, so the time visibly belongs to that meal.
  Widget _mealSlotTile(AdvanceMealSlot slot) {
    final selected = _selectedMealSlots.contains(slot.id);
    final time = (_mealTimes[slot.id] ?? '').trim();
    return AnimatedContainer(
      duration: ChechiBrand.fast,
      decoration: BoxDecoration(
        color: selected
            ? ChechiBrand.maroonDeep.withValues(alpha: 0.07)
            : const Color(0xFFFCF7F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? ChechiBrand.maroonDeep : ChechiBrand.border,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy ? null : () => _toggleMealSlot(slot.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      slot.id == 'breakfast'
                          ? Icons.wb_sunny_outlined
                          : slot.id == 'lunch'
                              ? Icons.lunch_dining_outlined
                              : Icons.nightlight_round,
                      size: 20,
                      color: ChechiBrand.maroonDeep,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        slot.name,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ChechiBrand.maroonDeep,
                        ),
                      ),
                    ),
                    Checkbox(
                      value: selected,
                      onChanged:
                          _busy ? null : (_) => _toggleMealSlot(slot.id),
                      activeColor: ChechiBrand.maroonDeep,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected) _mealTimeRow(slot, time),
        ],
      ),
    );
  }

  /// Time row for a selected meal — tap anywhere on it to (re)pick.
  Widget _mealTimeRow(AdvanceMealSlot slot, String time) {
    final hasTime = time.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _pickMealTime(slot.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasTime
                    ? ChechiBrand.border
                    : ChechiBrand.accent.withValues(alpha: 0.9),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: ChechiBrand.maroon.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${slot.name} delivery time',
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          color: const Color(0xFF7A6A62),
                        ),
                      ),
                      Text(
                        hasTime ? time : 'Tap to set time',
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: hasTime
                              ? ChechiBrand.maroonDeep
                              : ChechiBrand.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  hasTime ? 'Change' : 'Set',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ChechiBrand.maroonDeep,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: ChechiBrand.maroonDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalQuantityField() {
    return TextFormField(
      controller: _totalQtyCtrl,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: (_) => _onTotalQuantityChanged(),
      style: GoogleFonts.poppins(fontSize: 14),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return 'Enter total quantity';
        final n = int.tryParse(t);
        if (n == null || n <= 0) return 'Enter a valid quantity';
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Total quantity per delivery',
        helperText: 'Dish portions must add up to exactly this',
        helperStyle: GoogleFonts.poppins(
          fontSize: 10.5,
          color: const Color(0xFF7A6A62),
        ),
        prefixIcon: Icon(
          Icons.numbers_rounded,
          color: ChechiBrand.maroon.withValues(alpha: 0.75),
        ),
        filled: true,
        fillColor: const Color(0xFFFCF7F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ChechiBrand.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ChechiBrand.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ChechiBrand.maroon, width: 1.4),
        ),
      ),
    );
  }

  /// Live "80 of 100 assigned · 20 left" readout under the total field.
  Widget _allocationBar() {
    final total = _requestedTotal;
    if (total <= 0) return const SizedBox.shrink();
    final assigned = _totalPortions;
    final left = _remainingPortions;
    final done = left == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: done
            ? const Color(0xFFE8F5E9)
            : ChechiBrand.maroonDeep.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done ? const Color(0xFFA5D6A7) : ChechiBrand.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_outline_rounded : Icons.pie_chart_outline,
            size: 16,
            color: done ? const Color(0xFF2E7D32) : ChechiBrand.maroonDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              done
                  ? 'All $total portions assigned'
                  : '$assigned of $total assigned · $left left',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: done ? const Color(0xFF2E7D32) : ChechiBrand.maroonDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dishSearchField() {
    return TextField(
      controller: _dishSearchCtrl,
      enabled: !_busy,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: ChechiBrand.maroonDeep,
      ),
      onChanged: (v) => setState(() => _dishQuery = v.trim().toLowerCase()),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: _dishQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _dishSearchCtrl.clear();
                  setState(() => _dishQuery = '');
                },
              ),
        hintText: 'Search dishes',
        hintStyle: GoogleFonts.poppins(
          fontSize: 12.5,
          color: const Color(0xFF9C8A80),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ChechiBrand.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ChechiBrand.border),
        ),
      ),
    );
  }

  /// Sections with no dish matching the search are dropped entirely, so the
  /// list never shows a header with nothing under it.
  ///
  /// Reads the same resolved catalog the customer menu uses — admin-edited
  /// categories, with deleted dishes and deleted sections filtered out — so a
  /// dish removed from the menu can never linger on this form.
  List<Widget> _dishSectionBlocks() {
    final blocks = <Widget>[];
    final sections = customerMenuSections;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final sectionId = customerMenuSectionIdAt(i);
      if (MenuDeletedDishes.instance.isSectionDeleted(sectionId)) continue;
      final live = section.dishes
          .where((d) => !MenuDeletedDishes.instance.isDeleted(sectionId, d.title))
          .toList();
      final dishes = _dishQuery.isEmpty
          ? live
          : live
                .where(
                  (d) =>
                      d.title.toLowerCase().contains(_dishQuery) ||
                      d.subtitle.toLowerCase().contains(_dishQuery),
                )
                .toList();
      if (dishes.isEmpty) continue;
      blocks.add(_dishSectionBlock(section, sectionId, dishes));
    }
    if (blocks.isEmpty) {
      blocks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'No dishes match "${_dishSearchCtrl.text.trim()}"',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF7A6A62),
            ),
          ),
        ),
      );
    }
    return blocks;
  }

  Widget _dishSectionBlock(
    MenuCatalogSection section,
    String sectionId,
    List<MenuCatalogDish> dishes,
  ) {
    final selectedInSection = dishes
        .where((d) => _dishQuantities.containsKey(d.title))
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: ChechiBrand.maroonDeep,
                  ),
                ),
              ),
              if (selectedInSection > 0)
                Text(
                  '$selectedInSection selected',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: ChechiBrand.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final dish in dishes)
            _DishRow(
              dish: dish,
              sectionId: sectionId,
              quantity: _dishQuantities[dish.title],
              qtyController: _dishQtyController(dish.title),
              enabled: !_busy,
              onAdd: () {
                final seed = _maxQuantityFor(dish.title) < kDefaultDishQuantity
                    ? _maxQuantityFor(dish.title)
                    : kDefaultDishQuantity;
                final applied = _setDishQuantity(dish.title, seed);
                _dishQtyController(dish.title).text =
                    applied <= 0 ? '' : '$applied';
                if (applied <= 0) {
                  _showSnack('No portions left — increase the plan total.');
                }
              },
              onTyped: (raw) => _onDishQtyTyped(dish.title, raw),
              onRemove: () {
                _setDishQuantity(dish.title, 0);
                _dishQtyController(dish.title).clear();
              },
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ChechiBrand.border),
        boxShadow: [
          BoxShadow(
            color: ChechiBrand.maroon.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: ChechiBrand.maroonDeep.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: ChechiBrand.maroonDeep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: ChechiBrand.maroonDeep,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    bool readOnly = false,
    VoidCallback? onTap,
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        keyboardType: keyboard,
        validator: validator,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: ChechiBrand.maroon.withValues(alpha: 0.75)),
          filled: true,
          fillColor: const Color(0xFFFCF7F2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ChechiBrand.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ChechiBrand.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ChechiBrand.maroon, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _scheduleModeChips() {
    return Row(
      children: BulkScheduleMode.values.map((mode) {
        final selected = _scheduleMode == mode;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: mode == BulkScheduleMode.allDays ? 8 : 0,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  _scheduleMode = mode;
                  if (mode == BulkScheduleMode.allDays) {
                    _selectedDays.clear();
                  }
                }),
                child: AnimatedContainer(
                  duration: ChechiBrand.fast,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? ChechiBrand.maroonDeep
                        : const Color(0xFFFCF7F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? ChechiBrand.maroonDeep
                          : ChechiBrand.border,
                    ),
                  ),
                  child: Text(
                    mode.label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : ChechiBrand.maroonDeep,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _weekdayChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kBulkOrderWeekdays.map((day) {
        final selected = _selectedDays.contains(day);
        final label = kBulkOrderWeekdayLabels[day] ?? day;
        return FilterChip(
          label: Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: selected ? Colors.white : ChechiBrand.maroonDeep,
            ),
          ),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) {
              _selectedDays.add(day);
            } else {
              _selectedDays.remove(day);
            }
          }),
          selectedColor: ChechiBrand.maroonDeep,
          backgroundColor: const Color(0xFFFCF7F2),
          checkmarkColor: Colors.white,
          side: const BorderSide(color: ChechiBrand.border),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

/// Post-submit confirmation: animated tick, what happens next, and where the
/// customer can find the request again.
class _BookingSentScreen extends StatefulWidget {
  const _BookingSentScreen({
    required this.organisation,
    required this.phone,
    required this.portions,
    required this.dishCount,
    required this.meals,
    required this.onDone,
  });

  final String organisation;
  final String phone;
  final int portions;
  final int dishCount;
  final List<String> meals;
  final VoidCallback onDone;

  @override
  State<_BookingSentScreen> createState() => _BookingSentScreenState();
}

class _BookingSentScreenState extends State<_BookingSentScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _ring;
  late final Animation<double> _tick;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _ring = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
    );
    _tick = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = <String>[
      if (widget.meals.isNotEmpty) widget.meals.join(' · '),
      if (widget.dishCount > 0)
        '${widget.dishCount} dish${widget.dishCount == 1 ? '' : 'es'}',
      if (widget.portions > 0) '${widget.portions} portions per delivery',
    ].join('  •  ');

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: ChechiPremium.brandGradient()),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              children: [
                const Spacer(),
                ScaleTransition(
                  scale: _ring,
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ChechiBrand.maroonDeep.withValues(alpha: 0.08),
                      border: Border.all(
                        color: ChechiBrand.maroonDeep,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: ScaleTransition(
                        scale: _tick,
                        child: const Icon(
                          Icons.check_rounded,
                          size: 62,
                          color: ChechiBrand.maroonDeep,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Your booking is sent',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: ChechiBrand.maroonDeep,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We will send you a quotation within 24 hours.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    height: 1.45,
                    color: const Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: ChechiBrand.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.organisation.isNotEmpty) ...[
                        Text(
                          widget.organisation,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: ChechiBrand.maroonDeep,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            height: 1.4,
                            color: const Color(0xFF7A6A62),
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: ChechiBrand.border),
                      const SizedBox(height: 12),
                      _NextStep(
                        icon: Icons.chat_bubble_outline_rounded,
                        text: 'A copy of this plan is in your Support chat — '
                            'open Profile → Support to see it and reply there.',
                      ),
                      const SizedBox(height: 10),
                      _NextStep(
                        icon: Icons.notifications_active_outlined,
                        text: 'You will get a notification as soon as the '
                            'quotation is ready.',
                      ),
                      const SizedBox(height: 10),
                      _NextStep(
                        icon: Icons.call_outlined,
                        text: widget.phone.isEmpty
                            ? 'Our team will call you to confirm the plan.'
                            : 'Our team will call you on ${widget.phone} to '
                                'confirm the plan.',
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onDone,
                    style: FilledButton.styleFrom(
                      backgroundColor: ChechiBrand.maroonDeep,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: ChechiBrand.maroonDeep),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              height: 1.45,
              color: const Color(0xFF5D4037),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isHospital,
    required this.orderType,
    required this.busy,
    this.onBack,
  });

  final bool isHospital;
  final CustomerOrderType orderType;
  final bool busy;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: busy ? null : onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: ChechiBrand.maroonDeep,
          ),
          const SizedBox(width: 2),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ChechiBrand.accent, ChechiBrand.maroonDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: ChechiBrand.maroon.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              isHospital ? Icons.local_hospital_rounded : Icons.apartment_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  orderType.title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: ChechiBrand.maroonDeep,
                  ),
                ),
                Text(
                  isHospital
                      ? 'Set up patient & staff meal schedule'
                      : 'Set up office meal schedule',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF7A6A62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DishCountBadge extends StatelessWidget {
  const _DishCountBadge({required this.count, required this.portions});

  final int count;
  final int portions;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: has
            ? ChechiBrand.maroonDeep
            : ChechiBrand.maroonDeep.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        has ? '$count dish${count == 1 ? '' : 'es'} · $portions' : 'None yet',
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: has ? Colors.white : ChechiBrand.maroonDeep,
        ),
      ),
    );
  }
}

/// One selectable dish: thumbnail, name, and either an Add button or a typed
/// quantity box. Prices are intentionally not shown — bulk plans are quoted
/// separately, so a per-plate figure here would be misleading.
class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.dish,
    required this.sectionId,
    required this.quantity,
    required this.qtyController,
    required this.enabled,
    required this.onAdd,
    required this.onTyped,
    required this.onRemove,
  });

  final MenuCatalogDish dish;
  final String sectionId;
  final int? quantity;
  final TextEditingController qtyController;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<String> onTyped;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final qty = quantity;
    final selected = qty != null;
    final merged = mergeWithCatalog(
      dish,
      CustomerMenuOverrides.instance.snapshotFor(sectionId, dish.title),
    );
    return AnimatedContainer(
      duration: ChechiBrand.fast,
      curve: ChechiBrand.ease,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected
            ? ChechiBrand.maroonDeep.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? ChechiBrand.maroonDeep : ChechiBrand.border,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: [
          _DishThumb(imageBase64: merged.imageBase64),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  merged.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ChechiBrand.maroonDeep,
                  ),
                ),
                if (merged.subtitle.trim().isNotEmpty)
                  Text(
                    merged.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: const Color(0xFF7A6A62),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!selected)
            OutlinedButton(
              onPressed: enabled ? onAdd : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: ChechiBrand.maroonDeep,
                side: const BorderSide(color: ChechiBrand.maroonDeep),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                'Add',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            _QuantityField(
              controller: qtyController,
              enabled: enabled,
              onTyped: onTyped,
              onRemove: onRemove,
            ),
        ],
      ),
    );
  }
}

class _DishThumb extends StatelessWidget {
  const _DishThumb({required this.imageBase64});

  final String? imageBase64;

  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  static Uint8List? _decode(String b64) {
    final hit = _cache[b64];
    if (hit != null) return hit;
    try {
      final bytes = base64Decode(b64);
      if (_cache.length >= 80) _cache.remove(_cache.keys.first);
      _cache[b64] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b64 = imageBase64;
    final bytes = (b64 == null || b64.isEmpty) ? null : _decode(b64);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 46,
        height: 46,
        child: bytes == null
            ? ColoredBox(
                color: ChechiBrand.maroonDeep.withValues(alpha: 0.06),
                child: const Icon(
                  Icons.restaurant_rounded,
                  size: 18,
                  color: Color(0xFF9C8A80),
                ),
              )
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// Typed portions for one dish, with a clear button that drops it from the plan.
class _QuantityField extends StatelessWidget {
  const _QuantityField({
    required this.controller,
    required this.enabled,
    required this.onTyped,
    required this.onRemove,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onTyped;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 68,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: onTyped,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: ChechiBrand.maroonDeep,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Qty',
              hintStyle: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF9C8A80),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ChechiBrand.maroonDeep),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ChechiBrand.maroonDeep),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: ChechiBrand.maroon, width: 1.4),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          color: ChechiBrand.maroonDeep,
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove from plan',
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.busy,
    required this.dishCount,
    required this.onSubmit,
  });

  final bool busy;
  final int dishCount;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final label = dishCount > 0
        ? 'Confirm & book · $dishCount dish${dishCount == 1 ? '' : 'es'}'
        : 'Confirm & book plan';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        border: const Border(top: BorderSide(color: ChechiBrand.border)),
      ),
      child: FilledButton(
        onPressed: busy ? null : onSubmit,
        style: FilledButton.styleFrom(
          backgroundColor: ChechiBrand.maroonDeep,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}
