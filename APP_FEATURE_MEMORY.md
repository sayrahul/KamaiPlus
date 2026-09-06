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
