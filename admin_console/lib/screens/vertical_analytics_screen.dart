import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'merchant_detail_screen.dart';

class VerticalAnalyticsScreen extends StatefulWidget {
  const VerticalAnalyticsScreen({super.key});

  @override
  State<VerticalAnalyticsScreen> createState() => _VerticalAnalyticsScreenState();
}

class _VerticalAnalyticsScreenState extends State<VerticalAnalyticsScreen> {
  String? _selectedVerticalId;
  int _touchedIndex = -1;

  final Map<String, Color> _verticalColors = {
    'grocery': const Color(0xFF10B981), // Emerald
    'clothing': const Color(0xFF6366F1), // Indigo
    'pharmacy': const Color(0xFFF43F5E), // Rose
    'hardware': const Color(0xFFF59E0B), // Amber
    'restaurant': const Color(0xFF0EA5E9), // Sky Blue
    'other': const Color(0xFF64748B), // Slate
  };

  String _indianGroup(String digits) {
    if (digits.length <= 3) return digits;
    final lastThree = digits.substring(digits.length - 3);
    var remaining = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (remaining.length > 2) {
      groups.insert(0, remaining.substring(remaining.length - 2));
      remaining = remaining.substring(0, remaining.length - 2);
    }
    if (remaining.isNotEmpty) groups.insert(0, remaining);
    return '${groups.join(',')},$lastThree';
  }

