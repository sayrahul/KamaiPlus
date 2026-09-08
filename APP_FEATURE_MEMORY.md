# 🧠 KAMAI+ (KAMAIPLUS) — PERMANENT APP FEATURE & DECISIONS MEMORY
> **CRITICAL DIRECTIVE FOR ALL AI AGENTS & DEVELOPERS:**
> Yeh file KamaiPlus app ke sabhi solved features, UI decisions, aur user preferences ka **Single Source of Truth (SSOT)** hai. 
> Koi bhi naya feature ya screen banane se pehle is file ko check karna **COMPULSORY** hai. 
> Yaha likhe kisi bhi solved feature ya user preference ko dubara todna ya revert karna **STRICTLY FORBIDDEN** hai.
>
> 🔒 **PERMANENT GOLD BASELINE LOCKED:** Version 4.17.0 (Commit `e7d4079` / Tag `v4.17.0-locked-gold`).
> Is version ke sabhi features device par verified hain. Kisi bhi halat me is version ka koi bhi UI element, navigation structure, ya feature revert nahi kiya jayega.

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

