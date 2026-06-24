import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:chechi_puttu_app/services/auth_service.dart';
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
  final _timeCtrl = TextEditingController();

  BulkScheduleMode _scheduleMode = BulkScheduleMode.allDays;
  final Set<String> _selectedDays = {};
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
      _timeCtrl.text = init.preferredTime;
      _scheduleMode = init.scheduleMode;
      _selectedDays.addAll(init.days);
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
    _timeCtrl.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduleMode == BulkScheduleMode.specificDays &&
        _selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one day',
            style: GoogleFonts.poppins(),
          ),
        ),
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
        preferredTime: _timeCtrl.text.trim(),
        scheduleMode: _scheduleMode,
        days: days,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHospital = widget.orderType == CustomerOrderType.hospital;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: ChechiPremium.brandGradient()),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : widget.onChangeOrderType,
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: ChechiBrand.maroonDeep,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.orderType.title,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 22,
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
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _sectionTitle('Contact details'),
                      _field(
                        controller: _nameCtrl,
                        label: 'Your name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      _field(
                        controller: _phoneCtrl,
                        label: 'Phone number',
                        icon: Icons.phone_outlined,
                        keyboard: TextInputType.phone,
                        validator: (v) {
                          final d =
                              (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (d.length < 10) return 'Enter valid 10-digit number';
                          return null;
                        },
                      ),
                      _field(
                        controller: _altPhoneCtrl,
                        label: 'Alternate phone (optional)',
                        icon: Icons.phone_callback_outlined,
                        keyboard: TextInputType.phone,
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Organisation'),
                      _field(
                        controller: _orgCtrl,
                        label: _orgLabel,
                        icon: isHospital
                            ? Icons.local_hospital_outlined
                            : Icons.apartment_rounded,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      _field(
                        controller: _personCtrl,
                        label: 'Order contact person name',
                        icon: Icons.badge_outlined,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      _sectionTitle('Schedule'),
                      _field(
                        controller: _timeCtrl,
                        label: 'Preferred delivery time',
                        icon: Icons.schedule_rounded,
                        readOnly: true,
                        onTap: _pickTime,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Pick a time' : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Delivery days',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ChechiBrand.maroonDeep,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _scheduleModeChips(),
                      if (_scheduleMode == BulkScheduleMode.specificDays) ...[
                        const SizedBox(height: 14),
                        _weekdayChips(),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: ChechiBrand.maroonDeep,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save & continue',
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
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: GoogleFonts.playfairDisplay(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ChechiBrand.maroonDeep,
        ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
          fillColor: Colors.white.withValues(alpha: 0.92),
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
                        : Colors.white.withValues(alpha: 0.9),
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
          backgroundColor: Colors.white.withValues(alpha: 0.92),
          checkmarkColor: Colors.white,
          side: const BorderSide(color: ChechiBrand.border),
        );
      }).toList(),
    );
  }
}
