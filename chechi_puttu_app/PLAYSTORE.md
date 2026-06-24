# Publish Chechi Puttu Kadai on Google Play

## 1. Create app (Play Console — your current screen)

| Field | Value |
|-------|--------|
| **App name** | `Chechi Puttu Kadai` (or `chechi puttu kadai`) |
| **Package name** | `com.chechiputtu.kadai` |
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

```powershell
cd D:\chechi-puttu\chechi_puttu_app\android
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore chechi-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias chechi
```

Create `android/key.properties` (copy from `key.properties.example`) with your passwords.

Store the `.jks` file and passwords safely. **If you lose them, you cannot update the app on Play Store.**

### Add SHA fingerprints to Firebase (phone login / Google Sign-In)

After you have the upload certificate:

```powershell
cd D:\chechi-puttu\chechi_puttu_app\android
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore chechi-upload-keystore.jks -alias chechi
```

Copy **SHA-1** and **SHA-256** → [Firebase Console](https://console.firebase.google.com) → Project → Project settings → Your apps → Android `com.chechiputtu.kadai` → Add fingerprint.

Also add **Play App Signing** certificate SHA (from Play Console → **App integrity**) after first upload.

### Installed from Play Store but phone OTP / Google login fails?

Play re-signs your app. Firebase must have **all** of these for `com.chechiputtu.kadai`:

| Source | Where to copy SHA-1 + SHA-256 |
|--------|--------------------------------|
| **App signing key** (required for Play installs) | Play Console → **Test and release** → **App integrity** → *App signing key certificate* |
| **Upload key** (your `chechi-upload-keystore.jks`) | Same page → *Upload key certificate*, or `gradlew :app:signingReport` → `Variant: release` |
| **Debug** (optional, for `flutter run`) | `signingReport` → `Variant: debug` |

1. [Firebase Console](https://console.firebase.google.com) → Project settings → Android `com.chechiputtu.kadai` → **Add fingerprint** (paste SHA-1 and SHA-256 for each).
2. **Download** `google-services.json` again → replace `android/app/google-services.json`.
3. Wait **5–15 minutes**, then retry login on the **same** installed app (no new Play upload needed).

Error like *“play_integrity_token … no matching SHA-256”* means the **App signing key** SHA-256 is missing in Firebase.

**Google shows “cancelled”** on Play builds often means the Play signing SHA-1 is not registered (fix fingerprints above, then retry).

---

## 4. Build for Play Store (AAB, not APK)

Google Play requires **Android App Bundle** (`.aab`) for new apps:

```powershell
cd D:\chechi-puttu\chechi_puttu_app
flutter build appbundle --release --no-tree-shake-icons
```

Output: `build/app/outputs/bundle/release/app-release.aab`

**You must have `android/key.properties` and the `.jks` file before building.** Without them, the bundle is still signed with the debug key and Play Console will reject it with: *“signed in debug mode”*.

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

### Recommended path to **Production** (real publish)

| Step | Track | Who tests | Goal |
|------|--------|-----------|------|
| 1 | **Internal testing** | You + 1–2 trusted people | Login, admin, menu, orders |
| 2 | **Closed testing** (optional) | 5–20 customers | Real orders, COD, notifications |
| 3 | **Production** | Everyone | Public listing live |

Do **not** skip internal testing on **1.1.0+7** — this build includes Firestore database fix, admin dashboard rules, menu category delete sync, and menu image cloud sync.

---

## 7b. Pre-production test checklist (run on Play-installed build)

Use a phone with the app installed **from Play Console** (not USB debug). Test with **mobile data** and **Wi‑Fi**.

### Install & login

- [ ] App opens without crash
- [ ] **Customer** — phone OTP login works
- [ ] **Customer** — Google sign-in works (if enabled)
- [ ] **Admin** — email `chechiputtukadai@gmail.com` + password opens admin dashboard
- [ ] **Admin** — phone OTP `7358888437` opens admin dashboard
- [ ] Sign out and sign in again (token refresh)

### Customer menu & ordering

- [ ] Home shows categories (Puttu, Gravies, etc.)
- [ ] Menu tab → **Explore Categories** loads
- [ ] Dish details, search, add to cart
- [ ] Place **Cash on Delivery** order — success message / order in **My Orders**
- [ ] Profile edit (name, address) saves

### Admin (after admin login)

- [ ] Dashboard loads (**no** `permission-denied` error)
- [ ] **Menu** — edit dish title/price/image → Save → “synced to cloud” snackbar
- [ ] **Menu** — delete one dish → hidden on customer phone (pull to refresh or reopen app)
- [ ] **Menu** — **Delete category & all dishes** → category gone on admin **and** customer
- [ ] **Orders** tab shows test order
- [ ] **Customers** tab loads
- [ ] **Settings** — theme toggle works

### Push / chat (if used)

- [ ] Notification permission prompt (Android 13+)
- [ ] Customer ↔ admin chat sends/receives

### Before Production rollout

- [ ] Firebase **App signing** SHA-1 + SHA-256 in Firebase (see section 3)
- [ ] `firebase deploy --only firestore:rules` run from `D:\chechi-puttu`
- [ ] Privacy policy URL live in Play Console
- [ ] Data safety + content rating forms **complete**
- [ ] Store listing: icon, feature graphic, ≥2 screenshots, descriptions
- [ ] Release notes written for users

---

## 7c. Build command for this release

```powershell
cd D:\chechi-puttu\chechi_puttu_app
flutter clean
flutter pub get
flutter analyze
flutter build appbundle --release --no-tree-shake-icons
```

Upload: `build\app\outputs\bundle\release\app-release.aab`

**Version for production:** `1.1.0` (versionCode **7**)

Example release notes:

```
• Fixed admin dashboard and menu sync with Firebase
• Menu category delete now hides categories on all customer phones
• Improved login reliability on Play Store builds
• Bug fixes and stability improvements
```

---

## 8. App content that may need review

- **Food ordering** — declare payments (Razorpay / COD).
- **Location** — explain delivery address in Data safety.
- **Admin features** — same APK; ensure store description is for **customers**.

---

## Quick reference

- Package name: `com.chechiputtu.kadai`
- App label on device: `Chechi Puttu`
- Current version: `1.2.1+9` in `pubspec.yaml` (bump `+N` for each Play upload)
