# 📱 KAMAI+ (KAMAIPLUS) — MASTER MANUAL QA TESTING PLAYBOOK & BUG TRACKER

> **Purpose:** Fresh app install se lekar real-life retail scenarios tak har screen, modal, calculation, settings, aur hardware connectivity ko **step-by-step manually verify** karne ke liye master test checklist.
> 
> **How to use this playbook:**
> 1. Phone me app ka fresh install karein (ya App Info me jakar **Clear Data & Cache** karein).
> 2. Neeche diye gaye table me test case perform karein.
> 3. Pass hone par `[x] PASS` likhein, issue milne par `[ ] FAIL` mark karke **Observation / Bug Notes** column me likhein.
> 4. Agar koi naya bug ya UI glitch mile, toh har section ke end me **🐞 User Bug & Tweak Logger** me note likh lein.

---

## 📋 QUICK STATUS SUMMARY
- **Total Test Phases:** 12 Phases
- **Total Test Cases:** 85+ Detailed Scenarios
- **App Target:** `com.kamaiplus.pos` (Flutter & SQLite Local-First)
- **Baseline Version:** `v4.20.0`

---

## 🚀 PHASE 0: FRESH INSTALL, APP ONBOARDING & PERMISSIONS

| ID | Screen / Modal | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-001** | App Launch | App install karke pehli baar open karein | Splash screen ke baad clean **Welcome / Login** screen appear ho | `[ ] PASS` | |
| **TC-002** | Permissions | Android 13+ Notification permission prompt check | System notification permission dialog aaye; Allow karne par notification register ho | `[ ] PASS` | |
| **TC-003** | Auth Screen | Phone number enter karein (WhatsApp OTP / SMS OTP) | 6-digit OTP receive ho; auto-fill ya manual enter karne par authenticate ho | `[ ] PASS` | |
| **TC-004** | Auth Screen | Google Sign-in button tap karein | Google account chooser khule aur bina crash sign in ho | `[ ] PASS` | |
| **TC-005** | Store Setup | Shop Profile Setup screen par: Store Name, Owner Name, Phone, UPI ID enter karein | UPI ID format validate ho (e.g. `merchant@upi`); Invalid UPI par red warning dikhe | `[ ] PASS` | |
| **TC-006** | Vertical Picker | Business Vertical choose karein (Kirana, Garments, Pharmacy, Hardware, Cafe) | Selected vertical highlight ho aur default catalog seeds usi vertical ke load hon | `[ ] PASS` | |
| **TC-007** | Root Nav Init | Setup complete karke "Start Billing" tap karein | User directly **Home Tab (0)** par land ho; Bottom navigation bar me 5 items visible hon | `[ ] PASS` | |

---

## 🏠 PHASE 1: HOME DASHBOARD & OPERATIONS (TAB 0)

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-010** | Home Header | Store name, active vertical badge, aur date check karein | Correct shop name aur current Indian date/time render ho | `[ ] PASS` | |
| **TC-011** | KPI Cards | Today Sales, Orders count, Net Profit, Low stock alert check karein | Fresh app me ₹0.00 sales, 0 bills dikhe; values integer paise me accurate hon | `[ ] PASS` | |
| **TC-012** | Daily Ops Grid | Grid layout check karein (Must have exactly 2 cards) | Exactly 2 cards hon: **Cash Register** aur **Transactions** (POS Billing removed from grid) | `[ ] PASS` | |
| **TC-013** | Ops Navigation | Cash Register card tap karein | `CashRegisterScreen` open ho | `[ ] PASS` | |
| **TC-014** | Ops Navigation | Transactions card tap karein | `TransactionsScreen` open ho | `[ ] PASS` | |
| **TC-015** | Quick Actions | "Inward Stock / Add Product" shortcut tap karein | Add Product ya Rapid Inward screen smoothly push ho | `[ ] PASS` | |

---

