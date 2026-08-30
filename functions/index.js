const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {initializeFirestore} = require("firebase-admin/firestore");
const Razorpay = require("razorpay");
const {google} = require("googleapis");

const app = admin.initializeApp();
/** asia-south1 database (Console: `default`). Not (default)/nam5. */
const FIRESTORE_DB = "default";
const db = initializeFirestore(app, {preferRest: true}, FIRESTORE_DB);
const ADMIN_EMAIL = "chechiputtukadai@gmail.com";
const ADMIN_PHONE = "+917358888437";

/** Set in Firebase Console → Functions → each function → Runtime env vars, or Secret Manager. */
function razorpayKeys() {
  const keyId = process.env.RAZORPAY_KEY_ID || "";
  const keySecret = process.env.RAZORPAY_KEY_SECRET || "";
  return {keyId, keySecret};
}

function webhookSecret() {
  return process.env.RAZORPAY_WEBHOOK_SECRET || "";
}

const PRICE_BY_KEY = {
  "Rice Puttu|Soft rice & coconut layers": 70,
  "Ragi Puttu|Nutty finger millet favourite": 75,
  "Sorghum (Cholam) Puttu|Golden cholam, homestyle": 85,
  "Wheat Puttu|Soft steamed wheat layers": 85,
  "Chemba Puttu|Red rice puttu, earthy & mild": 85,
  "Rice Semiya Puttu|Fine vermicelli texture": 80,
  "Beetroot Puttu|Naturally sweet, vibrant": 90,
  "Palak Puttu|Spinach goodness in every layer": 95,
  "Carrot Puttu|Mild sweetness, colourful": 90,
  "Millet Puttu|Mixed millet, fibre-rich": 95,
  "Kadala Curry|Black chickpeas in thick gravy": 85,
  "Potato Stew|Creamy potato, coconut milk": 100,
  "Green Peas Curry|Sweet peas & coconut masala": 95,
  "Red Cow Peas Curry|Vanpayar — slow-cooked & hearty": 110,
  "Green Gram Curry|Moong in spiced coconut gravy": 95,
  "Vegetable Kuruma|Mixed veg, mild & fragrant": 90,
  "Tapioca (Kappa)|Seasoned kappa with curry leaves": 75,
  // Desserts and Signature Dishes are managed via admin panel in Firestore.
  // Their prices are resolved at order time via loadFirestoreMenuPrices() below.
};

function dishKey(name, subtitle) {
  return `${String(name).trim()}|${String(subtitle).trim()}`;
}

function parseRupees(priceStr) {
  const digits = String(priceStr || "").replace(/[^\d]/g, "");
  const n = parseInt(digits, 10);
  return isNaN(n) ? 0 : n;
}

/** Load admin-edited dish prices from Firestore; keyed by dish title (lowercased for fuzzy match). */
async function loadFirestoreMenuPrices(dbRef) {
  try {
    const snap = await dbRef
      .collection("admin_public")
      .doc("menu_overrides")
      .collection("snapshots")
      .get();
    const out = {};
    for (const d of snap.docs) {
      const data = d.data()?.data;
      if (!data) continue;
      const title = String(data.title || "").trim();
      const price = parseRupees(data.price);
      if (title && price > 0) {
        out[title.toLowerCase()] = {price, subtitle: String(data.subtitle || "").trim()};
      }
    }
    return out;
  } catch (e) {
    console.error("loadFirestoreMenuPrices failed:", e.message);
    return null;
  }
}

/** Delivery + packing charges applied to every order, set by admin in Settings. */
const DEFAULT_ORDER_CHARGES = {deliveryRupees: 40, packingRupees: 20};

function chargeOrDefault(raw, fallback) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return fallback;
  return Math.round(n);
}

/** Reads `admin_public/order_charges`; falls back to the defaults above. */
async function loadOrderCharges(dbRef) {
  if (!dbRef) return DEFAULT_ORDER_CHARGES;
  try {
    const snap = await dbRef.collection("admin_public").doc("order_charges").get();
    const data = snap.exists ? snap.data() || {} : {};
    return {
      deliveryRupees: chargeOrDefault(
          data.delivery_rupees, DEFAULT_ORDER_CHARGES.deliveryRupees),
      packingRupees: chargeOrDefault(
          data.packing_rupees, DEFAULT_ORDER_CHARGES.packingRupees),
    };
  } catch (e) {
    console.error("loadOrderCharges failed:", e.message);
    return DEFAULT_ORDER_CHARGES;
  }
}

async function computeServerOrder(items, dbRef) {
  if (!Array.isArray(items) || items.length === 0) throw new Error("EMPTY_CART");
  let firestorePrices = null; // lazy-loaded only when needed
  let subtotal = 0;
  let qtySum = 0;
  const lines = [];
  for (const raw of items) {
    const qty = Number(raw.qty);
    if (!Number.isInteger(qty) || qty < 1 || qty > 99) throw new Error("BAD_QTY");
    const name = String(raw.name ?? "").trim();
    const subtitle = String(raw.subtitle ?? "").trim();
    const key = dishKey(name, subtitle);
    let unit = PRICE_BY_KEY[key];

    if (unit == null) {
      // Item not in hardcoded list — could be admin-edited subtitle or a new dish.
      // Fall back to Firestore admin snapshots, matching by dish title.
      if (firestorePrices === null && dbRef) {
        firestorePrices = await loadFirestoreMenuPrices(dbRef);
      }
      if (firestorePrices) {
        const entry = firestorePrices[name.toLowerCase()];
        if (entry) unit = entry.price;
      }
    }

    if (unit == null) throw new Error(`UNKNOWN_ITEM:${key}`);
    subtotal += unit * qty;
    qtySum += qty;
    lines.push({name, subtitle, priceRupees: unit, qty});
  }
  const charges = await loadOrderCharges(dbRef);
  const del = qtySum > 0 ? charges.deliveryRupees : 0;
  const pack = qtySum > 0 ? charges.packingRupees : 0;
  const totalRupees = subtotal + del + pack;
  const totalPaise = Math.round(totalRupees * 100);
  if (totalPaise < 100) throw new Error("AMOUNT_TOO_LOW");
  return {
    lines,
    itemTotalRupees: subtotal,
    totalRupees,
    totalPaise,
    deliveryRupees: del,
    packagingRupees: pack,
  };
}

