# Admin account & Firebase reset

## New admin (only these open the admin dashboard)

| | Value |
|---|--------|
| **Email** | `chechiputtukadai@gmail.com` |
| **Phone** | `7358888437` (+91) |
| **Default password** (email login, first bootstrap) | `ChechiPuttu@7358` — change in Firebase Console after first sign-in |

Old admin (`sprizon1311@gmail.com` / `9994229860`) no longer works in the app or Firestore rules.

---

## Remove all users & customer data from Firebase

This cannot be done from the phone app. Run the reset script once on your PC.

### 1. Service account key

1. [Firebase Console](https://console.firebase.google.com) → **chechi-puttu-kadai**
2. **Project settings** → **Service accounts** → **Generate new private key**
3. Save in `chechi_puttu_app\` (never commit to git), e.g.  
   `D:\chechi-puttu\chechi_puttu_app\chechi-puttu-kadai-firebase-adminsdk-fbsvc-5369e3b5d9.json`

### 2. Run script

```powershell
cd D:\chechi-puttu\functions
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS="D:\chechi-puttu\chechi_puttu_app\chechi-puttu-kadai-firebase-adminsdk-fbsvc-5369e3b5d9.json"
$env:ADMIN_PASSWORD="ChechiPuttu@7358"
npm run reset-firebase
```

This will:

- Delete **all** Firebase Authentication users
- Delete Firestore: `users`, `orders`, `order_reviews`, `push_tokens`, `checkout_sessions`, `rzp_order_map`, `support_inbox` (and chat messages)
- **Keep** `admin_public` (menu images/text overrides)
- Create email user `chechiputtukadai@gmail.com`

### 3. Deploy Firestore rules

```powershell
cd D:\chechi-puttu
firebase deploy --only firestore:rules
```

### 4. Sign in as admin

- **Email:** `chechiputtukadai@gmail.com` + password  
- **Phone OTP:** `7358888437` (first OTP creates a new phone user — app treats it as admin)

### 5. Play Store testers

Upload a new release (`version` +1 in `pubspec.yaml`) so the installed app has the new admin constants.

---

## Clear data on a single phone only

Settings → Apps → Chechi Puttu → **Storage** → **Clear data** (does not delete Firebase; use the script above for that).
