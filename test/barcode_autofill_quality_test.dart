// Regression tests for the barcode → product-detail autofill pipeline.
//
// User report: "product add karte time barcode scan karne par internet se puri
// detail ani chahiye — atleast naam, unit vagaira sab."
//
// The pipeline existed but the normalisation on the way out of it was wrong in
// ways that quietly damaged the merchant's own catalog. These tests pin the
// corrected behaviour so it cannot regress:
//
//  1. Unit inference matched ' g' as a SUBSTRING, so "Amul Gold" and
//     "Britannia Good Day" were both filed as grams.
//  2. Category came straight from the Open Food Facts English taxonomy and was
//     then auto-created as a real category row in the shop's catalog.
//  3. Unit spellings from the seeded catalog and from online repositories
//     ('pack', 'jar', 'tube', 'pouch', ...) were appended to the Add Product
//     dropdown verbatim, so one unit ended up with four spellings.
//  4. Any string of 6+ characters was sent to the network as a "barcode".
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/services/cloud_barcode_resolver_service.dart';
import 'package:kamaiplus_pos/core/constants/business_vertical_config.dart';

void main() {
  group('Unit inference from pack size', () {
    test('parses real weights and volumes out of the pack-size string', () {
      expect(CloudBarcodeResolverService.inferUnit(packSize: '5 kg'), 'kg');
      expect(CloudBarcodeResolverService.inferUnit(packSize: '500 g'), 'gram');
      expect(CloudBarcodeResolverService.inferUnit(packSize: '70g'), 'gram');
      expect(CloudBarcodeResolverService.inferUnit(packSize: '1 L'), 'litre');
      expect(CloudBarcodeResolverService.inferUnit(packSize: '250 ml'), 'ml');
      expect(CloudBarcodeResolverService.inferUnit(packSize: '1.5 litre'), 'litre');
    });

    test('a brand name containing " g" is NOT read as grams', () {
      // The exact old failure: `text.contains(' g')` matched the space-g in
      // "Amul Gold", so a 1 litre milk pack was filed as a gram item.
      expect(
        CloudBarcodeResolverService.inferUnit(name: 'Amul Gold Full Cream Milk'),
        isNot('gram'),
      );
      expect(
        CloudBarcodeResolverService.inferUnit(name: 'Britannia Good Day Cashew Cookies'),
        isNot('gram'),
      );
      expect(
        CloudBarcodeResolverService.inferUnit(name: 'Tata Sampann Green Moong Dal'),
        isNot('gram'),
      );
    });

    test('pack size wins over anything guessable from the name', () {
      expect(
        CloudBarcodeResolverService.inferUnit(
          packSize: '1 L',
          name: 'Amul Gold Full Cream Milk',
        ),
        'litre',
      );
    });

    test('falls back to a vertical-appropriate unit, never a blanket pcs', () {
      expect(CloudBarcodeResolverService.inferUnit(name: 'Unknown Item', vertical: 'grocery'), 'piece');
      expect(CloudBarcodeResolverService.inferUnit(name: 'Unknown Item', vertical: 'pharmacy'), 'strip');
      expect(CloudBarcodeResolverService.inferUnit(name: 'Unknown Item', vertical: 'restaurant'), 'plate');
    });

    test('every inferred unit is one the app actually knows', () {
      final samples = <Map<String, String?>>[
        {'packSize': '5 kg', 'name': 'Atta'},
        {'packSize': '200 ml', 'name': 'Shampoo'},
        {'packSize': '15 tablets', 'name': 'Paracetamol'},
        {'packSize': '1 bottle', 'name': 'Cough Syrup'},
        {'packSize': '6 sachets', 'name': 'Shampoo Sachet'},
        {'packSize': null, 'name': 'Random Thing'},
      ];
      for (final s in samples) {
        final unit = CloudBarcodeResolverService.inferUnit(
          packSize: s['packSize'],
          name: s['name'],
        );
        expect(
          BusinessVerticals.unitDisplayLabels.containsKey(unit),
          isTrue,
          reason: '"$unit" is not a unit this app has a label for',
        );
      }
    });
  });

  group('Category mapping onto the merchant\'s own vertical categories', () {
    test('maps an Open Food Facts taxonomy string onto a real kirana category', () {
      expect(
        CloudBarcodeResolverService.mapToVerticalCategory(
          'en:plant-based-foods-and-beverages,en:snacks,en:biscuits',
          'Parle-G Glucose Biscuits',
          'grocery',
        ),
        'Biscuits & Snacks',
      );
      expect(
        CloudBarcodeResolverService.mapToVerticalCategory(
          'en:dairies,en:fermented-foods',
          'Amul Butter 500g',
          'grocery',
        ),
        'Dairy, Bread & Eggs',
      );
    });

    test('unrecognised taxonomy becomes General, never a junk category row', () {
      // 'General' is the value every caller deliberately SKIPS rather than
      // creating — so an unmappable foreign taxonomy can no longer end up as a
      // category pill in a kirana's catalog.
      expect(
        CloudBarcodeResolverService.mapToVerticalCategory(
          'en:groceries,en:some-unmappable-taxonomy-node',
          'Mystery Import',
          'grocery',
        ),
        'General',
      );
    });

    test('mapping respects the active vertical', () {
      expect(
        CloudBarcodeResolverService.mapToVerticalCategory('', 'Dolo 650 Paracetamol Tablets', 'pharmacy'),
        'Tablets & Capsules',
      );
      expect(
        CloudBarcodeResolverService.mapToVerticalCategory('', 'Levis Slim Fit Jeans', 'clothing'),
        'Jeans & Trousers',
      );
      expect(
        CloudBarcodeResolverService.mapToVerticalCategory('', 'Havells LED Bulb 9W', 'hardware'),
        'LED Bulbs & Battens',
      );
    });

    test('every mapped category is one the vertical actually offers', () {
      for (final vertical in ['grocery', 'pharmacy', 'clothing', 'hardware', 'restaurant']) {
        final profile = BusinessVerticals.resolve(vertical);
        final mapped = CloudBarcodeResolverService.mapToVerticalCategory(
          'en:snacks,en:biscuits',
          'Parle-G Glucose Biscuits 250g',
          vertical,
        );
        expect(
          mapped == 'General' || profile.quickCategories.contains(mapped),
          isTrue,
          reason: '$vertical produced "$mapped", which is not one of its own categories',
        );
      }
    });
  });

  group('Barcode validation', () {
    test('accepts the real retail symbologies', () {
      expect(CloudBarcodeResolverService.normalizeBarcode('8901030383701'), '8901030383701'); // EAN-13
      expect(CloudBarcodeResolverService.normalizeBarcode('012345678905'), '012345678905'); // UPC-A
      expect(CloudBarcodeResolverService.normalizeBarcode('96385074'), '96385074'); // EAN-8
    });

    test('strips separators a scanner or a paste can introduce', () {
      expect(CloudBarcodeResolverService.normalizeBarcode(' 8901-030-383701 '), '8901030383701');
    });

    test('rejects input no barcode repository could ever resolve', () {
      // Each of these used to be sent to the network and cost the cashier a
      // multi-second stall at the counter for a guaranteed miss.
      expect(CloudBarcodeResolverService.normalizeBarcode('ABC123'), isNull);
      expect(CloudBarcodeResolverService.normalizeBarcode('12345'), isNull);
      expect(CloudBarcodeResolverService.normalizeBarcode(''), isNull);
      expect(CloudBarcodeResolverService.normalizeBarcode('123456789012345678'), isNull);
    });
  });

  group('Display name assembly', () {
    test('prefixes the brand only when the name does not already carry it', () {
      expect(
        CloudBarcodeResolverService.buildDisplayName(rawName: 'Glucose Biscuits', brand: 'Parle'),
        'Parle Glucose Biscuits',
      );
      expect(
        CloudBarcodeResolverService.buildDisplayName(rawName: 'Parle-G Glucose Biscuits', brand: 'Parle-G'),
        'Parle-G Glucose Biscuits',
      );
    });

    test('appends the pack size once, not twice', () {
      expect(
        CloudBarcodeResolverService.buildDisplayName(
          rawName: 'Amul Butter 500g',
          brand: 'Amul',
          packSize: '500g',
        ),
        'Amul Butter 500g',
      );
      expect(
        CloudBarcodeResolverService.buildDisplayName(
          rawName: 'Amul Butter',
          brand: 'Amul',
          packSize: '500 g',
        ),
        'Amul Butter (500 g)',
      );
    });

    test('keeps the title short enough for a counter product card', () {
      final long = CloudBarcodeResolverService.buildDisplayName(
        rawName: 'A' * 300,
        brand: 'Brand',
      );
      expect(long.length, lessThanOrEqualTo(90));
    });
  });

  group('Unit synonym folding', () {
    test('four spellings of one unit collapse to one', () {
      for (final spelling in ['pack', 'pkt', 'pouch', 'sachet', 'bag']) {
        expect(BusinessVerticals.canonicalUnit(spelling), 'packet',
            reason: '"$spelling" should fold onto packet');
      }
      for (final spelling in ['bottle', 'jar', 'can', 'tin']) {
        expect(BusinessVerticals.canonicalUnit(spelling), 'btl',
            reason: '"$spelling" should fold onto btl');
      }
      for (final spelling in ['pcs', 'pc', 'nos', 'unit', 'tube']) {
        expect(BusinessVerticals.canonicalUnit(spelling), 'piece',
            reason: '"$spelling" should fold onto piece');
      }
    });

    test('canonical units survive untouched', () {
      for (final unit in ['kg', 'gram', 'litre', 'ml', 'packet', 'piece', 'box', 'strip']) {
        expect(BusinessVerticals.canonicalUnit(unit), unit);
      }
    });

    test('folds to something the app has a label for', () {
      // Sampled from the unit spellings actually present in the seeded master
      // catalog — the exact set that used to pollute the Add Product dropdown.
      const seedSpellings = [
        'packet', 'pack', 'bottle', 'strip', 'piece', 'jar', 'tube', 'box',
        'bag', 'pouch', 'kg', 'bar', 'litre', 'sachet', 'can', 'tetra',
        'tray', 'tin', 'refill', 'cup',
      ];
      for (final s in seedSpellings) {
        final canonical = BusinessVerticals.canonicalUnit(s);
        expect(
          BusinessVerticals.unitDisplayLabels.containsKey(canonical),
          isTrue,
          reason: '"$s" folded to "$canonical", which has no display label',
        );
      }
    });
  });
}
