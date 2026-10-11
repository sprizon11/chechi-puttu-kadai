import 'dart:async';

import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Remote switch for the admin side of the app, held in `app_access/status`.
///
/// The document can only be written with the service account (see
/// `scripts/set_app_access.cjs`) — Firestore rules refuse every client write —
/// so the shop owner cannot flip it back from inside the app.
///
///   state: 'ok'       normal
///   state: 'reminder' admin works, a banner asks for the pending payment
///   state: 'locked'   admin screens are replaced by [AppAccessLockedScreen]
///
/// Customers are never affected: only the admin dashboard is wrapped.
enum AppAccessState { ok, reminder, locked }

class AppAccess {
  const AppAccess({
    this.state = AppAccessState.ok,
    this.message = '',
    this.contact = '',
    this.amountDue,
  });

  static const ok = AppAccess();

  final AppAccessState state;
  final String message;
  final String contact;
  final num? amountDue;

  static const defaultMessage =
      'The final payment for this app is still pending. Please clear the '
      'balance with Hephora Tech to continue using the admin panel.';

  String get shownMessage => message.trim().isEmpty ? defaultMessage : message.trim();

  factory AppAccess.fromMap(Map<String, dynamic>? data) {
    if (data == null) return ok;
    final state = switch ((data['state'] as String?)?.trim().toLowerCase()) {
      'locked' => AppAccessState.locked,
      'reminder' => AppAccessState.reminder,
      _ => AppAccessState.ok,
    };
    return AppAccess(
      state: state,
      message: (data['message'] as String?) ?? '',
      contact: (data['contact'] as String?) ?? '',
      amountDue: data['amountDue'] as num?,
    );
  }
}

/// Live stream of the access flag. Any error (offline, rules, missing doc)
/// resolves to [AppAccess.ok]: a flaky connection must never lock a shop.
Stream<AppAccess> watchAppAccess() {
  return chechiFirestore
      .collection('app_access')
      .doc('status')
      .snapshots()
      .map((s) => AppAccess.fromMap(s.data()))
      .transform(
        StreamTransformer<AppAccess, AppAccess>.fromHandlers(
          handleError: (e, st, sink) => sink.add(AppAccess.ok),
        ),
      );
}

/// Wraps the admin dashboard. Shows it as normal, with a banner on
/// `reminder`, or the lock screen on `locked`.
class AppAccessGate extends StatelessWidget {
  const AppAccessGate({super.key, required this.child, required this.onSignOut});

  final Widget child;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppAccess>(
      stream: watchAppAccess(),
      initialData: AppAccess.ok,
      builder: (context, snap) {
        final access = snap.data ?? AppAccess.ok;
        switch (access.state) {
          case AppAccessState.locked:
            return AppAccessLockedScreen(access: access, onSignOut: onSignOut);
          case AppAccessState.reminder:
            return Column(
              children: [
                _ReminderBanner(access: access),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: child,
                  ),
                ),
              ],
            );
          case AppAccessState.ok:
            return child;
        }
      },
    );
  }
}

class _ReminderBanner extends StatelessWidget {
  const _ReminderBanner({required this.access});

  final AppAccess access;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFB45309),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  access.shownMessage,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppAccessLockedScreen extends StatelessWidget {
  const AppAccessLockedScreen({
    super.key,
    required this.access,
    required this.onSignOut,
  });

  final AppAccess access;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final due = access.amountDue;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 56, color: Color(0xFF7C1D1B)),
                  const SizedBox(height: 18),
                  Text(
                    'Payment pending',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3B1210),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    access.shownMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                  if (due != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Balance due: ₹${due.toStringAsFixed(due % 1 == 0 ? 0 : 2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF7C1D1B),
                      ),
                    ),
                  ],
                  if (access.contact.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Contact: ${access.contact.trim()}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
