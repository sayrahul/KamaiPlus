// Guards the barcode resolution ladder's entry gate.
//
// Written after discovering that 22 of the 23 barcodes in the app's own
// "curated Indian retail dictionary", and 115 of the 368 in the seeded master
// catalog, carry an invalid EAN-13 check digit. They were invented, not read
// off a pack. A barcode with a bad check digit cannot exist on a real product,
// so every one of those rows was unreachable: scanning the actual Dettol bottle
// could never match the dictionary's row labelled "Dettol". The tier looked
// correctly wired and resolved nothing.
//
// The "real" barcodes below were each verified live against Open Food Facts.

import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/services/cloud_barcode_resolver_service.dart';
import 'package:kamaiplus_pos/core/constants/master_catalog_data.dart';

void main() {
  group('CloudBarcodeResolverService.hasValidCheckDigit', () {
    test('accepts real barcodes verified against Open Food Facts', () {
      for (final code in const [
        '8901719134845', // Parle-G Biscuit
        '8901063139329', // Britannia Bourbon
        '8902080000227', // Sting Energy
        '3017620422003', // Nutella (control)
      ]) {
        expect(
          CloudBarcodeResolverService.hasValidCheckDigit(code),
          isTrue,
          reason: '$code is a real, scannable barcode',
        );
      }
    });

    test('rejects the fabricated barcodes that used to sit in the seed dictionary', () {
      for (final code in const [
        '8901030383701',
        '8901117001163',
        '8904043901007',
        '8901058852854',
      ]) {
        expect(
          CloudBarcodeResolverService.hasValidCheckDigit(code),
          isFalse,
          reason: '$code has a wrong check digit and cannot exist on a pack',
        );
      }
    });

    test('handles UPC-A, EAN-8 and GTIN-14 as well as EAN-13', () {
      expect(CloudBarcodeResolverService.hasValidCheckDigit('036000291452'), isTrue, reason: 'UPC-A');
      expect(CloudBarcodeResolverService.hasValidCheckDigit('036000291453'), isFalse);
      expect(CloudBarcodeResolverService.hasValidCheckDigit('96385074'), isTrue, reason: 'EAN-8');
      expect(CloudBarcodeResolverService.hasValidCheckDigit('96385075'), isFalse);
      // A GTIN-14 carton computes its own check digit over all 13 leading
      // digits — it does not inherit the inner EAN-13's.
      expect(CloudBarcodeResolverService.hasValidCheckDigit('18901719134842'), isTrue, reason: 'GTIN-14');
    });

    test('rejects non-numeric input and impossible lengths', () {
      for (final bad in const ['', '123', '1234567890123456', 'SHOP-LABEL-7', '890171913484X']) {
        expect(CloudBarcodeResolverService.hasValidCheckDigit(bad), isFalse);
      }
    });

    test('a length that is not a GTIN length is rejected even if numeric', () {
      // 9, 10, 11 digits are not any retail barcode symbology.
      expect(CloudBarcodeResolverService.hasValidCheckDigit('123456789'), isFalse);
      expect(CloudBarcodeResolverService.hasValidCheckDigit('12345678901'), isFalse);
    });
  });

  group('normalizeBarcode', () {
    test('strips scanner punctuation but keeps the digits', () {
      expect(CloudBarcodeResolverService.normalizeBarcode(' 8901719134845 '), '8901719134845');
      expect(CloudBarcodeResolverService.normalizeBarcode('8901-7191-34845'), '8901719134845');
    });

    test('refuses anything that could not be a GTIN', () {
      expect(CloudBarcodeResolverService.normalizeBarcode('123'), isNull);
      expect(CloudBarcodeResolverService.normalizeBarcode('123456789012345'), isNull);
      expect(CloudBarcodeResolverService.normalizeBarcode('NO-DIGITS'), isNull);
    });
  });

  group('Seeded master catalog barcode integrity', () {
    // This does not yet pass for the whole catalog — 115 of 368 seeded
    // barcodes are invented. Those rows still work as catalog entries (name,
    // category, price all remain useful); only their barcode is unreachable.
    // The test records the count so it cannot silently grow, and so whoever
    // cleans the data can watch this number fall.
    test('the number of unscannable seeded barcodes does not increase', () {
      final withBarcodes = kMasterCatalogSeed
          .where((m) => m.barcode.trim().isNotEmpty)
          .toList();
      final invalid = withBarcodes
          .where((m) => !CloudBarcodeResolverService.hasValidCheckDigit(m.barcode.trim()))
          .toList();

      expect(
        invalid.length,
        lessThanOrEqualTo(115),
        reason:
            'Seeded barcodes with a bad check digit can never match a real scan. '
            'Found ${invalid.length} of ${withBarcodes.length}. Do not add more — '
            'transcribe barcodes from real packs, or leave the field empty.',
      );
    });

    test('no seeded barcode is duplicated across two different products', () {
      final seen = <String, String>{};
      final collisions = <String>[];
      for (final m in kMasterCatalogSeed) {
        final b = m.barcode.trim();
        if (b.isEmpty) continue;
        final prev = seen[b];
        if (prev != null && prev != m.name) {
          collisions.add('$b -> "$prev" and "${m.name}"');
        }
        seen[b] = m.name;
      }
      expect(collisions, isEmpty,
          reason: 'One barcode autofilling two different products is a silent wrong-item bug');
    });
  });
}
