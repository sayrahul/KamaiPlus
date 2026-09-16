const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();

const {
  resolveModels,
  buildUniversalAiPrompt,
  parseModelJson,
  normalizeExtractedItem,
  DEFAULT_AI_MODELS,
  istDayKey,
  FREE_DAILY_IMAGE_SCANS,
  PRO_DAILY_IMAGE_SCANS,
} = require("./ai_extract_core");

const {
  hasValidCheckDigit,
  normalizeBarcode,
  buildBarcodePrompt,
  normalizeBarcodeResult,
} = require("./barcode_core");

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

/** Hard ceiling on an upload. Keeps one bad request from burning the budget. */
const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;

/** HTTP statuses that mean "try again", as opposed to "this model is wrong". */
const TRANSIENT_STATUSES = new Set([429, 500, 502, 503, 504]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Calls Gemini, walking the model list until one answers.
 *
 * Two behaviours the previous version lacked:
 *
 * 1. maxOutputTokens. It was unset, so the response was capped at the model
 *    default. A dense menu page (a 60-dish rate card is ordinary) ran past that
 *    cap, the JSON was cut off mid-object, JSON.parse threw, and the merchant
 *    got "AI could not read this file" for a photo the model had read fine.
 *    MAX_AI_OUTPUT_TOKENS is sized for roughly 200 items.
 *
 * 2. Retry on transient failures. A single 429 or 503 on the good model used to
 *    fall straight through to the weaker models and then to a 502, which is how
 *    a working setup still produced "offline OCR" junk for the merchant.
 */
const MAX_AI_OUTPUT_TOKENS = 16384;

async function callGemini(apiKey, prompt, mimeType, base64Data, models) {
  let lastError = "No model responded";
  const list = Array.isArray(models) && models.length ? models : DEFAULT_AI_MODELS;

  for (const model of list) {
    // Only the first-choice model is worth waiting on; after that, move down
    // the list rather than making the merchant stare at the scanning dialog.
    const attempts = model === list[0] ? 3 : 1;

    for (let attempt = 1; attempt <= attempts; attempt++) {
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
                // Near-zero: this is transcription, not writing. Any creativity
                // here shows up as an invented dish in someone's catalog.
                temperature: 0.05,
                response_mime_type: "application/json",
                maxOutputTokens: MAX_AI_OUTPUT_TOKENS,
              },
            }),
          }
        );

        if (!res.ok) {
          lastError = `${model}: HTTP ${res.status}`;
          if (TRANSIENT_STATUSES.has(res.status) && attempt < attempts) {
            await sleep(700 * attempt);
            continue;
          }
          break; // 400/403/404 — a different model is the only hope.
        }

        const body = await res.json();
        const candidate = body?.candidates?.[0];
        const text = candidate?.content?.parts?.[0]?.text;

        if (!text) {
          // A safety block or a MAX_TOKENS stop with no text — say which, so
          // the Admin Console's last_error is actionable instead of "empty".
          const reason =
            candidate?.finishReason ||
            body?.promptFeedback?.blockReason ||
            "empty response";
          lastError = `${model}: ${reason}`;
          break;
        }

        const json = parseModelJson(text);
        return { ok: true, json, model, truncated: candidate?.finishReason === "MAX_TOKENS" };
      } catch (e) {
        lastError = `${model}: ${e.message}`;
        if (attempt < attempts) {
          await sleep(700 * attempt);
          continue;
        }
      }
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
      const dayKey = istDayKey();
      const usageRef = db.collection("ai_usage").doc(`${bizId}_${dayKey}`);

      const bizSnap = await db.collection("businesses").doc(bizId).get();
      const b = bizSnap.exists ? bizSnap.data() : {};
      const merchantVertical = clientVertical || b?.business_type || "general retail";

      let dailyLimit = FREE_DAILY_IMAGE_SCANS;
      let usedToday = 0;

      if (isImage) {
        const proExpiry = b?.pro_expiry ? Date.parse(b.pro_expiry) : 0;
        const isPaidPro =
          !(b?.is_pro === false || b?.is_pro === 0) &&
          (b?.is_pro === true || b?.subscription_tier === "annual" || b?.subscription_tier === "monthly") &&
          (!proExpiry || proExpiry > Date.now());

        // A live trial unlocks the FEATURE, but is metered at the free rate.
        const trialStart = b?.trial_started_at ? Date.parse(b.trial_started_at) : 0;
        const inTrial = trialStart > 0 && Date.now() < trialStart + 7 * 24 * 60 * 60 * 1000;

        dailyLimit = isPaidPro ? PRO_DAILY_IMAGE_SCANS : FREE_DAILY_IMAGE_SCANS;

        const usage = await usageRef.get();
        usedToday = usage.exists ? usage.data()?.image_scans || 0 : 0;

        if (usedToday >= dailyLimit) {
          res.status(429).json({
            error: isPaidPro
              ? `You have used all ${PRO_DAILY_IMAGE_SCANS} Pro AI scans for today. The limit resets at midnight. Excel / CSV inward stays unlimited.`
              : `${inTrial ? "Trial" : "Free"} plan includes ${FREE_DAILY_IMAGE_SCANS} AI picture scans per day. ` +
                `Upgrade to Pro for ${PRO_DAILY_IMAGE_SCANS} per day, or use Excel / CSV inward (unlimited free).`,
            quota_exceeded: true,
            used: usedToday,
            limit: dailyLimit,
            is_pro: isPaidPro,
            resets_at: `${dayKey} 24:00 IST`,
          });
          return;
        }
      }

      // 4. Extract.
      // Dynamic key AND model order from Firestore platform_settings/ai_config,
      // falling back to Secret Manager and the built-in list.
      let activeApiKey = GEMINI_API_KEY.value();
      let aiConfig = null;
      try {
        const configDoc = await db.collection("platform_settings").doc("ai_config").get();
        if (configDoc.exists) {
          aiConfig = configDoc.data() || null;
          if (aiConfig && typeof aiConfig.api_key === "string" && aiConfig.api_key.trim().length > 10) {
            activeApiKey = aiConfig.api_key.trim();
          }
        }
      } catch (e) {
        console.warn("[AI] Could not read platform_settings/ai_config, using secret:", e.message);
      }

      if (!activeApiKey || activeApiKey.trim().length < 10) {
        console.error("[AI] No usable Gemini API key (neither ai_config.api_key nor the GEMINI_API_KEY secret)");
        res.status(503).json({
          error: "AI scanning is not configured yet. Please contact support.",
          detail: "missing_api_key",
        });
        return;
      }

      const prompt = buildUniversalAiPrompt(kind, merchantVertical);
      const result = await callGemini(
        activeApiKey,
        prompt,
        mimeType,
        dataB64,
        resolveModels(aiConfig)
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
            last_used_model: result.model || "unknown",
          },
          { merge: true }
        );
      } catch (_) {}

      const rawItems = Array.isArray(result.json?.items) ? result.json.items : [];
      const cleanItems = rawItems
        .map((raw) => normalizeExtractedItem(raw, kind))
        .filter((i) => i !== null);

      // 5. Only a scan that actually produced items costs the merchant one of
      //    their ten. A response that parsed to nothing used to still be
      //    counted on the device.
      if (isImage && cleanItems.length > 0) {
        await usageRef.set(
          {
            business_id: bizId,
            day: dayKey,
            image_scans: FieldValue.increment(1),
            last_scan_at: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      console.log(
        `[AI] ${kind} (${merchantVertical}) via ${result.model}: ` +
          `${cleanItems.length}/${rawItems.length} item(s) for ${bizId}` +
          (result.truncated ? " [TRUNCATED — raise MAX_AI_OUTPUT_TOKENS]" : "")
      );

      // The model answered but nothing survived normalization (every row was a
      // header, or a menu row had no price). Reporting 200 with an empty list
      // told the app "success", and it opened an empty review sheet; a 422
      // lets the app say something true instead.
      if (cleanItems.length === 0) {
        res.status(422).json({
          error:
            kind === "menu"
              ? "No dishes with prices could be read from this photo. Try again with the menu filling the frame, in good light."
              : "No line items could be read from this bill. Try a closer, brighter photo, or use Excel / CSV inward.",
          detail: `model returned ${rawItems.length} row(s), none usable`,
          model: result.model,
        });
        return;
      }

      res.status(200).json({
        ...result.json,
        items: cleanItems,
        detected_vertical: merchantVertical,
        model: result.model,
        truncated: Boolean(result.truncated),
        // So the app can render "N scans left today" without a second call.
        // usedToday was read before this scan was counted, hence the +1.
        quota: isImage
          ? { used: usedToday + 1, limit: dailyLimit, remaining: Math.max(0, dailyLimit - usedToday - 1) }
          : null,
      });
    } catch (error) {
      console.error("[AI] aiExtract failed:", error);
      res.status(500).json({ error: "AI scan failed. Please try again." });
    }
  }
);

