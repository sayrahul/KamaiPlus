// Refer & Earn — server-side logic for the `referral` Cloud Function.
//
// Why this runs on the server: a referral grants Pro days to TWO accounts,
// and firestore.rules forbid any client from writing Pro fields
// (`is_pro`, `pro_plan`, `pro_expiry`, ...) — on its own business, let alone
// on someone else's. The previous client-only flow read and wrote
// `referral_codes/*` and the referrer's `businesses/*` doc straight from the
// phone; the rules deny all of it, so every claim failed with "check your
// internet connection" and no referrer was ever credited.
//
// The offer:
//   * the friend who ACCEPTS an invite keeps the normal 7-day welcome trial
//     and gets `refereeDays` (15) more on top of it — 7 + 15 = 22 days;
//   * the merchant who SENT the invite gets `referrerDays` (30) added to
//     whatever Pro time they already have.
// Days always stack onto the later of: now, the current Pro expiry, and the
// end of the 7-day trial — so a bonus never overlaps time already owned.
//
// Everything here takes its Firestore handle, clock and FieldValue as
// arguments, so test/referral_core.test.js can drive it against an in-memory
// fake that enforces Firestore's transaction rules.

const crypto = require("node:crypto");

const DAY_MS = 24 * 60 * 60 * 1000;
const TRIAL_DAYS = 7;
const DEFAULT_REFERRER_DAYS = 30;
const DEFAULT_REFEREE_DAYS = 15;
const PAID_PLANS = new Set(["monthly", "annual"]);

// KAMAI + 4 characters today; up to 8 accepted so a longer collision
// fallback stays valid. No I, O, 0 or 1 — they are misread when typed.
const CODE_RE = /^KAMAI[A-Z0-9]{4,8}$/;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

class ReferralError extends Error {
  constructor(code, message, httpStatus = 400) {
    super(message);
    this.code = code;
    this.httpStatus = httpStatus;
  }
}

function normalizeReferralCode(raw) {
  return String(raw ?? "").trim().toUpperCase().replace(/\s+/g, "");
}

function isValidReferralCode(code) {
  return CODE_RE.test(code);
}

function randomReferralCode(randomInt = crypto.randomInt) {
  let suffix = "";
  for (let i = 0; i < 4; i++) suffix += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return `KAMAI${suffix}`;
}

/** ISO string, Date, Firestore Timestamp or epoch ms -> Date (or null). */
function parseDate(value) {
  if (value == null || value === "") return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value.toDate === "function") return value.toDate();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function isExplicitlyNotPro(biz) {
  return biz?.is_pro === false || biz?.is_pro === 0;
}

function storedExpiry(biz) {
  return (
    parseDate(biz?.pro_expiry) ||
    parseDate(biz?.subscription_expires_at) ||
    parseDate(biz?.subscription_valid_until)
  );
}

/** Pro with no expiry at all — an open-ended admin grant. Never shortened. */
function isOpenEndedPro(biz) {
  return biz?.is_pro === true && !storedExpiry(biz);
}

/** The Pro expiry stored in the cloud, if it is still in the future. */
function activeProExpiry(biz, now) {
  if (!biz || isExplicitlyNotPro(biz)) return null;
  const exp = storedExpiry(biz);
  return exp && exp > now ? exp : null;
}

/** End of the 7-day welcome trial. The device syncs `trial_started_at`. */
function trialEnd(biz, fallbackStart) {
  const start = parseDate(biz?.trial_started_at) || parseDate(fallbackStart);
  return start ? new Date(start.getTime() + TRIAL_DAYS * DAY_MS) : null;
}

/** New days start from the latest of: now, current Pro expiry, trial end. */
function grantBase(biz, now, trialFallbackStart) {
  let base = now;
  for (const d of [activeProExpiry(biz, now), trialEnd(biz, trialFallbackStart)]) {
    if (d && d > base) base = d;
  }
  return base;
}

function addDays(date, days) {
  return new Date(date.getTime() + days * DAY_MS);
}

function hasActivePaidPlan(biz, now) {
  const plan = String(biz?.pro_plan || biz?.subscription_tier || "").toLowerCase();
  return PAID_PLANS.has(plan) && activeProExpiry(biz, now) != null;
}

/**
 * The Pro fields to merge onto a business doc. A paying merchant keeps their
 * plan name — the app shows the "already Pro" screen for annual/monthly, and
 * a referral must not relabel a paid subscription as a free one.
 */
function buildProGrant(biz, newExpiry, grantedBy, now) {
  const iso = newExpiry.toISOString();
  const fields = {
    is_pro: true,
    pro_plan: hasActivePaidPlan(biz, now) ? biz.pro_plan || biz.subscription_tier : "referral_bonus",
    pro_expiry: iso,
    pro_granted_by: grantedBy,
  };
  // Keep the alternative expiry fields in step where they already exist, so
  // no reader sees two different end dates.
  if (biz?.subscription_expires_at != null) fields.subscription_expires_at = iso;
  if (biz?.subscription_valid_until != null) fields.subscription_valid_until = iso;
  return fields;
}

