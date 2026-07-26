import 'dart:convert';
import 'dart:typed_data';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:chechi_puttu_app/services/auth_service.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:chechi_puttu_app/services/customer_order_type_service.dart';
import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
  final _timeCtrl = TextEditingController();

  BulkScheduleMode _scheduleMode = BulkScheduleMode.allDays;
  final Set<String> _selectedDays = {};
  /// Dish title -> portions per delivery. Presence in this map *is* selection,
  /// so there is no separate selected-set that could disagree with it.
  final Map<String, int> _dishQuantities = {};
  final _dishSearchCtrl = TextEditingController();
  String _dishQuery = '';
  bool _busy = false;
  TimeOfDay? _pickedTime;

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
      _timeCtrl.text = init.preferredTime;
      _scheduleMode = init.scheduleMode;
      _selectedDays.addAll(init.days);
      _dishQuantities.addAll(init.dishQuantities);
    } else {
      _prefillFromAuth(user);
    }
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
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _orgCtrl.dispose();
    _personCtrl.dispose();
    _designationCtrl.dispose();
    _timeCtrl.dispose();
    _dishSearchCtrl.dispose();
    super.dispose();
  }

  String get _orgLabel => widget.orderType == CustomerOrderType.hospital
      ? 'Hospital name'
      : 'Company / organisation name';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _pickedTime ?? const TimeOfDay(hour: 8, minute: 0),
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
      _pickedTime = picked;
      final h = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final m = picked.minute.toString().padLeft(2, '0');
      final ampm = picked.period == DayPeriod.am ? 'AM' : 'PM';
      _timeCtrl.text = '$h:$m $ampm';
    });
  }

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
    if (_dishQuantities.isEmpty) {
      _showSnack('Add at least one dish to the plan');
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
        orderPersonDesignation: widget.orderType == CustomerOrderType.corporate
            ? _designationCtrl.text.trim()
            : '',
        preferredTime: _timeCtrl.text.trim(),
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
      widget.onCompleted();
    } catch (e) {
      if (mounted) {
        _showSnack('Could not save. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHospital = widget.orderType == CustomerOrderType.hospital;
    final dishCount = _dishQuantities.length;
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
                              label: 'Alternate phone (optional)',
                              icon: Icons.phone_callback_outlined,
                              keyboard: TextInputType.phone,
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
                              last: isHospital,
                            ),
                            if (!isHospital)
                              _field(
                                controller: _designationCtrl,
                                label: 'Order person job position',
                                icon: Icons.work_outline_rounded,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
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
                            _field(
                              controller: _timeCtrl,
                              label: 'Preferred delivery time',
                              icon: Icons.schedule_rounded,
                              readOnly: true,
                              onTap: _pickTime,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Pick a time'
                                  : null,
                              last: true,
                            ),
                            const SizedBox(height: 4),
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
                              'Set how many portions of each dish this plan '
                              'needs per delivery. You can update dishes later '
                              'from support chat.',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                height: 1.35,
                                color: const Color(0xFF7A6A62),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _dishSearchField(),
                            const SizedBox(height: 4),
                            ..._dishSectionBlocks(),
                          ],
                        ),
                      ),
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

  void _setDishQuantity(String title, int qty) {
    setState(() {
      if (qty <= 0) {
        _dishQuantities.remove(title);
      } else {
        _dishQuantities[title] = qty.clamp(1, kMaxDishQuantity);
      }
    });
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
  List<Widget> _dishSectionBlocks() {
    final blocks = <Widget>[];
    for (final section in kCustomerMenuSections) {
      final dishes = _dishQuery.isEmpty
          ? section.dishes
          : section.dishes
                .where(
                  (d) =>
                      d.title.toLowerCase().contains(_dishQuery) ||
                      d.subtitle.toLowerCase().contains(_dishQuery),
                )
                .toList();
      if (dishes.isEmpty) continue;
      blocks.add(_dishSectionBlock(section, dishes));
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
              sectionId: section.title,
              quantity: _dishQuantities[dish.title],
              enabled: !_busy,
              onAdd: () => _setDishQuantity(dish.title, kDefaultDishQuantity),
              onChanged: (qty) => _setDishQuantity(dish.title, qty),
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

/// One selectable dish: thumbnail, name, and either an Add button or a
/// quantity stepper. Prices are intentionally not shown — bulk plans are
/// quoted separately, so a per-plate figure here would be misleading.
class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.dish,
    required this.sectionId,
    required this.quantity,
    required this.enabled,
    required this.onAdd,
    required this.onChanged,
  });

  final MenuCatalogDish dish;
  final String sectionId;
  final int? quantity;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onChanged;

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
            _QuantityStepper(
              quantity: qty,
              enabled: enabled,
              onChanged: onChanged,
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

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });

  final int quantity;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          icon: quantity <= kDishQuantityStep
              ? Icons.delete_outline_rounded
              : Icons.remove_rounded,
          filled: false,
          // Stepping below one portion removes the dish from the plan.
          onTap: enabled ? () => onChanged(quantity - kDishQuantityStep) : null,
        ),
        SizedBox(
          width: 38,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ChechiBrand.maroonDeep,
            ),
          ),
        ),
        _StepperButton(
          icon: Icons.add_rounded,
          filled: true,
          onTap: enabled && quantity < kMaxDishQuantity
              ? () => onChanged(quantity + kDishQuantityStep)
              : null,
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? ChechiBrand.maroonDeep : Colors.transparent,
      shape: const CircleBorder(
        side: BorderSide(color: ChechiBrand.maroonDeep),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 16,
            color: filled ? Colors.white : ChechiBrand.maroonDeep,
          ),
        ),
      ),
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