exports.createRazorpayCheckout = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;
  const {keyId, keySecret} = razorpayKeys();
  if (!keyId || !keySecret) {
    throw new HttpsError("failed-precondition", "Razorpay keys not configured");
  }

  const body = request.data || {};
  const deliveryLine = String(body.deliveryLine ?? "").trim();
  const scheduleLine =
    body.scheduleLine == null ? null : String(body.scheduleLine).trim();
  if (!deliveryLine || deliveryLine.length > 500) {
    throw new HttpsError("invalid-argument", "Invalid delivery");
  }

  let computed;
  try {
    computed = await computeServerOrder(body.items, db);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "bad cart";
    if (msg.startsWith("UNKNOWN_ITEM")) {
      throw new HttpsError("invalid-argument", "Unknown menu item or price mismatch");
    }
    throw new HttpsError("invalid-argument", "Invalid cart");
  }

  const sessionRef = db.collection("checkout_sessions").doc();
  const sessionId = sessionRef.id;

  await sessionRef.set({
    uid,
    status: "pending_payment",
    items: computed.lines,
    total_rupees: computed.totalRupees,
    item_total_rupees: computed.itemTotalRupees,
    delivery_charge_rupees: computed.deliveryRupees,
    packing_charge_rupees: computed.packagingRupees,
    total_paise: computed.totalPaise,
    delivery_line: deliveryLine,
    schedule_line: scheduleLine,
    payment_mode: "razorpay",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  const razorpay = new Razorpay({key_id: keyId, key_secret: keySecret});
  let rpOrder;
  try {
    rpOrder = await razorpay.orders.create({
      amount: computed.totalPaise,
      currency: "INR",
      receipt: sessionId.replace(/-/g, "").slice(0, 40),
      notes: {uid, session_id: sessionId},
    });
  } catch (e) {
    await sessionRef.update({
      status: "error",
      error_message: e instanceof Error ? e.message : "razorpay failed",
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new HttpsError("internal", "Could not start payment");
  }

  await sessionRef.update({
    razorpay_order_id: rpOrder.id,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection("rzp_order_map").doc(rpOrder.id).set({
    session_id: sessionId,
    uid,
  });

  return {
    sessionId,
    razorpayOrderId: rpOrder.id,
    amountPaise: computed.totalPaise,
    keyId,
  };
});

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

exports.razorpayWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const secret = webhookSecret();
  if (!secret) {
    res.status(503).send("Webhook secret not configured");
    return;
  }

  const rawBody = req.rawBody ? req.rawBody.toString("utf8") : "";
  const crypto = require("crypto");
  const sig = req.get("x-razorpay-signature") || "";
  const expected = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  if (!timingSafeEqual(expected.toLowerCase(), sig.toLowerCase())) {
    res.status(400).send("Invalid signature");
    return;
  }

  let payload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    res.status(400).send("Bad JSON");
    return;
  }

  const event = payload.event;
  const pay = payload.payload?.payment?.entity;
  const orderId = pay?.order_id;
  const paymentId = pay?.id;
  const amount = Number(pay?.amount);

  if (event === "payment.captured" && orderId && paymentId) {
    const mapSnap = await db.collection("rzp_order_map").doc(orderId).get();
    if (!mapSnap.exists) {
      res.json({ok: false, reason: "map_missing"});
      return;
    }
    const {session_id: sessionId} = mapSnap.data();

    const sessRef = db.collection("checkout_sessions").doc(sessionId);
    const sessSnap = await sessRef.get();
    if (!sessSnap.exists) {
      res.json({ok: false, reason: "session_missing"});
      return;
    }
    const s = sessSnap.data();
    if (s.status !== "pending_payment") {
      res.json({ok: true, duplicate: true});
      return;
    }
    if (Number(s.total_paise) !== amount) {
      console.error("amount mismatch", s.total_paise, amount);
      res.json({ok: false, reason: "amount_mismatch"});
      return;
    }

    const firestoreOrderId = `rz_${paymentId}`;
    const orderRef = db.collection("orders").doc(firestoreOrderId);
    try {
      await orderRef.create({
        uid: s.uid,
        status: "placed",
        total_rupees: s.total_rupees,
        item_total_rupees: s.item_total_rupees ?? null,
        delivery_charge_rupees: s.delivery_charge_rupees ?? null,
        packing_charge_rupees: s.packing_charge_rupees ?? null,
        delivery_line: s.delivery_line,
        payment_mode: "razorpay",
        payment_status: "captured",
        razorpay_order_id: orderId,
        razorpay_payment_id: paymentId,
        checkout_session_id: sessionId,
        schedule_line: s.schedule_line,
        items: s.items,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (e.code === 6 || e.code === "already-exists") {
        res.json({ok: true, duplicate: true});
        return;
      }
      console.error(e);
      res.status(500).send("Order insert failed");
      return;
    }

    await sessRef.update({
      status: "paid",
      order_id: firestoreOrderId,
      razorpay_payment_id: paymentId,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ok: true});
    return;
  }

  if (event === "payment.failed" && orderId) {
    const mapSnap = await db.collection("rzp_order_map").doc(orderId).get();
    const sid = mapSnap.data()?.session_id;
    if (sid) {
      await db.collection("checkout_sessions").doc(sid).update({
        status: "failed",
        fail_reason: "payment_failed",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    res.json({ok: true});
    return;
  }

  res.json({ignored: true, event: event ?? null});
});

// Client-side confirmation: after the Razorpay SDK reports success, the app
// sends the payment id + signature here. We verify the HMAC signature and
// create the order immediately (idempotent), so confirmation does not depend on
// webhook delivery. The razorpayWebhook remains a backup for the same order id.
exports.verifyRazorpayPayment = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;
  const {keySecret} = razorpayKeys();
  if (!keySecret) {
    throw new HttpsError("failed-precondition", "Razorpay keys not configured");
  }
  const orderId = String(request.data?.razorpayOrderId ?? "").trim();
  const paymentId = String(request.data?.razorpayPaymentId ?? "").trim();
  const signature = String(request.data?.razorpaySignature ?? "").trim();
  const sessionId = String(request.data?.sessionId ?? "").trim();
  if (!orderId || !paymentId || !signature || !sessionId) {
    throw new HttpsError("invalid-argument", "Missing payment fields");
  }

  const crypto = require("crypto");
  const expected = crypto
      .createHmac("sha256", keySecret)
      .update(`${orderId}|${paymentId}`)
      .digest("hex");
  if (!timingSafeEqual(expected.toLowerCase(), signature.toLowerCase())) {
    throw new HttpsError("permission-denied", "Signature verification failed");
  }

  const sessRef = db.collection("checkout_sessions").doc(sessionId);
  const sessSnap = await sessRef.get();
  if (!sessSnap.exists) {
    throw new HttpsError("not-found", "Checkout session not found");
  }
  const s = sessSnap.data();
  if (String(s.uid || "") !== uid) {
    throw new HttpsError("permission-denied", "Not your checkout");
  }
  if (String(s.razorpay_order_id || "") !== orderId) {
    throw new HttpsError("invalid-argument", "Order mismatch");
  }
  if (s.status === "paid" && typeof s.order_id === "string" && s.order_id) {
    return {status: "paid", orderId: s.order_id};
  }

  const firestoreOrderId = `rz_${paymentId}`;
  const orderRef = db.collection("orders").doc(firestoreOrderId);
  try {
    await orderRef.create({
      uid: s.uid,
      status: "placed",
      total_rupees: s.total_rupees,
      item_total_rupees: s.item_total_rupees ?? null,
      delivery_charge_rupees: s.delivery_charge_rupees ?? null,
      packing_charge_rupees: s.packing_charge_rupees ?? null,
      delivery_line: s.delivery_line,
      payment_mode: "razorpay",
      payment_status: "captured",
      razorpay_order_id: orderId,
      razorpay_payment_id: paymentId,
      checkout_session_id: sessionId,
      schedule_line: s.schedule_line,
      items: s.items,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (e.code === 6 || e.code === "already-exists") {
      return {status: "paid", orderId: firestoreOrderId};
    }
    console.error("verifyRazorpayPayment order create failed:", e);
    throw new HttpsError("internal", "Could not place order");
  }

  await sessRef.update({
    status: "paid",
    order_id: firestoreOrderId,
    razorpay_payment_id: paymentId,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {status: "paid", orderId: firestoreOrderId};
});

function isAdminRequest(request) {
  if (!request.auth) return false;
  const email = String(request.auth.token?.email || "").trim().toLowerCase();
  const phone = String(request.auth.token?.phone_number || "").trim();
  const tokenAdmin = request.auth.token?.admin === true;
  return email === ADMIN_EMAIL || phone === ADMIN_PHONE || tokenAdmin;
}

async function deleteQueryInBatches(query, batchSize = 250) {
  while (true) {
    const snap = await query.limit(batchSize).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
    if (snap.size < batchSize) return;
  }
}

async function deleteQueryInBatchesSafe(label, query) {
  try {
    await deleteQueryInBatches(query);
  } catch (e) {
    console.error(`adminDeleteCustomer: ${label} query failed`, e);
    throw e;
  }
}

async function deleteCustomerDataEverywhere(uid) {
  const cleanUid = String(uid || "").trim();
  if (!cleanUid) return;

  await deleteQueryInBatchesSafe(
      "orders",
      db.collection("orders").where("uid", "==", cleanUid),
  );
  await deleteQueryInBatchesSafe(
      "order_reviews",
      db.collection("order_reviews").where("uid", "==", cleanUid),
  );
  await deleteQueryInBatchesSafe(
      "checkout_sessions",
      db.collection("checkout_sessions").where("uid", "==", cleanUid),
  );
  await deleteQueryInBatchesSafe(
      "rzp_order_map",
      db.collection("rzp_order_map").where("uid", "==", cleanUid),
  );
  await deleteQueryInBatchesSafe(
      "push_tokens",
      db.collection("push_tokens").where("uid", "==", cleanUid),
  );
  await deleteQueryInBatchesSafe(
      "support_messages",
      db.collection("support_inbox").doc(cleanUid).collection("messages"),
  );
  await db.collection("support_inbox").doc(cleanUid).delete().catch(() => null);
  await db.collection("users").doc(cleanUid).delete().catch(() => null);

  try {
    await admin.auth().deleteUser(cleanUid);
  } catch (e) {
    const code = String(e?.code || "");
    if (code !== "auth/user-not-found") throw e;
  }
}

exports.adminDeleteCustomer = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  if (!isAdminRequest(request)) {
    throw new HttpsError("permission-denied", "Admin access required");
  }

  const uid = String(request.data?.uid || "").trim();
  if (!uid) {
    throw new HttpsError("invalid-argument", "uid is required");
  }
  if (uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "You cannot delete your own admin account");
  }

  try {
    await deleteCustomerDataEverywhere(uid);
    return {ok: true};
  } catch (e) {
    console.error("adminDeleteCustomer failed for", uid, e);
    const msg = e instanceof Error ? e.message : "Could not delete customer data";
    throw new HttpsError("internal", msg);
  }
});

function orderRef(orderId) {
  const id = String(orderId || "").trim();
  if (!id) return "#ORD";
  const tail = id.length > 6 ? id.substring(id.length - 6) : id;
  return `#ORD${tail.toUpperCase()}`;
}

function orderStatusText(status, orderId, totalRupees) {
  const ref = orderRef(orderId);
  const amount = Number(totalRupees || 0);
  switch (String(status || "").toLowerCase()) {
    case "placed":
      return `Your order ${ref} is placed. Total: ₹${amount}.`;
    case "preparing":
    case "accepted":
      return `Your order ${ref} is now preparing in the kitchen.`;
    case "ready":
      return `Your order ${ref} is ready for pickup/delivery.`;
    case "out_for_delivery":
      return `Your order ${ref} is out for delivery.`;
    case "delivered":
      return `Your order ${ref} is delivered. Enjoy your meal!`;
    case "completed":
      return `Your order ${ref} is completed. Thank you!`;
    case "cancelled":
      return `Your order ${ref} was cancelled.`;
    case "rejected":
      return `Your order ${ref} was rejected by the store.`;
    default:
      return `Order ${ref} update: ${status}`;
  }
}

function orderStatusPushCopy(status) {
  switch (String(status || "").toLowerCase()) {
    case "placed":
      return {title: "Order placed", body: "We have received your order."};
    case "preparing":
    case "accepted":
      return {title: "Preparing", body: "Chechi kitchen is preparing your food."};
    case "ready":
      return {title: "Ready", body: "Your order is packed and ready."};
    case "out_for_delivery":
      return {title: "On the way", body: "Your order is out for delivery."};
    case "delivered":
      return {title: "Delivered", body: "Your order has been delivered."};
    case "completed":
      return {title: "Completed", body: "Your order is completed. Thank you!"};
    case "cancelled":
      return {title: "Order cancelled", body: "Your order was cancelled."};
    case "rejected":
      return {title: "Order rejected", body: "Your order was rejected by the store."};
    default:
      return null;
  }
}

async function createSystemMessageForOrder({
  customerUid,
  text,
  orderId,
  status,
}) {
  if (!customerUid || !text) return;
  await db.collection("support_inbox")
      .doc(customerUid)
      .collection("messages")
      .add({
        sender: "system",
        text,
        order_id: orderId,
        order_status: status,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
}

let _adminUidCache = null;
async function adminUid() {
  if (_adminUidCache) return _adminUidCache;
  try {
    const u = await admin.auth().getUserByEmail(ADMIN_EMAIL);
    _adminUidCache = u.uid;
    return _adminUidCache;
  } catch (e) {
    console.error("Could not resolve admin uid:", e);
    return null;
  }
}

async function tokensForUid(uid) {
  if (!uid) return [];
  const snap = await db.collection("push_tokens").where("uid", "==", uid).limit(50).get();
  const out = [];
  for (const d of snap.docs) {
    const t = String(d.data().token || "").trim();
    if (t) out.push(t);
  }
  return Array.from(new Set(out));
}

async function sendPush({uid, title, body, data = {}}) {
  const tokens = await tokensForUid(uid);
  if (!tokens.length) return;
  try {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title, body},
      data: Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)]),
      ),
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}},
    });
  } catch (e) {
    console.error("sendPush failed:", e);
  }
}

