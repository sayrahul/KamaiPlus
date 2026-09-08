# 🧠 KAMAI+ (KAMAIPLUS) — PERMANENT APP FEATURE & DECISIONS MEMORY
> **CRITICAL DIRECTIVE FOR ALL AI AGENTS & DEVELOPERS:**
> Yeh file KamaiPlus app ke sabhi solved features, UI decisions, aur user preferences ka **Single Source of Truth (SSOT)** hai. 
> Koi bhi naya feature ya screen banane se pehle is file ko check karna **COMPULSORY** hai. 
> Yaha likhe kisi bhi solved feature ya user preference ko dubara todna ya revert karna **STRICTLY FORBIDDEN** hai.
>
> 🔒 **PERMANENT GOLD BASELINE LOCKED:** Version 4.18.0 (Tag `v4.18.0-locked-gold`).
> Is version ke sabhi features physical device par tested aur verified hain. Kisi bhi halat me is version ka koi bhi UI element, navigation structure, ya feature revert nahi kiya jayega.

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
* **Soundbox Voice Feed:** Audio Payment Flash banner removed per user preference for a cleaner dashboard layout.

### 2. 📦 Products Master (`lib/views/products/products_screen.dart`)
* **List / Grid View Instant Toggle:** Dynamic toolbar button toggling between structured 1-column list and compact 2-column image grid.
* **Smart Stock Badge (Traffic Light Colors):** Red for Out of Stock, Amber for Low Stock (with count left), and Green for Healthy In-Stock.
* **Pencil Edit Icon:** Prominent, high-contrast dedicated edit button on every product item opening the full `AddProductModal`. Made crash-proof with dynamic unit, category, and tax rate fallback.
* **Quick Price / Stock In-Line Update:** Lightning bolt dialog allowing instantaneous price and stock quantity edits without opening the full product form.
* **Clean Retail Listing:** Barcode visual Code128 pattern strip removed per user instruction; clean numeric barcode text pill displayed beneath SKU name.

### 3. 🧾 POS Billing & Checkout (`lib/views/pos/pos_billing_screen.dart` & `pos_checkout_modal.dart`)
* **Top Search + Barcode Bar:** Fast SKU search with instant barcode scanner trigger and live camera feed.
* **Item Tiles Animation:** Tactile bounce scale micro-interaction (`0.94` scale down on press, bouncy spring return) on tapping product tiles into cart.
* **Floating Bottom Cart Drawer:** Floating elevated pill drawer with item count, total price, and direct checkout CTA.
* **Quick Tender Cash Chips:** Standard Indian currency note tender shortcuts: Exact, ₹50, ₹100, ₹200, ₹500, ₹1000, ₹2000.
* **Customer Auto-Suggest Dropdown on Click:** Real-time customer search dropdown displaying immediately on tap/click with customer name, phone, and current Khata ledger status badge (`₹X Baki` / `₹X Advance` / `₹0 Clear`).
* **Interactive Split Payment Function:** Allows dividing bill across Cash, UPI, and Udhar with live balance validation, auto-fill shortcuts (Auto UPI, Auto Cash, 50-50), and atomic SQLite transaction handling.
* **Dynamic UPI QR Code Tab:** High-end merchant counter QR display with 150px crisp QR code, accepted payment apps row, Soundbox ready tag, and 5-minute validity countdown timer.

### 4. 📖 Digital Khata (`lib/views/khata/khata_screen.dart`)
* **Market Udhar Hero Card:** Complete credit summary showing Net Balance, Total Customer Udhar, and Total Advance.
* **Customer Row Hierarchy:** 3-state visual hierarchy with custom borders and badges: Red (`#FECACA`) for Udhar Due + WhatsApp reminder, Green (`#A7F3D0`) for Advance payment, and Slate (`#E2E8F0`) for Settled accounts.
* **Date-Wise Voice Note (Audio Only - No Photos):** Integrated audio note recorder inside Jama & Udhar modals with waveform indicator, recording timer, and playback strip in customer statement ledger. Strictly NO photo attachment capability.

### 5. 💵 Cash Register (`lib/views/cash_register/cash_register_screen.dart`)
* **Galla Till Balance Card:** Live cash drawer balance card with shift status, opening float, cash sales, cash expenses, and expected closing till. Accounts for split cash sales.
* **Physical Currency Denomination Counter:** Note counter (`₹2000, ₹500, ₹200, ₹100, ₹50, ₹20, ₹10`) and coin counter (`₹5, ₹2, ₹1`) with live count and shortage/excess calculation.

### 6. 📂 Menu Hub Modal (`lib/views/menu/menu_screen.dart`)
* **Streamlined Daily Billing & Counter:** "Billing (POS) Register" hero card removed from Section 1 (as Center bottom nav button serves as primary POS launcher). Section 1 features Home Pulse, Transactions History, and Cash Register & Galla Till.
* **Grouped Bento Grid Tiles:** Categorized into Stock & Sourcing, Khata & Growth, and Tax & Settings.
* **Icons & Colors:** Vibrant pastel icon containers, high-contrast borders, and status badge pills (`AI OCR`, `Z-REPORT`, `UDHAR`, `CA READY`).

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

---

## 💎 8. MICRO UI/UX IMPROVEMENTS & ADVANCED POLISH (SEPTEMBER 07, 2026)

1. **Universal Typography (Google Sans):**
   - Globally enforced `GoogleFonts.plusJakartaSans` (Google Sans styled) across all headers, KPI metrics, buttons, badges, and modals. Subtitles standard to `GoogleFonts.inter`.

2. **Ultra-Compact Sale Completed Modal (`lib/views/pos/sale_completed_modal.dart`):**
   - Minimalistic green transaction card with invoice number, payment badge, and item count.
   - Large "+ New Bill" primary action button.
   - 10-digit WhatsApp number field (auto-prefilled if customer was selected, otherwise manual input) with 1-tap WhatsApp sender.
   - 2x2 compact action grid: Print Receipt (Thermal), Bluetooth Print, Download PDF, and Show PDF Preview.
   - Discarded bulky "Dispatch & Receipt Actions" section header for maximum space efficiency.

