# KamaiPlus (Kamai+) — Complete App Documentation
### Fresh git clone se banaya gaya, poora codebase audit (05 Sept 2026)

> **Note**: Ye document `github.com/sayrahul/kamai` ke fresh clone se generate kiya gaya hai, isliye ye actual code ke saath 100% match karta hai (koi purani AI summary pe bharosa nahi kiya).
>
> **Total codebase size**: ~55,300 lines of TypeScript/TSX code, **24 pages**, **31 API routes**, **~90 components**, **~50 lib/utility files**.

---

## 1. TECH STACK — Kya kya use hua hai

| Layer | Technology | Version |
|---|---|---|
| Framework | Next.js (App Router) | 16.3.1 |
| UI Library | React | 18.3.1 |
| Language | TypeScript | 5.7.3 |
| Styling | Tailwind CSS | 3.4.17 |
| Local DB (offline-first) | Dexie.js (IndexedDB wrapper) | 4.0.11 |
| Cloud Auth/Subscription DB | Supabase (Mumbai region) | JS SDK 2.112.3 |
| Cloud Sync (contested) | Firebase / Firestore | 12.18.0 |
| Payments | Razorpay | 2.9.8 |
| AI OCR | Google Gemini API | (via REST, no SDK) |
| Messaging | WhatsApp Cloud API (Meta) | REST v20 |
| Native App Wrapper | Capacitor (Android) | 8.5.0 |
| PDF generation | jsPDF + html2canvas | 4.2.1 / 1.4.1 |
| Excel import/export | xlsx (SheetJS) | 0.18.5 |
| Barcode scanning | html5-qrcode | 2.3.8 |
| QR generation | qrcode | 1.5.4 |
| Auth tokens | jsonwebtoken | 9.0.3 |
| Password hashing | bcryptjs | 3.0.3 |
| Schema validation | zod | 3.24.2 |
| Dates | date-fns | 4.1.0 |
| Icons | lucide-react | 0.475.0 |
| Confetti animation | canvas-confetti | 1.9.4 |

**Package manager scripts** (`package.json`):
- `dev` → Next dev server (Turbopack)
- `build` / `start` → production build/run
- `test:e2e` → `scripts/e2e_simulation.ts` custom E2E script
- `version:bump` → auto version bump script
- `cap:sync` / `cap:open` / `cap:build` → Capacitor Android build commands

---

## 2. THIRD-PARTY APIs & SERVICES (`.env.example` se confirm kiya)

| Service | Purpose | Env Vars |
|---|---|---|
| **JWT (custom)** | Merchant staff session tokens | `JWT_SECRET` |
| **JWT (custom)** | SuperAdmin session tokens | `ADMIN_JWT_SECRET`, `ADMIN_PASSWORD` |
| **Razorpay** | Subscription payments (Pro plan) | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` |
| **Google Gemini AI** | Purchase bill scan OCR (optional feature) | `GEMINI_API_KEY` |
| **Meta WhatsApp Cloud API** | OTP login, invoice bhejna, khata reminders, daily summary, marketing campaigns | `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET` |
| **Firebase** | Cloud sync, analytics, push notifications, remote config, storage (⚠️ architecturally contested — neeche dekhein) | `NEXT_PUBLIC_FIREBASE_*` (7 keys) |
| **Supabase** | Auth + subscription DB only (Mumbai region, project `dgolzwqlalbelvsxqzci`) | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` |

**⚠️ Important**: Browser kabhi Supabase ko directly call nahi karta — sab reads/writes Next.js API routes ke through jaate hain jo `service_role` key server-side use karte hain (RLS policies nahi hain).

---

## 3. APP WIRING — Sab kuch kaise connect hota hai

### 3.1 Root Layout Chain
```
app/layout.tsx (RootLayout)
   └─ I18nProvider (Hindi/English language context)
        └─ AppShell (components/layout/AppShell.tsx) ← YE MAIN WIRING FILE HAI
             ├─ Navbar (desktop top bar)
             ├─ Sidebar (desktop side nav)
             ├─ BottomNav (mobile bottom bar: Home, Billing, Khata, Products)
             ├─ GlobalBroadcastBanner (admin se bheja gaya announcement)
             ├─ DailyDigestAutoWatcher (auto daily WhatsApp summary trigger)
             └─ {children} → actual page content
        └─ PWAInstallBanner (install-to-homescreen prompt)
```

### 3.2 AppShell.tsx — App start hote hi kya-kya chalta hai
Jab app load hota hai, `AppShell` ke `useEffect` hooks ye sequence chalate hain:
1. `getStoredUser()` — localStorage se logged-in user check
2. `ensureStarterBusinessIfEmpty()` — agar Dexie DB khaali hai to demo "My Retail Store" business seed karta hai (⚠️ auth-check se PEHLE chalta hai — pending fix)
3. `initFirebaseAppCheck()` — Firebase App Check init
4. `initBackgroundCloudSync(business_id)` — **Firebase background sync start karta hai** (⚠️ ye locked "Dexie-only" architecture ko contradict karta hai)
5. `useFirebasePageTracking()` — page-view analytics
6. `subscriptionService` — Pro/Free entitlement check