async function userDisplayName(uid) {
  if (!uid) return null;
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return null;
    const m = snap.data() || {};
    const candidates = [m.displayName, m.name, m.fullName, m.username];
    for (const c of candidates) {
      if (typeof c === "string" && c.trim() && c.trim().toLowerCase() !== "customer") {
        return c.trim();
      }
    }
  } catch (e) {
    console.error("userDisplayName read failed:", e);
  }
  return null;
}

async function userProfileLite(uid) {
  if (!uid) return {name: null, mobile: null};
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return {name: null, mobile: null};
    const m = snap.data() || {};
    const name = [m.displayName, m.name, m.fullName, m.username]
        .find((v) => typeof v === "string" && v.trim() && v.trim().toLowerCase() !== "customer");
    const mobile = [m.mobile, m.phone, m.phoneNumber]
        .find((v) => typeof v === "string" && v.trim());
    return {
      name: typeof name === "string" ? name.trim() : null,
      mobile: typeof mobile === "string" ? mobile.trim() : null,
    };
  } catch (e) {
    console.error("userProfileLite read failed:", e);
    return {name: null, mobile: null};
  }
}

async function deleteOlderThan({
  collectionName,
  timestampField,
  olderThanDate,
  extraWhere = null,
  batchSize = 250,
}) {
  let query = db.collection(collectionName)
      .where(timestampField, "<", admin.firestore.Timestamp.fromDate(olderThanDate));
  if (extraWhere) {
    query = query.where(extraWhere.field, extraWhere.op, extraWhere.value);
  }
  while (true) {
    const snap = await query.limit(batchSize).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
    if (snap.size < batchSize) return;
  }
}

