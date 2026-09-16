const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();

/** Devices FCM lets us address in a single multicast call. */
const MULTICAST_CHUNK = 500;

/**
 * Resolves an audience selected in the Admin Console into the FCM tokens it
 * actually means.
 *
 * The console has always offered All / Pro / Free / Inactive targeting, and
 * this function has always read `data.target_audience`... and then sent to the
 * `all_merchants` topic regardless. Every "Pro only" or "win back inactive
 * merchants" campaign went to every merchant on the platform, including the
 * free users being told they had lapsed and the paying users being sold an
 * upgrade they already had.
 *
 * Returns `null` for the "all" audience, meaning "use the broadcast topic",
 * which stays the cheapest path for the common case.
 */
/** The only audiences this function knows how to resolve. */
const KNOWN_AUDIENCES = ["all", "pro", "free", "inactive"];

async function resolveAudienceTokens(targetAudience) {
  const audience = String(targetAudience || "all").toLowerCase();

  // Fail CLOSED on anything unrecognised. The filter below only ever removes
  // tokens, so an unknown value used to fall through every branch and return
  // the complete token list — i.e. a typo, or a future audience added in the
  // console before it was added here, would silently blast every merchant on
  // the platform. Refusing to send is the recoverable direction.
  if (!KNOWN_AUDIENCES.includes(audience)) {
    throw new Error(
      `Unknown target_audience "${targetAudience}" — refusing to send rather than broadcasting to everyone`
    );
  }

  if (audience === "all") return null;

  const db = getFirestore();
  const snapshot = await db.collection("businesses").get();
  const now = Date.now();
  const INACTIVE_AFTER_MS = 7 * 24 * 60 * 60 * 1000;

  const tokens = [];
  snapshot.forEach((doc) => {
    const d = doc.data() || {};
    const token = (d.fcm_token || "").trim();
    if (!token) return;

    const isPro = d.is_pro === true || d.is_pro === 1 || d.subscription_tier === "pro";

    if (audience === "pro" && !isPro) return;
    if (audience === "free" && isPro) return;
    if (audience === "inactive") {
      const lastSale = d.last_sale_at;
      // No sale ever recorded also counts as inactive — those are exactly the
      // signed-up-but-never-started merchants the campaign is aimed at.
      const lastSaleMs = lastSale && typeof lastSale.toMillis === "function"
        ? lastSale.toMillis()
        : 0;
      if (lastSaleMs && now - lastSaleMs < INACTIVE_AFTER_MS) return;
    }
    tokens.push(token);
  });

  // De-duplicate: one merchant reinstalling leaves stale duplicates behind.
  return [...new Set(tokens)];
}

/**
 * Triggered automatically when an Admin dispatches a push notification from the Admin Console.
 * Sends a real FCM System Tray push notification with high priority, sound & vibration to all merchants.
 */
