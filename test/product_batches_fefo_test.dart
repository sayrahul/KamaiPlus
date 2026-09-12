// Tests for real multi-batch FEFO (First-Expiry-First-Out), added
// 2026-09-12 as the "Pharmacy — Real FEFO" item from the KamaiPlus Playbook.
// Drives LocalDatabase through a real (in-memory FFI) SQLite database and
// asserts on what addProductBatch/getBatchesForProduct/processPosBill
// actually do — not a mock — matching this project's own established
// pattern (see vertical_product_leak_test.dart's header comment) for why
// that matters: a mock can pass while the real read/write path is broken.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

ProductModel _pharmacyProduct({
  String id = 'p_med_1',
  double stockQuantity = 0,
  String? expiryDate,
  String? batchNumber,
}) =>
    ProductModel(
      id: id,
      businessId: 'biz_test',
      name: 'Paracetamol 500mg',
      sellingPricePaise: 2000,
      mrpPaise: 2500,
      stockQuantity: stockQuantity,
      businessType: 'pharmacy',
      unit: 'strip',
      expiryDate: expiryDate,
      batchNumber: batchNumber,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabase.instance.switchUser('fefo_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  group('addProductBatch', () {
    test('creates a batch without touching the caller-owned stock_quantity', () async {
      final product = _pharmacyProduct(stockQuantity: 50);
      await LocalDatabase.instance.upsertProduct(product);

      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'batch_1',
        productId: product.id,
        businessId: product.businessId,
        quantity: 20,
        expiryDate: '2027-01-01',
        createdAt: DateTime.now(),
      ));

      final reloaded = (await LocalDatabase.instance.getAllProducts(businessType: 'pharmacy'))
          .firstWhere((p) => p.id == product.id);
      // addProductBatch never changes stock_quantity — that stays whatever
      // upsertProduct already set it to (the same responsibility split as
      // before this feature existed).
      expect(reloaded.stockQuantity, 50);
    });

    test('refreshes the product\'s denormalized expiry_date/batch_number to the soonest batch', () async {
      final product = _pharmacyProduct(stockQuantity: 100);
      await LocalDatabase.instance.upsertProduct(product);

      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'batch_far',
        productId: product.id,
        businessId: product.businessId,
        batchNumber: 'FAR001',
        quantity: 60,
        expiryDate: '2028-06-01',
        createdAt: DateTime.now(),
      ));
      var reloaded = (await LocalDatabase.instance.getAllProducts(businessType: 'pharmacy')).first;
      expect(reloaded.expiryDate, '2028-06-01');

      // A SECOND, sooner-expiring batch arrives — the denormalized summary
      // must now point at THIS one, not stay on the first.
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'batch_soon',
        productId: product.id,
        businessId: product.businessId,
        batchNumber: 'SOON001',
        quantity: 40,
        expiryDate: '2027-01-01',
        createdAt: DateTime.now(),
      ));
      reloaded = (await LocalDatabase.instance.getAllProducts(businessType: 'pharmacy')).first;
      expect(reloaded.expiryDate, '2027-01-01');
      expect(reloaded.batchNumber, 'SOON001');
    });
  });

  group('getBatchesForProduct', () {
    test('sorts soonest-expiring first, with unknown-expiry batches last', () async {
      final product = _pharmacyProduct(stockQuantity: 100);
      await LocalDatabase.instance.upsertProduct(product);

      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_no_expiry',
        productId: product.id,
        businessId: product.businessId,
        quantity: 10,
        createdAt: DateTime.now(),
      ));
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_2028',
        productId: product.id,
        businessId: product.businessId,
        quantity: 10,
        expiryDate: '2028-01-01',
        createdAt: DateTime.now(),
      ));
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_2027',
        productId: product.id,
        businessId: product.businessId,
        quantity: 10,
        expiryDate: '2027-01-01',
        createdAt: DateTime.now(),
      ));

      final batches = await LocalDatabase.instance.getBatchesForProduct(product.id);
      expect(batches.map((b) => b.id).toList(), ['b_2027', 'b_2028', 'b_no_expiry']);
    });
  });

  group('processPosBill FEFO deduction', () {
    test('a sale deducts from the soonest-expiring batch first', () async {
      final product = _pharmacyProduct(stockQuantity: 30);
      await LocalDatabase.instance.upsertProduct(product);
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_soon',
        productId: product.id,
        businessId: product.businessId,
        batchNumber: 'SOON',
        quantity: 10,
        expiryDate: '2027-01-01',
        createdAt: DateTime.now(),
      ));
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_later',
        productId: product.id,
        businessId: product.businessId,
        batchNumber: 'LATER',
        quantity: 20,
        expiryDate: '2028-01-01',
        createdAt: DateTime.now(),
      ));

      // Sell 4 units — should come entirely out of the SOON batch, leaving
      // it at 6, and LATER untouched at 20.
      await LocalDatabase.instance.processPosBill(
        businessId: product.businessId,
        cartItems: [CartItemModel(product: product, quantity: 4)],
        paymentMethod: 'cash',
      );

      final batches = await LocalDatabase.instance.getBatchesForProduct(product.id);
      final soon = batches.firstWhere((b) => b.id == 'b_soon');
      final later = batches.firstWhere((b) => b.id == 'b_later');
      expect(soon.quantity, 6);
      expect(later.quantity, 20);
    });

    test('a sale bigger than the soonest batch cascades into the next one', () async {
      final product = _pharmacyProduct(stockQuantity: 30);
      await LocalDatabase.instance.upsertProduct(product);
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_soon',
        productId: product.id,
        businessId: product.businessId,
        quantity: 10,
        expiryDate: '2027-01-01',
        createdAt: DateTime.now(),
      ));
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b_later',
        productId: product.id,
        businessId: product.businessId,
        quantity: 20,
        expiryDate: '2028-01-01',
        createdAt: DateTime.now(),
      ));

      // Sell 15 — exhausts the 10-unit SOON batch entirely (deleted, since
      // it hits zero) and takes 5 more from LATER, leaving it at 15.
      await LocalDatabase.instance.processPosBill(
        businessId: product.businessId,
        cartItems: [CartItemModel(product: product, quantity: 15)],
        paymentMethod: 'cash',
      );

      final batches = await LocalDatabase.instance.getBatchesForProduct(product.id);
      expect(batches.length, 1, reason: 'the fully-depleted SOON batch should be gone, not left at zero');
      expect(batches.first.id, 'b_later');
      expect(batches.first.quantity, 15);
    });

    test('still correctly deducts the aggregate stock_quantity, same as before this feature', () async {
      final product = _pharmacyProduct(stockQuantity: 30);
      await LocalDatabase.instance.upsertProduct(product);
      await LocalDatabase.instance.addProductBatch(ProductBatchModel(
        id: 'b1',
        productId: product.id,
        businessId: product.businessId,
        quantity: 30,
        expiryDate: '2027-01-01',
        createdAt: DateTime.now(),
      ));

      await LocalDatabase.instance.processPosBill(
        businessId: product.businessId,
        cartItems: [CartItemModel(product: product, quantity: 12)],
        paymentMethod: 'cash',
      );

      final reloaded = (await LocalDatabase.instance.getAllProducts(businessType: 'pharmacy')).first;
      expect(reloaded.stockQuantity, 18);
    });

    test('a product with no batches at all is completely unaffected — every non-pharmacy sale keeps working exactly as before', () async {
      final product = ProductModel(
        id: 'p_grocery',
        businessId: 'biz_test',
        name: 'Rice 5kg',
        sellingPricePaise: 40000,
        mrpPaise: 45000,
        stockQuantity: 20,
        businessType: 'grocery',
      );
      await LocalDatabase.instance.upsertProduct(product);

      // Must not throw, and must still deduct the aggregate normally, even
      // though no product_batches row exists for this product at all.
      await LocalDatabase.instance.processPosBill(
        businessId: product.businessId,
        cartItems: [CartItemModel(product: product, quantity: 5)],
        paymentMethod: 'cash',
      );

      final reloaded = (await LocalDatabase.instance.getAllProducts(businessType: 'grocery'))
          .firstWhere((p) => p.id == product.id);
      expect(reloaded.stockQuantity, 15);
      expect(await LocalDatabase.instance.getBatchesForProduct(product.id), isEmpty);
    });
  });
}