exports.nightlyDataCleanup = onSchedule("every day 03:15", async () => {
  const now = Date.now();
  const staleCheckoutBefore = new Date(now - 1000 * 60 * 60 * 24 * 30); // 30 days
  const stalePushBefore = new Date(now - 1000 * 60 * 60 * 24 * 45); // 45 days

  // Remove old pending/failed checkout session records.
  await deleteOlderThan({
    collectionName: "checkout_sessions",
    timestampField: "updated_at",
    olderThanDate: staleCheckoutBefore,
    extraWhere: {field: "status", op: "in", value: ["failed", "pending_payment", "error"]},
  });

  // Remove old push tokens that likely expired.
  await deleteOlderThan({
    collectionName: "push_tokens",
    timestampField: "updated_at",
    olderThanDate: stalePushBefore,
  });
});

// Customer-initiated order cancellation. Orders are admin-write-only in
// Firestore rules, so cancellation goes through this callable which verifies
// ownership and that the order is still in a cancellable state. The
// onOrderStatusChangedChatMessage trigger then posts the "was cancelled"
// system message and push automatically.
const CANCELLABLE_STATUSES = new Set([
  "", "placed", "new", "accepted", "preparing", "ready",
]);

exports.cancelOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;
  const orderId = String(request.data?.orderId ?? "").trim();
  if (!orderId) {
    throw new HttpsError("invalid-argument", "Missing orderId");
  }
  const reason = String(request.data?.reason ?? "").trim().slice(0, 300);

  const orderRef = db.collection("orders").doc(orderId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Order not found");
    }
    const o = snap.data();
    if (String(o.uid || "") !== uid) {
      throw new HttpsError("permission-denied", "Not your order");
    }
    const status = String(o.status || "").trim().toLowerCase();
    if (status === "cancelled") {
      return {ok: true, alreadyCancelled: true};
    }
    if (!CANCELLABLE_STATUSES.has(status)) {
      throw new HttpsError(
        "failed-precondition",
        "This order can no longer be cancelled. Please contact support.",
      );
    }
    tx.update(orderRef, {
      status: "cancelled",
      cancelled_by: "customer",
      cancel_reason: reason || null,
      cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {ok: true, cancelled: true};
  });
});

