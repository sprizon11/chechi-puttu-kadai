const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const functionsV1 = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {initializeFirestore} = require("firebase-admin/firestore");
const Razorpay = require("razorpay");

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
  const del = qtySum > 0 ? 30 : 0;
  const pack = qtySum > 0 ? 10 : 0;
  const totalRupees = subtotal + del + pack;
  const totalPaise = Math.round(totalRupees * 100);
  if (totalPaise < 100) throw new Error("AMOUNT_TOO_LOW");
  return {lines, totalRupees, totalPaise, deliveryRupees: del, packagingRupees: pack};
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

// ─────────────────────────── Cashfree Payments ───────────────────────────
// Set in Firebase Console → Functions runtime env vars / Secret Manager:
//   CASHFREE_APP_ID, CASHFREE_SECRET_KEY, CASHFREE_ENV ("production"|"sandbox")
// Optional: CASHFREE_WEBHOOK_URL (https URL of cashfreeWebhook below).
function cashfreeKeys() {
  const appId = (process.env.CASHFREE_APP_ID || "").trim();
  const secretKey = (process.env.CASHFREE_SECRET_KEY || "").trim();
  const env = (process.env.CASHFREE_ENV || "sandbox").trim().toLowerCase();
  return {appId, secretKey, env};
}

function cashfreeBaseUrl(env) {
  return env === "production"
    ? "https://api.cashfree.com/pg"
    : "https://sandbox.cashfree.com/pg";
}

function sanitizePhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  // Cashfree wants a 10-digit Indian number; strip a leading 91 if present.
  const local = digits.length > 10 ? digits.slice(-10) : digits;
  return /^[6-9]\d{9}$/.test(local) ? local : "9999999999";
}