## 📦 PHASE 2: PRODUCT MASTER CATALOG & INVENTORY (TAB 1)

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-020** | Layout Verification | Bottom Tab 1 (Product) open karein | Dense informative List View render ho (Grid View toggle removed). **No nested bottom navbar** | `[ ] PASS` | |
| **TC-021** | Product Card UI | Har product row me fields check karein | Image/Icon, Name, Category pill, Selling Price, Cost Price/Profit, Stock Stepper (`+`/`-`), Favorite star, Pencil edit button | `[ ] PASS` | |
| **TC-022** | Stock Stepper | Product card par direct `+` tap karein | Local SQLite stock instantly +1 increase ho; UI me 0.01s me update ho | `[ ] PASS` | |
| **TC-023** | Stock Stepper | Product card par `-` tap karein | Stock 1 decrease ho (0 se niche jane par negative stock warning de) | `[ ] PASS` | |
| **TC-024** | Favorite Star | Star icon tap karein | Star gold fill ho; POS billing me item top par prioritize ho | `[ ] PASS` | |
| **TC-025** | Pencil Edit Button | Product card ke pencil icon par click karein | `AddProductModal` khule with **all existing product fields pre-filled** (Name, Price, Cost, Stock, Category, Barcode) | `[ ] PASS` | |
| **TC-026** | Edit Save | Price badal kar "Update Product" tap karein | Database me new price update ho; modal dismiss ho; list me turant new price dikhe | `[ ] PASS` | |
| **TC-027** | Add Product (`+`) | Top right `+` button tap karein | Blank `AddProductModal` khule | `[ ] PASS` | |
| **TC-028** | Add Product Fields | Name, Selling Price, Cost Price, Stock, Category choose karein | Cost Price > Selling Price hone par loss warning de; Margin % auto calculate ho | `[ ] PASS` | |
| **TC-029** | Loose/Weighted Item | "Loose Weight / Sold by Weight" toggle enable karein | Unit dropdown me kg, gram, litre, metre select karne ka option enable ho | `[ ] PASS` | |
| **TC-030** | Category Filter | Top category horizontal pills scroll karein aur tap karein | Selected category ke items instantly filter hon; "All" par sabhi dikhein | `[ ] PASS` | |
| **TC-031** | Search Bar | Product name ya barcode type karein | Real-time <10ms instant SQLite filtering ho | `[ ] PASS` | |
| **TC-032** | Rapid Barcode Inward | Menu/Product se "Rapid Barcode Inward" screen open karein | Scanner activate ho; barcode scan karein | `[ ] PASS` | |
| **TC-033** | Restock Inward | Pehle se saved product ka barcode scan karein | Existing product details load hon; Inward Qty add karne par `newStock = existingStock + inwardQty` ho (overwrite na kare) | `[ ] PASS` | |
| **TC-034** | New Barcode Inward | Naye unregistered barcode ko scan karein | Naya product create form khule; Category dropdown me vertical categories auto-populate hon | `[ ] PASS` | |
| **TC-035** | AI Vision Bill OCR | Camera icon tap karke wholesale paper bill ki photo lein | OCR service table detect kare aur items pre-fill inward list me dikhaye | `[ ] PASS` | |

---