// Chat push notifications. A Firestore trigger can't do this job on a named
// database in asia-south1 (v1 triggers require (default); v2 hits an Eventarc
// internal error), so the client calls this right after sending a message to
// notify the other party. The thread summary doc is maintained client-side.
exports.notifyChatMessage = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const callerUid = request.auth.uid;
  const customerUid = String(request.data?.customerUid ?? "").trim();
  const text = String(request.data?.text ?? "").trim().slice(0, 4000);
  const sender = String(request.data?.sender ?? "").trim().toLowerCase();
  if (!customerUid || !text) {
    throw new HttpsError("invalid-argument", "Missing fields");
  }
  const callerIsAdmin = isAdminRequest(request);

  if (sender === "admin") {
    if (!callerIsAdmin) {
      throw new HttpsError("permission-denied", "Admins only");
    }
    await sendPush({
      uid: customerUid,
      title: "New message from support",
      body: text,
      data: {type: "chat_message", customer_uid: customerUid},
    });
    return {ok: true};
  }

  // Customer message -> notify admin. Only the customer themselves (or an
  // admin acting on their behalf) may trigger it.
  if (callerUid !== customerUid && !callerIsAdmin) {
    throw new HttpsError("permission-denied", "Not allowed");
  }
  const aUid = await adminUid();
  if (aUid) {
    const name = await userDisplayName(customerUid);
    await sendPush({
      uid: aUid,
      title: name ? `New message from ${name}` : "New customer message",
      body: text,
      data: {type: "chat_message", customer_uid: customerUid},
    });
  }
  return {ok: true};
});

exports.onOrderCreatedChatMessage = onDocumentCreated(
    {document: "orders/{orderId}", database: FIRESTORE_DB, region: "asia-south1"},
    async (event) => {
  const data = event.data?.data();
  if (!data) return;
  const uid = String(data.uid || "").trim();
  if (!uid) return;
  const status = String(data.status || "placed").trim();
  const text = orderStatusText(status, event.params.orderId, data.total_rupees);
  await createSystemMessageForOrder({
    customerUid: uid,
    text,
    orderId: event.params.orderId,
    status,
  });

  // Notify the admin that a new order came in.
  try {
    const adminId = await adminUid();
    if (adminId) {
      const {name, mobile} = await userProfileLite(uid);
      const who = name || mobile || "A customer";
      const amount = Number(data.total_rupees || 0);
      await sendPush({
        uid: adminId,
        title: "New order received",
        body: `${who} placed ${orderRef(event.params.orderId)} · ₹${amount}`,
        data: {
          type: "admin_new_order",
          orderId: event.params.orderId,
          customer_uid: uid,
        },
      });
    }
  } catch (e) {
    console.error("admin new-order push failed:", e);
  }

  // Kitchen sheet. Failing here must not cost the customer their chat message
  // or the admin their notification, so it is last and swallowed.
  try {
    await appendRegularOrderRow(event.params.orderId, data);
  } catch (e) {
    console.error("order -> sheet failed:", e);
  }
});