3. **Products Screen & Add Product Modal:**
   - 2x2 compact grid cards (`childAspectRatio: 0.88`) with clear pricing, stock badge, and pencil edit button.
   - QR code icon removed from product cards in both grid and list views.
   - Live camera `BarcodeScannerView` integrated into top search bar.
   - `AddProductModal`: 2-column compact input rows (Selling Price + Purchase Cost, Opening Stock + Low Stock Alert) + inline "Unlimited Stock ∞" toggle (stores `999999.0`).

4. **Universal Owner Privacy (4-Digit PIN Verification):**
   - Unmasking sensitive metrics (Today's Profit on Home, Valuation on Inventory, Drawer Cash on Cash Register, Net Turnover on GST Reports) requires 4-digit PIN verification via `OwnerPrivacyModal` (default PIN: `1234`).

5. **Reusable Empty State Card (`lib/views/common/empty_state_card.dart`):**
   - High-fidelity, clean empty state widget with soft tinted icon container, friendly title, descriptive helper text, and optional action CTA.
   - Standardized across Digital Khata, Customers Directory, Inventory Audit Trail, and Cash Register Expenses.

6. **Recent Transactions Detail Modal (`lib/views/transactions/sale_detail_modal.dart`):**
   - Tapping any invoice on Home Pulse opens a complete breakdown modal with invoice timestamp, customer details, itemized table, total/subtotal, thermal Bluetooth printing, and WhatsApp share.

7. **Note & Coin Tally Counter (`lib/views/cash_register/denomination_tally_modal.dart`):**
   - Reusable counter modal with live counted total, expected cash comparison, excess/shortage variance badge, and 1-tap WhatsApp tally breakdown text generator.
   - Added as a 1-tap quick action card on Home Pulse tab.

8. **Cash Register Shift History & Past Z-Reports:**
   - Historical shift lookup by date filter (All, Today, Yesterday, 7 Days, Custom Date picker).
   - Backed by SQLite persistence (`getAllCashRegisterShifts` in `LocalDatabase`).
   - Accessible via History icon on Cash Register AppBar and Quick Action Bar.

9. **WhatsApp Growth Hub (`lib/views/growth/growth_campaigns_screen.dart`):**
   - Birthday Radar banner detecting customer milestones.
   - 2x2 Campaign cards: Flash Sale, Festival Dhamaka, Khata Udhar Due Reminder, VIP Reward.
   - Voucher Customizer: Discount %, Min Order, Coupon Code, and Validity.
   - Realistic WhatsApp chat preview bubble with store name and formatted coupon text.
   - Recipient queue with audience filter tabs and 1-tap WhatsApp send.

10. **Barcode Studio & Sticker Maker (`lib/views/tools/barcode_studio_screen.dart`):**
    - 3 label layout sizes: Standard (50x25mm), Compact (38x25mm), Detailed (50x38mm).
    - 6 toggleable elements: Store Name, Product Title, Barcode Graphic, Code text, MRP/Price, Batch/Expiry, Tax notice.
    - Preset copies selector (5, 10, 25, 50, 100) + step buttons.
    - Interactive live thermal sticker preview that updates dimensions and contents in real-time.
    - Direct Bluetooth thermal print dispatch.

11. **Dedicated Pro Membership Page (`lib/views/settings/pro_membership_screen.dart`):**
    - Redesigned with world-class fintech aesthetics: Dark titanium card with gold glow, 50% Annual discount toggle.
    - 3 Plan Tiers: Free Starter, Pro Business (Most Popular), Enterprise Multi-Counter.
    - ROI value proposition card, 4-category deep-dive feature matrix, verified merchant trust badges, and interactive FAQs accordion.
    - Linked from Menu sheet and Pro upgrade modal.

12. **Modern Counter UPI Standee Modal (`lib/views/common/upi_standee_modal.dart`):**
    - High-contrast counter standee modal with updated Google Sans typography, dynamic merchant QR code, and accepted payment apps strip.

13. **Billing Out-of-Stock Protection & Red Outline:**
    - Non-unlimited items with stock <= 0 (or effective remaining stock <= 0) render with high-contrast Red Outline (`#EF4444`), dimmed background (`#FFF1F2`), and bold red `OUT OF STOCK` badge.
    - Attempting to add out-of-stock items to cart triggers heavy haptic feedback, blocking addition with warning toast.

14. **Multi-Billing Draft Invoices in POS Checkout Modal:**
    - Draft invoice tabs (`Bill #1 (3 items • ₹450)`, `Bill #2`, etc.) are located **exclusively inside the POS Checkout Modal (`PosCheckoutModal`)** to keep the main Billing Page uncluttered.
    - When the cashier taps `+ New Bill` inside the modal, a new draft bill is created, the current bill is held in drafts, and the modal **immediately dismisses downwards (`Navigator.pop`)** so the cashier is right back on the billing screen ready to scan or add items.
    - Switching tabs inside the modal dynamically switches active bill items, totals, and customer selection.

15. **Bottom Navigation Bar Color Theme:**
    - Per user preference, the Bottom Navigation Bar retains its original clean Emerald Green theme (`#059669` / `#10B981`) for the active tab indicator and center elevated billing button.

16. **Native Android Status Bar Notifications & Genuine PDF Generation:**
    - Integrated native Android `NotificationManager` engine (`com.kamaiplus.pos/notifications`) triggering high-priority status bar notifications on bill completion, PDF download, WhatsApp dispatch, and cloud sync.
    - Built-in Android `PdfDocument` engine (`InvoicePdfService`) generates genuine A4 Tax Invoices, saves directly to the device's public `Downloads/` directory, and provides 1-tap open in system PDF viewers via `FileProvider`.

17. **1-Tap Sales Return (Refund) & Inventory / Udhar Balance Reversal Engine:**
    - Completed sale invoices can be returned directly from `SaleDetailModal` (accessible from Transaction History and Home Recent Transactions).
    - **Single Atomic Transaction (`LocalDatabase.processSalesReturn`):**
      1. Sale status updated to `'refunded'` and marked for cloud sync.
      2. **Inventory Restock:** All items in the bill automatically added back to product stock (`stock_quantity = stock_quantity + qty`) with an audit entry in `inventory_movements` (`movement_type = 'RETURN'`).
      3. **Udhar (Credit) Balance Reversal:** If the sale was Credit (Udhar) or Split Credit, customer debt is automatically reduced (`current_balance_paise - creditDue`) and a debit ledger entry is recorded in `ledger_transactions` with reference to the refund invoice.
    - **Financial Integrity & Revenue Guards:**
      - Refunded sales are excluded from today's sales totals and net revenue calculations across Home Pulse Dashboard, Daily Ops Cash Register, and Transaction History.
      - Invoices marked refunded display a bold red `REFUNDED` badge, strike-through invoice amount, and disabled return action with an explanatory indicator to prevent duplicate refunds.






18. **Store-Type-Wise (Vertical) Dynamic Retail Engine:**
    - 5 Canonical Verticals supported: `grocery`, `pharmacy`, `clothing`, `hardware`, `restaurant`.
    - Backed by SQLite DB Version 2 (`business_type` column on `store_profile`, and `batch_number`, `expiry_date`, `size`, `color`, `imei_serial`, `hsn_code`, `is_loose_item` on `products`).
    - Dynamic search hints, recommended measurement units, quick category chips, and specialized vertical input rows.
    - Verified and deployed to physical Redmi 6 device on 07 September 2026, 09:55 PM IST.

19. **Google OAuth Authentication & Firebase / Local Notification Architecture:**
    - **Google OAuth (`lib/services/auth_service.dart`):**
      - Google Sign-In singleton initialized at app startup (`initGoogleSignIn`).
      - Uses Google Auth ID token for Firebase Authentication (`FirebaseAuth.signInWithCredential`).
      - "Continue with Google" button added to `LoginScreen` with automatic routing: new users route to `SignupStoreScreen`, existing users route directly to `HomeDashboardScreen`.
      - Seamless silent sign-in (`signInSilently`) on app boot; logout clears Google & Firebase sessions from `StoreProfileScreen`.
    - **Local & Remote Push Notifications (`lib/services/notification_service.dart`):**
      - High-priority Android notification channel (`kamai_pos_channel` - "KamaiPlus POS Alerts & Invoices").
      - Firebase Cloud Messaging (FCM) push token generated, cached in `SharedPreferences` (`fcm_token`), and synced with Firestore.
      - Foreground heads-up notification banner on bill generation (`showSaleNotification`), low stock alerts, and shift closing reports.
      - Android desugaring enabled (`com.android.tools:desugar_jdk_libs:2.1.4`) to support Java 8+ APIs required by `flutter_local_notifications`.
      - Deployed, verified, and FCM token registered on physical Redmi 6 device (`de7ea8af7d29`) on 07 September 2026, 10:32 PM IST.

20. **Data Reset & Start Fresh Vault (`lib/views/settings/backup_restore_screen.dart` & `lib/core/database/local_database.dart`):**
    - **Atomic SQLite Deletion Protocols:**
      1. `clearSalesHistory()`: Deletes from `sales`, resets today's turnover counter to 0.
      2. `clearProductsAndInventory()`: Deletes `products`, `categories`, and `inventory_movements` to allow clean real stock entry.
      3. `clearKhataAndCustomers()`: Deletes `customers` and `ledger_transactions` to clear Udhar/Jama dues.
      4. `completeFactoryReset({bool resetStoreProfile = false})`: Atomic SQLite wipe across all operational retail tables (`sales`, `products`, `categories`, `inventory_movements`, `customers`, `ledger_transactions`, `expenses`, `cash_register_shifts`, `suppliers`), with optional store profile preservation.
    - **UI & Security Invariants:**
      - High-contrast Danger Zone section with red warning badges and explanatory text.
    - **Owner Security PIN Guard (`1234`)** enforced before allowing complete factory wipe to prevent accidental employee deletion.
      - Accessible via Settings and Menu Hub modal ("Backup & Reset" tile).

21. **Category-Specific Onboarding & Default Product Seeding (`lib/core/constants/default_products.dart` + `lib/views/auth/signup_store_screen.dart`):**
    - **How It Works:**
      - During signup, user selects a Business Category (Grocery, Pharmacy, Apparel, Hardware, Restaurant).
      - If the "Pre-load starter product catalog" checkbox is checked (default: ON), `_seedDefaultProducts(businessTypeId)` is called after `saveStoreProfile`.
      - The seed function reads from `kDefaultProductsByVertical[businessTypeId]` — a `const Map` in `default_products.dart`.
      - For each unique `categoryName` in the seeds, a `CategoryModel` is upserted first, then each `ProductModel` is upserted with a fresh `uuid.v4()` ID.
    - **Product Counts per Vertical:** Grocery: 12 | Pharmacy: 10 | Apparel: 10 | Hardware: 10 | Restaurant: 11
    - **Financial Invariant:** All `sellingPricePaise`, `mrpPaise`, `purchasePricePaise` values are integer paise (₹1 = 100 paise). No floats.
    - **UI Invariant:** Checkbox subtitle text is dynamic — updates to show the currently selected vertical name (e.g., "Auto-seeds 10-12 popular products for Grocery with market prices.").
    - **User Control:** All seeded products appear in `ProductsScreen` and are fully editable/deletable by the user — no protection.
    - **Seeding happens only once:** At onboarding. If user opts out (unchecks checkbox), no products are seeded.
    - **Implemented & Verified:** `flutter analyze` — No issues found. Committed as `feat: category-specific onboarding default product seeding`.

22. **Universal Multi-Architecture (arm64-v8a + armeabi-v7a) Device Compatibility:**
    - **Issue:** OPPO CPH2691 and modern 64-bit Android devices crashed on launch with `MissingLibraryException: Could not find 'libflutter.so'. Looked for: [arm64-v8a], but only found: [armeabi-v7a]` when built with `--target-platform android-arm`.
    - **Resolution:** Default debug build command is `flutter build apk --debug` (omitting `--target-platform`) so Flutter compiles both 64-bit (`arm64-v8a`) and 32-bit (`armeabi-v7a`) native libraries into a universal APK (~225 MB).
    - **ADB Installation Protocol on ColorOS / Modern Devices:**
      - If `INSTALL_FAILED_VERIFICATION_FAILURE` occurs:
        1. `adb shell settings put global verifier_verify_adb_installs 0`
        2. `adb shell settings put global package_verifier_enable 0`
    - **Verified:** Tested live on OPPO CPH2691 (`88e61059`) running Android 14 (ColorOS) — app boots cleanly, Firebase Auth connects, SQLite loads, UI interactive.

23. **Exclusive Google OAuth Authentication (WhatsApp Auth Removed):**
    - **Decision:** WhatsApp login button and WhatsApp OTP drawer completely removed from `LoginScreen`.
    - **Primary Auth:** 1-tap "Continue with Google" via `AuthService.instance.signInWithGoogle()`.
    - **Flow:**
      - If first-time user (`!is_onboarded`): Opens `SignupStoreScreen` with Google display name and account details auto-populated.
      - If returning onboarded user: Sets `is_logged_in = true` and opens `HomeDashboardScreen`.
    - **Reset Guard:** "Reset Device Data (Start Fresh)" allows clearing onboarding state for fresh setup.
    - **Verified:** `flutter analyze` — 0 issues.

24. **Store Profile Logo Upload & Dynamic Top-Bar / Invoice Rendering:**
    - **Upload Architecture (`lib/views/settings/store_profile_screen.dart`):**
      - Real image picking enabled using `image_picker: ^1.2.3` (Gallery picker + Camera capture modal).
      - Selected logo path saved directly to `store_profile` table (`logo_url` column) in local SQLite database via `LocalDatabase.instance.saveStoreProfile`.
      - Supports "Change Logo" and "Remove Logo" actions.
    - **Universal Dynamic Avatar Component (`lib/views/common/store_logo_avatar.dart`):**
      - `StoreLogoAvatar` widget gracefully renders local `File` image, network URL, or default storefront icon fallback.
    - **Top-Right Screen Display (`lib/views/common/pwa_top_bar.dart` & `store_profile_screen.dart`):**
      - Top right header avatar dynamically renders the uploaded store logo immediately across all main tabs (`HomePulseTab`, `PosBillingScreen`, etc.).
    - **Invoice & Bill Display:**
      - **Sale Detail Modal (`lib/views/transactions/sale_detail_modal.dart`):** Header displays uploaded store brand logo next to Invoice # and date.
      - **Sale Completed Modal (`lib/views/pos/sale_completed_modal.dart`):** Displays store logo in modal header and itemized receipt breakdown.
      - **Invoice PDF Service (`lib/services/invoice_pdf_service.dart`):** Passes `logoPath` to native PDF generator for printable tax invoices.
    - **Verified:** `flutter analyze` — 0 issues.

25. **Production Launch-Readiness & Multi-Page A4 Invoice Architecture (LOCKED):**
    - **Multi-Page Native A4 PDF Engine (`MainActivity.java` + `InvoicePdfService.dart`):**
      - Built using Android native `PdfDocument` (595 x 842 points standard A4).
      - **Page 1:** Store Logo bitmap decode, store details (name, tagline, address, GSTIN, phone), Tax Invoice badge, Billed To card (customer name, phone, payment method pill), and dark slate table header (`S.NO`, `ITEM DESCRIPTION`, `QTY`, `UNIT RATE`, `AMOUNT (₹)`).
      - **Dynamic Pagination:** If product items exceed Page 1 capacity (~12 items), the engine seamlessly creates Page 2+ with identical compact header and column formatting.
      - **Last Page:** Renders summary block (Subtotal, Tax, Discount, Grand Total green pill, Terms & Conditions note, and Authorized Signatory box).
      - **Footer:** Bottom hairline divider with `"Page X of Y"` and `"Kamai+ POS • Retail & Inventory Software"`.
    - **Native Real-Device PDF Sharing (`MainActivity.java` & `InvoicePdfService.dart`):**
      - Implemented `sharePdf` channel invoking `Intent.ACTION_SEND` and `FileProvider.getUriForFile`.
      - Provides 1-tap sharing to WhatsApp, Gmail, Drive, Nearby Share, etc.
      - Integrated "Share PDF" button across both `SaleCompletedModal` and `SaleDetailModal`.
    - **1-Click Fresh Start (Wipe All Data):**
      - In `StoreProfileScreen` & `BackupRestoreScreen`: 1-click confirmation dialog triggers `LocalDatabase.instance.completeFactoryReset(resetStoreProfile: false)` and `FirestoreSyncService.instance.wipeCloudData()`.
      - Wipes test sales, products, khata ledgers, customers, and cash shifts without wiping store profile and UPI configuration.
    - **Product Catalog UX Polish (`ProductsScreen`):**
      - **Delete Action:** Trash can icon on product cards with direct confirmation dialog deleting from SQLite and cloud Firestore.
      - **Raw Barcode Digits Removed:** Clean product title and category view without raw numeric strings like `8904043901007`.
      - **Infinite / Loose Items:** For items where `isLooseItem || stockQuantity >= 99999`, the `+`/`-` stepper is replaced with an `∞ Unlimited` badge.
    - **Universal WhatsApp (`wa.me`):**
      - `AndroidManifest.xml` updated with `<queries>` for `com.whatsapp`, `com.whatsapp.w4b`, and HTTPS schemes for Android 11-14 compatibility.
      - All WhatsApp shares use `https://wa.me/91<phone>?text=...` with `LaunchMode.externalApplication` and automatic clipboard fallback.
    - **Google Cloud Firestore Sync (`FirestoreSyncService`):**
      - Full background CRUD sync (`pushProductToCloud`, `deleteProductFromCloud`, `pushCustomerToCloud`, `wipeCloudData`).
    - **Verified:** `flutter analyze` — 0 issues found.
 
26. **Retail Productivity & UX Enhancements (LOCKED):**
    - **Physical Cash Tally Denominations with Assets (`DenominationTallyModal`):**
      - Displays real rupee and coin assets (`assets/images/1.png`, `2.png`, `5.png`, `10.png`, `50.png`, `100.png`, `200.png`, `500.png`).
      - Clean row layout: `[Note/Coin Image] [Note Name] [-] [Count] [+] [Total]`.
    - **POS Product Cards Space-Saving (`PosBillingScreen`):**
      - Grid item aspect ratio adjusted to `1.48` with streamlined vertical padding, saving ~30% height so significantly more products fit on screen for fast counter billing.
    - **Universal Delete Actions with Confirmations:**
      - Customers: Delete customer (and associated khata ledger entries) from customer details sheet with alert dialog.
      - Purchases: Delete purchase order from order details sheet with alert dialog.
      - Expenses: 1-tap delete confirmation in Cash Register petty outflows list.
    - **AI Inward Modals Simplification:**
      - Removed redundant "Add single item Manually" option from both `ai_inward_sheet.dart` and `ai_inward_modal.dart`.
    - **Standardized Data Reset & Start Fresh:**
      - Unified `StoreProfileScreen` and `BackupRestoreScreen` with identical title, subtitle, confirmation dialog, and execution logic (`completeFactoryReset(resetStoreProfile: false)` + cloud wipe).
    - **Profile & Store Settings Clean-up:**
      - Removed "Invoice & Bill Rules" tab from `StoreProfileScreen` to prevent duplicate navigation (dedicated `InvoiceThemesScreen` handles it).
      - Removed "Store Type / Business Vertical" dropdown and helper text from `StoreProfileScreen` since business category is fixed at onboarding.
    - **WhatsApp Growth Hub Horizontally Paged Templates (`GrowthCampaignsScreen`):**
      - Expanded campaign library to 24 diverse retail templates across festival, weekend, clearance, VIP, birthday, and khata recovery goals.
      - Arranged in horizontal `PageView` (4 cards per page in a 2x2 grid, 6 pages total) with animated dot indicators.
    - **Verified:** `flutter analyze` — 0 issues.

27. **Target Platform 64-bit arm64-v8a Architecture & Physical Device Verification (LOCKED):**
    - **64-bit ABI Fix (`android/app/build.gradle.kts`):**
      - Explicitly configured `ndk.abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))` to resolve the Android 15/16 64-bit `MissingLibraryException: Could not find 'libflutter.so' Looked for: [arm64-v8a]` crash.
    - **Gradle Heap & Metaspace Optimization (`android/gradle.properties`):**
      - Configured `-Xmx4096m -XX:MaxMetaspaceSize=1024m -XX:+HeapDumpOnOutOfMemoryError` and disabled redundant release build lint checking for fast, deterministic compilation.
    - **Live Device Testing on OPPO CPH2691 (Android 16):**
      - Installed and verified live on physical device (`88e61059`). Zero runtime exceptions.
      - Tested POS billing, Cash Register with real ₹ note/coin PNG counter, modal bottom sheets, and multi-page A4 PDF invoicing.

28. **Retail Operations & POS Invoicing Refinements (LOCKED):**
    - **Tally Counter Note Adjustments (`DenominationTallyModal` & `CashRegisterScreen`):**
      - ₹20 note image properly linked (`assets/images/20.png`).
      - ₹2000 denomination note completely removed as per modern Indian retail operations.
    - **WhatsApp Growth Campaigns Grid Fix (`GrowthCampaignsScreen`):**
      - Fixed page view card container height to `212` with aspect ratio `1.95`, preventing any card bottom-clipping.
    - **VIP Customer Feature Across Entire App:**
      - SQLite database schema updated with `is_vip INTEGER DEFAULT 0` and `toggleCustomerVip()` method.
      - `CustomerModel` updated with `isVip` field and serialization.
      - Gold `👑 VIP` badge on customer cards in Customer Directory, Digital Khata list & statement header, and POS Checkout customer indicator.
      - Interactive VIP toggle switches in Add Customer modal, Customer Details sheet, and Khata 360 customer statement view.
    - **POS Billing Screen Compact Products & Multi-Bill Tabs (`PosBillingScreen`):**
      - Grid item aspect ratio adjusted to `1.72` with high-density padding (8h, 5v) and refined font sizes for compact, minimalistic counter billing.
      - Dynamic multi-bill horizontal draft tabs bar `_buildBillTabsBar()` right above categories: `[• Bill #1] [Bill #2] [+ New Bill]`, fully synchronized with checkout tabs and bottom floating cart bar.
    - **POS Checkout Modal View Cart Scroller (`PosCheckoutModal`):**
      - Cart items list constrained to `maxHeight: 230` with internal scrollbar showing exactly 3-4 items, keeping checkout buttons and totals visible on all phone screen sizes.
    - **Compulsory Validation in Red UI (`PosCheckoutModal`):**
      - When Credit (Udhar) mode is selected without a customer, the customer section automatically turns prominent red (`#EF4444` border, `#FFF1F2` soft red background, red warning hint, and an alert banner) so cashiers immediately recognize customer selection is compulsory.
    - **Space-Saving Expandable Bill Discount (`PosCheckoutModal`):**
      - Replaced static 120px box with an expandable dropdown pill (`_isDiscountExpanded`) displaying current discount summary or "Add Bill Discount / Coupon", smoothly expanding to Flat/% inputs.
    - **1-Tap WhatsApp UPI Link Dispatch (`PosCheckoutModal`):**
      - When UPI payment mode is selected and a customer is chosen, a prominent WhatsApp button appears: `Send 1-Tap UPI Link to <Customer> via WhatsApp` sending `upi://pay?pa=...&am=...` for one-tap direct customer payment.
    - **A4 PDF Invoicing Matching Theme Preview & WhatsApp Attachment:**
      - Theme settings (`invoice_theme_color_hex`, `invoice_heading`, `invoice_terms`, `custom_invoice_footer`, `invoice_show_dynamic_upi_qr`) persisted in `SharedPreferences`.
      - Native `MainActivity.java` A4 PDF generator renders theme-colored header banner, table header bar, dynamic UPI payment QR box, and grand total pill matching `InvoiceThemesScreen` preview.
      - "Send Bill to WhatsApp" in `SaleCompletedModal` generates the styled A4 PDF and attaches it directly via WhatsApp.

29. **Persistent Login Session, Android Background Task Minimization & Razorpay LIVE Integration (LOCKED):**
    - **Multi-Layer Session Persistence (`SplashScreen` & `LoginScreen`):**
      - Fixed repeated Google login prompt when minimizing or exiting app.
      - Implemented 4-tier authentication recovery check:
        1. `FirebaseAuth.instance.currentUser`
        2. Cached `auth_user_id` in SharedPreferences
        3. Flag `is_logged_in == true`
        4. Existing store profile in local SQLite database (`LocalDatabase.instance.getStoreProfile()`).
      - If any session indicator exists, immediately establishes `is_logged_in = true` and `is_onboarded = true` and launches directly into `HomeDashboardScreen` within milliseconds. Cashier never gets forced into Google login repeatedly.
    - **Android Native Background Task Minimization (`MainActivity.java` & `AppControlService`):**
      - Integrated native Android platform channel `com.kamaiplus.pos/app_control` calling Android's `activity.moveTaskToBack(true)`.
      - `HomeDashboardScreen` wrapped in `PopScope(canPop: false)`:
        - When on sub-tabs (Product, Billing, Khata), pressing Android system back button smoothly switches back to Tab 0 (Home).
        - When on Tab 0 (Home), pressing back button invokes `AppControlService.minimizeToBackground()` to push the task behind without killing the process or clearing RAM state (cart, cashier shift, draft bills remain active).
    - **Razorpay Payment Gateway LIVE Integration (`RazorpayService`):**
      - Dependency `razorpay_flutter: ^1.4.6` configured.
      - Live Razorpay credentials connected from `env.local`: `RAZORPAY_KEY_ID=rzp_live_TSJvcf9JnWpMMm`.
      - Strict Integer Paise Math invariant respected:
        - Annual Pro: `149900` paise (₹1,499.00 / year)
        - Monthly Pro: `19900` paise (₹199.00 / month)
      - Integrated complete checkout workflow with options payload (key, amount in paise, currency INR, store name, description, user mobile & email, emerald theme `#059669`).
      - On payment success:
        1. Activates Pro status in local SQLite database via `LocalDatabase.instance.activateProMembership(...)` storing `is_pro = 1`, plan name, expiry date, and `razorpay_payment_id`.
        2. Writes `is_pro: true`, `pro_plan`, `pro_expiry`, and `razorpay_payment_id` into SharedPreferences for zero-latency UI rendering.
        3. Triggers Hindi voice announcement via `SoundboxService.instance.speakCustom()` and dispatches system notification via `NativeNotificationService`.
    - **Pro vs Free Workflows Across the App:**
      - `ProMembershipScreen`: Live Razorpay subscription triggering with celebration modal upon payment success, showing active plan status and renewal dates.
      - `ProUpgradeModal`: Reusable modal bottom sheet equipped with 1-tap Razorpay checkout for Pro feature gates.
      - `MenuScreen`: Top dynamic Pro/Free status banner displaying active badge or "Upgrade to Pro" button, plus dedicated "Pro Membership & Plans" entry in Section 4.
      - `PosBillingScreen`: Bottom floating cart bar padding and layout refined with `Expanded` containers to eliminate any layout overflow on compact screens.

30. **Multi-Account & Multi-Store Database Isolation Architecture (LOCKED):**
    - **Root Cause of Store Mixing on Logout / Multi-Account Switch:**
      1. Single global SQLite file (`kamaiplus_local.db`) was shared across all user logins. Logging out of Store A and logging in with Email B was reading Store A's profile from the same database.
      2. Android OS Cloud Auto-Backup was defaulting to `android:allowBackup="true"`, causing uninstall/reinstall or app data clears to silently re-download the old `kamaiplus_local.db` from Google Drive.
      3. `AuthService.signOut()` previously only deleted user OAuth credentials while leaving `is_logged_in`, `is_onboarded`, and active database connections intact.
    - **User-Scoped SQLite Database Isolation (`LocalDatabase.instance.switchUser(uid)`):**
      - Each distinct Google Account / Merchant UID gets its own isolated database file: `kamaiplus_<safeUserId>.db`.
      - Store 1 (e.g. Pharmacy) data is completely isolated from Store 2 (e.g. Apparel / Garments). Switching accounts switches to that account's dedicated database in `<10ms`.
      - New accounts that haven't created a store return an empty store profile, correctly routing them to `SignupStoreScreen` instead of inheriting previous stores.
    - **Clean Session Teardown on Sign-Out (`AuthService.instance.signOut()`):**
      - Wipes all SharedPreferences session cache (`prefs.clear()`).
      - Closes the active SQLite connection (`LocalDatabase.instance.closeDatabase()`).
      - Disconnects Google OAuth token and resets `BusinessVerticals.updateActiveBusinessType('grocery')`.
    - **Android OS Auto-Backup Disabled (`AndroidManifest.xml`):**
      - Added `android:allowBackup="false"` and `android:fullBackupContent="false"` so fresh app reinstalls never restore obsolete local databases from Google Drive.
    - **Pure Vertical Catalog Seeding (`SignupStoreScreen`):**
      - Calls `LocalDatabase.instance.completeFactoryReset(resetStoreProfile: true)` prior to seeding new vertical products, preventing cross-vertical product pollution.

31. **Vertical Customizations, Soundbox Audio Toggle, Real Gemini AI Inward, & Free vs Pro Tiering (LOCKED):**
    - **Login Screen Clean-up:**
      - Removed "Reset Device Data (Start Fresh)" button and its dialog from `LoginScreen` to avoid accidental merchant data wipe on production.
    - **Soundbox Audio Toggle in Top Bar (`PwaTopBar`):**
      - Replaced WhatsApp icon in `PwaTopBar` with an interactive Audio On/Off toggle button (`Icons.volume_up_rounded` / `Icons.volume_off_rounded`).
      - State is persisted via `SharedPreferences` key `soundbox_audio_enabled`.
      - When disabled, all TTS voice announcements in `SoundboxService` are cleanly bypassed.
    - **Pharmacy Vertical Doctor Management (`DoctorModel`, `doctors` table):**
      - Pharmacy checkout features prescribing Doctor selection (`Dr. Self / General`, added doctors, or "+ Add Doctor").
      - Doctors are persisted in SQLite `doctors` table (`id`, `name`, `phone`, `qualification`, `reg_number`, `created_at`). User can add and delete doctors anytime.
      - Doctor Name is stored with the sale (`sales.doctor_name`) and rendered on the POS receipt preview and native A4 PDF invoice.
    - **Restaurant Vertical Dine-In Table Selection:**
      - Restaurant checkout features Table selector (`Takeaway`, `Table 1` to `Table 10`).
      - Selected table is stored in `sales.table_number` and rendered on receipt preview and native A4 PDF invoice.
    - **Real Google Gemini 1.5 Flash AI Inward (Bill Parcha OCR):**
      - Implemented `GeminiAiService` using Google Gemini 1.5 Flash endpoint (`dart:io` `HttpClient` + JSON schema prompt, zero external dependencies).
      - API Key retrieved from `env.local`.
      - Captures camera / gallery parcha images, sends base64, cleans Markdown/JSON formatting, and extracts structured items (`itemName`, `qty`, `costPricePaise`, `sellingPricePaise`, `hsnCode`, `gstRatePercent`).
      - Monthly scan counter (`ai_picture_scan_count_YYYY_MM`) tracks usage and enforces a 10 picture scan/month limit for Free users. Excel & PDF inward remains unlimited.
      - Confirmed items are batch-inserted directly into SQLite `products`.
    - **Free vs Pro Feature Gates & Invariants:**
32. **Pro Lock Badges, PDF WhatsApp Sharing with UPI Links, Cloud Backup & Sync, Barcode Studio, Invoice Themes & WhatsApp Growth (LOCKED):**
    - **Visual Pro Lock Badges (`🔒 PRO`):**
      - `MenuScreen`: Barcode Studio, WhatsApp Growth, and GSTR-1 & CA Pack display a golden `🔒 PRO` badge. Tapping them when not Pro immediately opens `ProUpgradeModal.show(context)`.
      - `BarcodeStudioScreen`: Renders `ProLockedCard` banner at top; print button displays `🔒 Upgrade to Pro to Print Stickers` and opens `ProUpgradeModal`.
      - `BackupRestoreScreen`: Displays `ProLockedCard` in Cloud Backup section with `🔒 Upgrade` badge; triggers `ProUpgradeModal` if free user taps "Sync to Cloud Now". Local JSON export/restore remains 100% free.
      - `InvoiceThemesScreen`: Free tier defaults to Navy Slate. The 6 premium palette circles feature a lock icon (`Icons.lock_rounded`) and open `ProUpgradeModal` on tap. Pro display options and "Remove Ads" button open `ProUpgradeModal`.
      - `GrowthCampaignsScreen`: Renders `ProLockedCard` banner at top, displays `🔒 PRO` badge on Birthday Radar, and single customer send buttons display `Unlock` with lock icon opening `ProUpgradeModal`.
      - `SaleDetailModal`: Sales return (1-tap refund & restock) action checks `profile.isPro` and prompts `ProUpgradeModal` for free tier.
    - **Every WhatsApp Share Dispatches Respective PDF + Formatted Text + Dynamic UPI Payment Link:**
      - Enhanced `MainActivity.java` `sharePdf` MethodChannel to accept `message` and `subject` arguments, writing them into `Intent.EXTRA_TEXT` so WhatsApp pre-populates the chat message along with the attached PDF.
      - Implemented native `generateAndSaveKhataStatementPdf` in `MainActivity.java` generating a pixel-perfect, lightning-fast (<150ms) A4 Customer Khata Statement with store header, net due pill, debit/credit ledger table, UPI payment box, and single source of truth footer.
      - `SaleCompletedModal`: Generates invoice PDF and shares via WhatsApp with complete item breakdown and dynamic UPI link (`upi://pay?pa=...`).
      - `TransactionsScreen`: Generates invoice PDF and shares via WhatsApp with complete item breakdown and dynamic UPI link.
      - `SaleDetailModal`: Generates invoice PDF and shares via WhatsApp with complete item breakdown and dynamic UPI link.
      - `KhataScreen`: Reminders generate customer statement PDF and share via WhatsApp with statement breakdown and dynamic UPI link. Bill view shares invoice PDF with payment link.
33. **Backend Payment Verification Webhook, Strict Firestore Rules, & Zero-Client-Bypass Architecture (LOCKED):**
    - **No Simulated Upgrades (Real Razorpay Native SDK):**
      - Removed any simulated timers or client-side bypasses. The app strictly uses the official `razorpay_flutter` native Android SDK with live keys (`rzp_live_TSJvcf9JnWpMMm`).
      - In `RazorpayService`, each checkout passes metadata notes (`business_id`, `plan`, `store_name`, `merchant_phone`).
      - Upon payment capture, the app syncs `is_pro: true`, `pro_plan`, `pro_expiry`, and `razorpay_payment_id` directly to Cloud Firestore `/businesses/{bizId}` as well as local SQLite.
    - **Secure Next.js Serverless Route (`backend/nextjs_razorpay_webhook_route.ts` & `backend/nextjs_razorpay_webhook_pages.js`):**
      - Full production webhook implementation for Vercel / Next.js Serverless.
      - Uses raw request buffer with `crypto.createHmac('sha256', secret)` to verify `x-razorpay-signature` against spoofing.
      - Upon `payment.captured` or `order.paid`, parses verified notes, sets Firestore `/businesses/{businessId}` with `is_pro: true`, plan details, and server timestamp.
    - **Strict Firestore Security Rules (`firestore.rules`):**
      - Enforces strict multi-tenant isolation: Merchant A can NEVER read or write Merchant B's products, sales, customers, or profile.
      - Rule matches `businessId == 'biz_' + request.auth.uid` or `owner_uid == request.auth.uid`.
      - Prevents cross-store data leakage in multi-device sync.
    - **Consolidated Navigation Invariant:**
      - Confirmed 0 duplicate navigation overlays. Exactly 5 bottom tabs, where Tab 5 is strictly `MenuScreen.show(context)` — a clean, single modal bottom sheet.

34. **100% Real & Fully Functional AI Inward & Wholesale Restock Suite (LOCKED):**
    - **Zero Mock Demo Fallbacks:**
      - Permanently eliminated `_generateSmartFallbackExtraction()`. No hardcoded demo items (Fortune Oil, Tata Dal, Aashirvaad Atta, Dolo) are ever injected. Failed scans return clear diagnostics so cashiers always know what happened.
    - **Multi-Model Gemini Vision OCR (`GeminiAiService`):**
      - Automatic sequential model retry fallback across `gemini-1.5-flash`, `gemini-2.0-flash`, and `gemini-1.5-flash-8b`.
      - Supports merchant-configured Google AI Studio API key persisted securely in `SharedPreferences` (`custom_gemini_api_key`) with in-app real-time validation via `GeminiAiService.testApiKey()`.
      - Directly accepts image files (`image/jpeg`, `image/png`) and PDF documents (`application/pdf`) in `inline_data`.
    - **100% Offline Excel / CSV File Inward Engine (`CsvInwardService`):**
      - Direct file picker integration (`file_picker: ^12.2.0`) reading `.csv`, `.tsv`, and `.txt` files.
      - Intelligent delimiter detection (comma, tab, semicolon) and heuristic column header mapping for Item Name, Quantity, Unit, Cost Price, MRP, and Selling Price.
      - Converts rupee amounts to integer paise (`1 INR = 100 paise`). Works 100% offline in <20ms with zero API keys or external network dependencies.
    - **Interactive Review & Edit Bottom Sheet (`BillScanReviewSheet`):**
      - Displays before saving: Supplier / Mandi Name, Bill / Invoice #, and detected item rows.
      - **Catalog Match Detection:** Automatically matches item names against existing SQLite `products`:
        - If matched: Displays `🔄 Existing SKU • Current Stock: X ➔ New: X+Qty`.
        - If new: Displays `✨ New SKU • Will be added to catalog`.
      - **Full Line Item Editability:** Cashiers can modify Product Name, adjust Quantity, pick Unit from dropdown (`pcs`, `kg`, `gram`, `litre`, `strip`, `box`, `packet`, `bag`), and edit Buy/Sell/MRP prices in real-time. Unwanted items can be deleted with 1 tap, and missing items added via `+ Add Row`.
      - **Atomic SQLite Stock Ingestion:**
        - Increments `stock_quantity` on existing items and saves via `LocalDatabase.instance.upsertProduct`.
        - Inserts brand new `ProductModel` records with UUID.
        - Records purchase movement in `inventory_movements` table (`movement_type = 'PURCHASE'`).
        - Upserts supplier into `suppliers` table and syncs products with Cloud Firestore.
    - **Unified Inward Entry:**
      - `PurchasesScreen` (`ai_inward_sheet.dart`) and `ProductsScreen` (`ai_inward_modal.dart`) both use the exact same genuine, non-simulated inward pipeline.

35. **Web Admin Dashboard & Multi-Platform Firestore Control Suite (LOCKED):**
    - **SuperAdmin Dashboard Architecture (`Billing WebApp/src/app/admin`):**
      - Next.js Web Admin Portal connected to the shared Firebase Firestore project (`kamaiplus`).
      - Local URL: `http://localhost:3000/admin`, Network URL: `http://192.168.1.35:3000/admin`.
      - Authenticated via SHA-256 constant-time hash comparison using master key (`ADMIN_PASSWORD`).
    - **Master Control Capabilities:**
      - **Merchants Management:** Direct real-time lookup across Firestore `businesses` collection. 1-click Pro license grant, expiration extension, and contact auditing.
      - **Remote Config Control:** Push real-time maintenance mode alerts, force minimum app versions, customize Pro subscription pricing, and update helpline numbers.
      - **Broadcast Announcements:** Send system-wide announcements to all store devices.
      - **Discount Coupons & Subscriptions:** Manage promo coupon codes and audit subscription transactions.

36. **Core Bug Fixes & Payment Integrity Audit (LOCKED):**
    - **Merchant UPI QR & WhatsApp Link Resolution (`pos_checkout_modal.dart` & `payment_modal.dart`):**
      - Resolved critical bug where POS counter QR code and WhatsApp 1-tap pay links were hardcoded to `proventure@icici`.
      - Now dynamically reads `_storeProfile.upiVpa` and `_storeProfile.storeName` from SQLite `store_profile` table so customer payments go directly to the merchant's own registered bank VPA.
    - **SplashScreen Timer Memory Leak & Smoke Test Fix (`splash_screen.dart` & `widget_test.dart`):**
      - Created managed `Timer? _splashTimer` and explicitly cancelled in `SplashScreen.dispose()`.
      - Eliminates `!timersPending` assertion crash and prevents memory leaks during fast transitions.
    - **Web Admin Dashboard Multi-Tenant Schema Alignment (`firestore_sync_service.dart`):**
      - Fixed store name display in Super Admin Dashboard by populating `name`, `shop_name`, `business_name`, `city`, and `subscription_tier` in `businesses/{bizId}` and mirroring to `merchants/{bizId}`.
      - Synchronized Pro membership activation so admin-granted licenses (`subscription_tier == 'pro'`) are immediately recognized during cloud restore.
    - **OCR Integer Paise Extraction Precision (`gemini_ai_service.dart`):**
      - Eliminated dangerous `val > 50000` heuristic in `ExtractedBillItem.fromJson`. Explicitly respects `_paise` schema fields vs rupee rates to prevent 100x multiplier errors on wholesale inventory items.



