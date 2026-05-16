// Razorpay webhook — verify signature, create order on payment.captured (service role)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  const bytes = new Uint8Array(sig);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";
  if (!webhookSecret) {
    return new Response("Webhook secret not configured", { status: 503 });
  }

  const rawBody = await req.text();
  const sig = req.headers.get("x-razorpay-signature") ?? "";
  const expected = await hmacSha256Hex(webhookSecret, rawBody);
  if (!timingSafeEqual(expected.toLowerCase(), sig.toLowerCase())) {
    return new Response("Invalid signature", { status: 400 });
  }

  let payload: { event?: string; payload?: { payment?: { entity?: Record<string, unknown> } } };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const event = payload.event;
  const pay = payload.payload?.payment?.entity;
  const orderId = pay?.order_id as string | undefined;
  const paymentId = pay?.id as string | undefined;
  const amount = Number(pay?.amount);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceKey);

  if (event === "payment.captured" && orderId && paymentId) {
    const map = await admin.from("rzp_order_map").select("session_id,uid").eq(
      "razorpay_order_id",
      orderId,
    ).maybeSingle();
    if (map.error || !map.data) {
      return Response.json({ ok: false, reason: "map_missing" });
    }
    const sessionId = map.data.session_id as string;

    const sess = await admin.from("checkout_sessions").select("*").eq("id", sessionId).maybeSingle();
    if (sess.error || !sess.data) {
      return Response.json({ ok: false, reason: "session_missing" });
    }
    const s = sess.data as Record<string, unknown>;
    if (s.status !== "pending_payment") {
      return Response.json({ ok: true, duplicate: true });
    }
    if (Number(s.total_paise) !== amount) {
      console.error("amount mismatch", s.total_paise, amount);
      return Response.json({ ok: false, reason: "amount_mismatch" });
    }

    const firestoreOrderId = `rz_${paymentId}`;

    const { error: oErr } = await admin.from("orders").insert({
      id: firestoreOrderId,
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
    });
    if (oErr) {
      if (oErr.code === "23505") {
        return Response.json({ ok: true, duplicate: true });
      }
      console.error(oErr);
      return new Response("Order insert failed", { status: 500 });
    }

    await admin.from("checkout_sessions").update({
      status: "paid",
      order_id: firestoreOrderId,
      razorpay_payment_id: paymentId,
      updated_at: new Date().toISOString(),
    }).eq("id", sessionId);

    return Response.json({ ok: true });
  }

  if (event === "payment.failed" && orderId) {
    const map = await admin.from("rzp_order_map").select("session_id").eq(
      "razorpay_order_id",
      orderId,
    ).maybeSingle();
    if (map.data?.session_id) {
      await admin.from("checkout_sessions").update({
        status: "failed",
        fail_reason: "payment_failed",
        updated_at: new Date().toISOString(),
      }).eq("id", map.data.session_id);
    }
    return Response.json({ ok: true });
  }

  return Response.json({ ignored: true, event: event ?? null });
});