exports.onOrderStatusChangedChatMessage = onDocumentUpdated(
    {document: "orders/{orderId}", database: FIRESTORE_DB, region: "asia-south1"},
    async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return;

  const prevStatus = String(before.status || "").trim().toLowerCase();
  const nextStatus = String(after.status || "").trim().toLowerCase();
  if (!nextStatus || prevStatus === nextStatus) return;

  const uid = String(after.uid || "").trim();
  if (!uid) return;
  const text = orderStatusText(nextStatus, event.params.orderId, after.total_rupees);
  await createSystemMessageForOrder({
    customerUid: uid,
    text,
    orderId: event.params.orderId,
    status: nextStatus,
  });

  const pushCopy = orderStatusPushCopy(nextStatus);
  if (pushCopy) {
    await sendPush({
      uid,
      title: pushCopy.title,
      body: pushCopy.body,
      data: {
        type: "order_status",
        orderId: event.params.orderId,
        status: nextStatus,
      },
    });
  }
});

const IST_TIMEZONE = "Asia/Kolkata";

function todayDateKey() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: IST_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function istMonthAndDay() {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: IST_TIMEZONE,
    month: "numeric",
    day: "numeric",
  }).formatToParts(new Date());
  const month = parseInt(parts.find((p) => p.type === "month")?.value || "0", 10);
  const day = parseInt(parts.find((p) => p.type === "day")?.value || "0", 10);
  return {month, day};
}

function isBirthdayToday(dobStr) {
  if (!dobStr || typeof dobStr !== "string") return false;
  const parts = dobStr.trim().split("-");
  if (parts.length < 3) return false;
  const m = parseInt(parts[1], 10);
  const day = parseInt(parts[2], 10);
  if (!Number.isFinite(m) || !Number.isFinite(day)) return false;
  const {month, day: todayDay} = istMonthAndDay();
  return m === month && day === todayDay;
}

function birthdayWishText(displayName) {
  const trimmed = String(displayName || "").trim();
  const first = trimmed ? trimmed.split(/\s+/)[0] : "there";
  return (
    `🎉 Happy Birthday, ${first}! 🎂\n\n` +
    "Warm wishes from everyone at Chechi Puttu Kadai. " +
    "May your day be filled with joy, love, and delicious homestyle food!"
  );
}

async function postBirthdayChatWish(customerUid, user) {
  const dayKey = todayDateKey();
  const threadRef = db.collection("support_inbox").doc(customerUid);
  const thread = await threadRef.get();
  if (thread.data()?.birthday_wish_sent_on === dayKey) {
    return false;
  }
  const name = String(user.displayName || "").trim() || "there";
  const text = birthdayWishText(name);
  const preview = text.split("\n")[0] || text;
  await threadRef.collection("messages").add({
    text,
    sender: "admin",
    kind: "birthday_wish",
    auto: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  await threadRef.set({
    customer_uid: customerUid,
    customer_name: user.displayName || null,
    customer_mobile: user.mobile || null,
    last_message: preview,
    last_sender: "admin",
    last_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    birthday_wish_sent_on: dayKey,
    unread_customer_to_admin: 0,
  }, {merge: true});
  return true;
}

function birthdayPushText(displayName) {
  const trimmed = String(displayName || "").trim();
  const first = trimmed ? trimmed.split(/\s+/)[0] : "there";
  return {
    title: `🎂 Happy Birthday, ${first}!`,
    body: "Warm wishes from Chechi Puttu Kadai. Open the app for a special message!",
  };
}

/** Every day at 7:00 AM IST — push + in-app chat wish for customers whose birthday is today. */
exports.dailyBirthdayMorningPush = onSchedule({
  schedule: "0 7 * * *",
  timeZone: IST_TIMEZONE,
}, async () => {
  const dayKey = todayDateKey();
  const snap = await db.collection("users").limit(2500).get();
  let pushCount = 0;
  let chatCount = 0;
  for (const doc of snap.docs) {
    const user = doc.data() || {};
    const uid = doc.id;
    const dob = user.dateOfBirth;
    if (!isBirthdayToday(dob)) continue;

    if (user.birthday_push_sent_on !== dayKey) {
      const name = String(user.displayName || "").trim() || "there";
      const {title, body} = birthdayPushText(name);
      await sendPush({
        uid,
        title,
        body,
        data: {type: "birthday", customer_uid: uid},
      });
      await doc.ref.set({birthday_push_sent_on: dayKey}, {merge: true});
      pushCount++;
    }

    const posted = await postBirthdayChatWish(uid, user);
    if (posted) chatCount++;
  }
  console.log(`dailyBirthdayMorningPush ${dayKey}: push=${pushCount} chat=${chatCount}`);
});

/** Idempotent: post one admin birthday wish in support chat per customer per day. */
exports.ensureBirthdayChatWish = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const customerUid = String(request.data?.customerUid || "").trim();
  if (!customerUid) {
    throw new HttpsError("invalid-argument", "customerUid is required");
  }
  const callerEmail = String(request.auth.token?.email || "").toLowerCase();
  const isAdmin = callerEmail === ADMIN_EMAIL.toLowerCase();
  if (!isAdmin && request.auth.uid !== customerUid) {
    throw new HttpsError("permission-denied", "Not allowed for this customer");
  }

  const userSnap = await db.collection("users").doc(customerUid).get();
  const user = userSnap.data() || {};
  const dob = user.dateOfBirth;
  if (!isBirthdayToday(dob)) {
    return {sent: false, reason: "not_birthday"};
  }

  const posted = await postBirthdayChatWish(customerUid, user);
  return {sent: posted, reason: posted ? null : "already_sent"};
});

