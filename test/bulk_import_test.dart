// Tests for bulk product import — the "first impression" path.
//
// A merchant installing this app has to get 500-1000+ products in before it is
// useful to them. Three things made that path quietly fail:
//
// 1. Every inward button is labelled "Upload Excel / CSV File", but the picker
//    accepted only `csv, txt, tsv`. A distributor's `.xlsx` could not even be
//    SELECTED. The label promised something the code refused.
// 2. The app's OWN generated template has Barcode and Expiry Date columns, and
//    the parser read neither — so every bulk-imported product arrived
//    unscannable, which defeats the entire reason to import in bulk, and with
//    no expiry, invisible to the pharmacy Near Expiry radar.
// 3. Column detection walked the headers once with an if/else-if chain, and the
//    purchase rule (which matches 'rate') ran before the selling rule. A sheet
//    with a "Sale Rate" column had its SELLING price read as the cost.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/services/csv_inward_service.dart';
import 'package:kamaiplus_pos/services/inventory_inward_service.dart';

void main() {
  group('Column mapping', () {
    test('maps a standard supplier sheet', () {
      final c = CsvInwardService.mapColumns([
        'Item Name', 'Quantity', 'Unit', 'Purchase Price', 'MRP',
        'Selling Price', 'Category', 'Barcode', 'Expiry Date',
      ]);
      expect(c.name, 0);
      expect(c.qty, 1);
      expect(c.unit, 2);
      expect(c.purchase, 3);
      expect(c.mrp, 4);
      expect(c.selling, 5);
      expect(c.category, 6);
      expect(c.barcode, 7, reason: 'the app generates this column itself');
      expect(c.expiry, 8);
    });

    test('"Sale Rate" is a SELLING price, not a cost', () {
      // The exact old mis-mapping: 'rate' matched the purchase rule first.
      final c = CsvInwardService.mapColumns(['Product', 'Qty', 'Sale Rate']);
      expect(c.selling, 2);
      expect(c.purchase, -1, reason: 'there is no cost column on this sheet');
    });

    test('"Purchase Rate" is still a cost', () {
      final c = CsvInwardService.mapColumns(['Product', 'Qty', 'Purchase Rate']);
      expect(c.purchase, 2);
      expect(c.selling, -1);
    });

    test('MRP is never confused with a selling or cost column', () {
      final c = CsvInwardService.mapColumns(['Item', 'MRP', 'Rate', 'Sale Price']);
      expect(c.mrp, 1);
      expect(c.purchase, 2);
      expect(c.selling, 3);
    });

    test('one column is never claimed by two roles', () {
      final c = CsvInwardService.mapColumns(['Item Name', 'Qty', 'Rate', 'MRP']);
      final used = [c.name, c.qty, c.unit, c.purchase, c.mrp, c.selling, c.category, c.barcode, c.expiry]
          .where((i) => i >= 0)
          .toList();
      expect(used.toSet().length, used.length);
    });

    test('an unrecognisable header row still treats column 0 as the item', () {
      final c = CsvInwardService.mapColumns(['Col A', 'Col B']);
      expect(c.name, 0);
    });
  });

  group('Expiry date normalisation', () {
    test('accepts the formats an Indian supplier sheet actually uses', () {
      expect(CsvInwardService.normalizeExpiry('2026-12-31'), '2026-12-31');
      expect(CsvInwardService.normalizeExpiry('2026-9-5'), '2026-09-05');
      // Day-first, not month-first — a UK/India sheet, not a US one.
      expect(CsvInwardService.normalizeExpiry('31/12/2026'), '2026-12-31');
      expect(CsvInwardService.normalizeExpiry('05-09-2027'), '2027-09-05');
      // The usual pharmacy strip stamp.
      expect(CsvInwardService.normalizeExpiry('12/2026'), '2026-12-01');
      expect(CsvInwardService.normalizeExpiry('08-27'), '2027-08-01');
    });

    test('refuses anything it cannot read confidently', () {
      // A wrong expiry on a medicine is worse than no expiry.
      expect(CsvInwardService.normalizeExpiry(''), isNull);
      expect(CsvInwardService.normalizeExpiry('NA'), isNull);
      expect(CsvInwardService.normalizeExpiry('soon'), isNull);
      expect(CsvInwardService.normalizeExpiry('45/13/2026'), isNull);
      expect(CsvInwardService.normalizeExpiry('13/2026'), isNull, reason: 'month 13');
    });
  });

  group('CSV parsing', () {
    const sheet = '''
Item Name,Quantity,Unit,Purchase Price,MRP,Selling Price,Category,Barcode,Expiry Date
Aashirvaad Atta 5kg,10,bag,210.00,265.00,250.00,Grocery,8901030012345,2026-11-30
Tata Salt 1kg,50,pkt,21.00,28.00,26.00,Spices,8904043901007,30/04/2027
''';

    test('reads barcode and expiry — the columns the parser used to ignore', () {
      final items = CsvInwardService.parseCsvContent(sheet);
      expect(items.length, 2);

      expect(items[0].barcode, '8901030012345',
          reason: 'without this, a bulk-imported product can never be scanned');
      expect(items[0].expiryDate, '2026-11-30');

      expect(items[1].barcode, '8904043901007');
      expect(items[1].expiryDate, '2027-04-30', reason: 'dd/MM/yyyy normalised');
    });

    test('money lands in integer paise', () {
      final items = CsvInwardService.parseCsvContent(sheet);
      expect(items[0].purchasePricePaise, 21000);
      expect(items[0].mrpPaise, 26500);
      expect(items[0].sellingPricePaise, 25000);
    });

    test('a missing price falls back to the SHARED markup, not a local copy', () {
      const noPrices = '''
Item Name,Quantity,Purchase Price
Loose Item,5,100.00
''';
      final items = CsvInwardService.parseCsvContent(noPrices);
      expect(items.single.sellingPricePaise,
          InventoryInwardService.defaultSellingPricePaise(10000));
      expect(items.single.mrpPaise, InventoryInwardService.defaultMrpPaise(10000));
    });

    test('a junk barcode is dropped rather than stored', () {
      const bad = '''
Item Name,Quantity,Barcode
Thing A,1,123
Thing B,1,NOT-A-BARCODE
Thing C,1,8901030012345
''';
      final items = CsvInwardService.parseCsvContent(bad);
      expect(items[0].barcode, isNull, reason: 'too short to be a real barcode');
      expect(items[1].barcode, isNull);
      expect(items[2].barcode, '8901030012345');
    });

    test('handles tab and semicolon separated exports', () {
      const tsv = 'Item Name\tQuantity\tPurchase Price\nParle-G\t12\t10.00';
      expect(CsvInwardService.parseCsvContent(tsv).single.productName, 'Parle-G');

      const ssv = 'Item Name;Quantity;Purchase Price\nMaggi;6;14.00';
      expect(CsvInwardService.parseCsvContent(ssv).single.productName, 'Maggi');
    });

    test('quoted names containing commas survive', () {
      const quoted = '''
Item Name,Quantity,Purchase Price
"Sharma & Sons, Special Mix",3,55.00
''';
      final items = CsvInwardService.parseCsvContent(quoted);
      expect(items.single.productName, 'Sharma & Sons, Special Mix');
      expect(items.single.quantity, 3);
    });

    test('blank and header-only files produce nothing, not a crash', () {
      expect(CsvInwardService.parseCsvContent(''), isEmpty);
      expect(CsvInwardService.parseCsvContent('Item Name,Quantity'), isEmpty);
    });
  });

  group('Generated template matches what the parser reads', () {
    test('every vertical template round-trips, barcodes and all', () {
      // The template and the parser drifting apart is what caused the original
      // bug: the template offered Barcode/Expiry columns the parser ignored.
      for (final vertical in ['grocery', 'pharmacy', 'restaurant', 'apparel']) {
        final csv = CsvInwardService.generateSampleInwardCsv(businessType: vertical);
        final items = CsvInwardService.parseCsvContent(csv);

        expect(items, isNotEmpty, reason: '$vertical template parsed to nothing');
        expect(items.every((i) => i.productName.trim().isNotEmpty), isTrue);
        expect(items.every((i) => i.purchasePricePaise > 0), isTrue,
            reason: '$vertical template should carry real costs');
        expect(items.every((i) => i.barcode != null && i.barcode!.isNotEmpty), isTrue,
            reason: '$vertical template has a Barcode column — it must be read back');
      }
    });

    test('pharmacy template carries usable expiry dates', () {
      final items = CsvInwardService.parseCsvContent(
        CsvInwardService.generateSampleInwardCsv(businessType: 'pharmacy'),
      );
      expect(items.every((i) => i.expiryDate != null), isTrue,
          reason: 'expiry drives FEFO and the Near Expiry radar');
    });
  });
}
