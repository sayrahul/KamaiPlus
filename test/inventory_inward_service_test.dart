// Tests for the single shared inward path introduced by the September 2026
// audit, covering two bugs that each made freshly inwarded stock look like it
// had vanished:
//
//  1. bill_scan_review_sheet.dart created new products with a raw
//     ProductModel(...) that never passed businessType, so the constructor
//     default 'grocery' won. Products, Inventory, POS Billing, Home Pulse and
//     Expiry Radar all read getAllProducts(businessType:), so a
//     restaurant/pharmacy/clothing store simply could not see the stock it had
//     just scanned in. The identical mistake had already been found and fixed
//     in quick_stock_update_modal.dart and was never carried across.
//
//  2. every inward screen computed `matched.stockQuantity + qty` from a
//     ProductModel captured when the screen opened and then wrote the whole row
//     back with ConflictAlgorithm.replace. Inward happens while the shop is
//     open and billing, so a sale rung up in between was silently reverted.
//
// Driven against a real (in-memory FFI) SQLite database rather than a mock, in
// line with this project's existing test style — a mock can pass while the real
// read/write path is broken.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/constants/business_vertical_config.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/services/inventory_inward_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabase.instance
        .switchUser('inward_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
    BusinessVerticals.activeBusinessTypeNotifier.value = 'grocery';
  });

  ProductModel existing({
    String id = 'p_existing',
    double stock = 10,
    String businessType = 'restaurant',
    String name = 'Amul Butter 500g',
  }) =>
      ProductModel(
        id: id,
        businessId: 'biz_starter_pos',
        name: name,
        sellingPricePaise: 28000,
        mrpPaise: 30000,
        purchasePricePaise: 24000,
        stockQuantity: stock,
        unit: 'pcs',
        businessType: businessType,
      );

  group('new products carry the store vertical', () {
    test('a restaurant store can see the stock it just inwarded', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'restaurant';

      final result = await InventoryInwardService.applyInward(
        referenceId: 'BILL-1',
        lines: const [
          InwardLine(
            name: 'Paneer 1kg',
            quantity: 6,
            unit: 'kg',
            purchasePricePaise: 32000,
          ),
        ],
      );

      expect(result.createdCount, 1);

      final visible = await LocalDatabase.instance
          .getAllProducts(businessType: 'restaurant');
      final created = visible.firstWhere((p) => p.name == 'Paneer 1kg');
      expect(created.businessType, 'restaurant',
          reason: 'the constructor default grocery would hide this product');
      expect(created.stockQuantity, 6);

      final leaked =
          await LocalDatabase.instance.getAllProducts(businessType: 'grocery');
      expect(leaked.any((p) => p.name == 'Paneer 1kg'), isFalse,
          reason: 'and it must not leak into another vertical either');
    });

    test('markup is applied only when no explicit prices are given', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'grocery';

      await InventoryInwardService.applyInward(lines: const [
        InwardLine(name: 'Loose Rice', quantity: 10, purchasePricePaise: 10000),
        InwardLine(
          name: 'Priced Dal',
          quantity: 5,
          purchasePricePaise: 10000,
          sellingPricePaise: 13000,
          mrpPaise: 14000,
        ),
      ]);

      final all =
          await LocalDatabase.instance.getAllProducts(businessType: 'grocery');
      final rice = all.firstWhere((p) => p.name == 'Loose Rice');
      expect(rice.sellingPricePaise, 11500, reason: '1.15 x cost');
      expect(rice.mrpPaise, 12000, reason: '1.20 x cost');

      final dal = all.firstWhere((p) => p.name == 'Priced Dal');
      expect(dal.sellingPricePaise, 13000, reason: 'explicit price must win');
      expect(dal.mrpPaise, 14000);
    });
  });

  group('existing products increment relatively', () {
    test('a sale made while the inward sheet was open is not reverted', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'restaurant';
      final product = existing(stock: 10);
      await LocalDatabase.instance.upsertProduct(product);

      // The inward screen captured this ProductModel (stock 10) on open.
      final staleSnapshot = product;

      // Meanwhile the cashier sells 3 at the counter: stock is now 7.
      await LocalDatabase.instance.processPosBill(
        businessId: product.businessId,
        cartItems: [CartItemModel(product: product, quantity: 3)],
        paymentMethod: 'cash',
      );

      // Now the delivery of 5 is saved, using the STALE snapshot.
      await InventoryInwardService.applyInward(
        referenceId: 'BILL-2',
        lines: [
          InwardLine(
            name: staleSnapshot.name,
            quantity: 5,
            matchedProduct: staleSnapshot,
          ),
        ],
      );

      final reloaded = (await LocalDatabase.instance
              .getAllProducts(businessType: 'restaurant'))
          .firstWhere((p) => p.id == product.id);
      expect(reloaded.stockQuantity, 12,
          reason: '7 on the shelf + 5 delivered. Writing the stale 10 + 5 = 15 '
              'would silently un-sell the three units already sold.');
    });

    test('an unlimited (>= 99999) product keeps its sentinel', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'restaurant';
      final product = existing(id: 'p_unlimited', stock: 99999);
      await LocalDatabase.instance.upsertProduct(product);

      await InventoryInwardService.applyInward(lines: [
        InwardLine(name: product.name, quantity: 20, matchedProduct: product),
      ]);

      final reloaded = (await LocalDatabase.instance
              .getAllProducts(businessType: 'restaurant'))
          .firstWhere((p) => p.id == product.id);
      expect(reloaded.stockQuantity, 99999,
          reason: 'an uncounted item must not become a counted one');
    });

    test('prices update but the vertical tag is never touched', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'pharmacy';
      final product = existing(id: 'p_med', stock: 4, businessType: 'pharmacy');
      await LocalDatabase.instance.upsertProduct(product);

      await InventoryInwardService.applyInward(lines: [
        InwardLine(
          name: product.name,
          quantity: 10,
          matchedProduct: product,
          purchasePricePaise: 25000,
          sellingPricePaise: 29000,
        ),
      ]);

      final reloaded = (await LocalDatabase.instance
              .getAllProducts(businessType: 'pharmacy'))
          .firstWhere((p) => p.id == product.id);
      expect(reloaded.stockQuantity, 14);
      expect(reloaded.purchasePricePaise, 25000);
      expect(reloaded.sellingPricePaise, 29000);
      expect(reloaded.mrpPaise, 30000, reason: 'untouched fields must survive');
      expect(reloaded.businessType, 'pharmacy');
    });
  });

  group('audit trail and expiry', () {
    test('every inwarded line writes an inventory movement', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'grocery';
      final product = existing(id: 'p_move', stock: 2, businessType: 'grocery');
      await LocalDatabase.instance.upsertProduct(product);

      await InventoryInwardService.applyInward(
        referenceId: 'PO-2001',
        lines: [
          InwardLine(name: product.name, quantity: 8, matchedProduct: product),
          const InwardLine(name: 'Brand New Item', quantity: 3),
        ],
      );

      final movements =
          await LocalDatabase.instance.getAllInventoryMovements(limit: 50);
      expect(movements.length, 2);
      expect(movements.every((m) => m.movementType == 'PURCHASE'), isTrue);
      expect(movements.every((m) => m.referenceId == 'PO-2001'), isTrue);

      final onExisting = movements.firstWhere((m) => m.productId == product.id);
      expect(onExisting.previousStock, 2);
      expect(onExisting.newStock, 10);
    });

    test('a line with an expiry becomes a real FEFO batch the radar can see',
        () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'pharmacy';
      final soon = DateTime.now().add(const Duration(days: 25));
      final expiry =
          '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';

      await InventoryInwardService.applyInward(lines: [
        InwardLine(
          name: 'Amoxicillin 500mg',
          quantity: 30,
          unit: 'strip',
          purchasePricePaise: 4000,
          batchNumber: 'AMX-77',
          expiryDate: expiry,
        ),
      ]);

      final radar =
          await LocalDatabase.instance.getNearExpiryBatches('pharmacy');
      expect(
        radar.any((r) => r['product_name'] == 'Amoxicillin 500mg'),
        isTrue,
        reason: 'AI-scanned deliveries never reached product_batches before, so '
            'the Near Expiry radar was blind to them',
      );
    });

    test('blank and zero-quantity lines are skipped, not written', () async {
      BusinessVerticals.activeBusinessTypeNotifier.value = 'grocery';

      final result = await InventoryInwardService.applyInward(lines: const [
        InwardLine(name: '   ', quantity: 5),
        InwardLine(name: 'Zero Qty Item', quantity: 0),
        InwardLine(name: 'Real Item', quantity: 2, purchasePricePaise: 5000),
      ]);

      expect(result.skippedCount, 2);
      expect(result.createdCount, 1);

      final all =
          await LocalDatabase.instance.getAllProducts(businessType: 'grocery');
      expect(all.any((p) => p.name == 'Zero Qty Item'), isFalse);
      expect(all.any((p) => p.name == 'Real Item'), isTrue);
    });
  });
}
