# KamaiPlus Flutter — Vertical Config Deviation Log

This log tracks all architectural nuances, judgment calls, and deliberate divergences from the original PWA reference or specification during the implementation of the Store-Type-Wise (Vertical) Adaptation.

---

### Deviations & Judgment Calls:
- **Baseline Tag**: Tagged `pre-vertical-config` on commit `8bae614`.
- **Database onUpgrade & onCreate Support**: Columns are added defensively with `ALTER TABLE ... ADD COLUMN` in `_migrateToV2(db)` as well as declared in `_ensureExtraTables` / `_createDB` so both existing upgraded installs and clean fresh installs have 100% schema alignment.
- **Row 13 Divergence (PWA vs Flutter)**: The Purchases screen remains visible for all verticals (including Restaurant) to support everyday manual kitchen inward entries; only the AI Bill Scan tile is conditionally gated by `toggles.hasBillScan`.
- **Row 7 (Quick Category Chips)**: Used `StatefulBuilder` inside the dialog so chips can update the `catCtrl.text` reactively. Chip tapping pre-fills the text field but still allows free-text override — not a restriction. `quickCategories` list from vertical config used as chip source.
- **Row 12 (Quick Supplier Chips)**: Extended the supplier name hint (from vertical config) to also dynamically swap quick-fill supplier chips per vertical. Added an inline `vertSupplierChips` map inside the `Builder` widget — judgment call to not add this to `BusinessVerticalProfile` class since it's presentation-only data specific to the Purchases screen.
- **Row 16 (Inventory Expiry Radar Tab Gating)**: When `showBatchExpiry = false`, Tab index 1 becomes "Stock Audit Trail" (not "Near Expiry"). `_buildPillTab` uses `showExpiry ? 2 : 1` as the Audit Trail index. `_activeTabIndex` value 1 will map to Audit Trail for non-pharmacy verticals — harmless since clicking it from 0 jumps to correct content via `Builder` logic. **IMPORTANT**: Near Expiry tab's internal content is still simulated/hardcoded batch data — real batch/expiry tracking from `batch_number`/`expiry_date` columns is a future task, not done here.
- **Row 18 (Cart Item Attribute Chips)**: Used emoji prefixes (📐 size, 🎨 color, 📦 batch) for visual distinction without requiring icons. Judgment call: emojis render consistently across Android API 26+ (minimum target), so no fallback needed.
- **Warranty field (Row 6 extension)**: Added a "Warranty (Months)" text field alongside IMEI for hardware vertical. This field is not in the original plan spec but was an obvious companion field to IMEI — recorded here as a minor additive judgment call. The field value is not persisted to DB in this phase (no `warrantyMonths` column in products) — it's UI-only for now, serving as a placeholder for a future schema extension.