### 3.3 Navigation Map (kaunsa button kaha le jaata hai)
**Bottom Nav (mobile, hamesha visible):** Home (`/`) → Billing (`/billing`) → Khata (`/khata`) → Products (`/products`)

**Mobile Menu Modal / Quick Tools Grid (home page se):**
`/barcode-generator`, `/billing`, `/cash-register`, `/cloud-backup`, `/customers`, `/growth`, `/gst-reports`, `/inventory`, `/invoice-designer`, `/khata`, `/pricing`, `/products`, `/purchases`, `/settings`, `/transactions`

**Standalone/system pages** (nav me nahi, direct link se): `/auth`, `/onboarding`, `/invoice/[id]` (shared invoice view), `/pay` (UPI payment redirect page), `/admin` (SuperAdmin, separate password-protected), `/pricing`, `/privacy-policy`, `/terms-of-service`, `/refund-policy`, `/contact-us`

---

## 4. HAR PAGE KA POORA DETAIL (24 pages)

### 4.1 `/` — Home Page (`app/page.tsx`, 268 lines)
- **Kaam**: Dashboard — aaj ka business pulse dikhata hai
- **Components use hote hain**: `TodayBusinessPulse`, `QuickActionDock`, `QuickToolsGrid`, `DashboardRecentSales`, `DashboardStockWatchlist`, `NicheRadarBanner`
- **DB access**: `db.businesses`, `db.customers`, `db.products`, `db.sales`
- **Functions**: `handleQuickRestock()` — low-stock item ko dashboard se hi restock karna; `handleQuickRestock` inventory movement + product stock update dono karta hai
- **API call**: `/api/auth/me` (session verify karne ke liye)

### 4.2 `/auth` — Login/Signup (`app/auth/page.tsx`, 59 lines — thin wrapper)
- **Kaam**: WhatsApp OTP-based login/signup ka entry point
- Actual logic `components/auth/AuthForm.tsx` (1025 lines!) aur `PhoneAuthForm.tsx` me hai
- **APIs called** (AuthForm ke through): `/api/auth/send-whatsapp-otp`, `/api/auth/verify-whatsapp-otp`, `/api/auth/signup`, `/api/auth/login`
- **Wiring**: Success par `/onboarding` ya `/` (home) pe redirect

### 4.3 `/onboarding` — New user setup (`app/onboarding/page.tsx`, 480 lines)
- **Kaam**: Naya business register karna — store name, category, GST, address
- **Function**: `handleSubmit()` — business record Dexie me create karta hai + welcome flow trigger
- **API**: `/api/auth/onboarding-welcome` (welcome WhatsApp message bhejta hai)
- **Component**: `OnboardingPhotoScanCard` (store photo se auto-setup try karta hai)

### 4.4 `/billing` — POS Billing (`app/billing/page.tsx`, **3,084 lines — sabse bada page**)
- **Kaam**: Main POS/checkout screen — cart, product search, payment collection
- **Multi-tab system**: Ek time par multiple customers ka bill parallel chal sakta hai (hold/resume)
- **Key functions**:
  - `getInitialTabs()` — saved cart tabs restore karta hai
  - `handleCreateNewTab()` / `handleCloseTab()` / `handleHoldActiveTab()` — tab management
  - `handleBarcodeScanned()` — barcode scan hote hi product cart me add
  - `handleCompleteSale()` — final checkout: stock deduct, sale record, invoice number generate, khata update (agar udhar)
  - `handleSaveQuickAddItem()` / `handleOpenEditItem()` / `handleSaveEditItem()` — cart item edit inline
  - `handleSaveQuickCustomer()` — naya customer bina page chhode add
  - `handleRestockAndAddToCart()` — agar stock kam hai to turant restock + cart add
  - `extractTabletsPerStrip()`, `getQuantityConfigForUnit()` — pharmacy-style unit conversion (strip/tablet)
- **DB access**: `businesses`, `categories`, `customers`, `products`, `sales`
- **Validation**: Out-of-stock enforcement cart-aware hai (already fixed), percentage discount validation
- **Linked components**: `InvoiceModal`, `SalesReturnModal`, `VoiceBillingModal`, `BarcodeScannerModal`, `HardwareManagerModal`

