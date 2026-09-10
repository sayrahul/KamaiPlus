import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/core/constants/master_catalog_data.dart';
import 'package:kamaiplus_pos/core/constants/default_products.dart';

void main() {
  group('Business Vertical Isolation & Type Classification', () {
    test('ProductModel preserves businessType across toMap and fromMap', () {
      final pharmaProd = ProductModel(
        id: 'prod_test_pharma',
        businessId: 'biz_test',
        name: 'Dolo 650mg Tablets',
        sellingPricePaise: 3500,
        mrpPaise: 3500,
        stockQuantity: 100,
        businessType: 'pharmacy',
      );

      final map = pharmaProd.toMap();
      expect(map['business_type'], 'pharmacy');

      final restored = ProductModel.fromMap(map);
      expect(restored.businessType, 'pharmacy');
    });

    test('inferBusinessType correctly detects pharmacy products and categories', () {
      expect(inferBusinessType('Dolo 650mg Paracetamol', null), 'pharmacy');
      expect(inferBusinessType('Crocin Advance', null), 'pharmacy');
      expect(inferBusinessType('Cetirizine 10mg', null), 'pharmacy');
      expect(inferBusinessType('Cough Syrup Benadryl', null), 'pharmacy');
      expect(inferBusinessType('Betadine Ointment', null), 'pharmacy');
      expect(inferBusinessType('Paracetamol 500mg', null), 'pharmacy');

      // Grocery items
      expect(inferBusinessType('Aashirvaad Atta 5kg', null), 'grocery');
      expect(inferBusinessType('Fortune Sunflower Oil 1L', null), 'grocery');
      expect(inferBusinessType('Tata Salt 1kg', null), 'grocery');
      expect(inferBusinessType('Maggi Noodles 70g', null), 'grocery');
      expect(inferBusinessType('Parle-G Biscuits', null), 'grocery');

      // Clothing items
      expect(inferBusinessType('Cotton T-Shirt Size M', null), 'clothing');
      expect(inferBusinessType('Silk Saree Designer', null), 'clothing');

      // Hardware items
      expect(inferBusinessType('PVC Pipe 1 inch', null), 'hardware');
      expect(inferBusinessType('Stanley Screwdriver Set', null), 'hardware');
    });

    test('Master Catalog pharmacy items are strictly tagged as pharmacy', () {
      final pharmacyItems = kMasterCatalogSeed.where((m) => m.businessType == 'pharmacy').toList();
      expect(pharmacyItems.isNotEmpty, true);

      for (final m in pharmacyItems) {
        expect(m.businessType, 'pharmacy');
        final storeProd = m.toProductModel(businessId: 'test_biz');
        expect(storeProd.businessType, 'pharmacy', reason: 'Failed for ${m.name}');
      }
    });

    test('Default seeds by vertical are separated without mixing', () {
      final grocerySeeds = kDefaultProductsByVertical['grocery']!;
      final pharmaSeeds = kDefaultProductsByVertical['pharmacy']!;

      // Verify no pharmacy items in grocery seeds
      for (final g in grocerySeeds) {
        expect(g.name.toLowerCase().contains('dolo'), false);
        expect(g.name.toLowerCase().contains('paracetamol'), false);
        expect(g.name.toLowerCase().contains('cetirizine'), false);
        expect(g.name.toLowerCase().contains('syrup'), false);
        expect(g.name.toLowerCase().contains('ointment'), false);
      }

      // Verify pharmacy seeds are medical items
      expect(pharmaSeeds.any((p) => p.name.contains('Dolo')), true);
      expect(pharmaSeeds.any((p) => p.name.contains('Cetirizine')), true);
    });
  });
}
