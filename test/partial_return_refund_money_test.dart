// Regression tests for the money side of a partial sales return.
//
// User report: "transaction page par item return karte hain, item minus karta
// hu to amount only 0 dikhata hai. Ye wapas jahan the wahan jana chahiye —
// cash refund hua to wahan, store credit wahan."
//
// Root cause: three places valued a returned line by reading
// `it['price_paise'] ?? it['selling_price_paise']`. Neither key exists on a
// sale item — `CartItemModel.toMap()` writes `unit_price_paise` and
// `gross_total_paise` — so every modern bill valued every return at exactly
// ZERO:
//
//   * the return sheet showed "₹0.00" however many items were selected;
//   * `processPartialSalesReturn` recorded a ₹0 refund, so the cash branch
//     (`totalRefundPaise > 0`) never fired and no cash left the drawer;
//   * the credit branch subtracted 0, leaving the customer's khata untouched
//     while writing a ₹0 "Store Credit" line into their statement;
//   * `SaleModel.totalRefundedPaise` stayed 0, so reports kept counting the
//     returned goods as full revenue.
//
// Stock still came back on the shelf, which is what made it look like the
// return had worked.
//
// Valuation now lives in one place — `SaleModel.lineEffectivePaidPaise` /
// `refundPaiseForItem` — used by both the sheet and the database.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabase.instance
        .switchUser('partial_return_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  ProductModel product({
    required String id,
    required int sellPaise,
    int costPaise = 0,
    double taxRate = 0,
    bool taxInclusive = true,
    double stock = 50,
  }) =>
      ProductModel(
        id: id,
        businessId: 'biz_ret',
        name: 'Item $id',
        sellingPricePaise: sellPaise,
        mrpPaise: sellPaise,
        purchasePricePaise: costPaise,
        stockQuantity: stock,
        taxRate: taxRate,
        isTaxInclusive: taxInclusive,
      );

  Future<SaleModel> bill(
    List<CartItemModel> items, {
    String method = 'cash',
    CustomerModel? customer,
    int discountPaise = 0,
  }) =>
      LocalDatabase.instance.processPosBill(
        businessId: 'biz_ret',
        cartItems: items,
        paymentMethod: method,
        customer: customer,
        discountPaise: discountPaise,
      );

  group('Valuing a returned line (the ₹0 bug)', () {
    test('a modern sale item values at its real price, not zero', () async {
      // ₹100 × 2 = ₹200 bill.
      final sale = await bill([
        CartItemModel(product: product(id: 'p1', sellPaise: 10000), quantity: 2),
      ]);

      expect(sale.refundPaiseForItem(0, 1), 10000, reason: 'one of two units = ₹100');
      expect(sale.refundPaiseForItem(0, 2), 20000, reason: 'both units = ₹200');
      expect(sale.refundPaiseForItem(0, 1), isNot(0), reason: 'the exact reported bug');
    });

    test('returning everything adds up to what the customer actually paid', () async {
      final sale = await bill([
        CartItemModel(product: product(id: 'a', sellPaise: 12500), quantity: 3),
        CartItemModel(product: product(id: 'b', sellPaise: 4900), quantity: 1),
      ]);

      var total = 0;
      for (var i = 0; i < sale.items.length; i++) {
        total += sale.refundPaiseForItem(i, (sale.items[i]['quantity'] as num));
      }
      expect(total, sale.totalAmountPaise);
    });

    test('a bill discount is apportioned — never refund more than was taken', () async {
      // ₹200 of goods, ₹50 off the bill → customer paid ₹150.
      final sale = await bill([
        CartItemModel(product: product(id: 'd1', sellPaise: 10000), quantity: 2),
      ], discountPaise: 5000);

      expect(sale.totalAmountPaise, 15000);
      expect(sale.refundPaiseForItem(0, 2), 15000,
          reason: 'full return = ₹150 paid, not the ₹200 list value');
      expect(sale.refundPaiseForItem(0, 1), 7500);
    });

    test('tax-exclusive items refund the tax the customer paid too', () async {
      // ₹100 + 18% GST charged on top → customer paid ₹118.
      final sale = await bill([
        CartItemModel(
          product: product(id: 'gst', sellPaise: 10000, taxRate: 18, taxInclusive: false),
          quantity: 1,
        ),
      ]);

      expect(sale.totalAmountPaise, 11800);
      expect(sale.refundPaiseForItem(0, 1), 11800,
          reason: 'refunding only the ₹100 base would short-change the customer');
    });

    test('a fractional (loose) quantity prorates', () async {
      // 2 kg at ₹80/kg; customer brings back half a kg.
      final sale = await bill([
        CartItemModel(product: product(id: 'loose', sellPaise: 8000), quantity: 2),
      ]);
      expect(sale.refundPaiseForItem(0, 0.5), 4000);
    });

    test('zero / out-of-range asks return zero, not a crash', () async {
      final sale = await bill([
        CartItemModel(product: product(id: 'z', sellPaise: 5000), quantity: 1),
      ]);
      expect(sale.refundPaiseForItem(0, 0), 0);
      expect(sale.refundPaiseForItem(0, -3), 0);
      expect(sale.refundPaiseForItem(99, 1), 0);
      expect(sale.lineEffectivePaidPaise(-1), 0);
    });
  });

  group('Where the money actually goes', () {
    test('CASH refund takes the money out of the drawer', () async {
      final sale = await bill([
        CartItemModel(product: product(id: 'c1', sellPaise: 10000), quantity: 2),
      ]);

      final before = (await LocalDatabase.instance.getAllExpenses())
          .fold<int>(0, (s, e) => s + e.amountPaise);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'c1', 'product_name': 'Item c1', 'return_quantity': 1},
        ],
        refundMethod: 'cash',
      );

      final expenses = await LocalDatabase.instance.getAllExpenses();
      final after = expenses.fold<int>(0, (s, e) => s + e.amountPaise);

      // The cash register screen computes expected cash as
      // opening + cashSales - expenses, so this row IS the drawer movement.
      expect(after - before, 10000, reason: '₹100 must leave the drawer');
      expect(expenses.any((e) => e.category == 'Refund'), isTrue);
    });

    test('CREDIT refund reduces the customer\'s udhar', () async {
      final customer = CustomerModel(
        id: 'cust_ret_1',
        businessId: 'biz_ret',
        name: 'Ramesh',
        phone: '9000000001',
      );
      await LocalDatabase.instance.upsertCustomer(customer);

      final sale = await bill([
        CartItemModel(product: product(id: 'u1', sellPaise: 30000), quantity: 1),
      ], method: 'credit', customer: customer);

      final owedBefore =
          (await LocalDatabase.instance.getAllCustomers()).firstWhere((c) => c.id == customer.id);
      expect(owedBefore.currentBalancePaise, 30000, reason: 'udhar was taken');

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'u1', 'product_name': 'Item u1', 'return_quantity': 1},
        ],
        refundMethod: 'credit',
        customerId: customer.id,
      );

      final owedAfter =
          (await LocalDatabase.instance.getAllCustomers()).firstWhere((c) => c.id == customer.id);
      expect(owedAfter.currentBalancePaise, 0, reason: 'the whole udhar is reversed');

      final ledger = await LocalDatabase.instance.getLedgerForCustomer(customer.id);
      expect(ledger.any((l) => l.amountPaise == 30000), isTrue);
    });

    test('STORE CREDIT leaves the customer in advance (jama), not at zero', () async {
      final customer = CustomerModel(
        id: 'cust_ret_2',
        businessId: 'biz_ret',
        name: 'Sita',
        phone: '9000000002',
      );
      await LocalDatabase.instance.upsertCustomer(customer);

      // Paid in cash, so there is no udhar to reverse — the refund becomes
      // money the shop now owes them. A negative balance is that advance.
      final sale = await bill([
        CartItemModel(product: product(id: 'sc1', sellPaise: 25000), quantity: 1),
      ], customer: customer);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'sc1', 'product_name': 'Item sc1', 'return_quantity': 1},
        ],
        refundMethod: 'credit_note',
        customerId: customer.id,
      );

      final after =
          (await LocalDatabase.instance.getAllCustomers()).firstWhere((c) => c.id == customer.id);
      expect(after.currentBalancePaise, -25000,
          reason: 'negative balance = shop owes the customer ₹250');
    });

    test('a cash refund does NOT touch any customer balance', () async {
      final customer = CustomerModel(
        id: 'cust_ret_3',
        businessId: 'biz_ret',
        name: 'Mohan',
        phone: '9000000003',
      );
      await LocalDatabase.instance.upsertCustomer(customer);

      final sale = await bill([
        CartItemModel(product: product(id: 'x1', sellPaise: 9000), quantity: 1),
      ], customer: customer);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'x1', 'product_name': 'Item x1', 'return_quantity': 1},
        ],
        refundMethod: 'cash',
        customerId: customer.id,
      );

      final after =
          (await LocalDatabase.instance.getAllCustomers()).firstWhere((c) => c.id == customer.id);
      expect(after.currentBalancePaise, 0, reason: 'cash went back in hand, not to khata');
    });
  });

  group('Safety rails', () {
    test('the returned stock still comes back on the shelf', () async {
      // Unlike the money tests above, this one reads the products table back,
      // so the row has to actually exist — processPosBill only decrements an
      // existing row, it does not create one.
      final p = product(id: 's1', sellPaise: 5000, stock: 10);
      await LocalDatabase.instance.upsertProduct(p);

      final sale = await bill([
        CartItemModel(product: p, quantity: 3),
      ]);

      final afterSale = (await LocalDatabase.instance.getAllProducts())
          .firstWhere((p) => p.id == 's1');
      expect(afterSale.stockQuantity, 7);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 's1', 'product_name': 'Item s1', 'return_quantity': 2},
        ],
        refundMethod: 'cash',
      );

      final afterReturn = (await LocalDatabase.instance.getAllProducts())
          .firstWhere((p) => p.id == 's1');
      expect(afterReturn.stockQuantity, 9);
    });

    test('two partial returns never refund more than the bill was worth', () async {
      final sale = await bill([
        CartItemModel(product: product(id: 'm1', sellPaise: 10000), quantity: 2),
      ]);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'm1', 'product_name': 'Item m1', 'return_quantity': 1},
        ],
        refundMethod: 'cash',
      );

      // Re-read so the second return sees the first one's returned_quantity.
      final reloaded = (await LocalDatabase.instance.getAllSales())
          .firstWhere((s) => s.id == sale.id);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: reloaded,
        returnItems: [
          {'item_index': 0, 'product_id': 'm1', 'product_name': 'Item m1', 'return_quantity': 1},
        ],
        refundMethod: 'cash',
      );

      final totalRefunded = (await LocalDatabase.instance.getAllExpenses())
          .where((e) => e.category == 'Refund')
          .fold<int>(0, (s, e) => s + e.amountPaise);
      expect(totalRefunded, 20000, reason: 'exactly the bill total, never more');

      final finalSale = (await LocalDatabase.instance.getAllSales())
          .firstWhere((s) => s.id == sale.id);
      expect(finalSale.isRefunded, isTrue, reason: 'everything is now back');
      expect(finalSale.netAmountPaise, 0);
    });

    test('a zero-value return writes no ledger noise into the khata', () async {
      final customer = CustomerModel(
        id: 'cust_ret_4',
        businessId: 'biz_ret',
        name: 'Geeta',
        phone: '9000000004',
      );
      await LocalDatabase.instance.upsertCustomer(customer);

      final sale = await bill([
        CartItemModel(product: product(id: 'n1', sellPaise: 7000), quantity: 1),
      ], customer: customer);

      // Nothing actually selected.
      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'n1', 'product_name': 'Item n1', 'return_quantity': 0},
        ],
        refundMethod: 'credit_note',
        customerId: customer.id,
      );

      final ledger = await LocalDatabase.instance.getLedgerForCustomer(customer.id);
      expect(ledger.any((l) => l.amountPaise == 0), isFalse,
          reason: 'a ₹0 "Store Credit" line reads as if something went through');
    });

    test('reports stop counting returned goods as revenue', () async {
      final sale = await bill([
        CartItemModel(product: product(id: 'r1', sellPaise: 10000), quantity: 2),
      ]);
      expect(sale.netAmountPaise, 20000);

      await LocalDatabase.instance.processPartialSalesReturn(
        sale: sale,
        returnItems: [
          {'item_index': 0, 'product_id': 'r1', 'product_name': 'Item r1', 'return_quantity': 1},
        ],
        refundMethod: 'cash',
      );

      final reloaded = (await LocalDatabase.instance.getAllSales())
          .firstWhere((s) => s.id == sale.id);
      expect(reloaded.isPartiallyRefunded, isTrue);
      expect(reloaded.totalRefundedPaise, 10000);
      expect(reloaded.netAmountPaise, 10000, reason: 'half the bill is no longer revenue');
    });
  });
}