### 4.5 `/cash-register` — Cash Drawer (`app/cash-register/page.tsx`, 251 lines)
- **Kaam**: Din ki shuruaat/end me cash register open/close, expenses track
- **Functions**: `handleOpenShift()`, `handleConfirmCloseShift()`, `handleSaveExpense()`, `handleDeleteExpense()`
- **DB**: `businesses`, `sales`
- **Components**: `AddExpenseModal`, `DenominationCalculatorModal` (notes/coins counting), `CashExpensesList`, `CashRegisterMetricsRibbon`
- **Report**: `DayEndClosingReportModal` (PDF close report — `lib/reports/dailyClosingPdf.ts` use karta hai)

### 4.6 `/khata` — Digital Credit Ledger (`app/khata/page.tsx`, 1,194 lines)
- **Kaam**: Udhar/Khata management — kisne kitna udhaar liya, kab dena hai
- **Functions**:
  - `handleCreateCustomer()`, `handleClearCustomerKhata()` — poora balance settle karna
  - `handleOpenEntryModal()`/`handleSaveEntry()` — manual credit/debit entry
  - `handleSaveEditTx()`/`handleDeleteTx()` — transaction edit/delete
  - `handleSendWhatsAppReminder()` — udhar reminder WhatsApp pe bhejna
  - `handleOpenSaleInvoice()` — related sale ka invoice khol na
- **API**: `/api/whatsapp/send-khata-reminder`
- **DB**: `businesses`, `customers`, `sales` (+ `ledger_transactions` table)
- **Components**: `ManualEntryModal`, `EditLedgerEntryModal`, `SettleInvoicesModal`, `ConsolidatedStatementModal` (658 lines — poora statement PDF), `CustomerLedgerTimelineTab`, `CustomerPendingInvoicesTab`, `QuickAddKhataCustomerModal`
- **Note**: Mobile UI redesign prompt already ready hai isi page ke liye (agenda me)

### 4.7 `/products` — Product Catalog (`app/products/page.tsx`, 529 lines)
- **Kaam**: Products add/edit/delete, categories, stock quick-adjust
- **Functions**: `handleSaveProduct()`, `handleDeleteProduct()`, `handleCreateCategory()`, `handleQuickStockChange()`, `handleToggleFavorite()`, `handleBarcodeScanned()` (naya product barcode se auto-fill)
- **DB**: `businesses`, `categories`, `products`
- **Components**: `AddEditProductModal`, `ProductCard`, `ProductFilterToolbar`, `ProductMetricsRibbon`
- **Barcode wiring**: `lib/barcode/offlineBarcodeLookup.ts` + `categoryBarcodeLoader.ts` + `offlineFMCGDatabase.ts` (offline hi barcode se product match karta hai, phir `publicBarcodeLookup.ts` se online fallback)

### 4.8 `/inventory` — Stock Management (`app/inventory/page.tsx`, 184 lines)
- **Kaam**: Low-stock alerts, reorder, supplier orders, expiry tracking
- **Functions**: `handleQuickRestock()`, `handleSendSupplierOrder()`
- **DB**: `businesses`, `products`, `suppliers`
- **Components**: `ExpiryRadar`, `ReorderAlertsList`, `StockMovementsList`, `ExcelInventoryImporter` (bulk import via Excel), `InventoryMetricsRibbon`

### 4.9 `/purchases` — Purchase/Bill Inward (`app/purchases/page.tsx`, 327 lines)
- **Kaam**: Supplier se maal aane par purchase record karna, AI se bill scan
- **Function**: `handleRecordPurchase()`
- **API**: `/api/purchases/scan-bill` (Gemini AI se bill photo se items extract)
- **Components**: `ScanBillButton`, `BillScanReviewModal` (extracted items review karke confirm), `PurchaseInwardOptionsSheet`
- **Lib**: `lib/ai/geminiClient.ts` (`extractPurchaseBillWithGemini`), `lib/purchases/matchProductByName.ts` (extracted item ko existing product se match karta hai)

### 4.10 `/customers` — Customer Management (`app/customers/page.tsx`, 257 lines)
- **Functions**: `handleSaveCustomer()`, `handleDeleteCustomer()`, `handleSendCustomerGreeting()`
- **API**: `/api/whatsapp/send-campaign`
- **DB**: `businesses`, `customers`
- **Components**: `AddEditCustomerModal`, `CustomerCard`, `CustomerSearchAutocomplete`, `CustomerFilterToolbar`

### 4.11 `/growth` — Marketing/WhatsApp Campaigns (`app/growth/page.tsx`, 929 lines)
- **Kaam**: WhatsApp marketing templates select karke customers ko bulk bhejna
- **Functions**: `handleSelectCampaign()`, `handleSendToCustomer()`, `handleCopyMessage()`
- **API**: `/api/whatsapp/send-campaign`
- **DB**: `businesses`, `customers`

