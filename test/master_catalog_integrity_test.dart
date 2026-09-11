// Guards the Phase 2 catalog-depth expansion (KamaiPlus Playbook,
// 2026-09-11): kMasterCatalogSeed grew from 165 to 368 entries in one pass.
// A dataset this size is easy to corrupt with a copy-paste duplicate or a
// bad hand-edit later — these checks catch that automatically instead of
// relying on someone noticing at runtime.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/constants/master_catalog_data.dart';

const _validBusinessTypes = {'grocery', 'pharmacy', 'clothing', 'hardware', 'restaurant', 'both'};

int _ean13CheckDigit(String digits12) {
  var total = 0;
  for (var i = 0; i < digits12.length; i++) {
    final d = int.parse(digits12[i]);
    total += i.isEven ? d : d * 3;
  }
  return (10 - (total % 10)) % 10;
}

void main() {
  group('kMasterCatalogSeed data integrity', () {
    test('has grown past the pre-Phase-2 baseline of 165', () {
      expect(kMasterCatalogSeed.length, greaterThan(165));
    });

    test('every barcode is unique — no duplicate PRIMARY KEY on insert', () {
      final barcodes = kMasterCatalogSeed.map((m) => m.barcode).toList();
      final unique = barcodes.toSet();
      expect(
        unique.length,
        barcodes.length,
        reason: 'Duplicate barcodes silently overwrite each other on insert '
            '(barcode is the SQLite PRIMARY KEY) — found '
            '${barcodes.length - unique.length} duplicate(s).',
      );
    });

    test('every barcode is 13 digits — the shape the app\'s barcode lookup assumes', () {
      final bad = kMasterCatalogSeed
          .where((m) => !RegExp(r'^\d{13}$').hasMatch(m.barcode))
          .map((m) => '${m.name}: ${m.barcode}')
          .toList();
      expect(bad, isEmpty, reason: 'Malformed barcodes:\n${bad.join('\n')}');
    });

    test('the Phase 2 batch (890 77 xxxxxxx prefix) has valid EAN-13 check digits', () {
      // Only the entries this session generated are asserted against the
      // real EAN-13 checksum — the pre-existing 165 rows were never
      // checksum-validated to begin with (a pre-existing gap, not something
      // this change touched), and the app itself never checks the digit
      // either; it uses barcode purely as a lookup key. Scoping the strict
      // check to the "89077" block this session reserved (see
      // DEVELOPMENT_LOG.md) still catches a real mistake in *new* data
      // without failing the suite over unrelated, already-shipped rows.
      final generated = kMasterCatalogSeed.where((m) => m.barcode.startsWith('89077'));
      expect(generated, isNotEmpty, reason: 'the Phase 2 batch should be present');
      final bad = generated
          .where((m) => int.parse(m.barcode[12]) != _ean13CheckDigit(m.barcode.substring(0, 12)))
          .map((m) => '${m.name}: ${m.barcode}')
          .toList();
      expect(bad, isEmpty, reason: 'Bad check digit:\n${bad.join('\n')}');
    });

    test('every entry has a non-empty name and a recognised businessType', () {
      final bad = <String>[];
      for (final m in kMasterCatalogSeed) {
        if (m.name.trim().isEmpty) bad.add('${m.barcode}: empty name');
        if (!_validBusinessTypes.contains(m.businessType)) {
          bad.add('${m.name}: unrecognised businessType "${m.businessType}"');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('every entry has a positive selling price — never a free/negative row', () {
      final bad = kMasterCatalogSeed.where((m) => m.sellingPricePaise <= 0).map((m) => m.name).toList();
      expect(bad, isEmpty, reason: 'Zero/negative selling price: ${bad.join(', ')}');
    });

    test('the Phase 2 pharmacy expansion actually landed', () {
      final pharmacyCount = kMasterCatalogSeed.where((m) => m.businessType == 'pharmacy').length;
      // Was 7 before Phase 2; this is the vertical that most needed depth.
      expect(pharmacyCount, greaterThan(50));
    });

    test('the Phase 2 grocery expansion actually landed', () {
      final groceryCount = kMasterCatalogSeed.where((m) => m.businessType == 'grocery').length;
      expect(groceryCount, greaterThan(200));
    });
  });
}
