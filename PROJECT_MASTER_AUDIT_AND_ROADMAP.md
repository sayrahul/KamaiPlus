# 🌟 KAMAI+ (KAMAIPLUS) NATIVE ANDROID — MASTER PROJECT AUDIT & ROADMAP

> **LOCKED GOLD BASELINE: Version 4.17.0 (Git Commit: `e7d4079` / Git Tag: `v4.17.0-locked-gold`)**  
> **Target OS:** Android 8.0 (API 26) to Android 14+ (API 34)  
> **Target Hardware:** Indian Retail Counter Android Phones & Tablets (e.g. Xiaomi Redmi 6, Samsung Galaxy, Realme)  
> **Core Architecture:** Flutter 3.x + SQLite (Local-First Offline Core) + Native Android Java Platform Channels + Firebase Cloud Sync  
> **Last Verified On Physical Device:** 07 September 2026, 12:17 PM IST (Redmi 6, 720x1440 resolution)

---

## 🔒 1. PERMANENT CONSTITUTIONAL PROTOCOLS & INVARIANTS (NEVER TO BE REVERTED)

Yeh rules app ki foundation hain. Kisi bhi situation me in rules ko modify ya revert nahi kiya jayega:

1. **5-Tab Locked Bottom Navigation:**
   * **Tab 0:** `Home` (`HomePulseTab`) — Business Pulse KPI Overview, 1-Tap Quick Actions, Daily Ops (Cash Register & Transactions).
   * **Tab 1:** `Product` (`ProductsScreen`) — Full catalog master. Has pencil edit button on every card. **Strictly NO nested bottom navbar**.
   * **Tab 2:** `Billing` (`PosBillingScreen`) — Center elevated button with Emerald Green glow (`#059669` / `#10B981`).
   * **Tab 3:** `Khata` (`KhataScreen`) — Digital Khata & Udhar ledger, customer statements, WhatsApp reminders.
   * **Tab 4:** `Menu` (`MenuScreen.show(context)`) — **STRICTLY A MODAL BOTTOM SHEET!** Sliding up from bottom with an 'X' close button. Dismissing returns to the current active tab. Never a full page in `PageView`.
2. **Financial Math Invariant (Integer Paise Only):**
   * Floating-point arithmetic (`0.1 + 0.2`) is **strictly forbidden** for monetary calculations.
   * All prices, discounts, taxes, customer balances, cash drawer amounts are stored and calculated as **integer paise** (`1 INR = 100 paise`).
   * UI displays rupee amounts using `MoneyFormatter.formatINR(paise)` or `(paise / 100.0).toStringAsFixed(2)`.
3. **Offline-First Zero-Latency Contract:**
   * Local SQLite database (`LocalDatabase.instance`) is the single source of truth for all screens (<10ms instant response).
   * Cloud sync (Firebase Firestore) runs in the background and must **never** block retail counter billing or checkout.
4. **Out-of-Stock Guard:**
   * Items with `effectiveStock <= 0` must display a high-contrast **Red Outline (`#EF4444`)**, light red tint (`#FFF1F2`), and a bold red **`OUT OF STOCK`** badge.
   * Clicking an out-of-stock item triggers heavy haptic feedback, shows a red warning snackbar, and blocks addition to cart.
5. **Multi-Draft POS Billing inside Checkout Modal:**
   * Bill draft tabs (`Bill #1`, `Bill #2`, `+ New Bill`) are located **exclusively inside the POS Checkout Modal** to prevent clutter on the main billing screen.
   * Tapping `+ New Bill` automatically saves the current draft, switches to a new draft, and **dismisses the modal downward** so the cashier is immediately on the product grid to scan or add items.
6. **No Unsolicited Rewrites or Reversions:**
   * Features solved and logged in `APP_FEATURE_MEMORY.md` must **never** be removed, rewritten, or simplified during subsequent tasks.

---

## 📊 2. COMPLETE SCREEN-BY-SCREEN IMPLEMENTATION MATRIX

