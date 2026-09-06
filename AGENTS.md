# 🛡️ KAMAI+ (KAMAIPLUS) NATIVE ANDROID — AI AGENT CONSTITUTION & PROTOCOLS

You are working on **KamaiPlus Native Android App** (`com.kamaiplus.pos`), built with **Flutter & SQLite** for Indian Small & Medium Retail Businesses (Kirana, Apparel, Electronics, General Stores).

---

## 👤 1. USER WORKING STYLE & COMMUNICATION PROTOCOL
1. **Language & Tone:** The user communicates in simple, direct **Hinglish / Hindi**. Respond in clear, friendly Hinglish with structured points. Avoid technical fluff and corporate jargon.
2. **One Thing at a Time (Atomic Focus):** Work on ONLY the specific screen, modal, or component requested by the user. Do not jump ahead or modify multiple unrelated screens in a single turn.
3. **No Unsolicited Rewrites:** NEVER simplify, refactor, or delete working features or UI elements unless the user explicitly tells you to remove them.
4. **Preserve Solved Problems:** Once a flow (e.g. POS cart calculations, modal dismissals, cash tender chips, database queries) is solved and working, NEVER break or modify it during unrelated tasks.
5. **Design Standard:** The user demands **Standard, Professional, Clean, Interactive Retail UI**.
   - No sluggish, unnecessary animations or page transitions.
   - High contrast, large touch targets suitable for fast counter-billing.
   - Reference images are available in the folder `Refrence PWA Attached/`. Look at them to ensure design consistency.
   - Always inform the user after finishing a screen before moving to the next one.

---

## 📱 2. APP NAVIGATION STRUCTURE (LOCKED)
The Bottom Navigation Bar has exactly 5 tabs in this order:
1. **Home** (`HomeDashboardScreen` / `HomePulseTab`)
2. **Product** (`ProductsScreen`)
3. **Billing** (`PosBillingScreen`)
4. **Khata** (`KhataScreen`)
5. **Menu** (`MenuScreen` — hub for Inventory, Cash Register, Purchases, Reports, Settings)

---

## 💰 3. FINANCIAL INVARIANT: INTEGER PAISE MATH
- **Floating point math (`0.1 + 0.2 !== 0.3`) is STRICTLY FORBIDDEN for money.**
- All monetary amounts (selling prices, cost prices, discounts, cart items, customer balances, taxes) MUST be computed and stored as **integer paise** (`1 INR = 100 paise`).
- Format helper: `MoneyFormatter.formatINR(paise)` $\rightarrow$ `₹499.00`
- Parse helper: `MoneyFormatter.parseRupeesToPaise("499")` $\rightarrow$ `49900`

---

## 🗄️ 4. DATABASE & OFFLINE-FIRST ARCHITECTURE
- Local SQLite database via `LocalDatabase.instance` in `lib/core/database/local_database.dart`.
- The local database is the single source of truth for the UI (<10ms instant response).
- Cloud sync (Firebase Firestore) runs in the background and must NEVER block cashier billing.

---

## 🧪 5. VERIFICATION & COMMIT PROTOCOL
Before telling the user a task is complete or committing to Git:
1. Run `flutter analyze` in the project root.
2. Ensure there are **0 compile errors**.
3. Keep commit messages clear: `feat: <description>` or `fix: <description>`.
4. Keystore for Google Play release is stored at `android/app/kamai-release-key.jks` with alias `kamaiplus`.
