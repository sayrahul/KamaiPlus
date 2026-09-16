# Play Store Release Runbook — KamaiPlus

Follow this top to bottom. The order matters: steps 1–2 must happen **before** the app
goes live, because this build depends on backend that is not deployed yet.

---

## ⛔ BLOCKER — do these first, or the release breaks AI scanning

This build calls a Cloud Function that **is not deployed**. If you publish before deploying
it, every merchant's AI bill/menu scan stops working, and **PDF invoice import dies
completely** (it has no offline fallback).

### 1. Deploy the AI proxy

```bash
firebase functions:secrets:set GEMINI_API_KEY      # paste your Google AI Studio key
firebase deploy --only functions:aiExtract
```

**Verify before moving on** — this must return `401`, not `404`:

```bash
curl -X POST https://us-central1-kamaiplus.cloudfunctions.net/aiExtract \
  -H "Content-Type: application/json" -d "{}"
```
`{"error":"Missing Authorization bearer token"}` = deployed and correctly refusing
unauthenticated callers. `404` = not deployed.

### 2. Deploy Firestore rules

```bash
firebase deploy --only firestore:rules
```

Needed for the admin console's new **Revenue** screen to read `razorpay_payments`, and for
the AI usage counter. Without it the Revenue screen shows a permission error.

### 3. Admin console (independent of the app — can be done any time)

```bash
cd admin_console
firebase deploy --only hosting:admin
```

---

## ✅ Verify on a real device BEFORE uploading

Install the universal APK (`export/`) on a phone and check these. **These are the things
that were changed and could not be verified without a device.**

| # | Check | Expected |
|---|---|---|
| 1 | AI scan a supplier bill photo | Items extracted. If it fails, step 1 above did not work |
| 2 | Import a real `.xlsx` from a distributor | File is selectable and rows import **with barcodes** |
| 3 | Scan an imported product's barcode at billing | It is found — proves the barcode carried through |
| 4 | Upload a PDF invoice | Parses (this is the one with no offline fallback) |
| 5 | Billing → UPI → tap QR | Countdown ticks down from 05:00 |
| 6 | Khata → Settle bill → tap QR | Same sheet opens, with the settlement amount |
| 7 | Return one item from a past bill | Refund amount is **not ₹0**; cash refund reduces the drawer |
| 8 | One real ₹199 payment | Firestore `razorpay_payments` gets a row; business doc shows `pro_granted_by: "razorpay_verified"` |
| 9 | Thermal print a bill | Store name, heading and footer print correctly (Hindi names should not garble) |

If **8** fails, stop — paying customers would not get what they paid for.

---

## 📦 Upload to Play Console

### What to upload
**`build/app/outputs/bundle/release/app-release.aab`** — an **AAB**, not an APK.
Play Store has required App Bundles since August 2021; an APK upload will be rejected.

The universal APK in `export/` is for **direct install and testing only** (WhatsApp it to a
merchant, sideload for QA). It is not a Play Store artifact.

### Version
`4.22.0` / versionCode `42202`.

> Bumped from 42201 deliberately. An AAB at 42201 was built on 13 Sep and the log does not
> record whether it was actually uploaded. Play rejects a version code that has been used
> before, so 42202 removes the risk either way. If Play still complains that 42202 is taken,
> bump `version:` in `pubspec.yaml` again (and the two `v4.22.0` strings in
> `lib/views/menu/menu_screen.dart` and `lib/views/splash/splash_screen.dart`).

### Steps
1. Play Console → **KamaiPlus** → Production → **Create new release**
2. Upload the `.aab`
3. Paste the release notes below
4. **Start at a staged rollout of 10–20%, not 100%** — see the opinion section
5. Review → **Start rollout to Production**

### Things to re-check in the listing
- **Data safety form** — bill/menu photos now go to *your* Cloud Function before Google,
  rather than device→Google directly. The categories collected have not changed, but the
  declaration is worth re-reading now that a first-party server is in the path.
- **No new Android permissions** in this release. Nothing to justify.
- Target SDK is already 36.

---

## 📝 Release notes (paste into Play Console)

```
What's new in 4.22.0

• Item return now refunds correctly — cash goes back to your drawer, or the
  customer's khata is reduced. Returns are also removed from your sales totals.
• Profit on the Home screen is now calculated from real buying prices instead
  of an estimate.
• Bulk add products from Excel (.xlsx) or CSV — barcodes and expiry dates now
  import correctly, so items can be scanned at the counter straight away.
• Barcode scan while adding a product now finds far more items online.
• Birthday offers now use real customer birthdays you save.
• Credit limit warning before giving udhar beyond a customer's limit.
• UPI QR now has a working countdown and can be opened full-screen from
  billing, split payments and khata settlement.
• Cash received against old udhar now shows in your Cash Register.
• Thermal bills now follow your Invoice Theme settings, and Hindi shop names
  print correctly.
• Backups can now be password protected, and restored directly from Google Drive.
• Several fixes to stock, pricing and reporting accuracy.
```

Keep it in plain language — the audience is shopkeepers, not developers.

---

## ↩️ If something goes wrong after rollout

1. Play Console → Production → **Halt rollout** (stops new users getting it immediately)
2. Crashlytics → check the top crash
3. If it is server-side, you can often fix without an app release:
   - AI broken → redeploy `aiExtract`
   - Need to force everyone onto a newer build → Admin Console → **Release & Control** →
     set `min_version_code`
   - Need to warn everyone → Admin Console → **Maintenance Mode** (now actually reaches
     the app)

That last point is the reason the maintenance and force-update controls were wired up:
you can act on a bad release without waiting for Play review.
