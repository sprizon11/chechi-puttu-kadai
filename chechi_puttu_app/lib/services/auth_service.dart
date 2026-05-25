import 'package:chechi_puttu_app/admin/admin_auth.dart';
import 'package:chechi_puttu_app/app_secrets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';

/// Phone (OTP) + email (staff) + Google via Firebase Auth.
final authService = AuthService();

class AuthSignInResult {
  const AuthSignInResult({required this.user, required this.isNewUser});

  final User user;
  final bool isNewUser;
}

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<AuthSignInResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final trimmed = email.trim();
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: trimmed,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'unknown', message: 'Sign-in failed');
      }
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;
      return AuthSignInResult(
        user: user,
        isNewUser: isNew || _isLikelyBrandNewAccount(user),
      );
    } on FirebaseAuthException catch (e) {
      final isReservedAdmin = trimmed.toLowerCase() == kChechiAdminEmail &&
          password == kChechiAdminPassword;
      if (!isReservedAdmin) rethrow;

      final code = e.code;
      final badCreds = code == 'user-not-found' ||
          code == 'wrong-password' ||
          code == 'invalid-credential' ||
          code == 'invalid-email';
      if (!badCreds) rethrow;

      try {
        final cred = await _auth.createUserWithEmailAndPassword(
          email: trimmed,
          password: password,
        );
        final user = cred.user;
        if (user == null) {
          throw FirebaseAuthException(
            code: 'unknown',
            message: 'Admin account created but could not sign in.',
          );
        }
        return AuthSignInResult(user: user, isNewUser: true);
      } on FirebaseAuthException catch (e2) {
        if (e2.code == 'email-already-in-use') {
          throw FirebaseAuthException(
            code: 'wrong-password',
            message: 'Incorrect password for this account.',
          );
        }
        rethrow;
      }
    }
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final name = displayName?.trim();
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (name != null && name.isNotEmpty && cred.user != null) {
      await cred.user!.updateDisplayName(name);
      await cred.user!.reload();
    }
  }

  /// Links email/password to the signed-in user (e.g. after phone OTP), or
  /// updates password when the account already has the password provider.
  Future<void> attachEmailPasswordForProfile({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Not signed in.',
      );
    }
    final trimmedEmail = email.trim();
    final hasPasswordProvider = user.providerData.any(
      (p) => p.providerId == EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD,
    );
    if (hasPasswordProvider) {
      await user.updatePassword(password);
      return;
    }
    await user.linkWithCredential(
      EmailAuthProvider.credential(
        email: trimmedEmail,
        password: password,
      ),
    );
    await user.reload();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Normalizes to E.164; if no `+`, assumes India (+91) for 10-digit numbers.
  static String normalizePhoneForFirebase(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return t;
    if (t.startsWith('+')) return t;
    final digitsOnly = t.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10) return '+91$digitsOnly';
    if (digitsOnly.length >= 12 && digitsOnly.startsWith('91')) {
      return '+$digitsOnly';
    }
    return '+$digitsOnly';
  }

  /// Sends SMS OTP. [onCodeSent] receives `verificationId` for [signInWithPhoneSms].
  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onVerificationFailed,
    required Future<void> Function(AuthSignInResult result) onAutoSignedIn,
  }) async {
    if (kIsWeb) {
      onVerificationFailed(
        FirebaseAuthException(
          code: 'operation-not-allowed',
          message: 'Phone sign-in runs in the Android/iOS app.',
        ),
      );
      return;
    }
    final formatted = normalizePhoneForFirebase(phoneNumber);
    if (kDebugMode) {
      debugPrint('[FirebaseAuth] verifyPhoneNumber using: $formatted');
    }
    if (formatted.replaceAll(RegExp(r'\D'), '').length < 10) {
      onVerificationFailed(
        FirebaseAuthException(
          code: 'invalid-phone-number',
          message: 'Enter a valid mobile number.',
        ),
      );
      return;
    }

    try {
      await _auth.initializeRecaptchaConfig();
    } catch (_) {}

    await _auth.verifyPhoneNumber(
      phoneNumber: formatted,
      timeout: const Duration(seconds: 90),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final r = await signInWithPhoneCredential(credential);
          await onAutoSignedIn(r);
        } catch (e) {
          if (e is FirebaseAuthException) {
            onVerificationFailed(e);
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (kDebugMode) {
          debugPrint(
            '[FirebaseAuth phone] code=${e.code} message=${e.message}',
          );
        }
        onVerificationFailed(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<AuthSignInResult> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unknown',
        message: 'Phone sign-in failed',
      );
    }
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    return AuthSignInResult(
      user: user,
      isNewUser: isNew || _isLikelyBrandNewAccount(user),
    );
  }

  Future<AuthSignInResult> signInWithPhoneSms({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return signInWithPhoneCredential(credential);
  }

  Future<AuthSignInResult?> signInWithGoogle() async {
    if (kIsWeb) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'Google sign-in on web is not configured. Use phone in the app.',
      );
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'Google Sign-In works on Android, iOS, macOS, and web. '
            'Use phone OTP on this device.',
      );
    }

    final webClientId = AppSecrets.googleWebClientId.trim();
    final iosClientId = AppSecrets.googleIosClientId.trim();
    final needsIosClientId = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final googleConfigured = webClientId.isNotEmpty &&
        !webClientId.contains('REPLACE') &&
        webClientId.contains('.apps.googleusercontent.com');
    final iosConfigured = !needsIosClientId ||
        (iosClientId.isNotEmpty &&
            !iosClientId.contains('REPLACE') &&
            iosClientId.contains('.apps.googleusercontent.com'));

    if (!googleConfigured || !iosConfigured) {
      throw FirebaseAuthException(
        code: 'client-configuration-error',
        message:
            'Set AppSecrets.googleWebClientId and AppSecrets.googleIosClientId '
            'in lib/app_secrets.dart with valid OAuth client IDs.',
      );
    }

    await GoogleSignIn.instance.initialize(
      serverClientId: webClientId,
      clientId: needsIosClientId ? iosClientId : null,
    );

    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final googleAuth = account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Missing Google ID token',
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final cred = await _auth.signInWithCredential(credential);
      final user = cred.user;
      if (user == null) return null;
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;
      return AuthSignInResult(
        user: user,
        isNewUser: isNew || _isLikelyBrandNewGoogleUser(user),
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  Future<void> applyDisplayNameIfNeeded(String? name) async {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final u = _auth.currentUser;
    if (u == null) return;
    if ((u.displayName ?? '').trim() == trimmed) return;
    await u.updateDisplayName(trimmed);
    await u.reload();
  }

  bool _isLikelyBrandNewAccount(User user) {
    final meta = user.metadata.creationTime;
    if (meta == null) return false;
    return DateTime.now().difference(meta).inMinutes < 3;
  }

  bool _isLikelyBrandNewGoogleUser(User user) {
    final meta = user.metadata.creationTime;
    if (meta == null) return false;
    return DateTime.now().difference(meta).inMinutes < 5;
  }
}
