import 'local_database.dart';
import '../../models/report_models.dart';
import '../../models/models.dart';

/// Data source for the Advanced Sales Reports (party / category / item /
/// dead-stock analytics).
///
/// Rules every figure here follows — keep them in sync with
/// `LocalDatabase.getDayProfitSummary` so Home and this screen never disagree:
///  * Fully refunded bills are excluded; PARTIALLY refunded bills count only
///    what the customer kept (`returned_quantity` on each line, and
///    `SaleModel.netAmountPaise` / `net*AmountPaise` for the bill).
///  * Line revenue is `gross_total_paise`, prorated for returned quantity.
///  * Profit covers only lines with a frozen buying rate (`cost_price_paise`
///    > 0); uncosted lines are counted separately, never as 100% margin.
///  * Periods are half-open: `start <= created_at < end`.
class ReportsRepository {
  static final ReportsRepository instance = ReportsRepository._init();
  ReportsRepository._init();

  /// [businessType] scopes the dead-stock list to the active vertical's
  /// catalogue. Without it every vertical's seeded products showed up as
  /// "dead stock" — the same cross-vertical leak DEVELOPMENT_LOG.md's case
  /// study describes for getAllProducts.
  Future<AdvancedReportsData> getAdvancedReportsData(
    DateTime start,
    DateTime end, {
    String? businessType,
  }) async {
    final sales = await _salesBetween(start, end);
    // Category lookup uses the whole catalogue so every sold line resolves
    // to its real category; only dead stock is scoped to the vertical.
    final allProducts = await LocalDatabase.instance.getAllProducts();
    final categories = await LocalDatabase.instance.getAllCategories();
    final verticalProducts = (businessType == null || businessType.isEmpty)
        ? allProducts
        : await LocalDatabase.instance.getAllProducts(businessType: businessType);

    return buildReport(
      sales: sales,
      catalog: allProducts,
      categoryNames: {for (final c in categories) c.id: c.name},
      deadStockCandidates: verticalProducts,
    );
  }

  Future<List<SaleModel>> getInvoicesForParty(DateTime start, DateTime end, String partyId) {
    return _salesBetween(start, end, partyId: partyId, newestFirst: true);
  }

