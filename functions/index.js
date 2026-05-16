const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const Razorpay = require("razorpay");

admin.initializeApp();
const db = admin.firestore();
const ADMIN_EMAIL = "sprizon1311@gmail.com";

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
  "Ada Pradhaman|Jaggery & rice ada": 120,
  "Elaneer Payasam|Tender coconut dessert": 110,
  "Chef Special Thali|Rice, curries & sides": 180,
  "Malabar Parotta|Flaky layered flatbread": 45,
  "Mixed Veg Curry|Chef special coconut gravy": 130,
  "Ghee Rice|Aromatic neichoru": 120,
};

function dishKey(name, subtitle) {
  return `${String(name).trim()}|${String(subtitle).trim()}`;
}

function computeServerOrder(items) {
  if (!Array.isArray(items) || items.length === 0) throw new Error("EMPTY_CART");
  let subtotal = 0;
  let qtySum = 0;
  const lines = [];
  for (const raw of items) {
    const qty = Number(raw.qty);
    if (!Number.isInteger(qty) || qty < 1 || qty > 99) throw new Error("BAD_QTY");
    const name = String(raw.name ?? "").trim();
    const subtitle = String(raw.subtitle ?? "").trim();
    const key = dishKey(name, subtitle);
    const unit = PRICE_BY_KEY[key];
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
    computed = computeServerOrder(body.items);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "bad cart";
    if (msg.startsWith("UNKNOWN_ITEM")) {
      throw new HttpsError("invalid-argument", "Unknown menu item or price mismatch");
    }
    throw new HttpsError("invalid-argument", "Invalid cart");
  }

  const db = admin.firestore();
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

  const db = admin.firestore();

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

function isAdminRequest(request) {
  if (!request.auth) return false;
  const email = String(request.auth.token?.email || "").trim().toLowerCase();
  const tokenAdmin = request.auth.token?.admin === true;
  return email === ADMIN_EMAIL || tokenAdmin;
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

async function deleteCustomerDataEverywhere(uid) {
  const cleanUid = String(uid || "").trim();
  if (!cleanUid) return;

  await deleteQueryInBatches(db.collection("orders").where("uid", "==", cleanUid));
  await deleteQueryInBatches(db.collection("checkout_sessions").where("uid", "==", cleanUid));
  await deleteQueryInBatches(db.collection("rzp_order_map").where("uid", "==", cleanUid));
  await deleteQueryInBatches(db.collection("push_tokens").where("uid", "==", cleanUid));
  await deleteQueryInBatches(
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

  await deleteCustomerDataEverywhere(uid);
  return {ok: true};
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
      return `Your order ${ref} is now preparing in the kitchen.`;
    case "ready":
      return `Your order ${ref} is ready for dispatch.`;
    case "out_for_delivery":
      return `Your order ${ref} is out for delivery.`;
    case "delivered":
      return `Your order ${ref} is delivered. Enjoy your meal!`;
    case "cancelled":
      return `Your order ${ref} was cancelled.`;
    case "rejected":
      return `Your order ${ref} was rejected by the store.`;
    default:
      return `Order ${ref} update: ${status}`;
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

exports.onOrderCreatedChatMessage = onDocumentCreated("orders/{orderId}", async (event) => {
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

exports.onOrderStatusChangedChatMessage = onDocumentUpdated("orders/{orderId}", async (event) => {
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
});

exports.onSupportMessagePush = onDocumentCreated(
    "support_inbox/{customerUid}/messages/{messageId}",
    async (event) => {
      const customerUid = String(event.params.customerUid || "").trim();
      const msg = event.data?.data();
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
    },
);

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
    "support_inbox/{customerUid}/messages/{messageId}",
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