exports.onAdminPushCreated = onDocumentCreated(
  "admin_push_notifications/{notificationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const data = snap.data();
    if (!data) return null;

    const title = data.title || "KamaiPlus POS Alert";
    const body = data.body || "";
    const actionUrl = data.action_url || "";
    const targetAudience = data.target_audience || "all";

    console.log(`[FCM] Processing notification: "${title}" for audience: ${targetAudience}`);

    const basePayload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        actionUrl: actionUrl,
        type: "admin_broadcast",
        notificationId: event.params.notificationId,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "kamai_pos_channel",
          sound: "default",
          priority: "high",
          defaultVibrateTimings: true,
          defaultSound: true,
          visibility: "public",
          icon: "ic_launcher",
        },
      },
    };

    try {
      const tokens = await resolveAudienceTokens(targetAudience);

      // "All" keeps the single cheap topic send.
      if (tokens === null) {
        const response = await getMessaging().send({
          ...basePayload,
          topic: "all_merchants",
        });
        console.log(`[FCM] Dispatched to topic all_merchants: ${response}`);
        await snap.ref.update({
          status: "delivered",
          target_audience_resolved: "all",
          fcm_message_id: response,
          delivered_at: FieldValue.serverTimestamp(),
        });
        return response;
      }

      if (tokens.length === 0) {
        console.log(`[FCM] Audience "${targetAudience}" matched no devices with a token.`);
        await snap.ref.update({
          status: "delivered",
          target_audience_resolved: targetAudience,
          recipients_matched: 0,
          success_count: 0,
          failure_count: 0,
          delivered_at: FieldValue.serverTimestamp(),
        });
        return null;
      }

      let successCount = 0;
      let failureCount = 0;
      for (let i = 0; i < tokens.length; i += MULTICAST_CHUNK) {
        const chunk = tokens.slice(i, i + MULTICAST_CHUNK);
        const res = await getMessaging().sendEachForMulticast({
          ...basePayload,
          tokens: chunk,
        });
        successCount += res.successCount;
        failureCount += res.failureCount;
      }

      console.log(
        `[FCM] Audience "${targetAudience}": ${successCount} delivered, ${failureCount} failed ` +
        `across ${tokens.length} device(s).`
      );
      await snap.ref.update({
        status: "delivered",
        target_audience_resolved: targetAudience,
        recipients_matched: tokens.length,
        success_count: successCount,
        failure_count: failureCount,
        delivered_at: FieldValue.serverTimestamp(),
      });
      return successCount;
    } catch (error) {
      console.error("[FCM] Failed to dispatch push notification:", error);
      await snap.ref.update({
        status: "failed",
        error: error.message,
      });
      return null;
    }
  }
);

// ============================================================================
// SERVER-SIDE RAZORPAY PAYMENT VERIFICATION
// ----------------------------------------------------------------------------
// Why this exists: Pro used to be granted entirely on the device. The app's
// own Razorpay success handler wrote `is_pro: true` straight into
// businesses/{bizId}, and firestore.rules let a business owner write any field
// on their own document. So Pro could be switched on with no payment at all,
// and even a real payment was never checked against Razorpay — no order_id, no
// signature, no amount check. This endpoint is now the ONLY thing that can
// grant paid Pro in the cloud (the Admin Console aside), and firestore.rules
// blocks clients from touching the subscription fields directly.
//
// Deploy:  firebase deploy --only functions
// Config:  firebase functions:secrets:set RAZORPAY_KEY_SECRET
//          (RAZORPAY_KEY_ID defaults to the live key already in the app)
// ============================================================================

const { onRequest } = require("firebase-functions/v2/https");
const { getAuth } = require("firebase-admin/auth");

const RAZORPAY_KEY_ID = process.env.RAZORPAY_KEY_ID || "rzp_live_TcXNjRb5XAUYqR";

/**
 * What each plan legitimately costs, in integer paise. A payment is only
 * honoured if it actually covers the plan being claimed.
 *
 * `minPaise` rather than an exact match because coupons are real: the app lets
 * a merchant apply an admin-issued coupon and pay less. The floor is what stops
 * someone paying ₹1 and claiming a year. Keep these in sync with
 * `razorpay_service.dart` and `pro_upgrade_modal.dart`.
 */
const PLAN_RULES = {
  monthly: { fullPaise: 19900, minPaise: 9900, days: 30 },
  annual: { fullPaise: 149900, minPaise: 74900, days: 365 },
};

