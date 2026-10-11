/**
 * Flip the admin-side payment gate (Firestore app_access/status).
 *
 *   cd functions
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="<path to service account json>"
 *   node ..\scripts\set_app_access.cjs ok
 *   node ..\scripts\set_app_access.cjs reminder --amount 15000 --contact "+91 ..." --message "..."
 *   node ..\scripts\set_app_access.cjs locked   --amount 15000 --contact "+91 ..."
 *
 * Only the service account can write this document; Firestore rules refuse
 * every client. Customers are never affected — only admin/staff screens.
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const [state, ...rest] = process.argv.slice(2);
if (!["ok", "reminder", "locked"].includes(state)) {
  console.error("Usage: set_app_access.cjs <ok|reminder|locked> [--amount N] [--contact TEXT] [--message TEXT]");
  process.exit(1);
}
const opt = (name) => {
  const i = rest.indexOf(`--${name}`);
  return i >= 0 ? rest[i + 1] : undefined;
};

admin.initializeApp({ projectId: "chechi-puttu-kadai" });
const db = admin.firestore();
db.settings({ databaseId: "default" });

const data = { state, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
if (opt("amount")) data.amountDue = Number(opt("amount"));
if (opt("contact")) data.contact = opt("contact");
if (opt("message")) data.message = opt("message");

db.collection("app_access").doc("status").set(data).then(
  () => { console.log(`app_access/status -> ${state}`); process.exit(0); },
  (e) => { console.error(e); process.exit(1); },
);