## 🧾 PHASE 3: HIGH-SPEED COUNTER BILLING POS (TAB 2 - CENTER)

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-040** | Center Button | Bottom navbar ka elevated center Billing button tap karein | Green glow center button tap karne par POS Billing screen instantly load ho | `[ ] PASS` | |
| **TC-041** | Product Selection | Catalog me kisi product par tap karein | Bottom cart bar me instant item add ho; sound/haptic feedback aaye | `[ ] PASS` | |
| **TC-042** | Multiple Taps | Same product par 3 baar tap karein | Cart me quantity `3` ho jaye; total integer paise me multiply ho | `[ ] PASS` | |
| **TC-043** | Barcode Camera Scan | Top barcode icon tap karein aur product barcode scan karein | <0.2 sec me item identify hokar cart me beep sound ke sath add ho | `[ ] PASS` | |
| **TC-044** | Loose Weight Modal | Loose item (e.g. Sugar/Rice) par tap karein | Weight calculator modal khule; 250g, 500g, 1.5kg enter karne par price exact nearest paisa calculate ho | `[ ] PASS` | |
| **TC-045** | Bottom Cart Bar | Bottom floating cart strip check karein | Total Items count aur Net Amount (₹) integer paise me calculate dikhe | `[ ] PASS` | |
| **TC-046** | Cart Sheet Open | Floating cart strip tap karein | Cart detail bottom sheet open ho with all items, individual quantities, unit prices | `[ ] PASS` | |
| **TC-047** | Cart Item Quantity | Cart sheet me `+` aur `-` stepper use karein | Item quantity increase/decrease ho; `0` karne par item cart se remove ho | `[ ] PASS` | |
| **TC-048** | Custom Item Discount | Kisi cart item par tap karke item discount add karein | Flat ₹ ya % discount apply ho; row total me cut-price dikhe | `[ ] PASS` | |
| **TC-049** | Bill-level Discount | Cart me overall bill discount add karein | Grand total se discount deduct ho; negative total allow na kare | `[ ] PASS` | |
| **TC-050** | Checkout Trigger | Cart me "Proceed to Pay / Checkout" tap karein | Payment Checkout Modal slide up ho | `[ ] PASS` | |

---

## 💳 PHASE 4: CHECKOUT MODAL, CASH TENDER & PAYMENTS

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-051** | Checkout Header | Bill summary check karein | Subtotal, GST Tax (agar configured hai), Discount, aur Grand Total exact paise me dikhe | `[ ] PASS` | |
| **TC-052** | Cash Mode (Default) | Cash tab select karein | Cash tender chips display hon: `Exact`, `+₹100`, `+₹200`, `+₹500`, `+₹2000` | `[ ] PASS` | |
| **TC-053** | Cash Chip Math | Bill ₹340 ka hai; `+₹500` chip tap karein | Tender amount ₹500 ho; "Change Due / Wapas karein: ₹160.00" green text me dikhe | `[ ] PASS` | |
| **TC-054** | Cash Tender Manual | Tender box me manual amount type karein | Change calculation real-time update ho | `[ ] PASS` | |
| **TC-055** | UPI Payment Mode | UPI tab tap karein | Dynamic UPI QR Code generate ho with store UPI ID & exact bill amount | `[ ] PASS` | |
| **TC-056** | UPI QR Verify | Doosre phone se GPay/PhonePe scan karke verify karein | QR code me store name aur exact paise amount pre-filled aaye | `[ ] PASS` | |
| **TC-057** | Udhar / Credit Mode | Udhar tab tap karein | Customer selector khule; customer choose karein ya naya add karein | `[ ] PASS` | |
| **TC-058** | Udhar Settlement | Udhar par "Charge" tap karein | Customer ke digital khata me debit balance add ho; bill create ho | `[ ] PASS` | |
| **TC-059** | Split Payment | Split Mode select karein (Part Cash + Part UPI) | Cash amount aur UPI amount ka sum Grand Total ke barabar hone par submit enable ho | `[ ] PASS` | |
| **TC-060** | Complete Bill Action | "Print & Bill / Done" tap karein | Bill save ho; SQLite stock deduct ho; Thermal print trigger ho; WhatsApp share dialog aaye; POS cart reset ho | `[ ] PASS` | |

---