### 4.12 `/gst-reports` — GST Compliance (`app/gst-reports/page.tsx`, 298 lines)
- **Kaam**: GSTR-1 report generation, tax summaries
- **Functions**: `handleExportCSV()`, `handleExportJSON()`, `handleExportTallyXML()`
- **Lib**: `lib/gst/gstr1Generator.ts` (`generateGSTR1Report`, `generateGSTR1CSV`, `generateGSTOfflineJSON`)
- **DB**: `businesses`, `customers`, `sales`
- **Components**: `GstHsnSummaryTable`, `GstMetricsRibbon`, `GstNavTabs`

### 4.13 `/transactions` — Sales History (`app/transactions/page.tsx`, 376 lines)
- **Functions**: `handleClearAllHistory()`, `handleConvertToInvoice()`, `handleExportCSV()`, `handleExportTallyXML()`, `handleOpenInvoice()`, `handleSendWhatsApp()`
- **DB**: `businesses`, `customers`, `products`, `sales`
- **Components**: `TransactionBillCard`, `TransactionFilterToolbar`, `useTransactionFilters` (custom hook), `ClearHistoryModal`

### 4.14 `/invoice` (shared, `?id=` param) (`app/invoice/page.tsx`, 480 lines)
- **Kaam**: Public/shareable invoice view (WhatsApp link click karne par ye khulta hai)
- **Functions**: `handlePrint()`, `handleDownloadPdf()`, `handleShare()`
- **DB**: `businesses`, `sales`
- **Lib**: `lib/invoices/pdfGenerator.ts`, `whatsappInvoice.ts` (`decodeInvoicePayload` — URL me encode kiya hua invoice data decode karta hai)

### 4.15 `/invoice-designer` — Invoice Template Customization (`app/invoice-designer/page.tsx`, 781 lines)
- **Functions**: `handleSelectPreset()`, `handleSave()`, `handleDownloadSamplePdf()`
- **Lib**: `lib/invoices/themeDefaults.ts` (presets), `pdfGenerator.ts`
- **DB**: `businesses` (theme config store hoti hai)

### 4.16 `/barcode-generator` — Print Barcodes (`app/barcode-generator/page.tsx`, 906 lines)
- **Functions**: `handleAddProductToQueue()`, `handleAddCustomItem()`, `handleUpdateCopies()`, `handleBluetoothPrint()`, `handleBrowserPrint()`, `handleSaveSettings()`
- **DB**: `businesses`, `products`
- **Lib**: `lib/barcode/barcodeGenerator.ts` (Code128 SVG generate), `lib/hardware/bluetoothPrinter.ts` + `escpos.ts` (thermal printer ESC/POS commands)

### 4.17 `/settings` — Store Settings (`app/settings/page.tsx`, 617 lines)
- **Kaam**: Store profile, UPI accounts, invoice settings, WhatsApp config — sab yaha
- **Functions**: `handleSaveAll()`, `handleDiscardAll()`, `handleLogoUpload()`, `handleAddUpi()`/`handleRemoveUpi()`/`handleSetDefaultUpi()`, `handleSendTestWhatsApp()`, `handleTabChangeAttempt()` (unsaved-changes warning)
- **API**: `/api/whatsapp/send-invoice` (test message ke liye)
- **DB**: `businesses`
- **Tabs**: `StoreProfileTab`, `UpiBankingTab`, `InvoiceSettingsTab`, `WhatsAppSettingsTab` (`SettingsNavTabs` se switch hota hai)

### 4.18 `/cloud-backup` — Backup/Restore (`app/cloud-backup/page.tsx`, 546 lines)
- **Functions**: `handleDownloadBackup()`, `handleFileSelect()`, `handleConfirmRestore()`, `handleSyncToFirestore()`, `handleRestoreFromFirestore()`, `handleExportTallyXML()`, `handleExportCAMasterCSV()`
- **DB**: sab tables (`businesses`, `customers`, `products`, `sales`)
- **Lib**: `lib/backup/cloudBackupService.ts` (JSON backup), `lib/firebase/firestoreSync.ts` (⚠️ ye woh contested Firebase sync hai), `lib/tally/tallyXmlGenerator.ts`, `lib/tally/caExcelGenerator.ts`

### 4.19 `/pricing` — Plans (Free/Pro) (`app/pricing/page.tsx`, 418 lines)
- **Function**: `handleSubChange()` (monthly/yearly toggle)
- **API**: `/api/admin/config` (dynamic pricing config admin se aati hai)
- **Component**: `UPIPaymentModal` (Razorpay checkout trigger)

### 4.20 `/pay` — UPI Payment Redirect (`app/pay/page.tsx`, 182 lines)
- **Kaam**: Customer ko UPI QR/link redirect page dikhana (khata settlement ya bill payment ke liye)

