// Run with:  npm --prefix functions test
//
// Refer & Earn server logic, driven end to end against an in-memory Firestore
// fake. The fake enforces the rule that bites real transactions — every read
// must happen before the first write — so an ordering mistake in
// executeRedeem fails here instead of in production.
//
// Offer under test: the invited merchant gets the 7-day trial + 15 days;
// the merchant who invited them gets +30 days on top of what they have.

const test = require("node:test");
const assert = require("node:assert");

const {
  DAY_MS,
  ReferralError,
  normalizeReferralCode,
  isValidReferralCode,
  randomReferralCode,
  grantBase,
  rewardDaysFromTemplate,
  executeStatus,
  executeRedeem,
} = require("../referral_core");

// ---------------------------------------------------------------------------
// In-memory Firestore fake (just the surface referral_core uses)
// ---------------------------------------------------------------------------

const FieldValue = {
  increment: (n) => ({ __op: "inc", n }),
  serverTimestamp: () => ({ __op: "ts" }),
};

function applyWrite(existing, data, merge, now) {
  const out = merge && existing ? { ...existing } : {};
  for (const [k, v] of Object.entries(data)) {
    if (v && v.__op === "inc") out[k] = (Number(out[k]) || 0) + v.n;
    else if (v && v.__op === "ts") out[k] = now;
    else out[k] = v;
  }
  return out;
}

class FakeDb {
  constructor(now) {
    this.docs = new Map();
    this.now = now;
  }
  collection(name) {
    return new FakeCollection(this, name);
  }
  seed(path, data) {
    this.docs.set(path, { ...data });
  }
  read(path) {
    return this.docs.get(path);
  }
  async runTransaction(fn) {
    const tx = new FakeTx(this);
    const result = await fn(tx);
    tx.commit();
    return result;
  }
}

class FakeCollection {
  constructor(db, name) {
    this.db = db;
    this.name = name;
    this.filters = [];
    this.max = Infinity;
  }
  doc(id) {
    return new FakeDocRef(this.db, `${this.name}/${id}`, id);
  }
  where(field, op, value) {
    assert.strictEqual(op, "==");
    const q = new FakeCollection(this.db, this.name);
    q.filters = [...this.filters, [field, value]];
    return q;
  }
  limit(n) {
    this.max = n;
    return this;
  }
  async get() {
    const docs = [];
    for (const [path, data] of this.db.docs) {
      const [col, id] = path.split("/");
      if (col !== this.name || path.split("/").length !== 2) continue;
      if (this.filters.every(([f, v]) => data[f] === v)) docs.push({ id, data: () => ({ ...data }) });
    }
    return { empty: docs.length === 0, docs: docs.slice(0, this.max) };
  }
}

class FakeDocRef {
  constructor(db, path, id) {
    this.db = db;
    this.path = path;
    this.id = id;
  }
  async get() {
    const data = this.db.read(this.path);
    return { exists: data !== undefined, id: this.id, data: () => (data ? { ...data } : undefined) };
  }
}

