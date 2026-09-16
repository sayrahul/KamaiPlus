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
const { defineSecret } = require("firebase-functions/params");

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

// ============================================================================
// AI EXTRACTION PROXY  (bill / menu / PDF invoice -> structured JSON)
// ----------------------------------------------------------------------------
// Why this exists — three problems it closes at once:
//
// 1. THE KEY WAS ON EVERY PHONE. The app fetched `gemini_api_key` from
//    Firestore and cached it in SharedPreferences, then called Google
//    directly. Any merchant could pull that key off their own device and spend
//    the project's quota and billing. A key handed to every device is not a
//    secret. It now never leaves this function.
//
// 2. THE FREE-SCAN LIMIT WAS ONLY ON THE PHONE. `getMonthlyScanCount()` read
//    SharedPreferences, so clearing app data reset the 10-scan free quota.
//    Counting server-side per business makes the limit real.
//
// 3. SWITCHING PROVIDER MEANT AN APP RELEASE. Model names live here now, so a
//    deprecated model (which has already happened once — see the 2026-09-15
//    entry about 1.5-flash returning 404) is a redeploy, not a Play Store
//    rollout waiting on every merchant to update.
//
// Deploy:  firebase deploy --only functions:aiExtract
// Config:  firebase functions:secrets:set GEMINI_API_KEY
// ============================================================================

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

/** Tried in order; the first that answers wins. */
const AI_MODELS = [
  "gemini-3.6-flash",
  "gemini-2.5-flash",
  "gemini-3.5-flash-lite",
  "gemini-3.7-flash",
  "gemini-2.5-flash-latest",
];

/** Free plan allowance per calendar month, per business. Pro is unlimited. */
const FREE_MONTHLY_IMAGE_SCANS = 10;

/** Hard ceiling on an upload. Keeps one bad request from burning the budget. */
const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;

/**
 * Dynamically builds an intelligent, multi-vertical OCR & extraction prompt.
 * Instructs Gemini to self-adapt based on document visual layout:
 * - Restaurant / Cafe / Dhaba menu cards (clean dish names, portion sizes, veg/non-veg classification, 320/- to paise)
 * - Grocery / Kirana wholesaler tax invoices / mandi parcha slips (brand + item + pack, units, purchase rate vs MRP)
 * - Pharmacy / Medical distributor invoices (medicine strength, batch no, expiry YYYY-MM-DD, packaging)
 * - Apparel / Garments (style, size S/M/L, color, piece rate)
 * - Handwritten notebook parchas / slips in Hindi / Hinglish / English
 */