## 📖 PHASE 5: DIGITAL KHATA & CUSTOMER LEDGER (TAB 3)

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-061** | Khata Screen UI | Bottom Tab 3 (Khata) tap karein | Clean "Digital Khata" header, Total Market Udhar summary card render ho | `[ ] PASS` | |
| **TC-062** | Add Customer | "+" icon tap karke Customer Name, Phone number, Credit Limit save karein | Naya customer list me add ho; phone format validate ho | `[ ] PASS` | |
| **TC-063** | Customer Search | Search bar me customer ka naam ya mobile number type karein | Matching customer instantly filter ho | `[ ] PASS` | |
| **TC-064** | Customer Ledger | Customer row par tap karein | Customer statement bottom sheet open ho; past bills, Jama (Credit), Udhar (Debit) dikhe | `[ ] PASS` | |
| **TC-065** | Give Udhar (Debit) | "Gave Udhar (-)" button tap karke amount & note enter karein | Balance badh jaye; ledger me debit entry add ho | `[ ] PASS` | |
| **TC-066** | Got Jama (Credit) | "Got Jama (+)" button tap karke Cash/UPI payment receive karein | Balance kam ho; ledger me receipt entry create ho | `[ ] PASS` | |
| **TC-067** | WhatsApp Reminder | Row par official WhatsApp icon tap karein | WhatsApp khule with pre-filled professional Hinglish reminder + UPI payment link | `[ ] PASS` | |
| **TC-068** | Settle Khata | Full settlement button tap karein | Remaining balance ₹0 ho; customer card "Clear" badge show kare | `[ ] PASS` | |

---

## 💵 PHASE 6: CASH REGISTER & EXPENSES

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-070** | Cash Register UI | Menu ya Home se Cash Register open karein | Dark gradient hero till balance card, 4-metric micro grid render ho | `[ ] PASS` | |
| **TC-071** | Opening Till | Opening Cash Till set karein (e.g. ₹2,000) | Current Drawer balance me ₹2,000 reflect ho | `[ ] PASS` | |
| **TC-072** | Add Cash Expense | "Cash Out / Expense" tap karke ₹150 Chai/Nashta tag ke sath add karein | Drawer balance se ₹150 minus ho; activity log me entry dikhe | `[ ] PASS` | |
| **TC-073** | POS Cash Feed | POS billing me ₹500 ka cash bill banayein | Cash Register me automatically "Cash Sales: +₹500" increment ho | `[ ] PASS` | |
| **TC-074** | Note & Coin Tally | "Physical Cash Tally" tap karein | Real notes assets dikhein (₹500, ₹200, ₹100, ₹50, ₹20, ₹10, coins) | `[ ] PASS` | |
| **TC-075** | Denomination Math | Har note count enter karein (e.g. 5x ₹500 = ₹2,500) | Subtotals exact multiply hon; Expected Drawer vs Physical Cash difference show ho | `[ ] PASS` | |
| **TC-076** | Z-Report Close | Day-end par "Generate Z-Report & Close Day" tap karein | Daily sales, cash breakdown, expense list ki formatted summary generate ho | `[ ] PASS` | |
| **TC-077** | WhatsApp Z-Report | Z-report WhatsApp share button tap karein | Store owner ko complete daily tally WhatsApp par message send kare | `[ ] PASS` | |

---

## 📜 PHASE 7: TRANSACTION HISTORY & INVOICE DETAILS

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-080** | Screen Navigation | Home/Menu se Transaction History open karein | Screen title "Transaction History" dikhe; persistent bottom nav bar rahe | `[ ] PASS` | |
| **TC-081** | Date Filters | Filters tap karein: Today, Yesterday, 7 Days, This Month | Selected date range ke bills correctly filter hon | `[ ] PASS` | |
| **TC-082** | Payment Mode Filter | Cash, UPI, ya Udhar filter tap karein | Sirf selected payment mode ke bills list me dikhein | `[ ] PASS` | |
| **TC-083** | Bill Detail Sheet | Kisi bill card par tap karein | Bill details sheet slide up ho with itemized list, tax breakdown, customer info | `[ ] PASS` | |
| **TC-084** | Reprint Receipt | "Reprint Thermal Receipt" tap karein | Bluetooth printer par exactly same bill bina glitch reprint ho | `[ ] PASS` | |
| **TC-085** | WhatsApp Share | "Share Bill on WhatsApp" tap karein | Clean formatted thermal receipt text WhatsApp me open ho | `[ ] PASS` | |

---