A deep audit of all screens and modules in `lib/`:

| Screen / Module | Primary File | Status | Key Implemented Features |
|---|---|---|---|
| **Home Dashboard** | `lib/views/dashboard/home_pulse_tab.dart` | ✅ 100% Active | Today's Sales, Orders count, Estimated Profit (PIN-protected eye toggle), Market Udhar overview, 1-Tap Quick Actions (+ New Bill, Khata, Stock Inward, Day Summary, Tally Counter), Daily Ops (Cash Register, Transactions). |
| **POS Billing** | `lib/views/pos/pos_billing_screen.dart` | ✅ 100% Active | 2-column product cards with category filters, instant search, camera barcode scanner, out-of-stock red outline & blocker, bottom floating cart drawer (`View Cart & Pay`), multi-cart draft state. |
| **POS Checkout Modal** | `lib/views/pos/pos_checkout_modal.dart` | ✅ 100% Active | Draft bill tabs (`Bill #1`, `Bill #2`, `+ New Bill`), Customer auto-suggest / Quick-Add, Cash Tender chips (Exact, ₹50, ₹100, ₹200, ₹500, ₹1000, ₹2000), Live dynamic UPI QR code, Split Payment calculator (Cash + UPI + Credit), Bill Discount (Flat ₹ or %), Return change computation, Thermal printer dispatch, Soundbox audio trigger. |
| **Sale Completed Modal** | `lib/views/pos/sale_completed_modal.dart` | ✅ 100% Active | Compact green completion badge, WhatsApp 1-tap bill dispatcher with auto-filled phone, Thermal printer 58mm/80mm dispatch, Native Android A4 PDF generator (`InvoicePdfService`), Native Android status bar notification (`NativeNotificationService`), large "+ New Bill" button. |
| **Products Catalog** | `lib/views/products/products_screen.dart` | ✅ 100% Active | Grid/List view toggle, Category horizontal pills with item counts, Search by name/barcode, Pencil edit button on each card, Traffic light stock badge, Inline +/- stock adjustment stepper. |
| **Add/Edit Product Modal** | `lib/views/products/add_product_modal.dart` | ✅ 100% Active | Name, Category dropdown, Barcode scanner trigger, Buying Cost, Selling Price, Margin % preview, Opening Stock, Low Stock Alert, Unit selector, GST rate (0%, 5%, 12%, 18%, 28%), Unlimited Stock toggle. |
| **Digital Khata** | `lib/views/khata/khata_screen.dart` | ✅ 100% Active | Market Udhar summary card (Net Due, Total Customers Due, Advance), Customer search, WhatsApp payment reminder button, Customer Statement Ledger (Jama vs Udhar entries), Audio voice note recorder (audio-only, no camera clutter). |
| **Cash Register & Galla** | `lib/views/cash_register/cash_register_screen.dart` | ✅ 100% Active | Opening cash float, Live cash sales, Expense logger with quick tags (Chai, Freight, Supplier, Electric), Expected closing cash, Note & Coin Denomination Counter modal, SQLite shift history, WhatsApp Z-Report summary. |
| **Denomination Tally** | `lib/views/cash_register/denomination_tally_modal.dart` | ✅ 100% Active | ₹2000, ₹500, ₹200, ₹100, ₹50, ₹20, ₹10 notes & ₹5, ₹2, ₹1 coins counter with live total, drawer cash comparison, excess/shortage badge, 1-tap WhatsApp tally share. |
| **Transactions History** | `lib/views/transactions/transactions_screen.dart` | ✅ 100% Active | Invoice search, Date filters (All, Today, Yesterday, 7 Days, Month), Payment mode filters (Cash, UPI, Credit, Split), Detail modal with thermal printing and WhatsApp bill sharing. |
| **Inventory Intelligence** | `lib/views/inventory/inventory_screen.dart` | ✅ 100% Active | Total stock valuation (PIN protected), Tracked SKUs count, Low stock reorder alert, Near expiry radar, Stock movement audit trail backed by `inventory_movements` SQLite table. |
| **Wholesale Purchases** | `lib/views/purchases/purchases_screen.dart` | ✅ 100% Active | Supplier purchase orders, Vendor udhar tracking, AI Mandi Parcha OCR camera viewfinder, 1-tap stock inventory inwarding, Supplier settlement dialog. |
| **GST Tax Reports** | `lib/views/reports/gst_reports_screen.dart` | ✅ 100% Active | Taxable turnover, CGST/SGST 50:50 breakdown, Table 12 HSN sales summary, Period selector (Month, Last Month, Q1-Q3), 1-Click CA Export Package (CSV/Excel) & WhatsApp share. |
| **Barcode Studio** | `lib/views/tools/barcode_studio_screen.dart` | ✅ 100% Active | SKU dropdown, Label copy counter, 3 sticker dimensions (50x25mm, 38x25mm, 50x38mm), Customizable layout elements, Live thermal sticker preview, Direct Bluetooth thermal printer dispatch. |
| **WhatsApp Growth Hub** | `lib/views/growth/growth_campaigns_screen.dart` | ✅ 100% Active | Birthday radar, Festival Dhamaka, Khata reminder, VIP reward campaigns, Discount voucher customizer, Live WhatsApp message preview bubble, Direct WhatsApp 1-tap launcher. |
| **Invoice Themes** | `lib/views/settings/invoice_themes_screen.dart` | ✅ 100% Active | 7 brand color palettes, 4 invoice header types (Tax Invoice, Retail Invoice, Cash Memo, Estimate), Display options checklist, Live A4 paper mockup preview. |
| **Pro Membership** | `lib/views/settings/pro_membership_screen.dart` | ✅ 100% Active | Dark titanium card with gold glow, 50% Annual discount toggle, 3 Plan Tiers (Starter, Pro, Enterprise), Comprehensive feature matrix, Verified retail testimonials, Interactive FAQ accordion. |
| **Hardware & Bluetooth** | `lib/views/settings/bluetooth_printer_dialog.dart` | ✅ 100% Active | Bluetooth paired devices scan, 58mm / 80mm roll selection, Test print receipt, Auto-reconnect persistence. |
| **Store Profile & UPI** | `lib/views/settings/store_profile_screen.dart` | ✅ 100% Active | Store details, Owner name, Address, GSTIN, FSSAI, Multi-bank UPI QR configuration, Bill header/footer notes. |
| **Menu Hub Modal** | `lib/views/menu/menu_screen.dart` | ✅ 100% Active | Full hub bottom sheet modal with 4 categories (Daily Billing, Stock, Khata & Growth, Tax & Settings), Close 'X' button, Direct navigation triggers. |

