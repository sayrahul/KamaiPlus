# KamaiPlus — Handover

**Written for:** the next engineer or AI agent picking this up cold, with no memory of the
session that produced it.

**Version at handover:** `4.27.0+42700` · Last updated 2026-09-16

Read this file first, then `DEVELOPMENT_LOG.md` (newest entries on top) for the blow-by-blow
of *why* each fix is shaped the way it is. `APP_FEATURE_MEMORY.md` holds the invariants —
rules that, if broken, reintroduce a bug that has already cost someone a day.

---

## 1. What this app is

An offline-first Android POS for small Indian retailers — kirana, restaurant, pharmacy,
clothing, hardware. Flutter + SQLite locally, Firebase (Auth, Firestore, Functions, FCM) for
sync and platform features. There is also a Flutter Web **admin console** at
https://kamaiplus-admin.web.app.

| Piece | Where | Notes |
|---|---|---|
| Mobile app | `lib/` | Flutter, offline-first, SQLite is the source of truth |
| Admin console | `admin_console/` | Flutter Web, deployed to Firebase Hosting target `admin` |
| Cloud Functions | `functions/` | Node 20. `aiExtract`, `resolveBarcode`, `onAdminPushCreated`, `verifyRazorpayPayment` |
| Security rules | `firestore.rules` | |
| i18n generator | `tool/` | `i18n_data.py` + `gen_i18n.py` |

---

## 2. Things that will bite you (read before changing anything)

These are not style preferences. Each one is a bug that reached a real merchant.

1. **The server↔app field contract for AI extraction.** `functions/ai_extract_core.js` emits
   *both* `dish_name`/`price_paise`/`category` and
   `product_name`/`selling_price_paise`/`category_name` on every item, and the Dart parsers
   read every spelling. Neither side may narrow this. When they disagreed, Gemini read a
   merchant's menu perfectly (the function logged `17 item(s)`) and the app rendered
   seventeen rows of "Menu Item ₹0.00".

2. **FCM is the only path to the notification tray.** `platform_settings/broadcast` drives the
   in-app banner and must never call `showLocalNotification`. It used to, and the admin
   console mirrored every push into that document, so one "Send" arrived as three
   notifications.

3. **There is exactly one owner PIN, in `OwnerPinService`.** Never compare a PIN to a string
   literal. `sale_detail_modal.dart` did (`'1234'` and `'0000'`), so refunds were authorised
   by the factory default on every install regardless of what the owner had set.

4. **A bill's purchase rate is never the selling price.** `normalizeExtractedItem` leaves
   `selling_price_paise` at 0 for bills, because `ExtractedBillItem.fromJson` only applies the
   markup when it is 0. Copying cost into it stocks everything at zero margin.

5. **Seed barcodes must be transcribed from real packs.** 22 of 23 in the old offline
   dictionary and 115 of 368 in `kMasterCatalogSeed` have invalid EAN-13 check digits — they
   were invented, so no physical product could ever match them.
   `test/barcode_checksum_test.dart` pins the count.

6. **`app_strings.dart` is generated.** Edit `tool/i18n_data.py` and run the generator.
   Editing the Dart directly means the next regeneration discards your work.

Full list: `APP_FEATURE_MEMORY.md`, invariants 1–24.

---

## 3. Languages — current state, honestly

**Infrastructure: complete. Screen coverage: partial and deliberately so.**

- **9 languages**: English, Hindi, Marathi (reviewed) + Gujarati, Tamil, Telugu, Kannada,
  Bengali, Punjabi (marked **BETA** in the picker).
- **137 keys × 9 languages = 1,233 strings**, in `tool/i18n_data.py`.
- Switching is a `ValueListenableBuilder` around `MaterialApp` plus const-map lookups — no
  IO, no async, no network. That is why it is instant.
- The **soundbox speaks the chosen language** (`ttsLocale`, e.g. `bn-IN`). It used to
  hardcode Hindi, so a Tamil shop heard its takings in Hindi.

**What is wired to `.tr` today:** bottom navigation, the Home dashboard tiles and quick
actions, checkout subtotal.

**What is not:** the remaining screens still hold hardcoded English. The app has ~1,482
`Text(` widgets; the catalog covers the vocabulary but the call sites have not all been
converted.

This was a deliberate scope decision, not an oversight. Converting every screen at once, in
six languages nobody on the team can read, at the point where the app is going to production,
trades a large regression risk for a benefit nobody can verify. The catalog and the mechanism
are done; the remaining work is mechanical and safe to do incrementally.

### How to translate another screen (10 minutes per screen)

```bash
# 1. Add the strings, all 9 languages on one line, to tool/i18n_data.py
#    add("Section name", { "my_key": ["English","हिंदी","मराठी","ગુજરાતી",
#                                     "தமிழ்","తెలుగు","ಕನ್ನಡ","বাংলা","ਪੰਜਾਬੀ"], })

python tool/gen_i18n.py          # 2. regenerate app_strings.dart
```

```dart
// 3. In the screen:
import '../../core/localization/app_language_service.dart';
Text('my_key'.tr)                // instead of Text('English')
```

```bash
flutter test test/localization_test.dart   # 4. fails if any language is missing
```

**Rule:** never add a key with fewer than 9 values. The test catches it, which is the whole
point of the key-first layout — the old per-language maps hid a completely absent Gujarati
translation behind a picker that showed a tick next to it.