// ============================================================================
// BARCODE RESOLUTION PROXY  (barcode -> product name / brand / category)
// ----------------------------------------------------------------------------
// Resolution ladder, cheapest first:
//   1. barcode_catalog/{gtin} — the shared catalog every merchant's scans build.
//   2. Open* Facts family, five hosts in parallel (free, no key).
//   3. UPCitemdb trial (free, no key, IP rate-limited — hence after Facts).
//   4. Gemini, text-only, as an explicitly-flagged guess.
//
// Tier 1 is the reason this is server-side. Open Facts has roughly 23,000
// Indian products, so a real barcode often resolves — but only the first
// merchant to scan it should pay for the lookup. Every hit written here makes
// the next shop's scan a single indexed read.
// ============================================================================

/** Shared catalog rows older than this are re-checked against the sources. */
const BARCODE_CACHE_TTL_DAYS = 120;

/** One lookup must never hold the counter for longer than this. */
const BARCODE_SOURCE_TIMEOUT_MS = 4000;

const FACTS_HOSTS = [
  "https://in.openfoodfacts.org",
  "https://world.openfoodfacts.org",
  "https://world.openbeautyfacts.org",
  "https://world.openproductsfacts.org",
  "https://world.openpetfoodfacts.org",
];

const FACTS_FIELDS =
  "product_name,product_name_en,generic_name,generic_name_en,brands,categories,quantity";

