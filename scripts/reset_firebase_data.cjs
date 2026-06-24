/**
 * One-time reset: delete all Firebase Auth users + customer Firestore data,
 * then create the new admin email account.
 *
 * Run from functions folder (uses firebase-admin dependency):
 *
 *   cd D:\chechi-puttu\functions
 *   npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="D:\chechi-puttu\firebase-service-account.json"
 *   $env:ADMIN_PASSWORD="ChechiPuttu@7358"
 *   node ..\scripts\reset_firebase_data.cjs
 */

const path = require("path");

// firebase-admin is installed under functions/ — resolve it explicitly.
const admin = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "firebase-admin",
));

const ADMIN_EMAIL = "chechiputtukadai@gmail.com";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "ChechiPuttu@7358";

const USER_DATA_COLLECTIONS = [
  "users",
  "orders",
  "order_reviews",
  "push_tokens",
  "checkout_sessions",
  "rzp_order_map",
  "support_inbox",
];

const fs = require("fs");
const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credPath || !fs.existsSync(credPath)) {
  console.error(
    "Service account JSON not found.\n\n" +
      "1. Firebase Console → chechi-puttu-kadai → Project settings → Service accounts\n" +
      "2. Click 'Generate new private key' → save the downloaded .json file\n" +
      "3. PowerShell (use your real path):\n" +
      '   $env:GOOGLE_APPLICATION_CREDENTIALS="D:\\chechi-puttu\\chechi-puttu-kadai-firebase-adminsdk-xxxxx.json"\n' +
      "   npm run reset-firebase\n",
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(credPath)),
});
const { getFirestore } = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "firebase-admin",
  "firestore",
));
/** asia-south1 — Console database name `default` (not (default)/nam5). */
const db = getFirestore(undefined, "default");
const auth = admin.auth();

async function deleteAllAuthUsers() {
  let pageToken;
  let total = 0;
  do {
    const res = await auth.listUsers(1000, pageToken);
    const uids = res.users.map((u) => u.uid);
    if (uids.length > 0) {
      await auth.deleteUsers(uids);
      total += uids.length;
      console.log(`Deleted ${uids.length} auth users (${total} total)`);
    }
    pageToken = res.pageToken;
  } while (pageToken);
}

async function deleteCollection(colRef) {
  const snap = await colRef.limit(400).get();
  if (snap.empty) return;

  for (const doc of snap.docs) {
    const subcols = await doc.ref.listCollections();
    for (const sub of subcols) {
      await deleteCollection(sub);
    }
  }

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  await deleteCollection(colRef);
}

async function wipeUserFirestore() {
  for (const name of USER_DATA_COLLECTIONS) {
    console.log(`Wiping Firestore/${name}...`);
    await deleteCollection(db.collection(name));
    console.log(`  done: ${name}`);
  }
}

async function setAdminCustomClaim(user) {
  await auth.setCustomUserClaims(user.uid, { admin: true });
  console.log(`Set admin custom claim on uid ${user.uid}`);
}

async function createAdminEmailUser() {
  let user;
  try {
    user = await auth.createUser({
      email: ADMIN_EMAIL,
      password: ADMIN_PASSWORD,
      emailVerified: true,
      displayName: "Chechi Puttu Admin",
    });
    console.log(`Created admin email user: ${user.uid}`);
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      console.log("Admin email exists — updating password.");
      user = await auth.getUserByEmail(ADMIN_EMAIL);
      await auth.updateUser(user.uid, {
        password: ADMIN_PASSWORD,
        emailVerified: true,
      });
    } else {
      throw e;
    }
  }
  await setAdminCustomClaim(user);
  return user;
}

async function main() {
  console.log("=== Chechi Puttu Firebase reset ===\n");
  console.log("Admin email:", ADMIN_EMAIL);
  console.log("Admin phone OTP: 7358888437 (+917358888437)\n");

  console.log("Using credentials:", credPath);
  console.log("\n1) Deleting all Firebase Auth users...");
  await deleteAllAuthUsers();

  console.log("\n2) Wiping customer Firestore (keeping admin_public menu)...");
  try {
    await wipeUserFirestore();
  } catch (e) {
    console.warn(
      "\nFirestore wipe skipped:",
      e.message || e,
      "\nEnable billing (Blaze) at:\n" +
        "https://console.developers.google.com/billing/enable?project=chechi-puttu-kadai\n" +
        "Or delete collections manually in Firebase Console → Firestore.\n",
    );
  }

  console.log("\n3) Creating admin email account...");
  await createAdminEmailUser();

  console.log("\nDone. Deploy rules: firebase deploy --only firestore:rules");
  console.log("Default password:", ADMIN_PASSWORD);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