---

## 🔍 3. MICRO-DETAILS & ARCHITECTURAL AUDIT

### A. Stock Protection & Integrity
* **Detection:** When `effectiveStock = (product.stockQuantity - inCartQty) <= 0`, product tile is immediately styled with:
  * Border: `Border.all(color: Color(0xFFEF4444), width: 1.6)`
  * Background: `Color(0xFFFFF1F2)`
  * Top Badge: `OUT OF STOCK` red tag
  * Bottom Text: `'Out of Stock'` in red font
  * Opacity: `0.75`
* **Cart Boundary Check:** If cashier taps tile, `_addToCart` verifies `currentQty >= product.stockQuantity`, emits `HapticFeedback.heavyImpact()`, and presents a red floating SnackBar.
* **Unlimited Stock Handling:** Products marked with `stockQuantity >= 900000` bypass depletion limits and show `'∞ Unlimited'`.

### B. Multi-Draft Billing in Checkout Modal
* **Data Structure:** `CartTab` encapsulates `id`, `name`, `number`, and `items: Map<String, CartItemModel>`.
* **Modal Separation:** `PosCheckoutModal` hosts the draft tabs bar at the top of its scroll view.
* **Dismiss-on-New-Bill:** When cashier clicks `+ New Bill`, `Navigator.of(context).pop()` is called immediately followed by `widget.onAddNewBill?.call()`. The modal smoothly drops down, and the screen resets to a fresh cart ready for scanning.

