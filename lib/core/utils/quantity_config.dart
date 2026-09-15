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

  if (norm == 'kg' || norm == 'kilo' || norm == 'kilogram') {
    return const QuantityUnitConfig(
      unitLabel: 'Weight (Kilograms - kg)',
      decimalNotice: 'Fractions / Grams supported',
      chips: [
        QuantityChip('10g', 0.01),
        QuantityChip('25g', 0.025),
        QuantityChip('50g', 0.05),
        QuantityChip('100g', 0.1),
        QuantityChip('250g', 0.25),
        QuantityChip('500g', 0.5),
        QuantityChip('750g', 0.75),
        QuantityChip('1 kg', 1),
        QuantityChip('1.5 kg', 1.5),
        QuantityChip('2 kg', 2),
        QuantityChip('5 kg', 5),
      ],
    );
  }

  if (norm == 'plate' || norm == 'portion' || norm == 'thali' || norm == 'serving' || norm == 'dish') {
    return const QuantityUnitConfig(
      unitLabel: 'Portion (Plate / Half / Third)',
      decimalNotice: 'Fractions supported (Half, Quarter, 1/3)',
      chips: [
        QuantityChip('¼ Plate', 0.25),
        QuantityChip('⅓ Plate', 0.33),
        QuantityChip('½ Plate', 0.5),
        QuantityChip('¾ Plate', 0.75),
        QuantityChip('1 Plate', 1),
        QuantityChip('1.5 Plate', 1.5),
        QuantityChip('2 Plates', 2),
        QuantityChip('3 Plates', 3),
        QuantityChip('5 Plates', 5),
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

  if (norm == 'litre' || norm == 'liter' || norm == 'l') {
    return const QuantityUnitConfig(
      unitLabel: 'Volume (Litres - L)',
      decimalNotice: 'Fractions / Millilitres supported',
      chips: [
        QuantityChip('50ml', 0.05),
        QuantityChip('100ml', 0.1),
        QuantityChip('¼ L (250ml)', 0.25),
        QuantityChip('½ L (500ml)', 0.5),
        QuantityChip('¾ L (750ml)', 0.75),
        QuantityChip('1 L', 1),
        QuantityChip('1.5 L', 1.5),
        QuantityChip('2 L', 2),
        QuantityChip('5 L', 5),
      ],
    );
  }

  if (norm == 'packet' || norm == 'pkt' || norm == 'pack') {
    return const QuantityUnitConfig(
      unitLabel: 'Quantity (Packet)',
      decimalNotice: 'Fractions supported (Quarter, Half, etc.)',
      chips: [
        QuantityChip('¼ Pkt', 0.25),
        QuantityChip('⅓ Pkt', 0.33),
        QuantityChip('½ Pkt', 0.5),
        QuantityChip('¾ Pkt', 0.75),
        QuantityChip('1 Pkt', 1),
        QuantityChip('1.5 Pkt', 1.5),
        QuantityChip('2 Pkts', 2),
        QuantityChip('3 Pkts', 3),
        QuantityChip('5 Pkts', 5),
      ],
    );
  }

  if (norm == 'piece' || norm == 'pcs' || norm == 'pc' || norm == 'box' || norm == 'bottle' || norm == 'can') {
    final unitTitle = norm.isNotEmpty ? norm[0].toUpperCase() + norm.substring(1) : 'Piece';
    return QuantityUnitConfig(
      unitLabel: 'Quantity ($unitTitle)',
      decimalNotice: 'Fractions supported (Quarter, Half, Whole)',
      chips: const [
        QuantityChip('¼', 0.25),
        QuantityChip('⅓', 0.33),
        QuantityChip('½', 0.5),
        QuantityChip('¾', 0.75),
        QuantityChip('1', 1),
        QuantityChip('1.5', 1.5),
        QuantityChip('2', 2),
        QuantityChip('3', 3),
        QuantityChip('5', 5),
        QuantityChip('10', 10),
      ],
    );
  }

  if (norm == 'sqft') {
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

  if (norm == 'strip' || norm == 'tablets' || norm == 'tablet') {
    if (subUnitsPerPack != null && subUnitsPerPack > 1) {
      final tabletCounts = <int>[
        for (int i = 1; i < subUnitsPerPack && i <= 15; i++) i,
      ];

      return QuantityUnitConfig(
        unitLabel: 'Quantity (Strip of $subUnitsPerPack)',
        decimalNotice: 'Tap loose tablet count or full strips',
        chips: [
          for (final n in tabletCounts)
            QuantityChip(n == 1 ? '1 Tablet' : '$n Tablets', n / subUnitsPerPack),
          QuantityChip('1 Full Strip', 1),
          QuantityChip('2 Strips', 2),
          QuantityChip('3 Strips', 3),
          QuantityChip('5 Strips', 5),
        ],
      );
    }

    return const QuantityUnitConfig(
      unitLabel: 'Quantity (Strips)',
      decimalNotice: 'Strip counts (0.5 for loose/half)',
      chips: [
        QuantityChip('1 Strip', 1),
        QuantityChip('2 Strips', 2),
        QuantityChip('3 Strips', 3),
        QuantityChip('5 Strips', 5),
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

  // Default: generic whole + fractional counts
  final displayUnitName = norm.isNotEmpty ? (norm[0].toUpperCase() + norm.substring(1)) : 'Units';
  return QuantityUnitConfig(
    unitLabel: 'Quantity ($displayUnitName)',
    decimalNotice: 'Units & Fractions supported',
    chips: const [
      QuantityChip('¼', 0.25),
      QuantityChip('⅓', 0.33),
      QuantityChip('½', 0.5),
      QuantityChip('¾', 0.75),
      QuantityChip('1', 1),
      QuantityChip('2', 2),
      QuantityChip('3', 3),
      QuantityChip('5', 5),
      QuantityChip('10', 10),
    ],
  );
}
