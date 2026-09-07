# KamaiPlus Flutter — Store-Type-Wise (Vertical) Adaptation
## Agent-Ready Implementation Plan

**Target repo:** `github.com/sayrahul/KamaiPlus` (Flutter, package `kamaiplus_pos`, currently v4.17.0)
**Reference repo (read-only, DO NOT MODIFY):** `github.com/sayrahul/kamai` (PWA) — specifically `src/lib/constants/storeProfiles.ts`
**Prepared:** Fresh clone + line-by-line source verification of BOTH repos on 7 Sept 2026. Every file path, function name, and current hardcoded value quoted in this plan is copy-pasted from actual code — not assumed.

---

## 0. What This Plan Does NOT Change (Read This First)

This is an **additive, isolated** feature. It must NOT touch:
- Auth/login flow (`login_screen.dart`, `signup_store_screen.dart` — except the one field described in Phase 1)
- Firestore sync logic (`firestore_sync_service.dart`)
- Any payment/checkout calculation logic (`pos_checkout_modal.dart` totals, tax, discount math)
- Any existing table's existing columns (only NEW nullable columns are added — nothing is renamed, retyped, or removed)
- Cash register, backup/restore, printer, soundbox code

If the coding agent finds itself editing any file not listed in Section 4's "Files Touched" table, **it must stop and ask**, not proceed on its own judgement.

---

## 1. The Core Problem (Confirmed by Code Audit)

Right now in Flutter:
- `signup_store_screen.dart` shows a category picker (Grocery/Kirana, Apparel/Clothing, Electronics & Mobile, Cafe/Restaurant) — this exists.
- The selected value is saved into `StoreProfileModel.category` as a **free-text display string** (e.g. `"Grocery / Kirana"`).
- **Nothing anywhere else in the app reads this field to change behavior.** It is dead data. Confirmed via full-codebase grep — zero conditional logic keys off `.category`.
- Search hint in Billing (`pos_billing_screen.dart:317`) is hardcoded: `'Scan barcode or type Atta, Rice, Oil, Maggi...'` — this is literally the PWA's **grocery-only** placeholder, copy-pasted, and shown to every business type including a clothing shop or pharmacy.
- `add_product_modal.dart` has one fixed unit list (`pkt, pcs, kg, g, ltr, ml, btl, box`) and no batch/expiry/size/color/IMEI fields at all — because `ProductModel` doesn't have those columns.
- `menu_screen.dart` menu tiles have grocery-flavored subtitles baked in permanently (e.g. "Products & FMCG — Daily Essentials & Barcodes", "Wholesale Inward — Mandi & Supplier Bills").

**Goal:** Make all of this dynamically driven by one canonical `businessType` value, exactly the way the PWA's `getStoreProfile(businessType)` pattern already works — 5 verticals: **grocery, pharmacy, clothing, hardware, restaurant.**

---

## 2. Canonical Vertical List (locked, matches PWA exactly)

| id | Display Name | Emoji |
|---|---|---|
| `grocery` | Kirana & Grocery Store | 🌾 |
| `pharmacy` | Medical Store & Pharmacy | 💊 |
| `clothing` | Clothing, Footwear & Apparel | 👕 |
| `hardware` | Hardware, Electrical & Sanitary | 🔩 |
| `restaurant` | Restaurant, Cafe & Fast Food | 🍽️ |

These 5 IDs are the only valid values ever stored in the new `business_type` column. Everything else (legacy strings, typos, null) must resolve to `grocery` as a safe default — same fallback rule the PWA uses (`getStoreProfile()` in `storeProfiles.ts` defaults to `STORE_PROFILES.grocery` when the type is unrecognized).

---

## 3. Pre-Existing Landmines the Agent Must Know About Before Touching These Files

These are REAL bugs already in the codebase (confirmed by grep), unrelated to this feature, but the agent WILL be editing near them. If the agent is not warned, it may either (a) accidentally fix them as a side-effect and break something else that depends on the current behavior, or (b) get confused about which one is "correct" and copy the wrong pattern into new code.