### C. Native Android Services
* **Native Notification:** Implemented in `MainActivity.java` via MethodChannel `com.kamaiplus.pos/notifications`. Uses `NotificationManager.IMPORTANCE_HIGH` with channel `kamaiplus_channel` so heads-up alerts display on all Android versions (8.0 to 14+).
* **Native A4 PDF Engine:** Implemented in `MainActivity.java` via MethodChannel `com.kamaiplus.pos/invoice_pdf`. Uses Android native `PdfDocument` with a 595x842pt canvas (standard A4). Generates crisp vector tables and writes to public `Downloads/` directory via `FileProvider`.

---

## 🎨 4. UI/UX EVALUATION VS PWA REFERENCE (`Refrence PWA Attached/`)

1. **Design Parity Achieved:**
   * High-contrast retail fonts (`Plus Jakarta Sans` / `Inter` / `JetBrains Mono` for numbers).
   * Clean pastel badge containers (`#ECFDF5` emerald, `#FEF3C7` amber, `#FEE2E2` red).
   * Physical POS counter ergonomics: Large touch targets (minimum 44x44dp), no micro-tap frustrations.
   * Floating bottom cart bar with high-contrast yellow button (`#FBBF24`).
2. **Key Polish Added Beyond Reference PWA:**
   * Owner Privacy 4-digit PIN protection for sensitive turnover and profit numbers.
   * Physical Note & Coin Denomination Counter for physical cash drawer reconciliation.
   * Native thermal printer ESC/POS bytes generator supporting cash drawer kick pulse (`kickCashDrawer`).
   * Ultra-compact `SaleCompletedModal` designed for 2-second counter dispatch.

---

## 🚀 5. NEXT PHASE ROADMAP & RECOMMENDATIONS

### Phase 1: High-Priority UI & Parity Polish (Immediate Next)
1. **A4 PDF Download in Transaction History:**
   * Wire `InvoicePdfService` into `SaleDetailModal` (`lib/views/transactions/sale_detail_modal.dart`) so past bills can also download the genuine A4 PDF with 1 tap.
2. **Barcode Studio Batch Mode:**
   * Allow selecting multiple SKUs or inwarded purchase invoices to generate multi-page sticker print jobs.
3. **Customer Credit Limit Alert:**
   * In `PosCheckoutModal`, if customer's Udhar exceeds pre-set credit limit, show an amber alert warning.

### Phase 2: Retail Hardware & Productivity Upgrades
1. **Quick-Add Custom Item in Cart:**
   * An optional "+ Misc Item" button in POS billing for non-barcoded or miscellaneous items (e.g. loose items, sudden tailoring/repair charges).
2. **Direct Bluetooth Auto-Reconnect:**
   * Background daemon that attempts reconnection to the saved thermal printer MAC address when the app starts.

### Phase 3: Cloud & Multi-Terminal Sync
1. **Firestore Multi-Device Conflict Handling:**
   * Automatic merge rules for stock levels when 2 mobile terminals bill concurrently offline.
2. **WhatsApp Cloud API Integration:**
   * Automated headless WhatsApp receipt delivery via Meta Cloud API alongside the current direct WhatsApp app launcher.

---

## 📌 6. CODE ARTIFACT AUDIT SUMMARY
* **Outdated Files Cleaned:** `HANDOVER.md` and `KamaiPlus_Complete_App_Documentation.md` deleted.
* **Active Single Sources of Truth:**
  1. `AGENTS.md` (Constitutional rules & AI instructions).
  2. `APP_FEATURE_MEMORY.md` (Permanent feature & UI memory).
  3. `PROJECT_MASTER_AUDIT_AND_ROADMAP.md` (This document: Architecture, status, and roadmap).
* **Git Anchor Tag:** `v4.17.0-locked-gold` (pointing to commit `e7d4079`).
