// Google Sign-In on Android: OAuth 2.0 **Web** client ID (same GCP project as Firebase).
// Optional for iOS if you use the same flow.
//
// Do not commit production secrets to a public repo.

abstract final class AppSecrets {
  static const String googleWebClientId =
      '316102307451-8gqjm1eeckudc7eqdluu60ptl2a1tb62.apps.googleusercontent.com';
  static const String googleIosClientId =
      '316102307451-l09t7egsunl83jmp6nk59blj2atp3oqc.apps.googleusercontent.com';
}

/// Meta (Facebook) app events.
///
/// The Android SDK reads the App ID and Client Token from
/// `android/app/src/main/res/values/strings.xml`; this constant exists only so
/// Dart can tell whether the integration has been configured yet. Keep it in
/// step with `facebook_app_id` in that file.
abstract final class MetaConfig {
  static const String appId = '1777958690062898';

  static bool get isConfigured =>
      appId.isNotEmpty && !appId.startsWith('REPLACE_WITH');
}