  Future<List<SaleModel>> _salesBetween(
    DateTime start,
    DateTime end, {
    String? partyId,
    bool newestFirst = false,
  }) async {
    final db = await LocalDatabase.instance.database;
    var where = "created_at >= ? AND created_at < ? AND LOWER(status) NOT IN ('refunded', 'returned')";
    final args = <Object?>[start.toIso8601String(), end.toIso8601String()];
    if (partyId == PartySalesSummary.walkInId) {
      where += " AND (customer_id IS NULL OR customer_id = '')";
    } else if (partyId != null) {
      where += ' AND customer_id = ?';
      args.add(partyId);
    }
    final rows = await db.query(
      'sales',
      where: where,
      whereArgs: args,
      orderBy: newestFirst ? 'created_at DESC' : 'created_at ASC',
    );
    return rows.map(SaleModel.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Pure aggregation — no database access, so tests can drive it directly.
  // ---------------------------------------------------------------------------

  static String partyIdOf(SaleModel sale) {
    final id = sale.customerId;
    return (id == null || id.isEmpty) ? PartySalesSummary.walkInId : id;
  }

  /// Builds every tab of the report from already-loaded rows.
  static AdvancedReportsData buildReport({
    required List<SaleModel> sales,
    required List<ProductModel> catalog,
    required Map<String, String> categoryNames,
    required List<ProductModel> deadStockCandidates,
  }) {
    final productsById = {for (final p in catalog) p.id: p};
    String categoryOf(String? productId) {
      final catId = productsById[productId]?.categoryId;
      return categoryNames[catId] ?? 'General';
    }

    int cash = 0, upi = 0, credit = 0;
    final salesByParty = <String, List<SaleModel>>{};
    final items = <String, _Acc>{};
    final categories = <String, _Acc>{};

    for (final sale in sales) {
      if (sale.isRefunded) continue;
      cash += sale.netCashAmountPaise;
      upi += sale.netUpiAmountPaise;
      credit += sale.netCreditAmountPaise;
      salesByParty.putIfAbsent(partyIdOf(sale), () => []).add(sale);

      for (final line in _linesOf(sale)) {
        final product = productsById[line.productId];
        final itemAcc = items.putIfAbsent(line.key, () => _Acc(line.productId ?? line.key));
        itemAcc.name = product?.name ?? line.name;
        itemAcc.add(line);
        categories.putIfAbsent(categoryOf(line.productId), () => _Acc('')).add(line);
      }
    }

    final itemData = <ItemSalesSummary>[
      for (final a in items.values)
        ItemSalesSummary(
          itemId: a.id,
          itemName: a.name,
          categoryName: categoryOf(a.id),
          totalSalesPaise: a.revenue,
          totalCostPaise: a.cost,
          totalProfitPaise: a.profit,
          quantitySold: a.qty,
          costedRevenuePaise: a.costedRevenue,
          uncostedRevenuePaise: a.uncostedRevenue,
          uncostedLineCount: a.uncostedLines,
        ),
    ];

    // Dead stock: in-stock products of this vertical with no sale in the
    // period. Variant parents are skipped — their children are what sells.
    for (final p in deadStockCandidates) {
      if (p.stockQuantity <= 0 || p.hasVariants || items.containsKey(p.id)) continue;
      itemData.add(ItemSalesSummary(
        itemId: '${ItemSalesSummary.deadStockPrefix}${p.id}',
        itemName: p.name,
        categoryName: categoryOf(p.id),
        totalSalesPaise: 0,
        totalCostPaise: 0,
        totalProfitPaise: 0,
        quantitySold: 0,
        stockQuantity: p.stockQuantity,
        unit: p.unit,
      ));
    }

    return AdvancedReportsData(
      partyData: [
        for (final e in salesByParty.entries) summarizeParty(e.key, e.value),
      ],
      categoryData: [
        for (final e in categories.entries)
          CategorySalesSummary(
            categoryName: e.key,
            totalSalesPaise: e.value.revenue,
            totalCostPaise: e.value.cost,
            totalProfitPaise: e.value.profit,
            quantitySold: e.value.qty,
            costedRevenuePaise: e.value.costedRevenue,
            uncostedRevenuePaise: e.value.uncostedRevenue,
            uncostedLineCount: e.value.uncostedLines,
          ),
      ],
      itemData: itemData,
      paymentSummary: PaymentModeSummary(
        totalCashPaise: cash,
        totalUpiPaise: upi,
        totalCreditPaise: credit,
      ),
    );
  }

  /// One party's totals from its bills. Also used by the party detail screen
  /// to refresh its header after a bill is returned from the sale modal.
  static PartySalesSummary summarizeParty(
    String partyId,
    List<SaleModel> sales, {
    String? fallbackName,
    String? fallbackPhone,
  }) {
    final isWalkIn = partyId == PartySalesSummary.walkInId;
    String? name;
    String? phone;
    int billed = 0, credit = 0, count = 0;
    final acc = _Acc(partyId);

    // Oldest first, so the most recent name/phone on record wins.
    final ordered = [...sales]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final sale in ordered) {
      if (sale.isRefunded) continue;
      count++;
      billed += sale.netAmountPaise;
      credit += sale.netCreditAmountPaise;
      if (!isWalkIn) {
        if ((sale.customerName ?? '').trim().isNotEmpty) name = sale.customerName!.trim();
        if ((sale.customerPhone ?? '').trim().isNotEmpty) phone = sale.customerPhone!.trim();
      }
      for (final line in _linesOf(sale)) {
        acc.add(line);
      }
    }

    return PartySalesSummary(
      partyId: partyId,
      partyName: isWalkIn ? 'Walk-in Customer' : (name ?? fallbackName ?? 'Customer'),
      partyPhone: isWalkIn ? '' : (phone ?? fallbackPhone ?? ''),
      totalSalesPaise: billed,
      totalCostPaise: acc.cost,
      totalProfitPaise: acc.profit,
      invoiceCount: count,
      creditPaise: credit,
      costedRevenuePaise: acc.costedRevenue,
      uncostedRevenuePaise: acc.uncostedRevenue,
      uncostedLineCount: acc.uncostedLines,
    );
  }

  /// A sale's lines, net of returned quantity. A malformed line is skipped on
  /// its own instead of silently dropping every line after it.
  static List<_Line> _linesOf(SaleModel sale) {
    final lines = <_Line>[];
    for (final raw in sale.items) {
      try {
        final soldQty = ((raw['quantity'] ?? raw['qty'] ?? 1) as num).toDouble();
        final returnedQty = ((raw['returned_quantity'] ?? 0) as num).toDouble();
        final qty = (soldQty - returnedQty).clamp(0.0, soldQty).toDouble();
        if (qty <= 0) continue;

        final productMap = raw['product'];
        final rawId = raw['product_id'] ??
            raw['id'] ??
            (productMap is Map ? productMap['id'] : null);
        final rawName = raw['product_name'] ??
            raw['name'] ??
            (productMap is Map ? productMap['name'] : null);
        final productId = (rawId?.toString().isNotEmpty ?? false) ? rawId.toString() : null;
        final name = (rawName?.toString().trim().isNotEmpty ?? false) ? rawName.toString().trim() : 'Unknown Item';

        final num unitPrice = (raw['unit_price_paise'] ?? raw['price_paise'] ?? raw['selling_price_paise'] ?? 0) as num;
        final num lineGross = (raw['gross_total_paise'] as num?) ?? unitPrice * soldQty;
        final revenue = qty == soldQty ? lineGross.round() : (lineGross * qty / soldQty).round();
        final unitCost = ((raw['cost_price_paise'] ?? 0) as num).toDouble();

        lines.add(_Line(
          key: productId ?? 'name:${name.toLowerCase()}',
          productId: productId,
          name: name,
          qty: qty,
          revenue: revenue,
          cost: unitCost > 0 ? (unitCost * qty).round() : null,
        ));
      } catch (_) {
        continue;
      }
    }
    return lines;
  }
}

class _Line {
  final String key;
  final String? productId;
  final String name;
  final double qty;
  final int revenue;

  /// Null when the line has no frozen buying rate.
  final int? cost;

  const _Line({
    required this.key,
    required this.productId,
    required this.name,
    required this.qty,
    required this.revenue,
    required this.cost,
  });
}

class _Acc {
  final String id;
  String name = '';
  double qty = 0;
  int revenue = 0;
  int cost = 0;
  int costedRevenue = 0;
  int uncostedRevenue = 0;
  int uncostedLines = 0;

  _Acc(this.id);

  int get profit => costedRevenue - cost;

  void add(_Line l) {
    qty += l.qty;
    revenue += l.revenue;
    if (l.cost == null) {
      uncostedRevenue += l.revenue;
      uncostedLines++;
    } else {
      cost += l.cost!;
      costedRevenue += l.revenue;
    }
  }
}
