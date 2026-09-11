/// One quick-fill chip for a quantity/weight/strip input — e.g. "250g" -> 0.25.
class QuantityChip {
  final String label;
  final double value;
  const QuantityChip(this.label, this.value);
}

/// The full set of quick-entry chips and copy for a product's unit.
class QuantityUnitConfig {
  final String unitLabel;
  final String decimalNotice;
  final List<QuantityChip> chips;

  const QuantityUnitConfig({
    required this.unitLabel,
    required this.decimalNotice,
    required this.chips,
  });
}

/// Returns the correct quantity-entry chips and copy for a product's unit —
/// e.g. a kg-priced loose item (kaju, badam, atta) gets 10g–500g chips plus
/// whole-kg ones, a pharmacy strip gets per-tablet chips when its pack size
/// is known (or a half-strip fallback when it isn't), a dozen-counted item
/// gets half/1.5/etc. dozen chips, and anything else falls back to a plain
/// whole-count list.
///
/// [subUnitsPerPack] is the real tablet/piece count inside one pack of a
/// `strip`-unit product (real strips are 10, 15, 20 or 30 tablets — never
/// assume 2). Pass `product.subUnitsPerPack`; leave it null when unknown and
/// the generic whole/half-strip chips are used instead of a wrong guess.
///
/// This was originally private to the POS billing cart-item editor
/// (`pos_item_edit_modal.dart`), where loose-item entry already worked
/// correctly. Extracted here so the Products screen's stock-update ("pencil")
/// modal and the Add Product screen's opening-stock field can show the same
/// unit-aware chips instead of a generic whole-number list that doesn't fit
/// a kilogram or a strip. See DEVELOPMENT_LOG.md's entry on loose-item
/// quantity granularity for the full context.
QuantityUnitConfig quantityConfigForUnit(String unit, {int? subUnitsPerPack}) {
  final norm = unit.trim().toLowerCase();

  if (norm == 'kg') {
    return const QuantityUnitConfig(
      unitLabel: 'Weight (Kilograms - kg)',
      decimalNotice: 'Decimals supported (Grams / Kg)',
      chips: [
        QuantityChip('10g', 0.01),
        QuantityChip('25g', 0.025),
        QuantityChip('50g', 0.05),
        QuantityChip('100g', 0.1),
        QuantityChip('250g', 0.25),
        QuantityChip('500g', 0.5),
        QuantityChip('1 kg', 1),
        QuantityChip('2 kg', 2),
        QuantityChip('5 kg', 5),
      ],
    );
  }

  if (norm == 'gram' || norm == 'g') {
    return const QuantityUnitConfig(
      unitLabel: 'Weight (Grams - g)',
      decimalNotice: 'Grams count',
      chips: [
        QuantityChip('10g', 10),
        QuantityChip('25g', 25),
        QuantityChip('50g', 50),
        QuantityChip('100g', 100),
        QuantityChip('250g', 250),
        QuantityChip('500g', 500),
        QuantityChip('1000g', 1000),
      ],
    );
  }

  if (norm == 'litre' || norm == 'l') {
    return const QuantityUnitConfig(
      unitLabel: 'Volume (Litres - L)',
      decimalNotice: 'Decimals supported (ml / Litres)',
      chips: [
        QuantityChip('100ml', 0.1),
        QuantityChip('250ml', 0.25),
        QuantityChip('500ml', 0.5),
        QuantityChip('1 L', 1),
        QuantityChip('2 L', 2),
        QuantityChip('5 L', 5),
      ],
    );
  }

  if (norm == 'sqft') {
    // Hardware items sold by area (tiles, marble, plywood sheets, glass) —
    // Phase 4 of the KamaiPlus Playbook. A tile job is rarely a whole
    // number of sq.ft, so half/quarter increments matter here the same
    // way grams matter for a kg-priced loose item.
    return const QuantityUnitConfig(
      unitLabel: 'Area (Square Feet - sq.ft)',
      decimalNotice: 'Decimals supported (e.g. 2.5 sq.ft)',
      chips: [
        QuantityChip('¼ sq.ft', 0.25),
        QuantityChip('½ sq.ft', 0.5),
        QuantityChip('1 sq.ft', 1),
        QuantityChip('2 sq.ft', 2),
        QuantityChip('5 sq.ft', 5),
        QuantityChip('10 sq.ft', 10),
        QuantityChip('25 sq.ft', 25),
        QuantityChip('50 sq.ft', 50),
        QuantityChip('100 sq.ft', 100),
      ],
    );
  }

  if (norm == 'strip') {
    // A real strip's pack size is known (10 / 15 / 20 / 30 tablets are all
    // common) — offer per-tablet chips so a customer buying 3 out of a
    // 15-tablet strip can actually be billed correctly, instead of forcing
    // a whole or half strip. Quantity stays denominated in strips (the unit
    // the price is set per), same as a 250g chip stays denominated in kg —
    // a tablet count is just `count / subUnitsPerPack` strips.
    if (subUnitsPerPack != null && subUnitsPerPack > 1) {
      final tabletCounts = <int>{
        1,
        if (subUnitsPerPack >= 3) 2,
        if (subUnitsPerPack >= 4) 3,
        if (subUnitsPerPack >= 6) 5,
        if (subUnitsPerPack ~/ 2 > 1 && subUnitsPerPack ~/ 2 < subUnitsPerPack) subUnitsPerPack ~/ 2,
      }..removeWhere((n) => n >= subUnitsPerPack);
      final sortedCounts = tabletCounts.toList()..sort();

      return QuantityUnitConfig(
        unitLabel: 'Quantity (Strip of $subUnitsPerPack)',
        decimalNotice: 'Tap a tablet count or type strip count',
        chips: [
          for (final n in sortedCounts)
            QuantityChip(n == 1 ? '1 Tablet' : '$n Tablets', n / subUnitsPerPack),
          QuantityChip('1 Full Strip', 1),
        ],
      );
    }
    return const QuantityUnitConfig(
      unitLabel: 'Quantity (Strips)',
      decimalNotice: 'Strip counts (0.5 for loose/half) — set the strip\'s tablet count on the product for exact tablet billing',
      chips: [
        QuantityChip('1 Strip', 1),
        QuantityChip('2 Strips', 2),
        QuantityChip('3 Strips', 3),
        QuantityChip('4 Strips', 4),
        QuantityChip('5 Strips', 5),
        QuantityChip('10 Strips', 10),
        QuantityChip('½ Strip', 0.5),
      ],
    );
  }

  if (norm == 'dozen') {
    return const QuantityUnitConfig(
      unitLabel: 'Quantity (Dozen)',
      decimalNotice: 'Dozen count (0.5 = 6 pcs)',
      chips: [
        QuantityChip('½ Dozen (6)', 0.5),
        QuantityChip('1 Dozen (12)', 1),
        QuantityChip('1.5 Dozen (18)', 1.5),
        QuantityChip('2 Dozen (24)', 2),
        QuantityChip('3 Dozen (36)', 3),
        QuantityChip('5 Dozen (60)', 5),
      ],
    );
  }

  // Default: Packet, Piece, Box, Bottle, etc. — whole counts only.
  final displayUnitName = norm.isNotEmpty ? (norm[0].toUpperCase() + norm.substring(1)) : 'Packet';
  return QuantityUnitConfig(
    unitLabel: 'Quantity ($displayUnitName)',
    decimalNotice: 'Whole count / Units',
    chips: const [
      QuantityChip('1', 1),
      QuantityChip('2', 2),
      QuantityChip('3', 3),
      QuantityChip('4', 4),
      QuantityChip('5', 5),
      QuantityChip('6', 6),
      QuantityChip('10', 10),
      QuantityChip('12', 12),
      QuantityChip('24', 24),
    ],
  );
}