exports.onSupportAbuseGuard = onDocumentCreated(
    {
      document: "support_inbox/{customerUid}/messages/{messageId}",
      database: FIRESTORE_DB,
      region: "asia-south1",
    },
    async (event) => {
      const customerUid = String(event.params.customerUid || "").trim();
      const msg = event.data?.data();
      if (!customerUid || !msg) return;
      const sender = String(msg.sender || "").trim().toLowerCase();
      if (sender !== "customer") return;

      const since = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 1000 * 60 * 2),
      );
      const recent = await db.collection("support_inbox")
          .doc(customerUid)
          .collection("messages")
          .where("created_at", ">=", since)
          .limit(30)
          .get();
      const recentCustomerCount = recent.docs.filter((d) => {
        const s = String(d.data().sender || "").trim().toLowerCase();
        return s === "customer";
      }).length;

      if (recentCustomerCount < 15) return;

      await db.collection("support_inbox").doc(customerUid).set({
        is_rate_limited: true,
        rate_limited_at: admin.firestore.FieldValue.serverTimestamp(),
        rate_limit_reason: "too_many_messages_short_window",
      }, {merge: true});

      const aUid = await adminUid();
      if (!aUid) return;
      await sendPush({
        uid: aUid,
        title: "Potential chat abuse detected",
        body: `User ${customerUid} sent ${recentCustomerCount} messages in ~2 minutes.`,
        data: {type: "support_abuse_alert", customer_uid: customerUid},
      });
    },
);

// ─────────── Bulk (hospital/corporate) enrollment → Google Sheet ───────────
// When a hospital/corporate customer completes the enrollment form, append a
// row to the shop's Google Sheet. The sheet must be shared (Editor) with this
// function's service account: 316102307451-compute@developer.gserviceaccount.com
const BULK_ORDERS_SHEET_ID = "169gBdQ9r0hrIshrkWMVni-a8KCKZ6qwPCas9rqGHHDE";
const BULK_ORDERS_SHEET_TAB = "Sheet1";
const BULK_ORDERS_HEADER = [
  "Submitted At", "Type", "Organisation", "Your Name", "Order Person",
  "Job Position", "Phone", "Alt Phone", "Preferred Time", "Delivery Days",
  "Selected Dishes", "Customer UID",
  // Appended after "Customer UID" so sheets created before these fields
  // existed keep their column alignment.
  "Meals", "Total Qty", "Dish Quantities",
];

// Every normal (non-bulk) order lands on its own tab of the same spreadsheet,
// so the kitchen has one file for both kinds of order.
const REGULAR_ORDERS_SHEET_TAB = "Regular orders";
const REGULAR_ORDERS_HEADER = [
  "Order At", "Order Ref", "Customer", "Phone", "Items", "Item Total",
  "Delivery", "Packing", "Total", "Payment", "Delivery Address",
  "Slot", "Status", "Customer UID",
];

/** Creates [tab] if the spreadsheet does not have it yet. */
async function ensureSheetTab(sheets, tab) {
  const meta = await sheets.spreadsheets.get({
    spreadsheetId: BULK_ORDERS_SHEET_ID,
    fields: "sheets.properties.title",
  });
  const exists = (meta.data.sheets || []).some(
      (s) => s.properties && s.properties.title === tab,
  );
  if (exists) return;
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId: BULK_ORDERS_SHEET_ID,
    requestBody: {
      requests: [{addSheet: {properties: {title: tab}}}],
    },
  });
}

/**
 * Appends one row to [tab], creating the tab and writing [header] the first
 * time. Used by both the bulk enrollment and the regular order triggers.
 */
async function appendSheetRow(tab, header, row) {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/spreadsheets"],
  });
  const sheets = google.sheets({version: "v4", auth});

  await ensureSheetTab(sheets, tab);

  // Write the header row once, only if the tab is currently empty.
  const first = await sheets.spreadsheets.values.get({
    spreadsheetId: BULK_ORDERS_SHEET_ID,
    range: `${tab}!A1:A1`,
  });
  if (!first.data.values || first.data.values.length === 0) {
    await sheets.spreadsheets.values.update({
      spreadsheetId: BULK_ORDERS_SHEET_ID,
      range: `${tab}!A1`,
      valueInputOption: "RAW",
      requestBody: {values: [header]},
    });
  }

  await sheets.spreadsheets.values.append({
    spreadsheetId: BULK_ORDERS_SHEET_ID,
    range: `${tab}!A1`,
    valueInputOption: "USER_ENTERED",
    insertDataOption: "INSERT_ROWS",
    requestBody: {values: [row]},
  });
}

async function appendBulkOrderRow(row) {
  await appendSheetRow(BULK_ORDERS_SHEET_TAB, BULK_ORDERS_HEADER, row);
}

/** One row per placed order, on the Regular orders tab. */
async function appendRegularOrderRow(orderId, data) {
  const items = Array.isArray(data.items) ? data.items : [];
  const itemsText = items
      .map((it) => {
        const name = String(it.name || "").trim();
        const qty = Number(it.qty || 0);
        return qty > 1 ? `${name} x${qty}` : name;
      })
      .filter((t) => t.length > 0)
      .join(", ");

  const placedAt = data.created_at && typeof data.created_at.toDate ===
    "function" ? data.created_at.toDate() : new Date();

  const rupees = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : "";
  };

  const row = [
    placedAt.toLocaleString("en-IN", {timeZone: "Asia/Kolkata"}),
    orderRef(orderId),
    String(data.customer_name || ""),
    String(data.customer_mobile || ""),
    itemsText,
    rupees(data.item_total_rupees),
    rupees(data.delivery_charge_rupees),
    rupees(data.packing_charge_rupees),
    rupees(data.total_rupees),
    String(data.payment_mode || "").replace(/_/g, " "),
    String(data.delivery_line || ""),
    String(data.schedule_line || ""),
    String(data.status || "placed"),
    String(data.uid || ""),
  ];
  await appendSheetRow(
      REGULAR_ORDERS_SHEET_TAB, REGULAR_ORDERS_HEADER, row,
  );
}

