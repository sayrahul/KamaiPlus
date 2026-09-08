import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/services/csv_inward_service.dart';
import 'package:kamaiplus_pos/services/gemini_ai_service.dart';

void main() {
  group('CSV Inward Parser Tests', () {
    test('Parses standard CSV with item name, qty, and prices correctly', () {
      const csv = '''
Item Name,Quantity,Unit,Purchase Price,Selling Price,MRP,Category
Fortune Sunlite Oil 1L,24,packet,115.50,135.00,145.00,Groceries
Aashirvaad Atta 10kg,10,bag,370,410,430,Atta & Dal
Tata Salt 1kg,50,pkt,22,28,28,Spices
''';

      final items = CsvInwardService.parseCsvContent(csv);

      expect(items.length, 3);

      expect(items[0].productName, 'Fortune Sunlite Oil 1L');
      expect(items[0].quantity, 24.0);
      expect(items[0].unit, 'packet');
      expect(items[0].purchasePricePaise, 11550); // ₹115.50 -> 11550 paise
      expect(items[0].sellingPricePaise, 13500);  // ₹135.00 -> 13500 paise
      expect(items[0].mrpPaise, 14500);           // ₹145.00 -> 14500 paise

      expect(items[1].productName, 'Aashirvaad Atta 10kg');
      expect(items[1].quantity, 10.0);
      expect(items[1].purchasePricePaise, 37000); // ₹370 -> 37000 paise

      expect(items[2].productName, 'Tata Salt 1kg');
      expect(items[2].quantity, 50.0);
      expect(items[2].purchasePricePaise, 2200);   // ₹22 -> 2200 paise
    });

    test('Parses semicolon-separated CSV correctly', () {
      const csv = '''
Description;Qty;Buy Rate;Sale Rate
Maggi 2-Minute Noodles;48;12.50;14.00
Parle-G 250g;60;25.00;30.00
''';

      final items = CsvInwardService.parseCsvContent(csv);

      expect(items.length, 2);
      expect(items[0].productName, 'Maggi 2-Minute Noodles');
      expect(items[0].quantity, 48.0);
      expect(items[0].purchasePricePaise, 1250);
      expect(items[0].sellingPricePaise, 1400);

      expect(items[1].productName, 'Parle-G 250g');
      expect(items[1].quantity, 60.0);
      expect(items[1].purchasePricePaise, 2500);
      expect(items[1].sellingPricePaise, 3000);
    });

    test('Handles empty or invalid CSV gracefully', () {
      expect(CsvInwardService.parseCsvContent(''), isEmpty);
      expect(CsvInwardService.parseCsvContent('Only Header Row,No Data'), isEmpty);
    });
  });

  group('ExtractedBillItem Model Tests', () {
    test('Correctly parses rupee strings with currency symbols and decimals', () {
      final json = {
        'product_name': 'Surf Excel Quick Wash 1kg',
        'quantity': 15,
        'unit': 'kg',
        'purchase_price': '₹128.50',
        'selling_price': '145',
        'mrp': '155.00',
      };

      final item = ExtractedBillItem.fromJson(json);

      expect(item.productName, 'Surf Excel Quick Wash 1kg');
      expect(item.quantity, 15.0);
      expect(item.unit, 'kg');
      expect(item.purchasePricePaise, 12850);
      expect(item.sellingPricePaise, 14500);
      expect(item.mrpPaise, 15500);
    });
  });
}