### 4.21 `/admin` — SuperAdmin Panel (`app/admin/page.tsx`, 1,053 lines)
- **Kaam**: Rahul (owner) ka god-mode dashboard — sab merchants dekhna, Pro grant karna, coupons, broadcast bhejna
- **Password-protected** (`ADMIN_PASSWORD` env var se, separate JWT `ADMIN_JWT_SECRET`)
- **Functions**: `handleLogin()`/`handleLogout()`, `handleAddMerchant()`/`handleUpdateMerchant()`/`handleDeleteMerchant()`, `handleTogglePro()`/`handleGrantProLicense()`, `handleToggleActive()`, `handleCreateCoupon()`/`handleDeleteCoupon()`, `handleSaveBroadcast()`, `handleSaveConfig()`, `handleSendTestOutreach()`, `handleResetLocalData()`
- **APIs**: `/api/admin/login`, `/logout`, `/session`, `/merchants`, `/merchants/[id]`, `/metrics`, `/config`, `/coupons`, `/broadcast`, `/whatsapp/outreach`
- **Tabs**: `AdminOverviewTab`, `AdminMerchantsTab` (719 lines), `AdminRevenueTab`, `AdminCouponsTab`, `AdminBroadcastTab`, `AdminConfigTab`, `AdminWhatsAppTab`

### 4.22–24. Legal/Static Pages
- `/privacy-policy` (156 lines), `/terms-of-service` (141 lines), `/refund-policy` (127 lines), `/contact-us` (101 lines) — pure static content, koi DB/API wiring nahi

---

## 5. API ROUTES — Sab 31 Backend Endpoints

### Auth (`/api/auth/*`)
| Route | Method | Kaam |
|---|---|---|
| `send-whatsapp-otp` | POST | WhatsApp pe OTP bhejta hai (rate-limited) |
| `verify-whatsapp-otp` | POST | OTP verify karke session JWT issue karta hai (328 lines — sabse complex auth route) |
| `signup` | POST | Naya merchant account banata hai |
| `login` | POST | Existing merchant login |
| `logout` | POST | Session cookie clear |
| `me` | GET | Current session verify + user info return |
| `onboarding-welcome` | POST | Welcome WhatsApp message bhejta hai naye user ko |
| `reverse-handshake/create` | POST | QR/link-based alternate login flow start |
| `reverse-handshake/status` | GET | Us handshake ka status poll karta hai |

### Admin (`/api/admin/*`)
| Route | Method | Kaam |
|---|---|---|
| `login` / `logout` / `session` | POST/POST/GET | SuperAdmin auth |
| `merchants` | GET/POST | Sab merchants list, naya merchant add |
| `merchants/[id]` | PATCH/DELETE | Ek merchant edit/delete/Pro grant |
| `metrics` | GET | Platform-wide metrics (total merchants, revenue, etc.) |
| `config` | GET/POST | Pricing config read/update (yehi `/pricing` page use karta hai) |
| `coupons` | GET/POST/PUT/DELETE | Discount coupons CRUD |
| `broadcast` | GET/POST | Sab merchants ko banner message bhejna |
| `transactions` | GET | Platform revenue transactions |
| `whatsapp/outreach` | POST | Bulk WhatsApp outreach test |

### Razorpay (`/api/razorpay/*`)
| Route | Method | Kaam | ⚠️ Status |
|---|---|---|---|
| `create-order` | POST | Razorpay order create karta hai (Pro subscription) | **Auth bypass bug open** — session na ho to client-supplied `businessId` fallback ho jaata hai |
| `verify` | POST | Payment signature verify | **Same bug** |
| `webhook` | POST | Razorpay se server-to-server payment confirmation | — |

### WhatsApp (`/api/whatsapp/*`, `/api/webhooks/whatsapp`, `/api/reports/*`)
| Route | Method | Kaam |
|---|---|---|
| `send-invoice` | POST | Invoice PDF/link WhatsApp pe bhejta hai |
| `send-campaign` | POST | Marketing template bulk-send |
| `send-khata-reminder` | POST | Udhar reminder |
| `daily-summary` | POST | Din ka business summary WhatsApp pe |
| `reports/send-daily-whatsapp` | POST | Scheduled daily report trigger |
| `webhooks/whatsapp` | GET/POST | Meta ka webhook (verify + incoming message handle — `ownerBotService.ts` yahi se trigger hota hai) |

### Purchases, Subscription, Health
| Route | Method | Kaam |
|---|---|---|
| `purchases/scan-bill` | POST | Gemini AI se bill photo scan (auth bypass yaha fix ho chuka hai) |
| `subscription/status` | GET | Current plan (Free/Pro) status |
| `subscription/activate` | POST | Manual/coupon-based activation |
| `health` | GET | Uptime/health check endpoint |

---

## 6. COMPONENTS — Module-wise Grouping (~90 components)

