import 'package:firebase_auth/firebase_auth.dart';

/// Reserved admin account (Firebase Auth email/password).
const String kChechiAdminEmail = 'sprizon1311@gmail.com';

/// Password for that account (first-time bootstrap from the app).
const String kChechiAdminPassword = 'chechi123';

/// Reserved admin phone — OTP login with this number opens admin dashboard.
const String kChechiAdminPhone = '9994229860';

String normalizeAdminPhone(String raw) {
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

String get kChechiAdminPhoneE164 => normalizeAdminPhone(kChechiAdminPhone);

bool isChechiAdminUser(User? user) {
  if (user == null) return false;
  final e = user.email?.trim().toLowerCase();
  if (e == kChechiAdminEmail) return true;
  final phone = user.phoneNumber?.trim();
  if (phone == null || phone.isEmpty) return false;
  return normalizeAdminPhone(phone) == kChechiAdminPhoneE164;
}
