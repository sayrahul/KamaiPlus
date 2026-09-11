# KamaiPlus — Development Log

**Purpose of this file:** so any session (human, or a different AI agent/session with no
memory of this conversation) can pick up work without re-discovering what's already known.
Old, already-fixed bugs kept quietly reappearing because nothing recorded *why* a fix was
made — a later, unrelated change would touch the same code and undo it, and nothing caught
that because the regression test (if any) checked the wrong layer. See the case study below.

**How to use this file:**
- Before starting new work, read the most recent entries (newest on top) and the
  **Known open issues** list at the bottom.
- After finishing work — even a small fix — add an entry. State the *symptom the user
  reported*, the *root cause* (file:line), the *fix*, and *how it was verified*. Don't just
  say "fixed X" — say what would happen if X regressed, so the next fix looks for that.
- If you touch a file that a past entry names, re-read that entry first — you may be about
  to reintroduce something.
- Never delete old entries. Append only. If something described here was later reverted or
  superseded, say so in a new entry rather than editing history.

---

## ⚠️ Case study: why bugs keep coming back (read this once)

On the same day, five hours apart:

- **08:44** — commit `ddc25d5` *"fix: strict store vertical product and category
  isolation"* correctly isolated products/categories by business vertical, and added
  `test/business_vertical_isolation_test.dart`.
- **13:45** — commit `dbb5997` *"feat: add dedicated printer hardware setup, universal
  1-tap direct print, rapid barcode inward, and resilient catalog seeding"* — while adding
  printer/barcode features, also touched `getAllProducts`/`getAllCategories` in
  `local_database.dart` and added a "resilient fallback": if a filtered query for the
  active vertical came back empty, it silently queried **every product/category in the
  table, ignoring vertical entirely**. This undid the morning's fix.

**The existing test suite did not catch it**, because
`business_vertical_isolation_test.dart` only checks that data gets *tagged* correctly
(`ProductModel.toMap()`/`fromMap()` round-trips, seed-data classification). It never calls
`getAllProducts()` or `getAllCategories()` — the actual read path — so it could not detect
that the read path had started ignoring the tag it was checking.

