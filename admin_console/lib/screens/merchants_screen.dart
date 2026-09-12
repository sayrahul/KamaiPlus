import 'dart:convert';
import 'dart:html' as html;

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'merchant_detail_screen.dart';

/// Groups a whole-rupee digit string the Indian way (last 3 digits, then
/// pairs): "1234568" -> "12,34,568".
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

/// Formats a paise integer as a rupee string, e.g. `123456` paise -> `₹1,235`
/// (rounded to the nearest rupee — this project has no shared currency
/// formatter, so this small helper is carried locally by every screen that
/// needs one).
String _formatPaise(int paise) {
  final rupees = (paise / 100).round();
  final sign = rupees < 0 ? '-' : '';
  return '$sign₹${_indianGroup(rupees.abs().toString())}';
}

String _titleCase(String s) {
  if (s.isEmpty) return s;
  return s
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

enum _SortBy { name, sales, revenue, lastSale }

/// Merchant directory: every business in one searchable, sortable table.
/// Tapping a row drills into [MerchantDetailScreen].
class MerchantsScreen extends StatefulWidget {
  const MerchantsScreen({super.key});

  @override
  State<MerchantsScreen> createState() => _MerchantsScreenState();
}

class _MerchantsScreenState extends State<MerchantsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _SortBy _sortBy = _SortBy.lastSale;
  bool _sortAsc = false;
  // A ValueNotifier, not a plain field: Scaffold evaluates its `appBar`
  // argument before `body` runs the StreamBuilder that computes the
  // visible list, so a plain field read by the export button would show
  // stale (disabled) data for a full extra render. The button listens to
  // this directly instead, so it updates the moment the list is known,
  // independent of Scaffold's argument-evaluation order.
  final _visibleNotifier = ValueNotifier<List<AdminBusiness>>([]);

  @override
  void dispose() {
    _searchCtrl.dispose();
    _visibleNotifier.dispose();
    super.dispose();
  }

  List<AdminBusiness> _filterAndSort(List<AdminBusiness> all) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<AdminBusiness>.of(all)
        : all
              .where(
                (b) =>
                    b.name.toLowerCase().contains(q) ||
                    b.ownerName.toLowerCase().contains(q) ||
                    b.phone.toLowerCase().contains(q),
              )
              .toList();

    int cmp(AdminBusiness a, AdminBusiness b) {
      switch (_sortBy) {
        case _SortBy.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortBy.sales:
          return a.totalSalesCount.compareTo(b.totalSalesCount);
        case _SortBy.revenue:
          return a.totalRevenuePaise.compareTo(b.totalRevenuePaise);
        case _SortBy.lastSale:
          return (a.lastSaleAt ?? DateTime(2000)).compareTo(
            b.lastSaleAt ?? DateTime(2000),
          );
      }
    }

    filtered.sort(cmp);
    if (!_sortAsc) return filtered.reversed.toList();
    return filtered;
  }

  int get _sortColumnIndex {
    switch (_sortBy) {
      case _SortBy.name:
        return 0;
      case _SortBy.sales:
        return 5;
      case _SortBy.revenue:
        return 6;
      case _SortBy.lastSale:
        return 7;
    }
  }

  void _onSort(_SortBy by, bool ascending) {
    setState(() {
      _sortBy = by;
      _sortAsc = ascending;
    });
  }

  /// Downloads the currently visible (filtered/sorted) merchant list as a
  /// CSV — `dart:html` directly, not a plugin, since this project only
  /// ever targets Web and a Blob + anchor-click download needs nothing
  /// more than that.
  void _exportCsv(List<AdminBusiness> rows) {
    final dateFmt = DateFormat('d MMM yyyy');
    final data = [
      [
        'Name',
        'Owner',
        'Phone',
        'Email',
        'Business Type',
        'Pro Status',
        'Plan',
        'Pro Expiry',
        'Bills',
        'Revenue (INR)',
        'Last Sale',
        'Coupon Used',
      ],
      for (final b in rows)
        [
          b.name,
          b.ownerName,
          b.phone,
          b.email,
          b.businessType,
          b.isProEffective ? 'Pro' : (b.isPro ? 'Expired' : 'Free'),
          b.proPlan,
          b.proExpiry != null ? dateFmt.format(b.proExpiry!) : '',
          b.totalSalesCount,
          (b.totalRevenuePaise / 100).toStringAsFixed(2),
          b.lastSaleAt != null ? dateFmt.format(b.lastSaleAt!) : '',
          b.couponCodeUsed ?? '',
        ],
    ];
    final csv = const ListToCsvConverter().convert(data);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'kamaiplus_merchants_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      )
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    // No own Scaffold/AppBar — this is a shell tab (AdminShell owns the top
    // chrome consistently across all four), not a pushed route. The title +
    // CSV-export action live in an in-body header instead, matching
    // coupons_screen.dart's own pattern.
    return Padding(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<List<AdminBusiness>>(
        stream: AdminFirestoreService.instance.watchBusinesses(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.error_outline_rounded,
              color: AdminColors.red,
              title: 'Could not load merchants',
              subtitle: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const _MessageState(
              icon: Icons.hourglass_top_rounded,
              color: AdminColors.inkFaint,
              title: 'Loading merchants…',
              subtitle: 'Fetching the merchant directory from Firestore.',
              loading: true,
            );
          }

          final all = snapshot.data!;
          if (all.isEmpty) {
            return const _MessageState(
              icon: Icons.storefront_outlined,
              color: AdminColors.inkFaint,
              title: 'No merchants yet',
              subtitle:
                  'Businesses appear here as soon as they sync from the app.',
            );
          }

          final visible = _filterAndSort(all);
          final proCount = all.where((b) => b.isProEffective).length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _visibleNotifier.value = visible;
          });

          final searchField = TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search by name, owner, or phone',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() {
                        _searchCtrl.clear();
                        _query = '';
                      }),
                    ),
            ),
          );
          final statChips = [
            _StatChip(label: 'Merchants', value: '${all.length}'),
            const SizedBox(width: 8),
            _StatChip(
              label: 'Pro',
              value: '$proCount',
              color: AdminColors.accent,
              bg: AdminColors.accentSoft,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title/subtitle + CSV export — no own AppBar (see
              // build()'s top comment), so this is the screen's only chrome.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Merchants', style: AdminTheme.heading(22)),
                        const SizedBox(height: 2),
                        const Text(
                          'Every store synced from the app, searchable and exportable.',
                          style: TextStyle(
                            color: AdminColors.inkMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Export visible list as CSV',
                    icon: const Icon(Icons.download_rounded),
                    onPressed: visible.isEmpty
                        ? null
                        : () => _exportCsv(visible),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Search + stat chips — stacked on narrow width instead of
              // squeezing three things into one row.
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        searchField,
                        const SizedBox(height: 10),
                        Row(children: statChips),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 16),
                      ...statChips,
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                _query.isEmpty
                    ? 'Showing all ${visible.length} merchants'
                    : 'Showing ${visible.length} of ${all.length} merchants',
                style: const TextStyle(
                  color: AdminColors.inkMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visible.isEmpty
                    ? _MessageState(
                        icon: Icons.search_off_rounded,
                        color: AdminColors.inkFaint,
                        title: 'No merchants match "$_query"',
                        subtitle:
                            'Try a different name, owner, or phone number.',
                      )
                    : LayoutBuilder(
                        builder: (context, outer) {
                          // Below ~700px an 8-column table is unreadable
                          // even with horizontal scroll — a phone user
                          // wants to scan merchants, not pan a table. Swap
                          // to a card list instead of just shrinking it.
                          if (outer.maxWidth < 700) {
                            return ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) =>
                                  _MerchantCard(business: visible[i]),
                            );
                          }
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            margin: EdgeInsets.zero,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: constraints.maxWidth,
                                      ),
                                      child: DataTable(
                                        sortColumnIndex: _sortColumnIndex,
                                        sortAscending: _sortAsc,
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                              AdminColors.surfaceSunken,
                                            ),
                                        columns: [
                                          DataColumn(
                                            label: const Text('Business'),
                                            onSort: (_, asc) =>
                                                _onSort(_SortBy.name, asc),
                                          ),
                                          const DataColumn(
                                            label: Text('Owner'),
                                          ),
                                          const DataColumn(
                                            label: Text('Phone'),
                                          ),
                                          const DataColumn(label: Text('Type')),
                                          const DataColumn(label: Text('Plan')),
                                          DataColumn(
                                            label: const Text('Sales'),
                                            numeric: true,
                                            onSort: (_, asc) =>
                                                _onSort(_SortBy.sales, asc),
                                          ),
                                          DataColumn(
                                            label: const Text('Revenue'),
                                            numeric: true,
                                            onSort: (_, asc) =>
                                                _onSort(_SortBy.revenue, asc),
                                          ),
                                          DataColumn(
                                            label: const Text('Last sale'),
                                            onSort: (_, asc) =>
                                                _onSort(_SortBy.lastSale, asc),
                                          ),
                                        ],
                                        rows: [
                                          for (final b in visible)
                                            DataRow(
                                              onSelectChanged: (_) =>
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          MerchantDetailScreen(
                                                            business: b,
                                                          ),
                                                    ),
                                                  ),
                                              cells: [
                                                DataCell(
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        b.name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      if (b.isDisabled) ...[
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        const _DisabledBadge(),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    b.ownerName.isEmpty
                                                        ? '—'
                                                        : b.ownerName,
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    b.phone.isEmpty
                                                        ? '—'
                                                        : b.phone,
                                                  ),
                                                ),
                                                DataCell(
                                                  _TypeChip(
                                                    type: b.businessType,
                                                  ),
                                                ),
                                                DataCell(
                                                  _ProBadge(business: b),
                                                ),
                                                DataCell(
                                                  Text(
                                                    '${b.totalSalesCount}',
                                                    style: AdminTheme.mono(13),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _formatPaise(
                                                      b.totalRevenuePaise,
                                                    ),
                                                    style: AdminTheme.mono(13),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    b.lastSaleAt == null
                                                        ? '—'
                                                        : DateFormat(
                                                            'd MMM yyyy',
                                                          ).format(
                                                            b.lastSaleAt!,
                                                          ),
                                                    style: const TextStyle(
                                                      color:
                                                          AdminColors.inkMuted,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Narrow-width stand-in for a `DataTable` row: same fields, laid out as a
/// tappable card instead of columns that would otherwise get crushed or
/// force horizontal scrolling on a phone.
class _MerchantCard extends StatelessWidget {
  final AdminBusiness business;
  const _MerchantCard({required this.business});

  @override
  Widget build(BuildContext context) {
    final b = business;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MerchantDetailScreen(business: b)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (b.isDisabled) ...[
                    const _DisabledBadge(),
                    const SizedBox(width: 6),
                  ],
                  _ProBadge(business: b),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (b.ownerName.isNotEmpty) b.ownerName,
                  if (b.phone.isNotEmpty) b.phone,
                ].join(' · '),
                style: const TextStyle(
                  color: AdminColors.inkMuted,
                  fontSize: 12.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _TypeChip(type: b.businessType),
                  const Spacer(),
                  Text(
                    b.lastSaleAt == null
                        ? '—'
                        : DateFormat('d MMM yyyy').format(b.lastSaleAt!),
                    style: const TextStyle(
                      color: AdminColors.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _MerchantCardStat(
                      label: 'Bills',
                      value: '${b.totalSalesCount}',
                    ),
                  ),
                  Expanded(
                    child: _MerchantCardStat(
                      label: 'Revenue',
                      value: _formatPaise(b.totalRevenuePaise),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MerchantCardStat extends StatelessWidget {
  final String label;
  final String value;
  const _MerchantCardStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AdminColors.inkFaint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: AdminTheme.mono(14)),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bg;
  const _StatChip({
    required this.label,
    required this.value,
    this.color = AdminColors.ink,
    this.bg = AdminColors.surfaceSunken,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AdminColors.violetSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _titleCase(type),
        style: const TextStyle(
          color: AdminColors.violet,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Small pill showing a business's Pro/Free status — reused as-is by the
/// merchant detail header.
/// Flags a merchant an admin has kicked out via the kill-switch
/// (merchant_detail_screen.dart's Disable action) — shown wherever a
/// merchant's name appears in the directory so this doesn't stay hidden
/// behind a detail-page click.
class _DisabledBadge extends StatelessWidget {
  const _DisabledBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AdminColors.redSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AdminColors.red.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'DISABLED',
        style: TextStyle(color: AdminColors.red, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  final AdminBusiness business;
  const _ProBadge({required this.business});

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    final String label;
    if (business.isProEffective) {
      fg = AdminColors.accent;
      bg = AdminColors.accentSoft;
      label = 'PRO';
    } else if (business.isPro) {
      fg = AdminColors.amber;
      bg = AdminColors.amberSoft;
      label = 'EXPIRED';
    } else {
      fg = AdminColors.inkMuted;
      bg = AdminColors.surfaceSunken;
      label = 'FREE';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: fg.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (business.isProEffective && business.proExpiry != null) ...[
          const SizedBox(height: 3),
          Text(
            'until ${DateFormat('d MMM yyyy').format(business.proExpiry!)}',
            style: const TextStyle(color: AdminColors.inkFaint, fontSize: 10.5),
          ),
        ],
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool loading;
  const _MessageState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(icon, size: 40, color: color),
          const SizedBox(height: 14),
          Text(title, style: AdminTheme.heading(15)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
