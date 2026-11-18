import 'dart:async';
import 'dart:io' show Platform;

import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Update the app" prompt, driven by `admin_public/app_update`:
///
/// ```
/// { latest_build: 60, min_build: 0, message: "...", android_url, ios_url }
/// ```
///
/// Build numbers are the part after `+` in pubspec's `version` (1.6.4+60 -> 60),
/// which is also the Play Store version code. A phone on a lower build than
/// `latest_build` is asked to update and may tap "Later"; one lower than
/// `min_build` cannot use the app until it updates. Set from the admin web,
/// Settings -> App update.
class AppUpdateInfo {
  const AppUpdateInfo({
    this.latestBuild = 0,
    this.minBuild = 0,
    this.message = '',
    this.androidUrl = '',
    this.iosUrl = '',
  });

  static const none = AppUpdateInfo();

  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.chechiputtu.kadai';

  static const defaultMessage =
      'A new version of Chechi Puttu is available with important improvements. '
      'Please update to keep ordering smoothly.';

  final int latestBuild;
  final int minBuild;
  final String message;
  final String androidUrl;
  final String iosUrl;

  String get displayMessage =>
      message.trim().isEmpty ? defaultMessage : message.trim();

  /// Where the Update button goes on this phone. Empty means there is nowhere
  /// to send it (e.g. iOS while the app is not on the App Store).
  String storeUrl({required bool isAndroid}) {
    if (isAndroid) {
      return androidUrl.trim().isEmpty ? playStoreUrl : androidUrl.trim();
    }
    return iosUrl.trim();
  }

  /// What this phone, on [currentBuild], should be shown.
  AppUpdateNeed needFor(int currentBuild) {
    if (currentBuild <= 0) return AppUpdateNeed.none;
    if (minBuild > currentBuild) return AppUpdateNeed.required;
    if (latestBuild > currentBuild) return AppUpdateNeed.optional;
    return AppUpdateNeed.none;
  }

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static AppUpdateInfo fromMap(Map<String, dynamic>? data) {
    if (data == null) return none;
    String str(Object? v) => v is String ? v : '';
    return AppUpdateInfo(
      latestBuild: _int(data['latest_build']),
      minBuild: _int(data['min_build']),
      message: str(data['message']),
      androidUrl: str(data['android_url']),
      iosUrl: str(data['ios_url']),
    );
  }
}

enum AppUpdateNeed { none, optional, required }

/// Sits above every screen (from [MaterialApp.builder]) and lays the update
/// prompt over the app when there is one. Built as an overlay rather than a
/// dialog because it lives above the Navigator.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  StreamSubscription<AppUpdateInfo>? _sub;
  AppUpdateInfo _info = AppUpdateInfo.none;
  int _build = 0;

  /// The latest_build the customer tapped "Later" on, for this launch only —
  /// they are asked again next time they open the app.
  int _dismissedBuild = 0;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (kIsWeb) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return; // Unknown build: never nag.
    }
    if (!mounted || _build <= 0) return;
    try {
      _sub = chechiFirestore
          .collection('admin_public')
          .doc('app_update')
          .snapshots()
          .map((s) => AppUpdateInfo.fromMap(s.data()))
          .listen(
            (info) {
              if (mounted) setState(() => _info = info);
            },
            onError: (_) {}, // Offline or no doc: just no prompt.
          );
    } catch (_) {
      // Firebase failed to start; the app shows its own error for that.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _openStore() async {
    final url = _info.storeUrl(isAndroid: _isAndroid);
    if (url.isEmpty) return;
    // Straight into the Play Store app when it is there, browser otherwise.
    if (_isAndroid && url.contains('play.google.com')) {
      final id = Uri.parse(url).queryParameters['id'];
      if (id != null && id.isNotEmpty) {
        final market = Uri.parse('market://details?id=$id');
        try {
          if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
            return;
          }
        } catch (_) {}
      }
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    var need = _info.needFor(_build);
    if (need == AppUpdateNeed.optional &&
        _dismissedBuild >= _info.latestBuild) {
      need = AppUpdateNeed.none;
    }
    // Nowhere to send the customer (iOS without a store link): no prompt.
    if (_info.storeUrl(isAndroid: _isAndroid).isEmpty) {
      need = AppUpdateNeed.none;
    }
    return Stack(
      children: [
        widget.child,
        if (need != AppUpdateNeed.none)
          Positioned.fill(
            child: _UpdatePrompt(
              required: need == AppUpdateNeed.required,
              message: _info.displayMessage,
              onUpdate: _openStore,
              onLater: () =>
                  setState(() => _dismissedBuild = _info.latestBuild),
            ),
          ),
      ],
    );
  }
}

class _UpdatePrompt extends StatelessWidget {
  const _UpdatePrompt({
    required this.required,
    required this.message,
    required this.onUpdate,
    required this.onLater,
  });

  final bool required;
  final String message;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  static const _maroon = Color(0xFF7C1D1B);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(22),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFBEAEA),
                        ),
                        child: const Icon(
                          Icons.system_update_rounded,
                          size: 32,
                          color: _maroon,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        required ? 'Update required' : 'Update available',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Text(
                            message,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              height: 1.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onUpdate,
                        style: FilledButton.styleFrom(
                          backgroundColor: _maroon,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.shop_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        label: Text(
                          'Update now',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (!required) ...[
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: onLater,
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          child: Text(
                            'Later',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