## 📂 PHASE 8: MENU HUB (BOTTOM SHEET MODAL - TAB 4)

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-090** | Modal Slide-up | Bottom navbar me "Menu" tab tap karein | **STRICTLY BOTTOM SHEET MODAL:** Niche se slide up ho, top right me 'X' close button ho (Never a 5th full PageView page) | `[ ] PASS` | |
| **TC-091** | Dismiss Contract | 'X' button tap karein ya background tap karein | Modal dismiss ho jaye; user apne previous tab par hi rahe | `[ ] PASS` | |
| **TC-092** | Hub Sections | Sections check karein | 1. Daily Billing & Counter, 2. Stock & Inventory, 3. Customers & Khata, 4. Tax, Backup & Settings | `[ ] PASS` | |
| **TC-093** | Top Banner | Check karein koi unwanted Free/Upgrade banner na ho | Menu directly *Daily Billing & Counter* se start ho | `[ ] PASS` | |
| **TC-094** | Footer Layout | Bottom footer check karein | **Single Row Layout:** 1. Version pill (`v4.20.0`), 2. WhatsApp Support, 3. Language Switcher, 4. Logout button | `[ ] PASS` | |
| **TC-095** | Language Switcher | Flag dropdown tap karein | Language selection sheet khule (English, Hindi, Marathi, Gujarati); select karne par app translate ho | `[ ] PASS` | |
| **TC-096** | WhatsApp Support | WhatsApp Support button tap karein | Official KamaiPlus support WhatsApp chat open ho | `[ ] PASS` | |
| **TC-097** | Logout Action | Red Logout button tap karein | Confirmation dialog prompt ho ("Are you sure you want to logout?"); Cancel karne par modal rahe | `[ ] PASS` | |

---

## 🖨️ PHASE 9: HARDWARE, THERMAL PRINTER & BARCODE SCANNERS

| ID | Screen / Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-100** | Printer Settings | Menu $\rightarrow$ Printer Settings open karein | Bluetooth nearby devices permission prompt kare; paired devices list show kare | `[ ] PASS` | |
| **TC-101** | Device Discovery | Bluetooth thermal printer turn on karein aur scan karein | Printer (e.g. MPT-II, POS-58, Everycom, NGX) list me show ho | `[ ] PASS` | |
| **TC-102** | Pairing & Connect | Printer select karke connect karein | "Connected" status show ho with green badge | `[ ] PASS` | |
| **TC-103** | Paper Width | 58mm (2-inch) aur 80mm (3-inch) switch karein | Receipt formatting automatic adjust ho (32 columns vs 48 columns) | `[ ] PASS` | |
| **TC-104** | Test Print | "Test Print Receipt" button tap karein | 0.8s me clean formatted test bill print ho (Store Header, Sample Items, QR Code, Footer) | `[ ] PASS` | |
| **TC-105** | Disconnect Recovery | Printer band karke on karein | App crash na ho; background reconnect gracefully handle kare | `[ ] PASS` | |

---

## 🏬 PHASE 10: 5 BUSINESS VERTICALS ISOLATION & TAILORED WORKFLOWS

| ID | Vertical | Specific Scenario | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-110** | **Kirana / Grocery** | Loose items (dal, chawal, tel) gram calculation in paise | Decimal weights (e.g. 0.450 kg @ ₹90/kg) exact nearest paise me bill ho | `[ ] PASS` | |
| **TC-111** | **Kirana / Grocery** | Fast packaged FMCG barcode scan (Parle-G, Maggi, Lux) | Barcode se instant item fetch ho; Kirana catalog me dusre vertical ka item mix na ho | `[ ] PASS` | |
| **TC-112** | **Garments / Apparel**| Size & Color variants sheet check | Product variants modal me M, L, XL, XXL select karke alag stock maintain ho | `[ ] PASS` | |
| **TC-113** | **Pharmacy** | Batch number & Expiry date tracking | Medicine add karte waqt Batch No aur Expiry date save ho; Expired alert show kare | `[ ] PASS` | |
| **TC-114** | **Hardware / Electrical**| Bulk units (meter, bundle, packet, piece) & GST B2B | Customer GSTIN enter karne par B2B Tax invoice with HSN codes generate ho | `[ ] PASS` | |
| **TC-115** | **Cafe / Dine-in** | Fast touch grid & Table / KOT token billing | Quick tap menu items; Kitchen Order Token generate karne ka option ho | `[ ] PASS` | |
| **TC-116** | **Vertical Isolation** | Store profile me vertical switch karein | Pehle vertical ke products doosre vertical me leak/mix na hon (Strict SQLite isolation) | `[ ] PASS` | |