---

## 4. AI features

### AI scan (`aiExtract`)
Menu cards and purchase bills → structured items. Prompts live in
`functions/ai_extract_core.js` — **separate prompts for menu and bill**, because a menu has no
supplier, no quantity and no cost price, and feeding one through the bill prompt marks the
menu price up as if it were wholesale.

- Reads any Indian script and returns names **in the script as printed**.
- `maxOutputTokens: 16384` — a dense 60-dish card used to truncate into a parse failure.
- Model order is `ai_config.active_model` first, then `DEFAULT_AI_MODELS`. Admin-configurable.
- Junk rows (`Rate`, `Item`, `Sr. No`, `360/-`) are dropped server-side *and* in the app.

**Debugging:** `firebase functions:log --only aiExtract`. A healthy line reads
`[AI] menu (restaurant) via gemini-3.6-flash: 17/17 item(s)`. If N ≪ M the normalizer is
rejecting good rows; if N == M but the app shows nothing, the field contract broke — run
`npm --prefix functions test`.

### Barcode (`resolveBarcode`)
Ladder: shared `barcode_catalog` → Open Facts (5 hosts parallel) → UPCitemdb → **Gemini text
fallback**. One merchant's scan populates the catalog for everyone.

Check digits are validated before any network call. AI-derived names are flagged
`is_ai_guess`, badged in the UI, and the price is left blank — a confident wrong name silently
corrupts a shop's catalog for every future scan.

### Quotas
Free & trial: **10 image scans/day**. Paid Pro: **100/day**. Reset at **IST midnight** —
a UTC day would reset at 5:30 AM, mid-way through a dairy's morning inward. A live trial
unlocks the feature but meters at the free rate.

---

## 5. Build, test, deploy

```bash
flutter analyze                      # expect 4 pre-existing dart:html infos in admin_console
flutter test                         # full suite
npm --prefix functions test          # 52 Cloud Function tests
python tool/gen_i18n.py              # after any string change

flutter build apk --release          # testing APK
flutter build appbundle --release    # Play Store AAB

FUNCTIONS_DISCOVERY_TIMEOUT=120 firebase deploy --only functions
firebase deploy --only firestore:rules
cd admin_console && flutter build web --release && cd .. && firebase deploy --only hosting:admin
```

**`FUNCTIONS_DISCOVERY_TIMEOUT=120` is not optional on this machine.** The default is 10s,
shorter than the cold `require` of `firebase-functions` here, and the failure reads
"User code failed to load", which looks like a syntax error and is not.

`flutter test` in parallel with a build contends over `sqlite3.dll` and produces failures that
are not real. If two tests fail in a full run, re-run them alone before believing it.

### Test suites

| Suite | Count | Guards |
|---|---|---|
| `functions/test/ai_extract_core.test.js` | 33 | server↔app field contract, prompts, junk rows |
| `functions/test/barcode_core.test.js` | 19 | check digits, AI-guess flagging, IST quota day |
| `test/localization_test.dart` | 17 | all 9 languages complete, beta flags, TTS locales |
| `test/menu_scan_test.dart` | 17 | real `aiExtract` payload shape |
| `test/cash_tally_and_owner_pin_test.dart` | 16 | draft persistence, one-PIN rule |
| `test/barcode_checksum_test.dart` | 9 | fabricated-barcode corpus |
| `test/notification_channels_test.dart` | 5 | one send = one notification |

---

## 6. Open items

1. **SECURITY — rotate the Gemini key.** `firestore.rules` grants every signed-in merchant
   read on `platform_settings/global_config`, and that document still contains
   `gemini_api_key`. Firestore rules cannot hide a single field. **Delete the field and rotate
   the key.** The app no longer reads or caches it (`GeminiAiService.purgeAnyCachedApiKey()`
   wipes copies on startup), but it has been readable by every merchant account for some time.
   `platform_settings/ai_config`, where the admin console writes it now, is correctly
   admin-only.

2. **115 invalid barcodes in `kMasterCatalogSeed`.** Those rows still work as catalog entries;
   only the barcode is unreachable. Fixing means transcribing from real packs — inventing
   replacements recreates the original bug.

3. **Remaining screens need the `.tr` pass** (section 3).

4. **Dead FCM topic.** The app subscribes to `announcements` and nothing ever sends to it.

5. **Node 20 runtime is deprecated** (decommissioned 2026-10-30). Functions need Node 22
   before then.

---

## 7. Where things live

```
lib/
  core/localization/    app_strings.dart (GENERATED), app_language_service.dart
  services/             gemini_ai_service, cloud_barcode_resolver_service,
                        owner_pin_service, cash_tally_draft_service,
                        mlkit_ocr_service, soundbox_service, auth_service
  views/                one folder per feature area
functions/
  index.js              endpoints + FCM trigger
  ai_extract_core.js    prompts, model order, item normalizer  (pure, tested)
  barcode_core.js       check digits, barcode prompt           (pure, tested)
tool/
  i18n_data.py          THE source of translations
  gen_i18n.py           generator
```

**Pattern worth keeping:** the pure logic in `functions/*_core.js` has no Firebase, no network
and no secrets, so it runs under `node --test` in milliseconds. The bug that started all of
this survived because the only way to exercise that code was to deploy it and photograph a
menu. Anything with a contract in it belongs in a `_core` file with a test.
