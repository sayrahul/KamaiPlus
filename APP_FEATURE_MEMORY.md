# 🧠 KAMAI+ (KAMAIPLUS) — PERMANENT APP FEATURE & DECISIONS MEMORY
> **CRITICAL DIRECTIVE FOR ALL AI AGENTS & DEVELOPERS:**
> Yeh file KamaiPlus app ke sabhi solved features, UI decisions, aur user preferences ka **Single Source of Truth (SSOT)** hai. 
> Koi bhi naya feature ya screen banane se pehle is file ko check karna **COMPULSORY** hai. 
> Yaha likhe kisi bhi solved feature ya user preference ko dubara todna ya revert karna **STRICTLY FORBIDDEN** hai.

---

## 📱 1. BOTTOM NAVIGATION BAR & ROOT ARCHITECTURE (LOCKED)
The Bottom Navigation Bar has 5 items. The navigation contract is strictly defined as follows:

| Index | Tab Label | Type | Target Screen / Action | Behavior & Contract |
|---|---|---|---|---|
| **0** | **Home** | Page Tab | `HomePulseTab` | Dashboard KPI overview, Quick action hubs. Daily Ops has *Cash Register* & *Transactions* (Billing POS removed from grid). |
| **1** | **Product** | Page Tab | `ProductsScreen` | Master catalog. Pencil icon opens `AddProductModal` for full edit. **NO nested bottom nav**. |
| **2** | **Billing** | Page Tab (Center) | `PosBillingScreen` | Quick retail counter billing, elevated center button with green glow. |
| **3** | **Khata** | Page Tab | `KhataScreen` | Digital Khata & Udhar ledger, customer search, WhatsApp reminder, settlement sheet. |
| **4** | **Menu** | **BOTTOM SHEET MODAL ONLY** | `MenuScreen.show(context)` | **NEVER A SEPARATE FULL PAGE!** User clicks Menu $\rightarrow$ slides up as a bottom sheet with close 'X' button. Dismissing returns to current tab. |

> [!CAUTION]
> **MENU IS A BOTTOM SHEET MODAL — NEVER A SEPARATE FULL SCREEN IN PAGEVIEW!**
> Do NOT create a 5th tab in PageView for Menu. Menu must always slide up from the bottom via `MenuScreen.show(context)` and have an 'X' button at the top right to close it.

---

## 🛡️ 2. SOLVED FEATURES & SCREEN-BY-SCREEN INVARIANTS

### 1. 🏠 Home Screen (`lib/views/dashboard/home_pulse_tab.dart`)
* **Daily Counter & OPS Grid:** Exactly 2 cards side-by-side: `Cash Register` and `Transactions`.
* **Billing POS:** Removed from this grid (since Center Billing button is already on bottom navbar).
* **KPI Stats:** Today Sales, Orders count, Net profit, Low stock alert.

### 2. 📦 Products Master (`lib/views/products/products_screen.dart`)
* **Edit Product:** Pencil icon button has dedicated touch target; clicking it calls `AddProductModal(existingProduct: product)` with all fields pre-filled.
* **Add Product:** Top "+" button and AI Vision bill OCR trigger.
* **Bottom Nav:** Must NOT have its own `bottomNavigationBar` inside its Scaffold when displayed inside `HomeDashboardScreen`.

### 3. 🧾 Billing POS (`lib/views/pos/pos_billing_screen.dart`)
* Fast retail grid/list view with instant search and barcode scan.
* Cart bar at bottom with floating cart summary.
* Payment checkout modal with rapid cash chips and dynamic UPI QR code.

### 4. 📖 Digital Khata (`lib/views/khata/khata_screen.dart`)
* Simple, minimalistic, clean UI named **Digital Khata**.
* Top Market Udhar Card with total pending balance and due count.
* Customer row: Name, Phone, Balance, WhatsApp reminder button (official WhatsApp icon).
* Customer Statement bottom sheet: Jama/Udhar ledger history and settlement buttons.

