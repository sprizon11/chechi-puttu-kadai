import 'dart:async';

import 'package:chechi_puttu_app/services/auth_service.dart';
import 'package:chechi_puttu_app/services/user_profile_service.dart';
import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single-page profile editor (not the multi-step signup wizard).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCompleted,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onCompleted;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  DateTime? _dob;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _phoneLocked = false;

  static const _monthShort = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = authService.currentUser;
    if (user == null) return;
    final n = user.displayName?.trim();
    if (n != null && n.isNotEmpty) _nameCtrl.text = n;
    final authEmail = user.email?.trim();
    if (authEmail != null && authEmail.isNotEmpty) {
      _emailCtrl.text = authEmail;
    }
    _phoneLocked = user.phoneNumber?.trim().isNotEmpty ?? false;
    if (_phoneLocked && user.phoneNumber != null) {
      final p = AuthService.normalizePhoneForFirebase(user.phoneNumber!);
      final digits = p.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        _mobileCtrl.text = digits.length > 10
            ? digits.substring(digits.length - 10)
            : digits;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final uid = user.uid;
    final mobile = prefs.getString('chechi_profile_mobile_$uid') ?? '';
    final contactEmail =
        prefs.getString('chechi_profile_contact_email_$uid') ?? '';
    final dobStr = prefs.getString('chechi_profile_dob_$uid') ?? '';
    if (!mounted) return;
    setState(() {
      if (_mobileCtrl.text.isEmpty && mobile.isNotEmpty) {
        _mobileCtrl.text = mobile;
      }
      if (_emailCtrl.text.isEmpty && contactEmail.isNotEmpty) {
        _emailCtrl.text = contactEmail;
      }
      if (_dob == null && dobStr.length >= 10) {
        final parts = dobStr.split('-');
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (y != null && m != null && day != null) {
            _dob = DateTime(y, m, day);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _dobLabel() {
    final d = _dob;
    if (d == null) return 'Select date of birth';
    return '${d.day} ${_monthShort[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDob() async {
    if (_busy) return;
    final now = DateTime.now();
    final last = DateTime(now.year - 13, now.month, now.day);
    final initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(1900))
          ? DateTime(1900)
          : (initial.isAfter(last) ? last : initial),
      firstDate: DateTime(1900),
      lastDate: last,
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      _snack('Please choose your date of birth');
      return;
    }
    final user = authService.currentUser;
    if (user == null) {
      _snack('Not signed in');
      return;
    }
    setState(() => _busy = true);
    try {
      final name = _nameCtrl.text.trim();
      final mobile = _mobileCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      final dob = _dob!;

      if (password.isNotEmpty) {
        await authService.attachEmailPasswordForProfile(
          email: email,
          password: password,
        );
      }

      await user.reload();
      final fresh = authService.currentUser ?? user;
      final cloudSaved = await userProfileService.trySaveCustomerProfile(
        user: fresh,
        displayName: name,
        contactEmail: email,
        mobile: mobile,
        homeAddress: '',
        officeAddress: '',
        otherAddress: '',
        dateOfBirth: dob,
      );

      final uid = fresh.uid;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('chechi_profile_complete_$uid', true);
      await prefs.setString('chechi_profile_contact_email_$uid', email);
      await prefs.setString(
        'chechi_profile_dob_$uid',
        '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}',
      );
      await prefs.setString('chechi_profile_mobile_$uid', mobile);
      if (name.isNotEmpty) {
        await fresh.updateDisplayName(name);
        await fresh.reload();
      }
      if (!mounted) return;
      if (!cloudSaved) {
        _snack('Saved on this phone. Will sync when online.');
        unawaited(userProfileService.syncPendingProfileIfAny(fresh));
      } else {
        _snack('Profile updated');
      }
      widget.onCompleted();
    } catch (e) {
      if (mounted) _snack('Could not save profile. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(m, style: GoogleFonts.poppins())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: ChechiBrand.cream,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: ChechiBrand.maroonDeep,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit profile',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: ChechiBrand.maroonDeep,
                            ),
                          ),
                          Text(
                            'Update your personal details',
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
              const SizedBox(height: 8),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ChechiBrand.gold.withValues(alpha: 0.55),
                              width: 2,
                            ),
                          ),
                          child: const CircleAvatar(
                            radius: 42,
                            backgroundColor: Color(0xFFF3E8DC),
                            backgroundImage:
                                AssetImage('assets/images/hero.png'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _sectionLabel('Personal'),
                      _field(
                        controller: _nameCtrl,
                        label: 'Full name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Enter your name'
                            : null,
                      ),
                      _field(
                        controller: _mobileCtrl,
                        label: 'Mobile number',
                        icon: Icons.phone_outlined,
                        keyboard: TextInputType.phone,
                        readOnly: _phoneLocked,
                        validator: (v) {
                          final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (d.length != 10) return 'Enter 10-digit mobile';
                          if (!RegExp(r'^[6-9]').hasMatch(d)) {
                            return 'Enter a valid Indian mobile number';
                          }
                          return null;
                        },
                      ),
                      _dobTile(),
                      const SizedBox(height: 8),
                      _sectionLabel('Account'),
                      _field(
                        controller: _emailCtrl,
                        label: 'Email address',
                        icon: Icons.email_outlined,
                        keyboard: TextInputType.emailAddress,
                        validator: (v) {
                          final e = v?.trim() ?? '';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$')
                              .hasMatch(e)) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      _field(
                        controller: _passwordCtrl,
                        label: 'New password (optional)',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePassword,
                        suffix: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: const Color(0xFF7A6A62),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (v.length < 6) return 'Min 6 characters';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: FilledButton(
                  onPressed: _busy ? null : _save,
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
                          'Save changes',
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

  Widget _sectionLabel(String text) {
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
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        obscureText: obscure,
        keyboardType: keyboard,
        validator: validator,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ChechiBrand.maroonDeep,
        ),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffix,
          prefixIcon: Icon(
            icon,
            color: ChechiBrand.maroon.withValues(alpha: 0.7),
          ),
          filled: true,
          fillColor: Colors.white,
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

  Widget _dobTile() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : _pickDob,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ChechiBrand.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cake_outlined,
                  color: ChechiBrand.maroon.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date of birth',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF7A6A62),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dobLabel(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _dob == null
                              ? const Color(0xFF7A6A62)
                              : ChechiBrand.maroonDeep,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.calendar_month_outlined,
                  color: Color(0xFF7A6A62),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