async function fetchJsonWithTimeout(url, ms = BARCODE_SOURCE_TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent": "KamaiPlus-POS/4.23 (india-retail-counter)",
        Accept: "application/json",
      },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Tier 2 — all five Facts hosts at once; host order is priority order. */
async function queryFactsFamily(barcode) {
  const results = await Promise.all(
    FACTS_HOSTS.map(async (host) => {
      const json = await fetchJsonWithTimeout(
        `${host}/api/v2/product/${barcode}.json?fields=${FACTS_FIELDS}`
      );
      if (!json || json.status !== 1) return null;
      const p = json.product;
      if (!p || typeof p !== "object") return null;
      const name = p.product_name_en || p.product_name || p.generic_name_en || p.generic_name;
      if (!name) return null;
      return { name, brand: p.brands, category: p.categories, pack_size: p.quantity };
    })
  );
  return results.find(Boolean) || null;
}

/** Tier 3 — general merchandise the Facts family does not index. */
async function queryUpcItemDb(barcode) {
  const json = await fetchJsonWithTimeout(
    `https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`
  );
  const items = json?.items;
  if (!Array.isArray(items) || !items.length) return null;
  const item = items[0];
  if (!item?.title) return null;
  return {
    name: item.title,
    brand: item.brand || item.manufacturer,
    category: item.category,
    pack_size: item.size || item.weight,
  };
}

/** Tier 4 — Gemini, text only. Cheap, but a recollection, never a fact. */
async function queryGeminiForBarcode(apiKey, barcode, models) {
  const prompt = buildBarcodePrompt(barcode);
  const list = Array.isArray(models) && models.length ? models : DEFAULT_AI_MODELS;

  for (const model of list) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: {
              temperature: 0,
              response_mime_type: "application/json",
              maxOutputTokens: 512,
            },
          }),
        }
      );
      if (!res.ok) continue;
      const body = await res.json();
      const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) continue;

      const json = parseModelJson(text);
      if (!json || json.known !== true) return null; // an honest "no" — respect it
      // A low-confidence recollection is worth less than an empty field.
      if (json.confidence && String(json.confidence).toLowerCase() === "low") return null;
      return json;
    } catch (_) {
      /* try the next model */
    }
  }
  return null;
}