class FakeTx {
  constructor(db) {
    this.db = db;
    this.writes = [];
  }
  async get(ref) {
    if (this.writes.length) throw new Error("Firestore transactions require all reads before writes");
    return ref.get();
  }
  set(ref, data, opts = {}) {
    this.writes.push([ref.path, data, !!opts.merge]);
  }
  commit() {
    for (const [path, data, merge] of this.writes) {
      this.db.docs.set(path, applyWrite(this.db.read(path), data, merge, this.db.now));
    }
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const NOW = new Date("2026-09-19T10:00:00.000Z");
const days = (n) => n * DAY_MS;
const iso = (ms) => new Date(ms).toISOString();

function world() {
  const db = new FakeDb(NOW);
  // Referrer Asha: on day 3 of her 7-day trial, owns code KAMAIASHA.
  db.seed("referral_codes/KAMAIASHA", { merchant_id: "asha", activated_count: 0, free_days_earned: 0 });
  db.seed("businesses/biz_asha", { name: "Asha Kirana", trial_started_at: iso(NOW - days(3)) });
  // Invitee Ravi: signed up a minute ago; first sync already ran.
  db.seed("businesses/biz_ravi", { name: "Ravi Stores", trial_started_at: iso(NOW - 60 * 1000) });
  return db;
}

const redeem = (db, uid, code, extra = {}) =>
  executeRedeem({ db, FieldValue, uid, rawCode: code, now: NOW, ...extra });

// ---------------------------------------------------------------------------
// Codes
// ---------------------------------------------------------------------------

test("codes are normalised and validated", () => {
  assert.strictEqual(normalizeReferralCode("  kamai 7xk2 "), "KAMAI7XK2");
  assert.ok(isValidReferralCode("KAMAI7XK2"));
  assert.ok(isValidReferralCode("KAMAI7711"), "legacy phone-suffix codes stay valid");
  assert.ok(!isValidReferralCode("KAMAI"));
  assert.ok(!isValidReferralCode("HELLO1234"));
  assert.match(randomReferralCode(), /^KAMAI[A-HJ-NP-Z2-9]{4}$/);
});

test("status creates a code on first use and returns the same one after", async () => {
  const db = new FakeDb(NOW);
  const first = await executeStatus({ db, FieldValue, uid: "neha", now: NOW, randomCode: () => "KAMAINEW1" });
  assert.strictEqual(first.code, "KAMAINEW1");
  assert.strictEqual(db.read("referral_codes/KAMAINEW1").merchant_id, "neha");

  const again = await executeStatus({ db, FieldValue, uid: "neha", now: NOW, randomCode: () => "KAMAIOTHR" });
  assert.strictEqual(again.code, "KAMAINEW1");
});

test("status registers the code already cached on the phone when it is free", async () => {
  const db = new FakeDb(NOW);
  const out = await executeStatus({ db, FieldValue, uid: "neha", preferredCode: "kamai7xk2", now: NOW });
  assert.strictEqual(out.code, "KAMAI7XK2", "a code already shared on WhatsApp keeps working");
});

test("status never hands out a code owned by another merchant", async () => {
  const db = world();
  const out = await executeStatus({
    db,
    FieldValue,
    uid: "neha",
    preferredCode: "KAMAIASHA",
    now: NOW,
    randomCode: () => "KAMAINEHA",
  });
  assert.strictEqual(out.code, "KAMAINEHA");
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").merchant_id, "asha");
});

// ---------------------------------------------------------------------------
// Redeem — the offer itself
// ---------------------------------------------------------------------------

test("invitee gets 7-day trial + 15 days; inviter gets +30 on top of her trial", async () => {
  const db = world();
  const out = await redeem(db, "ravi", "kamaiasha");

  const ravi = db.read("businesses/biz_ravi");
  const raviTrialStart = NOW.getTime() - 60 * 1000;
  assert.strictEqual(ravi.pro_expiry, iso(raviTrialStart + days(7 + 15)), "7 + 15 = 22 days from signup");
  assert.strictEqual(ravi.is_pro, true);
  assert.strictEqual(ravi.pro_plan, "referral_bonus");
  assert.strictEqual(ravi.referred_by_code, "KAMAIASHA");
  assert.strictEqual(out.pro_expiry, ravi.pro_expiry, "the app applies exactly what the cloud stored");
  assert.strictEqual(out.referee_bonus_days, 15);

  const asha = db.read("businesses/biz_asha");
  const ashaTrialStart = NOW.getTime() - days(3);
  assert.strictEqual(asha.pro_expiry, iso(ashaTrialStart + days(7 + 30)), "trial end + 30, not now + 30");
  assert.strictEqual(asha.is_pro, true);
  assert.strictEqual(asha.referral_days_earned, 30);

  const code = db.read("referral_codes/KAMAIASHA");
  assert.strictEqual(code.activated_count, 1);
  assert.strictEqual(code.free_days_earned, 30);

  assert.strictEqual(db.read("referral_redemptions/ravi").referrer_uid, "asha");
  assert.strictEqual(db.read("merchants/ravi").subscription_expires_at, ravi.pro_expiry);
  assert.strictEqual(db.read("merchants/asha").subscription_expires_at, asha.pro_expiry);
});

test("every further invite adds another 30 days to the inviter", async () => {
  const db = world();
  db.seed("businesses/biz_meena", { trial_started_at: iso(NOW) });
  await redeem(db, "ravi", "KAMAIASHA");
  const afterOne = new Date(db.read("businesses/biz_asha").pro_expiry).getTime();
  await redeem(db, "meena", "KAMAIASHA");
  const afterTwo = new Date(db.read("businesses/biz_asha").pro_expiry).getTime();

  assert.strictEqual(afterTwo - afterOne, days(30));
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").activated_count, 2);
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").free_days_earned, 60);
});

test("claiming at signup before the first sync still lands after the 7-day trial", async () => {
  const db = world();
  db.docs.delete("businesses/biz_ravi"); // device has not synced yet
  const createdAt = new Date(NOW.getTime() - 30 * 1000);
  await redeem(db, "ravi", "KAMAIASHA", { refereeCreatedAt: createdAt.toUTCString() });

  assert.strictEqual(db.read("businesses/biz_ravi").pro_expiry, iso(createdAt.getTime() + days(22)));
});

test("a merchant whose trial already ended gets the 15 days from today", async () => {
  const db = world();
  db.seed("businesses/biz_ravi", { trial_started_at: iso(NOW - days(40)) });
  await redeem(db, "ravi", "KAMAIASHA");
  assert.strictEqual(db.read("businesses/biz_ravi").pro_expiry, iso(NOW.getTime() + days(15)));
});

test("a paying inviter keeps the paid plan and gets 30 days past the paid expiry", async () => {
  const db = world();
  const paidTill = NOW.getTime() + days(200);
  db.seed("businesses/biz_asha", {
    is_pro: true,
    pro_plan: "annual",
    subscription_tier: "annual",
    pro_expiry: iso(paidTill),
    subscription_expires_at: iso(paidTill),
    trial_started_at: iso(NOW - days(300)),
  });
  await redeem(db, "ravi", "KAMAIASHA");

  const asha = db.read("businesses/biz_asha");
  assert.strictEqual(asha.pro_plan, "annual");
  assert.strictEqual(asha.pro_expiry, iso(paidTill + days(30)));
  assert.strictEqual(asha.subscription_expires_at, asha.pro_expiry, "both expiry fields move together");
});

test("an open-ended admin grant is never shortened, but the inviter is still counted", async () => {
  const db = world();
  db.seed("businesses/biz_asha", { is_pro: true, pro_plan: "pro" });
  await redeem(db, "ravi", "KAMAIASHA");

  assert.strictEqual(db.read("businesses/biz_asha").pro_expiry, undefined);
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").activated_count, 1);
});

test("reward days follow Remote Config, with safe defaults", async () => {
  assert.deepStrictEqual(rewardDaysFromTemplate(null), { referrerDays: 30, refereeDays: 15 });
  assert.deepStrictEqual(
    rewardDaysFromTemplate({
      parameters: {
        referral_reward_days: { defaultValue: { value: "45" } },
        referral_referee_bonus_days: { defaultValue: { value: "-3" } },
      },
    }),
    { referrerDays: 45, refereeDays: 15 }
  );

  const db = world();
  await redeem(db, "ravi", "KAMAIASHA", { referrerDays: 45, refereeDays: 10 });
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").free_days_earned, 45);
  assert.strictEqual(db.read("referral_redemptions/ravi").referee_bonus_days, 10);
});

// ---------------------------------------------------------------------------
// Redeem — abuse and retries
// ---------------------------------------------------------------------------

async function rejects(promise, code) {
  await assert.rejects(promise, (e) => e instanceof ReferralError && e.code === code);
}

test("unknown, malformed and own codes are rejected without granting anything", async () => {
  const db = world();
  await rejects(redeem(db, "ravi", "KAMAIZZZZ"), "NOT_FOUND");
  await rejects(redeem(db, "ravi", "hello"), "INVALID_FORMAT");
  await rejects(redeem(db, "asha", "KAMAIASHA"), "SELF");
  assert.strictEqual(db.read("businesses/biz_ravi").pro_expiry, undefined);
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").activated_count, 0);
});

test("an account can claim only one code", async () => {
  const db = world();
  db.seed("referral_codes/KAMAIMEEN", { merchant_id: "meena" });
  await redeem(db, "ravi", "KAMAIASHA");
  await rejects(redeem(db, "ravi", "KAMAIMEEN"), "ALREADY_REDEEMED");
});

test("retrying the same claim is safe: nothing is granted twice", async () => {
  const db = world();
  const first = await redeem(db, "ravi", "KAMAIASHA");
  const retry = await redeem(db, "ravi", "KAMAIASHA");

  assert.strictEqual(retry.already_redeemed, true);
  assert.strictEqual(retry.pro_expiry, first.pro_expiry);
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").activated_count, 1);
  assert.strictEqual(db.read("referral_codes/KAMAIASHA").free_days_earned, 30);
});

test("two merchants cannot trade codes back and forth", async () => {
  const db = world();
  db.seed("referral_codes/KAMAIRAVI", { merchant_id: "ravi" });
  await redeem(db, "ravi", "KAMAIASHA");
  await rejects(redeem(db, "asha", "KAMAIRAVI"), "MUTUAL");
});

test("status reports the inviter's stats and the invitee's claimed code", async () => {
  const db = world();
  await redeem(db, "ravi", "KAMAIASHA");

  const asha = await executeStatus({ db, FieldValue, uid: "asha", now: NOW });
  assert.strictEqual(asha.code, "KAMAIASHA");
  assert.strictEqual(asha.activated_count, 1);
  assert.strictEqual(asha.free_days_earned, 30);
  assert.strictEqual(asha.pro_expiry, db.read("businesses/biz_asha").pro_expiry);

  const ravi = await executeStatus({ db, FieldValue, uid: "ravi", now: NOW, randomCode: () => "KAMAIRAV1" });
  assert.strictEqual(ravi.applied_code, "KAMAIASHA");
  assert.strictEqual(ravi.referee_bonus_days, 15);
});

test("grantBase takes the latest of now, Pro expiry and trial end", () => {
  const later = iso(NOW.getTime() + days(50));
  assert.strictEqual(grantBase(null, NOW, null).getTime(), NOW.getTime());
  assert.strictEqual(
    grantBase({ is_pro: true, pro_expiry: later, trial_started_at: iso(NOW) }, NOW, null).toISOString(),
    later
  );
  assert.strictEqual(
    grantBase({ is_pro: false, pro_expiry: later }, NOW, null).getTime(),
    NOW.getTime(),
    "an explicit revoke is not extended"
  );
});
