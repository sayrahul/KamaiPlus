import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/core/constants/master_catalog_data.dart';

void main() {
  group('Crossover Goods & Cloud Barcode Resolution Logic', () {
    test('Crossover items sold in both Kirana and Medical store are tagged as "both"', () {
      // Health, hygiene & OTC items available in both retail stores
      expect(inferBusinessType('Dettol Original Bathing Soap 125g', 'Soaps'), 'both');
      expect(inferBusinessType('Savlon Antiseptic Liquid 100ml', 'First Aid'), 'both');
      expect(inferBusinessType('Lifebuoy Total Soap Bar 125g', 'Personal Care'), 'both');
      expect(inferBusinessType('Vicks VapoRub 25ml', 'Cold Relief'), 'both');
      expect(inferBusinessType('Moov Pain Relief Cream 50g', 'Pain Relief'), 'both');
      expect(inferBusinessType('Volini Pain Relief Gel 30g', 'Pain Relief'), 'both');
      expect(inferBusinessType('Band-Aid Washproof Medicated Strips', 'First Aid'), 'both');
      expect(inferBusinessType('Eno Regular Fruit Salt Lemon 100g', 'Digestive'), 'both');
      expect(inferBusinessType('Dabur Pudin Hara Pearls (Strip of 10)', 'Digestive'), 'both');
      expect(inferBusinessType('Strepsils Honey & Lemon Lozenges', 'Throat Lozenges'), 'both');
      expect(inferBusinessType('Colgate Strong Teeth Toothpaste 100g', 'Oral Care'), 'both');
      expect(inferBusinessType('Sensodyne Rapid Relief Toothpaste 80g', 'Oral Care'), 'both');
      expect(inferBusinessType('Horlicks Classic Malt Refill 500g', 'Health Food Drink'), 'both');
      expect(inferBusinessType('Glucon-D Instant Energy Drink Tangy Orange 450g', 'Energy Drink'), 'both');
      expect(inferBusinessType('Pampers All Round Protection Baby Diaper', 'Baby Care'), 'both');
    });

    test('Strict vertical isolation: Pure medicines NEVER become grocery or both', () {
      expect(inferBusinessType('Dolo 650mg Paracetamol Tablets', 'Tablets'), 'pharmacy');
      expect(inferBusinessType('Crocin Advance 500mg', 'Tablets'), 'pharmacy');
      expect(inferBusinessType('Cetirizine 10mg Tablets (Strip of 10)', 'Anti-Allergy'), 'pharmacy');
      expect(inferBusinessType('Benadryl Cough Formula Syrup 100ml', 'Cough Syrup'), 'pharmacy');
      expect(inferBusinessType('Azithromycin 500mg (Strip of 3)', 'Antibiotic'), 'pharmacy');
      expect(inferBusinessType('Pantoprazole 40mg Gastro-Resistant Tablets', 'Antacid'), 'pharmacy');
    });

    test('Strict vertical isolation: Pure grocery NEVER becomes pharmacy or both', () {
      expect(inferBusinessType('Aashirvaad Shudh Chakki Atta (5kg)', 'Flour'), 'grocery');
      expect(inferBusinessType('Fortune Sunlite Sunflower Oil (1L)', 'Edible Oil'), 'grocery');
      expect(inferBusinessType('Tata Salt Vacuum Evaporated (1kg)', 'Salt'), 'grocery');
      expect(inferBusinessType('Maggi 2-Minute Masala Noodles (70g)', 'Instant Noodles'), 'grocery');
      expect(inferBusinessType('Parle-G Gold Glucose Biscuits (1kg)', 'Biscuits'), 'grocery');
    });

    test('Master Catalog seed contains verified crossover items with "both"', () {
      final dettolItems = kMasterCatalogSeed.where((m) => m.name.toLowerCase().contains('dettol')).toList();
      expect(dettolItems.isNotEmpty, true);
      for (final item in dettolItems) {
        expect(item.businessType, 'both', reason: '${item.name} should be both');
      }

      final vicksItems = kMasterCatalogSeed.where((m) => m.name.toLowerCase().contains('vicks')).toList();
      expect(vicksItems.isNotEmpty, true);
      for (final item in vicksItems) {
        expect(item.businessType, 'both', reason: '${item.name} should be both');
      }

      final enoItems = kMasterCatalogSeed.where((m) => m.name.toLowerCase().contains('eno')).toList();
      expect(enoItems.isNotEmpty, true);
      for (final item in enoItems) {
        expect(item.businessType, 'both', reason: '${item.name} should be both');
      }
    });

    test('MasterProductModel toProductModel maintains businessType "both" correctly', () {
      const masterCrossover = MasterProductModel(
        barcode: '8901396317524',
        name: 'Dettol Original Bathing Soap (125g)',
        category: 'Personal Care',
        mrpPaise: 6800,
        sellingPricePaise: 6500,
        businessType: 'both',
      );

      final storeProduct = masterCrossover.toProductModel(businessId: 'biz_sample');
      expect(storeProduct.businessType, 'both');
    });
  });
}