### 5. 📂 Menu Hub Modal (`lib/views/menu/menu_screen.dart`)
* **Type:** Modal Bottom Sheet via `showModalBottomSheet`.
* **Header:** Dark curved banner with "Full Hub Menu", store name, and **close 'X' button**.
* **Sections:** 
  1. *Daily Billing & Counter* (Home, Billing, Transactions, Cash Register)
  2. *Stock & Inventory* (Products & FMCG, Inventory & Alerts, Wholesale Purchases, Barcode Studio)
  3. *Customers & Khata* (Digital Khata, Customers Directory, WhatsApp Growth, Pro Plans)
  4. *Tax, Backup & Settings* (GSTR-1 Reports, Invoice Themes, Cloud Backup, Store Profile & UPI)
* Clicking any sub-screen dismisses the modal and pushes that screen.

### 6. 💵 Cash Register (`lib/views/cash_register/cash_register_screen.dart`)
* Dark gradient hero till balance card.
* 4-metric micro grid: Opening Till, Cash Sales, Cash Expenses, Expected Drawer Cash.
* Rapid expense sheet with quick tags (*Chai/Nashta*, *Supplier*, *Freight*, *Electric*, *Labour*).
* Physical Note & Coin Tally Counter (₹2000 down to ₹1).
* Z-Report generation with 1-tap WhatsApp summary share.
* Has persistent `KamaiBottomNav()`.

### 7. 📜 Transaction History (`lib/views/transactions/transactions_screen.dart`)
* Renamed to **Transaction History**.
* Fast invoice search, date filters (*All*, *Today*, *Yesterday*, *7 Days*, *Month*).
* Payment mode filters (*All*, *Cash*, *UPI*, *Udhar*).
* Invoice details bottom sheet with thermal receipt printing and WhatsApp share.
* Has persistent `KamaiBottomNav()`.

### 8. 📡 Inventory & Expiry Radar (`lib/views/inventory/inventory_screen.dart`)
* Hero Stock Intelligence card with valuation mask/unmask eye toggle.
* 4-metric grid: Tracked SKUs, Inventory Asset, Reorder Alert, Near Expiry.
* 3 pills: *Reorder Radar (0)*, *Near Expiry (0)*, *Stock Audit Trail*.
* Fast action buttons: *Inward Bills* (opens AI Inward) and *Manage Products* (switches to Product tab).
* Has persistent `KamaiBottomNav()`.

### 9. 📑 GST Reports & CA Tax Filing (`lib/views/reports/gst_reports_screen.dart`)
* Export action buttons: *CA Excel (CSV)*, *Tally XML*, *GSTR-1 JSON*.
* Period pills: *This Month*, *Last Month*, *Q1*, *Q2*, *Q3*.
* 4-metric tax grid: Taxable Value, Total GST Tax, CGST/SGST 50:50, B2B Invoices.
* Table 12 HSN-wise Sales Summary with live search bar.
* Has persistent `KamaiBottomNav()`.

### 10. 🎨 Invoice Themes & Design (`lib/views/settings/invoice_themes_screen.dart`)
* 7 circular brand color palettes.
* 4 heading pills (*TAX INVOICE*, *RETAIL INVOICE*, *CASH MEMO*, *ESTIMATE / BILL*).
* Display options checklist with PRO badges.
* Platform Branding strip & editable Terms & Footer notes.
* Live Interactive pixel-accurate A4 invoice paper card with QR code, items table, subtotal, and grand total.
* Has persistent `KamaiBottomNav()`.

### 11. 🚚 Purchases & Restock Orders (`lib/views/purchases/purchases_screen.dart`)
* Wholesale & Mandi Inward Hub banner with *AI Bill / Parcha OCR* and *+ Manual Inward*.
* 4-metric integer paise grid: Total Purchases, Vendor Udhar Due, Received Stock, In-Transit.
* 4 Filter Pills: *All*, *Received*, *In-Transit*, *Udhar Due*.
* Order cards with delivery status, payment badge, items count, and grand total.
* Inward itemized breakdown sheet & Supplier payment settlement sheet.
* 1-tap WhatsApp supplier message.
* Has persistent `KamaiBottomNav()`.