function clampDays(value, fallback) {
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || n < 0) return fallback;
  return Math.min(n, 365);
}

/**
 * Reward days from a Remote Config template, so the server grants exactly
 * what the app's copy promises (`referral_reward_days` is already a Remote
 * Config key the app reads). Falls back to 30 / 15.
 */
function rewardDaysFromTemplate(template) {
  const read = (key) => template?.parameters?.[key]?.defaultValue?.value;
  return {
    referrerDays: clampDays(read("referral_reward_days"), DEFAULT_REFERRER_DAYS),
    refereeDays: clampDays(read("referral_referee_bonus_days"), DEFAULT_REFEREE_DAYS),
  };
}

function bizRef(db, uid) {
  return db.collection("businesses").doc(`biz_${uid}`);
}

// ---------------------------------------------------------------------------
// action: "status" — this merchant's code (created on first call) + stats
// ---------------------------------------------------------------------------

/**
 * Returns the merchant's referral code, creating it on first use.
 *
 * `preferredCode` is the code the device already has cached. Codes were
 * generated on the phone before, and some have been shared on WhatsApp
 * without ever reaching the server (the rules blocked the write), so a
 * cached code is registered for this merchant when it is still free.
 */
async function executeStatus({ db, FieldValue, uid, preferredCode, now, randomCode = randomReferralCode }) {
  const codes = db.collection("referral_codes");
  let codeDoc = null;

  const owned = await codes.where("merchant_id", "==", uid).limit(1).get();
  if (!owned.empty) {
    codeDoc = { id: owned.docs[0].id, data: owned.docs[0].data() };
  } else {
    const preferred = normalizeReferralCode(preferredCode);
    const candidates = [];
    if (isValidReferralCode(preferred)) candidates.push(preferred);
    for (let i = 0; i < 8; i++) candidates.push(randomCode());

    for (const candidate of candidates) {
      const ref = codes.doc(candidate);
      const claimed = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.exists) return snap.data().merchant_id === uid ? snap.data() : null;
        const data = {
          merchant_id: uid,
          created_at: FieldValue.serverTimestamp(),
          activated_count: 0,
          free_days_earned: 0,
        };
        tx.set(ref, data);
        return data;
      });
      if (claimed) {
        codeDoc = { id: candidate, data: claimed };
        break;
      }
    }
    if (!codeDoc) throw new ReferralError("CODE_UNAVAILABLE", "Could not create a referral code. Please try again.", 503);
  }

  const redemption = await db.collection("referral_redemptions").doc(uid).get();
  const r = redemption.exists ? redemption.data() : null;
  const biz = await bizRef(db, uid).get();
  const expiry = activeProExpiry(biz.exists ? biz.data() : null, now);

  return {
    code: codeDoc.id,
    activated_count: Number(codeDoc.data.activated_count) || 0,
    free_days_earned: Number(codeDoc.data.free_days_earned) || 0,
    applied_code: r ? r.code : null,
    referee_bonus_days: r ? r.referee_bonus_days : null,
    pro_expiry: expiry ? expiry.toISOString() : null,
  };
}

// ---------------------------------------------------------------------------
// action: "redeem" — the invited merchant claims a friend's code
// ---------------------------------------------------------------------------

/**
 * One Firestore transaction: validate the code, credit BOTH merchants, bump
 * the referrer's counters and record the redemption, all or nothing.
 *
 * `refereeCreatedAt` is the referee's Firebase Auth creation time. At signup
 * the redeem call can reach the server before the device's first sync has
 * written `trial_started_at`; the account creation time stands in for the
 * trial start so the 15 days still land after the 7-day trial.
 */