| Folder | Components | Kaam |
|---|---|---|
| `admin/` | AdminHeader, AdminNavTabs, AdminMobileBottomNav, 6× Tab components, 6× modals | Admin panel UI pieces |
| `auth/` | AuthForm, PhoneAuthForm, GoogleAuthCard, IntroWalkthrough | Login/signup flow |
| `barcode/` | BarcodeScannerModal | Camera-based barcode scan |
| `cash-register/` | AddExpenseModal, CashExpensesList, DenominationCalculatorModal, etc. | Cash drawer UI |
| `common/` | DailyDigestAutoWatcher, GlobalBroadcastBanner, SyncStatusBadge | Cross-app utilities |
| `customers/` | AddEditCustomerModal, CustomerCard, CustomerSearchAutocomplete, etc. | Customer UI |
| `dashboard/` | TodayBusinessPulse, QuickActionDock, QuickToolsGrid, DashboardRecentSales, DashboardStockWatchlist, NicheRadarBanner | Home page widgets |
| `gst/` | GstHsnSummaryTable, GstMetricsRibbon, GstNavTabs | GST report UI |
| `hardware/` | HardwareManagerModal | Printer/scanner device pairing |
| `inventory/` | ExcelInventoryImporter, ExpiryRadar, ReorderAlertsList, StockMovementsList | Stock UI |
| `invoices/` | InvoiceModal (1,240 lines), EditInvoiceModal | Invoice display/edit |
| `khata/` | ConsolidatedStatementModal (658 lines), ManualEntryModal, SettleInvoicesModal, etc. | Khata UI |
| `layout/` | AppShell, Navbar, Sidebar, BottomNav, MobileMenuCardsModal | **Core app wiring** |
| `onboarding/` | OnboardingPhotoScanCard | AI-assisted setup |
| `payments/` | NativeSoundboxStatusCard, PaymentCelebrationModal | UPI soundbox integration UI |
| `paytm/` | MerchantQRModal | Paytm QR display |
| `pricing/` | UPIPaymentModal | Razorpay checkout modal |
| `privacy/` | CashierPinModal, ProfitMask | Staff PIN + profit-hiding feature |
| `products/` | AddEditProductModal, ProductCard, ProductFilterToolbar, ProductMetricsRibbon | Product UI |
| `purchases/` | BillScanReviewModal, PurchaseInwardOptionsSheet, ScanBillButton | Purchase/OCR UI |
| `pwa/` | PWAInstallBanner, PWAInstallSettingsCard | Install-to-homescreen prompts |
| `reports/` | DayEndClosingReportModal | Cash-closing PDF report |
| `sales/` | SalesReturnModal | Return/refund flow |
| `settings/` | 5× tab components, SettingsChangeDialogue | Settings page tabs |
| `subscription/` | ProFeatureGate, UpgradeModal | Feature-gating for Free vs Pro |
| `transactions/` | TransactionBillCard, useTransactionFilters (hook), 4× more | Transactions UI |
| `ui/` | Badge, Button, Card, Input, Modal, WhatsAppLogo | Reusable design-system primitives |
| `voice/` | VoiceBillingModal | Voice-based billing (Hindi speech parsing) |

---

## 7. LIB FOLDER — Business Logic Functions (domain-wise)

### 7.1 Auth & Session (`lib/auth.ts`, `lib/auth/*`)
- `getStoredUser()` / `setStoredUser()` — localStorage user cache
- `logoutUser()` / `purgeLocalDeviceData()` — logout + local data wipe
- `signSessionToken()` / `verifySessionToken()` (`session.ts`) — merchant JWT (24h expiry)
- `signOtpSessionToken()` / `verifyStatelessOtp()` / `checkOtpCooldown()` (`otpService.ts`) — OTP rate-limit + verification
- `createHandshakeSession()` / `getHandshakeStatus()` (`reverseHandshakeService.ts`) — QR-based login
- `getOwnerCashierPin()` / `verifyOwnerPin()` / `isProfitHidden()` (`cashierPrivacy.ts`) — staff PIN + profit-mask feature (Pro tier, deferred)

### 7.2 Admin Auth (`lib/admin/adminAuth.ts`)
- `signAdminToken()` / `verifyAdminToken()` / `getAdminSessionFromCookies()` / `verifyAdminRequest()` — SuperAdmin JWT (separate secret)

### 7.3 AI/OCR (`lib/ai/*`)
- `extractPurchaseBillWithGemini()` — bill photo → structured JSON (Gemini API call)
- `BILL_SCAN_SYSTEM_PROMPT` — prompt template

### 7.4 Barcode (`lib/barcode/*`)
- `generateCode128SVG()` / `generateCode128DataURL()` — barcode print ke liye
- `performHybridBarcodeScan()` — offline DB pehle check, phir online fallback
- `loadCategoryBarcodeDictionary()` / `lookupCategoryBarcode()` — category-specific FMCG barcode dictionary
- `autoCreateProductFromCategoryItem()` / `autoCreateProductFromMaster()` — barcode match hote hi auto product create

