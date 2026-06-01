# Publish Chechi Puttu Kadai on Google Play

## 1. Create app (Play Console — your current screen)

| Field | Value |
|-------|--------|
| **App name** | `Chechi Puttu Kadai` (or `chechi puttu kadai`) |
| **Package name** | `com.example.chechiputtuapp` |
| **Default language** | English (United States) |

Tap **Check availability** — the package must be free and must **exactly match** the app ID in `android/app/build.gradle.kts`.

**Important:** The package name **cannot be changed** after you create the app. It is already set in Firebase (`google-services.json`).

---

## 2. Google Play Developer account

- Pay the **one-time $25** registration fee (if not done).
- Complete **identity** and **developer profile**.

---

## 3. Release signing (required for production)

Play Store does **not** accept debug-signed builds on Production.

### Create upload keystore (once, on your PC)

```bash
keytool -genkey -pair -v -keystore chechi-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias chechi
```

Store the `.jks` file and passwords safely (password manager). **If you lose it, you cannot update the app.**

### Register signing in Codemagic (recommended)

1. Codemagic → your app → **Team settings** → **Code signing identities** → Android.
2. Upload the keystore or let Codemagic generate one.
3. In the Android workflow, enable **Android code signing**.

### Add SHA fingerprints to Firebase (phone login / Google Sign-In)

After you have the upload certificate:

```bash
keytool -list -v -keystore chechi-upload-keystore.jks -alias chechi
```

Copy **SHA-1** and **SHA-256** → [Firebase Console](https://console.firebase.google.com) → Project → Project settings → Your apps → Android `com.example.chechiputtuapp` → Add fingerprint.

Also add Play App Signing certificate SHA (from Play Console → Setup → App integrity) after first upload.

---

## 4. Build for Play Store (AAB, not APK)

Google Play requires **Android App Bundle** (`.aab`) for new apps:

```bash
cd chechi_puttu_app
flutter build appbundle --release --no-tree-shake-icons
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Or download **`app-release.aab`** from Codemagic after the Android workflow runs (if AAB step is enabled).

---

## 5. Store listing checklist

In Play Console → **Main store listing**:

- **Short description** (80 chars)
- **Full description** (4000 chars)
- **App icon** 512×512 PNG
- **Feature graphic** 1024×500
- **Phone screenshots** — at least 2 (1080×1920 or similar)

---

## 6. Required policies & forms

| Item | Notes |
|------|--------|
| **Privacy policy URL** | Public HTTPS link (required for location, phone, Firebase) |
| **Data safety** | Declare location, phone number, purchases, Firebase |
| **Content rating** | Complete questionnaire (food app, no adult content) |
| **Target audience** | Set age groups |
| **News app / COVID** | Usually “No” for food delivery |

---

## 7. Upload release

1. Play Console → **Testing** → **Internal testing** (fastest first test) or **Production**.
2. **Create new release** → Upload `app-release.aab`.
3. Add **release notes**.
4. **Review and roll out**.

Start with **Internal testing** (up to 100 testers) before Production.

---

## 8. App content that may need review

- **Food ordering** — declare payments (Razorpay / COD).
- **Location** — explain delivery address in Data safety.
- **Admin features** — same APK; ensure store description is for **customers**.

---

## Quick reference

- Package name: `com.example.chechiputtuapp`
- App label on device: `Chechi Puttu`
- Current version: `1.0.0+1` in `pubspec.yaml` (bump `+1` for each Play upload)