### 12. 👥 Customer Directory & CRM (`lib/views/customers/customers_screen.dart`)
* CRM hero banner with registered customer count & total market dues.
* 4-metric grid: Total Customers, VIP Members, Udhar Due, Active Ledgers.
* Search bar (name/phone) and 4 filter chips (*All*, *Udhar Due*, *VIP*, *Settled*).
* Interactive customer cards: Tapping opens Customer Details Sheet with lifetime spending, bill count, and direct WhatsApp greeting.
* "+ Jama / Udhar" ledger entry dialog with instant SQLite balance reconciliation.
* Has persistent `KamaiBottomNav()`.

### 13. 🏷️ Barcode Studio & Stickers (`lib/views/tools/barcode_studio_screen.dart`)
* Product SKU dropdown selector & label copies counter.
* Realistic 50mm × 25mm thermal sticker card mockup with Code128 graphic bars, store name, MRP, and barcode number.
* Dispatch to Bluetooth thermal printer trigger.
* Has persistent `KamaiBottomNav()`.

### 14. 📢 WhatsApp Growth Campaigns (`lib/views/growth/growth_campaigns_screen.dart`)
* 1-Click WhatsApp marketing banner.
* Target audience selector chips (*All Customers*, *Udhar Due Customers*, *VIP Customers*) with dynamic recipient count.
* Curated campaign cards: Weekend Dhamaka, Festival Mubarak, Polite Khata Reminder, New Stock Arrival.
* 1-tap WhatsApp launch with pre-filled message text.
* Has persistent `KamaiBottomNav()`.

### 15. 🔒 Data Backup & Restore Vault (`lib/views/settings/backup_restore_screen.dart`)
* Encrypted JSON database snapshot export.
* Cloud sync trigger with Firestore status indicator.
* Tally XML vouchers and CA Master CSV exports.
* Has persistent `KamaiBottomNav()`.

### 16. ⚙️ Store Profile & UPI Banking (`lib/views/settings/store_profile_screen.dart`)
* 3 segmented tabs: Store & GST Profile, UPI QR & Banking, Invoice & Bill Rules.
* Store name, address, GSTIN, FSSAI, multi-bank UPI QR codes.
* Has persistent `KamaiBottomNav()`.

---

## 💰 3. FINANCIAL INVARIANT (PAISE MATH)
* **Floating point math (`0.1 + 0.2`) is STRICTLY FORBIDDEN.**
* All money values in state, database, and models are **integer paise** (`₹1 = 100 paise`).
* Always format with `MoneyFormatter.formatINR(amountPaise)` or `MoneyFormatter.formatPaise(amountPaise)`.

---

## 🚫 4. STRICT BEHAVIORAL PROTOCOLS
1. **NO Unsolicited Rewrites or Architecture Changes:**
   Never change the navigation paradigm (e.g. converting a modal to a full page or vice versa) without explicit user confirmation.
2. **NO Duplicate Bottom Navbars:**
   When adding `KamaiBottomNav` to screens, ensure it is ONLY on pushed standalone sub-screens. Primary tabs in `HomeDashboardScreen` must NEVER have inner `bottomNavigationBar`.
3. **NO Automatic APK Compiles:**
   Only compile and install APK on device when the user explicitly commands it (*"har baar APK compile mat karo.. me jab bolunga tabhi"*).

---