### 7.5 Backup (`lib/backup/cloudBackupService.ts`)
- `createFullBackupPayload()` / `downloadBackupJSON()` — poora DB JSON export
- `restoreDatabaseFromPayload()` — JSON se restore
- `uploadBackupToGoogleDrive()` — (⚠️ pehle ye fake tha, ab remove ho chuka hai per memory)

### 7.6 Database (`lib/db/*`)
- `db` — main Dexie instance (`VyaparSetuDatabase` class — 14 tables)
- `ensureStarterBusinessIfEmpty()` — demo data seed (⚠️ auth se pehle chalta hai, pending fix)
- `seedComprehensiveDemoData()` — full "Sharma Kirana Store" demo dataset

### 7.7 Firebase (`lib/firebase/*` — ⚠️ CONTESTED MODULE)
- `initBackgroundCloudSync()` (`backgroundSync.ts`) — **AppShell me active hai, business data ko Firestore pe live sync karta hai**
- `syncLocalDexieToFirestore()` / `restoreFirestoreToLocalDexie()` (`firestoreSync.ts`)
- `subscribeToLiveSales()` / `subscribeToMultiDeviceSync()` — real-time listeners
- `initFirebaseAnalytics()`, `initFirebaseAppCheck()`, `initFirebaseMessaging()` (push), `fetchPlatformPromoConfig()` (remote config), `uploadStoreLogoToStorage()` etc.
- **⚠️ Firestore rules abhi `allow read, write: if true`** — publicly open, isliye ye poora module "Dexie-only" architecture se conflict karta hai

### 7.8 GST (`lib/gst/gstr1Generator.ts`)
- `generateGSTR1Report()` / `generateGSTR1CSV()` / `generateGSTOfflineJSON()` — GST return format

### 7.9 Hardware (`lib/hardware/*`)
- `useHardwareBarcodeScanner()` — physical USB/BT scanner listener
- `bluetoothPrinter` — thermal printer connection object
- `escpos.ts` — ESC/POS raw print command builder

### 7.10 Invoices (`lib/invoices/*`)
- `calculateGstSummary()` / `numberToWordsINR()` (`gstCalculator.ts`)
- `getNextUniqueInvoiceNumber()` / `commitNextInvoiceNumber()` (`invoiceNumberService.ts`) — race-condition-safe invoice numbering
- `generateInvoicePdfBlobFromElement()` / `shareInvoicePdfDirect()` (`pdfGenerator.ts`)
- `INVOICE_THEME_PRESETS`, `getDefaultThemeForCategory()` (`themeDefaults.ts`)
- `generateWhatsAppInvoiceMessage()` / `sendInvoiceViaOfficialCloudApi()` (`whatsappInvoice.ts`)

### 7.11 Payments (`lib/payments/*`)
- `parsePaymentNotification()` / `extractAmountToPaise()` / `extractUtrNumber()` — UPI notification parsing (soundbox feature)
- `soundboxEngine` / `numberToHindiWords()` — "₹500 rupaye prapt hue" voice announcement

### 7.12 Purchases (`lib/purchases/matchProductByName.ts`)
- `matchExtractedItemsWithProducts()` — AI-scanned bill items ko existing product catalog se fuzzy-match karta hai

### 7.13 Rate Limiting (`lib/rateLimit.ts`, `lib/security/rateLimiter.ts`)
- `checkRateLimit()` / `getClientIp()` — OTP spam/abuse rokne ke liye (duplicate module — cleanup candidate)

### 7.14 Reports (`lib/reports/*`)
- `generateDailyClosingPDF()` — cash register closing report
- `exportTransactionsCSV()` — transactions CSV export

### 7.15 Subscription (`lib/subscription/*`)
- `canAccess()` / `can()` (`entitlementService.ts`) — Free vs Pro feature-gate ka core logic (`ENTITLEMENT_MAP`)
- `subscriptionService` — plan status fetch/cache

### 7.16 Sync Engine (`lib/sync/syncEngine.ts`)
- `syncProfileToCloud()` / `restoreDataFromCloud()` — (Firebase module se related, secondary sync layer)

### 7.17 Tally Export (`lib/tally/*`)
- `generateTallyPrimeXML()` / `generateCASalesRegisterCSV()` — CA/accountant ke liye Tally-compatible export

### 7.18 Utils (`lib/utils.ts`)
- `formatINR()`, `parseRupeesToPaise()`, `calculateTax()`, `generateUPILink()`, `generateWhatsAppReceiptLink()`, `cn()` (classnames merge)

### 7.19 Validation (`lib/validation/validators.ts`) — poora section 8 me detail hai

### 7.20 Voice (`lib/voice/*`)
- `parseSpokenBillingText()` / `parseVoicePhrase()` — Hindi speech se billing items nikalna ("do kilo chawal" → product + qty)

