/**
 * Grant Firebase Auth custom claim { admin: true } to the Chechi admin account.
 * Run after rules deploy if admin dashboard shows permission-denied.
 *
 *   cd D:\chechi-puttu\functions
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="D:\chechi-puttu\chechi-puttu-kadai-firebase-adminsdk-fbsvc-5369e3b5d9.json"
 *   node ..\scripts\set_admin_claim.cjs
 */

const path = require("path");
const fs = require("fs");

const admin = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "firebase-admin",
));

const ADMIN_EMAIL = "chechiputtukadai@gmail.com";
const ADMIN_PHONE_E164 = "+917358888437";

const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credPath || !fs.existsSync(credPath)) {
  console.error("Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON.");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(credPath)),
});

async function main() {
  const auth = admin.auth();
  let user;
  try {
    user = await auth.getUserByEmail(ADMIN_EMAIL);
    console.log("Found admin by email:", user.uid);
  } catch (_) {
    const res = await auth.listUsers(1000);
    user = res.users.find((u) => u.phoneNumber === ADMIN_PHONE_E164);
    if (!user) {
      throw new Error(
        `No admin user for ${ADMIN_EMAIL} or ${ADMIN_PHONE_E164}. Run npm run reset-firebase first.`,
      );
    }
    console.log("Found admin by phone:", user.uid);
  }

  await auth.setCustomUserClaims(user.uid, { admin: true });
  console.log("Admin claim set. Sign out of the app and sign in again.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