## 🔒 5. VALIDATION ENGINE & RETAIL STANDARDS (`lib/core/utils/app_validators.dart`)
Standardized Indian retail input validation across the app:
* **Mobile Numbers:** TRAI 10-digit format (`^[6-9]\d{9}$`). Handles cleaning of `+91`, spaces, hyphens, and leading zeros.
* **OTP Verification:** Strict 4-digit numeric verification (`^\d{4}$`).
* **UPI VPAs:** Dynamic NPCI VPA format (`^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$`).
* **GSTIN:** 15-character Indian GST format (`^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$`).
* **FSSAI License:** 14-digit food business standard (`^\d{14}$`).
* **Pincode:** Indian Postal 6-digit standard (`^[1-9][0-9]{5}$`).
* **Active Bindings:** Wired into `LoginScreen`, `SignupStoreScreen`, `StoreProfileScreen`, `PosCheckoutModal` (quick customer add), and `CustomersScreen` / `KhataScreen`.

---

## ⚡ 6. HIGH-END 24-POINT RETAIL FINTECH UPGRADE SUITE (LOCKED)
Comprehensive enterprise-grade retail UX upgrade suite aligned with PhonePe Business, Paytm for Business, and Khatabook:

### 1. 🏠 Home Pulse Dashboard (`lib/views/dashboard/home_pulse_tab.dart`)
* **KPI Stat Cards (Sales, Bills, Est. Profit, Udhar):** Redesigned with subtle gradients, micro-glow shadows, 1-tap navigation to relevant screens, and an eye toggle to mask/unmask sensitive shop turnover amounts.
* **Audio Payment Flash (Soundbox Feed):** Live Soundbox audio announcement ticker banner showing real-time UPI & cash receipts with a "Bolo" re-announce button calling `SoundboxService.instance.announceHindiPayment`.

### 2. 📦 Products Master (`lib/views/products/products_screen.dart`)
* **List / Grid View Instant Toggle:** Dynamic toolbar button toggling between structured 1-column list and compact 2-column image grid.
* **Smart Stock Badge (Traffic Light Colors):** Red for Out of Stock, Amber for Low Stock (with count left), and Green for Healthy In-Stock.
* **Pencil Edit Icon:** Prominent, high-contrast dedicated edit button on every product item opening the full `AddProductModal`.
* **Quick Price / Stock In-Line Update:** Lightning bolt dialog allowing instantaneous price and stock quantity edits without opening the full product form.
* **Barcode Visual Strip:** Realistic rendered Code128 visual barcode pattern strip displayed beneath SKU barcode numbers.
* **Clean Retail Listing:** Long descriptions hidden from default list view; strictly displays SKU Name, Unit, Selling Price, and Stock Quantity.

### 3. 🧾 POS Billing & Checkout (`lib/views/pos/pos_billing_screen.dart` & `pos_checkout_modal.dart`)
* **Top Search + Barcode Bar:** Fast SKU search with instant barcode scanner trigger and live camera feed.
* **Item Tiles Animation:** Tactile bounce scale micro-interaction (`0.94` scale down on press, bouncy spring return) on tapping product tiles into cart.
* **Floating Bottom Cart Drawer:** Floating elevated pill drawer with item count, total price, and direct checkout CTA.
* **Quick Tender Cash Chips:** Standard Indian currency note tender shortcuts: Exact, ₹50, ₹100, ₹200, ₹500, ₹1000, ₹2000.
* **Customer Auto-Suggest:** Real-time customer search dropdown displaying customer name, phone, and current Khata ledger status badge (`₹X Baki` / `₹X Advance` / `₹0 Clear`).
* **Dynamic UPI QR Code Tab:** High-end merchant counter QR display with 150px crisp QR code, accepted payment apps row, Soundbox ready tag, and 5-minute validity countdown timer.