/** Razorpay's REST API, called with HTTP Basic auth (key_id:key_secret). */
async function fetchRazorpayPayment(paymentId, keyId, keySecret) {
  const auth = Buffer.from(`${keyId}:${keySecret}`).toString("base64");
  const res = await fetch(`https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`, {
    method: "GET",
    headers: { Authorization: `Basic ${auth}` },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Razorpay lookup failed (${res.status}): ${body.slice(0, 300)}`);
  }
  return res.json();
}

exports.verifyRazorpayPayment = onRequest(
  { secrets: ["RAZORPAY_KEY_SECRET"], cors: true, region: "us-central1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    try {
      // 1. Who is asking? A Firebase ID token, verified server-side — never a
      //    business_id the caller simply claims in the body.
      const header = req.get("Authorization") || "";
      const idToken = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
      if (!idToken) {
        res.status(401).json({ error: "Missing Authorization bearer token" });
        return;
      }

      let decoded;
      try {
        decoded = await getAuth().verifyIdToken(idToken);
      } catch (e) {
        res.status(401).json({ error: "Invalid or expired ID token" });
        return;
      }
      const uid = decoded.uid;
      const bizId = `biz_${uid}`;

      // 2. What are they claiming?
      const body = req.body || {};
      const paymentId = String(body.payment_id || "").trim();
      const plan = String(body.plan || "").trim().toLowerCase();
      const couponCode = String(body.coupon_code || "").trim();

      if (!paymentId) {
        res.status(400).json({ error: "payment_id is required" });
        return;
      }
      const rule = PLAN_RULES[plan];
      if (!rule) {
        res.status(400).json({ error: `Unknown plan "${plan}"` });
        return;
      }

      // 3. Ask Razorpay what actually happened. This is the whole point — the
      //    device's word is not evidence of anything.
      const secret = process.env.RAZORPAY_KEY_SECRET;
      const payment = await fetchRazorpayPayment(
        paymentId,
        RAZORPAY_KEY_ID,
        secret
      );

      if (payment.status !== "captured") {
        res.status(402).json({
          error: `Payment is "${payment.status}", not captured`,
          status: payment.status,
        });
        return;
      }
      if (payment.amount < rule.minPaise) {
        res.status(402).json({
          error: `Paid ${payment.amount} paise, below the floor for the ${plan} plan`,
        });
        return;
      }
      if (payment.currency !== "INR") {
        res.status(402).json({ error: `Unexpected currency ${payment.currency}` });
        return;
      }

      const db = getFirestore();

      // 4. One payment grants Pro once. Replaying the same payment_id — the
      //    obvious next move once the client-side hole is closed — must not
      //    extend the subscription again, and must not let a SECOND account
      //    claim someone else's payment.
      const receiptRef = db.collection("razorpay_payments").doc(paymentId);
      const receipt = await receiptRef.get();
      if (receipt.exists) {
        const owner = receipt.data()?.business_id;
        if (owner && owner !== bizId) {
          res.status(409).json({ error: "This payment is already claimed by another account" });
          return;
        }
        res.status(200).json({
          ok: true,
          already_granted: true,
          pro_expiry: receipt.data()?.pro_expiry || null,
        });
        return;
      }

      // 5. Grant, via the Admin SDK — which is exactly what firestore.rules now
      //    forbids the client itself from doing.
      const expiry = new Date(Date.now() + rule.days * 24 * 60 * 60 * 1000).toISOString();
      const proFields = {
        is_pro: true,
        pro_plan: plan,
        pro_expiry: expiry,
        subscription_tier: plan,
        subscription_expires_at: expiry,
        subscription_valid_until: expiry,
        razorpay_payment_id: paymentId,
        pro_activated_at: FieldValue.serverTimestamp(),
        pro_granted_by: "razorpay_verified",
      };
      if (couponCode) proFields.coupon_code_used = couponCode;

      const batch = db.batch();
      batch.set(db.collection("businesses").doc(bizId), proFields, { merge: true });
      batch.set(
        db.collection("merchants").doc(uid),
        {
          is_pro: true,
          subscription_tier: plan,
          subscription_expires_at: expiry,
          updated_at: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      batch.set(receiptRef, {
        business_id: bizId,
        uid: uid,
        plan: plan,
        amount_paise: payment.amount,
        pro_expiry: expiry,
        coupon_code: couponCode || null,
        razorpay_status: payment.status,
        verified_at: FieldValue.serverTimestamp(),
      });
      await batch.commit();

      console.log(`[PRO] Verified ${paymentId} (${payment.amount}p, ${plan}) -> ${bizId}`);
      res.status(200).json({ ok: true, pro_plan: plan, pro_expiry: expiry });
    } catch (error) {
      console.error("[PRO] verifyRazorpayPayment failed:", error);
      res.status(500).json({ error: "Verification failed. Please contact support." });
    }
  }
);