| # | File | Issue | Instruction to Agent |
|---|---|---|---|
| 1 | `lib/views/purchases/ai_inward_sheet.dart` (lines ~71, ~81) | Uses hardcoded `businessId: 'default_business'` instead of `FirestoreSyncService.instance.activeBusinessId` | **Do not fix this in this task.** Leave as-is. Out of scope — flag it in the Deviation Log (Section 8) but do not change it, to keep this PR isolated and reviewable. |
| 2 | `lib/services/firestore_sync_service.dart` | Default fallback business id is `'biz_starter_pos'` | Do not change. This plan's new `business_type` column lives on the **local `store_profile` row**, not on this sync default. |
| 3 | `lib/views/products/add_product_modal.dart` (~line 105) | Fallback category uses `businessId: 'biz_default'` | Do not change. Third different hardcoded id string in the app — a separate cleanup task, not this one. |
| 4 | `lib/views/common/pwa_top_bar.dart` | Fallback display text is `'Sharma Kirana Store'` / owner `'Rahul jathee'` | Do not change wording — only make sure this fallback still renders correctly after Phase 1's schema change (it must not crash if `business_type` column is null on an old row). |
| 5 | `lib/models/models.dart` → `StoreProfileModel` | Default constructor values are `storeName: 'Rahul Shramas'`, `ownerName: 'Divyaang Pratishthan'` — **different placeholder text than landmine #4 above.** Two different fallback identities exist in the app already. | Do not unify them in this task. Just add the new `businessType` field to this same class (Phase 1) without touching the existing default values for other fields. |

**Rule for the agent:** touch only what Section 4 explicitly lists. Every other file stays byte-for-byte identical except for the specific lines named.

---

## 4. Implementation Phases & Exact File Changes

Each phase is a **separate, independently-testable commit**. Do not start Phase N+1 until Phase N's acceptance criteria (given per phase) all pass.

### PHASE 1 — Data Model Foundation (no UI change yet)

**Goal:** Add the canonical `businessType` field to storage, with zero visible behavior change to the running app.

**File: `lib/core/database/local_database.dart`**
- Bump `openDatabase(... version: 1 ...)` → `version: 2`.
- Add an `onUpgrade` callback (currently missing — there is only `onCreate` and `onOpen`). Implement:
  ```dart
  onUpgrade: (db, oldVersion, newVersion) async {
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
  },
  ```
- New method `_migrateToV2(Database db)`:
  - `ALTER TABLE store_profile ADD COLUMN business_type TEXT` (nullable — existing installs get `NULL`, which the app must treat as `'grocery'` at read-time, never write a hard default into old rows blindly).
  - `ALTER TABLE products ADD COLUMN batch_number TEXT`
  - `ALTER TABLE products ADD COLUMN expiry_date TEXT`
  - `ALTER TABLE products ADD COLUMN size TEXT`
  - `ALTER TABLE products ADD COLUMN color TEXT`
  - `ALTER TABLE products ADD COLUMN imei_serial TEXT`
  - `ALTER TABLE products ADD COLUMN hsn_code TEXT`
  - `ALTER TABLE products ADD COLUMN is_loose_item INTEGER DEFAULT 0`
  - Wrap each `ALTER TABLE` in its own `try { } catch (_) {}` — SQLite throws if a column already exists, and `_ensureExtraTables()` already uses this exact defensive pattern in the current code (see the existing `ALTER TABLE customers ADD COLUMN address` at line ~59) — **follow that existing pattern exactly, don't invent a new one.**
- **Important:** since `_ensureExtraTables()` currently already does an ad-hoc `ALTER TABLE customers ADD COLUMN address TEXT` inside `onOpen` (not inside a versioned migration), leave that exactly as it is. Do not move it. Just add the new `onUpgrade` block alongside it.