### 4. 📖 Digital Khata (`lib/views/khata/khata_screen.dart`)
* **Market Udhar Hero Card:** Complete credit summary showing Net Balance, Total Customer Udhar, and Total Advance.
* **Customer Row Hierarchy:** 3-state visual hierarchy with custom borders and badges: Red (`#FECACA`) for Udhar Due + WhatsApp reminder, Green (`#A7F3D0`) for Advance payment, and Slate (`#E2E8F0`) for Settled accounts.
* **Date-Wise Voice Note (Audio Only - No Photos):** Integrated audio note recorder inside Jama & Udhar modals with waveform indicator, recording timer, and playback strip in customer statement ledger. Strictly NO photo attachment capability.

### 5. 💵 Cash Register (`lib/views/cash_register/cash_register_screen.dart`)
* **Galla Till Balance Card:** Live cash drawer balance card with shift status, opening float, cash sales, cash expenses, and expected closing till.
* **Physical Currency Denomination Counter:** Note counter (`₹2000, ₹500, ₹200, ₹100, ₹50, ₹20, ₹10`) and coin counter (`₹5, ₹2, ₹1`) with live count and shortage/excess calculation.

### 6. 📂 Menu Hub Modal (`lib/views/menu/menu_screen.dart`)
* **Grouped Bento Grid Tiles:** Asymmetric Bento Grid layout with hero feature tiles for POS Billing and Kamai+ Pro, categorized into Counter & Billing, Stock & Sourcing, Khata & Growth, and Tax & Settings.
* **Icons & Colors:** Vibrant pastel icon containers, high-contrast borders, and status badge pills (`FAST BILLING`, `AI OCR`, `Z-REPORT`, `UDHAR`, `CA READY`).

### 7. 🚚 Purchases & Mandi Inward (`lib/views/purchases/purchases_screen.dart` & `ai_inward_sheet.dart`)
* **AI Vision Parcha OCR Scanner:** High-tech camera viewfinder modal with scanning laser line animation, handwritten mandi parcha slip preview, OCR extraction confidence, margin calculation, and 1-tap stock inventory save.
* **Supplier Udhar Status Pill:** Prominent vendor dues status pill on each order card and an interactive Supplier Udhar Summary Banner with direct 1-tap settlement and WhatsApp payment vouchers.

### 8. 📑 GST Reports (`lib/views/reports/gst_reports_screen.dart`)
* **HSN-Wise Sales Table:** Official Table 12 HSN summary table with HSN codes (`1902, 1512, 3401, 0402, 2106, 3306, 1006`), descriptions, GST rates (5%, 12%, 18%), UQC units, quantities, taxable values, CGST, SGST, and total invoice values, complete with search and aggregate totals.
* **1-Click CA Export Package:** Complete compliance audit package bundle featuring GSTR-1 JSON, GSTR-3B Excel worksheet, Table 12 HSN CSV, B2B wholesale register, and purchase inward vouchers, with 1-click ZIP export and direct WhatsApp sharing with Chartered Accountants.

---

## 🏛️ 7. PWA DOCUMENTATION PARITY & MASTER HANDOVER (SEPTEMBER 06, 2026)
* **Document Audited:** `KamaiPlus_PWA_Documentation.docx` (51,597 chars, 707 paragraphs, direct audit from `sayrahul/kamai`).
* **14 Database Tables Parity:**
  - `businesses` mapped to `store_profile` SQLite table + `SharedPreferences`.
  - `categories`, `products`, `customers`, `sales`, `ledger_transactions`, `expenses` all verified.
  - Added dedicated SQLite tables: `inventory_movements` (stock audit ledger for SALE, PURCHASE, ADJUSTMENT), `suppliers` (vendor master with `current_balance_paise`), and `cash_register_shifts` (shift history).
  - Every POS sale automatically logs an atomic `inventory_movements` record (`movement_type: 'SALE'`).
  - Stock Audit Trail in `InventoryScreen` reads and renders live movements from `inventory_movements`.
* **Master Handover Document:** Created `HANDOVER.md` in project root covering all completed features, PWA parity analysis, remaining backend/services integrations (Meta Cloud API, Gemini live OCR, Razorpay Android SDK, Bluetooth hardware auto-connect), and UI enhancements.