async function executeRedeem({
  db,
  FieldValue,
  uid,
  rawCode,
  now,
  refereeCreatedAt = null,
  referrerDays = DEFAULT_REFERRER_DAYS,
  refereeDays = DEFAULT_REFEREE_DAYS,
}) {
  const code = normalizeReferralCode(rawCode);
  if (!isValidReferralCode(code)) {
    throw new ReferralError(
      "INVALID_FORMAT",
      "That is not a valid Kamai+ referral code (it looks like KAMAI7XK2)."
    );
  }

  const codeRef = db.collection("referral_codes").doc(code);
  const redemptionRef = db.collection("referral_redemptions").doc(uid);
  const refereeRef = bizRef(db, uid);

  return db.runTransaction(async (tx) => {
    // ---- reads (Firestore requires every read before any write) ----
    const [codeSnap, redemptionSnap, refereeSnap] = await Promise.all([
      tx.get(codeRef),
      tx.get(redemptionRef),
      tx.get(refereeRef),
    ]);

    if (!codeSnap.exists || !codeSnap.data().merchant_id) {
      throw new ReferralError("NOT_FOUND", "Invalid referral code. Please check the code and try again.", 404);
    }
    const referrerUid = codeSnap.data().merchant_id;
    if (referrerUid === uid) {
      throw new ReferralError("SELF", "You cannot use your own referral code!");
    }

    const refereeBiz = refereeSnap.exists ? refereeSnap.data() : null;

    if (redemptionSnap.exists) {
      const prior = redemptionSnap.data();
      if (prior.code !== code) {
        throw new ReferralError(
          "ALREADY_REDEEMED",
          `You have already claimed a referral code (${prior.code}).`,
          409
        );
      }
      // Same code again — a retry after a dropped connection. Report the
      // standing result; grant nothing twice.
      const current = activeProExpiry(refereeBiz, now);
      return {
        ok: true,
        already_redeemed: true,
        code,
        referee_bonus_days: prior.referee_bonus_days,
        pro_plan: refereeBiz?.pro_plan || "referral_bonus",
        pro_expiry: (current || parseDate(prior.referee_new_expiry)).toISOString(),
      };
    }

    const referrerRef = bizRef(db, referrerUid);
    const referrerRedemptionRef = db.collection("referral_redemptions").doc(referrerUid);
    const [referrerSnap, referrerRedemptionSnap] = await Promise.all([
      tx.get(referrerRef),
      tx.get(referrerRedemptionRef),
    ]);

    // A joined B with B's code; B now tries A's code. Two accounts trading
    // codes back and forth would otherwise mint 45 days each for nothing.
    if (referrerRedemptionSnap.exists && referrerRedemptionSnap.data().referrer_uid === uid) {
      throw new ReferralError(
        "MUTUAL",
        "This merchant joined Kamai+ with your code, so you cannot use theirs.",
        409
      );
    }

    const referrerBiz = referrerSnap.exists ? referrerSnap.data() : null;

    // ---- compute ----
    const refereeOpenEnded = isOpenEndedPro(refereeBiz);
    const referrerOpenEnded = isOpenEndedPro(referrerBiz);
    const refereeExpiry = addDays(grantBase(refereeBiz, now, refereeCreatedAt), refereeDays);
    const referrerExpiry = addDays(grantBase(referrerBiz, now, null), referrerDays);
    const refereeGrant = refereeOpenEnded ? null : buildProGrant(refereeBiz, refereeExpiry, "referral_bonus", now);

    // ---- writes ----
    if (!refereeOpenEnded) {
      tx.set(
        refereeRef,
        {
          ...refereeGrant,
          referred_by_code: code,
          referred_by_uid: referrerUid,
          pro_activated_at: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      tx.set(
        db.collection("merchants").doc(uid),
        { is_pro: true, subscription_expires_at: refereeExpiry.toISOString(), updated_at: FieldValue.serverTimestamp() },
        { merge: true }
      );
    }
    if (!referrerOpenEnded) {
      tx.set(
        referrerRef,
        {
          ...buildProGrant(referrerBiz, referrerExpiry, "referral_reward", now),
          referral_days_earned: FieldValue.increment(referrerDays),
          pro_activated_at: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      tx.set(
        db.collection("merchants").doc(referrerUid),
        { is_pro: true, subscription_expires_at: referrerExpiry.toISOString(), updated_at: FieldValue.serverTimestamp() },
        { merge: true }
      );
    }
    tx.set(
      codeRef,
      {
        activated_count: FieldValue.increment(1),
        free_days_earned: FieldValue.increment(referrerDays),
        last_redeemed_at: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    tx.set(redemptionRef, {
      code,
      referrer_uid: referrerUid,
      referee_uid: uid,
      referee_bonus_days: refereeDays,
      referrer_reward_days: referrerDays,
      referee_new_expiry: refereeOpenEnded ? null : refereeExpiry.toISOString(),
      referrer_new_expiry: referrerOpenEnded ? null : referrerExpiry.toISOString(),
      redeemed_at: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      already_redeemed: false,
      code,
      referee_bonus_days: refereeDays,
      referrer_reward_days: referrerDays,
      pro_plan: refereeGrant ? refereeGrant.pro_plan : refereeBiz.pro_plan || "pro",
      pro_expiry: refereeOpenEnded ? null : refereeExpiry.toISOString(),
    };
  });
}

module.exports = {
  DAY_MS,
  TRIAL_DAYS,
  DEFAULT_REFERRER_DAYS,
  DEFAULT_REFEREE_DAYS,
  ReferralError,
  normalizeReferralCode,
  isValidReferralCode,
  randomReferralCode,
  parseDate,
  activeProExpiry,
  trialEnd,
  grantBase,
  buildProGrant,
  rewardDaysFromTemplate,
  executeStatus,
  executeRedeem,
};