exports.createCashfreeCheckout = onCall(
    {secrets: ["CASHFREE_APP_ID", "CASHFREE_SECRET_KEY", "CASHFREE_ENV"]},
    async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;
  const {appId, secretKey, env} = cashfreeKeys();
  if (!appId || !secretKey) {
    throw new HttpsError("failed-precondition", "Cashfree keys not configured");
  }

  const body = request.data || {};
  const deliveryLine = String(body.deliveryLine ?? "").trim();
  const scheduleLine =
    body.scheduleLine == null ? null : String(body.scheduleLine).trim();
  const scheduledAtIso =
    body.scheduledAtIso == null ? null : String(body.scheduledAtIso).trim();
  if (!deliveryLine || deliveryLine.length > 500) {
    throw new HttpsError("invalid-argument", "Invalid delivery");
  }

  let scheduledAtTs = null;
  if (scheduledAtIso) {
    const d = new Date(scheduledAtIso);
    if (!Number.isNaN(d.getTime())) {
      scheduledAtTs = admin.firestore.Timestamp.fromDate(d);
    }
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

  // Resolve the customer's phone from their profile (server-trusted).
  let customerPhone = request.auth.token?.phone_number || "";
  try {
    const profile = await db.collection("users").doc(uid).get();
    const p = profile.data() || {};
    customerPhone = p.mobile || p.authPhone || customerPhone;
  } catch (_) {
    // Non-fatal; fall back below.
  }
  customerPhone = sanitizePhone(customerPhone);

  const sessionRef = db.collection("checkout_sessions").doc();
  const sessionId = sessionRef.id;

  await sessionRef.set({
    uid,
    status: "pending_payment",
    items: computed.lines,
    total_rupees: computed.totalRupees,
    total_paise: computed.totalPaise,
    delivery_line: deliveryLine,
    schedule_line: scheduleLine,
    scheduled_at: scheduledAtTs,
    payment_mode: "cashfree",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  const orderPayload = {
    order_id: sessionId,
    order_amount: computed.totalRupees,
    order_currency: "INR",
    customer_details: {
      customer_id: uid,
      customer_phone: customerPhone,
    },
    order_note: "Chechi Puttu Kadai order",
    order_tags: {session_id: sessionId},
  };
  const notifyUrl = process.env.CASHFREE_WEBHOOK_URL || "";
  if (notifyUrl) {
    orderPayload.order_meta = {notify_url: notifyUrl};
  }

  let cfData;
  try {
    const resp = await fetch(`${cashfreeBaseUrl(env)}/orders`, {
      method: "POST",
      headers: {
        "accept": "application/json",
        "content-type": "application/json",
        "x-api-version": "2023-08-01",
        "x-client-id": appId,
        "x-client-secret": secretKey,
      },
      body: JSON.stringify(orderPayload),
    });
    cfData = await resp.json().catch(() => ({}));
    if (!resp.ok || !cfData.payment_session_id) {
      // Log the real Cashfree response so production failures are diagnosable
      // (no secrets are logged — only env + status + Cashfree's own message).
      console.error("cashfreeOrderFailed", {
        env,
        baseUrl: cashfreeBaseUrl(env),
        httpStatus: resp.status,
        cfMessage: cfData.message || null,
        cfCode: cfData.code || null,
        cfType: cfData.type || null,
      });
      throw new Error(cfData.message || `Cashfree HTTP ${resp.status}`);
    }
  } catch (e) {
    console.error("createCashfreeCheckout error:", e instanceof Error ? e.message : e);
    await sessionRef.update({
      status: "error",
      error_message: e instanceof Error ? e.message : "cashfree failed",
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new HttpsError("internal", "Could not start payment");
  }

  await sessionRef.update({
    cf_order_id: cfData.cf_order_id != null ? String(cfData.cf_order_id) : null,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    sessionId,
    paymentSessionId: cfData.payment_session_id,
    cfOrderId: String(cfData.cf_order_id ?? sessionId),
    orderId: sessionId,
    mode: env === "production" ? "production" : "sandbox",
    amountRupees: computed.totalRupees,
  };
});

// Creates a Cashfree Payment Link and returns its shareable URL. The app opens
// this URL in the system browser, so the payment page is hosted on Cashfree's
// own domain — no app-package or domain whitelisting is required (this is the
// key advantage over the native SDK, which fails Android package verification).
// Confirmation is handled by reconcileCashfreeOrder (link-aware) and the
// scheduled safety net — the order is keyed by checkout session id (link_id).
exports.createCashfreePaymentLink = onCall(
    {secrets: ["CASHFREE_APP_ID", "CASHFREE_SECRET_KEY", "CASHFREE_ENV"]},
    async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;
  const {appId, secretKey, env} = cashfreeKeys();
  if (!appId || !secretKey) {
    throw new HttpsError("failed-precondition", "Cashfree keys not configured");
  }

  const body = request.data || {};
  const deliveryLine = String(body.deliveryLine ?? "").trim();
  const scheduleLine =
    body.scheduleLine == null ? null : String(body.scheduleLine).trim();
  const scheduledAtIso =
    body.scheduledAtIso == null ? null : String(body.scheduledAtIso).trim();
  if (!deliveryLine || deliveryLine.length > 500) {
    throw new HttpsError("invalid-argument", "Invalid delivery");
  }

  let scheduledAtTs = null;
  if (scheduledAtIso) {
    const d = new Date(scheduledAtIso);
    if (!Number.isNaN(d.getTime())) {
      scheduledAtTs = admin.firestore.Timestamp.fromDate(d);
    }
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

  let customerPhone = request.auth.token?.phone_number || "";
  let customerName = "";
  try {
    const profile = await db.collection("users").doc(uid).get();
    const p = profile.data() || {};
    customerPhone = p.mobile || p.authPhone || customerPhone;
    customerName = String(p.name || p.fullName || "").trim();
  } catch (_) {
    // Non-fatal.
  }
  customerPhone = sanitizePhone(customerPhone);

  const sessionRef = db.collection("checkout_sessions").doc();
  const sessionId = sessionRef.id;

  await sessionRef.set({
    uid,
    status: "pending_payment",
    items: computed.lines,
    total_rupees: computed.totalRupees,
    total_paise: computed.totalPaise,
    delivery_line: deliveryLine,
    schedule_line: scheduleLine,
    scheduled_at: scheduledAtTs,
    payment_mode: "cashfree_link",
    link_id: sessionId,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  const customerEmail =
    String(request.auth.token?.email || "").trim() || "customer@chechiputtu.in";

  const linkPayload = {
    link_id: sessionId,
    link_amount: computed.totalRupees,
    link_currency: "INR",
    link_purpose: "Chechi Puttu Kadai order",
    customer_details: {
      customer_phone: customerPhone,
      customer_email: customerEmail,
      customer_name: customerName || "Customer",
    },
    link_notify: {send_sms: false, send_email: false},
    link_auto_reminders: false,
  };

  let linkData;
  try {
    const resp = await fetch(`${cashfreeBaseUrl(env)}/links`, {
      method: "POST",
      headers: {
        "accept": "application/json",
        "content-type": "application/json",
        "x-api-version": "2023-08-01",
        "x-client-id": appId,
        "x-client-secret": secretKey,
      },
      body: JSON.stringify(linkPayload),
    });
    linkData = await resp.json().catch(() => ({}));
    if (!resp.ok || !linkData.link_url) {
      console.error("cashfreeLinkFailed", {
        env,
        httpStatus: resp.status,
        cfMessage: linkData.message || null,
        cfCode: linkData.code || null,
        cfType: linkData.type || null,
      });
      throw new Error(linkData.message || `Cashfree HTTP ${resp.status}`);
    }
  } catch (e) {
    console.error("createCashfreePaymentLink error:",
      e instanceof Error ? e.message : e);
    await sessionRef.update({
      status: "error",
      error_message: e instanceof Error ? e.message : "cashfree link failed",
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new HttpsError("internal", "Could not start payment");
  }

  await sessionRef.update({
    cf_link_id: linkData.cf_link_id != null ? String(linkData.cf_link_id) : null,
    link_url: String(linkData.link_url),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    sessionId,
    linkUrl: String(linkData.link_url),
    mode: env === "production" ? "production" : "sandbox",
    amountRupees: computed.totalRupees,
  };
});

/**
 * Idempotently creates the order doc for a successful Cashfree payment and
 * marks the checkout session paid. Shared by the webhook (push) and the
 * client-triggered reconcile path (pull). Returns one of:
 *   {result: "paid", orderId}       order freshly created
 *   {result: "duplicate", orderId}  order already existed
 *   {result: "amount_mismatch"}     paid amount != session total
 * `paidAmount` may be omitted (NaN) to skip the amount check.
 */
async function finalizeCashfreeSuccess(sessRef, s, cfPaymentId, paidAmount) {
  if (Number.isFinite(paidAmount) &&
      Math.round(Number(s.total_rupees) * 100) !== Math.round(paidAmount * 100)) {
    console.error("amount mismatch", s.total_rupees, paidAmount);
    return {result: "amount_mismatch"};
  }

  const firestoreOrderId = `cf_${cfPaymentId}`;
  const orderRef = db.collection("orders").doc(firestoreOrderId);
  let duplicate = false;
  try {
    await orderRef.create({
      uid: s.uid,
      status: "placed",
      total_rupees: s.total_rupees,
      delivery_line: s.delivery_line,
      payment_mode: "cashfree",
      payment_status: "captured",
      cf_order_id: s.cf_order_id ?? null,
      cf_payment_id: cfPaymentId,
      checkout_session_id: sessRef.id,
      schedule_line: s.schedule_line ?? null,
      scheduled_at: s.scheduled_at ?? null,
      items: s.items,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (e.code === 6 || e.code === "already-exists") {
      duplicate = true;
    } else {
      throw e;
    }
  }

  // Mark the session paid even on a duplicate create, so any client still
  // polling this session resolves to success.
  await sessRef.update({
    status: "paid",
    order_id: firestoreOrderId,
    cf_payment_id: cfPaymentId,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {result: duplicate ? "duplicate" : "paid", orderId: firestoreOrderId};
}

exports.cashfreeWebhook = onRequest(
    {secrets: ["CASHFREE_APP_ID", "CASHFREE_SECRET_KEY", "CASHFREE_ENV"]},
    async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const {secretKey} = cashfreeKeys();
  if (!secretKey) {
    res.status(503).send("Cashfree secret not configured");
    return;
  }

  const rawBody = req.rawBody ? req.rawBody.toString("utf8") : "";
  const crypto = require("crypto");
  const ts = req.get("x-webhook-timestamp") || "";
  const sig = req.get("x-webhook-signature") || "";
  const expected = crypto
    .createHmac("sha256", secretKey)
    .update(ts + rawBody)
    .digest("base64");
  if (!timingSafeEqual(expected, sig)) {
    console.error("cashfreeWebhook: signature mismatch", {ts: !!ts, rawBodyLen: rawBody.length});
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

  const type = payload.type;
  const order = payload.data?.order;
  const payment = payload.data?.payment;
  const sessionId = order?.order_id;
  const paymentStatus = payment?.payment_status;
  const cfPaymentId =
    payment?.cf_payment_id != null ? String(payment.cf_payment_id) : "";
  const paidAmount = Number(payment?.payment_amount);

  if (type === "PAYMENT_SUCCESS_WEBHOOK" &&
      paymentStatus === "SUCCESS" && sessionId && cfPaymentId) {
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

    let fin;
    try {
      fin = await finalizeCashfreeSuccess(sessRef, s, cfPaymentId, paidAmount);
    } catch (e) {
      console.error(e);
      res.status(500).send("Order insert failed");
      return;
    }
    if (fin.result === "amount_mismatch") {
      res.json({ok: false, reason: "amount_mismatch"});
      return;
    }

    res.json({ok: true, duplicate: fin.result === "duplicate"});
    return;
  }

  if (type === "PAYMENT_FAILED_WEBHOOK" && sessionId) {
    const sessRef = db.collection("checkout_sessions").doc(sessionId);
    const sessSnap = await sessRef.get();
    if (sessSnap.exists && sessSnap.data().status === "pending_payment") {
      await sessRef.update({
        status: "failed",
        fail_reason: "payment_failed",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    res.json({ok: true});
    return;
  }

  res.json({ignored: true, type: type ?? null});
});

// Fetches the payment list for a Cashfree order and finalizes it idempotently.
// Returns {status:'paid', orderId} | {status:'failed'[, reason]} | {status:'pending'}.
// Never throws — transient errors map to 'pending' so callers retry.
async function reconcileOrderPayments(sessRef, s, cfOrderId, env, appId, secretKey) {
  let payments;
  try {
    const resp = await fetch(
      `${cashfreeBaseUrl(env)}/orders/${encodeURIComponent(cfOrderId)}/payments`,
      {
        method: "GET",
        headers: {
          "accept": "application/json",
          "x-api-version": "2023-08-01",
          "x-client-id": appId,
          "x-client-secret": secretKey,
        },
      },
    );
    payments = await resp.json().catch(() => null);
    if (!resp.ok) {
      console.error("reconcileOrderPayments: fetch failed", {httpStatus: resp.status});
      return {status: "pending"};
    }
  } catch (e) {
    console.error("reconcileOrderPayments error:", e instanceof Error ? e.message : e);
    return {status: "pending"};
  }

  const list = Array.isArray(payments) ? payments : [];
  const success = list.find((p) => p && p.payment_status === "SUCCESS");
  if (success) {
    const cfPaymentId =
      success.cf_payment_id != null ? String(success.cf_payment_id) : "";
    if (!cfPaymentId) return {status: "pending"};
    let fin;
    try {
      fin = await finalizeCashfreeSuccess(
        sessRef, s, cfPaymentId, Number(success.payment_amount));
    } catch (e) {
      console.error("reconcileOrderPayments finalize failed", e);
      return {status: "pending"};
    }
    if (fin.result === "amount_mismatch") {
      return {status: "failed", reason: "amount_mismatch"};
    }
    return {status: "paid", orderId: fin.orderId};
  }

  // No success yet. If at least one attempt reached a terminal failed state and
  // none are still pending, the payment is genuinely not completed.
  const FAILED_STATES = new Set([
    "FAILED", "USER_DROPPED", "CANCELLED", "VOID", "EXPIRED",
  ]);
  const anyPending = list.some((p) => p && p.payment_status === "PENDING");
  const anyFailed = list.some((p) => p && FAILED_STATES.has(p.payment_status));
  if (anyFailed && !anyPending) return {status: "failed"};
  return {status: "pending"};
}

// For a Payment-Link session, finds the PAID order created under the link and
// finalizes it. Returns the same shape as reconcileOrderPayments.
async function reconcileLinkSession(sessRef, s, env, appId, secretKey) {
  const linkId = s.link_id || sessRef.id;
  let orders;
  try {
    const resp = await fetch(
      `${cashfreeBaseUrl(env)}/links/${encodeURIComponent(linkId)}/orders`,
      {
        method: "GET",
        headers: {
          "accept": "application/json",
          "x-api-version": "2023-08-01",
          "x-client-id": appId,
          "x-client-secret": secretKey,
        },
      },
    );
    orders = await resp.json().catch(() => null);
    if (!resp.ok) {
      console.error("reconcileLinkSession: orders fetch failed", {httpStatus: resp.status});
      return {status: "pending"};
    }
  } catch (e) {
    console.error("reconcileLinkSession error:", e instanceof Error ? e.message : e);
    return {status: "pending"};
  }

  const list = Array.isArray(orders) ? orders : [];
  const paid = list.find((o) => o && o.order_status === "PAID" && o.order_id);
  if (paid) {
    return reconcileOrderPayments(
      sessRef, s, String(paid.order_id), env, appId, secretKey);
  }
  // No paid order yet — the user may still be paying. The client times out and
  // shows a safe message; the scheduled job keeps reconciling in the background.
  return {status: "pending"};
}

function sessionIsLink(s) {
  return s.payment_mode === "cashfree_link" || !!s.link_id || !!s.cf_link_id;
}

// Client-triggered reconciliation. The app calls this while waiting for
// payment confirmation so it does NOT depend on the webhook being delivered in
// time. We query Cashfree's authoritative status and finalize the order
// ourselves (idempotent with the webhook). Handles both the legacy order flow
// and the Payment-Link flow.
exports.reconcileCashfreeOrder = onCall(
    {secrets: ["CASHFREE_APP_ID", "CASHFREE_SECRET_KEY", "CASHFREE_ENV"]},
    async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;
  const sessionId = String(request.data?.sessionId ?? "").trim();
  if (!sessionId) {
    throw new HttpsError("invalid-argument", "Missing sessionId");
  }
  const {appId, secretKey, env} = cashfreeKeys();
  if (!appId || !secretKey) {
    throw new HttpsError("failed-precondition", "Cashfree keys not configured");
  }

  const sessRef = db.collection("checkout_sessions").doc(sessionId);
  const sessSnap = await sessRef.get();
  if (!sessSnap.exists) {
    throw new HttpsError("not-found", "Unknown session");
  }
  const s = sessSnap.data();
  if (s.uid !== uid) {
    throw new HttpsError("permission-denied", "Not your session");
  }
  if (s.status === "paid" && typeof s.order_id === "string" && s.order_id) {
    return {status: "paid", orderId: s.order_id};
  }
  if (s.status === "failed" || s.status === "error") {
    return {status: "failed"};
  }

  return sessionIsLink(s)
    ? reconcileLinkSession(sessRef, s, env, appId, secretKey)
    : reconcileOrderPayments(sessRef, s, sessionId, env, appId, secretKey);
});

// Safety net: even if the app is killed right after a Link payment, this finds
// paid-but-unfinalized link sessions and creates their orders. Runs often and
// cheaply; the finalizer is idempotent so double-runs are harmless.
exports.reconcileCashfreePendingLinks = onSchedule(
    {
      schedule: "every 2 minutes",
      secrets: ["CASHFREE_APP_ID", "CASHFREE_SECRET_KEY", "CASHFREE_ENV"],
    },
    async () => {
  const {appId, secretKey, env} = cashfreeKeys();
  if (!appId || !secretKey) return;

  // Only look back ~45 min — older unpaid sessions are abandoned.
  const cutoffMs = Date.now() - 45 * 60 * 1000;
  const snap = await db
    .collection("checkout_sessions")
    .where("status", "==", "pending_payment")
    .limit(80)
    .get();

  for (const doc of snap.docs) {
    const s = doc.data();
    if (!sessionIsLink(s)) continue;
    const createdMs = s.created_at && s.created_at.toMillis
      ? s.created_at.toMillis()
      : null;
    if (createdMs != null && createdMs < cutoffMs) continue;
    try {
      await reconcileLinkSession(doc.ref, s, env, appId, secretKey);
    } catch (e) {
      console.error("scheduled link reconcile failed", doc.id,
        e instanceof Error ? e.message : e);
    }
  }
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

exports.onOrderCreatedChatMessage = onDocumentCreated(
    {document: "orders/{orderId}", database: FIRESTORE_DB},
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

// NOTE: onSupportMessagePush cannot be deployed as a Firestore trigger because
// this project uses a named Firestore database ('default') in asia-south1.
// Firebase v1 triggers require (default) database; v2 triggers hit an Eventarc
// internal error for named databases in asia-south1. Chat messages still save
// correctly — only push notifications for new chat messages are affected.
// To fix: migrate support_inbox writes to the (default) database, or use an
// HTTP callable triggered from the client after sending a message.
exports.onSupportMessagePush = functionsV1
    .region("asia-south1")
    .firestore.document("support_inbox/{customerUid}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const customerUid = String(context.params.customerUid || "").trim();
      const msg = snap.data();
      if (!customerUid || !msg) return;

      const sender = String(msg.sender || "").trim().toLowerCase();
      const text = String(msg.text || "").trim();
      if (!text) return;
      const createdAt = msg.created_at || admin.firestore.FieldValue.serverTimestamp();
      const inc = sender === "customer" ? 1 : 0;
      const profile = await userProfileLite(customerUid);
      await db.collection("support_inbox").doc(customerUid).set({
        customer_uid: customerUid,
        customer_name: profile.name,
        customer_mobile: profile.mobile,
        last_message: text,
        last_sender: sender || "customer",
        last_at: createdAt,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        unread_customer_to_admin: admin.firestore.FieldValue.increment(inc),
      }, {merge: true});

      if (sender === "customer") {
        const aUid = await adminUid();
        if (!aUid) return;
        const name = await userDisplayName(customerUid);
        await sendPush({
          uid: aUid,
          title: name ? `New message from ${name}` : "New customer message",
          body: text,
          data: {
            type: "chat_message",
            customer_uid: customerUid,
          },
        });
        return;
      }

      // admin/system message -> notify customer
      await sendPush({
        uid: customerUid,
        title: sender === "system" ? "Order update" : "New message from support",
        body: text,
        data: {
          type: sender === "system" ? "order_chat_update" : "chat_message",
          customer_uid: customerUid,
        },
      });
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
