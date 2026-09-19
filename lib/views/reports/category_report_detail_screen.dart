import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/report_models.dart';
import '../common/kamai_bottom_nav.dart';

class CategoryReportDetailScreen extends StatelessWidget {
  final CategorySalesSummary category;
  final List<ItemSalesSummary> items;
  final String dateRangeText;

  /// Profit is shown only if the owner unlocked it on the report screen.
  final bool showProfit;

  static const Color _kIndigo = Color(0xFF4F46E5);
  static const Color _kGreen = Color(0xFF059669);
  static const Color _kGreenLight = Color(0xFFECFDF5);
  static const Color _kSlate50 = Color(0xFFF8FAFC);
  static const Color _kSlate500 = Color(0xFF64748B);
  static const Color _kSlate900 = Color(0xFF0F172A);
  static const Color _kBlue = Color(0xFF0284C7);
  static const Color _kAmber = Color(0xFFD97706);

  const CategoryReportDetailScreen({
    super.key,
    required this.category,
    required this.items,
    required this.dateRangeText,
    this.showProfit = false,
  });

  String _profitText(int paise) => showProfit ? MoneyFormatter.formatINR(paise) : '₹ ••••';

  @override
  Widget build(BuildContext context) {
    final margin = category.isProfitPartial ? 'partial' : '${category.marginPercent.toStringAsFixed(1)}% margin';
    // The header promises "sorted by sales volume" whatever sort the
    // report screen was using.
    final items = [...this.items]..sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));

    int maxSales = 0;
    for (var i in items) {
      if (i.totalSalesPaise > maxSales) maxSales = i.totalSalesPaise;
    }

    return Scaffold(
      backgroundColor: _kSlate50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _kSlate900),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.categoryName,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kSlate900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${items.length} Products • $dateRangeText',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _kSlate500,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const KamaiBottomNav(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        children: [
          // 1. Category KPI Hero Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _kGreenLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.category_rounded, size: 20, color: _kGreen),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.categoryName,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16, color: _kSlate900),
                          ),
                          Text(
                            'Period: $dateRangeText',
                            style: GoogleFonts.inter(fontSize: 11, color: _kSlate500, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFF1F5F9), height: 1),
                const SizedBox(height: 12),

                // Metrics Row
                Row(
                  children: [
                    Expanded(
                      child: _buildHeroStatTile(
                        icon: Icons.trending_up_rounded,
                        color: _kGreen,
                        title: 'Total Sales',
                        value: MoneyFormatter.formatINR(category.totalSalesPaise),
                      ),
                    ),
                    Container(width: 1, height: 42, color: const Color(0xFFF1F5F9)),
                    Expanded(
                      child: _buildHeroStatTile(
                        icon: Icons.pie_chart_outline_rounded,
                        color: _kIndigo,
                        title: 'Est. Profit',
                        value: _profitText(category.totalProfitPaise),
                        subtitle: showProfit ? margin : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildHeroStatTile(
                        icon: Icons.inventory_2_outlined,
                        color: _kBlue,
                        title: 'Qty Sold',
                        value: '${formatReportQty(category.quantitySold)} units',
                      ),
                    ),
                    Container(width: 1, height: 42, color: const Color(0xFFF1F5F9)),
                    Expanded(
                      child: _buildHeroStatTile(
                        icon: Icons.receipt_long_rounded,
                        color: _kAmber,
                        title: 'Products',
                        value: '${items.length} items',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PRODUCTS IN CATEGORY (${items.length})',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _kSlate500,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'Sorted by sales volume',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Items List
          if (items.isEmpty)
            _buildEmptyState()
          else
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final fraction = maxSales > 0 ? item.totalSalesPaise / maxSales : 0.0;
              final itemMargin = showProfit ? ' (${item.marginPercent.toStringAsFixed(1)}%)' : '';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Rank badge
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: index == 0
                                  ? const Color(0xFFFEF3C7)
                                  : (index == 1 ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '#${index + 1}',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: index == 0
                                      ? const Color(0xFFD97706)
                                      : (index == 1 ? const Color(0xFF475569) : _kSlate500),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.itemName,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: _kSlate900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            MoneyFormatter.formatINR(item.totalSalesPaise),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: _kSlate900,
                            ).copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: const AlwaysStoppedAnimation<Color>(_kIndigo),
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Qty: ${formatReportQty(item.quantitySold)} units',
                            style: GoogleFonts.inter(fontSize: 11, color: _kSlate500, fontWeight: FontWeight.w500),
                          ),
                          Row(
                            children: [
                              Text('Profit: ', style: GoogleFonts.inter(fontSize: 11, color: _kSlate500)),
                              Text(
                                _profitText(item.totalProfitPaise),
                                style: GoogleFonts.inter(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w700),
                              ),
                              Text(itemMargin, style: GoogleFonts.inter(fontSize: 10.5, color: _kSlate500)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildHeroStatTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: _kSlate500),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: _kSlate900)
                            .copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _kGreen),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            'No Products Found',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
          ),
          const SizedBox(height: 4),
          Text(
            'No items billed in this category for the selected period.',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
