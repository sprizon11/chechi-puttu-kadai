import 'package:chechi_puttu_app/admin/admin_shop_location_screen.dart';
import 'package:chechi_puttu_app/services/shop_location_service.dart';
import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminSettingsBody extends StatefulWidget {
  const AdminSettingsBody({
    super.key,
    required this.onToggleTheme,
    required this.onOpenTab,
  });

  final VoidCallback onToggleTheme;
  final ValueChanged<int> onOpenTab;

  @override
  State<AdminSettingsBody> createState() => _AdminSettingsBodyState();
}

class _AdminSettingsBodyState extends State<AdminSettingsBody> {
  String _language = 'English';
  String _shopLocationSubtitle = 'Set kadai location on map';

  @override
  void initState() {
    super.initState();
    _loadShopLocationSubtitle();
  }

  Future<void> _loadShopLocationSubtitle() async {
    final shop = await ShopLocationService.load();
    if (!mounted) return;
    setState(() {
      _shopLocationSubtitle = shop == null
          ? 'Set kadai location on map'
          : shop.address;
    });
  }

  Future<void> _openShopLocation() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminShopLocationScreen()),
    );
    if (saved == true) {
      await _loadShopLocationSubtitle();
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showInfoDialog(String title, String message) async {
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLanguagePicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('English'),
              trailing: _language == 'English'
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(ctx, 'English'),
            ),
            ListTile(
              title: const Text('Malayalam'),
              trailing: _language == 'Malayalam'
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(ctx, 'Malayalam'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _language = picked);
      _snack('Language set to $picked');
    }
  }

  Future<void> _openNotificationsSheet() async {
    var orderAlerts = true;
    var payoutAlerts = true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Order alerts'),
                    subtitle: const Text('New orders and status changes'),
                    trailing: Switch.adaptive(
                      value: orderAlerts,
                      onChanged: (v) => setModal(() => orderAlerts = v),
                    ),
                  ),
                  ListTile(
                    title: const Text('Payout alerts'),
                    subtitle: const Text('Revenue and settlement updates'),
                    trailing: Switch.adaptive(
                      value: payoutAlerts,
                      onChanged: (v) => setModal(() => payoutAlerts = v),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (email == null || email.isEmpty) {
      _snack('No email on this account. Use email/password admin login first.');
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    _snack('Password reset link sent to $email');
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse(
      'mailto:support@chechiputtukadai.com?subject=Admin%20Support',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('Could not open mail app');
    }
  }

  Future<void> _editProfileInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Not signed in.');
      return;
    }
    final ref = chechiFirestore.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!mounted) return;
    final data = snap.data() ?? const <String, dynamic>{};

    final nameCtrl = TextEditingController(
      text: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String)
          : (user.displayName ?? ''),
    );
    final emailCtrl = TextEditingController(
      text: (data['contactEmail'] as String?)?.trim().isNotEmpty == true
          ? (data['contactEmail'] as String)
          : (user.email ?? ''),
    );
    final phoneCtrl = TextEditingController(
      text: (data['mobile'] as String?)?.trim().isNotEmpty == true
          ? (data['mobile'] as String)
          : (user.phoneNumber ?? ''),
    );

    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            'Profile Information',
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Enter email';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                        return 'Enter valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone number'),
                    validator: (v) {
                      final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (d.length < 10) return 'Enter valid phone number';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || save != true) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      return;
    }

    final nextName = nameCtrl.text.trim();
    final nextEmail = emailCtrl.text.trim().toLowerCase();
    final nextPhone = phoneCtrl.text.trim();

    try {
      if ((user.displayName ?? '').trim() != nextName) {
        await user.updateDisplayName(nextName);
      }
      if ((user.email ?? '').trim().toLowerCase() != nextEmail) {
        await user.verifyBeforeUpdateEmail(nextEmail);
      }
      await ref.set({
        'uid': user.uid,
        'displayName': nextName,
        'contactEmail': nextEmail,
        'mobile': nextPhone,
        'authEmail': user.email,
        'authPhone': user.phoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      final emailMsg =
          (user.email ?? '').trim().toLowerCase() != nextEmail
          ? '\nA verification email was sent to apply new email.'
          : '';
      _snack('Profile updated.$emailMsg');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update profile: $e');
    } finally {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    return AppPullToRefresh(
      onRefresh: AppRefresh.refreshAdminMenuData,
      child: SingleChildScrollView(
        physics: AppPullToRefresh.scrollPhysics,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: GoogleFonts.playfairDisplay(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your account, preferences and business settings',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: 'Account',
            children: [
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                iconBg: const Color(0xFFFFF0E6),
                iconColor: const Color(0xFF9A4632),
                title: 'Profile Information',
                subtitle: 'View and edit your personal details',
                onTap: _editProfileInfo,
              ),
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                iconBg: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF2E7D32),
                title: 'Change Password',
                subtitle: 'Update your password',
                onTap: _changePassword,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Business Settings',
            children: [
              _SettingsTile(
                icon: Icons.store_mall_directory_outlined,
                iconBg: const Color(0xFFFFF0E6),
                iconColor: const Color(0xFF9A4632),
                title: 'Shop location',
                subtitle: _shopLocationSubtitle,
                onTap: _openShopLocation,
              ),
              _SettingsTile(
                icon: Icons.menu_book_outlined,
                iconBg: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF2E7D32),
                title: 'Menu Management',
                subtitle: 'Manage your menu items and categories',
                onTap: () => widget.onOpenTab(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Preferences',
            children: [
              _SettingsTile(
                icon: Icons.notifications_none_rounded,
                iconBg: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF2E7D32),
                title: 'Notifications',
                subtitle: 'Choose what you want to be notified about',
                onTap: _openNotificationsSheet,
              ),
              _SettingsTile(
                icon: Icons.language_rounded,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF1565C0),
                title: 'Language',
                subtitle: 'Select your preferred language',
                trailingText: _language,
                onTap: _openLanguagePicker,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Support & Others',
            children: [
              _SettingsTile(
                icon: Icons.help_outline_rounded,
                iconBg: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF2E7D32),
                title: 'Help & Support',
                subtitle: 'Get help and contact support',
                onTap: _openSupport,
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF1565C0),
                title: 'Privacy Policy',
                subtitle: 'Read our privacy policy',
                onTap: () => _showInfoDialog(
                  'Privacy Policy',
                  'Your data is used only for order processing, account '
                      'management and service improvement.',
                ),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                iconBg: const Color(0xFFF3E5F5),
                iconColor: const Color(0xFF7B1FA2),
                title: 'Terms & Conditions',
                subtitle: 'Read our terms and conditions',
                onTap: () => _showInfoDialog(
                  'Terms & Conditions',
                  'Use the app responsibly. Orders, pricing and availability '
                      'are subject to operational updates.',
                ),
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                iconBg: const Color(0xFFFFEBEE),
                iconColor: const Color(0xFFC62828),
                title: 'Log Out',
                subtitle: 'Sign out from your account',
                onTap: () async => FirebaseAuth.instance.signOut(),
                danger: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'App Version 1.2.1',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailingText,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: danger ? const Color(0xFFC62828) : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  trailingText!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
            Icon(Icons.chevron_right_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }
}
