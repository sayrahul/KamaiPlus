// Regression test for the Home dashboard's "EST. PROFIT" card.
//
// It used to be computed as `todaySalesPaise * 0.14` — a hardcoded 14% of
// turnover, in home_pulse_tab.dart, presented as "Live Margin" behind an owner
// privacy PIN. It never read a cost price, so a day of loss-leaders and a day
// of high-margin goods reported the identical "profit", and the PIN gate made
// the number look more authoritative than it was.
//
// Profit is now computed line by line from the buying rate frozen onto each
// sale item at billing time. These tests pin that, plus the two decisions that
// keep it honest:
//   - lines with no known cost are EXCLUDED, not counted as 100% profit;
//   - expenses are subtracted.
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
        .switchUser('profit_math_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  /// Bills [items] through the real POS path so the test exercises the same
  /// code a cashier does, not a hand-written sales row.
  Future<SaleModel> bill(List<CartItemModel> items) {
    return LocalDatabase.instance.processPosBill(
      businessId: 'biz_profit_test',
      cartItems: items,
      paymentMethod: 'cash',
    );
  }

  ProductModel product({
    required String id,
    required int sellPaise,
    required int costPaise,
  }) {
    return ProductModel(
      id: id,
      businessId: 'biz_profit_test',
      name: 'Item $id',
      sellingPricePaise: sellPaise,
      mrpPaise: sellPaise,
      purchasePricePaise: costPaise,
      stockQuantity: 100,
    );
  }

  test('profit is revenue minus real cost of goods, not a fixed % of turnover', () async {
    // ₹100 sold, ₹60 cost → ₹40 margin. A flat 14% rule would have said ₹14.
    await bill([
      CartItemModel(product: product(id: 'p1', sellPaise: 10000, costPaise: 6000)),
    ]);

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    expect(summary.grossMarginPaise, 4000);
    expect(summary.netProfitPaise, 4000);
    expect(summary.isPartial, isFalse);
  });

  test('two items with different margins do not collapse to one flat rate', () async {
    // Loss-leader: ₹50 sold at ₹48 cost → ₹2.
    // High margin:  ₹50 sold at ₹10 cost → ₹40.
    await bill([
      CartItemModel(product: product(id: 'loss', sellPaise: 5000, costPaise: 4800)),
      CartItemModel(product: product(id: 'high', sellPaise: 5000, costPaise: 1000)),
    ]);

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    expect(summary.grossMarginPaise, 4200);
    // The old rule would have reported 14% of ₹100 = ₹14 for this exact basket.
    expect(summary.grossMarginPaise, isNot(1400));
  });

  test('quantity is multiplied into the cost, not just the price', () async {
    await bill([
      CartItemModel(
        product: product(id: 'q', sellPaise: 2000, costPaise: 1500),
        quantity: 4,
      ),
    ]);

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    // 4 × (₹20 − ₹15) = ₹20
    expect(summary.grossMarginPaise, 2000);
  });

  test('a line with no known cost is excluded, never counted as pure profit', () async {
    // The dangerous direction: treating cost 0 as "free stock" would report the
    // whole ₹500 as margin on an item the shop actually paid for.
    await bill([
      CartItemModel(product: product(id: 'costed', sellPaise: 10000, costPaise: 6000)),
      CartItemModel(product: product(id: 'uncosted', sellPaise: 50000, costPaise: 0)),
    ]);

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    expect(summary.grossMarginPaise, 4000, reason: 'only the costed line contributes');
    expect(summary.uncostedLineCount, 1);
    expect(summary.uncostedRevenuePaise, 50000);
    expect(summary.isPartial, isTrue);
    expect(summary.costCoverage, closeTo(10000 / 60000, 0.0001));
  });

  test('a fully uncosted day reports zero margin, not the full turnover', () async {
    await bill([
      CartItemModel(product: product(id: 'u1', sellPaise: 25000, costPaise: 0)),
    ]);

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    expect(summary.grossMarginPaise, 0);
    expect(summary.isPartial, isTrue);
  });

  test('expenses are subtracted from the margin', () async {
    await bill([
      CartItemModel(product: product(id: 'e', sellPaise: 10000, costPaise: 6000)),
    ]);
    await LocalDatabase.instance.addExpense(ExpenseModel(
      id: 'exp_test_1',
      businessId: 'biz_profit_test',
      title: 'Chai',
      amountPaise: 1500,
      createdAt: DateTime.now(),
    ));

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    expect(summary.grossMarginPaise, 4000);
    expect(summary.expensesPaise, 1500);
    expect(summary.netProfitPaise, 2500);
  });

  test("yesterday's sales do not leak into today's profit", () async {
    await bill([
      CartItemModel(product: product(id: 'today', sellPaise: 10000, costPaise: 6000)),
    ]);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final summary = await LocalDatabase.instance.getDayProfitSummary(yesterday);
    expect(summary.grossMarginPaise, 0);
    expect(summary.uncostedLineCount, 0);
  });

  test('a catalog-imported product carries no invented cost price', () async {
    // MasterProductModel.toProductModel used to set
    // `purchasePricePaise: (mrpPaise * 0.85).round()` — a made-up 15% margin
    // that nobody entered and no supplier bill supports, which then flowed
    // into the profit tile and the inventory valuation as if it were real.
    const master = MasterProductModel(
      barcode: '8901030383701',
      name: 'Aashirvaad Atta 5kg',
      category: 'Atta, Rice & Dal',
      mrpPaise: 26000,
      sellingPricePaise: 24500,
    );
    final imported = master.toProductModel(businessId: 'biz_profit_test');

    expect(imported.purchasePricePaise, 0);
    expect(imported.purchasePricePaise, isNot(22100)); // 26000 × 0.85
    // An unknown cost must not inflate stock valuation either.
    expect(imported.assetCostValuationPaise, 0);
  });

  // 55 real bills through the real POS path is deliberately slow — it has to
  // cross the old 50-row cap to prove anything, and each bill runs a genuine
  // SQLite transaction. Hence the raised timeout rather than a faked insert.
  test('getSalesBetween is not capped, so a busy day is not truncated', () async {
    // The dashboard used to derive "today" by filtering the most recent 50
    // sales, so bill #51 onwards silently pushed the day's earliest bills out
    // of its own totals.
    for (var i = 0; i < 55; i++) {
      await bill([
        CartItemModel(product: product(id: 'bulk$i', sellPaise: 10000, costPaise: 6000)),
      ]);
    }

    final start = DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    final sales = await LocalDatabase.instance
        .getSalesBetween(dayStart, dayStart.add(const Duration(days: 1)));
    expect(sales.length, 55);

    final summary = await LocalDatabase.instance.getDayProfitSummary(DateTime.now());
    expect(summary.grossMarginPaise, 55 * 4000);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