function buildUniversalAiPrompt(kind, clientVertical) {
  const isMenu = kind === "menu";
  const vertical = (clientVertical || "general retail").toLowerCase();

  return `You are an elite Indian retail AI assistant specializing in computer vision, OCR, and inventory/menu extraction for small and medium Indian retail and food businesses (Kirana, Restaurants, Medical/Pharmacy, Apparel/Garments, Electronics, Hardware).

CONTEXT & BUSINESS PROFILE:
- Upload Intent: ${isMenu ? "Menu Card / Rate Card / Catalog Scan" : "Inventory Purchase Bill / Supplier Invoice / Mandi Slip / Parcha"}
- Declared Merchant Vertical: "${vertical}"

SELF-ADAPTATION & INTELLIGENCE (CRITICAL):
Indian merchants upload diverse physical documents. You must visually inspect the document and intelligently adapt:

1. RESTAURANT / DHABA / CAFE / FOOD MENU:
   - Extract EVERY dish, snack, bread, rice, beverage, and dessert visible.
   - Clean names: Remove leading numbers or bullets (e.g., convert "21.Chicken Hydrabadi(5pcs)" -> "Chicken Hydrabadi (5pcs)").
   - Preserve portion sizes in the name (e.g., "Mutton Kasa (4pcs)", "Kadai Paneer (Half)", "Dal Makhani (Full)").
   - Determine Vegetarian status strictly:
     * Non-Veg (is_veg: false): contains chicken, mutton, gosht, murgh, fish, machhli, egg, anda, prawn, keema, pork, crab, duck, kabab.
     * Veg (is_veg: true): paneer, dal, sabzi, aloo, gobi, naan, roti, rice, beverages, chai, coffee, desserts, etc.
   - Categorize logically: Starters, Main Course Gravy, Biryani & Rice, Breads & Roti, Beverages, Desserts, Chinese, Snacks.

2. GROCERY / KIRANA / GENERAL STORE BILL:
   - Extract Brand + Product Name + Weight/Volume (e.g., "Aashirvaad Shuddh Chakki Atta 5kg", "Fortune Refined Sunlite Oil 1L", "Tata Salt 1kg", "Maggi 2-Min 70g").
   - Extract Quantity, Unit (kg, gram, litre, ml, packet, box, pcs), Purchase Cost, and MRP.

3. PHARMACY / MEDICAL DISTRIBUTOR INVOICE:
   - Extract Medicine Name + Strength (e.g., "Dolo 650mg", "Azithral 500mg", "Pantocid 40mg").
   - Extract Batch Number, Expiry Date (convert MM/YY or MM/YYYY to YYYY-MM-DD), packaging (strip, box, bottle, vial, tube).

4. APPAREL / CLOTHING / FOOTWEAR:
   - Extract Style/Item name, Size (S/M/L/XL or 28/30/32/34), Color, piece count, and rate.

5. MANDI PARCHA / HANDWRITTEN NOTEBOOK SLIP:
   - Carefully read Hindi/Devanagari/Hinglish handwriting (e.g., "चना दाल 50kg @ 68 = 3400", "प्याज 2 बोरी 80kg").
   - Extract item name, quantity, unit, and rate accurately.

PRICING & INDIAN CURRENCY RULES (STRICT):
- Rates in India often end with "/-" (e.g. "320/-", "340/-", "1,200/-") or have "Rs.", "Rs", "INR", "₹".
- ALL prices MUST be returned as INTEGER PAISE (1 Rupee = 100 paise):
  * "320/-" or "₹320" -> 32000
  * "340/-" -> 34000
  * "1200/-" -> 120000
  * "45.50" -> 4550
- If only one price is visible, use it for both selling_price_paise and purchase_price_paise.
- Never use null or decimals for paise values. Always use integers.

RESPONSE SCHEMA (JSON ONLY):
Return strictly valid JSON matching this exact structure, with no markdown code blocks, no backticks, no explanatory text:
{
  "supplier_name": "Supplier/Vendor name or empty string",
  "bill_number": "Invoice/slip number or empty string",
  "bill_date": "YYYY-MM-DD or empty string",
  "detected_document_type": "menu | invoice | slip | handwritten | catalog",
  "items": [
    {
      "product_name": "Clean product or dish name",
      "quantity": 1,
      "unit": "pcs",
      "purchase_price_paise": 32000,
      "mrp_paise": 32000,
      "selling_price_paise": 32000,
      "category_name": "Category or menu section",
      "is_veg": false,
      "barcode": "",
      "expiry_date": "",
      "batch_number": ""
    }
  ]
}
DO NOT RETURN AN EMPTY ITEMS ARRAY. Extract every line item that can be identified.`;
}

/** Calls Gemini, walking the model list until one answers. */
async function callGemini(apiKey, prompt, mimeType, base64Data) {
  let lastError = "No model responded";

  for (const model of AI_MODELS) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify({
            contents: [
              {
                parts: [
                  { text: prompt },
                  { inline_data: { mime_type: mimeType, data: base64Data } },
                ],
              },
            ],
            generationConfig: {
              temperature: 0.1,
              response_mime_type: "application/json",
            },
          }),
        }
      );

      if (!res.ok) {
        lastError = `${model}: HTTP ${res.status}`;
        // 404 = model retired, 429 = quota. Both are worth trying the next
        // model for; anything else usually is not, but the loop is cheap.
        continue;
      }

      const body = await res.json();
      const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) {
        lastError = `${model}: empty response`;
        continue;
      }

      const cleaned = text.replace(/```json/g, "").replace(/```/g, "").trim();
      return { ok: true, json: JSON.parse(cleaned), model };
    } catch (e) {
      lastError = `${model}: ${e.message}`;
    }
  }
  return { ok: false, error: lastError };
}