exports.resolveBarcode = onRequest(
  { secrets: [GEMINI_API_KEY], cors: true, region: "us-central1", memory: "256MiB", timeoutSeconds: 30 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "POST only" });
      return;
    }

    try {
      const header = req.get("Authorization") || "";
      const idToken = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
      if (!idToken) {
        res.status(401).json({ error: "Missing Authorization bearer token" });
        return;
      }
      try {
        await getAuth().verifyIdToken(idToken);
      } catch (_) {
        res.status(401).json({ error: "Invalid or expired ID token" });
        return;
      }

      const barcode = normalizeBarcode(req.body?.barcode);
      if (!barcode) {
        res.status(400).json({ error: "barcode is required (8-14 digits)" });
        return;
      }

      // A wrong check digit means a misread or a shop's own printed label.
      // No global repository can know it, so answering immediately is both
      // correct and much faster than four lookups that must all miss.
      if (!hasValidCheckDigit(barcode)) {
        res.status(200).json({ found: false, reason: "invalid_check_digit", barcode });
        return;
      }

      const db = getFirestore();
      const cacheRef = db.collection("barcode_catalog").doc(barcode);

      // TIER 1 — the shared catalog.
      try {
        const snap = await cacheRef.get();
        if (snap.exists) {
          const row = snap.data() || {};
          const ageMs = row.resolved_at ? Date.now() - Date.parse(row.resolved_at) : 0;
          const fresh = ageMs < BARCODE_CACHE_TTL_DAYS * 24 * 60 * 60 * 1000;
          // A cached miss is only honoured for AI-unknown rows; a database
          // that had no answer in March may well have one now.
          if (row.found === true && fresh) {
            await cacheRef.set(
              { hits: FieldValue.increment(1), last_hit_at: new Date().toISOString() },
              { merge: true }
            );
            res.status(200).json({ found: true, ...row.product, cached: true });
            return;
          }
        }
      } catch (e) {
        console.warn("[BARCODE] cache read failed:", e.message);
      }

      // TIERS 2 & 3 — free public repositories.
      let hit = null;
      let source = "";

      const facts = await queryFactsFamily(barcode);
      if (facts) {
        hit = facts;
        source = "Open Facts";
      }
      if (!hit) {
        const upc = await queryUpcItemDb(barcode);
        if (upc) {
          hit = upc;
          source = "UPCitemdb";
        }
      }

      let isAiGuess = false;

      // TIER 4 — Gemini, only once the free databases have all missed.
      if (!hit) {
        let activeApiKey = GEMINI_API_KEY.value();
        let aiConfig = null;
        try {
          const cfg = await db.collection("platform_settings").doc("ai_config").get();
          if (cfg.exists) {
            aiConfig = cfg.data() || null;
            if (aiConfig?.api_key && String(aiConfig.api_key).trim().length > 10) {
              activeApiKey = String(aiConfig.api_key).trim();
            }
          }
        } catch (_) {}

        if (activeApiKey && activeApiKey.length > 10) {
          const guess = await queryGeminiForBarcode(activeApiKey, barcode, resolveModels(aiConfig));
          if (guess) {
            hit = guess;
            source = "AI";
            isAiGuess = true;
          }
        }
      }

      const product = normalizeBarcodeResult(hit, { source, isAiGuess });

      if (!product) {
        // Remember the miss so the next scan of this barcode is one read, not
        // four lookups — but only briefly, since coverage improves over time.
        try {
          await cacheRef.set(
            { found: false, barcode, resolved_at: new Date().toISOString() },
            { merge: true }
          );
        } catch (_) {}
        console.log(`[BARCODE] ${barcode}: not found in any source`);
        res.status(200).json({ found: false, barcode });
        return;
      }

      // Write through, so the next merchant to scan this gets one indexed read.
      try {
        await cacheRef.set(
          {
            found: true,
            barcode,
            product,
            resolved_at: new Date().toISOString(),
            hits: FieldValue.increment(1),
          },
          { merge: true }
        );
      } catch (e) {
        console.warn("[BARCODE] cache write failed:", e.message);
      }

      console.log(`[BARCODE] ${barcode} -> "${product.name}" via ${source}`);
      res.status(200).json({ found: true, ...product, cached: false });
    } catch (error) {
      console.error("[BARCODE] resolveBarcode failed:", error);
      res.status(500).json({ error: "Barcode lookup failed." });
    }
  }
);
