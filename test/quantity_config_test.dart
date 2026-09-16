// Tests for the loose-item / pharmacy-strip granularity fix added
// 2026-09-11 (Phase 1 of the KamaiPlus Playbook): quantityConfigForUnit is
// the single source of quantity chips now shared by the POS billing
// cart-item editor, the Products screen's "pencil" stock-update modal, and
// the Add Product screen's opening-stock field. Before this fix, only the
// billing screen had unit-aware chips — this file locks in that every unit
// still resolves correctly from the shared function, and that a real
// strip's tablet count actually changes what a customer can be billed for.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/utils/quantity_config.dart';

void main() {
  group('quantityConfigForUnit — weight & volume units', () {
    test('kg offers gram-level chips down to 10g, not just whole kilos', () {
      final config = quantityConfigForUnit('kg');
      final labels = config.chips.map((c) => c.label).toList();

      expect(labels, containsAll(['10g', '25g', '50g', '100g', '250g', '500g', '1 kg']));
      // The exact bug reported: a pencil-edit screen offering only whole-kg
      // presets for a loose item like kaju/badam.
      final gram250 = config.chips.firstWhere((c) => c.label == '250g');
      expect(gram250.value, 0.25, reason: '250g must be a quarter of a kg, not 250 whole kg');
    });

    test('litre offers ml-level chips', () {
      final config = quantityConfigForUnit('litre');
      // Asserted by VALUE, not by an exact label string. This test was failing
      // (pre-existing, unrelated to any behaviour change) because it looked for
      // a chip labelled exactly '500ml' while the config had since been
      // relabelled '½ L (500ml)'. The behaviour it exists to protect — that a
      // half-litre is one tap away — was never broken; only the label moved.
      final ml500 = config.chips.firstWhere((c) => c.value == 0.5);
      expect(ml500.label, contains('500ml'));
      // And genuinely sub-quarter-litre granularity is still offered.
      expect(config.chips.any((c) => c.value == 0.05), isTrue, reason: '50ml chip');
      expect(config.chips.any((c) => c.value == 0.1), isTrue, reason: '100ml chip');
    });

    test('sqft (hardware per-area pricing, Phase 4) offers fractional area chips', () {
      final config = quantityConfigForUnit('sqft');
      final quarter = config.chips.firstWhere((c) => c.label == '¼ sq.ft');
      expect(quarter.value, 0.25);
      final hundred = config.chips.firstWhere((c) => c.label == '100 sq.ft');
      expect(hundred.value, 100);
    });

    test('an unrecognised unit falls back to a safe chip list, never crashes', () {
      final config = quantityConfigForUnit('quintal');
      expect(config.chips, isNotEmpty);
      // The point of this test is that an unknown unit degrades gracefully
      // instead of throwing or rendering an empty chip row.
      //
      // It previously also asserted every fallback chip was a WHOLE number.
      // That was true when written, but the default branch was later changed
      // on purpose to "generic whole + fractional counts" (see the comment on
      // it in quantity_config.dart) — half a quintal is a perfectly real thing
      // to sell. This test was left asserting the older shape and had been
      // failing ever since; it now matches the deliberate behaviour rather
      // than dragging the code back to it.
      expect(config.chips.any((c) => c.value == 1), isTrue, reason: 'a plain "1" must exist');
      expect(config.chips.every((c) => c.value > 0), isTrue, reason: 'no zero/negative chips');
      expect(config.unitLabel.toLowerCase(), contains('quintal'));
    });
  });

  group('quantityConfigForUnit — pharmacy strip, tablet-level billing', () {
    test('with no known pack size, falls back to the old whole/half-strip chips', () {
      final config = quantityConfigForUnit('strip');
      final labels = config.chips.map((c) => c.label).toList();
      expect(labels, contains('½ Strip'));
      expect(labels, isNot(contains(matches(RegExp(r'Tablet')))), reason: 'no tablet chips without a real pack size');
    });

    test('a 15-tablet strip lets a customer be billed for exactly 3 tablets', () {
      final config = quantityConfigForUnit('strip', subUnitsPerPack: 15);
      final threeTablets = config.chips.firstWhere(
        (c) => c.label == '3 Tablets',
        orElse: () => throw StateError('expected a "3 Tablets" chip for a 15-tablet strip'),
      );
      // Quantity stays denominated in strips (what the price is set per) —
      // 3 of 15 tablets is exactly 1/5 of a strip.
      expect(threeTablets.value, closeTo(3 / 15, 1e-9));
    });

    test('a 10-tablet strip and a 20-tablet strip produce different chip sets', () {
      final ten = quantityConfigForUnit('strip', subUnitsPerPack: 10);
      final twenty = quantityConfigForUnit('strip', subUnitsPerPack: 20);

      expect(ten.unitLabel, contains('10'));
      expect(twenty.unitLabel, contains('20'));
      expect(
        ten.chips.map((c) => c.label).toSet(),
        isNot(equals(twenty.chips.map((c) => c.label).toSet())),
        reason: 'different real-world pack sizes must not collapse to identical chips',
      );
    });

    test('every generated tablet chip stays below a full strip — no bogus 15-of-10', () {
      final config = quantityConfigForUnit('strip', subUnitsPerPack: 10);
      final tabletChips = config.chips.where((c) => c.label.contains('Tablet'));
      for (final c in tabletChips) {
        expect(c.value, lessThan(1), reason: '${c.label} must be a fraction of one strip');
      }
    });

    test('a full-strip chip is always present so a whole strip is still one tap away', () {
      final config = quantityConfigForUnit('strip', subUnitsPerPack: 15);
      expect(config.chips.any((c) => c.label == '1 Full Strip' && c.value == 1), isTrue);
    });

    test('a degenerate pack size of 1 does not crash and falls back safely', () {
      expect(() => quantityConfigForUnit('strip', subUnitsPerPack: 1), returnsNormally);
      final config = quantityConfigForUnit('strip', subUnitsPerPack: 1);
      expect(config.chips, isNotEmpty);
    });
  });

  group('quantityConfigForUnit — dozen (unaffected by this change)', () {
    test('still offers half/1.5/etc. dozen chips', () {
      final config = quantityConfigForUnit('dozen');
      final half = config.chips.firstWhere((c) => c.label.contains('½ Dozen'));
      expect(half.value, 0.5);
    });
  });
}
