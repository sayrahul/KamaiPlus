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
      final ml500 = config.chips.firstWhere((c) => c.label == '500ml');
      expect(ml500.value, 0.5);
    });

    test('an unrecognised unit falls back to a safe whole-count list, never crashes', () {
      final config = quantityConfigForUnit('quintal');
      expect(config.chips, isNotEmpty);
      expect(config.chips.every((c) => c.value == c.value.roundToDouble()), isTrue);
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