**File: `lib/models/models.dart`**
- `ProductModel`: add 7 new **nullable, optional** fields — `batchNumber`, `expiryDate`, `size`, `color`, `imeiSerial`, `hsnCode` (all `String?`), `isLooseItem` (`bool`, default `false`). Add to constructor, `toMap()`, `fromMap()`, and `copyWith()`. Every existing call site that constructs a `ProductModel` (search all usages first) must keep compiling with zero required-field changes — these are all optional named parameters with defaults, so nothing else breaks.
- `StoreProfileModel`: add one new field `businessType` (`String`, default `'grocery'`). Add to constructor, `toMap()` (`'business_type': businessType`), `fromMap()` (`businessType: map['business_type'] ?? 'grocery'`). Do **not** touch the existing `category` field — leave it exactly as-is for backward display compatibility; `businessType` is the new canonical machine-readable id, `category` remains the old free-text label (they can temporarily disagree, that's fine, `category` becomes purely cosmetic legacy text after Phase 2).

**New file: `lib/core/constants/business_vertical_config.dart`**
This is the direct Dart port of the PWA's `src/lib/constants/storeProfiles.ts`. Structure:

```dart
class VerticalFeatureToggles {
  final bool showBarcode;
  final bool showWeightUnits;
  final bool showBatchExpiry;
  final bool showTableOrderType;
  final bool showSizeVariants;
  final bool showImeiWarranty;
  final bool showDoctorPrescription;
  final bool hasBillScan;
  final bool showQuotationEstimate;
  const VerticalFeatureToggles({
    required this.showBarcode,
    required this.showWeightUnits,
    required this.showBatchExpiry,
    required this.showTableOrderType,
    required this.showSizeVariants,
    required this.showImeiWarranty,
    required this.showDoctorPrescription,
    required this.hasBillScan,
    required this.showQuotationEstimate,
  });
}

class VerticalPlaceholders {
  final String searchProduct;
  final String newProductName;
  final String customerSearch;
  final String supplierNameExample;
  final String invoiceFooterNote;
  const VerticalPlaceholders({
    required this.searchProduct,
    required this.newProductName,
    required this.customerSearch,
    required this.supplierNameExample,
    required this.invoiceFooterNote,
  });
}

class BusinessVerticalProfile {
  final String id;
  final String name;
  final String shortName;
  final String emoji;
  final VerticalFeatureToggles toggles;
  final VerticalPlaceholders placeholders;
  final String defaultUnit;
  final List<String> recommendedUnits;
  final List<String> quickCategories;
  final String productsMenuTitle;
  final String productsMenuSubtitle;
  final String purchasesMenuTitle;
  final String purchasesMenuSubtitle;
  const BusinessVerticalProfile({
    required this.id,
    required this.name,
    required this.shortName,
    required this.emoji,
    required this.toggles,
    required this.placeholders,
    required this.defaultUnit,
    required this.recommendedUnits,
    required this.quickCategories,
    required this.productsMenuTitle,
    required this.productsMenuSubtitle,
    required this.purchasesMenuTitle,
    required this.purchasesMenuSubtitle,
  });
}

class BusinessVerticals {
  static const grocery = BusinessVerticalProfile(
    id: 'grocery', name: 'Kirana & Grocery Store', shortName: 'Kirana', emoji: '🌾',
    toggles: VerticalFeatureToggles(
      showBarcode: true, showWeightUnits: true, showBatchExpiry: false,
      showTableOrderType: false, showSizeVariants: false, showImeiWarranty: false,
      showDoctorPrescription: false, hasBillScan: true, showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Scan barcode or type Atta, Rice, Oil, Maggi...',
      newProductName: 'e.g., Aashirvaad Shudh Chakki Atta 5kg',
      customerSearch: 'Search regular customer name or 10-digit mobile...',
      supplierNameExample: 'e.g. Metro Cash & Carry, Parle Agency...',
      invoiceFooterNote: 'Thank you for shopping with us! Please visit again.',
    ),
    defaultUnit: 'kg',
    recommendedUnits: ['kg', 'gram', 'litre', 'packet', 'piece', 'box', 'dozen'],
    quickCategories: ['Atta, Rice & Dal', 'Spices & Cooking Oil', 'Dairy, Bread & Eggs', 'Biscuits & Snacks', 'Soaps & Detergents', 'Pooja & Agarbatti'],
    productsMenuTitle: 'Products & FMCG', productsMenuSubtitle: 'Daily Essentials & Barcodes',
    purchasesMenuTitle: 'Wholesale Inward', purchasesMenuSubtitle: 'Mandi & Supplier Bills',
  );

  static const pharmacy = BusinessVerticalProfile(
    id: 'pharmacy', name: 'Medical Store & Pharmacy', shortName: 'Medical', emoji: '💊',
    toggles: VerticalFeatureToggles(
      showBarcode: true, showWeightUnits: false, showBatchExpiry: true,
      showTableOrderType: false, showSizeVariants: false, showImeiWarranty: false,
      showDoctorPrescription: true, hasBillScan: true, showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Type medicine name (Paracetamol, Cetirizine, Syrup)...',
      newProductName: 'e.g., Dolo 650mg Paracetamol (Strip of 15)',
      customerSearch: 'Patient name, WhatsApp number, or Doctor name...',
      supplierNameExample: 'e.g. Zenith Pharma Distributors...',
      invoiceFooterNote: 'Medicines once sold cannot be returned without original batch verification. Get well soon!',
    ),
    defaultUnit: 'strip',
    recommendedUnits: ['strip', 'piece', 'box', 'ml', 'litre', 'packet'],
    quickCategories: ['Tablets & Capsules', 'Syrups & Suspensions', 'Injections & Vials', 'Ointments & Creams', 'First Aid & Bandages', 'Generic Medicines'],
    productsMenuTitle: 'Medicines & Stock', productsMenuSubtitle: 'Batch, Expiry & Barcodes',
    purchasesMenuTitle: 'Stockist Inward', purchasesMenuSubtitle: 'Distributor & Stockist Bills',
  );

  static const clothing = BusinessVerticalProfile(
    id: 'clothing', name: 'Clothing, Footwear & Apparel', shortName: 'Apparel', emoji: '👕',
    toggles: VerticalFeatureToggles(
      showBarcode: true, showWeightUnits: false, showBatchExpiry: false,
      showTableOrderType: false, showSizeVariants: true, showImeiWarranty: false,
      showDoctorPrescription: false, hasBillScan: true, showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Search Shirt, Jeans, Kurti, Shoes or scan tag...',
      newProductName: 'e.g., Men Pure Cotton Slim Fit Shirt (Size 40)',
      customerSearch: 'Customer name or WhatsApp number...',
      supplierNameExample: 'e.g. Surat Textile Wholesaler...',
      invoiceFooterNote: 'Exchange permitted within 7 days with original bill and price tags intact. No cash refund.',
    ),
    defaultUnit: 'piece',
    recommendedUnits: ['piece', 'pair', 'set', 'meter', 'box'],
    quickCategories: ['Men Shirts & T-Shirts', 'Women Kurtis & Sarees', 'Jeans & Trousers', 'Kids Wear', 'Shoes & Footwear', 'Innerwear & Accessories'],
    productsMenuTitle: 'Products & Sizes', productsMenuSubtitle: 'Size, Color & Stock',
    purchasesMenuTitle: 'Wholesale Inward', purchasesMenuSubtitle: 'Wholesaler & Manufacturer Bills',
  );

  static const hardware = BusinessVerticalProfile(
    id: 'hardware', name: 'Hardware, Electrical & Sanitary', shortName: 'Hardware', emoji: '🔩',
    toggles: VerticalFeatureToggles(
      showBarcode: true, showWeightUnits: true, showBatchExpiry: false,
      showTableOrderType: false, showSizeVariants: false, showImeiWarranty: true,
      showDoctorPrescription: false, hasBillScan: true, showQuotationEstimate: true,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Search Paint, PVC Pipe, Screw, Wire, MCB, Tap...',
      newProductName: 'e.g., Asian Paints Apex Exterior Emulsion 4L',
      customerSearch: 'Contractor, electrician, plumber or customer mobile...',
      supplierNameExample: 'e.g. Havells Distributor, Local Hardware Supplier...',
      invoiceFooterNote: 'Goods once cut or tinted cannot be taken back. Replacement warranty on LED & Fans with bill copy.',
    ),
    defaultUnit: 'piece',
    recommendedUnits: ['piece', 'meter', 'foot', 'sqft', 'kg', 'litre', 'box', 'bundle'],
    quickCategories: ['Pipes & PVC Fittings', 'Paints & Wall Primer', 'Wires, Switches & MCB', 'Hand & Power Tools', 'Screws, Nails & Fasteners', 'Sanitary & Water Taps', 'Cement & Adhesives', 'LED Bulbs & Battens'],
    productsMenuTitle: 'Products & Stock', productsMenuSubtitle: 'Tools, Paints & Electricals',
    purchasesMenuTitle: 'Supplier Inward', purchasesMenuSubtitle: 'Distributor & Supplier Bills',
  );

  static const restaurant = BusinessVerticalProfile(
    id: 'restaurant', name: 'Restaurant, Cafe & Fast Food', shortName: 'Cafe / Dine', emoji: '🍽️',
    toggles: VerticalFeatureToggles(
      showBarcode: false, showWeightUnits: false, showBatchExpiry: false,
      showTableOrderType: true, showSizeVariants: false, showImeiWarranty: false,
      showDoctorPrescription: false, hasBillScan: false, showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Touch category or type Chai, Paneer, Dosa, Pizza...',
      newProductName: 'e.g., Paneer Butter Masala (Full) / Cold Coffee',
      customerSearch: 'Guest name or phone (optional for dine-in)...',
      supplierNameExample: 'e.g. Local Vegetable Vendor, Dairy Supplier...',
      invoiceFooterNote: 'Thank you for dining with us! Hope you enjoyed the food. Please visit again.',
    ),
    defaultUnit: 'plate',
    recommendedUnits: ['plate', 'portion', 'piece', 'packet', 'box'],
    quickCategories: ['Hot & Cold Beverages', 'Starters & Snacks', 'Main Course (Curries)', 'Roti, Naan & Rice', 'Fast Food & Pizzas', 'Desserts & Sweets'],
    productsMenuTitle: 'Menu Items', productsMenuSubtitle: 'Dishes & Prices',
    purchasesMenuTitle: 'Kitchen Inward', purchasesMenuSubtitle: 'Vendor & Raw Material Bills',
  );

  static const Map<String, BusinessVerticalProfile> all = {
    'grocery': grocery, 'pharmacy': pharmacy, 'clothing': clothing,
    'hardware': hardware, 'restaurant': restaurant,
  };

  /// Legacy free-text category strings already stored on existing installs
  /// (from the current signup screen's 4 options) must resolve correctly.
  static const Map<String, String> _legacyMap = {
    'grocery / kirana': 'grocery',
    'apparel / clothing': 'clothing',
    'electronics & mobile': 'hardware',
    'cafe / restaurant': 'restaurant',
  };

  static BusinessVerticalProfile resolve(String? businessType) {
    if (businessType == null || businessType.isEmpty) return grocery;
    if (all.containsKey(businessType)) return all[businessType]!;
    final mapped = _legacyMap[businessType.toLowerCase().trim()];
    if (mapped != null) return all[mapped]!;
    return grocery;
  }
}
```

**Acceptance criteria for Phase 1:**
1. Fresh install: app opens exactly as before, zero visual change.
2. Existing install (simulate by NOT wiping app data): app opens without crashing, migration runs once, `sqlite3` inspection of the `.db` file shows the new columns exist and old data is untouched.
3. `flutter analyze` passes with zero new warnings.
4. No existing screen's behavior changed (manually re-test: complete one cash sale, one credit/khata sale, add one product, scan one barcode — all four must work exactly as before).

---


### PHASE 2 — Wire Up Signup + Settings (source of truth for `businessType`)

**File: `lib/views/auth/signup_store_screen.dart`**
- Current `_categories` list (line ~33) has 4 entries with only a `'title'` key. Add a second key `'businessTypeId'` mapped to the canonical ids:
  - `'Grocery / Kirana'` → `'grocery'`
  - `'Apparel / Clothing'` → `'clothing'`
  - `'Electronics & Mobile'` → `'hardware'`
  - `'Cafe / Restaurant'` → `'restaurant'`
  - **Add a 5th option: `'Medical / Pharmacy'` → `'pharmacy'`** (currently missing entirely from signup — this vertical exists in the PWA but has no signup entry point in Flutter at all).
- When `StoreProfileModel` is saved at the end of signup, set BOTH `category: _selectedCategory` (unchanged, cosmetic) AND the new `businessType: businessTypeIdForSelected` field.

**File: `lib/views/settings/store_profile_screen.dart`**
- Find wherever `category` is currently editable (a dropdown/picker, since this screen lets users edit store profile after signup). Add the same 5-option picker wired to `businessType`, so a store can correct their vertical after onboarding without reinstalling.
- **Critical:** changing `businessType` here must NOT delete or modify any existing products, customers, or sales — it only changes which config profile is used to render screens going forward. Do not add any "migrate old products" logic in this phase; that's explicitly out of scope.

**Acceptance criteria for Phase 2:**
1. New signup → selecting "Medical / Pharmacy" → `store_profile.business_type` column in the DB reads `'pharmacy'` (verify with a debug print or DB inspection, not just UI).
2. Existing (pre-migration) installs that have never set `businessType` → `BusinessVerticals.resolve(null)` returns `grocery` → app behaves exactly as it does today (since today's behavior IS grocery-flavored everywhere).
3. Editing vertical in Settings and going back to Billing immediately reflects the new search hint/behavior — no app restart required (use a `ValueNotifier<String>` or similar reactive pattern already used elsewhere in the app, e.g. `FirestoreSyncService.syncState` is a `ValueNotifier` — follow that existing pattern for consistency rather than introducing a new state-management library).

---

### PHASE 3 — Screen-by-Screen Conditional UI (the actual "adaptation")

This is the exhaustive table. **Every row is independently testable.** The agent should implement and verify one row at a time, not all at once.

| # | Screen / File | What Changes | Exact Condition |
|---|---|---|---|
| 1 | `pos_billing_screen.dart` search field (line ~317) | Replace hardcoded hint string with `BusinessVerticals.resolve(currentBusinessType).placeholders.searchProduct` | All verticals — value differs per vertical (see Phase 1 config) |
| 2 | `add_product_modal.dart` — "New Product" name field hint | Replace with `.placeholders.newProductName` | All verticals |
| 3 | `add_product_modal.dart` — Unit dropdown (`_units` list, line ~64) | Replace static list with `BusinessVerticals.resolve(...).recommendedUnits`, mapped to display labels (build a small static `Map<String,String>` of unit-id → display-label covering all units across all 5 verticals, e.g. `'strip': 'Medicine Strip (strip)'`, `'plate': 'Plate / Dish (plate)'`, `'sqft': 'Square Feet (sq.ft)'`, etc. — full list is in Section 2's PWA reference `MASTER_UNITS`) | All verticals |
| 4 | `add_product_modal.dart` — new conditional field block: **Batch Number + Expiry Date** (two new `TextField`s, expiry via date-picker) | Show only if `toggles.showBatchExpiry == true` | **pharmacy only** |
| 5 | `add_product_modal.dart` — new conditional field block: **Size + Color** (two new `TextField`s or dropdowns) | Show only if `toggles.showSizeVariants == true` | **clothing only** |
| 6 | `add_product_modal.dart` — new conditional field block: **IMEI/Serial + Warranty Months** | Show only if `toggles.showImeiWarranty == true` | **hardware only** |
| 7 | `add_product_modal.dart` — "Add Category" quick-suggestions | When creating a new category, show `.quickCategories` as tappable chips above the free-text field (still allow custom text — this is a convenience shortcut, not a restriction) | All verticals |
| 8 | `add_product_modal.dart` — Barcode field + scan button | Hide entirely if `toggles.showBarcode == false` | **restaurant only** hides it |
| 9 | `menu_screen.dart` — "Products & FMCG" tile (title+subtitle) | Replace hardcoded strings with `.productsMenuTitle` / `.productsMenuSubtitle` | All verticals |
| 10 | `menu_screen.dart` — "Wholesale Inward" tile (title+subtitle) | Replace with `.purchasesMenuTitle` / `.purchasesMenuSubtitle` | All verticals |
| 11 | `menu_screen.dart` — "Barcode Studio" tile | Hide entirely if `toggles.showBarcode == false` | **restaurant only** hides it |
| 12 | `purchases_screen.dart` — supplier name field hint (line ~830) | Replace `'e.g. Metro Cash & Carry, Parle Agency...'` with `.placeholders.supplierNameExample` | All verticals |
| 13 | `purchases_screen.dart` + `ai_inward_sheet.dart` — Purchases menu tile AND "AI Bill Scan" specifically | Keep the Purchases screen visible for ALL verticals including restaurant (manual purchase entry is genuinely useful everywhere); only hide the "AI Bill Scan" button/tile specifically when `toggles.hasBillScan == false`. This deliberately diverges from the PWA (which hides the whole Purchases nav item for restaurant), because Flutter's AI Inward is currently simulated/fake anyway — hiding the real manual-entry screen for restaurants would remove useful functionality for no reason. **Agent: record this deliberate divergence in the Deviation Log.** |
| 14 | `khata_screen.dart` — customer search hint (line ~507) | Replace with `.placeholders.customerSearch` | All verticals |
| 15 | `customers_screen.dart` — search hint (line ~549) | Same, use `.placeholders.customerSearch` | All verticals |
| 16 | `inventory_screen.dart` — "Expiry Radar" tab | Only show this tab if `toggles.showBatchExpiry == true`; other verticals show 2 tabs (Reorder Alerts / Stock Movements only). **Important:** current Expiry Radar data is hardcoded/simulated (comment literally says "Simulated realistic near-expiry batches") — do NOT wire it to real `batch_number`/`expiry_date` in this phase; that's a separate larger feature. Only gate the tab's **visibility** correctly; leave its internal fake content untouched, and note this clearly in the Deviation Log so it isn't mistaken for "fully done." |
| 17 | `invoice_themes_screen.dart` — invoice footer note default | Use `.placeholders.invoiceFooterNote` as pre-filled default for NEW stores only; never overwrite an already-customized footer on existing stores | All verticals |
| 18 | `pos_item_edit_modal.dart` — if a cart item's product has `size`/`color`/`batchNumber` set, show them read-only as a small subtitle chip under the item name | Purely cosmetic, per-product (not per-vertical toggle needed — just "does this field have a value") | All verticals |
| 19 | `gst_reports_screen.dart` — HSN search hint | Already generic ("Search HSN code...") — confirmed via audit, **no change needed.** Listed only to record it was checked. | N/A |

**Explicitly OUT OF SCOPE for Phase 3** (do not attempt even if it looks easy):
- Restaurant table/KOT/token-number ordering flow — needs a genuinely new screen, not a toggle on existing ones. Future task.
- Hardware "Quotation/Estimate" mode — also needs a new screen.
- Wiring real batch/expiry tracking into Inventory's Expiry Radar (see row 16).
- Any change to `pos_checkout_modal.dart` payment/tax/discount math.
- Per-vertical sample/seed product data (`_seedStarterData()` in `local_database.dart` stays grocery-only for now) — a pharmacy signup will start with zero sample products rather than pharmacy-flavored ones. Fast-follow task if wanted later, not blocking this one.

**Acceptance criteria for Phase 3 (test per vertical, all 5):**
For EACH of the 5 verticals, set it in Settings, then verify:
1. Billing search box shows the correct placeholder text.
2. Add Product modal shows correct unit list, correct extra fields (batch/expiry OR size/color OR IMEI OR none), correct barcode visibility.
3. Menu screen shows correct tile titles/subtitles.
4. Inventory screen shows correct number of tabs.
5. Completing one full cash sale AND one full credit/khata sale still works with zero errors, for every vertical — this is the most important regression check, since the sale-completion code path must never be touched by anything above, only surrounding UI.

---

### PHASE 4 — Regression Safety Net (mandatory, not optional)

Because this touches ~8 files that are also central to daily billing operations, the agent must follow this discipline:

1. **One file, one commit.** Do not batch multiple files into a single commit — makes it impossible to bisect later if something breaks.
2. **Before editing any file in the Phase 3 table, run `flutter analyze` and note the baseline warning count.** After editing, count must not increase except for the exact line changed.
3. **Deviation Log** — append to `VERTICAL_CONFIG_DEVIATION_LOG.md` in repo root as work proceeds: every time the agent makes a judgment call not explicitly spelled out above (exact spacing, exact chip styling, wording tweaks), write one line: what was decided and why. Lets Rahul review the reasoning without re-reading every diff.
4. **Never change a function's existing parameters/return type** if it's called from more than one place — check call sites first (`grep -rn "functionName("`) before touching a signature.
5. **Highest-risk file: `add_product_modal.dart`** (most new conditional fields land here). After finishing it, manually test: add a new product AND edit an existing product, for all 5 verticals, confirming the existing product's original fields (name/price/stock/barcode) are never blanked or corrupted by new optional fields being absent.
6. **Do not touch `pos_checkout_modal.dart`, `payment_modal.dart`, or any sale-completion/stock-deduction/ledger-update method in `local_database.dart` as part of this task.** Those are the exact functions responsible for stock deduction and khata balance correctness; this feature has zero legitimate reason to touch them. If the agent finds itself needing to edit one of these files to make a Phase 3 row work, it must stop and flag it rather than proceed.

---

## 5. Recommended Execution Order (give this sequence to the agent as the task order)

1. Phase 1 → `local_database.dart` migration only → test migration alone → commit.
2. Phase 1 → `models.dart` changes → test app still compiles and runs → commit.
3. Phase 1 → new `business_vertical_config.dart` file (pure addition, no wiring yet) → commit.
4. Phase 2 → signup screen wiring → test new-signup path → commit.
5. Phase 2 → settings screen wiring → test edit-existing-store path → commit.
6. Phase 3 → rows 1–2 (search hints only, lowest risk, purely cosmetic) → test → commit.
7. Phase 3 → rows 9–10, 17 (menu/invoice text swaps, still cosmetic) → test → commit.
8. Phase 3 → row 3 (unit dropdown) → test add/edit product for all 5 verticals → commit.
9. Phase 3 → rows 4–6 (new conditional fields in Add Product modal — highest risk, do these LAST and ONE AT A TIME, each as its own commit) → test thoroughly after each → commit.
10. Phase 3 → rows 7–8, 11–16, 18 (remaining toggles) → test → commit.
11. Full regression pass across all 5 verticals (Section 4's Phase 3 acceptance criteria) → final commit.

**Why this order:** cosmetic/text-only changes first (near-zero risk, builds confidence and catches config-wiring mistakes early), structural dropdown/field changes last (highest risk, isolated into their own commits so any bug is easy to isolate and revert).

## 6. Final Acceptance Checklist (Rahul reviews this before merging/shipping)

- [ ] All 5 verticals selectable in both Signup and Settings.
- [ ] Switching vertical in Settings updates Billing search hint immediately, no restart needed.
- [ ] Add Product modal shows correct extra fields per vertical (batch/expiry for pharmacy, size/color for clothing, IMEI for hardware, nothing extra for grocery/restaurant).
- [ ] Barcode field hidden ONLY for restaurant, visible for the other 4.
- [ ] Menu tile titles/subtitles change per vertical.
- [ ] Inventory tab count changes correctly (3 tabs for pharmacy, 2 for everyone else).
- [ ] For every vertical: one full cash sale completes correctly (stock decrements, invoice number increments, invoice shows correct total).
- [ ] For every vertical: one full credit/khata sale completes correctly (customer balance increases by the right paise amount, ledger entry created).
- [ ] Editing a product created BEFORE this feature shipped (i.e., with all-null new columns) opens without crashing and saves correctly.
- [ ] `VERTICAL_CONFIG_DEVIATION_LOG.md` exists and has an entry for every judgment call made.
- [ ] Every landmine in Section 3 is confirmed untouched (`grep` for `'default_business'`, `'biz_starter_pos'`, `'biz_default'`, `'Sharma Kirana Store'`, `'Rahul Shramas'` — all counts should be identical before/after this feature).
- [ ] `flutter analyze` warning count did not increase beyond the intentionally-touched lines.

## 7. What Rahul Needs to Do (Setup on Your End)

1. **Before starting:** make a fresh backup — `git tag pre-vertical-config` on the current `main` branch, so there's a one-command rollback point (`git checkout pre-vertical-config`) if anything goes seriously wrong mid-way.
2. **Give the agent this exact file** (`VERTICAL_CONFIG_PLAN.md`) as its task brief — not a paraphrase. The exact file paths/line numbers/table rows are load-bearing; a summary would lose precision.
3. **Review commits one at a time**, in the Section 5 order — don't let the agent batch everything into one giant commit even if it offers to "save time."
4. **Test on a real device with an EXISTING install** (not a fresh emulator wipe) at least once — this is the only way to genuinely verify the SQLite migration (`onUpgrade`) path works, since a fresh install always takes the `onCreate` path and would never catch a migration bug.
5. **After Phase 1 alone is merged, wait a day of normal personal use** before starting Phase 2 — this is your real safety net for the migration, since it touches every existing product/store-profile row on your own device.
6. **Read `VERTICAL_CONFIG_DEVIATION_LOG.md` fully** before final sign-off — it's short by design and tells you every place the agent used judgment instead of your exact spec.
7. **Do NOT ask the agent to also fix the Section 3 landmines "while it's in there."** Keep this PR scoped to vertical config only — bundle-fixing unrelated bugs in the same PR is exactly how a small feature turns into a hard-to-review, hard-to-revert mess.

---

*Document prepared 7 Sept 2026 via fresh clone + line-level source audit of both `sayrahul/kamai` (PWA reference) and `sayrahul/KamaiPlus` (Flutter target) repos. All quoted code, file paths, and line numbers are from actual source, not reconstructed from memory of prior sessions.*
