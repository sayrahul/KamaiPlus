import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

/// Landing screen after login.
///
/// Everything on this screen is derived client-side from the single
/// [AdminFirestoreService.watchBusinesses] stream — no dedicated dashboard
/// query. That stream already comes sorted by `lastSaleAt` descending, which
/// is exactly what "recently active" needs and is also why "needs
/// attention" doesn't need its own sort key beyond `proExpiry`.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminBusiness>>(
      stream: AdminFirestoreService.instance.watchBusinesses(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StateMessage(
            icon: Icons.error_outline_rounded,
            iconColor: AdminColors.red,
            iconBg: AdminColors.redSoft,
            title: 'Could not load merchants',
            message: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const _StateMessage(
            icon: Icons.hourglass_top_rounded,
            iconColor: AdminColors.inkMuted,
            iconBg: AdminColors.surfaceSunken,
            title: 'Loading merchants…',
            message: 'Fetching the latest data from Firestore.',
            showSpinner: true,
          );
        }

        final businesses = snapshot.data!;
        if (businesses.isEmpty) {
          return const _StateMessage(
            icon: Icons.storefront_outlined,
            iconColor: AdminColors.inkMuted,
            iconBg: AdminColors.surfaceSunken,
            title: 'No merchants yet',
            message: "They'll show up here once a shop signs up.",
          );
        }

        return _DashboardContent(businesses: businesses);
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final List<AdminBusiness> businesses;
  const _DashboardContent({required this.businesses});

  @override
  Widget build(BuildContext context) {
    final total = businesses.length;
    final proCount = businesses.where((b) => b.isProEffective).length;
    final freeCount = total - proCount;
    final totalRevenuePaise = businesses.fold<int>(0, (sum, b) => sum + b.totalRevenuePaise);
    final totalBills = businesses.fold<int>(0, (sum, b) => sum + b.totalSalesCount);

    // "Recently active": watchBusinesses() already sorts by lastSaleAt desc.
    final recentlyActive = businesses.take(8).toList();

    // "Needs attention": Pro lapsed within the last 14 days — a real,
    // actionable renewal-nudge signal, not every ever-free merchant.
    final now = DateTime.now();
    final needsAttention = businesses.where((b) {
      if (b.isProEffective) return false;
      final expiry = b.proExpiry;
      if (expiry == null || !now.isAfter(expiry)) return false;
      return now.difference(expiry).inDays <= 14;
    }).toList()
      ..sort((a, b) => b.proExpiry!.compareTo(a.proExpiry!));
    final needsAttentionTop = needsAttention.take(5).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1080
            ? 4
            : width >= 720
                ? 2
                : 1;
        final aspectRatio = crossAxisCount == 4
            ? 1.9
            : crossAxisCount == 2
                ? 2.3
                : 2.8;
        final stacked = width < 900;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard', style: AdminTheme.heading(22)),
              const SizedBox(height: 4),
              const Text(
                'Live view across every merchant on KamaiPlus.',
                style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
              ),
              const SizedBox(height: 22),
              GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: aspectRatio,
                children: [
                  _StatCard(
                    icon: Icons.storefront_rounded,
                    color: AdminColors.accent,
                    bg: AdminColors.accentSoft,
                    value: _decimal.format(total),
                    label: 'Merchants',
                    sublabel: 'Signed up on KamaiPlus',
                  ),
                  _StatCard(
                    icon: Icons.workspace_premium_rounded,
                    color: AdminColors.violet,
                    bg: AdminColors.violetSoft,
                    value: _decimal.format(proCount),
                    label: 'Pro merchants',
                    sublabel: '${_decimal.format(freeCount)} on Free',
                  ),
                  _StatCard(
                    icon: Icons.payments_rounded,
                    color: AdminColors.accent,
                    bg: AdminColors.accentSoft,
                    value: _formatPaise(totalRevenuePaise),
                    label: 'Lifetime revenue',
                    sublabel: 'Across all merchants',
                  ),
                  _StatCard(
                    icon: Icons.receipt_long_rounded,
                    color: AdminColors.amber,
                    bg: AdminColors.amberSoft,
                    value: _decimal.format(totalBills),
                    label: 'Bills generated',
                    sublabel: 'Total across all merchants',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _RevenueTrendSection(),
              const SizedBox(height: 24),
              if (stacked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RecentlyActiveSection(businesses: recentlyActive),
                    const SizedBox(height: 16),
                    _NeedsAttentionSection(businesses: needsAttentionTop),
                  ],
                )
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _RecentlyActiveSection(businesses: recentlyActive)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _NeedsAttentionSection(businesses: needsAttentionTop)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------

/// 14-day revenue trend across every merchant. Its own Future (not part of
/// [DashboardScreen]'s `watchBusinesses()` stream) since it needs a
/// different query — a `timestamp` range on root `sales`, not anything
/// derivable from the businesses list.
class _RevenueTrendSection extends StatefulWidget {
  const _RevenueTrendSection();

  @override
  State<_RevenueTrendSection> createState() => _RevenueTrendSectionState();
}

class _RevenueTrendSectionState extends State<_RevenueTrendSection> {
  static const _days = 14;
  late Future<Map<String, int>> _trendFuture;

  @override
  void initState() {
    super.initState();
    _trendFuture = AdminFirestoreService.instance.getDailyRevenueTrend(days: _days);
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.show_chart_rounded,
      iconColor: AdminColors.accent,
      iconBg: AdminColors.accentSoft,
      title: 'Revenue — last $_days days',
      subtitle: 'Total across every merchant, by day',
      child: SizedBox(
        height: 200,
        child: FutureBuilder<Map<String, int>>(
          future: _trendFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _InlineEmpty(text: 'Could not load the revenue trend.');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            final byDay = snapshot.data!;
            // Fill every day in the window, even ones with zero sales — a
            // gap in the line would otherwise misleadingly join two
            // non-adjacent days as if nothing happened in between, instead
            // of showing the actual zero.
            final now = DateTime.now();
            final points = <FlSpot>[];
            final dayLabels = <int, String>{};
            int maxPaise = 0;
            for (int i = _days - 1; i >= 0; i--) {
              final day = now.subtract(Duration(days: i));
              final key = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
              final paise = byDay[key] ?? 0;
              final x = (_days - 1 - i).toDouble();
              points.add(FlSpot(x, paise / 100.0));
              dayLabels[x.toInt()] = DateFormat('d MMM').format(day);
              if (paise > maxPaise) maxPaise = paise;
            }

            if (maxPaise == 0) {
              return const _InlineEmpty(text: 'No sales recorded in this window yet.');
            }

            return LineChart(
              LineChartData(
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxPaise / 100.0) / 4,
                  getDrawingHorizontalLine: (_) => const FlLine(color: AdminColors.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) => Text(
                        _formatPaiseCompact((value * 100).round()),
                        style: const TextStyle(fontSize: 10, color: AdminColors.inkFaint),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: (_days / 5).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        final label = dayLabels[value.toInt()];
                        if (label == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label, style: const TextStyle(fontSize: 10, color: AdminColors.inkFaint)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              _formatPaise((s.y * 100).round()),
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: AdminColors.accent,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: AdminColors.accentSoft),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecentlyActiveSection extends StatelessWidget {
  final List<AdminBusiness> businesses;
  const _RecentlyActiveSection({required this.businesses});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.bolt_rounded,
      iconColor: AdminColors.accent,
      iconBg: AdminColors.accentSoft,
      title: 'Recently active',
      subtitle: 'Most recent sale, across all merchants',
      child: businesses.isEmpty
          ? const _InlineEmpty(text: 'No sales recorded yet.')
          : Column(
              children: [
                for (int i = 0; i < businesses.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AdminColors.border),
                  _RecentlyActiveRow(business: businesses[i]),
                ],
              ],
            ),
    );
  }
}

class _RecentlyActiveRow extends StatelessWidget {
  final AdminBusiness business;
  const _RecentlyActiveRow({required this.business});

  @override
  Widget build(BuildContext context) {
    final isPro = business.isProEffective;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _InitialAvatar(name: business.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AdminColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _titleCase(business.businessType),
                  style: const TextStyle(color: AdminColors.inkMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ProBadge(isPro: isPro),
              const SizedBox(height: 4),
              Text(_relativeTime(business.lastSaleAt), style: const TextStyle(color: AdminColors.inkFaint, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NeedsAttentionSection extends StatelessWidget {
  final List<AdminBusiness> businesses;
  const _NeedsAttentionSection({required this.businesses});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.warning_amber_rounded,
      iconColor: AdminColors.amber,
      iconBg: AdminColors.amberSoft,
      title: 'Needs attention',
      subtitle: 'Pro lapsed in the last 14 days',
      child: businesses.isEmpty
          ? const _InlineEmpty(
              icon: Icons.check_circle_outline_rounded,
              text: 'No recently-lapsed Pro subscribers.',
            )
          : Column(
              children: [
                for (int i = 0; i < businesses.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AdminColors.border),
                  _NeedsAttentionRow(business: businesses[i]),
                ],
              ],
            ),
    );
  }
}

class _NeedsAttentionRow extends StatelessWidget {
  final AdminBusiness business;
  const _NeedsAttentionRow({required this.business});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _InitialAvatar(name: business.name, color: AdminColors.amber, bg: AdminColors.amberSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AdminColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Pro lapsed ${_relativeTime(business.proExpiry)}',
                  style: const TextStyle(color: AdminColors.inkMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, color: iconColor, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AdminColors.ink)),
                      Text(subtitle, style: const TextStyle(color: AdminColors.inkFaint, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String value;
  final String label;
  final String sublabel;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.bg,
    required this.value,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 19),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: AdminTheme.heading(22)),
                ),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(color: AdminColors.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text(sublabel, style: const TextStyle(color: AdminColors.inkFaint, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  final bool isPro;
  const _ProBadge({required this.isPro});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPro ? AdminColors.violetSoft : AdminColors.surfaceSunken,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPro ? AdminColors.violet.withValues(alpha: 0.35) : AdminColors.border),
      ),
      child: Text(
        isPro ? 'PRO' : 'FREE',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: isPro ? AdminColors.violet : AdminColors.inkMuted),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final Color bg;
  const _InitialAvatar({required this.name, this.color = AdminColors.accent, this.bg = AdminColors.accentSoft});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String text;
  final IconData icon;
  const _InlineEmpty({required this.text, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AdminColors.inkFaint),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12.5))),
        ],
      ),
    );
  }
}

/// Full-bleed placeholder for loading / error / empty states — always with
/// an icon and a message, never a bare spinner with no context.
class _StateMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final bool showSpinner;

  const _StateMessage({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 26),
              ),
            const SizedBox(height: 16),
            Text(title, style: AdminTheme.heading(16), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12.5), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Local formatting helpers — no shared MoneyFormatter/relative-time util
// exists in this project yet, so these stay private to this screen.
// ---------------------------------------------------------------------

final NumberFormat _decimal = NumberFormat.decimalPattern('en_IN');
final NumberFormat _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String _formatPaise(int paise) => _currency.format(paise / 100);

/// Chart-axis-friendly compact form ("₹1.2K", "₹45"), since the full
/// comma-grouped `_formatPaise` output is too wide for a Y-axis label.
String _formatPaiseCompact(int paise) {
  final rupees = paise / 100.0;
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) return '₹${(rupees / 1000).toStringAsFixed(1)}K';
  return '₹${rupees.toStringAsFixed(0)}';
}

String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _relativeTime(DateTime? dt) {
  if (dt == null) return 'No sales yet';
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}
