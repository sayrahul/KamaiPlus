# 🏛️ KAMAI+ (KAMAIPLUS) NATIVE ANDROID MASTER HANDOVER & SPECIFICATION

> **Application Name:** KamaiPlus POS (Kamai+)  
> **Package ID / Application ID:** `com.kamaiplus.pos`  
> **Repository:** `https://github.com/sayrahul/KamaiPlus`  
> **Local Workspace Directory:** `D:\My Web Sites\KamaiPlus Android`  
> **Technology:** Flutter 3.x / Dart / SQLite (`sqflite`) / Cloud Firestore  
> **Date:** September 06, 2026  

---

## 📌 1. ARCHITECTURAL ISOLATION: TWO DEDICATED REPOSITORIES

KamaiPlus is strictly split into two specialized repositories to keep dependencies, build systems, and version control clean and high-performance:

| System | Workspace Directory | Git Repository | Primary Tech Stack | Target Platform |
| :--- | :--- | :--- | :--- | :--- |
| **Web App & PWA** | `D:\My Web Sites\Billing WebApp` | `sayrahul/kamai` | Next.js 16, React 18, Dexie.js, TailwindCSS | Desktop Counter WebApp, PWA, SuperAdmin Portal |
| **Native Android App** | `D:\My Web Sites\KamaiPlus Android` | `sayrahul/KamaiPlus` | Flutter, Dart, SQFlite, Android SDK | 100% Native Android APK / Google Play AAB |

### Why Separate Folders & Repositories?
1. **Performance & Speed:** Next.js contains heavy `node_modules` (~600MB) and TypeScript builds. Flutter contains Gradle, Android SDK, and Dart build caches. Separating them prevents IDE freezes, slow indexing, and massive multi-gigabyte git clones.
2. **Dedicated Tooling:** Opening `D:\My Web Sites\KamaiPlus Android` directly in Antigravity IDE provides an ultra-fast Flutter/Dart development environment where `flutter run`, `flutter analyze`, and hot reload work seamlessly without interference from Node.js scripts.
3. **Independent Release Lifecycles:** Web updates deploy to web hosting instantly, while Android App updates produce Google Play signed App Bundles (`.aab`).

---

## 👤 2. USER WORKING & COMMUNICATION STYLE GUIDE

* **Language:** The user communicates in natural **Hinglish / Hindi**.
* **Preferred Flow:** **"Step-by-step, screen-by-screen"** (Ek ek screen perfect karo, jaldbaazi me sab kuch ek sath mat karo).
* **Design Philosophy:**
  * **Standard, Professional, Clean, Interactive Retail UI.**
  * **Zero Gimmicks:** Avoid heavy animations, slow page transitions, or childish designs.
  * **Retail Usability:** Big touch targets for cashier fingers, high contrast, instant haptic feedback.
  * **Visual Ground Truth:** 38 reference screenshots are stored in `Refrence PWA Attached/`. Match or exceed this reference design.
* **Golden Rules for AI Agents:**
  1. Never perform unsolicited rewrites or remove existing working features.
  2. Always test and verify with `flutter analyze` (0 errors required).
  3. Inform the user clearly once a screen is finished before proceeding to the next screen.

---

## 💰 3. SACRED INVARIANTS

1. **Integer Paise Math (Zero Floating Point):**
   - Money is strictly stored and calculated as integer paise (`₹1.00 = 100 paise`).
   - Use `MoneyFormatter.formatINR(paise)` for UI display.
2. **Offline-First SQLite Engine:**
   - Single source of truth is local SQLite (`LocalDatabase.instance` in `lib/core/database/local_database.dart`).
   - All cashier actions (cart additions, bill generation) execute in <10ms locally.
3. **Google Play Release Signing:**
   - Keystore: `android/app/kamai-release-key.jks`
   - Key Alias: `kamaiplus`
   - Password: `kamaiplus2026`
   - Application ID: `com.kamaiplus.pos`

---

## 📊 4. COMPLETE AUDIT: WHAT HAS BEEN IMPLEMENTED

### A. WebApp Reference Features (`sayrahul/kamai`):
* 24 App Router pages, 31 API routes, ~90 modular components.
* Dexie.js local IndexedDB with 10 tables.
* WhatsApp reverse-handshake authentication (`KP-XXXXX` click-to-chat).
* Indian GST tax calculation engine (tax-inclusive and tax-exclusive).
* ESC/POS direct thermal printing and Cash Drawer kick pulse.
* USB Barcode hardware interceptor (<30ms character bursts).
* Multilingual voice soundbox engine (Hindi & English payment speaker).

