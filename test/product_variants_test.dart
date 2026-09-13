import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabase.instance.switchUser('variants_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  test('Parent-Child Variant Matrix creation, querying, and barcode resolution', () async {
    final db = LocalDatabase.instance;

    // 1. Create Parent Product
    final parent = ProductModel(
      id: 'p_parent_shirt',
      businessId: 'biz_variant_test',
      name: 'Men Slim Fit Shirt',
      sellingPricePaise: 79900, // ₹799.00
      mrpPaise: 99900,
      stockQuantity: 0.0,
      hasVariants: true,
      businessType: 'clothing',
    );

    // 2. Create Matrix with Sizes S, M, L, XL
    final createdVariants = await db.createProductWithVariants(
      parentProduct: parent,
      variantLabels: ['S', 'M', 'L', 'XL'],
    );

    expect(createdVariants.length, 4);

    // 3. Fetch variants from SQLite
    final loadedVariants = await db.getVariantsForProduct('p_parent_shirt');
    expect(loadedVariants.length, 4);

    final labels = loadedVariants.map((v) => v.variantLabel).toList();
    expect(labels, containsAll(['S', 'M', 'L', 'XL']));

    for (final v in loadedVariants) {
      expect(v.parentId, 'p_parent_shirt');
      expect(v.isVariant, isTrue);
      expect(v.hasVariants, isFalse);
      expect(v.sellingPricePaise, 79900);
    }

    // 4. Assign unique barcode to variant M and verify barcode lookup
    final variantM = loadedVariants.firstWhere((v) => v.variantLabel == 'M');
    final updatedM = variantM.copyWith(barcode: '8901234567890', stockQuantity: 25.0);
    await db.upsertProduct(updatedM);

    final scannedProduct = await db.findProductByBarcode('8901234567890', businessType: 'clothing');
    expect(scannedProduct, isNotNull);
    expect(scannedProduct!.id, variantM.id);
    expect(scannedProduct.name, contains('(M)'));
    expect(scannedProduct.variantLabel, 'M');
    expect(scannedProduct.stockQuantity, 25.0);
  });
}