**The lesson, concretely:** a regression test must exercise the same code path a real user
hits (the screen's data-loading call), not just the data shape. See
`test/vertical_product_leak_test.dart` (added 2026‑09‑11) for the corrected pattern — it
drives `LocalDatabase` through a real (in-memory FFI) SQLite database and asserts on what
`getAllProducts`/`getAllCategories` actually return.

---

## 2026-09-11 — Cross-screen wiring + business-vertical product leak

**Reported by user:** (1) "incomplete workflow, things not interconnected properly" —
screens don't update after a sale/edit elsewhere. (2) "kisi aur store type par dusre store
type ke master sku wale product aa rahe he" — switching business vertical shows another
vertical's products.

**Starting point:** this work began on a worktree that was 52 commits behind `origin/main`.
An initial audit was done against that stale code and largely discarded once the gap was
discovered — see the conversation, not repeated here. All work below is against
`origin/main` at commit `1589c95`.

### Fix 1 — Screens never refreshed after data changed elsewhere

**Root cause:** `home_dashboard_screen.dart:84` builds the four tab screens once into a
`PageView` in `initState`. Tab switches call `jumpToPage`; children stay alive and never
reload. Every screen loaded from SQLite exactly once, at first build. There was no
mechanism anywhere in the app for one screen's data mutation to reach another — 358
`setState` calls, 76 `initState`, and only 22 reactive primitives (`ValueNotifier`/
`ChangeNotifier`), none of which represented "a sale/edit just happened".

Concrete symptom: complete a sale on the Billing tab → Home's "Today's Sales", Khata's
customer balance, Cash Register's expected cash, and Transactions' list all kept stale
values until the app was fully restarted.

**Fix:** Added a small app-wide signal, `AppDataBus` (`lib/core/state/app_data_bus.dart`) —
four `ValueNotifier<int>` counters: `salesRevision`, `productsRevision`,
`customersRevision`, `cashRevision`. `LocalDatabase` bumps the relevant counter(s) after
each write **commits** (in the data layer, not the UI, so every caller — present and
future — is covered automatically). Bumps are coalesced over a 120ms window so a bulk
write loop (Firestore restore, catalog seeding) triggers one reload, not hundreds.

Screens subscribe via a mixin, `DataBusRefresh` (`lib/core/state/data_bus_refresh.dart`),
which guarantees listeners are added in `initState` and removed in `dispose` — added to:
`home_pulse_tab.dart`, `products_screen.dart`, `pos_billing_screen.dart`,
`khata_screen.dart`, `transactions_screen.dart`, `cash_register_screen.dart`,
`inventory_screen.dart`, `gst_reports_screen.dart`, `customers_screen.dart`.

`products_screen.dart` also got a `RefreshIndicator` (pull-to-refresh) as a manual
fallback — it was the one tab with no refresh mechanism at all, matching the pattern
already used on `home_pulse_tab.dart`.

**Verified:** `flutter analyze` (0 new issues), `flutter test` (all pass, including 7 new
tests in `test/app_data_bus_test.dart` covering: bumps only notify their own signal,
counter fires on every call (not just value changes), a cash sale wakes
sales+products+cash but not customers, a credit sale wakes customers but not cash, bulk
bumps coalesce into one reload, and a disposed screen's listener is actually removed).
**Not verified on a physical device** — needs a manual pass: complete a sale and watch
Home/Khata/Transactions/Cash Register update without restarting the app.

### Fix 2 — Debug build was broken (`android/app/build.gradle.kts`)

**Root cause:** the `debug` build type applied the `release` signing config
(`signingConfig = signingConfigs.getByName("release")`), and that keystore
(`kamai-release-key.jks`) is correctly gitignored and therefore absent from a fresh clone.
Fresh clone/CI could not produce even a debug APK. The signing passwords were also
hardcoded in the committed build script.

**Fix:** credentials now load from `android/key.properties` (gitignored; template at
`android/key.properties.example`). When that file is absent, `debug` uses the standard
Android debug keystore and `release` falls back to it too (so CI/contributors can still
build something runnable) rather than failing outright.

**Verified:** `flutter build apk --debug` — previously failed before any code compiled;
now succeeds and produces `build/app/outputs/flutter-apk/app-debug.apk`. (Needed a copy of
`android/app/google-services.json` from the main checkout — that file is intentionally
gitignored and was already present there; not a bug, just a prerequisite for building at
all, noted here so the next person doesn't waste time on it.)

### Fix 3 — Business vertical product/category leak

**Root cause:** `local_database.dart`, `getAllProducts()` and `getAllCategories()`. When
the query filtered by the active `business_type` came back empty, the code fell back to
querying the table **with no vertical filter at all** — i.e. it showed every product/
category regardless of vertical, including ones explicitly tagged for a different store
type. This is exactly the "resilient fallback" introduced in `dbb5997`, five hours after
`ddc25d5` had established isolation (see case study above).

Trigger scenario: a merchant switches business vertical in Settings
(`store_profile_screen.dart:409`) to one whose starter catalog either hasn't finished
seeding yet or has zero matching rows for some other reason → the fallback fires → every
other vertical's tagged products appear in the grid and category pills.

**Fix:** replaced the "show everything" fallback with a three-step resolution that never
crosses vertical boundaries:
1. Query rows tagged for this vertical (or `'both'`). If any, return them.
2. If none, try seeding this vertical's starter catalog (`seedVerticalStarterData`), then
   re-query with the same filter.
3. If still none, fall back **only** to genuinely unclassified rows
   (`business_type IS NULL OR business_type = ''`) — legacy data that pre-dates the
   vertical feature — never to another vertical's tagged rows. If even that is empty,
   return an empty list. An empty catalog is the correct result for a vertical that
   genuinely has nothing yet; another vertical's catalog is not.

**Also found and fixed while writing the regression test:** five SQL `WHERE` clauses used
`business_type = "both"` — a **double-quoted** string literal. Standard SQL treats
double-quoted text as a column/identifier reference, not a string; only single quotes are
string literals. Android's bundled SQLite has historically been lenient about this (a
legacy compatibility fallback), which is why it "worked" — but it is version-dependent
behavior, not something to rely on, and it hard-crashes on a strict SQLite build (this is
exactly what happened running the new test against `sqflite_common_ffi`, which uses
standard SQLite and does not have Android's leniency). Fixed to single-quoted string
literals (`business_type = 'both'`) at `local_database.dart:746, 758, 793, 850, 892`.

**Verified:** new file `test/vertical_product_leak_test.dart` (4 tests, using
`sqflite_common_ffi` for a real in-memory SQLite database — not a mock — so it exercises
actual SQL behavior): (1) switching to a vertical with its own starter catalog never
returns another vertical's products, (2) a vertical with no starter catalog returns empty
rather than everything, (3) legacy unclassified rows still show (backward compatibility
for installs that pre-date the vertical feature), (4) category isolation matches product
isolation. `flutter analyze` clean, full `flutter test` suite passes (28 tests total).
**Not verified on a physical device.**

**Files changed this session:**
- `android/app/build.gradle.kts`, `android/key.properties.example` (new)
- `lib/core/state/app_data_bus.dart` (new), `lib/core/state/data_bus_refresh.dart` (new)
- `lib/core/database/local_database.dart`
- `lib/views/dashboard/home_pulse_tab.dart`, `products/products_screen.dart`,
  `pos/pos_billing_screen.dart`, `khata/khata_screen.dart`,
  `transactions/transactions_screen.dart`, `cash_register/cash_register_screen.dart`,
  `inventory/inventory_screen.dart`, `reports/gst_reports_screen.dart`,
  `customers/customers_screen.dart`
- `test/app_data_bus_test.dart` (new), `test/vertical_product_leak_test.dart` (new)
- `pubspec.yaml` (added `sqflite_common_ffi` dev dependency, for DB-backed tests)

---

## Known open issues (not fixed this session — out of scope, noted so they aren't lost)

- `local_database.dart`, `getAllExpenses()` — re-inserts two demo expenses
  (`'Morning Chai & Snacks for Staff'`, `'Carry Bags & Packaging Tape'`) whenever the
  expenses table is empty. Deleting them brings them back.
- `splash_screen.dart` / `MainActivity.java` — a `test_screen` SharedPreferences key
  bypasses the login/session check and deep-links directly into any screen. It is now
  load-bearing for the home-screen widgets and launcher shortcuts (`QuickPosWidgetProvider`,
  `TodaySaleWidgetProvider`, `shortcuts.xml`), so it needs a proper auth-token handshake to
  replace it, not a straight removal.
- No `business_id` scoping on `getAllProducts`/`getAllCategories`/several other list
  queries — currently harmless in practice because each on-device SQLite file holds one
  store's data (see `switchUser` in `local_database.dart`, which gives each signed-in
  user/email their own db file), but worth tightening if a single-device multi-store mode
  is ever planned.