### B. Native Android App Features (`sayrahul/KamaiPlus`):
1. **SQLite Database (`local_database.dart`):** Complete relational schema for businesses, products, categories, customers, sales, sale items, and ledger transactions.
2. **Bottom Navigation Architecture:** 5 locked tabs:
   - Tab 1: **Home**
   - Tab 2: **Product**
   - Tab 3: **Billing**
   - Tab 4: **Khata**
   - Tab 5: **Menu**
3. **Screen 1: Home Dashboard (`home_pulse_tab.dart`):**
   - Store header with store name, Pro badge, QR Standee icon, and Owner Privacy eye icon.
   - `ProUpgradeModal`: Pro subscription dialog.
   - `UpiStandeeModal`: Merchant UPI QR Standee popup.
   - `OwnerPrivacyModal`: Eye toggle to hide Today's Profit from cashier eyes.
   - Fixed invoice collision issue (`#001` vs `INV-001`).
   - Quick Action Dock (Billing, Scan, Inward, Khata, Cash Register).
   - Today's Sales Pulse and Recent Invoices list.
4. **Screen 2: Products Screen (`products_screen.dart`):**
   - Live product catalog with category chips, instant search, and stock quantity indicators.
   - `AddProductModal`: Multi-tab product creation (Selling Price, Cost Price, GST, Barcode, Units, Expiry, Batch).
   - `AiInwardModal`: 4-way purchase inward (Camera OCR scan, PDF bill inward, Quick Add, Gallery).
   - `BarcodeScannerModal`: Camera scanner integration.
   - Eye toggle for Stock Asset valuation visibility.
5. **Screen 3: POS Billing Screen & Cart Flow (`pos_billing_screen.dart`):**
   - POS item cards with 1-tap add to cart and haptic feedback.
   - Camera barcode scanner button and category filter chips.
   - Floating bottom cart bar (item count + bill amount + "View Cart & Pay").
   - `PosCheckoutModal`: Slide-up View Cart drawer with quantity `+`/`-`, item removal, and customer search/attachment.
   - `PosItemEditModal`: Pencil button dialog for custom selling price, item discount (%/₹), custom units (packet, kg, pc), and tax.
   - **Extended Cash & Payment Options:** Quick Cash Tender chips (`₹100`, `₹200`, `₹500`, `₹2000`, `Exact`), live change calculation, payment modes (Cash, UPI QR, Udhar/Khata, Split), and bill discount (Flat / %).
6. **Screen 4: Menu Hub (`menu_screen.dart`):**
   - Organized grid for all store management tools: Inventory, Purchases, Customers, Transactions, Cash Register, GST Reports, Cloud Backup, Settings, Support & Logout.

---

## 📋 5. REMAINING WORK & ROADMAP

1. **Khata / Digital Ledger Screen (`khata_screen.dart`):**
   - Modernize customer list cards matching PWA reference.
   - Balance display in Red (Udhar) and Green (Jama).
   - 1-tap WhatsApp payment reminder with deep link.
   - Quick Add Customer modal.
   - Customer Ledger detail view with "Maine Diye" (Given) and "Maine Liye" (Received) transactions.
2. **Transactions History Screen (`transactions_screen.dart`):**
   - Bill cards list with invoice pills, date/payment filters, thermal receipt preview, and cancel/refund actions.
3. **Cash Register Screen (`cash_register_screen.dart`):**
   - Day-open / day-close cash drawer balances.
   - Currency denomination calculator chips (₹500x, ₹200x, ₹100x...).
   - Daily cash expense tracking.
4. **Inventory & Expiry Radar (`inventory_screen.dart`):**
   - Low stock warning list and expiry radar.
   - Stock manual adjustments.
5. **Settings & Hardware Bridges:**
   - Store Profile & GSTIN details.
   - Bluetooth Thermal Printer pairing modal (`bluetooth_printer_dialog.dart`).
   - Voice soundbox speaker triggers.
6. **Phase 3 (Backend & Cloud Sync):**
   - Bidirectional real-time Cloud Firestore sync engine.
   - WhatsApp / Phone OTP reverse-handshake auth.
   - Google Play signed release bundle (`.aab`) generation.

---

## 🚀 6. GIT SETUP & LINKING INSTRUCTIONS

To connect `D:\My Web Sites\KamaiPlus Android` cleanly to `https://github.com/sayrahul/KamaiPlus`:

```bash
cd "D:\My Web Sites\KamaiPlus Android"
git init
git remote add origin https://github.com/sayrahul/KamaiPlus.git
git branch -M main
git add .
git commit -m "feat: initial commit for KamaiPlus Native Android App (Flutter)"
git push -u origin main --force
```

*(Note: `--force` replaces any old/obsolete files on the remote repo with the clean, fresh Flutter project).*
