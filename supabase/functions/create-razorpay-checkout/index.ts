// Deno Edge Function: create Razorpay order + checkout_sessions (auth: user JWT)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import Razorpay from "npm:razorpay@2.9.2";

const PRICE_BY_KEY: Record<string, number> = {
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
  "Egg Roast Curry|Spicy Kerala-style egg roast": 100,
  "Ada Pradhaman|Jaggery & rice ada": 120,
  "Elaneer Payasam|Tender coconut dessert": 110,
  "Chef Special Thali|Rice, curries & sides": 180,
  "Malabar Parotta|Flaky layered flatbread": 45,
  "Mixed Veg Curry|Chef special coconut gravy": 130,
  "Ghee Rice|Aromatic neichoru": 120,
  "Veg Meals|Sambar, poriyal & kootu": 140,
  "Sadya Mini (Veg)|Banana leaf festive meal": 220,
};

function dishKey(name: string, subtitle: string) {
  return `${name.trim()}|${subtitle.trim()}`;
}

function computeServerOrder(items: unknown) {
  if (!Array.isArray(items) || items.length === 0) throw new Error("EMPTY_CART");
  let subtotal = 0;
  let qtySum = 0;
  const lines: Array<{
    name: string;
    subtitle: string;
    priceRupees: number;
    qty: number;
  }> = [];
  for (const raw of items as Array<Record<string, unknown>>) {
    const qty = Number(raw.qty);
    if (!Number.isInteger(qty) || qty < 1 || qty > 99) throw new Error("BAD_QTY");
    const name = String(raw.name ?? "").trim();
    const subtitle = String(raw.subtitle ?? "").trim();
    const key = dishKey(name, subtitle);
    const unit = PRICE_BY_KEY[key];
    if (unit == null) throw new Error(`UNKNOWN_ITEM:${key}`);
    subtotal += unit * qty;
    qtySum += qty;
    lines.push({ name, subtitle, priceRupees: unit, qty });
  }
  const del = qtySum > 0 ? 30 : 0;
  const pack = qtySum > 0 ? 10 : 0;
  const totalRupees = subtotal + del + pack;
  const totalPaise = Math.round(totalRupees * 100);
  if (totalPaise < 100) throw new Error("AMOUNT_TOO_LOW");
  return { lines, totalRupees, totalPaise, deliveryRupees: del, packagingRupees: pack };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const keyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
  if (!keyId || !keySecret) {
    return Response.json(
      { error: "Razorpay keys not configured on this function" },
      { status: 503 },
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await supabase.auth.getUser();
  if (userErr || !user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const deliveryLine = String(body.deliveryLine ?? "").trim();
  const scheduleLine = body.scheduleLine == null
    ? null
    : String(body.scheduleLine).trim();
  if (!deliveryLine || deliveryLine.length > 500) {
    return Response.json({ error: "Invalid delivery" }, { status: 400 });
  }

  let computed;
  try {
    computed = computeServerOrder(body.items);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "bad cart";
    if (msg.startsWith("UNKNOWN_ITEM")) {
      return Response.json({ error: "Unknown menu item or price mismatch" }, { status: 400 });
    }
    return Response.json({ error: "Invalid cart" }, { status: 400 });
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceKey);

  const { data: sessionRow, error: insErr } = await admin
    .from("checkout_sessions")
    .insert({
      uid: user.id,
      status: "pending_payment",
      items: computed.lines,
      total_rupees: computed.totalRupees,
      total_paise: computed.totalPaise,
      delivery_line: deliveryLine,
      schedule_line: scheduleLine || null,
      payment_mode: "razorpay",
    })
    .select("id")
    .single();

  if (insErr || !sessionRow) {
    return Response.json({ error: insErr?.message ?? "session insert failed" }, { status: 500 });
  }
  const sessionId = sessionRow.id as string;

  const razorpay = new Razorpay({ key_id: keyId, key_secret: keySecret });
  let rpOrder: { id: string };
  try {
    rpOrder = await razorpay.orders.create({
      amount: computed.totalPaise,
      currency: "INR",
      receipt: sessionId.replace(/-/g, "").slice(0, 40),
      notes: { uid: user.id, session_id: sessionId },
    }) as { id: string };
  } catch (e) {
    await admin.from("checkout_sessions").update({
      status: "error",
      error_message: e instanceof Error ? e.message : "razorpay failed",
      updated_at: new Date().toISOString(),
    }).eq("id", sessionId);
    return Response.json({ error: "Could not start payment" }, { status: 500 });
  }

  await admin.from("checkout_sessions").update({
    razorpay_order_id: rpOrder.id,
    updated_at: new Date().toISOString(),
  }).eq("id", sessionId);

  await admin.from("rzp_order_map").insert({
    razorpay_order_id: rpOrder.id,
    session_id: sessionId,
    uid: user.id,
  });

  return Response.json({
    sessionId,
    razorpayOrderId: rpOrder.id,
    amountPaise: computed.totalPaise,
    keyId,
  });
});
