# KamaiPlus Flutter — Vertical Config Deviation Log

This log tracks all architectural nuances, judgment calls, and deliberate divergences from the original PWA reference or specification during the implementation of the Store-Type-Wise (Vertical) Adaptation.

---

### Deviations & Judgment Calls:
- **Baseline Tag**: Tagged `pre-vertical-config` on commit `8bae614`.
- **Database onUpgrade & onCreate Support**: Columns are added defensively with `ALTER TABLE ... ADD COLUMN` in `_migrateToV2(db)` as well as declared in `_ensureExtraTables` / `_createDB` so both existing upgraded installs and clean fresh installs have 100% schema alignment.
- **Row 13 Divergence (PWA vs Flutter)**: The Purchases screen remains visible for all verticals (including Restaurant) to support everyday manual kitchen inward entries; only the AI Bill Scan tile is conditionally gated by `toggles.hasBillScan`.