---

## 📡 PHASE 11: OFFLINE-FIRST, INTERNET RECOVERY & FIREBASE CLOUD SYNC

| ID | Component | Step / Action | Expected Result | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-120** | Airplane Mode | Phone ko Airplane Mode me daalein (Zero internet) | App full speed me open ho; koi connection error popup na aaye | `[ ] PASS` | |
| **TC-121** | Offline Billing | Airplane mode me 3 naye bills generate karein aur khata entry karein | Billing bina kisi lag (<10ms) complete ho; bills local SQLite me safely save hon | `[ ] PASS` | |
| **TC-122** | Internet Restore | Wi-Fi / Mobile Data wapas on karein | Background `FirestoreSyncService` silently trigger ho; cloud me bills push hon | `[ ] PASS` | |
| **TC-123** | Cloud Verification | Admin Console (`kamaiplus-admin.web.app`) check karein | Phone par offline banaye gaye bills admin console me sync ho chuke hon | `[ ] PASS` | |
| **TC-124** | FCM Push Notification | Admin console se Push alert ya Instant FCM Ping send karein | Phone lock screen / system tray me high-priority heads-up drop-down banner aaye | `[ ] PASS` | |

---

## 💰 PHASE 12: FINANCIAL INTEGER PAISE INTEGRITY TESTS

| ID | Test Scenario | Calculation Input | Expected Financial Output | Status | Observation / Bug Notes |
|:---|:---|:---|:---|:---:|:---|
| **TC-130** | Float Rounding Bug | 3 items: ₹33.33 + ₹33.33 + ₹33.34 | Exact ₹100.00 (10,000 paise) — zero ₹0.01 discrepancy | `[ ] PASS` | |
| **TC-131** | GST Tax Split | ₹1,000 bill par 18% GST (CGST 9% + SGST 9%) | CGST = ₹90.00, SGST = ₹90.00, Total = ₹1,180.00 exact | `[ ] PASS` | |
| **TC-132** | Percentage Discount | ₹499 par 15% discount | Discount = ₹74.85, Net Total = ₹424.15 exact | `[ ] PASS` | |
| **TC-133** | Cash Return | Total ₹338.10, Tendered ₹500.00 | Change Due = ₹161.90 exact | `[ ] PASS` | |

---

## 🐞 USER BUG REPORT & TWEAK LOGGER
*(Aap testing ke dauran jo bhi bugs, alignment glitches, ya improvements dekhein, yaha list karte jayein so we can fix them immediately in the next step!)*

| Bug # | Screen / Modal | Issue Description | Steps to Reproduce | Severity (High / Med / Low) |
|:---:|:---|:---|:---|:---:|
| **BUG-01** | | | | |
| **BUG-02** | | | | |
| **BUG-03** | | | | |
| **BUG-04** | | | | |
| **BUG-05** | | | | |
| **BUG-06** | | | | |
| **BUG-07** | | | | |
| **BUG-08** | | | | |
| **BUG-09** | | | | |
| **BUG-10** | | | | |

---

## 📌 VERIFICATION PROTOCOL BEFORE NEXT CODE MODIFICATIONS:
1. User tests each phase on physical Android device.
2. User enters observations or marks bugs in this document.
3. Every fix will adhere to:
   - **Integer Paise Financial Math** (`MoneyFormatter.formatINR` / `parseRupeesToPaise`).
   - **Offline-First SQLite as single source of truth**.
   - **No unsolicited rewrites** of existing working features.
   - **0 compile errors** (`flutter analyze`).
