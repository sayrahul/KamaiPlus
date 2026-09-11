// Regression test for the reported bug: "kisi aur store type par dusre store type
// ke master sku wale product aa rahe he" — switching a store to a business vertical
// with few/zero products of its own would leak another vertical's tagged products
// into the catalog and POS grid.
//
// Root cause: `getAllProducts`/`getAllCategories` in local_database.dart fell back to
// querying every row in the table (no business_type filter at all) whenever the
// filtered query for the active vertical came back empty. Fixed to fall back only to
// genuinely unclassified rows (pre-dating the vertical feature), and to return an
// empty list — never another vertical's data — when a vertical has nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // A fresh, isolated on-disk db per test via the app's own user-switch path —
    // this exercises the real production code path, not a mock.
    await LocalDatabase.instance.switchUser('vertical_leak_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  test('switching to a vertical with its own seed catalog never shows another vertical\'s products', () async {
    // Simulate an existing Grocery store with grocery-tagged products already in the DB.
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_grocery_1',
      businessId: 'biz_test',
      name: 'Aashirvaad Atta 5kg',
      sellingPricePaise: 25000,
      mrpPaise: 26000,
      stockQuantity: 10,
      businessType: 'grocery',
    ));
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_clothing_1',
      businessId: 'biz_test',
      name: 'Cotton T-Shirt',
      sellingPricePaise: 39900,
      mrpPaise: 49900,
      stockQuantity: 5,
      businessType: 'clothing',
    ));

    // Merchant now switches the store to Hardware (has its own default seed catalog).
    final hardwareProducts = await LocalDatabase.instance.getAllProducts(businessType: 'hardware');

    expect(hardwareProducts, isNotEmpty, reason: 'hardware has a starter catalog and should auto-seed');
    for (final p in hardwareProducts) {
      expect(
        p.businessType == 'hardware' || p.businessType == 'both',
        isTrue,
        reason: 'Leaked a non-hardware product into the Hardware catalog: '
            '${p.name} (businessType=${p.businessType})',
      );
    }
    expect(
      hardwareProducts.any((p) => p.id == 'p_grocery_1' || p.id == 'p_clothing_1'),
      isFalse,
      reason: 'Grocery/Clothing products must never appear while browsing as a Hardware store',
    );
  });

  test('a vertical with no starter catalog shows an empty catalog, not every other vertical\'s products', () async {
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_grocery_2',
      businessId: 'biz_test',
      name: 'Tata Salt 1kg',
      sellingPricePaise: 2500,
      mrpPaise: 2800,
      stockQuantity: 20,
      businessType: 'grocery',
    ));

    // A niche/custom vertical that has no entry in kDefaultProductsByVertical.
    final result = await LocalDatabase.instance.getAllProducts(businessType: 'bespoke_jewellery');

    expect(
      result.any((p) => p.id == 'p_grocery_2'),
      isFalse,
      reason: 'An empty vertical must never fall back to showing every product in the store',
    );
  });

  test('legacy unclassified products (pre-dating the vertical feature) still show up', () async {
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_legacy_1',
      businessId: 'biz_test',
      name: 'Old Product Before Verticals Existed',
      sellingPricePaise: 10000,
      mrpPaise: 10000,
      stockQuantity: 3,
      businessType: '',
    ));

    final result = await LocalDatabase.instance.getAllProducts(businessType: 'bespoke_jewellery');

    expect(
      result.any((p) => p.id == 'p_legacy_1'),
      isTrue,
      reason: 'Unclassified legacy rows should still be visible as a backward-compatible fallback',
    );
  });

  test('category isolation matches product isolation', () async {
    await LocalDatabase.instance.upsertCategory(CategoryModel(
      id: 'c_grocery_1',
      businessId: 'biz_test',
      name: 'Grains',
      businessType: 'grocery',
    ));

    final result = await LocalDatabase.instance.getAllCategories(businessType: 'hardware');

    for (final c in result) {
      expect(
        c.businessType == 'hardware' || c.businessType == 'both',
        isTrue,
        reason: 'Leaked a non-hardware category: ${c.name} (businessType=${c.businessType})',
      );
    }
  });
}