exports.aiExtract = onRequest(
  { secrets: [GEMINI_API_KEY], cors: true, region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    try {
      // 1. Who is asking — verified server-side, never trusted from the body.
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
      const bizId = `biz_${decoded.uid}`;

      // 2. What are they sending?
      const body = req.body || {};
      const kind = String(body.kind || "bill").toLowerCase();
      const clientVertical = String(body.business_type || "").trim().toLowerCase();
      const mimeType = String(body.mime_type || "image/jpeg");
      const dataB64 = String(body.data_base64 || "");

      if (!dataB64) {
        res.status(400).json({ error: "data_base64 is required" });
        return;
      }
      // base64 is ~4/3 of the raw size.
      if (dataB64.length * 0.75 > MAX_UPLOAD_BYTES) {
        res.status(413).json({ error: "File too large. Please use a smaller photo or a CSV/Excel file." });
        return;
      }
      if (kind !== "bill" && kind !== "menu") {
        res.status(400).json({ error: `Unknown kind "${kind}"` });
        return;
      }

      const db = getFirestore();
      const isImage = mimeType.startsWith("image/");

      // 3. Quota — server-side, so clearing app data no longer resets it.
      //    PDFs stay free and unlimited, matching the app's own copy.
      const monthKey = new Date().toISOString().slice(0, 7); // YYYY-MM
      const usageRef = db.collection("ai_usage").doc(`${bizId}_${monthKey}`);

      const bizSnap = await db.collection("businesses").doc(bizId).get();
      const b = bizSnap.exists ? bizSnap.data() : {};
      const merchantVertical = clientVertical || b?.business_type || "general retail";

      if (isImage) {
        const proExpiry = b?.pro_expiry ? Date.parse(b.pro_expiry) : 0;
        const isPro =
          !(b?.is_pro === false || b?.is_pro === 0) &&
          (b?.is_pro === true || b?.subscription_tier === "annual" || b?.subscription_tier === "monthly") &&
          (!proExpiry || proExpiry > Date.now());

        // A live trial counts as Pro for AI, same as everywhere else in the app.
        const trialStart = b?.trial_started_at ? Date.parse(b.trial_started_at) : 0;
        const inTrial = trialStart > 0 && Date.now() < trialStart + 7 * 24 * 60 * 60 * 1000;

        if (!isPro && !inTrial) {
          const usage = await usageRef.get();
          const used = usage.exists ? usage.data()?.image_scans || 0 : 0;
          if (used >= FREE_MONTHLY_IMAGE_SCANS) {
            res.status(429).json({
              error: `Free plan includes ${FREE_MONTHLY_IMAGE_SCANS} AI picture scans per month. Upgrade to Pro for unlimited scans, or use Excel / CSV inward (unlimited free).`,
              quota_exceeded: true,
              used,
              limit: FREE_MONTHLY_IMAGE_SCANS,
            });
            return;
          }
        }
      }

      // 4. Extract.
      // Dynamic key from Firestore platform_settings/ai_config, fallback to Secret Manager
      let activeApiKey = GEMINI_API_KEY.value();
      try {
        const configDoc = await db.collection("platform_settings").doc("ai_config").get();
        if (configDoc.exists) {
          const cfg = configDoc.data();
          if (cfg && typeof cfg.api_key === "string" && cfg.api_key.trim().length > 10) {
            activeApiKey = cfg.api_key.trim();
          }
        }
      } catch (e) {
        console.warn("[AI] Could not read platform_settings/ai_config, using secret:", e.message);
      }

      const prompt = buildUniversalAiPrompt(kind, merchantVertical);
      const result = await callGemini(
        activeApiKey,
        prompt,
        mimeType,
        dataB64
      );

      if (!result.ok) {
        console.error("[AI] extraction failed:", result.error);
        // Telemetry for Admin Console
        try {
          await db.collection("platform_settings").doc("ai_config").set(
            {
              status: result.error && result.error.includes("429") ? "quota_exhausted" : "error",
              last_error: result.error || "Unknown error",
              last_error_at: new Date().toISOString(),
            },
            { merge: true }
          );
        } catch (_) {}

        res.status(502).json({
          error: "AI could not read this file right now. Try the offline scan, or upload Excel / CSV.",
          detail: result.error,
        });
        return;
      }

      // Record successful health telemetry for Admin Console
      try {
        await db.collection("platform_settings").doc("ai_config").set(
          {
            status: "healthy",
            last_success_at: new Date().toISOString(),
            last_used_model: result.model || "gemini-3.6-flash",
          },
          { merge: true }
        );
      } catch (_) {}

      const rawItems = Array.isArray(result.json?.items) ? result.json.items : [];
      const cleanItems = rawItems
        .map((raw) => {
          let name = String(raw.product_name || raw.name || "").trim();
          // Strip leading numbering e.g. "21.", "1.", "1)", "#5", "- "
          name = name.replace(/^[\d#]+[\.\)\-\:\s]+/, "").trim();

          let sellPaise = Number(raw.selling_price_paise) || 0;
          let buyPaise = Number(raw.purchase_price_paise) || 0;
          let mrpPaise = Number(raw.mrp_paise) || 0;

          // Harmonize prices if one is present and others are 0
          if (sellPaise > 0 && buyPaise === 0) buyPaise = sellPaise;
          if (buyPaise > 0 && sellPaise === 0) sellPaise = buyPaise;
          if (mrpPaise === 0) mrpPaise = Math.max(sellPaise, buyPaise);

          let qty = Number(raw.quantity) || 1;
          let unit = String(raw.unit || "pcs").trim().toLowerCase();
          let category = String(raw.category_name || raw.category || "General").trim();

          // Smart non-veg detection across Indian cuisines
          const lowerName = name.toLowerCase();
          const lowerCat = category.toLowerCase();
          const nonVegTerms = [
            "chicken", "mutton", "fish", "egg", "anda", "murgh", "gosht",
            "keema", "prawn", "crab", "pork", "beef", "non-veg", "seafood",
            "kabab", "tikka", "duck", "meat"
          ];
          const isExplicitlyNonVeg = nonVegTerms.some(
            (term) => lowerName.includes(term) || lowerCat.includes(term)
          );

          let isVeg = raw.is_veg;
          if (isExplicitlyNonVeg) {
            isVeg = false;
          } else if (isVeg === undefined || isVeg === null) {
            isVeg = true;
          } else {
            isVeg = Boolean(isVeg);
          }

          return {
            product_name: name,
            quantity: qty,
            unit: unit || "pcs",
            purchase_price_paise: Math.round(buyPaise),
            mrp_paise: Math.round(mrpPaise),
            selling_price_paise: Math.round(sellPaise),
            category_name: category,
            is_veg: isVeg,
            barcode: String(raw.barcode || "").trim(),
            expiry_date: String(raw.expiry_date || "").trim(),
            batch_number: String(raw.batch_number || "").trim(),
          };
        })
        .filter((i) => i.product_name.length > 0);

      // 5. Only a scan that actually produced items costs the merchant one of
      //    their ten. A response that parsed to nothing used to still be
      //    counted on the device.
      if (isImage && cleanItems.length > 0) {
        await usageRef.set(
          {
            business_id: bizId,
            month: monthKey,
            image_scans: FieldValue.increment(1),
            last_scan_at: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      console.log(`[AI] ${kind} (${merchantVertical}) via ${result.model}: ${cleanItems.length} item(s) for ${bizId}`);
      res.status(200).json({
        ...result.json,
        items: cleanItems,
        detected_vertical: merchantVertical,
        model: result.model,
      });
    } catch (error) {
      console.error("[AI] aiExtract failed:", error);
      res.status(500).json({ error: "AI scan failed. Please try again." });
    }
  }
);
