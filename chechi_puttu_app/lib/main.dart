import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:chechi_puttu_app/admin/admin_auth.dart';
import 'package:chechi_puttu_app/admin/admin_dashboard_screen.dart';
import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/customer/bulk_order_setup_screen.dart';
import 'package:chechi_puttu_app/customer/customer_chat_screen.dart';
import 'package:chechi_puttu_app/customer/edit_profile_screen.dart';
import 'package:chechi_puttu_app/customer/order_type_selection_screen.dart';
import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:chechi_puttu_app/services/customer_order_type_service.dart';
import 'package:chechi_puttu_app/delivery_location_sheet.dart';
import 'package:chechi_puttu_app/services/advance_order_schedule.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/firebase_options.dart';
import 'package:chechi_puttu_app/services/auth_service.dart';
import 'package:chechi_puttu_app/services/customer_menu_overrides.dart';
import 'package:chechi_puttu_app/services/customer_menu_section_overrides.dart';
import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:chechi_puttu_app/services/menu_deleted_dishes.dart';
import 'package:chechi_puttu_app/services/user_profile_service.dart';
import 'package:chechi_puttu_app/services/birthday_chat_wish_service.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:chechi_puttu_app/widgets/birthday_home_banner.dart';
import 'package:chechi_puttu_app/services/razorpay_checkout_service.dart';
import 'package:chechi_puttu_app/services/notifications_service.dart';
import 'package:chechi_puttu_app/services/orders_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? firebaseErr;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    firebaseErr = e;
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st));
  }
  runApp(ChechiPuttuApp(firebaseInitError: firebaseErr));
}

class ChechiPuttuApp extends StatefulWidget {
  const ChechiPuttuApp({super.key, this.firebaseInitError});

  /// Non-null if [Firebase.initializeApp] failed.
  final Object? firebaseInitError;

  @override
  State<ChechiPuttuApp> createState() => _ChechiPuttuAppState();
}

class _ChechiPuttuAppState extends State<ChechiPuttuApp> {
  final bool _isDark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chechi Puttu',
      themeMode: ThemeMode.light,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeAnimationDuration: const Duration(milliseconds: 320),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return child;
      },
      home: _StartupSplashGate(
        firebaseInitError: widget.firebaseInitError,
        isDark: _isDark,
        onToggleTheme: () {},
      ),
    );
  }
}

class _StartupSplashGate extends StatefulWidget {
  const _StartupSplashGate({
    required this.firebaseInitError,
    required this.isDark,
    required this.onToggleTheme,
  });

  final Object? firebaseInitError;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<_StartupSplashGate> createState() => _StartupSplashGateState();
}

class _StartupSplashGateState extends State<_StartupSplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) return const _AnimatedStartupSplash();
    if (widget.firebaseInitError != null) {
      return _FirebaseInitErrorBody(error: widget.firebaseInitError!);
    }
    return _AuthGateHome(
      isDark: widget.isDark,
      onToggleTheme: widget.onToggleTheme,
    );
  }
}

class _AnimatedStartupSplash extends StatefulWidget {
  const _AnimatedStartupSplash();

  @override
  State<_AnimatedStartupSplash> createState() => _AnimatedStartupSplashState();
}

class _AnimatedStartupSplashState extends State<_AnimatedStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _haloScale;
  late final Animation<double> _haloOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..forward();
    _logoScale = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.54, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.04, 0.45, curve: Curves.easeOut),
      ),
    );
    _haloScale = Tween<double>(begin: 0.8, end: 1.18).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.08, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _haloOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.4, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.32, 0.72, curve: Curves.easeOut),
      ),
    );
    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.56, 0.9, curve: Curves.easeOut),
      ),
    );
    _progress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.08, 1, curve: Curves.easeInOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _GlobalAppBackgroundLayer(
            assetPath: _GlobalAppBackgroundLayer.profileAssetPath,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.64),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _haloOpacity,
                        child: ScaleTransition(
                          scale: _haloScale,
                          child: Container(
                            width: 148,
                            height: 148,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFFF4C06A).withValues(alpha: 0.42),
                                  const Color(0xFF7C1D1B).withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeTransition(
                        opacity: _logoOpacity,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C1D1B).withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SlideTransition(
                        position: _titleSlide,
                        child: FadeTransition(
                          opacity: _titleOpacity,
                          child: Column(
                            children: [
                              Text(
                                "Sai Logabala's",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFF6D5A1),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Chechi Puttu Kadai',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.playfairDisplay(
                                  color: Colors.white,
                                  fontSize: 33,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FadeTransition(
                        opacity: _subtitleOpacity,
                        child: Text(
                          'Authentic Kerala Delights',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 30,
                  child: FadeTransition(
                    opacity: _subtitleOpacity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 4,
                        color: Colors.white.withValues(alpha: 0.2),
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _progress.value,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFF9D08A),
                                      Color(0xFFD88A2A),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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

/// Full-bleed illustrated backdrop for auth flows (login, profile setup).
class _GlobalAppBackgroundLayer extends StatelessWidget {
  const _GlobalAppBackgroundLayer({
    this.imageAlignment = Alignment.center,
    this.assetPath = _GlobalAppBackgroundLayer.loginAssetPath,
  });

  /// Login / OTP screen — replace `assets/images/login_background.png` to change.
  static const loginAssetPath = 'assets/images/login_background.png';

  /// Profile completion & other auth steps.
  static const profileAssetPath = 'assets/images/app_background.png';

  /// For [BoxFit.cover], biases which part of the bitmap stays visible when cropped.
  final Alignment imageAlignment;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _AppColors.appBackdrop),
          Positioned.fill(
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              alignment: imageAlignment,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) {
                // Fallback if login_background.png is missing.
                if (assetPath != profileAssetPath) {
                  return Image.asset(
                    profileAssetPath,
                    fit: BoxFit.cover,
                    alignment: imageAlignment,
                    filterQuality: FilterQuality.high,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Alternate background used only after login (Home + tabs).
class _PostLoginBackgroundLayer extends StatelessWidget {
  const _PostLoginBackgroundLayer();

  static const lightAssetPath = 'assets/images/post_login_background.png';
  static const darkAssetPath = 'assets/images/post_login_background_dark.png';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = dark ? darkAssetPath : lightAssetPath;
    // Solid plate behind the image so we never flash through a transparent
    // scaffold during theme changes (AnimatedSwitcher crossfade caused that).
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: dark ? const Color(0xFF120E0D) : _AppColors.appBackdrop,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Image.asset(
              asset,
              key: ValueKey(asset),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirebaseInitErrorBody extends StatelessWidget {
  const _FirebaseInitErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Firebase setup needed',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '1. In Firebase Console, add Android app package '
                '`com.chechiputtu.kadai` and download `google-services.json` → '
                '`android/app/`\n'
                '2. Run: dart pub global activate flutterfire_cli\n'
                '   dart pub global run flutterfire_cli:flutterfire configure\n'
                '   (updates `lib/firebase_options.dart`)\n'
                '3. Deploy Cloud Functions from repo `functions/` and set Razorpay secrets\n\n'
                'Error: $error',
                style: GoogleFonts.poppins(fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthGateHome extends StatefulWidget {
  const _AuthGateHome({required this.isDark, required this.onToggleTheme});

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<_AuthGateHome> createState() => _AuthGateHomeState();
}

class _AuthGateHomeState extends State<_AuthGateHome> {
  int _profileGateEpoch = 0;
  int _orderTypeGateEpoch = 0;
  late final ValueNotifier<int> _homeNavIndexNotifier;
  late final ValueNotifier<int> _adminNavIndexNotifier;
  late final ValueNotifier<List<CartLineItem>> _cartLinesNotifier;
  late final NotificationsService _notifications;
  String? _profileGateUid;
  bool? _needsProfileCompletion;
  Future<void>? _profileGateTask;
  String? _orderTypeGateUid;
  CustomerOrderTypeState? _orderTypeState;
  Future<void>? _orderTypeGateTask;

  void _handlePushDeepLink(Map<String, String> data) {
    final type = (data['type'] ?? '').trim().toLowerCase();
    if (type == 'order_chat_update' || type == 'order_update' ||
        type == 'order_status') {
      _homeNavIndexNotifier.value = 2;
      return;
    }
    if (type == 'chat_message') {
      _homeNavIndexNotifier.value = 4;
      return;
    }
  }

  @override
  void initState() {
    super.initState();
    _homeNavIndexNotifier = ValueNotifier<int>(0);
    _adminNavIndexNotifier = ValueNotifier<int>(0);
    _cartLinesNotifier = ValueNotifier<List<CartLineItem>>([]);
    _notifications = NotificationsService(onDeepLink: _handlePushDeepLink);
    _notifications.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MenuDeletedDishes.instance.reloadFromPrefs();
      MenuDeletedDishes.instance.addListener(() {
        CustomerMenuSectionOverrides.instance.rebuildFromDishOverrides();
      });
      authService.authStateChanges.listen((user) {
        if (user != null) {
          unawaited(userProfileService.syncPendingProfileIfAny(user));
        }
      });
    });
  }

  @override
  void dispose() {
    _homeNavIndexNotifier.dispose();
    _adminNavIndexNotifier.dispose();
    _cartLinesNotifier.dispose();
    _notifications.dispose();
    super.dispose();
  }

  void _onProfileGateRefresh() {
    setState(() {
      _profileGateEpoch++;
      _needsProfileCompletion = false;
      _profileGateTask = null;
    });
  }

  void _onOrderTypeGateRefresh() {
    setState(() {
      _orderTypeGateEpoch++;
      _orderTypeState = null;
      _orderTypeGateTask = null;
    });
  }

  Future<void> _onOrderTypeChosen(CustomerOrderType type) async {
    final user = authService.currentUser;
    if (user == null) return;
    await customerOrderTypeService.saveOrderType(user: user, type: type);
    if (!mounted || _orderTypeGateUid != user.uid) return;
    final state = await customerOrderTypeService.loadState(user.uid);
    if (!mounted || _orderTypeGateUid != user.uid) return;
    setState(() => _orderTypeState = state);
  }

  void _ensureOrderTypeGateState(User user) {
    if (_orderTypeGateUid == user.uid && _orderTypeState != null) return;
    if (_orderTypeGateUid == user.uid && _orderTypeGateTask != null) return;

    _orderTypeGateUid = user.uid;
    _orderTypeState = null;
    _orderTypeGateTask = customerOrderTypeService
        .loadState(user.uid)
        .then((state) {
          if (!mounted || _orderTypeGateUid != user.uid) return;
          setState(() => _orderTypeState = state);
        })
        .whenComplete(() {
          if (mounted && _orderTypeGateUid == user.uid) {
            _orderTypeGateTask = null;
          }
        });
  }

  void _ensureProfileGateState(User user) {
    if (_profileGateUid == user.uid && _needsProfileCompletion != null) return;
    if (_profileGateUid == user.uid && _profileGateTask != null) return;

    _profileGateUid = user.uid;
    _needsProfileCompletion = null;
    _profileGateTask = _shouldPromptCompleteProfile(user)
        .then((needsProfile) {
          if (!mounted || _profileGateUid != user.uid) return;
          setState(() => _needsProfileCompletion = needsProfile);
        })
        .whenComplete(() {
          if (mounted && _profileGateUid == user.uid) _profileGateTask = null;
        });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          _homeNavIndexNotifier.value = 0;
          _adminNavIndexNotifier.value = 0;
          _cartLinesNotifier.value = [];
          _profileGateUid = null;
          _needsProfileCompletion = null;
          _profileGateTask = null;
          _orderTypeGateUid = null;
          _orderTypeState = null;
          _orderTypeGateTask = null;
          return LoginScreen(
            isDark: widget.isDark,
            onToggleTheme: widget.onToggleTheme,
          );
        }
        if (isChechiAdminUser(user)) {
          return AdminDashboardScreen(
            onToggleTheme: widget.onToggleTheme,
            navIndexNotifier: _adminNavIndexNotifier,
          );
        }
        _ensureOrderTypeGateState(user);
        if (_orderTypeState == null) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_orderTypeState!.needsOrderTypeSelection) {
          return OrderTypeSelectionScreen(
            key: ValueKey<Object?>('ot_${user.uid}_$_orderTypeGateEpoch'),
            onTypeChosen: _onOrderTypeChosen,
          );
        }
        final bulkType = _orderTypeState!.orderType;
        if (_orderTypeState!.needsBulkEnrollment && bulkType != null) {
          return BulkOrderSetupScreen(
            key: ValueKey<Object?>('bulk_${user.uid}_$_orderTypeGateEpoch'),
            orderType: bulkType,
            initial: _orderTypeState!.bulkEnrollment,
            onCompleted: _onOrderTypeGateRefresh,
            onChangeOrderType: () async {
              await customerOrderTypeService.clearOrderTypeSelection(user.uid);
              if (!mounted) return;
              _onOrderTypeGateRefresh();
            },
          );
        }
        _ensureProfileGateState(user);
        if (_needsProfileCompletion == null) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_needsProfileCompletion == true) {
          return CompleteProfileScreen(
            key: ValueKey<Object?>('cp_${user.uid}_$_profileGateEpoch'),
            isDark: widget.isDark,
            onToggleTheme: widget.onToggleTheme,
            onCompleted: _onProfileGateRefresh,
          );
        }
        return HomeScreen(
          key: ValueKey<String>('home_${user.uid}'),
          isDark: widget.isDark,
          onToggleTheme: widget.onToggleTheme,
          navIndexNotifier: _homeNavIndexNotifier,
          cartLinesNotifier: _cartLinesNotifier,
        );
      },
    );
  }
}

String _readableAuthError(Object e) {
  if (e is FirebaseException && e.plugin == 'cloud_firestore') {
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Could not reach the server. Check mobile data or Wi‑Fi, '
            'then tap FINISH again.';
      case 'permission-denied':
        return 'Profile could not be saved (permission denied). '
            'Sign out and sign in again, or contact support.';
      default:
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty) return msg;
        return 'Could not save profile (${e.code}). Please try again.';
    }
  }
  if (e is FirebaseAuthException) {
    final code = e.code;
    final raw = e.message ?? '';
    final lower = raw.toLowerCase();
    if (code == 'network-request-failed') {
      return 'No internet connection. Check Wi‑Fi or mobile data and try again.';
    }
    if (code == 'invalid-app-credential' ||
        code == 'missing-client-identifier' ||
        lower.contains('play_integrity') ||
        lower.contains('app check')) {
      return 'Phone login is not configured for this build. '
          'In Firebase, add your app SHA-1 (debug SHA for USB install, '
          'Play signing SHA for Play Store). Then try again.';
    }
    // Firebase phone abuse / rate limits (message text varies by SDK).
    if (code == 'too-many-requests' ||
        lower.contains('blocked all requests') ||
        lower.contains('unusual activity')) {
      return 'Firebase temporarily blocked phone sign-in on this device '
          '(too many attempts). Wait several hours, switch Wi‑Fi/mobile data, '
          'or use Google / email. For testing: Firebase Console → '
          'Authentication → Phone → add a test number + fixed OTP.';
    }
    return raw.isNotEmpty ? raw : code;
  }
  return e.toString();
}

/// Bottom inset so form clears the “Made with Love” text on the maroon band.
double _authScreenBottomGap(BuildContext context) {
  final sh = MediaQuery.sizeOf(context).height;
  final safe = MediaQuery.viewPaddingOf(context).bottom;
  // Use a smaller footer overlap on compact screens to give the form more room.
  final footerOverlay = sh < 950 ? 72.0 : 188.0;
  final minClear = footerOverlay + safe;
  final soft = (sh * 0.14 + safe + 14).clamp(100.0, 158.0);
  return soft >= minClear ? soft : minClear;
}

ThemeData _buildLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _AppColors.primary),
  );

  final scheme = base.colorScheme.copyWith(
    primary: _AppColors.primary,
    onPrimary: Colors.white,
    secondary: ChechiBrand.accent,
    surface: ChechiBrand.creamCard,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: _AppColors.appBackdrop,
    dividerColor: _AppColors.border,
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
    pageTransitionsTheme: _appPageTransitionsTheme(),
    cardTheme: CardThemeData(
      elevation: 0,
      color: ChechiBrand.creamCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _AppColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _AppColors.primary,
        side: const BorderSide(color: _AppColors.border, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AppColors.primary, width: 1.5),
      ),
    ),
  );
}

ThemeData _buildDarkTheme() {
  // Keep the same brand primary, but swap surfaces/backgrounds for dark.
  const cream = Color(0xFFF3E9DE);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: _AppColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF1C1715),
        onSurface: cream,
        surfaceContainerLow: const Color(0xFF241E1B),
        surfaceContainer: const Color(0xFF2B2421),
        outline: const Color(0xFF3A312D),
        outlineVariant: const Color(0xFF2F2724),
        onSurfaceVariant: const Color(0xFFE7DCCF),
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF120E0D),
    dividerColor: const Color(0xFF2F2724),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    textTheme: GoogleFonts.poppinsTextTheme(
      base.textTheme,
    ).apply(bodyColor: cream, displayColor: cream),
    pageTransitionsTheme: _appPageTransitionsTheme(),
  );
}

class _SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(enter),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.014, 0),
          end: Offset.zero,
        ).animate(enter),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.97).animate(exit),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.01, 0),
            ).animate(exit),
            child: child,
          ),
        ),
      ),
    );
  }
}

PageTransitionsTheme _appPageTransitionsTheme() {
  return PageTransitionsTheme(
    builders: {
      for (final TargetPlatform p in TargetPlatform.values)
        p: const _SmoothPageTransitionsBuilder(),
    },
  );
}

class _Theme {
  static Color surfaceLow(BuildContext c) =>
      Theme.of(c).colorScheme.surfaceContainerLow;
  static Color border(BuildContext c) => Theme.of(c).colorScheme.outlineVariant;
  static Color text(BuildContext c) => Theme.of(c).colorScheme.onSurface;
  static Color muted(BuildContext c) {
    final t = Theme.of(c);
    if (t.brightness == Brightness.dark) {
      return t.colorScheme.onSurface.withValues(alpha: 0.72);
    }
    return t.colorScheme.onSurfaceVariant;
  }

  static Color primary(BuildContext c) => Theme.of(c).colorScheme.primary;
}

/// Shown in app bars on login, tabs, and profile completion.
class _RoundThemeToggle extends StatelessWidget {
  const _RoundThemeToggle({required this.isDark, required this.onToggle});

  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    assert(() {
      isDark;
      onToggle;
      return true;
    }());
    return const SizedBox.shrink();
  }
}

Future<bool> _shouldPromptCompleteProfile(User user) async {
  final prefs = await SharedPreferences.getInstance();
  try {
    final completeInFirestore = await userProfileService
        .isProfileComplete(user.uid)
        .timeout(const Duration(seconds: 12));
    if (completeInFirestore) return false;
    // If profile doc is missing in Firestore, always treat as a new user flow
    // even when older local prefs still exist on device.
    return true;
  } on TimeoutException {
    if (prefs.getBool(_profileCompleteKey(user.uid)) == true) return false;
    return true;
  } catch (_) {
    // Offline/rules issue: fall back to device-only uid flag.
    if (prefs.getBool(_profileCompleteKey(user.uid)) == true) return false;
    return true;
  }
}

/// Same account can be recognized after reinstall / new device when email matches.
String? _profileCompleteEmailPrefKey(String? email) {
  final e = email?.trim().toLowerCase();
  if (e == null || e.isEmpty) return null;
  return 'chechi_profile_complete_email_$e';
}

String _profileCompleteKey(String uid) => 'chechi_profile_complete_$uid';
String _profileMobileKey(String uid) => 'chechi_profile_mobile_$uid';
String _profileLocationKey(String uid) => 'chechi_profile_location_$uid';
String _profileDobKey(String uid) => 'chechi_profile_dob_$uid';
String _profileContactEmailKey(String uid) =>
    'chechi_profile_contact_email_$uid';
String _profileAddrHomeKey(String uid) => 'chechi_profile_addr_home_$uid';
String _profileAddrOfficeKey(String uid) => 'chechi_profile_addr_office_$uid';
String _profileAddrOtherKey(String uid) => 'chechi_profile_addr_other_$uid';
String _deliveryLabelKey(String uid) => 'chechi_delivery_label_$uid';
String _deliveryStreetKey(String uid) => 'chechi_delivery_street_$uid';
String _deliveryLatKey(String uid) => 'chechi_delivery_lat_$uid';
String _deliveryLngKey(String uid) => 'chechi_delivery_lng_$uid';
String _savedHomeKey(String uid) => 'chechi_saved_home_$uid';
String _savedWorkKey(String uid) => 'chechi_saved_work_$uid';
String _savedOtherKey(String uid) => 'chechi_saved_other_$uid';
const String kMenuSectionSchedulePrefsKey = 'chechi_menu_section_schedule_v1';

class _ProfileStoredData {
  const _ProfileStoredData({required this.mobile, required this.location});

  final String mobile;
  final String location;
}

