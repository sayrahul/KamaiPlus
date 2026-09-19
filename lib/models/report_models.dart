import 'package:intl/intl.dart';

/// "12", "2.5", "0.25" — whole numbers without decimals, loose quantities
/// (kg / litre) without rounding them away the way `toStringAsFixed(0)` did.
String formatReportQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

/// Profit fields shared by every summary row in the Advanced Sales Reports.
///
/// Profit is computed ONLY over lines whose buying rate was frozen onto the
/// sale (`cost_price_paise > 0`) — the same rule as
/// `LocalDatabase.getDayProfitSummary`. A line with no known cost used to be
/// counted here as 100% profit, so a shop that never entered buying prices saw
/// its entire turnover reported as "profit". Uncosted revenue is now reported
/// separately so the UI can say "partial" instead of overstating the margin.
mixin ProfitCoverage {
  int get totalProfitPaise;
  int get costedRevenuePaise;
  int get uncostedRevenuePaise;
  int get uncostedLineCount;

  bool get isProfitPartial => uncostedLineCount > 0;

  /// Margin over the revenue it actually covers (costed lines only).
  double get marginPercent =>
      costedRevenuePaise > 0 ? totalProfitPaise * 100 / costedRevenuePaise : 0.0;
}

class PartySalesSummary with ProfitCoverage {
  final String partyId;
  final String partyName;
  final String partyPhone;

  /// What the party was billed in the period, net of returns — the same
  /// figure as the invoice cards and the statement PDF.
  final int totalSalesPaise;
  final int totalCostPaise;
  @override
  final int totalProfitPaise;
  final int invoiceCount;

  /// Part of [totalSalesPaise] that was billed on udhar (credit).
  final int creditPaise;
  @override
  final int costedRevenuePaise;
  @override
  final int uncostedRevenuePaise;
  @override
  final int uncostedLineCount;

  PartySalesSummary({
    required this.partyId,
    required this.partyName,
    required this.partyPhone,
    required this.totalSalesPaise,
    required this.totalCostPaise,
    required this.totalProfitPaise,
    required this.invoiceCount,
    this.creditPaise = 0,
    this.costedRevenuePaise = 0,
    this.uncostedRevenuePaise = 0,
    this.uncostedLineCount = 0,
  });

  bool get isWalkIn => partyId == PartySalesSummary.walkInId;

  static const String walkInId = 'walkin';
}

class CategorySalesSummary with ProfitCoverage {
  final String categoryName;
  final int totalSalesPaise;
  final int totalCostPaise;
  @override
  final int totalProfitPaise;
  final double quantitySold;
  @override
  final int costedRevenuePaise;
  @override
  final int uncostedRevenuePaise;
  @override
  final int uncostedLineCount;

  CategorySalesSummary({
    required this.categoryName,
    required this.totalSalesPaise,
    required this.totalCostPaise,
    required this.totalProfitPaise,
    required this.quantitySold,
    this.costedRevenuePaise = 0,
    this.uncostedRevenuePaise = 0,
    this.uncostedLineCount = 0,
  });
}

class ItemSalesSummary with ProfitCoverage {
  /// Product id, or `dead_<productId>` for an unsold in-stock product.
  final String itemId;
  final String itemName;
  final String categoryName;
  final int totalSalesPaise;
  final int totalCostPaise;
  @override
  final int totalProfitPaise;
  final double quantitySold;
  @override
  final int costedRevenuePaise;
  @override
  final int uncostedRevenuePaise;
  @override
  final int uncostedLineCount;

  /// Current stock on hand — only filled for dead-stock rows.
  final double stockQuantity;
  final String unit;

  ItemSalesSummary({
    required this.itemId,
    required this.itemName,
    required this.categoryName,
    required this.totalSalesPaise,
    required this.totalCostPaise,
    required this.totalProfitPaise,
    required this.quantitySold,
    this.costedRevenuePaise = 0,
    this.uncostedRevenuePaise = 0,
    this.uncostedLineCount = 0,
    this.stockQuantity = 0,
    this.unit = '',
  });

  static const String deadStockPrefix = 'dead_';

  bool get isDeadStock => itemId.startsWith(deadStockPrefix);
}

class PaymentModeSummary {
  final int totalCashPaise;
  final int totalUpiPaise;
  final int totalCreditPaise;

  int get totalPaise => totalCashPaise + totalUpiPaise + totalCreditPaise;

  PaymentModeSummary({
    required this.totalCashPaise,
    required this.totalUpiPaise,
    required this.totalCreditPaise,
  });
}

class AdvancedReportsData {
  final List<PartySalesSummary> partyData;
  final List<CategorySalesSummary> categoryData;
  final List<ItemSalesSummary> itemData;
  final PaymentModeSummary paymentSummary;

  AdvancedReportsData({
    required this.partyData,
    required this.categoryData,
    required this.itemData,
    required this.paymentSummary,
  });

  int get totalProfitPaise => categoryData.fold(0, (s, c) => s + c.totalProfitPaise);
  int get costedRevenuePaise => categoryData.fold(0, (s, c) => s + c.costedRevenuePaise);
  int get uncostedLineCount => categoryData.fold(0, (s, c) => s + c.uncostedLineCount);
  bool get isProfitPartial => uncostedLineCount > 0;
  double get marginPercent =>
      costedRevenuePaise > 0 ? totalProfitPaise * 100 / costedRevenuePaise : 0.0;

  List<ItemSalesSummary> get soldItems => itemData.where((i) => !i.isDeadStock).toList();
  List<ItemSalesSummary> get deadStockItems => itemData.where((i) => i.isDeadStock).toList();
}

/// A report period as a half-open range: `start <= created_at < end`.
///
/// Same convention as `LocalDatabase.getSalesBetween`. The screen used to
/// build closed ranges ending at "now" or at 23:59:59.999, which silently
/// dropped any sale stamped in the last sub-millisecond (sales carry
/// microseconds), and "7 Days" actually spanned 8 calendar days.
class ReportPeriod {
  final String label;
  final DateTime start;
  final DateTime end;

  const ReportPeriod(this.label, this.start, this.end);

  static const List<String> labels = ['Today', 'Yesterday', '7 Days', 'This Month', 'Last Month'];

  factory ReportPeriod.resolve(String label, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final tomorrow = DateTime(n.year, n.month, n.day + 1);
    switch (label) {
      case 'Today':
        return ReportPeriod(label, today, tomorrow);
      case 'Yesterday':
        return ReportPeriod(label, DateTime(n.year, n.month, n.day - 1), today);
      case '7 Days':
        // Today plus the six days before it.
        return ReportPeriod(label, DateTime(n.year, n.month, n.day - 6), tomorrow);
      case 'Last Month':
        return ReportPeriod(label, DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 1));
      case 'This Month':
      default:
        return ReportPeriod('This Month', DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1));
    }
  }

  /// "1 Sep 2026 - 19 Sep 2026" — the last day shown is capped at today.
  static String spanText(DateTime start, DateTime end, {DateTime? now, String? locale}) {
    final n = now ?? DateTime.now();
    var last = end.subtract(const Duration(microseconds: 1));
    if (last.isAfter(n)) last = n;
    final fmt = DateFormat('d MMM yyyy', locale);
    final a = fmt.format(start);
    final b = fmt.format(last);
    return a == b ? a : '$a - $b';
  }

  String get dateSpanText => spanText(start, end);
}