### 7.21 WhatsApp (`lib/whatsapp/*`)
- `sendWhatsAppOTP()`, `sendOfficialWhatsAppInvoice()`, `sendWhatsAppKhataReminderMessage()`, `sendWhatsAppDailySummaryMessage()`, `sendWhatsAppInteractiveButtons()`, `uploadWhatsAppMedia()` (`cloudApi.ts` — 855 lines, sabse bada WhatsApp module)
- `handleOwnerBotMessage()` / `parseOwnerIntent()` (`ownerBotService.ts`) — owner WhatsApp pe reply karke commands de sakta hai (jaise "aaj ka sale batao")

---

## 8. VALIDATION RULES (`lib/validation/validators.ts`)

| Validator | Rule |
|---|---|
| `validateIndianPhone()` | 10-digit, sirf 6/7/8/9 se start (TRAI standard) |
| `validateEmail()` | Standard RFC regex |
| `validateGstin()` | Exactly 15 chars, format: `2-digit-state + 5-letter-PAN + 4-digit + 1-letter + entity + Z + checksum` |
| `validateUpiId()` | VPA format `xxx@bankhandle` |
| `validatePincode()` | 6-digit Indian postal code |
| `validateFssaiLicense()` | Food license number format (pharmacy/food business ke liye) |
| `validateProductData()` / `validateCustomerData()` / `validateExpenseData()` | Composite validators jo upar wale sabko combine karke poora form validate karte hain |

Ye sab forms me use hote hain: onboarding, settings (UPI/GST), customer add, product add, expense add.

---

## 9. DATA MODELS (Dexie Schema — 14 Tables)

`lib/db/index.ts` me `VyaparSetuDatabase` class:

| Table | Key Fields (indexed) |
|---|---|
| `businesses` | id, name, business_type, phone, created_at |
| `categories` | id, business_id, name |
| `products` | id, business_id, name, barcode, category_id, is_active, is_favorite, current_stock, min_stock_level |
| `customers` | id, business_id, name, phone, current_balance, customer_type |
| `suppliers` | id, business_id, name, phone, current_balance |
| `sales` | id, business_id, invoice_number, customer_id, payment_method, status |
| `inventory_movements` | id, business_id, product_id, movement_type, reference_id |
| `ledger_transactions` | id, business_id, party_type, party_id, transaction_type |
| `cash_registers` | id, business_id, status, opened_at, closed_at |
| `cash_expenses` | id, business_id, category, payment_mode |
| `sales_returns` | id, business_id, return_number, original_sale_id, customer_id |
| `marketing_templates` | id, category, language, is_custom |
| `audit_logs` | id, business_id, action, entity_type, entity_id |
| `purchase_bills` | id, business_id, supplier_id, status |

Corresponding TypeScript interfaces (`types/index.ts`): `Business`, `Category`, `Product`, `Customer`, `Supplier`, `Sale`, `CartItem`, `PaymentSplit`, `CashExpense`, `InventoryMovement`, `LedgerTransaction`, `CashRegister`, `ReturnItem`, `SalesReturn`, `MarketingTemplate`, `AuditLog`, `PurchaseBill`, `PurchaseBillLineItem`, `UpiAccount`, `InvoiceThemeConfig`, `ProductAttributeDefinition`.

---

## 10. KNOWN OPEN ISSUES (existing memory se cross-check, abhi bhi codebase me confirm)

1. **Firebase sync open hai** — `initBackgroundCloudSync` `AppShell.tsx` me wired hai, `firestore.rules` abhi bhi `allow read, write: if true` hai. Ye locked "Dexie-only for business data" decision ko violate karta hai. **Decision pending Rahul se.**
2. **Razorpay routes me auth-bypass** — `create-order` aur `verify` routes me client-supplied `businessId` fallback hai jab session missing ho.
3. **`ensureStarterBusinessIfEmpty()`** auth-state establish hone se pehle demo data seed karta hai.
4. **`gemini-3.6-flash`** model name `geminiClient.ts` me — valid Google model hai ya nahi verify karna baaki hai.
5. **Capacitor + TWA dono scaffolded hain** — Android distribution path decide karna baaki (TWA recommended, kam effort).
6. **Duplicate rate-limiter modules** — `lib/rateLimit.ts` aur `lib/security/rateLimiter.ts` dono same kaam karte hain.

---

## 11. SUMMARY NUMBERS

- **24 pages** (`app/*/page.tsx`)
- **31 API routes** (`app/api/**/route.ts`)
- **~90 React components** (`components/**`)
- **~50 lib/utility files** with **150+ exported functions**
- **14 Dexie tables**, **21 TypeScript data models**
- **6 major third-party service integrations**: Razorpay, Gemini AI, WhatsApp Cloud API, Firebase, Supabase, Capacitor

---

*Document generated by fresh `git clone` audit — koi purani/stale AI session summary use nahi ki gayi (jaisa ki established practice hai is project ke liye).*