Future<_ProfileStoredData> _readStoredProfileData(User? user) async {
  final prefs = await SharedPreferences.getInstance();
  final uid = user?.uid;
  final mobile = uid == null
      ? (prefs.getString('chechi_profile_mobile') ?? '')
      : (prefs.getString(_profileMobileKey(uid)) ??
            prefs.getString('chechi_profile_mobile') ??
            '');
  final location = uid == null
      ? (prefs.getString('chechi_profile_location') ?? '')
      : (prefs.getString(_profileAddrHomeKey(uid)) ??
            prefs.getString(_profileLocationKey(uid)) ??
            prefs.getString('chechi_profile_location') ??
            '');
  return _ProfileStoredData(mobile: mobile, location: location);
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCompleted,
    this.forProfileEdit = false,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onCompleted;

  /// When true, back pops without signing out; primary action still saves profile.
  final bool forProfileEdit;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  static const int _kStepCount = 4;
  int _step = 0;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  bool _busy = false;
  DateTime? _dob;
  bool _lockVerifiedMobile = false;
  bool _obscurePassword = true;

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

  String _dobDisplayLabel() {
    final d = _dob;
    if (d == null) return 'Choose date of birth';
    return '${d.day} ${_monthShort[d.month - 1]} ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    final user = authService.currentUser;
    final n = user?.displayName?.trim();
    if (n != null && n.isNotEmpty) {
      _nameCtrl.text = n;
    }
    final authEmail = user?.email?.trim();
    if (authEmail != null && authEmail.isNotEmpty) {
      _emailCtrl.text = authEmail;
    }
    _lockVerifiedMobile =
        !widget.forProfileEdit &&
        (user?.phoneNumber?.trim().isNotEmpty ?? false);
    if (_lockVerifiedMobile && user?.phoneNumber != null) {
      final p = AuthService.normalizePhoneForFirebase(user!.phoneNumber!);
      final digits = p.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 12 && digits.startsWith('91')) {
        _mobileCtrl.text = digits.substring(2);
      } else if (digits.length >= 10) {
        _mobileCtrl.text = digits.length > 10
            ? digits.substring(digits.length - 10)
            : digits;
      } else {
        _mobileCtrl.text = user.phoneNumber!.trim();
      }
    }
    _prefillSavedProfile(user);
  }

  Future<void> _prefillSavedProfile(User? user) async {
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = user.uid;
    final mobile =
        prefs.getString(_profileMobileKey(uid)) ??
        prefs.getString('chechi_profile_mobile') ??
        '';
    final contactEmail = prefs.getString(_profileContactEmailKey(uid)) ?? '';
    final dobStr = prefs.getString(_profileDobKey(uid)) ?? '';
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

  Future<void> _pickDob() async {
    if (_busy) return;
    final now = DateTime.now();
    final last = DateTime(now.year - 13, now.month, now.day);
    final initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    final first = DateTime(1900);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        if (_nameCtrl.text.trim().length < 2) {
          _snack('Please enter your full name');
          return false;
        }
        if (!_lockVerifiedMobile) {
          final digits = _mobileCtrl.text.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 10) {
            _snack('Please enter a valid 10-digit mobile number');
            return false;
          }
        }
        return true;
      case 1:
        final e = _emailCtrl.text.trim();
        if (e.isEmpty || !e.contains('@')) {
          _snack('Please enter a valid email address');
          return false;
        }
        return true;
      case 2:
        final p = _passwordCtrl.text;
        if (p.length < 6) {
          _snack('Password must be at least 6 characters');
          return false;
        }
        return true;
      case 3:
        if (_dob == null) {
          _snack('Please choose your date of birth');
          return false;
        }
        return true;
    }
    return true;
  }

  void _onPrimary() {
    if (_busy) return;
    if (_step < _kStepCount - 1) {
      if (!_validateStep(_step)) return;
      setState(() => _step++);
      return;
    }
    if (!_validateStep(3)) return;
    unawaited(_continue());
  }

  void _onBack() {
    if (_busy || _step <= 0) return;
    setState(() => _step--);
  }

  Future<void> _continue() async {
    if (!_validateStep(0) ||
        !_validateStep(1) ||
        !_validateStep(2) ||
        !_validateStep(3)) {
      return;
    }
    if (!_lockVerifiedMobile || widget.forProfileEdit) {
      final digits = _mobileCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 10) {
        _snack('Please enter a valid mobile number');
        setState(() => _step = 0);
        return;
      }
    }
    final name = _nameCtrl.text.trim();
    final contactEmail = _emailCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    const home = '';
    const office = '';
    const other = '';
    final dob = _dob!;
    setState(() => _busy = true);
    try {
      final u = authService.currentUser;
      final uid = u?.uid;
      if (u == null || uid == null) {
        _snack('Not signed in');
        return;
      }
      await authService.attachEmailPasswordForProfile(
        email: contactEmail,
        password: _passwordCtrl.text,
      );
      await u.reload();
      final uFresh = authService.currentUser;
      if (uFresh == null) {
        _snack('Not signed in');
        return;
      }
      final cloudSaved = await userProfileService.trySaveCustomerProfile(
        user: uFresh,
        displayName: name,
        contactEmail: contactEmail,
        mobile: mobile,
        homeAddress: home,
        officeAddress: office,
        otherAddress: other,
        dateOfBirth: dob,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_profileCompleteKey(uid), true);
      await prefs.setString(_profileContactEmailKey(uid), contactEmail);
      await prefs.setString(
        _profileDobKey(uid),
        '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}',
      );
      await prefs.setString(_profileMobileKey(uid), mobile);
      await prefs.setString(_profileAddrHomeKey(uid), home);
      await prefs.setString(_profileAddrOfficeKey(uid), office);
      await prefs.setString(_profileAddrOtherKey(uid), other);
      await prefs.setString(_profileLocationKey(uid), home);
      await prefs.setString(_savedHomeKey(uid), home);
      await prefs.setString(_savedWorkKey(uid), office);
      await prefs.setString(_savedOtherKey(uid), other);
      await prefs.setString(_deliveryLabelKey(uid), 'Delivery');
      await prefs.setString(_deliveryStreetKey(uid), home);
      await prefs.remove(_deliveryLatKey(uid));
      await prefs.remove(_deliveryLngKey(uid));
      final emailKey = _profileCompleteEmailPrefKey(uFresh.email);
      if (emailKey != null) {
        await prefs.setBool(emailKey, true);
      }
      await prefs.setBool('chechi_profile_complete', true);
      await prefs.setString('chechi_profile_mobile', mobile);
      await prefs.setString('chechi_profile_location', home);
      if (name.isNotEmpty) {
        await uFresh.updateDisplayName(name);
        await uFresh.reload();
      }
      if (!mounted) return;
      if (!cloudSaved) {
        _snack(
          'Saved on this phone. Server was busy — we will sync when online. '
          'You can use the app now.',
        );
        unawaited(userProfileService.syncPendingProfileIfAny(uFresh));
      }
      widget.onCompleted();
    } catch (e) {
      if (mounted) _snack(_readableAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _stepHeadline(String a, String b, Color orange, Color titleMaroon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          a,
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            color: orange,
            fontSize: 19,
            height: 1.05,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          b,
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            color: titleMaroon,
            fontSize: 19,
            height: 1.05,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// Keeps titles left of the illustrated arc on the auth backdrop.
  Widget _stepHeadlineClearOfArt(
    BuildContext context,
    String a,
    String b,
    Color orange,
    Color titleMaroon,
  ) {
    final pad = (MediaQuery.sizeOf(context).width * 0.20).clamp(52.0, 88.0);
    return Padding(
      padding: EdgeInsets.only(left: 2, right: pad),
      child: _stepHeadline(a, b, orange, titleMaroon),
    );
  }

  /// Edit profile uses a solid form card; keep titles centered. Signup keeps
  /// headlines padded away from the illustrated arc on the full-bleed backdrop.
  Widget _profileStepHeadlineForMode(
    BuildContext context,
    String a,
    String b,
    Color orange,
    Color titleMaroon,
  ) {
    if (widget.forProfileEdit) {
      return _stepHeadline(a, b, orange, titleMaroon);
    }
    return _stepHeadlineClearOfArt(context, a, b, orange, titleMaroon);
  }

  double _profileSignupArtPadR(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.46).clamp(130.0, 190.0);
  }

  /// First signup step — matches “Create your account” marketing layout.
  String _signupStepTitle(int step) {
    switch (step) {
      case 0:
        return 'Name & phone';
      case 1:
        return 'Email';
      case 2:
        return 'Password';
      default:
        return 'Date of birth';
    }
  }

  Widget _signupProgressStrip(Color active, Color inactive, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(_kStepCount, (i) {
              final on = i <= _step;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 4,
                    decoration: BoxDecoration(
                      color: on ? active : inactive,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${_step + 1} of $_kStepCount · ${_signupStepTitle(_step)}',
            style: GoogleFonts.poppins(
              color: labelColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCreateSignupHeader(
    BuildContext context,
    Color orange,
    Color titleMaroon,
    Color bodyMuted,
  ) {
    final w = MediaQuery.sizeOf(context).width;
    final padR = _profileSignupArtPadR(context);
    final subtitleMax = (w * 0.52).clamp(156.0, 198.0);
    final createSize = (w * 0.095).clamp(34.0, 40.0);
    final accountSize = (w * 0.075).clamp(26.0, 30.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(6, 6, padR, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create',
            style: GoogleFonts.playfairDisplay(
              color: orange,
              fontSize: createSize,
              height: 0.98,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -4),
            child: Text(
              'Your Account',
              style: GoogleFonts.playfairDisplay(
                color: titleMaroon,
                fontSize: accountSize,
                height: 1.06,
                letterSpacing: -0.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: subtitleMax),
            child: Text(
              'Sign up to enjoy\n'
              'authentic flavors and a delightful\n'
              'experience with Chechi\n'
              'Puttu Kadai.',
              softWrap: true,
              style: GoogleFonts.poppins(
                color: bodyMuted,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileStepBody(
    BuildContext context,
    Color orange,
    Color titleMaroon,
    Color bodyMuted,
    Color fieldBg,
    Color fieldBr,
  ) {
    switch (_step) {
      case 0:
        return _buildStepName(
          context,
          orange,
          titleMaroon,
          bodyMuted,
          fieldBg,
          fieldBr,
        );
      case 1:
        return _buildStepEmail(
          context,
          orange,
          titleMaroon,
          bodyMuted,
          fieldBg,
          fieldBr,
        );
      case 2:
        return _buildStepPassword(
          context,
          orange,
          titleMaroon,
          bodyMuted,
          fieldBg,
          fieldBr,
        );
      default:
        return _buildStepDob(
          context,
          orange,
          titleMaroon,
          bodyMuted,
          fieldBg,
          fieldBr,
        );
    }
  }

  /// Next / FINISH on simplified signup — fixed width for bottom-right placement.
  Widget _profileSimplifiedSignupPrimary(Color btnBg) {
    final last = _step >= _kStepCount - 1;
    return SizedBox(
      width: 172,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: btnBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _busy ? null : _onPrimary,
          child: _busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : last
              ? Text(
                  'FINISH',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Next',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _profileSimplifiedSignupBackField(Color titleMaroon, Color fieldBr) {
    return SizedBox(
      width: 88,
      height: 48,
      child: OutlinedButton(
        onPressed: _busy ? null : _onBack,
        style: OutlinedButton.styleFrom(
          foregroundColor: titleMaroon,
          side: BorderSide(color: fieldBr),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: Text(
          'BACK',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 11),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE56B1F);
    const maroonTitle = Color(0xFF5D1109);
    const maroonBtn = Color(0xFF5D1109);
    const btnBg = maroonBtn;
    const fieldFill = Color(0xFFFAF5ED);
    const fieldBorder = Color(0xFFE0D5C1);
    const subtext = Color(0xFF5C4A42);
    const titleMaroon = maroonTitle;
    const bodyMuted = subtext;
    const fieldBg = fieldFill;
    const fieldBr = fieldBorder;
    final simplifiedSignup = !widget.forProfileEdit;
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    // Keep NEXT/BACK above bottom band + “Made with Love” overlay + home indicator.
    const maroonFooterBottom = 56.0;
    const maroonFooterHeight = 96.0;
    const gapAboveMaroon = 34.0;
    final profileActionBottom =
        maroonFooterBottom + viewBottom + maroonFooterHeight + gapAboveMaroon;
    final profileContentBottom = simplifiedSignup
        ? maroonFooterBottom + viewBottom + 12
        : profileActionBottom + 48 + 32;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _GlobalAppBackgroundLayer(
              assetPath: _GlobalAppBackgroundLayer.profileAssetPath,
              imageAlignment: widget.forProfileEdit
                  ? const Alignment(-0.55, 0.2)
                  : const Alignment(-0.72, -0.38),
            ),
            SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Positioned.fill(
                    bottom: profileContentBottom,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              InkWell(
                                onTap: () async {
                                  if (widget.forProfileEdit) {
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                    return;
                                  }
                                  await authService.signOut();
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    color: maroonTitle,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              _RoundThemeToggle(
                                isDark: widget.isDark,
                                onToggle: widget.onToggleTheme,
                              ),
                            ],
                          ),
                          if (!widget.forProfileEdit) ...[
                            const SizedBox(height: 28),
                            _profileCreateSignupHeader(
                              context,
                              orange,
                              titleMaroon,
                              bodyMuted,
                            ),
                            _signupProgressStrip(btnBg, fieldBr, bodyMuted),
                            const SizedBox(height: 4),
                          ],
                          if (widget.forProfileEdit)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: fieldBg,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: fieldBr),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF5D1109,
                                        ).withValues(alpha: 0.07),
                                        blurRadius: 22,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      16,
                                      14,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: Row(
                                            children: List.generate(_kStepCount, (
                                              i,
                                            ) {
                                              final on = i <= _step;
                                              return Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 3,
                                                      ),
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 220,
                                                    ),
                                                    height: 4,
                                                    decoration: BoxDecoration(
                                                      color: on
                                                          ? btnBg
                                                          : fieldBorder,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            99,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Step ${_step + 1} of $_kStepCount',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: bodyMuted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        _InputCard(
                                          height: 44,
                                          horizontalPadding: 10,
                                          radius: 10,
                                          borderColor: fieldBr,
                                          fillColor: Colors.white,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.phone_outlined,
                                                size: 18,
                                                color: bodyMuted,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextField(
                                                  controller: _mobileCtrl,
                                                  enabled: !_busy,
                                                  keyboardType:
                                                      TextInputType.phone,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: titleMaroon,
                                                  ),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                    hintText: 'Mobile number',
                                                    hintStyle:
                                                        GoogleFonts.poppins(
                                                          color: bodyMuted
                                                              .withValues(
                                                                alpha: 0.85,
                                                              ),
                                                          fontSize: 14,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            physics:
                                                const ClampingScrollPhysics(),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 320,
                                                  ),
                                                  switchInCurve:
                                                      Curves.easeOutCubic,
                                                  switchOutCurve:
                                                      Curves.easeInCubic,
                                                  transitionBuilder:
                                                      (child, animation) {
                                                        final slide =
                                                            CurvedAnimation(
                                                              parent: animation,
                                                              curve: Curves
                                                                  .easeOutCubic,
                                                            );
                                                        return FadeTransition(
                                                          opacity: animation,
                                                          child: SlideTransition(
                                                            position:
                                                                Tween<Offset>(
                                                                  begin:
                                                                      const Offset(
                                                                        0.04,
                                                                        0,
                                                                      ),
                                                                  end: Offset
                                                                      .zero,
                                                                ).animate(
                                                                  slide,
                                                                ),
                                                            child: child,
                                                          ),
                                                        );
                                                      },
                                                  child: KeyedSubtree(
                                                    key: ValueKey<int>(_step),
                                                    child: _profileStepBody(
                                                      context,
                                                      orange,
                                                      titleMaroon,
                                                      bodyMuted,
                                                      fieldBg,
                                                      fieldBr,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    physics: simplifiedSignup
                                        ? const NeverScrollableScrollPhysics()
                                        : const ClampingScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: simplifiedSignup
                                            ? 0.0
                                            : constraints.maxHeight,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const SizedBox(height: 4),
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 320,
                                            ),
                                            switchInCurve: Curves.easeOutCubic,
                                            switchOutCurve: Curves.easeInCubic,
                                            transitionBuilder:
                                                (child, animation) {
                                                  final slide = CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOutCubic,
                                                  );
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                          0.04,
                                                          0,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(slide),
                                                      child: child,
                                                    ),
                                                  );
                                                },
                                            child: KeyedSubtree(
                                              key: ValueKey<int>(_step),
                                              child: _profileStepBody(
                                                context,
                                                orange,
                                                titleMaroon,
                                                bodyMuted,
                                                fieldBg,
                                                fieldBr,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: profileActionBottom,
                    child: simplifiedSignup
                        ? const SizedBox.shrink()
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (_step > 0)
                                Expanded(
                                  child: SizedBox(
                                    height: 44,
                                    child: OutlinedButton(
                                      onPressed: _busy ? null : _onBack,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: titleMaroon,
                                        side: BorderSide(color: fieldBr),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'BACK',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_step > 0) const SizedBox(width: 10),
                              Expanded(
                                flex: _step > 0 ? 2 : 1,
                                child: SizedBox(
                                  height: 44,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: btnBg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.35,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: _busy ? null : _onPrimary,
                                      child: _busy
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : _step < _kStepCount - 1
                                          ? Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Next',
                                                  style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.4,
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.arrow_forward_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ],
                                            )
                                          : Text(
                                              widget.forProfileEdit
                                                  ? 'SAVE'
                                                  : 'FINISH',
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.9,
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepName(
    BuildContext context,
    Color orange,
    Color titleMaroon,
    Color bodyMuted,
    Color fieldBg,
    Color fieldBr,
  ) {
    final createStyle = !widget.forProfileEdit && _step == 0;
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!createStyle) ...[
          _profileStepHeadlineForMode(
            context,
            'Your',
            'name',
            orange,
            titleMaroon,
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the name we should use for your orders.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          Text(
            "Let's start with your",
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Full Name',
            style: GoogleFonts.playfairDisplay(
              color: titleMaroon,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        createStyle
            ? _AuthGlassInputCard(
                icon: Icons.person_outline_rounded,
                iconColor: bodyMuted,
                child: Material(
                  color: Colors.transparent,
                  child: TextField(
                    controller: _nameCtrl,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: titleMaroon,
                    ),
                    decoration: authGlassFieldDecoration(
                      hintText: 'Enter your full name',
                    ),
                  ),
                ),
              )
            : _InputCard(
                borderColor: fieldBr,
                fillColor: fieldBg,
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: bodyMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: titleMaroon,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Full name',
                          hintStyle: GoogleFonts.poppins(
                            color: bodyMuted.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        if (createStyle && !_lockVerifiedMobile) ...[
          const SizedBox(height: 14),
          Text(
            'Mobile number',
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _AuthGlassInputCard(
            icon: Icons.phone_outlined,
            iconColor: bodyMuted,
            child: Material(
              color: Colors.transparent,
              child: TextField(
                controller: _mobileCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: titleMaroon,
                ),
                decoration: authGlassFieldDecoration(
                  hintText: '10-digit mobile number',
                ),
              ),
            ),
          ),
        ],
        if (createStyle) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: _profileSimplifiedSignupPrimary(const Color(0xFF5D1109)),
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: double.infinity, child: inner),
    );
  }

  Widget _profileSimplifiedSignupActions(
    Color titleMaroon,
    Color fieldBr,
    Color btnBg,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_step > 0) _profileSimplifiedSignupBackField(titleMaroon, fieldBr),
        const Spacer(),
        _profileSimplifiedSignupPrimary(btnBg),
      ],
    );
  }

  Widget _buildStepEmail(
    BuildContext context,
    Color orange,
    Color titleMaroon,
    Color bodyMuted,
    Color fieldBg,
    Color fieldBr,
  ) {
    final signupAlign = !widget.forProfileEdit;
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!signupAlign) ...[
          _profileStepHeadlineForMode(
            context,
            'Your',
            'email',
            orange,
            titleMaroon,
          ),
          const SizedBox(height: 12),
          Text(
            'For receipts and order updates.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          Text(
            'Next, enter your',
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Email Address',
            style: GoogleFonts.playfairDisplay(
              color: titleMaroon,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        signupAlign
            ? _AuthGlassInputCard(
                icon: Icons.email_outlined,
                iconColor: bodyMuted,
                child: Material(
                  color: Colors.transparent,
                  child: TextField(
                    controller: _emailCtrl,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: titleMaroon,
                    ),
                    decoration: authGlassFieldDecoration(
                      hintText: 'Enter your email address',
                    ),
                  ),
                ),
              )
            : _InputCard(
                borderColor: fieldBr,
                fillColor: fieldBg,
                child: Row(
                  children: [
                    Icon(Icons.email_outlined, size: 18, color: bodyMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _emailCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: titleMaroon,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Email address',
                          hintStyle: GoogleFonts.poppins(
                            color: bodyMuted.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        if (signupAlign) ...[
          const SizedBox(height: 12),
          _profileSimplifiedSignupActions(
            titleMaroon,
            fieldBr,
            const Color(0xFF5D1109),
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: double.infinity, child: inner),
    );
  }

  Widget _buildStepPassword(
    BuildContext context,
    Color orange,
    Color titleMaroon,
    Color bodyMuted,
    Color fieldBg,
    Color fieldBr,
  ) {
    final signupAlign = !widget.forProfileEdit;
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!signupAlign) ...[
          _profileStepHeadlineForMode(
            context,
            'Account',
            'password',
            orange,
            titleMaroon,
          ),
          const SizedBox(height: 12),
          Text(
            'At least 6 characters. Used to sign in with your email.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          Text(
            'Create a',
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Password',
            style: GoogleFonts.playfairDisplay(
              color: titleMaroon,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        signupAlign
            ? _AuthGlassInputCard(
                icon: Icons.lock_outline_rounded,
                iconColor: bodyMuted,
                trailing: IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: bodyMuted,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: TextField(
                    controller: _passwordCtrl,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: titleMaroon,
                    ),
                    decoration: authGlassFieldDecoration(
                      hintText: 'Enter password (min 6 characters)',
                    ),
                  ),
                ),
              )
            : _InputCard(
                borderColor: fieldBr,
                fillColor: fieldBg,
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 18, color: bodyMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _passwordCtrl,
                        enabled: !_busy,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: titleMaroon,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'New password',
                          hintStyle: GoogleFonts.poppins(
                            color: bodyMuted.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: bodyMuted,
                      ),
                    ),
                  ],
                ),
              ),
        if (signupAlign) ...[
          const SizedBox(height: 12),
          _profileSimplifiedSignupActions(
            titleMaroon,
            fieldBr,
            const Color(0xFF5D1109),
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: double.infinity, child: inner),
    );
  }

  Widget _buildStepDob(
    BuildContext context,
    Color orange,
    Color titleMaroon,
    Color bodyMuted,
    Color fieldBg,
    Color fieldBr,
  ) {
    final signupAlign = !widget.forProfileEdit;
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!signupAlign) ...[
          _profileStepHeadlineForMode(
            context,
            'Date of',
            'birth',
            orange,
            titleMaroon,
          ),
          const SizedBox(height: 12),
          Text(
            'You must be at least 13 years old.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ] else ...[
          Text(
            'Almost done',
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Date of birth',
            style: GoogleFonts.playfairDisplay(
              color: titleMaroon,
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You must be at least 13 years old.',
            textAlign: TextAlign.left,
            style: GoogleFonts.poppins(
              color: bodyMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        SizedBox(height: signupAlign ? 10 : 14),
        GestureDetector(
          onTap: _busy ? null : _pickDob,
          child: signupAlign
              ? _AuthGlassInputCard(
                  icon: Icons.cake_outlined,
                  iconColor: bodyMuted,
                  trailing: Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: bodyMuted,
                  ),
                  child: Text(
                    _dobDisplayLabel(),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _dob == null ? _kAuthGlassHint : titleMaroon,
                    ),
                  ),
                )
              : _InputCard(
                  height: 48,
                  borderColor: fieldBr,
                  fillColor: fieldBg,
                  child: Row(
                    children: [
                      Icon(Icons.cake_outlined, size: 18, color: bodyMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _dobDisplayLabel(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _dob == null
                                ? bodyMuted.withValues(alpha: 0.85)
                                : titleMaroon,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: bodyMuted,
                      ),
                    ],
                  ),
                ),
        ),
        if (signupAlign) ...[
          const SizedBox(height: 12),
          _profileSimplifiedSignupActions(
            titleMaroon,
            fieldBr,
            const Color(0xFF5D1109),
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: double.infinity, child: inner),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final FocusNode _otpFocus = FocusNode();
  String? _verificationId;
  bool _otpSent = false;
  bool _busy = false;

  static const int _otpBoxCount = 6;

  late final AnimationController _entryAnim;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    final curve = CurvedAnimation(
      parent: _entryAnim,
      curve: Curves.easeOutCubic,
    );
    _entryFade = Tween<double>(begin: 0, end: 1).animate(curve);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(curve);
    _entryAnim.forward();
    _otpFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _entryAnim.dispose();
    _otpFocus.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _resetPhoneOtpFlow() {
    _otpFocus.unfocus();
    setState(() {
      _verificationId = null;
      _otpSent = false;
      _otpCtrl.clear();
    });
  }

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.replaceAll(RegExp(r'\D'), '').length < 10) {
      _snack('Enter a valid 10-digit mobile number');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    _snack('Sending OTP…');
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
    }

    final watchdog = Timer(const Duration(seconds: 75), () {
      if (!mounted || finished) return;
      finish();
      setState(() => _busy = false);
      _snack(
        'OTP request timed out. Check internet, wait a minute, and try again. '
        'If you installed via USB (flutter run), add debug SHA-1 in Firebase.',
      );
    });

    try {
      await authService.startPhoneVerification(
        phoneNumber: raw,
        onCodeSent: (id) {
          finish();
          watchdog.cancel();
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _otpSent = true;
            _busy = false;
            _otpCtrl.clear();
          });
          _snack('OTP sent. Check your SMS.');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _otpFocus.requestFocus();
          });
        },
        onVerificationFailed: (e) {
          finish();
          watchdog.cancel();
          if (!mounted) return;
          setState(() => _busy = false);
          _snack(_readableAuthError(e));
        },
        onAutoSignedIn: (r) async {
          finish();
          watchdog.cancel();
          if (!mounted) return;
          setState(() => _busy = false);
        },
      );
    } catch (e) {
      finish();
      watchdog.cancel();
      if (mounted) {
        setState(() => _busy = false);
        _snack(_readableAuthError(e));
      }
    }
  }

  Future<void> _verifyOtpAndLogin() async {
    final id = _verificationId;
    if (id == null || id.isEmpty) {
      _snack('Tap Send OTP first');
      return;
    }
    final code = _otpCtrl.text.trim();
    if (code.length < 6) {
      _snack('Enter the 6-digit code');
      return;
    }
    setState(() => _busy = true);
    try {
      await authService.signInWithPhoneSms(verificationId: id, smsCode: code);
      if (!mounted) return;
    } catch (e) {
      if (mounted) _snack(_readableAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      final r = await authService.signInWithGoogle();
      if (!mounted) return;
      if (!kIsWeb) {
        if (r == null && authService.currentUser == null) {
          _snack('Google sign-in was cancelled');
          return;
        }
      } else {
        if (r == null) {
          _snack(
            'If a browser tab opened, complete Google sign-in there, then return to this app.',
          );
        }
      }
    } catch (e) {
      _snack(_readableAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showEmailPasswordLogin() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Sign in with email',
            style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: _AppColors.primary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final email = emailCtrl.text.trim();
                final pass = passCtrl.text;
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid email address'),
                    ),
                  );
                  return;
                }
                if (pass.length < 6) {
                  ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                    const SnackBar(
                      content: Text('Password must be at least 6 characters'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext);
                setState(() => _busy = true);
                try {
                  await authService
                      .signInWithEmail(email: email, password: pass)
                      .timeout(const Duration(seconds: 30));
                  if (!mounted) return;
                } on TimeoutException {
                  if (mounted) {
                    _snack('Sign-in timed out. Check internet and try again.');
                  }
                } catch (e) {
                  if (mounted) _snack(_readableAuthError(e));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              child: Text(
                'Login',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
    emailCtrl.dispose();
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgText = Color(0xFF2E1E1A);
    const muted = Color(0xFF7F6F65);
    const border = Color(0xFFE4D7C7);
    const loginGlassFill = _kAuthGlassFill;
    const loginGlassBorder = _kAuthGlassBorder;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compactLogin = screenHeight < 950;
    final labelBrown = _AppColors.primary;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _GlobalAppBackgroundLayer(
              assetPath: _GlobalAppBackgroundLayer.loginAssetPath,
              imageAlignment: Alignment(-0.75, -0.35),
            ),
            SafeArea(
              child: Stack(
                children: [
                  FadeTransition(
                    opacity: _entryFade,
                    child: SlideTransition(
                      position: _entrySlide,
                      child: Stack(
                        clipBehavior: Clip.none,
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                10,
                                20,
                                10,
                                _authScreenBottomGap(context) + 12,
                              ),
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height:
                                        (screenHeight * (compactLogin ? 0.09 : 0.062))
                                            .clamp(
                                              compactLogin ? 40.0 : 28.0,
                                              compactLogin ? 90.0 : 76.0,
                                            ) +
                                        (compactLogin ? 2.0 : 12.0),
                                  ),
                                  Transform.scale(
                                    alignment: Alignment.centerLeft,
                                    scale: 0.84,
                                    child: LayoutBuilder(
                                      builder: (context, c2) {
                                        const scale = 0.84;
                                        final brandW = (c2.maxWidth * 0.48)
                                            .clamp(142.0, 192.0);
                                        return SizedBox(
                                          width: brandW / scale,
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              top: compactLogin ? 6 : 18,
                                              right: 26,
                                            ),
                                            child: const _LoginLogoBlock(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(height: compactLogin ? 4 : 12),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final formContent = SizedBox(
                                            width: constraints.maxWidth,
                                            child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      height: compactLogin ? 4 : 8,
                                                    ),
                                                    Text(
                                                      'Welcome back',
                                                      style:
                                                          GoogleFonts.playfairDisplay(
                                                            color: labelBrown,
                                                            fontSize:
                                                                compactLogin ? 20 : 22,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.05,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Vanakkam — homely puttu, curries, and Kerala flavours await you.',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style:
                                                          GoogleFonts.poppins(
                                                            color: muted,
                                                            fontSize: 13,
                                                            height: 1.28,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                    ),
                                                    SizedBox(
                                                      height: compactLogin ? 6 : 10,
                                                    ),
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'Mobile number',
                                                          style: GoogleFonts.poppins(
                                                            color: labelBrown,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        if (_otpSent)
                                                          InkWell(
                                                            onTap: _busy
                                                                ? null
                                                                : _resetPhoneOtpFlow,
                                                            child: Text(
                                                              'Edit number',
                                                              style: GoogleFonts.poppins(
                                                                color: const Color(
                                                                  0xFFEA7A2C,
                                                                ),
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight.w700,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 5),
                                                    _InputCard(
                                                      height: compactLogin ? 40 : 46,
                                                      horizontalPadding: 12,
                                                      radius: 15,
                                                      borderColor:
                                                          loginGlassBorder,
                                                      fillColor: loginGlassFill,
                                                      glass: true,
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .phone_outlined,
                                                            size: 18,
                                                            color: muted,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            '+91',
                                                            style:
                                                                GoogleFonts.poppins(
                                                                  color: bgText,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .expand_more_rounded,
                                                            size: 20,
                                                            color: muted,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Expanded(
                                                            child: Material(
                                                              color: Colors
                                                                  .transparent,
                                                              child: TextField(
                                                                controller:
                                                                    _phoneCtrl,
                                                                enabled:
                                                                    !_busy &&
                                                                    !_otpSent,
                                                                keyboardType:
                                                                    TextInputType
                                                                        .phone,
                                                                autocorrect:
                                                                    false,
                                                                inputFormatters: [
                                                                  FilteringTextInputFormatter
                                                                      .digitsOnly,
                                                                  LengthLimitingTextInputFormatter(
                                                                    10,
                                                                  ),
                                                                ],
                                                                decoration:
                                                                    authGlassFieldDecoration(
                                                                  hintText:
                                                                      'Enter your mobile number',
                                                                ),
                                                                scrollPadding:
                                                                    const EdgeInsets.only(
                                                                      bottom: 180,
                                                                    ),
                                                                style: GoogleFonts
                                                                    .poppins(
                                                                  color: bgText,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'OTP',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            color: labelBrown,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    _InputCard(
                                                      height: compactLogin ? 40 : 46,
                                                      horizontalPadding: 12,
                                                      radius: 15,
                                                      borderColor:
                                                          loginGlassBorder,
                                                      fillColor: loginGlassFill,
                                                      glass: true,
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .verified_user_outlined,
                                                            size: 18,
                                                            color: muted,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            child: Material(
                                                              color: Colors
                                                                  .transparent,
                                                              child: TextField(
                                                                controller:
                                                                    _otpCtrl,
                                                                focusNode:
                                                                    _otpFocus,
                                                                keyboardType:
                                                                    TextInputType
                                                                        .number,
                                                                autocorrect:
                                                                    false,
                                                                enabled: !_busy,
                                                                inputFormatters: [
                                                                  FilteringTextInputFormatter
                                                                      .digitsOnly,
                                                                  LengthLimitingTextInputFormatter(
                                                                    _otpBoxCount,
                                                                  ),
                                                                ],
                                                                decoration:
                                                                    authGlassFieldDecoration(
                                                                  hintText:
                                                                      'Enter 6-digit OTP',
                                                                ),
                                                                scrollPadding:
                                                                    const EdgeInsets.only(
                                                                      bottom: 180,
                                                                    ),
                                                                style: GoogleFonts
                                                                    .poppins(
                                                                  color: bgText,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                                onChanged: (_) =>
                                                                    setState(
                                                                      () {},
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: _busy
                                                                ? null
                                                                : () async {
                                                                    final raw =
                                                                        _phoneCtrl
                                                                            .text
                                                                            .trim();
                                                                    if (raw
                                                                            .replaceAll(
                                                                              RegExp(
                                                                                r'\D',
                                                                              ),
                                                                              '',
                                                                            )
                                                                            .length <
                                                                        10) {
                                                                      _snack(
                                                                        'Enter a valid '
                                                                        '10-digit mobile number',
                                                                      );
                                                                      return;
                                                                    }
                                                                    await _sendOtp();
                                                                  },
                                                            style: TextButton.styleFrom(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 0,
                                                                  ),
                                                              minimumSize:
                                                                  Size.zero,
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                            child: Text(
                                                              _otpSent
                                                                  ? 'Resend'
                                                                  : 'Send OTP',
                                                              style: GoogleFonts.poppins(
                                                                color:
                                                                    const Color(
                                                                      0xFFEA7A2C,
                                                                    ),
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    SizedBox(
                                                      height:
                                                          compactLogin ? 36 : 40,
                                                      width: double.infinity,
                                                      child: Stack(
                                                        fit: StackFit.expand,
                                                        children: [
                                                          DecoratedBox(
                                                            decoration: BoxDecoration(
                                                              gradient: const LinearGradient(
                                                                begin: Alignment.topCenter,
                                                                end: Alignment.bottomCenter,
                                                                colors: [
                                                                  Color(0xFF8E2422),
                                                                  _AppColors.primary,
                                                                ],
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              border: Border.all(
                                                                color:
                                                                    const Color(
                                                                      0xFF8D2C24,
                                                                    ),
                                                                width: 1.5,
                                                              ),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: _AppColors.primary
                                                                      .withValues(alpha: 0.34),
                                                                  blurRadius: 14,
                                                                  offset: const Offset(0, 5),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  2,
                                                                ),
                                                            child: DecoratedBox(
                                                              decoration: BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      9,
                                                                    ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white
                                                                      .withValues(
                                                                        alpha:
                                                                            0.38,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Material(
                                                            type: MaterialType
                                                                .transparency,
                                                            child: InkWell(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              onTap: _busy
                                                                  ? null
                                                                  : () async {
                                                                      if (!_otpSent) {
                                                                        _snack(
                                                                          'Tap Send OTP '
                                                                          'first to receive '
                                                                          'your code.',
                                                                        );
                                                                        return;
                                                                      }
                                                                      await _verifyOtpAndLogin();
                                                                    },
                                                              child: Center(
                                                                child: _busy
                                                                    ? const SizedBox(
                                                                        height:
                                                                            20,
                                                                        width:
                                                                            20,
                                                                        child: CircularProgressIndicator(
                                                                          strokeWidth:
                                                                              2,
                                                                          color:
                                                                              Colors.white,
                                                                        ),
                                                                      )
                                                                    : Text(
                                                                        'LOGIN',
                                                                        style: GoogleFonts.poppins(
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          letterSpacing:
                                                                              1.2,
                                                                          color:
                                                                              Colors.white,
                                                                          fontSize:
                                                                              14,
                                                                        ),
                                                                      ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        bottom:
                                                            compactLogin ? 0 : 6,
                                                      ),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    vertical: 2,
                                                                  ),
                                                              child: Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Divider(
                                                                      color: border
                                                                          .withValues(
                                                                            alpha:
                                                                                0.85,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  Padding(
                                                                    padding:
                                                                        const EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              8,
                                                                        ),
                                                                    child: Text(
                                                                      'OR',
                                                                      style: GoogleFonts.poppins(
                                                                        color:
                                                                            muted,
                                                                        fontSize:
                                                                            10.5,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w700,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Expanded(
                                                                    child: Divider(
                                                                      color: border
                                                                          .withValues(
                                                                            alpha:
                                                                                0.85,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            SizedBox(
                                                              height:
                                                                  compactLogin
                                                                      ? 36
                                                                      : 40,
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .stretch,
                                                                children: [
                                                                  Expanded(
                                                                    child: OutlinedButton.icon(
                                                                    style: OutlinedButton.styleFrom(
                                                                      foregroundColor:
                                                                          bgText,
                                                                      backgroundColor:
                                                                          loginGlassFill,
                                                                      side: BorderSide(
                                                                        color:
                                                                            loginGlassBorder,
                                                                        width:
                                                                            1.25,
                                                                      ),
                                                                      padding: const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            0,
                                                                      ),
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    onPressed:
                                                                        _busy
                                                                        ? null
                                                                        : _signInWithGoogle,
                                                                    icon: Container(
                                                                      width: 20,
                                                                      height:
                                                                          20,
                                                                      alignment:
                                                                          Alignment
                                                                              .center,
                                                                      decoration: BoxDecoration(
                                                                        color: Colors
                                                                            .transparent,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              3,
                                                                            ),
                                                                        border: Border.all(
                                                                          color:
                                                                              loginGlassBorder,
                                                                        ),
                                                                      ),
                                                                      child: Text(
                                                                        'G',
                                                                        style: GoogleFonts.poppins(
                                                                          fontSize:
                                                                              11.5,
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          color: const Color(
                                                                            0xFF4285F4,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    label: FittedBox(
                                                                      fit: BoxFit
                                                                          .scaleDown,
                                                                      child: Text(
                                                                        'Continue with Google',
                                                                        maxLines:
                                                                            1,
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        style: GoogleFonts.poppins(
                                                                          fontSize:
                                                                              11,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: OutlinedButton.icon(
                                                                    style: OutlinedButton.styleFrom(
                                                                      foregroundColor:
                                                                          bgText,
                                                                      backgroundColor:
                                                                          loginGlassFill,
                                                                      side: BorderSide(
                                                                        color:
                                                                            loginGlassBorder,
                                                                        width:
                                                                            1.25,
                                                                      ),
                                                                      padding: const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            0,
                                                                      ),
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    onPressed:
                                                                        _busy
                                                                        ? null
                                                                        : _showEmailPasswordLogin,
                                                                    icon: Icon(
                                                                      Icons
                                                                          .mail_outline_rounded,
                                                                      size: 20,
                                                                      color:
                                                                          labelBrown,
                                                                    ),
                                                                    label: FittedBox(
                                                                      fit: BoxFit
                                                                          .scaleDown,
                                                                      child: Text(
                                                                        'Continue with Email',
                                                                        maxLines:
                                                                            1,
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        style: GoogleFonts.poppins(
                                                                          fontSize:
                                                                              11,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                          );
                                          return formContent;
                                        },
                                  ),
                                ],
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 0,
                            left: -14,
                            child: _LoginSlbLogoOverlay(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SLB Kitchen mark — overlaid top-left; does not affect login layout.
class _LoginSlbLogoOverlay extends StatelessWidget {
  const _LoginSlbLogoOverlay();

  static const _asset = 'assets/images/slb_kitchen_logo.png';

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Image.asset(
        _asset,
        width: 96,
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class _LoginLogoBlock extends StatelessWidget {
  static const _brandOrange = Color(0xFFEA7A2C);

  const _LoginLogoBlock();

  @override
  Widget build(BuildContext context) {
    final sh = MediaQuery.sizeOf(context).height;
    final compact = sh < 950;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: compact ? 4 : 10),
        Text(
          'Chechi',
          style: GoogleFonts.pacifico(
            fontSize: compact ? 38 : 46,
            height: 1.0,
            color: _brandOrange,
            fontWeight: FontWeight.w400,
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -2),
          child: Text(
            'Puttu Kadai',
            style: GoogleFonts.playfairDisplay(
              fontSize: compact ? 21 : 26,
              height: 1.08,
              color: _AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          const _LoginTaglineFlourish(),
        ] else ...[
          const SizedBox(height: 4),
          const _LoginTaglineFlourish(),
        ],
      ],
    );
  }
}

/// Tagline only (no decorative line/dot).
class _LoginTaglineFlourish extends StatelessWidget {
  static const _accent = Color(0xFFEA7A2C);

  const _LoginTaglineFlourish();

  @override
  Widget build(BuildContext context) {
    return Text(
      "Homely Food from God's Own\nCountry",
      textAlign: TextAlign.left,
      maxLines: 3,
      style: GoogleFonts.dancingScript(
        fontSize: 14,
        height: 1.28,
        color: _accent,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

const _kAuthGlassFill = Color(0x59FFF8F1);
const _kAuthGlassBorder = Color(0x99FFFFFF);
const _kAuthGlassHint = Color(0xFF9A8B81);

InputDecoration authGlassFieldDecoration({
  required String hintText,
  Color hintColor = _kAuthGlassHint,
  double hintSize = 14,
}) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    hintText: hintText,
    hintStyle: GoogleFonts.poppins(
      color: hintColor,
      fontSize: hintSize,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Login / signup glass field shell (icon + child).
class _AuthGlassInputCard extends StatelessWidget {
  const _AuthGlassInputCard({
    required this.icon,
    required this.iconColor,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      height: 48,
      horizontalPadding: 12,
      radius: 15,
      borderColor: _kAuthGlassBorder,
      fillColor: _kAuthGlassFill,
      glass: true,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: child),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.child,
    required this.borderColor,
    required this.fillColor,
    this.height = 44,
    this.horizontalPadding = 12,
    this.radius = 12,
    this.glass = false,
  });
  final Widget child;
  final Color borderColor;
  final Color fillColor;
  final double height;
  final double horizontalPadding;
  final double radius;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            height: height,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.26),
                  fillColor,
                ],
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor, width: 1.25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5D1109).withValues(alpha: 0.09),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1.35),
        ),
      ),
      child: child,
    );
  }
}

/// One line in the shopping cart (synced with home / search dish cards).
class CartLineItem {
  const CartLineItem({
    required this.name,
    required this.subtitle,
    required this.price,
    required this.qty,
    this.imageBase64,
  });

  final String name;
  final String subtitle;
  final int price;
  final int qty;
  final String? imageBase64;

  CartLineItem copyWith({
    String? name,
    String? subtitle,
    int? price,
    int? qty,
    String? imageBase64,
  }) {
    return CartLineItem(
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      price: price ?? this.price,
      qty: qty ?? this.qty,
      imageBase64: imageBase64 ?? this.imageBase64,
    );
  }
}

int _parseRupeesPrice(String displayPrice) {
  final digits = displayPrice.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

int _cartBadgeTotal(List<CartLineItem> items) =>
    items.fold<int>(0, (s, e) => s + e.qty);

int _cartQtyForDish(List<CartLineItem> lines, String title, String subtitle) {
  for (final e in lines) {
    if (e.name == title && e.subtitle == subtitle) return e.qty;
  }
  return 0;
}

void _cartAddDishLine(
  ValueNotifier<List<CartLineItem>> cart,
  String title,
  String subtitle,
  String priceStr,
  String? imageBase64,
) {
  final rupees = _parseRupeesPrice(priceStr);
  final next = List<CartLineItem>.from(cart.value);
  final idx = next.indexWhere((e) => e.name == title && e.subtitle == subtitle);
  if (idx >= 0) {
    next[idx] = next[idx].copyWith(
      qty: next[idx].qty + 1,
      imageBase64: next[idx].imageBase64 ?? imageBase64,
    );
  } else {
    next.add(
      CartLineItem(
        name: title,
        subtitle: subtitle,
        price: rupees,
        qty: 1,
        imageBase64: imageBase64,
      ),
    );
  }
  cart.value = next;
}

void _cartRemoveDishLine(
  ValueNotifier<List<CartLineItem>> cart,
  String title,
  String subtitle,
) {
  final next = List<CartLineItem>.from(cart.value);
  final idx = next.indexWhere((e) => e.name == title && e.subtitle == subtitle);
  if (idx < 0) return;
  if (next[idx].qty > 1) {
    next[idx] = next[idx].copyWith(qty: next[idx].qty - 1);
  } else {
    next.removeAt(idx);
  }
  cart.value = next;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.navIndexNotifier,
    required this.cartLinesNotifier,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final ValueNotifier<int> navIndexNotifier;
  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _homeSearchController = TextEditingController();
  Timer? _homeSearchDebounce;

  /// `null` = show all [customerMenuSections]; otherwise index of single section.
  int? _homeSectionFilter;
  late final AnimationController _tabAnim;
  late final VoidCallback _navListener;
  late int _lastNavIndex;
  late final List<GlobalKey> _menuSectionKeys;
  final GlobalKey<ScaffoldState> _homeScaffoldKey = GlobalKey<ScaffoldState>();
  final ValueNotifier<int> _ordersFilterNotifier = ValueNotifier<int>(0);
  String _deliveryStreet = 'Choose delivery address';
  double? _deliveryLat;
  double? _deliveryLng;
  Set<String> _favoriteDishKeys = <String>{};
  bool _forcingLocationPrompt = false;
  String? _activeSubscriptionPlan;
  Map<String, ({int startHour, int endHour})> _sectionSchedules = {};

  bool get _hasExactDeliveryLocation =>
      _deliveryLat != null && _deliveryLng != null;

  String get _deliveryLine => _deliveryStreet;

  Future<void> _restoreDeliveryAddress() async {
    final p = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final firstHomePopupDoneKey = 'chechi_first_home_location_popup_done_$uid';
    final persistedLat = p.getDouble(_deliveryLatKey(uid));
    final persistedLng = p.getDouble(_deliveryLngKey(uid));
    final persistedStreet = (p.getString(_deliveryStreetKey(uid)) ?? '').trim();

    if (!mounted) return;
    setState(() {
      _deliveryStreet =
          persistedStreet.isNotEmpty ? persistedStreet : 'Choose delivery address';
      _deliveryLat = persistedLat;
      _deliveryLng = persistedLng;
    });

    // Web cannot reliably capture exact GPS coordinates; skip the forced
    // first-login map prompt there so the user is never stuck in a loop.
    if (!kIsWeb && !_hasExactDeliveryLocation) {
      await _promptFirstLoginLocation();
      if (!mounted || !_hasExactDeliveryLocation) return;
      await p.setBool(firstHomePopupDoneKey, true);
      return;
    }

    if (p.getBool(firstHomePopupDoneKey) != true) {
      await p.setBool(firstHomePopupDoneKey, true);
    }
  }

  Future<void> _promptFirstLoginLocation() async {
    if (!mounted || _forcingLocationPrompt) return;
    _forcingLocationPrompt = true;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is required before you continue.'),
        ),
      );
      while (mounted && !_hasExactDeliveryLocation) {
        final picked = await _openDeliveryLocationSheet(required: true);
        if (!mounted) return;
        if (picked && _hasExactDeliveryLocation) break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      _forcingLocationPrompt = false;
    }
  }

  Future<void> _syncDeliveryLocationToProfile({
    required String street,
    double? latitude,
    double? longitude,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cleanStreet = street.trim();
    if (uid == null || uid.isEmpty) return;
    if (cleanStreet.isEmpty || cleanStreet.toLowerCase() == 'choose delivery address') {
      return;
    }
    try {
      final lat = latitude;
      final lng = longitude;
      await chechiFirestore.collection('users').doc(uid).set({
        'uid': uid,
        'location': cleanStreet,
        if (lat != null && lng != null) ...{
          'location_lat': lat,
          'location_lng': lng,
          'location_geo': GeoPoint(lat, lng),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-blocking: checkout still uses local delivery address.
    }
  }

  Future<void> _persistDeliverySelection(
    SharedPreferences p,
    DeliveryAddressResult r,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    await p.setString(_deliveryLabelKey(uid), r.label);
    await p.setString(_deliveryStreetKey(uid), r.street);
    if (r.latitude != null && r.longitude != null) {
      await p.setDouble(_deliveryLatKey(uid), r.latitude!);
      await p.setDouble(_deliveryLngKey(uid), r.longitude!);
    } else {
      await p.remove(_deliveryLatKey(uid));
      await p.remove(_deliveryLngKey(uid));
    }
    if (!mounted) return;
    setState(() {
      _deliveryStreet = r.street;
      _deliveryLat = r.latitude;
      _deliveryLng = r.longitude;
    });
    await _syncDeliveryLocationToProfile(
      street: r.street,
      latitude: r.latitude,
      longitude: r.longitude,
    );
  }

  Future<bool> _openDeliveryLocationSheet({bool required = false}) async {
    final r = await showDeliveryLocationSheet(
      context,
      currentStreet: _deliveryStreet,
      isDismissible: !required,
      enableDrag: !required,
    );
    if (!mounted) return false;
    if (r == null) {
      if (required) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please set your location to continue.'),
          ),
        );
      }
      return false;
    }
    final p = await SharedPreferences.getInstance();
    await _persistDeliverySelection(p, r);
    return true;
  }

  static const String _kPrefsNotifOrders = 'chechi_notif_orders';
  static const String _kPrefsNotifPromos = 'chechi_notif_promos';
  static const String _kSupportPhoneDisplay = '7538888437';
  static final Uri _kSupportPhoneUri = Uri.parse('tel:+917538888437');
  static final Uri _kSupportWhatsAppUri = Uri.parse(
    'https://wa.me/917538888437?text=${Uri.encodeQueryComponent('Hi Chechi Puttu Kadai! I have a query.')}',
  );
  static final Uri _kSupportEmailUri = Uri.parse(
    'mailto:chechiputtukadai@gmail.com?subject=Chechi%20Puttu%20Kadai%20—%20Customer%20query',
  );

  Future<void> _launchUri(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot open this link on your device.'),
          ),
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link. Try again later.')),
      );
    }
  }

  Future<void> _openNotificationSettings() async {
    if (!mounted) return;

    var osGranted = kIsWeb;
    if (!kIsWeb) {
      final s = await Permission.notification.status;
      if (s.isGranted) {
        osGranted = true;
      } else if (s.isPermanentlyDenied) {
        osGranted = false;
      } else {
        final r = await Permission.notification.request();
        osGranted = r.isGranted;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var orders = prefs.getBool(_kPrefsNotifOrders) ?? true;
    var promos = prefs.getBool(_kPrefsNotifPromos) ?? true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(
                'Notifications',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!osGranted) ...[
                      Text(
                        'Phone notifications are turned off for Chechi Puttu. '
                        'Allow them here (or in system App info) so order alerts can appear.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          height: 1.35,
                          color: _Theme.muted(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () async {
                          await openAppSettings();
                        },
                        child: Text(
                          'Open app settings',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Order updates',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Preparing, out for delivery, delivered',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: _Theme.muted(context),
                        ),
                      ),
                      value: orders,
                      onChanged: (v) async {
                        setLocal(() => orders = v);
                        await prefs.setBool(_kPrefsNotifOrders, v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Offers & deals',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Discounts and festival specials',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: _Theme.muted(context),
                        ),
                      ),
                      value: promos,
                      onChanged: (v) async {
                        setLocal(() => promos = v);
                        await prefs.setBool(_kPrefsNotifPromos, v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Done',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openHelpAndSupport() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Help & support',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _Theme.text(ctx),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please share your valuable feedback. For clarifications or queries, call or WhatsApp us.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.4,
                        color: _Theme.muted(ctx),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mobile: $_kSupportPhoneDisplay\nEmail: chechiputtukadai@gmail.com',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: _Theme.text(ctx),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _launchUri(_kSupportPhoneUri);
                        });
                      },
                      icon: const Icon(Icons.call_rounded, size: 20),
                      label: Text(
                        'Call $_kSupportPhoneDisplay',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _launchUri(_kSupportWhatsAppUri);
                        });
                      },
                      icon: const Icon(Icons.chat_rounded, size: 20),
                      label: Text(
                        'WhatsApp $_kSupportPhoneDisplay',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _launchUri(_kSupportEmailUri);
                        });
                      },
                      icon: const Icon(Icons.email_outlined, size: 20),
                      label: Text(
                        'chechiputtukadai@gmail.com',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditProfile() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => EditProfileScreen(
          isDark: widget.isDark,
          onToggleTheme: widget.onToggleTheme,
          onCompleted: () {
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _handleProfileSettingsTap(BuildContext menuContext, String label) {
    switch (label) {
      case 'Personal Information':
        _openEditProfile();
        break;
      case 'Saved Addresses':
        _openDeliveryLocationSheet();
        break;
      case 'Payment Methods':
        _showChechiPaymentMethodsDialog(menuContext);
        break;
      case 'Subscription Plans':
        _openSubscriptionPlans();
        break;
      case 'Notifications':
        _openNotificationSettings();
        break;
      case 'Privacy & Security':
        _showChechiPrivacyDialog(menuContext);
        break;
      case 'Help & Support':
        _openHelpAndSupport();
        break;
      case 'FAQs':
        _showChechiFaqsDialog(menuContext);
        break;
      case 'Terms & Conditions':
        _showChechiTermsDialog(menuContext);
        break;
      case 'Cancellation Policy':
        _showChechiCancellationPolicyDialog(menuContext);
        break;
      case 'About Us':
        _showChechiAboutDialog(menuContext);
        break;
      case 'Contact Us':
        _showChechiContactUsDialog(menuContext);
        break;
    }
  }

  void _goToOrdersWithFilter(int filterIndex) {
    _ordersFilterNotifier.value = filterIndex.clamp(0, 3);
    widget.navIndexNotifier.value = 2;
  }

  void _openAppMenu() {
    _homeScaffoldKey.currentState?.openDrawer();
  }

  Future<void> _openCustomerChat() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CustomerChatScreen()),
    );
  }

  Widget _buildAppNavigationDrawer(BuildContext drawerContext) {
    final scheme = Theme.of(drawerContext).colorScheme;
    final wa = _kSupportWhatsAppUri;

    void popDrawerThen(VoidCallback fn) {
      Navigator.pop(drawerContext);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fn();
      });
    }

    return Drawer(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(18)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Menu',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _Theme.text(drawerContext),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(drawerContext),
                    icon: Icon(
                      Icons.close_rounded,
                      color: _Theme.muted(drawerContext),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _AppMenuTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    subtitle: 'Order alerts & offers',
                    onTap: () => popDrawerThen(() {
                      _openNotificationSettings();
                    }),
                  ),
                  _AppMenuTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Chat with Chechi',
                    subtitle: 'WhatsApp',
                    onTap: () => popDrawerThen(() {
                      _launchUri(wa);
                    }),
                  ),
                  _AppMenuTile(
                    icon: Icons.location_on_outlined,
                    title: 'Delivery address',
                    subtitle: _deliveryLine,
                    onTap: () => popDrawerThen(() {
                      _openDeliveryLocationSheet();
                    }),
                  ),
                  _AppMenuTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & support',
                    subtitle: 'Call, email, FAQs',
                    onTap: () => popDrawerThen(() {
                      _openHelpAndSupport();
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _menuSectionKeys = List<GlobalKey>.generate(
      customerMenuSections.length,
      (_) => GlobalKey(),
    );
    _lastNavIndex = widget.navIndexNotifier.value;
    _tabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..value = 1;
    _navListener = () {
      final v = widget.navIndexNotifier.value;
      if (v == 0) {
        CustomerMenuOverrides.instance.reloadFromPrefs();
        CustomerMenuSectionOverrides.instance.reloadFromPrefs();
        MenuDeletedDishes.instance.reloadFromPrefs();
        unawaited(_restoreSectionSchedules());
      }
      if (v != _lastNavIndex) {
        _lastNavIndex = v;
        _tabAnim.forward(from: 0);
      }
    };
    widget.navIndexNotifier.addListener(_navListener);
    _homeSearchController.addListener(_onHomeSearchTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreDeliveryAddress());
      unawaited(_restoreFavorites());
      unawaited(_restoreSubscriptionPlan());
      unawaited(_restoreSectionSchedules());
      CustomerMenuOverrides.instance.reloadFromPrefs();
      CustomerMenuSectionOverrides.instance.reloadFromPrefs();
      MenuDeletedDishes.instance.reloadFromPrefs();
      unawaited(_loadBirthdayBannerState());
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _showPreOrderInfoDialog(context);
      });
    });
  }

  void _showPreOrderInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor:
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: _AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.schedule_rounded,
                          color: _AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pre-Order Info',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'We prepare everything fresh! Place your order in advance and choose your preferred meal slot.',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: _Theme.muted(ctx),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _preOrderSlotRow(
                  ctx,
                  icon: Icons.wb_sunny_outlined,
                  meal: 'Breakfast',
                  time: '8:00 – 10:00 AM',
                  rule: 'Order before 12 PM',
                ),
                const SizedBox(height: 8),
                _preOrderSlotRow(
                  ctx,
                  icon: Icons.lunch_dining_outlined,
                  meal: 'Lunch',
                  time: '12:00 – 2:00 PM',
                  rule: 'Order before 6 PM',
                ),
                const SizedBox(height: 8),
                _preOrderSlotRow(
                  ctx,
                  icon: Icons.nightlight_round,
                  meal: 'Dinner',
                  time: '6:00 – 9:00 PM',
                  rule: 'Order anytime',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: Text(
                      'Got it!',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _preOrderSlotRow(
    BuildContext context, {
    required IconData icon,
    required String meal,
    required String time,
    required String rule,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _Theme.surfaceLow(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _Theme.border(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  rule,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: _Theme.muted(context),
                      height: 1.3),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  void _onHomeSearchTextChanged() {
    _homeSearchDebounce?.cancel();
    _homeSearchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() {});
    });
  }

  bool _birthdayToday = false;
  String _birthdayFirstName = 'there';

  Future<void> _loadBirthdayBannerState() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _birthdayToday = false);
      return;
    }
    final isToday =
        await BirthdayChatWishService.instance.isBirthdayTodayForUid(uid);
    final first =
        await BirthdayChatWishService.instance.firstNameForUid(uid);
    if (!mounted) return;
    setState(() {
      _birthdayToday = isToday;
      _birthdayFirstName = first;
    });
    if (isToday) {
      // Send chat wish (idempotent — server deduplicates by day).
      unawaited(BirthdayChatWishService.instance.ensureForCustomer(uid));
      // Show popup once per day on first app open.
      await _maybeShowBirthdayPopup(first, uid);
    }
  }

  static String _birthdayPopupShownKey(String uid) =>
      'chechi_birthday_popup_shown_${uid}_${BirthdayChatWishService.todayKey()}';

  Future<void> _maybeShowBirthdayPopup(String firstName, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _birthdayPopupShownKey(uid);
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _BirthdayPopupDialog(
        firstName: firstName,
        onOpenChat: () {
          Navigator.of(ctx).pop();
          // Navigate to Chat tab (index 4).
          widget.navIndexNotifier.value = 4;
        },
      ),
    );
  }

  Future<void> _handlePullToRefresh() async {
    await Future.wait([
      AppRefresh.refreshMenuData(),
      _restoreDeliveryAddress(),
      _restoreFavorites(),
      _restoreSectionSchedules(),
      _loadBirthdayBannerState(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navIndexNotifier != widget.navIndexNotifier) {
      oldWidget.navIndexNotifier.removeListener(_navListener);
      widget.navIndexNotifier.addListener(_navListener);
      _lastNavIndex = widget.navIndexNotifier.value;
    }
  }

  @override
  void dispose() {
    _homeSearchDebounce?.cancel();
    widget.navIndexNotifier.removeListener(_navListener);
    _homeSearchController.removeListener(_onHomeSearchTextChanged);
    _homeSearchController.dispose();
    _ordersFilterNotifier.dispose();
    _tabAnim.dispose();
    super.dispose();
  }

  int _qtyInCart(String title, String subtitle) =>
      _cartQtyForDish(widget.cartLinesNotifier.value, title, subtitle);

  String _favDishKey(String title, String subtitle) => '$title\u001f$subtitle';

  String _favoritesPrefKey(String uid) => 'chechi_favorites_$uid';

  Future<void> _restoreFavorites() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_favoritesPrefKey(uid)) ?? const <String>[];
    if (!mounted) return;
    setState(() => _favoriteDishKeys = raw.toSet());
  }

  String _subscriptionPrefKey(String uid) => 'chechi_subscription_plan_$uid';

  Future<void> _restoreSubscriptionPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final p = await SharedPreferences.getInstance();
    final v = (p.getString(_subscriptionPrefKey(uid)) ?? '').trim();
    if (!mounted) return;
    setState(() => _activeSubscriptionPlan = v.isEmpty ? null : v);
  }

  Future<void> _restoreSectionSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kMenuSectionSchedulePrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _sectionSchedules = {});
      return;
    }
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return;
      final out = <String, ({int startHour, int endHour})>{};
      for (final e in m.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final sh = v['startHour'];
        final eh = v['endHour'];
        if (sh is num && eh is num) {
          out[e.key] = (startHour: sh.toInt(), endHour: eh.toInt());
        }
      }
      if (!mounted) return;
      setState(() => _sectionSchedules = out);
    } catch (_) {}
  }

  String _sectionIdAt(int index) => customerMenuSectionIdAt(index);

  bool _isSectionOpenNow(String sectionId) {
    final slot = _sectionSchedules[sectionId];
    if (slot == null) return true;
    final nowHour = DateTime.now().hour;
    final s = slot.startHour;
    final e = slot.endHour;
    if (s == e) return true;
    if (s < e) return nowHour >= s && nowHour < e;
    return nowHour >= s || nowHour < e;
  }

  Future<void> _openSubscriptionPlans() async {
    final plans = <({String id, String title, String subtitle, int rupees})>[
      (
        id: 'weekly_lite',
        title: 'Weekly Lite',
        subtitle: '1 meal/day, 5 days',
        rupees: 899,
      ),
      (
        id: 'weekly_plus',
        title: 'Weekly Plus',
        subtitle: '2 meals/day, 6 days',
        rupees: 1499,
      ),
      (
        id: 'monthly_family',
        title: 'Monthly Family',
        subtitle: 'Family combo, 24 deliveries',
        rupees: 5299,
      ),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Subscription plans',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              for (final p in plans) ...[
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                    ),
                  ),
                  title: Text(
                    p.title,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${p.subtitle} • ₹${p.rupees}',
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                  trailing: _activeSubscriptionPlan == p.id
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32))
                      : null,
                  onTap: () => Navigator.pop(ctx, p.id),
                ),
                const SizedBox(height: 8),
              ],
              if (_activeSubscriptionPlan != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, '_clear'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel active plan'),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    final next = picked == '_clear' ? null : picked;
    if (next == null) {
      await prefs.remove(_subscriptionPrefKey(uid));
    } else {
      await prefs.setString(_subscriptionPrefKey(uid), next);
    }
    if (!mounted) return;
    setState(() => _activeSubscriptionPlan = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next == null ? 'Subscription cancelled.' : 'Subscription updated.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  bool _isFavoriteDish(String title, String subtitle) =>
      _favoriteDishKeys.contains(_favDishKey(title, subtitle));

  Future<void> _toggleFavoriteDish(String title, String subtitle) async {
    final key = _favDishKey(title, subtitle);
    final next = Set<String>.from(_favoriteDishKeys);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() => _favoriteDishKeys = next);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_favoritesPrefKey(uid), next.toList()..sort());
  }

  void _addDishToCart(
    String title,
    String subtitle,
    String priceStr, {
    String? imageBase64,
  }) {
    _cartAddDishLine(
      widget.cartLinesNotifier,
      title,
      subtitle,
      priceStr,
      imageBase64,
    );
  }

  void _removeDishFromCart(String title, String subtitle) {
    _cartRemoveDishLine(widget.cartLinesNotifier, title, subtitle);
  }

  AdminDishEditSnapshot _mergedDish(String sectionId, MenuCatalogDish d) {
    return mergeWithCatalog(
      d,
      CustomerMenuOverrides.instance.snapshotFor(sectionId, d.title),
    );
  }

  List<MenuCatalogDish> _visibleDishes(MenuCatalogSection s, String sectionId) {
    if (!_isSectionOpenNow(sectionId)) return const <MenuCatalogDish>[];
    return s.dishes
        .where((d) => !MenuDeletedDishes.instance.isDeleted(sectionId, d.title))
        .toList();
  }

  String _normalizeHomeSearchQuery(String q) {
    var s = q.toLowerCase().trim();
    const aliases = <String, String>{'caddala': 'kadala', 'kadla': 'kadala'};
    for (final e in aliases.entries) {
      if (s.contains(e.key)) s = s.replaceAll(e.key, e.value);
    }
    return s;
  }

  List<String> _homeSearchTokens(String normalizedLower) {
    return normalizedLower
        .replaceAll(RegExp(r'[.,;/\\|]'), ' ')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _haystackHasAllTokens(String haystackLower, List<String> tokens) {
    if (tokens.isEmpty) return true;
    return tokens.every((t) => haystackLower.contains(t));
  }

  bool _homeSectionMatchesSearch(
    MenuCatalogSection s,
    String sectionId,
    List<String> tokens,
  ) {
    final sec = '${s.title} ${s.subtitle}'.toLowerCase();
    final sectionMatches = _haystackHasAllTokens(sec, tokens);
    for (final d in _visibleDishes(s, sectionId)) {
      final m = _mergedDish(sectionId, d);
      final dish = '${m.title} ${m.subtitle}'.toLowerCase();
      if (_haystackHasAllTokens(dish, tokens)) return true;
    }
    if (sectionMatches) return _visibleDishes(s, sectionId).isNotEmpty;
    return false;
  }

  /// Matching dishes first, then the rest of the section (same category).
  List<MenuCatalogDish> _dishesOrderedForSearch(
    MenuCatalogSection s,
    String sectionId,
    List<String> tokens,
  ) {
    final visible = _visibleDishes(s, sectionId);
    if (tokens.isEmpty) return visible;
    bool dishMatches(MenuCatalogDish d) {
      final m = _mergedDish(sectionId, d);
      final dish = '${m.title} ${m.subtitle}'.toLowerCase();
      return _haystackHasAllTokens(dish, tokens);
    }

    final matched = visible.where(dishMatches).toList();
    final rest = visible.where((d) => !dishMatches(d)).toList();
    return [...matched, ...rest];
  }

  Iterable<int> _iterVisibleMenuSectionIndices() sync* {
    final f = _homeSectionFilter;
    if (f == null) {
      yield* customerVisibleMenuSectionIndices();
    } else {
      yield f.clamp(0, customerMenuSections.length - 1);
    }
  }

  void _openHomeMenuFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                      child: Row(
                        children: [
                          Text(
                            'Filter by menu',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _Theme.text(ctx),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(
                              Icons.close_rounded,
                              color: _Theme.muted(ctx),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Pick one menu or show all dishes on the home screen.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          height: 1.35,
                          color: _Theme.muted(ctx),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.restaurant_menu_rounded,
                        color: _Theme.primary(ctx),
                      ),
                      title: Text(
                        'All dishes',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: _Theme.text(ctx),
                        ),
                      ),
                      subtitle: Text(
                        'All menus',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: _Theme.muted(ctx),
                        ),
                      ),
                      trailing: _homeSectionFilter == null
                          ? Icon(
                              Icons.check_rounded,
                              color: _Theme.primary(ctx),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _homeSectionFilter = null);
                      },
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    ...() {
                      final visibleSections =
                          customerVisibleMenuSectionIndices();
                      final tiles = <Widget>[];
                      for (var vi = 0; vi < visibleSections.length; vi++) {
                        if (vi > 0) {
                          tiles.add(
                            Divider(
                              height: 1,
                              indent: 56,
                              color: scheme.outlineVariant,
                            ),
                          );
                        }
                        final i = visibleSections[vi];
                        tiles.add(
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            leading: Icon(
                              Icons.category_outlined,
                              color: _Theme.primary(ctx),
                            ),
                            title: Text(
                              customerMenuSections[i].title,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: _Theme.text(ctx),
                              ),
                            ),
                            subtitle: Text(
                              customerMenuSections[i].subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: _Theme.muted(ctx),
                              ),
                            ),
                            trailing: _homeSectionFilter == i
                                ? Icon(
                                    Icons.check_rounded,
                                    color: _Theme.primary(ctx),
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() => _homeSectionFilter = i);
                            },
                          ),
                        );
                      }
                      return tiles;
                    }(),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildHomeBrowseBody(BuildContext context) {
    return [
      const _HeroCarousel(),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _FeatureStrip(),
      ),
      const SizedBox(height: 12),
      if (_homeSectionFilter != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _Theme.surfaceLow(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _Theme.border(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_rounded,
                    size: 20,
                    color: _Theme.primary(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Showing this menu',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _Theme.muted(context),
                          ),
                        ),
                        Text(
                          customerMenuSections[_homeSectionFilter!.clamp(
                                0,
                                customerMenuSections.length - 1,
                              )]
                              .title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _Theme.text(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _homeSectionFilter = null),
                    child: Text(
                      'Clear',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: _Theme.primary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ] else ...[
        ChechiFadeIn(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeader(
              title: 'Explore Menus',
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: Listenable.merge([
            CustomerMenuSectionOverrides.instance,
            MenuDeletedDishes.instance,
          ]),
          builder: (context, _) {
            final visible = customerVisibleMenuSectionIndices();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 88,
                child: visible.length <= 6
                    ? Row(
                        children: List.generate(visible.length, (chipIdx) {
                          final i = visible[chipIdx];
                          final label = customerMenuSections[i].title;
                          final chipLabel = label.length > 14
                              ? '${label.substring(0, 12).trim()}…'
                              : label;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: chipIdx < visible.length - 1 ? 8 : 0),
                              child: _CategoryChip(
                                label: chipLabel.replaceAll(' & ', ' &\n'),
                                icon: _exploreMenuChipIcon(label),
                                selected: _homeSectionFilter == i,
                                margin: EdgeInsets.zero,
                                onTap: () => setState(() =>
                                    _homeSectionFilter =
                                        _homeSectionFilter == i ? null : i),
                              ),
                            ),
                          );
                        }),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, chipIdx) {
                          final i = visible[chipIdx];
                          final label = customerMenuSections[i].title;
                          final chipLabel = label.length > 14
                              ? '${label.substring(0, 12).trim()}…'
                              : label;
                          return SizedBox(
                            width: 76,
                            child: _CategoryChip(
                              label: chipLabel.replaceAll(' & ', ' &\n'),
                              icon: _exploreMenuChipIcon(label),
                              selected: _homeSectionFilter == i,
                              margin: EdgeInsets.zero,
                              onTap: () => setState(() =>
                                  _homeSectionFilter =
                                      _homeSectionFilter == i ? null : i),
                            ),
                          );
                        },
                      ),
              ),
            );
          },
        ),
      ],
      const SizedBox(height: 10),
      ..._buildHomeBrowseMenuSections(context),
    ];
  }

  List<Widget> _buildHomeBrowseMenuSections(BuildContext context) {
    final out = <Widget>[];
    var first = true;
    for (final i in _iterVisibleMenuSectionIndices()) {
      final sec = customerMenuSections[i];
      final sectionId = _sectionIdAt(i);
      final dishes = _visibleDishes(sec, sectionId);
      if (dishes.isEmpty) continue;
      out.add(SizedBox(height: first ? 10 : 14));
      first = false;
      out.add(
        ChechiFadeIn(
          delay: chechiStagger(i, staggerMs: 55),
          child: KeyedSubtree(
            key: _menuSectionKeys[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SectionHeader(
                title: sec.title,
              ),
            ),
          ),
        ),
      );
      out.add(const SizedBox(height: 6));
      out.add(
        ListenableBuilder(
          listenable: Listenable.merge([
            widget.cartLinesNotifier,
            CustomerMenuOverrides.instance,
            CustomerMenuSectionOverrides.instance,
            MenuDeletedDishes.instance,
          ]),
          builder: (context, _) {
            final dishes = _visibleDishes(sec, sectionId);
            if (_homeSectionFilter != null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.88,
                  ),
                  itemCount: dishes.length,
                  itemBuilder: (context, idx) {
                    final m = _mergedDish(sectionId, dishes[idx]);
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final h = constraints.maxWidth / 0.88;
                        return _ProductCard(
                          height: h.isFinite ? h : 190,
                          badge: m.badge,
                          title: m.title,
                          subtitle: m.subtitle,
                          price: m.price,
                          imageBase64: m.imageBase64,
                          available: m.available,
                          isFavorite: _isFavoriteDish(m.title, m.subtitle),
                          onToggleFavorite: () =>
                              _toggleFavoriteDish(m.title, m.subtitle),
                          qty: _qtyInCart(m.title, m.subtitle),
                          onAdd: () => _addDishToCart(
                            m.title,
                            m.subtitle,
                            m.price,
                            imageBase64: m.imageBase64,
                          ),
                          onRemove: () =>
                              _removeDishFromCart(m.title, m.subtitle),
                        );
                      },
                    );
                  },
                ),
              );
            }
            return SizedBox(
              height: _kHomeDishCardHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ...dishes.map((d) {
                    final m = _mergedDish(sectionId, d);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: _ProductCard(
                        width: 136,
                        height: _kHomeDishCardHeight,
                        badge: m.badge,
                        title: m.title,
                        subtitle: m.subtitle,
                        price: m.price,
                        imageBase64: m.imageBase64,
                        available: m.available,
                        isFavorite: _isFavoriteDish(m.title, m.subtitle),
                        onToggleFavorite: () =>
                            _toggleFavoriteDish(m.title, m.subtitle),
                        qty: _qtyInCart(m.title, m.subtitle),
                        onAdd: () => _addDishToCart(
                          m.title,
                          m.subtitle,
                          m.price,
                          imageBase64: m.imageBase64,
                        ),
                        onRemove: () =>
                            _removeDishFromCart(m.title, m.subtitle),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      );
    }
    return out;
  }

  List<Widget> _buildHomeSearchBody(BuildContext context, List<String> tokens) {
    var anyMatch = false;
    for (var i = 0; i < customerMenuSections.length; i++) {
      if (_homeSectionFilter != null && i != _homeSectionFilter) continue;
      if (_homeSectionMatchesSearch(
        customerMenuSections[i],
        _sectionIdAt(i),
        tokens,
      )) {
        anyMatch = true;
        break;
      }
    }
    if (!anyMatch) {
      final q = _homeSearchController.text.trim();
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
          child: Text(
            'No dishes found for "$q".\nTry puttu, kadala curry, appam...',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: _Theme.muted(context),
              height: 1.45,
            ),
          ),
        ),
      ];
    }

    var first = true;
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Results',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _Theme.text(context),
                ),
              ),
            ),
            if (_homeSectionFilter != null)
              TextButton(
                onPressed: () => setState(() => _homeSectionFilter = null),
                child: Text(
                  'Clear filter',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: _Theme.primary(context),
                  ),
                ),
              ),
            TextButton(
              onPressed: () => _homeSearchController.clear(),
              child: Text(
                'Clear search',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: _Theme.primary(context),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_homeSectionFilter != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 18,
                color: _Theme.primary(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Only searching in: ${customerMenuSections[_homeSectionFilter!.clamp(0, customerMenuSections.length - 1)].title}',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _Theme.muted(context),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    for (var i = 0; i < customerMenuSections.length; i++) {
      if (_homeSectionFilter != null && i != _homeSectionFilter) continue;
      final s = customerMenuSections[i];
      final sectionId = _sectionIdAt(i);
      if (!_homeSectionMatchesSearch(s, sectionId, tokens)) continue;
      if (_visibleDishes(s, sectionId).isEmpty) continue;
      final h = first ? 10 : 14;
      first = false;
      out.addAll([
        SizedBox(height: h.toDouble()),
        KeyedSubtree(
          key: _menuSectionKeys[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeader(
              title: s.title,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: Listenable.merge([
            widget.cartLinesNotifier,
            CustomerMenuOverrides.instance,
            CustomerMenuSectionOverrides.instance,
            MenuDeletedDishes.instance,
          ]),
          builder: (context, _) {
            return SizedBox(
              height: _kHomeDishCardHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ..._dishesOrderedForSearch(s, sectionId, tokens).map((d) {
                    final m = _mergedDish(sectionId, d);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: _ProductCard(
                        width: 136,
                        height: _kHomeDishCardHeight,
                        badge: m.badge,
                        title: m.title,
                        subtitle: m.subtitle,
                        price: m.price,
                        imageBase64: m.imageBase64,
                        available: m.available,
                        isFavorite: _isFavoriteDish(m.title, m.subtitle),
                        onToggleFavorite: () =>
                            _toggleFavoriteDish(m.title, m.subtitle),
                        qty: _qtyInCart(m.title, m.subtitle),
                        onAdd: () => _addDishToCart(
                          m.title,
                          m.subtitle,
                          m.price,
                          imageBase64: m.imageBase64,
                        ),
                        onRemove: () =>
                            _removeDishFromCart(m.title, m.subtitle),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ]);
    }

    out.add(const SizedBox(height: 10));
    return out;
  }

  Widget _buildHomeTab() {
    final norm = _normalizeHomeSearchQuery(_homeSearchController.text);
    final tokens = _homeSearchTokens(norm);
    final searching = tokens.isNotEmpty;

    return Column(
      key: const ValueKey('home-tab'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopLocationRow(
                deliveryLine: _deliveryLine,
                onMenu: _openAppMenu,
                onLocationTap: _openDeliveryLocationSheet,
                isDark: widget.isDark,
                onToggleTheme: widget.onToggleTheme,
                cartLinesNotifier: widget.cartLinesNotifier,
                onCartTap: () => widget.navIndexNotifier.value = 1,
              ),
              const SizedBox(height: 6),
              _HomeSearchBar(
                controller: _homeSearchController,
                hintText: 'Search for puttu, curry, appam...',
                filterActive: _homeSectionFilter != null,
                onFilter: _openHomeMenuFilterSheet,
              ),
            ],
          ),
        ),
        if (_birthdayToday)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: BirthdayHomeBanner(
              firstName: _birthdayFirstName,
              onOpenChat: _openCustomerChat,
            ),
          ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              CustomerMenuOverrides.instance,
              CustomerMenuSectionOverrides.instance,
              MenuDeletedDishes.instance,
            ]),
            builder: (context, _) {
              return AppPullToRefresh(
                onRefresh: _handlePullToRefresh,
                child: SingleChildScrollView(
                  physics: AppPullToRefresh.scrollPhysics,
                  padding: EdgeInsets.fromLTRB(
                      0, 0, 0, 90 + MediaQuery.of(context).padding.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: searching
                        ? _buildHomeSearchBody(context, tokens)
                        : _buildHomeBrowseBody(context),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: _PostLoginBackgroundLayer()),
        Scaffold(
          key: _homeScaffoldKey,
          backgroundColor: Colors.transparent,
          drawer: Builder(
            builder: (drawerContext) =>
                _buildAppNavigationDrawer(drawerContext),
          ),
          body: Stack(
            children: [
              SafeArea(
                child: ListenableBuilder(
                  listenable: widget.navIndexNotifier,
                  builder: (context, _) {
                    final tabCurve = CurvedAnimation(
                      parent: _tabAnim,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity:
                          Tween<double>(begin: 0.94, end: 1).animate(tabCurve),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.014),
                          end: Offset.zero,
                        ).animate(tabCurve),
                        child: IndexedStack(
                          index: widget.navIndexNotifier.value.clamp(0, 4),
                          sizing: StackFit.expand,
                          children: [
                            _buildHomeTab(),
                            _CartTab(
                              cartLinesNotifier: widget.cartLinesNotifier,
                              onBack: () => widget.navIndexNotifier.value = 0,
                              isDark: widget.isDark,
                              onToggleTheme: widget.onToggleTheme,
                              deliveryLine: _deliveryLine,
                              onOpenDeliveryLocation:
                                  _openDeliveryLocationSheet,
                              onRefresh: _handlePullToRefresh,
                              onGoToOrders: () =>
                                  widget.navIndexNotifier.value = 2,
                            ),
                            _OrdersTab(
                              cartLinesNotifier: widget.cartLinesNotifier,
                              onMenu: _openAppMenu,
                              onCartTap: () =>
                                  widget.navIndexNotifier.value = 1,
                              isDark: widget.isDark,
                              onToggleTheme: widget.onToggleTheme,
                              ordersFilterNotifier: _ordersFilterNotifier,
                              onRefresh: _handlePullToRefresh,
                            ),
                            _ProfileTab(
                              cartLinesNotifier: widget.cartLinesNotifier,
                              onMenu: _openAppMenu,
                              onCartTap: () =>
                                  widget.navIndexNotifier.value = 1,
                              onViewAllOrders: () {
                                _ordersFilterNotifier.value = 0;
                                widget.navIndexNotifier.value = 2;
                              },
                              onEditProfile: () {
                                _openEditProfile();
                              },
                              onSettingsTap: _handleProfileSettingsTap,
                              onOrdersStatTap: _goToOrdersWithFilter,
                              isDark: widget.isDark,
                              onToggleTheme: widget.onToggleTheme,
                              onRefresh: _handlePullToRefresh,
                            ),
                            const CustomerChatScreen(asTab: true),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ListenableBuilder(
                  listenable: widget.navIndexNotifier,
                  builder: (context, _) => _BottomNavBar(
                    index: widget.navIndexNotifier.value,
                    onChanged: (i) => widget.navIndexNotifier.value = i,
                    onChat: _openCustomerChat,
                  ),
                ),
              ),
              // Cart bar — floats above nav bar when items are in cart
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    widget.cartLinesNotifier,
                    widget.navIndexNotifier,
                  ]),
                  builder: (context, _) {
                    final lines = widget.cartLinesNotifier.value;
                    final totalItems =
                        lines.fold<int>(0, (s, e) => s + e.qty);
                    final totalPrice =
                        lines.fold<int>(0, (s, e) => s + e.price * e.qty);
                    final navIndex = widget.navIndexNotifier.value;
                    final show = totalItems > 0 && navIndex != 1 && navIndex != 4;
                    final bottomInset =
                        MediaQuery.of(context).padding.bottom;
                    // Nav pill height (62) + bottom padding (20) + gap (8)
                    final aboveNav = 90.0 + bottomInset;
                    return AnimatedSlide(
                      offset:
                          show ? Offset.zero : const Offset(0, 1.5),
                      duration: ChechiBrand.fast,
                      curve: ChechiBrand.ease,
                      child: AnimatedOpacity(
                        opacity: show ? 1.0 : 0.0,
                        duration: ChechiBrand.fast,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              14, 0, 14, aboveNav),
                          child: GestureDetector(
                            onTap: () =>
                                widget.navIndexNotifier.value = 1,
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                color: _AppColors.primary,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: _AppColors.primary
                                        .withValues(alpha: 0.38),
                                    blurRadius: 18,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withValues(alpha: 0.18),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$totalItems item${totalItems == 1 ? '' : 's'}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'added to cart',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white
                                          .withValues(alpha: 0.85),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '₹$totalPrice',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'View Cart',
                                          style: GoogleFonts.poppins(
                                            color: _AppColors.primary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          color: _AppColors.primary,
                                          size: 11,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Design tokens for the My Profile screen (reference UI).
class _ProfilePalette {
  static const title = Color(0xFF661D1D);
  static const orange = Color(0xFFE65100);
  static const muted = Color(0xFF757575);
  static const cardBorder = Color(0xFFE8E2DC);
  static const cardFill = Color(0xFFFFFFFF);
  static const deliveredBg = Color(0xFFE8F5E9);
  static const deliveredFg = Color(0xFF2E7D32);
  static const ongoingBg = Color(0xFFFFF9C4);
  static const ongoingFg = Color(0xFFE65100);
  static const cancelledBg = Color(0xFFFFEBEE);
  static const cancelledFg = Color(0xFFC62828);
  static const totalBg = Color(0xFFF5EDE4);
  static const totalFg = Color(0xFF661D1D);
  static const listDivider = Color(0xFFEEEEEE);

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color titleOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.onSurface : title;
  static Color mutedOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.onSurfaceVariant : muted;
  static Color orangeOf(BuildContext c) => orange;
  static Color cardFillOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.surfaceContainerHigh : cardFill;
  static Color cardBorderOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.outlineVariant : cardBorder;
  static Color listDividerOf(BuildContext c) => _dark(c)
      ? Theme.of(c).colorScheme.outline.withValues(alpha: 0.25)
      : listDivider;

  /// Stat strip on profile: light pastels in light mode; deep tiles + readable text in dark.
  static ({Color bg, Color label, Color count, Color icon}) deliveredStatColors(
    BuildContext c,
  ) {
    if (!_dark(c)) {
      return (bg: deliveredBg, label: title, count: title, icon: deliveredFg);
    }
    return (
      bg: const Color(0xFF15251A),
      label: const Color(0xFFB2DFB2),
      count: const Color(0xFFE8F5E9),
      icon: const Color(0xFF81C784),
    );
  }

  static ({Color bg, Color label, Color count, Color icon}) ongoingStatColors(
    BuildContext c,
  ) {
    if (!_dark(c)) {
      return (bg: ongoingBg, label: title, count: title, icon: ongoingFg);
    }
    return (
      bg: const Color(0xFF3A3214),
      label: const Color(0xFFFFE082),
      count: const Color(0xFFFFF8E1),
      icon: const Color(0xFFFFCA28),
    );
  }

  static ({Color bg, Color label, Color count, Color icon}) cancelledStatColors(
    BuildContext c,
  ) {
    if (!_dark(c)) {
      return (bg: cancelledBg, label: title, count: title, icon: cancelledFg);
    }
    return (
      bg: const Color(0xFF351A1C),
      label: const Color(0xFFFFAB91),
      count: const Color(0xFFFFEBEE),
      icon: const Color(0xFFFF8A65),
    );
  }

  static ({Color bg, Color label, Color count, Color icon}) totalStatColors(
    BuildContext c,
  ) {
    if (!_dark(c)) {
      return (bg: totalBg, label: title, count: title, icon: totalFg);
    }
    return (
      bg: const Color(0xFF2A221C),
      label: const Color(0xFFFFCC80),
      count: const Color(0xFFFFF3E0),
      icon: const Color(0xFFFFB74D),
    );
  }
}

void _showChechiPaymentMethodsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'Payment methods',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          'Chechi Puttu currently accepts:\n\n'
          '• Cash on delivery (COD)\n'
          '• UPI at your door (GPay, PhonePe, Paytm)\n\n'
          'Saved cards and in-app wallet payments will be added in a future update.',
          style: GoogleFonts.poppins(
            height: 1.45,
            fontSize: 13,
            color: _ProfilePalette.mutedOf(c),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'OK',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

void _showChechiPrivacyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'Privacy & security',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          'We use your account and delivery details only to fulfil orders and improve '
          'your experience.\n\n'
          '• Sign-in is secured with Firebase Authentication.\n'
          '• Delivery addresses are stored on this device and used for checkout.\n'
          '• Location permission is optional and only used when you choose to detect your area.\n\n'
          'Contact support if you want your data reviewed or removed.',
          style: GoogleFonts.poppins(
            height: 1.45,
            fontSize: 13,
            color: _ProfilePalette.mutedOf(c),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'OK',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

void _showChechiFaqsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'FAQs',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _faqBlock(
              c,
              'How long does delivery take?',
              'Most orders in Kochi reach within 35–50 minutes during busy hours. Festival days may take a bit longer.',
            ),
            const SizedBox(height: 14),
            _faqBlock(
              c,
              'Can I schedule an order?',
              'Scheduled orders are coming soon. For now, choose items and place your order when you are ready to eat.',
            ),
            const SizedBox(height: 14),
            _faqBlock(
              c,
              'Is everything vegetarian?',
              'Most of our menu is vegetarian. Egg dishes are marked clearly — check item descriptions before ordering.',
            ),
            const SizedBox(height: 14),
            _faqBlock(
              c,
              'How do I change my address?',
              'Open Saved Addresses from your profile or tap Deliver to on the home screen.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'Close',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Widget _faqBlock(BuildContext context, String q, String a) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        q,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: _ProfilePalette.titleOf(context),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        a,
        style: GoogleFonts.poppins(
          fontSize: 12.5,
          height: 1.4,
          color: _ProfilePalette.mutedOf(context),
        ),
      ),
    ],
  );
}

void _showChechiTermsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'Terms & conditions',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          'By using Chechi Puttu you agree to:\n\n'
          '1. Provide accurate delivery information so riders can reach you.\n'
          '2. Pay for your order as agreed (COD or UPI at delivery unless stated otherwise).\n'
          '3. Treat delivery partners and support staff with respect.\n'
          '4. Use the app only for lawful personal orders.\n\n'
          'We may update prices, menu items, and these terms; continued use means you accept reasonable changes.\n\n'
          'For disputes, contact our support team first so we can resolve things quickly.',
          style: GoogleFonts.poppins(
            height: 1.45,
            fontSize: 13,
            color: _ProfilePalette.mutedOf(c),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'Close',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

void _showChechiCancellationPolicyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'Cancellation Policy',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          '1) Orders can be cancelled within 30 minutes of confirmation.\n\n'
          '2) Cancellation will not be accepted within 4 hours prior to the delivery time.\n\n'
          '3) Bulk and customized orders are non-refundable.\n\n'
          '4) Refunds, if applicable, will be processed within 12–24 hours.\n\n'
          '5) In case of unforeseen situations from our side, the customer will be informed immediately and eligible refunds will be processed accordingly.',
          style: GoogleFonts.poppins(
            height: 1.45,
            fontSize: 13,
            color: _ProfilePalette.mutedOf(c),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'Close',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

void _showChechiContactUsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'Contact Us',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Please do share your valuable feedback. For any further clarifications or queries, call us or WhatsApp us.',
              style: GoogleFonts.poppins(
                height: 1.45,
                fontSize: 13,
                color: _ProfilePalette.mutedOf(c),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.phone_in_talk_rounded,
                color: _ProfilePalette.titleOf(c),
              ),
              title: Text(
                'Mobile',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _ProfilePalette.mutedOf(c),
                ),
              ),
              subtitle: Text(
                '7538888437',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ProfilePalette.titleOf(c),
                ),
              ),
              onTap: () {
                Navigator.pop(c);
                launchUrl(
                  Uri.parse('tel:+917538888437'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.chat_rounded,
                color: _ProfilePalette.titleOf(c),
              ),
              title: Text(
                'WhatsApp',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _ProfilePalette.mutedOf(c),
                ),
              ),
              subtitle: Text(
                '7538888437',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ProfilePalette.titleOf(c),
                ),
              ),
              onTap: () {
                Navigator.pop(c);
                launchUrl(
                  Uri.parse(
                    'https://wa.me/917538888437?text=${Uri.encodeQueryComponent('Hi Chechi Puttu Kadai!')}',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.email_outlined,
                color: _ProfilePalette.titleOf(c),
              ),
              title: Text(
                'Email',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _ProfilePalette.mutedOf(c),
                ),
              ),
              subtitle: Text(
                'chechiputtukadai@gmail.com',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ProfilePalette.titleOf(c),
                ),
              ),
              onTap: () {
                Navigator.pop(c);
                launchUrl(
                  Uri.parse(
                    'mailto:chechiputtukadai@gmail.com?subject=Chechi%20Puttu%20Kadai%20—%20Customer%20query',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'Close',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

void _showChechiAboutDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'About Us',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: _ProfilePalette.titleOf(c),
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          'Sai Logabala OPC Pvt. Ltd. proudly presents Chechi Puttu Kadai, a brand dedicated to bringing authentic Kerala traditional flavors to your plate. We specialize in a wide variety of puttu, homemade snacks, catering services, live counters, party orders, and doorstep delivery with quality, hygiene, and taste at heart.\n\n'
          'We also extend our services to hospital in-patients, ensuring fresh, hygienic, and homely food delivered with care and comfort.\n\n'
          'Our mission is to serve fresh, delicious food with a touch of tradition and homemade love.',
          style: GoogleFonts.poppins(
            height: 1.45,
            fontSize: 13,
            color: _ProfilePalette.mutedOf(c),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(
            'OK',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.cartLinesNotifier,
    required this.onMenu,
    required this.onCartTap,
    required this.onViewAllOrders,
    required this.onEditProfile,
    required this.onSettingsTap,
    required this.onOrdersStatTap,
    required this.isDark,
    required this.onToggleTheme,
    required this.onRefresh,
  });

  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;
  final VoidCallback onMenu;
  final VoidCallback onCartTap;
  final VoidCallback onViewAllOrders;
  final VoidCallback onEditProfile;
  final void Function(BuildContext context, String label) onSettingsTap;
  final ValueChanged<int> onOrdersStatTap;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final name = (user?.displayName ?? 'Anjali Nair').trim();
    final email = user?.email ?? 'anjali.nair@email.com';
    return FutureBuilder<_ProfileStoredData>(
      future: _readStoredProfileData(user),
      builder: (context, snap) {
        final storedPhone = snap.data?.mobile ?? '';
        final phone = storedPhone.isNotEmpty
            ? storedPhone
            : (user?.phoneNumber ?? '+91 98765 43210');
        return AppPullToRefresh(
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            physics: AppPullToRefresh.scrollPhysics,
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: onMenu,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.menu_rounded,
                            size: 26,
                            color: _ProfilePalette.titleOf(context),
                          ),
                        ),
                    ),
                    const Spacer(),
                    _RoundThemeToggle(isDark: isDark, onToggle: onToggleTheme),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onCartTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: ListenableBuilder(
                          listenable: cartLinesNotifier,
                          builder: (context, _) {
                            final cartCount = _cartBadgeTotal(
                              cartLinesNotifier.value,
                            );
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 24,
                                  color: _ProfilePalette.titleOf(context),
                                ),
                                if (cartCount > 0)
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE53935),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _AppColors.appBackdrop,
                                          width: 1.5,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$cartCount',
                                        style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Profile',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: _ProfilePalette.titleOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage your account and preferences',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: _ProfilePalette.mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ProfileUserCard(
                  name: name.isEmpty ? 'Anjali Nair' : name,
                  email: email,
                  phone: phone,
                  onEditProfile: onEditProfile,
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ProfileOrdersSummary(
                  onViewAll: onViewAllOrders,
                  onStatTap: onOrdersStatTap,
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ProfileSettingsSection(
                  title: 'Account Settings',
                  onItemTap: onSettingsTap,
                  items: const [
                    (Icons.person_outline_rounded, 'Personal Information'),
                    (Icons.location_on_outlined, 'Saved Addresses'),
                    (Icons.credit_card_outlined, 'Payment Methods'),
                    (Icons.notifications_none_rounded, 'Notifications'),
                    (Icons.verified_user_outlined, 'Privacy & Security'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ProfileSettingsSection(
                  title: 'Support & More',
                  onItemTap: onSettingsTap,
                  items: const [
                    (Icons.headset_mic_outlined, 'Help & Support'),
                    (Icons.contact_phone_outlined, 'Contact Us'),
                    (Icons.help_outline_rounded, 'FAQs'),
                    (Icons.description_outlined, 'Terms & Conditions'),
                    (Icons.policy_outlined, 'Cancellation Policy'),
                    (Icons.info_outline_rounded, 'About Us'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await authService.signOut();
                  },
                  icon: Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: _ProfilePalette.titleOf(context),
                  ),
                  label: Text(
                    'Logout',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ProfilePalette.titleOf(context),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ProfilePalette.titleOf(context),
                    side: BorderSide(
                      color: _ProfilePalette.titleOf(context),
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 100), // space for floating nav bar
            ],
          ),
        ),
        );
      },
    );
  }
}

class _ProfileUserCard extends StatelessWidget {
  const _ProfileUserCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.onEditProfile,
  });

  final String name;
  final String email;
  final String phone;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: _ProfilePalette.cardFillOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ProfilePalette.cardBorderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFFF3E8DC),
            backgroundImage: const AssetImage('assets/images/hero.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ProfilePalette.titleOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _ProfilePalette.mutedOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _ProfilePalette.mutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEditProfile,
            tooltip: 'Edit profile',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              Icons.edit_outlined,
              size: 20,
              color: _ProfilePalette.titleOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileOrdersSummary extends StatelessWidget {
  const _ProfileOrdersSummary({
    required this.onViewAll,
    required this.onStatTap,
  });

  final VoidCallback onViewAll;
  final ValueChanged<int> onStatTap;

  @override
  Widget build(BuildContext context) {
    final delivered = _ProfilePalette.deliveredStatColors(context);
    final ongoing = _ProfilePalette.ongoingStatColors(context);
    final cancelled = _ProfilePalette.cancelledStatColors(context);
    final total = _ProfilePalette.totalStatColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'My Orders',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ProfilePalette.titleOf(context),
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All Orders',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ProfilePalette.orangeOf(context),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _ProfilePalette.orangeOf(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _ProfilePalette.cardFillOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _ProfilePalette.cardBorderOf(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ProfileStatCell(
                  bg: delivered.bg,
                  icon: Icons.shopping_bag_outlined,
                  iconColor: delivered.icon,
                  label: 'Delivered',
                  count: '0',
                  labelColor: delivered.label,
                  countColor: delivered.count,
                  onTap: () => onStatTap(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileStatCell(
                  bg: ongoing.bg,
                  icon: Icons.schedule_rounded,
                  iconColor: ongoing.icon,
                  label: 'Ongoing',
                  count: '0',
                  labelColor: ongoing.label,
                  countColor: ongoing.count,
                  onTap: () => onStatTap(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileStatCell(
                  bg: cancelled.bg,
                  icon: Icons.cancel_outlined,
                  iconColor: cancelled.icon,
                  label: 'Cancelled',
                  count: '0',
                  labelColor: cancelled.label,
                  countColor: cancelled.count,
                  onTap: () => onStatTap(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileStatCell(
                  bg: total.bg,
                  icon: Icons.inventory_2_outlined,
                  iconColor: total.icon,
                  label: 'Total Orders',
                  count: '0',
                  labelColor: total.label,
                  countColor: total.count,
                  onTap: () => onStatTap(0),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStatCell extends StatelessWidget {
  const _ProfileStatCell({
    required this.bg,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.labelColor,
    required this.countColor,
    required this.onTap,
  });

  final Color bg;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String count;
  final Color labelColor;
  final Color countColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: countColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSettingsSection extends StatelessWidget {
  const _ProfileSettingsSection({
    required this.title,
    required this.items,
    required this.onItemTap,
  });

  final String title;
  final List<(IconData, String)> items;
  final void Function(BuildContext context, String label) onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _ProfilePalette.titleOf(context),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _ProfilePalette.cardFillOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _ProfilePalette.cardBorderOf(context)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: _ProfilePalette.listDividerOf(context),
                  ),
                _ProfileSettingsTile(
                  icon: items[i].$1,
                  label: items[i].$2,
                  onTap: () => onItemTap(context, items[i].$2),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSettingsTile extends StatelessWidget {
  const _ProfileSettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: _ProfilePalette.titleOf(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ProfilePalette.titleOf(context),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: _ProfilePalette.mutedOf(context).withValues(alpha: 0.65),
            ),
          ],
        ),
      ),
    );
  }
}

/// Design tokens for the Categories screen (reference UI).
class _CategoriesPalette {
  static const title = Color(0xFF5D1F1A);
  static const accent = Color(0xFFE85D3F);
  static const muted = Color(0xFF7A7A7A);
  static const cardBorder = Color(0xFFE5E0DA);
  static const cardFill = Color(0xFFFFFFFF);
  static const thumbPlaceholder = Color(0xFFF3EBE3);

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color titleOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.onSurface : title;
  static Color mutedOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.onSurfaceVariant : muted;
  static Color cardFillOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.surfaceContainerHigh : cardFill;
  static Color cardBorderOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.outlineVariant : cardBorder;
  static Color thumbPlaceholderOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.surfaceContainer : thumbPlaceholder;
  static Color cartBadgeRingOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.surface : cardFill;
}

/// Design tokens for the My Orders screen (reference UI).
class _OrdersPalette {
  static const pageBg = Color(0xFFFFF9F2);
  static const title = Color(0xFF5D1F1A);
  static const muted = Color(0xFF7A7A7A);
  static const cardBorder = Color(0xFFE8E2DC);
  static const cardFill = Color(0xFFFFFFFF);
  static const filterBorder = Color(0xFFE0D8D0);
  static const divider = Color(0xFFD4CCC4);
  // Status badge backgrounds / foregrounds
  static const deliveredBg = Color(0xFFE8F5E9);
  static const deliveredFg = Color(0xFF1B5E20);
  static const ongoingBg = Color(0xFFFFF3E0);
  static const ongoingFg = Color(0xFFE65100);
  static const cancelledBg = Color(0xFFFFEBEE);
  static const cancelledFg = Color(0xFFC62828);
  static const deliveredIcon = Color(0xFF2E7D32);
  static const ongoingIcon = Color(0xFFE65100);
  static const cancelledIcon = Color(0xFFC62828);

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color pageBgOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.surface : pageBg;
  static Color titleOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.onSurface : title;
  static Color mutedOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.onSurfaceVariant : muted;
  static Color cardFillOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.surfaceContainerHigh : cardFill;
  static Color cardBorderOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.outlineVariant : cardBorder;
  static Color filterBorderOf(BuildContext c) =>
      _dark(c) ? Theme.of(c).colorScheme.outlineVariant : filterBorder;
  static Color dividerOf(BuildContext c) => _dark(c)
      ? Theme.of(c).colorScheme.outline.withValues(alpha: 0.35)
      : divider;

  /// Selected filter chip background (maroon in light; primary in dark).
  static Color filterSelectedBgOf(BuildContext c) {
    final t = Theme.of(c);
    if (_dark(c)) return t.colorScheme.primary;
    return title;
  }
}

enum _OrderUiStatus { delivered, ongoing, cancelled }

class _OrderUiModel {
  const _OrderUiModel({
    required this.sourceId,
    required this.id,
    required this.itemCount,
    required this.placedAt,
    required this.statusRaw,
    required this.statusLine,
    required this.status,
    required this.price,
    required this.actionLabel,
    required this.reorderLines,
    required this.canRate,
    required this.deliveryLine,
    required this.paymentMode,
  });

  final String sourceId;
  final String id;
  final int itemCount;
  final String placedAt;
  final String statusRaw;
  final String statusLine;
  final _OrderUiStatus status;
  final String price;
  final String actionLabel;
  final List<CartLineItem> reorderLines;
  final bool canRate;
  final String deliveryLine;
  final String paymentMode;

  /// Customer may cancel while the order is still early in the flow. Once it is
  /// out for delivery, delivered, completed, cancelled or rejected, it can't.
  bool get canCancel {
    switch (statusRaw.trim().toLowerCase()) {
      case '':
      case 'placed':
      case 'new':
      case 'accepted':
      case 'preparing':
      case 'ready':
        return true;
      default:
        return false;
    }
  }
}

int _orderTimelineStepFromRaw(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'preparing':
    case 'accepted':
      return 1;
    case 'ready':
      return 2;
    case 'completed':
    case 'delivered':
    case 'out_for_delivery':
      return 3;
    default:
      return 0;
  }
}

enum _CheckoutPaymentMode { cashOnDelivery, onlinePayment }

class _CartTab extends StatefulWidget {
  const _CartTab({
    required this.cartLinesNotifier,
    required this.onBack,
    required this.isDark,
    required this.onToggleTheme,
    required this.deliveryLine,
    required this.onOpenDeliveryLocation,
    required this.onRefresh,
    this.onGoToOrders,
  });

  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;
  final VoidCallback onBack;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final String deliveryLine;
  final Future<void> Function() onOpenDeliveryLocation;
  final Future<void> Function() onRefresh;
  final VoidCallback? onGoToOrders;

  @override
  State<_CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<_CartTab> {
  late final OrdersService _orders;
  late final RazorpayCheckoutService _rzpCheckout;
  final Razorpay _razorpay = Razorpay();
  Completer<PaymentSuccessResponse?>? _rzpResult;

  @override
  void initState() {
    super.initState();
    _orders = OrdersService();
    _rzpCheckout = RazorpayCheckoutService();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRzpSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onRzpError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onRzpExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // The Razorpay SDK fires success only when the payment is captured; the app
  // then verifies the signature server-side. Error fires on failure/cancel.
  // The completer bridges these events to the awaiting checkout flow (null =
  // not completed).
  void _onRzpSuccess(PaymentSuccessResponse r) {
    if (_rzpResult != null && !_rzpResult!.isCompleted) {
      _rzpResult!.complete(r);
    }
  }

  void _onRzpError(PaymentFailureResponse r) {
    if (_rzpResult != null && !_rzpResult!.isCompleted) {
      _rzpResult!.complete(null);
    }
  }

  void _onRzpExternalWallet(ExternalWalletResponse r) {
    // UPI / cards / net banking resolve via success/error. External wallet
    // selection continues in the wallet app; no completer action needed.
  }

  int _deliveryFeeFor(List<CartLineItem> items) => items.isEmpty ? 0 : 30;

  int _packagingFeeFor(List<CartLineItem> items) => items.isEmpty ? 0 : 10;

  int _lineSum(List<CartLineItem> items) =>
      items.fold<int>(0, (s, e) => s + e.price * e.qty);

  int _qtySum(List<CartLineItem> items) =>
      items.fold<int>(0, (s, e) => s + e.qty);

  String _checkoutErrorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? e.code;
    }
    return e.toString();
  }

  bool _hasValidDeliveryLine(String line) {
    final v = line.trim().toLowerCase();
    if (v.isEmpty) return false;
    if (v == 'choose delivery address') return false;
    if (v.startsWith('add location -')) return false;
    return true;
  }

  Future<String?> _ensureDeliveryLineForCheckout(BuildContext context) async {
    var line = widget.deliveryLine.trim();
    if (_hasValidDeliveryLine(line)) return line;

    await widget.onOpenDeliveryLocation();
    if (!context.mounted) return null;
    line = widget.deliveryLine.trim();
    if (_hasValidDeliveryLine(line)) return line;

    final p = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final street = (p.getString(_deliveryStreetKey(uid)) ?? '').trim();
    if (_hasValidDeliveryLine(street)) return street;
    if (!context.mounted) return null;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Please choose your delivery location before placing the order.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
    return null;
  }

  /// Razorpay in-app checkout → verify signature server-side → place order.
  Future<void> _runOnlineRazorpayCheckout({
    required BuildContext context,
    required ScaffoldMessengerState messenger,
    required List<CartLineItem> lines,
    required int total,
    required String deliveryLine,
    required String? scheduleLine,
    required DateTime? scheduledAt,
  }) async {
    if (kIsWeb) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Online payment is available on the Android/iOS app. Please use cash on delivery here.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    final items = <Map<String, Object?>>[
      for (final li in lines)
        <String, Object?>{
          'name': li.name,
          'subtitle': li.subtitle,
          'qty': li.qty,
        },
    ];

    // Show loading immediately while the Firebase function + Razorpay order
    // creation completes (~2-4 s).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text('Opening payment…', style: GoogleFonts.poppins(fontSize: 14)),
            ],
          ),
        ),
      ),
    );

    late final RazorpayCheckoutResult start;
    try {
      start = await _rzpCheckout.createCheckout(
        items: items,
        deliveryLine: deliveryLine,
        scheduleLine: scheduleLine,
        scheduledAt: scheduledAt,
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _checkoutErrorMessage(e),
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    // Open the Razorpay checkout. Success fires only on a captured payment.
    final payResult = Completer<PaymentSuccessResponse?>();
    _rzpResult = payResult;
    final user = FirebaseAuth.instance.currentUser;
    final phoneDigits = (user?.phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final contact = phoneDigits.length >= 10
        ? phoneDigits.substring(phoneDigits.length - 10)
        : null;
    try {
      _razorpay.open(<String, dynamic>{
        'key': start.keyId,
        'order_id': start.razorpayOrderId,
        'amount': start.amountPaise,
        'currency': 'INR',
        'name': 'Chechi Puttu Kadai',
        'description': 'Order payment',
        'theme': <String, dynamic>{'color': '#7C1D1B'},
        if (contact != null) 'prefill': <String, dynamic>{'contact': contact},
      });
    } catch (e) {
      _rzpResult = null;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open payment: $e',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    PaymentSuccessResponse? success;
    try {
      success = await payResult.future.timeout(const Duration(minutes: 12));
    } on TimeoutException {
      _rzpResult = null;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Payment window closed. No order was placed.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    } catch (_) {
      _rzpResult = null;
      return;
    }
    _rzpResult = null;

    if (!context.mounted) return;

    if (success == null) {
      // The SDK reported failure/cancellation — Razorpay only fires success on
      // a captured payment, so no money was taken.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Payment was not completed. No order was placed.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Confirming payment…\n'
                  'Do not close the app.',
                  style: GoogleFonts.poppins(height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    RazorpayPaymentOutcome outcome;
    try {
      outcome = await _rzpCheckout.verifyPayment(
        sessionId: start.sessionId,
        razorpayOrderId: success.orderId ?? start.razorpayOrderId,
        razorpayPaymentId: success.paymentId ?? '',
        razorpaySignature: success.signature ?? '',
      );
      if (!outcome.isTerminal) {
        // Verify didn't confirm (transient) — fall back to the webhook-updated
        // session doc.
        outcome = await _rzpCheckout.confirmPayment(
          start.sessionId,
          timeout: const Duration(minutes: 2),
        );
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!context.mounted) return;
    if (outcome.isPaid) {
      final orderId = outcome.orderId!;
      final ref = orderId.length > 10 ? orderId.substring(0, 10) : orderId;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _OrderSuccessDialog(
          scheduleLine: scheduleLine ?? '',
          deliveryLine: deliveryLine,
          total: total,
          paymentLabel: 'Paid online · Ref: $ref',
          onTrackOrder: widget.onGoToOrders,
        ),
      );
      if (!context.mounted) return;
      widget.cartLinesNotifier.value = [];
    } else if (outcome.isFailed) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Payment was not completed. No order was placed.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } else {
      // Unconfirmed: timed out without a definite answer. Money may have been
      // debited — never claim "no order placed". The webhook still creates the
      // order automatically once Razorpay confirms.
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text(
            'We could not confirm your payment yet. If money was debited, your '
            'order will appear in Orders within a few minutes — please do not '
            'pay again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    }
  }

  Future<void> _runCheckout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final lines = List<CartLineItem>.from(widget.cartLinesNotifier.value);
    if (lines.isEmpty) return;
    final deliveryLine = await _ensureDeliveryLineForCheckout(context);
    if (!context.mounted || deliveryLine == null) return;

    final booking = await AdvanceOrderSchedule.pickMealBooking(context);
    if (!context.mounted || booking == null) return;

    final pay = await showModalBottomSheet<_CheckoutPaymentMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose payment',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'How would you like to pay?',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _PaymentOptionTile(
                  icon: Icons.payments_rounded,
                  iconBg: const Color(0xFFE8F5E9),
                  iconColor: const Color(0xFF2E7D32),
                  title: 'Cash on Delivery',
                  subtitle: 'Pay when your order arrives',
                  onTap: () =>
                      Navigator.pop(ctx, _CheckoutPaymentMode.cashOnDelivery),
                ),
                const SizedBox(height: 10),
                _PaymentOptionTile(
                  icon: Icons.credit_card_rounded,
                  iconBg: const Color(0xFFE3F2FD),
                  iconColor: const Color(0xFF1565C0),
                  title: 'Online Payment',
                  subtitle: 'UPI, cards, net banking via Razorpay',
                  onTap: () =>
                      Navigator.pop(ctx, _CheckoutPaymentMode.onlinePayment),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || pay == null) return;

    final scheduleLine = booking.displayLine;
    final scheduledAt = booking.when;

    final total =
        _lineSum(lines) + _deliveryFeeFor(lines) + _packagingFeeFor(lines);

    if (pay == _CheckoutPaymentMode.onlinePayment) {
      await _runOnlineRazorpayCheckout(
        context: context,
        messenger: messenger,
        lines: lines,
        total: total,
        deliveryLine: deliveryLine,
        scheduleLine: scheduleLine,
        scheduledAt: scheduledAt,
      );
      return;
    }

    // Persist COD order for notifications + admin status updates.
    try {
      await _orders.createOrder(
        items: [
          for (final li in lines)
            {
              'name': li.name,
              'subtitle': li.subtitle,
              'priceRupees': li.price,
              'qty': li.qty,
            },
        ],
        totalRupees: total,
        deliveryLine: deliveryLine,
        paymentMode: 'cash_on_delivery',
        scheduleLine: scheduleLine,
        scheduledAt: scheduledAt,
      );
    } catch (e) {
      // Booking failed to save — tell the customer and keep the cart so they
      // can retry. Never show a fake "Order placed" confirmation.
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not place your order. Please check your internet and try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OrderSuccessDialog(
        scheduleLine: scheduleLine,
        deliveryLine: deliveryLine,
        total: total,
        paymentLabel: 'Pay ₹$total cash on delivery',
        onTrackOrder: widget.onGoToOrders,
      ),
    );
    if (!context.mounted) return;
    widget.cartLinesNotifier.value = [];
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark
        ? Theme.of(context).colorScheme.onSurface
        : const Color(0xFF661D1D);
    final muted = dark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : const Color(0xFF7A7A7A);
    final cardFill = dark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Colors.white;
    final border = dark
        ? Theme.of(context).colorScheme.outlineVariant
        : const Color(0xFFE8E2DC);

    return ListenableBuilder(
      listenable: widget.cartLinesNotifier,
      builder: (context, _) {
        final lines = widget.cartLinesNotifier.value;
        final itemTotal = _lineSum(lines);
        final deliveryFee = _deliveryFeeFor(lines);
        final packagingFee = _packagingFeeFor(lines);
        final toPay = itemTotal + deliveryFee + packagingFee;
        final itemCount = _qtySum(lines);

        return AppPullToRefresh(
          onRefresh: widget.onRefresh,
          child: SingleChildScrollView(
            physics: AppPullToRefresh.scrollPhysics,
            padding: EdgeInsets.fromLTRB(
                16, 6, 16, 110 + MediaQuery.of(context).padding.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: widget.onBack,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 24,
                          color: titleColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'My Cart',
                style: GoogleFonts.playfairDisplay(
                  color: titleColor,
                  fontSize: 44,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                lines.isEmpty
                    ? 'Add dishes from Home to see them here'
                    : AdvanceOrderSchedule.policySummary(),
                style: GoogleFonts.poppins(
                  color: muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 20,
                      color: Color(0xFFE65100),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pre-book only — no same-day orders. '
                        'Example: order at 9 PM today → tomorrow dinner.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF5D4037),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _CartDeliveryCard(
                border: border,
                fill: cardFill,
                muted: muted,
                title: titleColor,
                deliveryLine: widget.deliveryLine,
                onOpenLocation: widget.onOpenDeliveryLocation,
              ),
              const SizedBox(height: 10),
              if (lines.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 36,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: cardFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_basket_outlined,
                        size: 48,
                        color: muted.withValues(alpha: 0.65),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your cart is empty',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: titleColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use the + button on dishes in Home to add items.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: cardFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < lines.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final idx = i;
                            return _CartItemTile(
                              item: lines[idx],
                              titleColor: titleColor,
                              muted: muted,
                              border: border,
                              onMinus: () {
                                final next = List<CartLineItem>.from(
                                  widget.cartLinesNotifier.value,
                                );
                                if (next[idx].qty > 1) {
                                  next[idx] = next[idx].copyWith(
                                    qty: next[idx].qty - 1,
                                  );
                                } else {
                                  next.removeAt(idx);
                                }
                                widget.cartLinesNotifier.value = next;
                              },
                              onPlus: () {
                                final next = List<CartLineItem>.from(
                                  widget.cartLinesNotifier.value,
                                );
                                next[idx] = next[idx].copyWith(
                                  qty: next[idx].qty + 1,
                                );
                                widget.cartLinesNotifier.value = next;
                              },
                              onDelete: () {
                                final next = List<CartLineItem>.from(
                                  widget.cartLinesNotifier.value,
                                );
                                next.removeAt(idx);
                                widget.cartLinesNotifier.value = next;
                              },
                            );
                          },
                        ),
                        if (i < lines.length - 1)
                          Divider(
                            height: 1,
                            color: border.withValues(alpha: 0.85),
                          ),
                      ],
                    ],
                  ),
                ),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 10),
                _CartCouponCard(
                  border: border,
                  fill: cardFill,
                  muted: muted,
                  titleColor: titleColor,
                ),
                const SizedBox(height: 10),
                _CartSummaryCard(
                  border: border,
                  fill: cardFill,
                  titleColor: titleColor,
                  muted: muted,
                  itemTotal: itemTotal,
                  deliveryFee: deliveryFee,
                  packagingFee: packagingFee,
                  toPay: toPay,
                  itemCount: itemCount,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: lines.isEmpty
                        ? const Color(0xFFFF5A1F).withValues(alpha: 0.45)
                        : const Color(0xFFFF5A1F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: lines.isEmpty ? null : () => _runCheckout(context),
                  child: Text(
                    'Book order  →',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartDeliveryCard extends StatelessWidget {
  const _CartDeliveryCard({
    required this.border,
    required this.fill,
    required this.muted,
    required this.title,
    required this.deliveryLine,
    required this.onOpenLocation,
  });

  final Color border;
  final Color fill;
  final Color muted;
  final Color title;
  final String deliveryLine;
  final Future<void> Function() onOpenLocation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () async {
          await onOpenLocation();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_outlined, color: muted, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery address',
                      style: GoogleFonts.poppins(
                        color: muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      deliveryLine,
                      style: GoogleFonts.poppins(
                        color: title,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.titleColor,
    required this.muted,
    required this.border,
    required this.onMinus,
    required this.onPlus,
    required this.onDelete,
  });

  final CartLineItem item;
  final Color titleColor;
  final Color muted;
  final Color border;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onDelete;

  Widget _buildDishImage() {
    final b64 = item.imageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final bytes = _MenuBase64ImageCache.read(b64);
        if (bytes == null) throw const FormatException('bad base64');
        return Image.memory(
          bytes,
          key: ValueKey(b64.hashCode),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          width: double.infinity,
          height: double.infinity,
        );
      } catch (_) {}
    }
    return Image.asset(
      'assets/images/hero.png',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 70,
              height: 70,
              child: _buildDishImage(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    color: titleColor,
                    fontSize: 17,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: muted,
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${item.price}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFE65100),
                    fontSize: 18,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: Color(0xFFB25A5A),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QtyButton(icon: Icons.remove_rounded, onTap: onMinus),
                    Container(
                      alignment: Alignment.center,
                      width: 36,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(color: border),
                        ),
                      ),
                      child: Text(
                        '${item.qty}',
                        style: GoogleFonts.poppins(
                          color: titleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _QtyButton(icon: Icons.add_rounded, onTap: onPlus),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : const Color(0xFF7A7A7A);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Icon(icon, size: 18, color: muted),
      ),
    );
  }
}

class _CartCouponCard extends StatelessWidget {
  const _CartCouponCard({
    required this.border,
    required this.fill,
    required this.muted,
    required this.titleColor,
  });

  final Color border;
  final Color fill;
  final Color muted;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD580).withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Color(0xFFE67C2D),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fresh & Made to Order',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF5D1F1A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Every dish is prepared fresh for you',
                  style: GoogleFonts.poppins(
                    color: muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFFE67C2D),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _CartSummaryCard extends StatelessWidget {
  const _CartSummaryCard({
    required this.border,
    required this.fill,
    required this.titleColor,
    required this.muted,
    required this.itemTotal,
    required this.deliveryFee,
    required this.packagingFee,
    required this.toPay,
    required this.itemCount,
  });

  final Color border;
  final Color fill;
  final Color titleColor;
  final Color muted;
  final int itemTotal;
  final int deliveryFee;
  final int packagingFee;
  final int toPay;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Summary',
            style: GoogleFonts.playfairDisplay(
              color: titleColor,
              fontSize: 28,
              height: 0.98,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Item Total ($itemCount items)',
            value: '₹$itemTotal',
            color: muted,
          ),
          const SizedBox(height: 5),
          _SummaryRow(
            label: 'Delivery Fee',
            value: '₹$deliveryFee',
            color: muted,
          ),
          const SizedBox(height: 5),
          _SummaryRow(
            label: 'Packaging Fee',
            value: '₹$packagingFee',
            color: muted,
          ),
          const SizedBox(height: 8),
          Divider(color: border.withValues(alpha: 0.8), height: 1),
          const SizedBox(height: 9),
          _SummaryRow(
            label: 'To Pay',
            value: '₹$toPay',
            color: titleColor,
            valueColor: const Color(0xFFE65100),
            labelWeight: FontWeight.w700,
            valueWeight: FontWeight.w800,
            isTotal: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.valueColor,
    this.labelWeight = FontWeight.w500,
    this.valueWeight = FontWeight.w600,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final Color color;
  final Color? valueColor;
  final FontWeight labelWeight;
  final FontWeight valueWeight;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: isTotal ? 16 : 14,
              fontWeight: labelWeight,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: valueColor ?? color,
            fontSize: isTotal ? 22 : 14,
            height: isTotal ? 1.0 : 1.2,
            fontWeight: valueWeight,
          ),
        ),
      ],
    );
  }
}

class _OrderSuccessDialog extends StatelessWidget {
  const _OrderSuccessDialog({
    required this.scheduleLine,
    required this.deliveryLine,
    required this.total,
    required this.paymentLabel,
    this.onTrackOrder,
  });

  final String scheduleLine;
  final String deliveryLine;
  final int total;
  final String paymentLabel;
  final VoidCallback? onTrackOrder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2E7D32),
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Order Placed!',
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'We\'ll start preparing your food soon.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  _SuccessRow(
                    icon: Icons.schedule_rounded,
                    label: scheduleLine,
                  ),
                  const SizedBox(height: 8),
                  _SuccessRow(
                    icon: Icons.location_on_rounded,
                    label: deliveryLine,
                  ),
                  const SizedBox(height: 8),
                  _SuccessRow(
                    icon: Icons.payments_outlined,
                    label: paymentLabel,
                    highlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFEFE6), Color(0xFFFFF5ED)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Total paid: ',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF5D1F1A),
                    ),
                  ),
                  Text(
                    '₹$total',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFE65100),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ChechiBrand.maroonDeep,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onTrackOrder?.call();
                },
                child: Text(
                  'Track my order',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: highlight ? const Color(0xFF2E7D32) : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              color: highlight ? const Color(0xFF2E7D32) : cs.onSurface,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _RateOrderDialog extends StatefulWidget {
  const _RateOrderDialog();

  @override
  State<_RateOrderDialog> createState() => _RateOrderDialogState();
}

class _RateOrderDialogState extends State<_RateOrderDialog> {
  int _stars = 5;
  final TextEditingController _reviewCtrl = TextEditingController();

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Rate your order',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (i) => IconButton(
                  onPressed: () => setState(() => _stars = i + 1),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  iconSize: 30,
                  icon: Icon(
                    i < _stars
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFFFFB300),
                  ),
                ),
              ),
            ),
            TextField(
              controller: _reviewCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Write a short review (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (rating: _stars, review: _reviewCtrl.text.trim()),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

Widget _orderInvoiceRow(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _OrdersPalette.mutedOf(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _OrdersPalette.titleOf(context),
            ),
          ),
        ),
      ],
    ),
  );
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({
    required this.cartLinesNotifier,
    required this.onMenu,
    required this.onCartTap,
    required this.isDark,
    required this.onToggleTheme,
    required this.ordersFilterNotifier,
    required this.onRefresh,
  });

  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;
  final VoidCallback onMenu;
  final VoidCallback onCartTap;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final ValueNotifier<int> ordersFilterNotifier;
  final Future<void> Function() onRefresh;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  int _filter = 0;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    _filter = widget.ordersFilterNotifier.value.clamp(0, 3);
    widget.ordersFilterNotifier.addListener(_syncFilterFromNotifier);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _ordersStream = chechiFirestore
          .collection('orders')
          .where('uid', isEqualTo: uid)
          .limit(120)
          .snapshots();
    }
  }

  void _syncFilterFromNotifier() {
    final v = widget.ordersFilterNotifier.value.clamp(0, 3);
    if (_filter != v && mounted) setState(() => _filter = v);
  }

  @override
  void dispose() {
    widget.ordersFilterNotifier.removeListener(_syncFilterFromNotifier);
    super.dispose();
  }

  void _setFilter(int i) {
    final v = i.clamp(0, 3);
    setState(() => _filter = v);
    widget.ordersFilterNotifier.value = v;
  }

  List<_OrderUiModel> _visibleFrom(List<_OrderUiModel> list) {
    switch (_filter) {
      case 1:
        return list
            .where((o) => o.status == _OrderUiStatus.ongoing)
            .toList();
      case 2:
        return list
            .where((o) => o.status == _OrderUiStatus.delivered)
            .toList();
      case 3:
        return list
            .where((o) => o.status == _OrderUiStatus.cancelled)
            .toList();
      default:
        return list;
    }
  }

  _OrderUiStatus _statusFromRaw(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'delivered' || s == 'completed') return _OrderUiStatus.delivered;
    if (s == 'cancelled' || s == 'rejected') return _OrderUiStatus.cancelled;
    return _OrderUiStatus.ongoing;
  }

  String _statusLineFromRaw(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'placed':
        return 'Order placed successfully.';
      case 'preparing':
      case 'accepted':
        return 'Chechi kitchen is preparing your order.';
      case 'ready':
        return 'Your order is packed and ready.';
      case 'out_for_delivery':
        return 'Delivery partner is on the way.';
      case 'delivered':
        return 'Delivered to your location.';
      case 'completed':
        return 'Order completed successfully.';
      case 'cancelled':
        return 'This order was cancelled.';
      case 'rejected':
        return 'Order rejected by store.';
      default:
        return 'Order update: ${s.isEmpty ? 'pending' : s}.';
    }
  }

  String _placedAtLabel(DateTime? t) {
    if (t == null) return 'Date unavailable';
    final d = '${t.day.toString().padLeft(2, '0')}/'
        '${t.month.toString().padLeft(2, '0')}/${t.year}';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$d • $h:$m $ampm';
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return 0;
  }

  List<CartLineItem> _reorderLinesFromOrder(Map<String, dynamic> m) {
    final lines = <CartLineItem>[];
    final rawItems = m['items'];
    if (rawItems is! List) return lines;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? raw['title'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final subtitle = (raw['subtitle'] ?? '').toString().trim();
      final qty = (_asInt(raw['qty'] ?? raw['quantity'])).clamp(1, 99);
      final price = _asInt(raw['priceRupees'] ?? raw['price_rupees']);
      lines.add(
        CartLineItem(
          name: name,
          subtitle: subtitle,
          price: price,
          qty: qty,
        ),
      );
    }
    return lines;
  }

  _OrderUiModel _orderUiFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final statusRaw = (m['status'] as String?) ?? '';
    final status = _statusFromRaw(statusRaw);
    final created = m['created_at'];
    final dt = created is Timestamp ? created.toDate() : null;
    final total = _asInt(m['total_rupees']);
    final reorderLines = _reorderLinesFromOrder(m);
    final deliveryLine = (m['delivery_line'] as String?)?.trim() ?? '';
    final paymentMode = (m['payment_mode'] as String?)?.trim() ?? 'cash_on_delivery';
    final itemCount = reorderLines.fold<int>(0, (s, e) => s + e.qty);
    final tail = d.id.length > 6 ? d.id.substring(d.id.length - 6) : d.id;
    return _OrderUiModel(
      sourceId: d.id,
      id: '#ORD${tail.toUpperCase()}',
      itemCount: itemCount <= 0 ? reorderLines.length : itemCount,
      placedAt: _placedAtLabel(dt),
      statusRaw: statusRaw,
      statusLine: _statusLineFromRaw(statusRaw),
      status: status,
      price: '₹$total',
      actionLabel: 'Reorder',
      reorderLines: reorderLines,
      canRate: status == _OrderUiStatus.delivered,
      deliveryLine: deliveryLine,
      paymentMode: paymentMode,
    );
  }

  void _reorder(_OrderUiModel order) {
    if (order.reorderLines.isEmpty) return;
    final next = List<CartLineItem>.from(widget.cartLinesNotifier.value);
    for (final item in order.reorderLines) {
      final idx = next.indexWhere(
        (e) => e.name == item.name && e.subtitle == item.subtitle,
      );
      if (idx >= 0) {
        next[idx] = next[idx].copyWith(qty: next[idx].qty + item.qty);
      } else {
        next.add(item);
      }
    }
    widget.cartLinesNotifier.value = next;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Items added back to cart.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<void> _cancelOrder(_OrderUiModel order) async {
    final isOnline = order.paymentMode.trim().toLowerCase() != 'cash_on_delivery';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancel this order?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          isOnline
              ? 'Order ${order.id} will be cancelled. If you paid online, our '
                  'team will process your refund — this may take a few days.'
              : 'Order ${order.id} will be cancelled. This cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep order',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel order',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('cancelOrder');
      await callable.call({'orderId': order.sourceId});
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order ${order.id} cancelled.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'Could not cancel this order.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not cancel this order. Please try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    }
  }

  Future<void> _rateOrder(_OrderUiModel order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    final result = await showDialog<({int rating, String review})>(
      context: context,
      builder: (dialogContext) => const _RateOrderDialog(),
    );
    if (result == null || !mounted) return;

    await chechiFirestore.collection('order_reviews').add({
      'uid': user.uid,
      'order_id': order.sourceId,
      'rating': result.rating,
      'review': result.review,
      'created_at': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Thank you! Your review is submitted.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<void> _showInvoice(_OrderUiModel order) async {
    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final issued =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final itemTotal = order.reorderLines.fold<int>(
      0,
      (acc, line) => acc + line.price * line.qty,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final titleColor = _OrdersPalette.titleOf(ctx);
        final muted = _OrdersPalette.mutedOf(ctx);
        final border = _OrdersPalette.cardBorderOf(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: _OrdersPalette.cardFillOf(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border.all(color: border),
              ),
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: muted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Chechi Puttu Kadai',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    'Tax Invoice / Bill Summary',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _orderInvoiceRow(ctx, 'Invoice Date', issued),
                  _orderInvoiceRow(ctx, 'Order Ref', order.id),
                  _orderInvoiceRow(ctx, 'Order Date', order.placedAt),
                  _orderInvoiceRow(ctx, 'Status', order.statusLine),
                  if (user?.phoneNumber?.trim().isNotEmpty ?? false)
                    _orderInvoiceRow(ctx, 'Mobile', user!.phoneNumber!.trim()),
                  const SizedBox(height: 12),
                  Text(
                    'Items',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...order.reorderLines.map((line) {
                    final lineTotal = line.price * line.qty;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _OrdersPalette.pageBgOf(ctx),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                ),
                                if (line.subtitle.trim().isNotEmpty)
                                  Text(
                                    line.subtitle,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      color: muted,
                                    ),
                                  ),
                                Text(
                                  'Qty: ${line.qty}  ×  ₹${line.price}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₹$lineTotal',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  _orderInvoiceRow(
                    ctx,
                    'Delivery',
                    order.deliveryLine.isEmpty ? '—' : order.deliveryLine,
                  ),
                  _orderInvoiceRow(
                    ctx,
                    'Payment',
                    order.paymentMode.replaceAll('_', ' '),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Total Amount',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          itemTotal > 0 ? '₹$itemTotal' : order.price,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This is a system-generated invoice summary for your order.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      height: 1.35,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Close',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -8,
          top: -4,
          width: MediaQuery.sizeOf(context).width * 0.52,
          height: 200,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OrdersWatermarkPainter(
                lineColor: Color(0xFF8D6E63).withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.12
                      : 0.07,
                ),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: widget.onMenu,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.menu_rounded,
                        size: 26,
                        color: _OrdersPalette.titleOf(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _RoundThemeToggle(
                    isDark: widget.isDark,
                    onToggle: widget.onToggleTheme,
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: widget.onCartTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ListenableBuilder(
                        listenable: widget.cartLinesNotifier,
                        builder: (context, _) {
                          final cartCount = _cartBadgeTotal(
                            widget.cartLinesNotifier.value,
                          );
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 24,
                                color: _OrdersPalette.titleOf(context),
                              ),
                              if (cartCount > 0)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE53935),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _OrdersPalette.pageBgOf(context),
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$cartCount',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Orders',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: _OrdersPalette.titleOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Track and manage your orders',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: _OrdersPalette.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _OrdersFilterRow(selected: _filter, onChanged: _setFilter),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AppPullToRefresh(
                onRefresh: widget.onRefresh,
                child: Builder(
                  builder: (context) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      return ListView(
                        physics: AppPullToRefresh.scrollPhysics,
                        children: const [SizedBox(height: 120)],
                      );
                    }
                    final stream = _ordersStream ??= chechiFirestore
                        .collection('orders')
                        .where('uid', isEqualTo: user.uid)
                        .limit(120)
                        .snapshots();
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (context, snap) {
                      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                        snap.data?.docs ?? const [],
                      )..sort((a, b) {
                        final ta = a.data()['created_at'];
                        final tb = b.data()['created_at'];
                        final da = ta is Timestamp ? ta.toDate() : DateTime(2000);
                        final db = tb is Timestamp ? tb.toDate() : DateTime(2000);
                        return db.compareTo(da);
                      });
                      final all = docs
                          .map(_orderUiFromDoc)
                          .toList();
                      final visible = _visibleFrom(all);
                      if (visible.isEmpty) {
                        return ListView(
                          physics: AppPullToRefresh.scrollPhysics,
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.35,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    32,
                                    0,
                                    32,
                                    24,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_outlined,
                                  size: 52,
                                  color: _OrdersPalette.mutedOf(
                                    context,
                                  ).withValues(alpha: 0.55),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No orders yet',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _OrdersPalette.titleOf(context),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'When you place an order from the cart, it will appear here.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                    color: _OrdersPalette.mutedOf(context),
                                  ),
                                ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return ListView.separated(
                        physics: AppPullToRefresh.scrollPhysics,
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _OrderListCard(
                          order: visible[i],
                          onReorder: () => _reorder(visible[i]),
                          onRate: visible[i].canRate
                              ? () => _rateOrder(visible[i])
                              : null,
                          onInvoice: () => _showInvoice(visible[i]),
                          onCancel: visible[i].canCancel
                              ? () => _cancelOrder(visible[i])
                              : null,
                        ),
                      );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OrdersWatermarkPainter extends CustomPainter {
  _OrdersWatermarkPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    void curve(Offset a, Offset b, Offset c) {
      final path = Path()..moveTo(a.dx, a.dy);
      path.quadraticBezierTo(b.dx, b.dy, c.dx, c.dy);
      canvas.drawPath(path, p);
    }

    final w = size.width;
    final h = size.height;
    curve(
      Offset(w * 0.05, h * 0.25),
      Offset(w * 0.42, h * 0.05),
      Offset(w * 0.92, h * 0.2),
    );
    curve(
      Offset(w * 0.12, h * 0.55),
      Offset(w * 0.48, h * 0.38),
      Offset(w * 0.88, h * 0.52),
    );
    curve(
      Offset(w * 0.18, h * 0.88),
      Offset(w * 0.52, h * 0.72),
      Offset(w * 0.9, h * 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _OrdersWatermarkPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}

class _OrdersFilterRow extends StatelessWidget {
  const _OrdersFilterRow({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const _labels = ['All Orders', 'Ongoing', 'Delivered', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _OrdersPalette.pageBgOf(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _OrdersPalette.filterBorderOf(context)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 26,
                color: _OrdersPalette.dividerOf(context),
              ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected == i
                          ? _OrdersPalette.filterSelectedBgOf(context)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: i == 0 ? 11 : 11,
                        fontWeight: FontWeight.w600,
                        color: selected == i
                            ? Colors.white
                            : _OrdersPalette.titleOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderListCard extends StatelessWidget {
  const _OrderListCard({
    required this.order,
    this.onReorder,
    this.onRate,
    this.onInvoice,
    this.onCancel,
  });

  final _OrderUiModel order;
  final VoidCallback? onReorder;
  final VoidCallback? onRate;
  final VoidCallback? onInvoice;
  final VoidCallback? onCancel;

  (Color bg, Color fg) get _badgeColors {
    switch (order.status) {
      case _OrderUiStatus.delivered:
        return (_OrdersPalette.deliveredBg, _OrdersPalette.deliveredFg);
      case _OrderUiStatus.ongoing:
        return (_OrdersPalette.ongoingBg, _OrdersPalette.ongoingFg);
      case _OrderUiStatus.cancelled:
        return (_OrdersPalette.cancelledBg, _OrdersPalette.cancelledFg);
    }
  }

  String get _badgeText {
    final s = order.statusRaw.trim().toLowerCase();
    switch (order.status) {
      case _OrderUiStatus.delivered:
        return s == 'completed' ? 'Completed' : 'Delivered';
      case _OrderUiStatus.ongoing:
        switch (s) {
          case 'ready':
            return 'Ready';
          case 'preparing':
          case 'accepted':
            return 'Preparing';
          case 'out_for_delivery':
            return 'On the way';
          case 'placed':
          case 'new':
          case '':
            return 'Placed';
          default:
            return 'Ongoing';
        }
      case _OrderUiStatus.cancelled:
        return 'Cancelled';
    }
  }

  (IconData icon, Color color) get _statusIcon {
    switch (order.status) {
      case _OrderUiStatus.delivered:
        return (Icons.check_circle_rounded, _OrdersPalette.deliveredIcon);
      case _OrderUiStatus.ongoing:
        return (Icons.restaurant_rounded, _OrdersPalette.ongoingIcon);
      case _OrderUiStatus.cancelled:
        return (Icons.cancel_rounded, _OrdersPalette.cancelledIcon);
    }
  }

  int get _timelineStep => _orderTimelineStepFromRaw(order.statusRaw);

  @override
  Widget build(BuildContext context) {
    final badge = _badgeColors;
    final st = _statusIcon;
    final showTimeline = order.status != _OrderUiStatus.cancelled;
    final muted = _OrdersPalette.mutedOf(context);
    final titleColor = _OrdersPalette.titleOf(context);

    OutlinedButton compactBtn({
      required VoidCallback? onPressed,
      required String label,
      required Color fg,
    }) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: fg, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Material(
      color: _OrdersPalette.cardFillOf(context),
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _OrdersPalette.cardBorderOf(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.id,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          height: 1.1,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badge.$1,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _badgeText,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: badge.$2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${order.itemCount} items • ${order.placedAt}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(st.$1, size: 13, color: st.$2),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        order.statusLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (showTimeline) ...[
                  const SizedBox(height: 6),
                  _OrderTimelineMini(currentStep: _timelineStep),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      order.price,
                      style: GoogleFonts.poppins(
                        fontSize: 19,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFE65100),
                      ),
                    ),
                    const Spacer(),
                    compactBtn(
                      onPressed: onReorder,
                      label: order.actionLabel,
                      fg: titleColor,
                    ),
                    if (onRate != null) ...[
                      const SizedBox(width: 6),
                      compactBtn(
                        onPressed: onRate,
                        label: 'Rate',
                        fg: const Color(0xFFEA7A2C),
                      ),
                    ],
                    if (onInvoice != null) ...[
                      const SizedBox(width: 6),
                      compactBtn(
                        onPressed: onInvoice,
                        label: 'Invoice',
                        fg: const Color(0xFF1F5AA0),
                      ),
                    ],
                    if (onCancel != null) ...[
                      const SizedBox(width: 6),
                      compactBtn(
                        onPressed: onCancel,
                        label: 'Cancel',
                        fg: const Color(0xFFB3261E),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderTimelineMini extends StatelessWidget {
  const _OrderTimelineMini({required this.currentStep});

  final int currentStep;

  static const _labels = ['Placed', 'Preparing', 'Ready', 'Done'];

  @override
  Widget build(BuildContext context) {
    final muted = _OrdersPalette.mutedOf(context);
    final done = const Color(0xFF2E7D32);
    return Row(
      children: List.generate(_labels.length, (i) {
        final complete = i <= currentStep;
        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: complete ? done : muted.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 3),
              Text(
                _labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: complete ? FontWeight.w700 : FontWeight.w500,
                  color: complete ? done : muted,
                  height: 1.1,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _MenuVarietyDetailScreen extends StatelessWidget {
  const _MenuVarietyDetailScreen({
    required this.section,
    required this.sectionId,
    required this.cartLinesNotifier,
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenCartTab,
  });

  final MenuCatalogSection section;
  final String sectionId;
  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenCartTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _Theme.text(context),
          ),
        ),
        title: Text(
          section.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _Theme.text(context),
          ),
        ),
        actions: [
          _RoundThemeToggle(isDark: isDark, onToggle: onToggleTheme),
          const SizedBox(width: 4),
          ListenableBuilder(
            listenable: cartLinesNotifier,
            builder: (context, _) {
              final n = _cartBadgeTotal(cartLinesNotifier.value);
              return IconButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpenCartTab();
                },
                icon: Badge(
                  isLabelVisible: n > 0,
                  label: Text(
                    '$n',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  child: Icon(
                    Icons.shopping_cart_outlined,
                    color: _Theme.text(context),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          cartLinesNotifier,
          CustomerMenuOverrides.instance,
          CustomerMenuSectionOverrides.instance,
          MenuDeletedDishes.instance,
        ]),
        builder: (context, _) {
          final lines = cartLinesNotifier.value;
          final visible = section.dishes
              .where(
                (d) => !MenuDeletedDishes.instance.isDeleted(
                  sectionId,
                  d.title,
                ),
              )
              .toList();
          return AppPullToRefresh(
            onRefresh: () async {
              await AppRefresh.refreshMenuData();
            },
            child: CustomScrollView(
              physics: AppPullToRefresh.scrollPhysics,
              slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    section.subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: _Theme.muted(context),
                    ),
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No dishes in this category right now.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _Theme.muted(context),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final d = visible[index];
                      final m = mergeWithCatalog(
                        d,
                        CustomerMenuOverrides.instance.snapshotFor(
                          sectionId,
                          d.title,
                        ),
                      );
                      return _ProductCard(
                        badge: m.badge,
                        title: m.title,
                        subtitle: m.subtitle,
                        price: m.price,
                        imageBase64: m.imageBase64,
                        available: m.available,
                        qty: _cartQtyForDish(lines, m.title, m.subtitle),
                        onAdd: () => _cartAddDishLine(
                          cartLinesNotifier,
                          m.title,
                          m.subtitle,
                          m.price,
                          m.imageBase64,
                        ),
                        onRemove: () => _cartRemoveDishLine(
                          cartLinesNotifier,
                          m.title,
                          m.subtitle,
                        ),
                        width: null, // let the grid control width
                        margin: EdgeInsets.zero, // no extra gap between columns
                      );
                    }, childCount: visible.length),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({
    required this.cartLinesNotifier,
    required this.onMenu,
    required this.onCartTap,
    required this.onOpenCartTab,
    required this.isDark,
    required this.onToggleTheme,
    required this.onRefresh,
  });

  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;
  final VoidCallback onMenu;
  final VoidCallback onCartTap;
  final VoidCallback onOpenCartTab;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -12,
          top: -8,
          width: MediaQuery.sizeOf(context).width * 0.55,
          height: 220,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CategoriesWatermarkPainter(
                lineColor: _CategoriesPalette.titleOf(context).withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.14
                      : 0.045,
                ),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: onMenu,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.menu_rounded,
                        size: 26,
                        color: _CategoriesPalette.titleOf(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _RoundThemeToggle(isDark: isDark, onToggle: onToggleTheme),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onCartTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ListenableBuilder(
                        listenable: cartLinesNotifier,
                        builder: (context, _) {
                          final cartCount = _cartBadgeTotal(
                            cartLinesNotifier.value,
                          );
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 24,
                                color: _CategoriesPalette.titleOf(context),
                              ),
                              if (cartCount > 0)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _CategoriesPalette.accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            _CategoriesPalette.cartBadgeRingOf(
                                              context,
                                            ),
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$cartCount',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discover Our Kitchen',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 27,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: _CategoriesPalette.titleOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Homely Kerala flavours — puttu, curries & sweets made fresh',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: _CategoriesPalette.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const _CategoriesSearchRow(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AppPullToRefresh(
                onRefresh: onRefresh,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    CustomerMenuSectionOverrides.instance,
                    MenuDeletedDishes.instance,
                  ]),
                  builder: (context, _) {
                    final sections = customerMenuSections
                        .asMap()
                        .entries
                        .where((e) {
                          final id = customerMenuSectionIdAt(e.key);
                          return MenuDeletedDishes.instance
                              .sectionHasVisibleDishes(e.value, id);
                        })
                        .map((e) => (index: e.key, section: e.value))
                        .toList();
                    return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Row(
                          children: [
                            Text(
                              'Explore Categories',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _CategoriesPalette.titleOf(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 1.2,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _CategoriesPalette.accent.withValues(
                                        alpha: 0.65,
                                      ),
                                      _CategoriesPalette.accent.withValues(
                                        alpha: 0.06,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: _CategoriesPalette.accent.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                      child: sections.isEmpty // no visible categories
                          ? ListView(
                              physics: AppPullToRefresh.scrollPhysics,
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.35,
                                  child: Center(
                                    child: Text(
                                      'No menu categories yet.',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _CategoriesPalette.mutedOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: AppPullToRefresh.scrollPhysics,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              itemCount: sections.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, listIdx) {
                                final entry = sections[listIdx];
                                final i = entry.index;
                                final sec = entry.section;
                                final sectionId = customerMenuSectionIdAt(i);
                                final coverB64 = CustomerMenuSectionOverrides
                                    .instance
                                    .sectionOverrideFor(sectionId)
                                    ?.imageBase64;
                                final fallbackAsset =
                                    menuSectionFallbackAsset(sectionId);
                                return SizedBox(
                                  height: 100,
                                  child: _CategoryGridCard(
                                    title: sec.title,
                                    subtitle: sec.subtitle,
                                    imageBase64: coverB64,
                                    imageAsset: fallbackAsset,
                                    onOpen: () {
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (ctx) =>
                                              _MenuVarietyDetailScreen(
                                            section: sec,
                                            sectionId: sectionId,
                                            cartLinesNotifier:
                                                cartLinesNotifier,
                                            isDark: isDark,
                                            onToggleTheme: onToggleTheme,
                                            onOpenCartTab: onOpenCartTab,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                      ),
                    ],
                  );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoriesWatermarkPainter extends CustomPainter {
  _CategoriesWatermarkPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    void curve(Offset a, Offset b, Offset c) {
      final path = Path()..moveTo(a.dx, a.dy);
      path.quadraticBezierTo(b.dx, b.dy, c.dx, c.dy);
      canvas.drawPath(path, p);
    }

    final w = size.width;
    final h = size.height;
    curve(
      Offset(w * 0.1, h * 0.35),
      Offset(w * 0.45, h * 0.08),
      Offset(w * 0.9, h * 0.25),
    );
    curve(
      Offset(w * 0.15, h * 0.55),
      Offset(w * 0.5, h * 0.35),
      Offset(w * 0.85, h * 0.5),
    );
    curve(
      Offset(w * 0.2, h * 0.82),
      Offset(w * 0.55, h * 0.65),
      Offset(w * 0.88, h * 0.88),
    );
  }

  @override
  bool shouldRepaint(covariant _CategoriesWatermarkPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}

class _CategoriesSearchRow extends StatelessWidget {
  const _CategoriesSearchRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _CategoriesPalette.cardFillOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _CategoriesPalette.cardBorderOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 20,
            color: _CategoriesPalette.mutedOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Search for puttu, curry, appam...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: _CategoriesPalette.mutedOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGridCard extends StatelessWidget {
  const _CategoryGridCard({
    required this.title,
    required this.subtitle,
    required this.onOpen,
    this.imageAsset,
    this.imageBase64,
  });

  final String title;
  final String subtitle;
  final VoidCallback onOpen;
  final String? imageAsset;
  final String? imageBase64;

  Widget _buildCardImage() {
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      try {
        final bytes = _MenuBase64ImageCache.read(imageBase64!);
        if (bytes == null) return const SizedBox.shrink();
        return Image.memory(
          bytes,
          key: ValueKey(imageBase64.hashCode),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          cacheWidth: 420,
          cacheHeight: 260,
        );
      } catch (_) {
        // Fall through to asset/placeholder if admin image is malformed.
      }
    }
    if (imageAsset != null) {
      return Image.asset(imageAsset!, fit: BoxFit.cover);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = _CategoriesPalette.titleOf(context);
    final subtitleColor = _CategoriesPalette.mutedOf(context);
    final accent = _CategoriesPalette.accent;
    final border = _CategoriesPalette.cardBorderOf(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? _CategoriesPalette.cardFillOf(context)
                : const Color(0xFFFFFCF8),
            border: Border.all(color: border),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: const Color(0xFF5D1109).withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 84,
                  height: double.infinity,
                  child: ColoredBox(
                    color: const Color(0xFFFFF3EA),
                    child: _buildCardImage(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppMenuTile extends StatelessWidget {
  const _AppMenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: _Theme.primary(context), size: 24),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: _Theme.text(context),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: _Theme.muted(context),
                height: 1.25,
              ),
            ),
      trailing: Icon(Icons.chevron_right_rounded, color: _Theme.muted(context)),
      onTap: onTap,
    );
  }
}

class _TopLocationRow extends StatelessWidget {
  const _TopLocationRow({
    required this.deliveryLine,
    required this.onMenu,
    required this.onLocationTap,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCartTap,
    required this.cartLinesNotifier,
  });

  final String deliveryLine;
  final VoidCallback onMenu;
  final VoidCallback onLocationTap;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onCartTap;
  final ValueNotifier<List<CartLineItem>> cartLinesNotifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onMenu,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.menu_rounded,
              size: 24,
              color: _Theme.text(context),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onLocationTap,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivery address',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _Theme.muted(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: _Theme.text(context),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: _AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          deliveryLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _Theme.text(context),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onCartTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: _Theme.surfaceLow(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _Theme.border(context)),
                ),
                child: ListenableBuilder(
                  listenable: cartLinesNotifier,
                  builder: (context, _) {
                    final cartCount = _cartBadgeTotal(cartLinesNotifier.value);
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 18,
                          color: _Theme.primary(context),
                        ),
                        if (cartCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _Theme.surfaceLow(context),
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                cartCount > 99 ? '99+' : '$cartCount',
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({
    required this.controller,
    required this.hintText,
    required this.onFilter,
    this.filterActive = false,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                height: 38,
                padding: const EdgeInsets.only(left: 4, right: 4),
                decoration: BoxDecoration(
                  color: _kAuthGlassFill,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _kAuthGlassBorder, width: 1.15),
                ),
                child: TextField(
                  controller: controller,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _Theme.text(context),
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: _Theme.primary(context),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: hintText,
                    hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _Theme.muted(context),
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: _Theme.muted(context),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 38,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, val, _) {
                        if (val.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () => controller.clear(),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: _Theme.muted(context),
                          ),
                        );
                      },
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(0, 9, 0, 9),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onFilter,
                child: Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: _AppColors.primary.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: filterActive
                          ? Colors.white.withValues(alpha: 0.9)
                          : _kAuthGlassBorder,
                      width: filterActive ? 2 : 1.1,
                    ),
                  ),
                  child: Icon(
                    filterActive ? Icons.filter_alt_rounded : Icons.tune_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel();

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const List<String> _bannerAssets = <String>[
    'assets/images/home_banner_festive_2.png',
  ];

  late final PageController _controller;
  Timer? _autoScrollTimer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 1);
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients || _bannerAssets.length < 2) {
        return;
      }
      final next = (_index + 1) % _bannerAssets.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _Theme.border(context)),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              offset: const Offset(0, 4),
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ],
          color: _Theme.surfaceLow(context),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1536 / 691,
            child: PageView.builder(
              controller: _controller,
              itemCount: _bannerAssets.length,
              onPageChanged: (value) => _index = value,
              itemBuilder: (context, i) => Image.asset(
                _bannerAssets[i],
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _Theme.surfaceLow(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Theme.border(context)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Feature(icon: Icons.eco_outlined, label: '100%\nNatural'),
          _Feature(
            icon: Icons.restaurant_menu_rounded,
            label: 'Authentic\nRecipes',
          ),
          _Feature(
            icon: Icons.water_drop_outlined,
            label: 'No Added\nPreservatives',
          ),
          _Feature(
            icon: Icons.favorite_border_rounded,
            label: 'Made\nwith Love',
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF86D69C)
        : _AppColors.icon;

    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _Theme.text(context),
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? _Theme.text(context) : _AppColors.primary;

    return Row(
      children: [
        Container(
          width: 5,
          height: 20,
          decoration: BoxDecoration(
            color: headerColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.playfairDisplay(
              color: headerColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

IconData _exploreMenuChipIcon(String sectionTitle) {
  switch (sectionTitle) {
    case 'Puttu':
      return Icons.breakfast_dining_rounded;
    case 'Gravies & Curries':
      return Icons.soup_kitchen_outlined;
    case 'Desserts':
      return Icons.icecream_outlined;
    case 'Our Signature Dishes':
      return Icons.star_outline_rounded;
    case 'Combo Offers':
      return Icons.local_offer_rounded;
    default:
      return Icons.rice_bowl_rounded;
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    this.onTap,
    this.margin,
    this.icon,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? _Theme.text(context) : _AppColors.primary;
    return ChechiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: ChechiBrand.fast,
        curve: ChechiBrand.ease,
        margin: margin ?? const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                  ? _AppColors.primary.withValues(alpha: 0.25)
                  : const Color(0xFFFFEFE6))
              : (isDark
                  ? _Theme.surfaceLow(context)
                  : const Color(0xFFFFFCF8)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _AppColors.primary.withValues(alpha: 0.55)
                : _Theme.border(context).withValues(alpha: 0.9),
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  if (!isDark)
                    BoxShadow(
                      color: const Color(0xFF5D1109).withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: selected
                    ? _AppColors.primary.withValues(alpha: 0.12)
                    : const Color(0xFFFFEFE6),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _AppColors.primary.withValues(
                      alpha: selected ? 0.3 : 0.12),
                ),
              ),
              child: Icon(
                icon ?? Icons.rice_bowl_rounded,
                size: 18,
                color: _AppColors.primary,
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  color: accent,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home horizontal dish row — compact premium cards.
const double _kHomeDishCardHeight = 172;

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.badge,
    this.imageBase64,
    this.available = true,
    this.width,
    this.height,
    this.margin,
  });

  final String title;
  final String subtitle;
  final String price;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final String? badge;
  final String? imageBase64;
  final bool available;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? margin;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  void _increment() {
    if (!widget.available) return;
    widget.onAdd();
  }

  void _decrement() {
    if (widget.qty <= 0) return;
    widget.onRemove();
  }

  Widget _buildImageHeader() {
    final b64 = widget.imageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final bytes = _MenuBase64ImageCache.read(b64);
        if (bytes == null) throw const FormatException('bad base64');
        return ColoredBox(
          color: const Color(0xFFF6EFE6),
          child: Image.memory(
            bytes,
            key: ValueKey(b64.hashCode),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            // Width-only decode keeps original aspect ratio (prevents stretch).
            cacheWidth: 720,
            errorBuilder: (_, _, _) => Image.asset(
              'assets/images/hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
      } catch (_) {}
    }
    return ColoredBox(
      color: const Color(0xFFF6EFE6),
      child: Image.asset(
        'assets/images/hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = !widget.available;
    final compactHeight =
        widget.height != null && widget.height! <= _kHomeDishCardHeight + 4;
    final imageRadius = compactHeight ? 11.0 : 12.0;
    // Home cards have a fixed height: let the title wrap to 2 lines (so long
    // names like "Ella Adai (per set 2)" show fully) and give the subtitle 1
    // line so the card height stays identical.
    final titleMaxLines = 2;
    final subtitleMaxLines = compactHeight ? 1 : 2;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        width: widget.width ?? 140,
        height: widget.height,
        margin: widget.margin ?? const EdgeInsets.only(right: 12),
        decoration: ChechiPremium.premiumCard(
          context: context,
          color: _Theme.surfaceLow(context),
          radius: 18,
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, 7, 8, compactHeight ? 4 : 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(imageRadius),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.16 : 0.45,
                        ),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.24 : 0.1,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(imageRadius),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: _buildImageHeader(),
                      ),
                    ),
                  ),
                  SizedBox(height: compactHeight ? 4 : 6),
                  if (widget.height != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: titleMaxLines,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w800,
                                  color: _Theme.text(context),
                                  fontSize: compactHeight ? 12.5 : 13.5,
                                  height: compactHeight ? 1.06 : 1.12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle,
                                maxLines: subtitleMaxLines,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                  color: _Theme.muted(context),
                                  fontWeight: FontWeight.w600,
                                  fontSize: compactHeight ? 9.5 : 10.5,
                                  height: 1.08,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                widget.price,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: isDark
                                          ? _Theme.text(context)
                                          : _AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const Spacer(),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(opacity: anim, child: child),
                                child: widget.qty == 0
                                    ? GestureDetector(
                                        key: const ValueKey('pc-add'),
                                        onTap: disabled ? null : _increment,
                                        child: Container(
                                          height: 26,
                                          width: 26,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: disabled
                                                ? null
                                                : const LinearGradient(
                                                    colors: [
                                                      Color(0xFFC23E2B),
                                                      _AppColors.primary,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                            color: disabled
                                                ? _Theme.muted(context)
                                                : null,
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.45),
                                            ),
                                            boxShadow: disabled
                                                ? const []
                                                : [
                                                    BoxShadow(
                                                      blurRadius: 8,
                                                      offset:
                                                          const Offset(0, 3),
                                                      color: _AppColors.primary
                                                          .withValues(
                                                              alpha: 0.28),
                                                    ),
                                                  ],
                                          ),
                                          child: const Icon(
                                            Icons.add_rounded,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        key: const ValueKey('pc-step'),
                                        height: 26,
                                        decoration: BoxDecoration(
                                          gradient: disabled
                                              ? null
                                              : const LinearGradient(
                                                  colors: [
                                                    Color(0xFFC23E2B),
                                                    _AppColors.primary,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                          color: disabled
                                              ? _Theme.muted(context)
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(13),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.35),
                                          ),
                                          boxShadow: disabled
                                              ? const []
                                              : [
                                                  BoxShadow(
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 3),
                                                    color: _AppColors.primary
                                                        .withValues(alpha: 0.24),
                                                  ),
                                                ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap:
                                                  (!disabled || widget.qty > 0)
                                                      ? _decrement
                                                      : null,
                                              child: const SizedBox(
                                                width: 26,
                                                height: 26,
                                                child: Icon(
                                                  Icons.remove_rounded,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${widget.qty}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: widget.available
                                                  ? _increment
                                                  : null,
                                              child: const SizedBox(
                                                width: 26,
                                                height: 26,
                                                child: Icon(
                                                  Icons.add_rounded,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.title,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _Theme.text(context),
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _Theme.muted(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 10.2,
                            height: 1.15,
                          ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          widget.price,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: isDark
                                        ? _Theme.text(context)
                                        : _AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const Spacer(),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: widget.qty == 0
                              ? GestureDetector(
                                  key: const ValueKey('pc-add'),
                                  onTap: disabled ? null : _increment,
                                  child: Container(
                                    height: 26,
                                    width: 26,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: disabled
                                          ? null
                                          : const LinearGradient(
                                              colors: [
                                                Color(0xFFC23E2B),
                                                _AppColors.primary,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                      color: disabled
                                          ? _Theme.muted(context)
                                          : null,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.45),
                                      ),
                                      boxShadow: disabled
                                          ? const []
                                          : [
                                              BoxShadow(
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                                color: _AppColors.primary.withValues(
                                                  alpha: 0.28,
                                                ),
                                              ),
                                            ],
                                    ),
                                    child: const Icon(
                                      Icons.add_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : Container(
                                  key: const ValueKey('pc-step'),
                                  height: 26,
                                  decoration: BoxDecoration(
                                    gradient: disabled
                                        ? null
                                        : const LinearGradient(
                                            colors: [
                                              Color(0xFFC23E2B),
                                              _AppColors.primary,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                    color: disabled
                                        ? _Theme.muted(context)
                                        : null,
                                    borderRadius: BorderRadius.circular(13),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                    boxShadow: disabled
                                        ? const []
                                        : [
                                            BoxShadow(
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                              color: _AppColors.primary.withValues(
                                                alpha: 0.24,
                                              ),
                                            ),
                                          ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GestureDetector(
                                        onTap: (!disabled || widget.qty > 0)
                                            ? _decrement
                                            : null,
                                        child: const SizedBox(
                                          width: 26,
                                          height: 26,
                                          child: Icon(
                                            Icons.remove_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${widget.qty}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: widget.available
                                            ? _increment
                                            : null,
                                        child: const SizedBox(
                                          width: 26,
                                          height: 26,
                                          child: Icon(
                                            Icons.add_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (widget.badge != null)
              Positioned(
                left: 10,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA7A2C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.badge!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (widget.onToggleFavorite != null)
              Positioned(
                right: 10,
                top: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: widget.onToggleFavorite,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        widget.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 15,
                        color: widget.isFavorite
                            ? const Color(0xFFE53935)
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuBase64ImageCache {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static const int _limit = 260;

  static Uint8List? read(String b64) {
    final cached = _cache[b64];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(b64);
      if (_cache.length >= _limit) {
        _cache.remove(_cache.keys.first);
      }
      _cache[b64] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.code, required this.onOrderNow});

  final String code;
  final VoidCallback onOrderNow;

  static const _asset = 'assets/images/combo_offers_banner.png';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOrderNow,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            _asset,
            width: double.infinity,
            height: 92,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/offer.png',
              width: double.infinity,
              height: 92,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Birthday Popup ───────────────────────────────

class _BirthdayPopupDialog extends StatefulWidget {
  const _BirthdayPopupDialog({
    required this.firstName,
    required this.onOpenChat,
  });

  final String firstName;
  final VoidCallback onOpenChat;

  @override
  State<_BirthdayPopupDialog> createState() => _BirthdayPopupDialogState();
}

class _BirthdayPopupDialogState extends State<_BirthdayPopupDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.firstName.trim().isEmpty ? 'there' : widget.firstName;
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF8F0), Color(0xFFFFEDF5)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE85D3F).withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Decorative circles
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFD6C2).withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -30,
                  left: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFB6C1).withValues(alpha: 0.4),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎂', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 12),
                      Text(
                        '🎉 Happy Birthday!',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF5D1F1A),
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE85D3F),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Warm wishes from everyone at\nChechi Puttu Kadai 🌸\n\nMay your day be filled with joy,\nlove & delicious homestyle food!',
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF7A5C58),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onOpenChat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE85D3F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'See your birthday message 🎁',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Close',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: const Color(0xFF9E7E78),
                          ),
                        ),
                      ),
                    ],
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

// ─────────────────────────── Bottom Nav Bar ───────────────────────────────

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.index,
    required this.onChanged,
    required this.onChat,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final inactiveColor = dark
        ? theme.colorScheme.onSurfaceVariant
        : const Color(0xFF8B756E);
    final warmSelected = dark
        ? const Color(0xFFFFB28F)
        : const Color(0xFFE85D3F);
    final profileSelected = dark
        ? const Color(0xFFFFB28F)
        : const Color(0xFFE65100);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottomInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: AnimatedContainer(
            duration: ChechiBrand.fast,
            curve: ChechiBrand.ease,
            height: 62,
              decoration: BoxDecoration(
                color: dark
                    ? Colors.black.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.90),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.35 : 0.10),
                    blurRadius: 32,
                    offset: const Offset(0, 6),
                  ),
                  if (!dark)
                    BoxShadow(
                      color: const Color(0xFF7C1D1B).withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _NavPillItem(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      selected: index == 0,
                      onTap: () => onChanged(0),
                      activeColor: dark
                          ? theme.colorScheme.primaryContainer
                          : const Color(0xFFFFEEE7),
                      activeTextColor: dark
                          ? theme.colorScheme.onPrimaryContainer
                          : const Color(0xFF5D1F1A),
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _NavPillItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Orders',
                      selected: index == 2,
                      onTap: () => onChanged(2),
                      activeColor: dark
                          ? theme.colorScheme.primaryContainer
                          : const Color(0xFFFFEEE7),
                      activeTextColor: dark
                          ? theme.colorScheme.onPrimaryContainer
                          : warmSelected,
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _NavPillItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Chat',
                      selected: index == 4,
                      onTap: () => onChanged(4),
                      activeColor: dark
                          ? theme.colorScheme.primaryContainer
                          : const Color(0xFFFFEEE7),
                      activeTextColor: dark
                          ? theme.colorScheme.onPrimaryContainer
                          : warmSelected,
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _NavPillItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Profile',
                      selected: index == 3,
                      onTap: () => onChanged(3),
                      activeColor: dark
                          ? theme.colorScheme.primaryContainer
                          : const Color(0xFFFFEEE7),
                      activeTextColor: dark
                          ? theme.colorScheme.onPrimaryContainer
                          : profileSelected,
                      inactiveColor: inactiveColor,
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

class _NavPillItem extends StatelessWidget {
  const _NavPillItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.activeColor,
    required this.activeTextColor,
    required this.inactiveColor,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;
  final Color activeTextColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? activeTextColor : inactiveColor;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: GoogleFonts.poppins(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 9.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppColors {
  /// Fallback under full-bleed art (light mode); matches illustration cream.
  static const appBackdrop = Color(0xFFFFF6ED);
  static const border = Color(0xFFE4D7C7);
  static const primary = Color(0xFF7C1D1B);
  static const icon = Color(0xFF2E7D32);
}