  String _formatPaise(int paise) {
    final rupees = (paise / 100).round();
    final sign = rupees < 0 ? '-' : '';
    return '$sign₹${_indianGroup(rupees.abs().toString())}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.surfaceSunken,
      body: SafeArea(
        child: StreamBuilder<List<AdminBusiness>>(
          stream: AdminFirestoreService.instance.watchBusinesses(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AdminColors.red)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final businesses = snapshot.data!;
            final stats = AdminFirestoreService.instance.computeVerticalAnalytics(businesses);

            // Filtered stores if a vertical is tapped
            final filteredStores = _selectedVerticalId != null
                ? businesses.where((b) => b.businessType.toLowerCase().trim() == _selectedVerticalId).toList()
                : <AdminBusiness>[];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AdminColors.violetSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.pie_chart_rounded, color: AdminColors.violet, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vertical Intelligence & Retail Analytics', style: AdminTheme.heading(22)),
                          const SizedBox(height: 2),
                          const Text(
                            'Category distribution, market penetration, and turnover analysis across Indian retail verticals.',
                            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Top Section: Donut Chart + Highlights
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 900;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: _buildChartCard(stats, businesses.length)),
                            const SizedBox(width: 24),
                            Expanded(flex: 2, child: _buildHighlightsCard(stats)),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _buildChartCard(stats, businesses.length),
                          const SizedBox(height: 20),
                          _buildHighlightsCard(stats),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // Detailed Vertical Breakdown Cards
                  Text('Detailed Vertical Breakdown', style: AdminTheme.heading(18)),
                  const SizedBox(height: 4),
                  const Text(
                    'Click any vertical card to filter and inspect all stores in that segment.',
                    style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  _buildVerticalGrid(stats),

                  // Segmented Merchant Drilldown (if selected)
                  if (_selectedVerticalId != null) ...[
                    const SizedBox(height: 32),
                    _buildFilteredStoresSection(filteredStores),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChartCard(List<AdminVerticalStat> stats, int totalStores) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.donut_large_rounded, size: 20, color: AdminColors.violet),
              const SizedBox(width: 8),
              Text('Store Share by Category', style: AdminTheme.heading(16)),
              const Spacer(),
              Text('$totalStores Total Stores', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.inkMuted)),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          setState(() {
                            if (!event.isInterestedForInteractions || response == null || response.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = response.touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 3,
                      centerSpaceRadius: 55,
                      sections: stats.asMap().entries.map((entry) {
                        final i = entry.key;
                        final s = entry.value;
                        final isTouched = i == _touchedIndex;
                        final color = _verticalColors[s.verticalId] ?? AdminColors.inkMuted;
                        final radius = isTouched ? 65.0 : 55.0;

                        return PieChartSectionData(
                          color: color,
                          value: s.storeCount > 0 ? s.storeCount.toDouble() : 0.1,
                          title: s.storeCount > 0 ? '${s.percentage.toStringAsFixed(0)}%' : '',
                          radius: radius,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Legend
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: stats.map((s) {
                      final color = _verticalColors[s.verticalId] ?? AdminColors.inkMuted;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${s.iconEmoji} ${s.label}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${s.storeCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightsCard(List<AdminVerticalStat> stats) {
    if (stats.isEmpty) return const SizedBox.shrink();

    final topRevenue = stats.reduce((curr, next) => curr.totalRevenuePaise > next.totalRevenuePaise ? curr : next);
    final topCount = stats.reduce((curr, next) => curr.storeCount > next.storeCount ? curr : next);
    final topPro = stats.reduce((curr, next) => curr.proPenetrationPercent > next.proPenetrationPercent ? curr : next);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, size: 20, color: AdminColors.accent),
              const SizedBox(width: 8),
              Text('Vertical Insights', style: AdminTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 20),
          _buildInsightRow(
            title: 'Top Revenue Generator',
            name: '${topRevenue.iconEmoji} ${topRevenue.label}',
            metric: _formatPaise(topRevenue.totalRevenuePaise),
            color: AdminColors.accent,
            bgColor: AdminColors.accentSoft,
            icon: Icons.payments_rounded,
          ),
          const SizedBox(height: 14),
          _buildInsightRow(
            title: 'Largest Retail Base',
            name: '${topCount.iconEmoji} ${topCount.label}',
            metric: '${topCount.storeCount} stores (${topCount.percentage.toStringAsFixed(1)}%)',
            color: AdminColors.violet,
            bgColor: AdminColors.violetSoft,
            icon: Icons.storefront_rounded,
          ),
          const SizedBox(height: 14),
          _buildInsightRow(
            title: 'Highest Pro Conversion',
            name: '${topPro.iconEmoji} ${topPro.label}',
            metric: '${topPro.proPenetrationPercent.toStringAsFixed(1)}% on Pro Tier',
            color: AdminColors.amber,
            bgColor: AdminColors.amberSoft,
            icon: Icons.workspace_premium_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildInsightRow({
    required String title,
    required String name,
    required String metric,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(metric, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalGrid(List<AdminVerticalStat> stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1080 ? 3 : (constraints.maxWidth >= 640 ? 2 : 1);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: cols == 3 ? 1.45 : 1.6,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          itemBuilder: (context, index) {
            final s = stats[index];
            final isSelected = _selectedVerticalId == s.verticalId;
            final color = _verticalColors[s.verticalId] ?? AdminColors.accent;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedVerticalId = isSelected ? null : s.verticalId;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AdminColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? color : AdminColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))]
                      : const [BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(s.iconEmoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${s.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetricCol('Gross Turnover', _formatPaise(s.totalRevenuePaise), color),
                        _buildMetricCol('Store Count', '${s.storeCount} stores', AdminColors.ink),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetricCol('Avg / Store', _formatPaise(s.avgRevenuePaise), AdminColors.inkMuted),
                        _buildMetricCol('Pro Adoption', '${s.proStoresCount} (${s.proPenetrationPercent.toStringAsFixed(0)}%)', AdminColors.violet),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        isSelected ? '▲ Hide stores' : '▼ View stores',
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
      ],
    );
  }

  Widget _buildFilteredStoresSection(List<AdminBusiness> stores) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Stores in this Vertical (${stores.length})', style: AdminTheme.heading(16)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _selectedVerticalId = null),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Close View'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (stores.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No stores found in this category.', style: TextStyle(color: AdminColors.inkMuted))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stores.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: AdminColors.border),
              itemBuilder: (context, index) {
                final b = stores[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  title: Row(
                    children: [
                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      if (b.isProEffective)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AdminColors.violetSoft, borderRadius: BorderRadius.circular(4)),
                          child: const Text('PRO', style: TextStyle(color: AdminColors.violet, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                  subtitle: Text('${b.ownerName.isNotEmpty ? b.ownerName : 'Owner'} • 📞 ${b.phone} • Bills: ${b.totalSalesCount}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_formatPaise(b.totalRevenuePaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => MerchantDetailScreen(business: b)),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