/**
 * Confirms a submitted bulk plan to the customer (support-chat record + push)
 * and alerts the admin that a quotation is due within 24 hours.
 */
async function notifyBulkEnrollment({
  customerUid,
  typeLabel,
  org,
  meals,
  dishQuantities,
  totalQuantity,
  days,
  phone,
}) {
  if (!customerUid) return;

  const lines = [
    `Your ${typeLabel.toLowerCase()} bulk booking request has been received.`,
    org ? `Organisation: ${org}` : null,
    meals ? `Meals: ${meals}` : null,
    totalQuantity ? `Total quantity: ${totalQuantity} per delivery` : null,
    dishQuantities ? `Dishes: ${dishQuantities}` : null,
    days ? `Delivery days: ${days}` : null,
    "",
    "Our team will send you a quotation within 24 hours. " +
      "Reply here if anything needs to change.",
  ].filter((l) => l !== null);
  const text = lines.join("\n");

  const threadRef = db.collection("support_inbox").doc(customerUid);
  const {name, mobile} = await userProfileLite(customerUid);
  await threadRef.collection("messages").add({
    text,
    sender: "system",
    kind: "bulk_enrollment",
    auto: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  await threadRef.set({
    customer_uid: customerUid,
    customer_name: name || null,
    customer_mobile: mobile || phone || null,
    last_message: "Bulk booking request received",
    last_sender: "system",
    last_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await sendPush({
    uid: customerUid,
    title: "Booking request received",
    body: "We'll send your quotation within 24 hours.",
    data: {type: "bulk_enrollment", customer_uid: customerUid},
  });

  const aUid = await adminUid();
  if (aUid) {
    const who = org || name || mobile || "A customer";
    await sendPush({
      uid: aUid,
      title: `New ${typeLabel.toLowerCase()} bulk booking`,
      body: totalQuantity ?
        `${who} — ${totalQuantity} portions. Quotation due in 24h.` :
        `${who} — quotation due in 24h.`,
      data: {type: "bulk_enrollment_admin", customer_uid: customerUid},
    });
  }
}

exports.onBulkEnrollmentToSheet = onDocumentWritten(
    {document: "users/{userId}", database: FIRESTORE_DB, region: "asia-south1"},
    async (event) => {
      const after = event.data?.after?.data();
      if (!after) return; // doc deleted
      const before = event.data?.before?.data() || {};
      const beforeBulk = before.bulkOrder || {};
      const afterBulk = after.bulkOrder || {};

      // Fire only when an enrollment newly becomes complete (one row per submit).
      if (afterBulk.enrollmentComplete !== true) return;
      if (beforeBulk.enrollmentComplete === true) return;

      const orderType = String(after.orderType || "").trim().toLowerCase();
      if (orderType !== "hospital" && orderType !== "corporate") return;

      const days = Array.isArray(afterBulk.days) ? afterBulk.days.join(", ") : "";
      const dishes = Array.isArray(afterBulk.selectedDishes) ?
        afterBulk.selectedDishes.join(", ") : "";
      // Each meal carries its own delivery time. Older plans have no
      // mealTimes map — those fall back to the bare meal name.
      const MEAL_LABELS = {
        breakfast: "Breakfast",
        lunch: "Lunch",
        dinner: "Dinner",
      };
      const mealTimeMap = afterBulk.mealTimes &&
        typeof afterBulk.mealTimes === "object" ? afterBulk.mealTimes : {};
      const meals = Array.isArray(afterBulk.mealSlots) ?
        afterBulk.mealSlots
            .map((id) => {
              const label = MEAL_LABELS[id] || id;
              const at = String(mealTimeMap[id] || "").trim();
              return at ? `${label} ${at}` : label;
            })
            .join(", ") : "";
      const qtyMap = afterBulk.dishQuantities &&
        typeof afterBulk.dishQuantities === "object" ?
        afterBulk.dishQuantities : {};
      const dishQuantities = Object.entries(qtyMap)
          .map(([title, qty]) => `${title} x${qty}`)
          .join(", ");
      const submittedAt = new Date().toLocaleString("en-IN", {
        timeZone: "Asia/Kolkata",
      });

      const row = [
        submittedAt,
        orderType === "hospital" ? "Hospital" : "Corporate",
        String(afterBulk.organizationName || ""),
        String(afterBulk.contactName || ""),
        String(afterBulk.orderPersonName || ""),
        String(afterBulk.orderPersonDesignation || ""),
        String(afterBulk.phone || ""),
        String(afterBulk.alternatePhone || ""),
        String(afterBulk.preferredTime || ""),
        days,
        dishes,
        event.params.userId,
        meals,
        String(afterBulk.totalQuantity || ""),
        dishQuantities,
      ];

      try {
        await appendBulkOrderRow(row);
        console.log(`Bulk enrollment row added for ${event.params.userId}`);
      } catch (e) {
        console.error("bulk enrollment -> sheet failed:", e);
      }

      // The sheet is for the kitchen; the customer needs their own record and
      // a nudge, and the admin needs to know a quotation is due. A failure in
      // any of these must not mask the others.
      const typeLabel = orderType === "hospital" ? "Hospital" : "Corporate";
      const org = String(afterBulk.organizationName || "").trim();
      try {
        await notifyBulkEnrollment({
          customerUid: event.params.userId,
          typeLabel,
          org,
          meals,
          dishQuantities,
          totalQuantity: afterBulk.totalQuantity,
          days,
          phone: String(afterBulk.phone || "").trim(),
        });
      } catch (e) {
        console.error("bulk enrollment -> notify failed:", e);
      }
    },
);
