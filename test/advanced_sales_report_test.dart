// Regression tests for the Advanced Sales Reports data path
// (ReportsRepository.getAdvancedReportsData / getInvoicesForParty).
//
// Drives the real read path through an FFI SQLite database, per the lesson in
// DEVELOPMENT_LOG.md's case study — asserting on what the screen actually
// loads, not just on data shapes. Each test pins a bug found in review:
//  * partially returned bills were counted at their full value;
//  * lines with no buying price were counted as 100% profit;
//  * dead stock listed every business vertical's products;
//  * period ranges were closed and "7 Days" spanned 8 calendar days.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/core/database/reports_repository.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/models/report_models.dart';

Map<String, dynamic> _line(
  String productId,
  String name, {
  required double qty,
  required int unitPaise,
  int costPaise = 0,
  double returned = 0,
}) =>
    {
      'product_id': productId,
      'product_name': name,
      'quantity': qty,
      'unit_price_paise': unitPaise,
      'gross_total_paise': (unitPaise * qty).round(),
      'cost_price_paise': costPaise,
      'tax_rate': 0.0,
      'is_tax_inclusive': 1,
      if (returned > 0) 'returned_quantity': returned,
    };

SaleModel _sale(
  String id,
  DateTime at,
  List<Map<String, dynamic>> items, {
  String? customerId,
  String? customerName,
  String paymentMethod = 'cash',
  String status = 'completed',
}) {
  final total = items.fold<int>(0, (s, i) => s + (i['gross_total_paise'] as int));
  return SaleModel(
    id: id,
    businessId: 'biz_test',
    invoiceNumber: 'INV-$id',
    customerId: customerId,
    customerName: customerName,
    customerPhone: customerId == null ? null : '98765$id',
    subtotalPaise: total,
    taxAmountPaise: 0,
    totalAmountPaise: total,
    paymentMethod: paymentMethod,
    status: status,
    items: items,
    createdAt: at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final day = DateTime(2026, 9, 18);
  final start = day;
  final end = DateTime(2026, 9, 19);

  setUp(() async {
    await LocalDatabase.instance.switchUser('adv_report_test_${DateTime.now().microsecondsSinceEpoch}');
    await LocalDatabase.instance.upsertCategory(
      CategoryModel(id: 'cat_staples', businessId: 'biz_test', name: 'Staples', businessType: 'grocery'),
    );
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_atta',
      businessId: 'biz_test',
      name: 'Atta 5kg',
      categoryId: 'cat_staples',
      sellingPricePaise: 25000,
      mrpPaise: 26000,
      purchasePricePaise: 20000,
      stockQuantity: 10,
      businessType: 'grocery',
    ));
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  test('a partially returned bill counts only what the customer kept', () async {
    await LocalDatabase.instance.upsertSale(_sale(
      's1',
      day.add(const Duration(hours: 10)),
      [
        _line('p_atta', 'Atta 5kg', qty: 2, unitPaise: 25000, costPaise: 20000, returned: 1),
      ],
      status: 'partially_refunded',
    ));
    // A fully refunded bill contributes nothing at all.
    await LocalDatabase.instance.upsertSale(_sale(
      's2',
      day.add(const Duration(hours: 11)),
      [_line('p_atta', 'Atta 5kg', qty: 1, unitPaise: 25000, costPaise: 20000)],
      status: 'refunded',
    ));

    final data = await ReportsRepository.instance.getAdvancedReportsData(start, end, businessType: 'grocery');

    expect(data.paymentSummary.totalPaise, 25000, reason: 'One of two units was returned');
    expect(data.paymentSummary.totalCashPaise, 25000);
    final atta = data.soldItems.single;
    expect(atta.quantitySold, 1);
    expect(atta.totalSalesPaise, 25000);
    expect(atta.totalProfitPaise, 5000);
    expect(atta.categoryName, 'Staples');
    expect(data.partyData.single.totalSalesPaise, 25000);
  });

  test('lines with no buying price are reported as uncosted, never as 100% profit', () async {
    await LocalDatabase.instance.upsertSale(_sale(
      's1',
      day.add(const Duration(hours: 9)),
      [
        _line('p_atta', 'Atta 5kg', qty: 1, unitPaise: 25000, costPaise: 20000),
        _line('p_loose', 'Loose Sugar', qty: 2.5, unitPaise: 4000), // no cost on record
      ],
    ));

    final data = await ReportsRepository.instance.getAdvancedReportsData(start, end, businessType: 'grocery');

    expect(data.paymentSummary.totalPaise, 35000);
    expect(data.totalProfitPaise, 5000, reason: 'Only the costed line contributes margin');
    expect(data.isProfitPartial, isTrue);
    expect(data.uncostedLineCount, 1);
    expect(data.marginPercent, closeTo(20.0, 0.001), reason: 'Margin is over costed revenue only');

    final sugar = data.soldItems.firstWhere((i) => i.itemId == 'p_loose');
    expect(sugar.quantitySold, 2.5);
    expect(sugar.totalProfitPaise, 0);
    expect(sugar.categoryName, 'General');
  });

  test('periods are half-open and "7 Days" is exactly seven calendar days', () async {
    final lastInstantOfYesterday = DateTime(2026, 9, 17, 23, 59, 59, 999, 999);
    await LocalDatabase.instance.upsertSale(_sale(
      'late',
      lastInstantOfYesterday,
      [_line('p_atta', 'Atta 5kg', qty: 1, unitPaise: 25000, costPaise: 20000)],
    ));
    await LocalDatabase.instance.upsertSale(_sale(
      'midnight',
      DateTime(2026, 9, 18),
      [_line('p_atta', 'Atta 5kg', qty: 1, unitPaise: 10000, costPaise: 8000)],
    ));

    final now = DateTime(2026, 9, 18, 15);
    final yesterday = ReportPeriod.resolve('Yesterday', now: now);
    final yData = await ReportsRepository.instance
        .getAdvancedReportsData(yesterday.start, yesterday.end, businessType: 'grocery');
    expect(yData.paymentSummary.totalPaise, 25000,
        reason: 'The last microsecond of yesterday belongs to yesterday; midnight belongs to today');

    final week = ReportPeriod.resolve('7 Days', now: now);
    expect(week.start, DateTime(2026, 9, 12));
    expect(week.end, DateTime(2026, 9, 19));
    expect(week.end.difference(week.start).inDays, 7);

    final lastMonth = ReportPeriod.resolve('Last Month', now: DateTime(2026, 1, 10));
    expect(lastMonth.start, DateTime(2025, 12, 1));
    expect(lastMonth.end, DateTime(2026, 1, 1));
  });

  test('dead stock lists only the active vertical, skips variant parents and sold items', () async {
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_rice',
      businessId: 'biz_test',
      name: 'Basmati Rice',
      sellingPricePaise: 12000,
      mrpPaise: 13000,
      stockQuantity: 4,
      businessType: 'grocery',
    ));
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_shirt',
      businessId: 'biz_test',
      name: 'Cotton Shirt',
      sellingPricePaise: 49900,
      mrpPaise: 59900,
      stockQuantity: 7,
      businessType: 'clothing',
    ));
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'p_parent',
      businessId: 'biz_test',
      name: 'Oil (all sizes)',
      sellingPricePaise: 0,
      mrpPaise: 0,
      stockQuantity: 20,
      businessType: 'grocery',
      hasVariants: true,
    ));
    await LocalDatabase.instance.upsertSale(_sale(
      's1',
      day.add(const Duration(hours: 12)),
      [_line('p_atta', 'Atta 5kg', qty: 1, unitPaise: 25000, costPaise: 20000)],
    ));

    final data = await ReportsRepository.instance.getAdvancedReportsData(start, end, businessType: 'grocery');
    final deadIds = data.deadStockItems.map((i) => i.itemId).toSet();

    expect(deadIds, contains('dead_p_rice'));
    expect(deadIds, isNot(contains('dead_p_shirt')), reason: 'Clothing stock must not leak into a grocery report');
    expect(deadIds, isNot(contains('dead_p_parent')), reason: 'Variant parents are not sold directly');
    expect(deadIds, isNot(contains('dead_p_atta')), reason: 'Atta sold in the period');
    expect(data.deadStockItems.firstWhere((i) => i.itemId == 'dead_p_rice').stockQuantity, 4);
  });

  test('walk-in and named customers are grouped separately and their bills load', () async {
    await LocalDatabase.instance.upsertSale(_sale(
      'w1',
      day.add(const Duration(hours: 8)),
      [_line('p_atta', 'Atta 5kg', qty: 1, unitPaise: 25000, costPaise: 20000)],
    ));
    await LocalDatabase.instance.upsertSale(_sale(
      'c1',
      day.add(const Duration(hours: 9)),
      [_line('p_atta', 'Atta 5kg', qty: 2, unitPaise: 25000, costPaise: 20000)],
      customerId: 'cust_ravi',
      customerName: 'Ravi',
      paymentMethod: 'credit',
    ));

    final data = await ReportsRepository.instance.getAdvancedReportsData(start, end, businessType: 'grocery');
    final walkIn = data.partyData.firstWhere((p) => p.isWalkIn);
    final ravi = data.partyData.firstWhere((p) => p.partyId == 'cust_ravi');

    expect(walkIn.partyName, 'Walk-in Customer');
    expect(walkIn.totalSalesPaise, 25000);
    expect(ravi.partyName, 'Ravi');
    expect(ravi.totalSalesPaise, 50000);
    expect(ravi.creditPaise, 50000);
    expect(data.paymentSummary.totalCreditPaise, 50000);

    final walkInBills = await ReportsRepository.instance.getInvoicesForParty(start, end, PartySalesSummary.walkInId);
    final raviBills = await ReportsRepository.instance.getInvoicesForParty(start, end, 'cust_ravi');
    expect(walkInBills.map((s) => s.id), ['w1']);
    expect(raviBills.map((s) => s.id), ['c1']);

    // The party screen recomputes its header from reloaded bills.
    final recomputed = ReportsRepository.summarizeParty('cust_ravi', raviBills);
    expect(recomputed.totalSalesPaise, ravi.totalSalesPaise);
    expect(recomputed.totalProfitPaise, ravi.totalProfitPaise);
  });
}
