// Tests for the Purchases & Restock screen finally having persistence.
//
// Audit finding: purchases_screen.dart did not import LocalDatabase at all.
// Orders lived in `final List<Map<String, dynamic>> _purchases = []` — widget
// state, initialised empty, never loaded from anywhere:
//
//   * creating an order called setState only, so it was gone on dispose;
//   * "Mark Inward Received" set purchase['status'] = 'Received' on that Map
//     and showed the toast "marked as Received into Stock!" while touching no
//     product row, no inventory movement and no supplier;
//   * ids came from 'PO-${1085 + _purchases.length}', which reused an id as
//     soon as any order was deleted.
//
// That is the literal mechanism behind "stock is added via Purchase/Restock,
// but after some time it gets deleted/reverts on its own": the write never
// happened, so a restart showed the truth.
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
        .switchUser('po_test_${DateTime.now().microsecondsSinceEpoch}');
    BusinessVerticals.activeBusinessTypeNotifier.value = 'grocery';
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
    BusinessVerticals.activeBusinessTypeNotifier.value = 'grocery';
  });

  PurchaseOrderModel order({
    required String id,
    String supplier = 'Sharma Wholesale',
    int amountPaise = 500000,
    String status = 'In-Transit',
    DateTime? stockAppliedAt,
    List<Map<String, dynamic>>? items,
  }) =>
      PurchaseOrderModel(
        id: id,
        businessId: 'biz_starter_pos',
        invoiceNo: 'INV-77',
        supplierName: supplier,
        amountPaise: amountPaise,
        duePaise: 0,
        status: status,
        itemsCount: items?.length ?? 1,
        items: items ??
            [
              {
                'name': 'Tata Salt 1kg',
                'qty': 24,
                'unit': 'pcs',
                'rate_paise': 2000,
                'total_paise': 48000,
              }
            ],
        orderDate: DateTime.now(),
        stockAppliedAt: stockAppliedAt,
      );

  test('an order survives being written and read back', () async {
    await LocalDatabase.instance.upsertPurchaseOrder(order(id: 'PO-1086'));

    final loaded = await LocalDatabase.instance.getAllPurchaseOrders();
    expect(loaded.length, 1);
    expect(loaded.first.id, 'PO-1086');
    expect(loaded.first.supplierName, 'Sharma Wholesale');
    expect(loaded.first.amountPaise, 500000);
    expect(loaded.first.items.length, 1,
        reason: 'line items must round-trip through items_json');
    expect(loaded.first.items.first['name'], 'Tata Salt 1kg');
    expect(loaded.first.hasStockBeenApplied, isFalse);
  });

  test('an order survives the app being closed and reopened', () async {
    await LocalDatabase.instance.upsertPurchaseOrder(order(id: 'PO-1086'));

    // The exact scenario the merchant reported: come back later, it's gone.
    await LocalDatabase.instance.reloadDatabase();

    final loaded = await LocalDatabase.instance.getAllPurchaseOrders();
    expect(loaded.length, 1, reason: 'the order must not vanish on relaunch');
    expect(loaded.first.id, 'PO-1086');
  });

  test('purchase order numbers never collide after a delete', () async {
    final first = await LocalDatabase.instance.getNextPurchaseOrderNumber();
    await LocalDatabase.instance.upsertPurchaseOrder(order(id: first));

    final second = await LocalDatabase.instance.getNextPurchaseOrderNumber();
    await LocalDatabase.instance.upsertPurchaseOrder(order(id: second));

    // Delete one, then allocate again — the old 'PO-${1085 + length}'
    // expression would hand back an id that is already in use.
    await LocalDatabase.instance.deletePurchaseOrder(second);
    final third = await LocalDatabase.instance.getNextPurchaseOrderNumber();

    expect(third, isNot(first));
    expect(third, isNot(second));

    await LocalDatabase.instance.upsertPurchaseOrder(order(id: third));
    final all = await LocalDatabase.instance.getAllPurchaseOrders();
    expect(all.length, 2, reason: 'nothing may have been silently overwritten');
  });

  test('deleting an order removes it for good', () async {
    await LocalDatabase.instance.upsertPurchaseOrder(order(id: 'PO-1086'));
    await LocalDatabase.instance.deletePurchaseOrder('PO-1086');
    await LocalDatabase.instance.reloadDatabase();

    expect(await LocalDatabase.instance.getAllPurchaseOrders(), isEmpty);
  });

  group('receiving an order into stock', () {
    test('creates the product and records the movement against the PO', () async {
      final po = order(id: 'PO-1086');
      await LocalDatabase.instance.upsertPurchaseOrder(po);

      await InventoryInwardService.applyInward(
        lines: [
          for (final raw in po.items)
            InwardLine(
              name: raw['name'] as String,
              quantity: (raw['qty'] as num).toDouble(),
              unit: raw['unit'] as String,
              purchasePricePaise: (raw['rate_paise'] as num).toInt(),
            ),
        ],
        supplierName: po.supplierName,
        referenceId: po.invoiceNo,
      );
      await LocalDatabase.instance.upsertPurchaseOrder(
        po.copyWith(status: 'Received', stockAppliedAt: DateTime.now()),
      );

      final products =
          await LocalDatabase.instance.getAllProducts(businessType: 'grocery');
      final salt = products.firstWhere((p) => p.name == 'Tata Salt 1kg');
      expect(salt.stockQuantity, 24,
          reason: '"Received into Stock" must actually add stock');

      final movements =
          await LocalDatabase.instance.getAllInventoryMovements(limit: 10);
      expect(movements.length, 1);
      expect(movements.first.referenceId, 'INV-77');

      final suppliers = await LocalDatabase.instance.getAllSuppliers();
      expect(suppliers.any((s) => s.name == 'Sharma Wholesale'), isTrue);

      final reloaded =
          await LocalDatabase.instance.getPurchaseOrderById('PO-1086');
      expect(reloaded!.hasStockBeenApplied, isTrue);
    });

    test('an already-received order is flagged so stock cannot be added twice',
        () async {
      final po = order(
        id: 'PO-1086',
        status: 'Received',
        stockAppliedAt: DateTime.now(),
      );
      await LocalDatabase.instance.upsertPurchaseOrder(po);

      final reloaded =
          await LocalDatabase.instance.getPurchaseOrderById('PO-1086');
      expect(reloaded!.hasStockBeenApplied, isTrue,
          reason: 'the screen checks this before inwarding, so a double tap or '
              're-entering the sheet cannot add the delivery twice');
    });

    test('receiving twice would double the stock without the guard', () async {
      // Documents exactly what the guard prevents.
      const line = InwardLine(
        name: 'Tata Salt 1kg',
        quantity: 24,
        purchasePricePaise: 2000,
      );
      await InventoryInwardService.applyInward(lines: [line]);

      final afterFirst =
          (await LocalDatabase.instance.getAllProducts(businessType: 'grocery'))
              .firstWhere((p) => p.name == 'Tata Salt 1kg');
      expect(afterFirst.stockQuantity, 24);

      await InventoryInwardService.applyInward(
        lines: [line.name == afterFirst.name
            ? InwardLine(
                name: line.name,
                quantity: line.quantity,
                purchasePricePaise: line.purchasePricePaise,
                matchedProduct: afterFirst,
              )
            : line],
      );

      final afterSecond =
          (await LocalDatabase.instance.getAllProducts(businessType: 'grocery'))
              .firstWhere((p) => p.name == 'Tata Salt 1kg');
      expect(afterSecond.stockQuantity, 48,
          reason: 'inward itself is additive by design — which is exactly why '
              'the PO needs stockAppliedAt to stop a repeat');
    });
  });
}
