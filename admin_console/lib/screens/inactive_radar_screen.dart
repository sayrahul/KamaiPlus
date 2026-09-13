import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import 'merchant_detail_screen.dart';

class InactiveRadarScreen extends StatefulWidget {
  const InactiveRadarScreen({super.key});

  @override
  State<InactiveRadarScreen> createState() => _InactiveRadarScreenState();
}

class _InactiveRadarScreenState extends State<InactiveRadarScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'all'; // 'all', 'never_billed', 'dormant_7d', 'dormant_30d'

  final DateFormat _dateFmt = DateFormat('dd MMM yyyy');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openWhatsApp(AdminBusiness b) {
    var phone = b.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 10) phone = '91$phone';

    String greeting;
    if (b.isNeverBilled) {
      greeting = 'Namaste ${b.ownerName.isNotEmpty ? b.ownerName : b.name} ji! 🙏\n\n'
          'KamaiPlus POS me aapka swagat hai. Humne dekha aapka store "${b.name}" register ho chuka hai. '
          'Kya aapko dukan ka pehla bill banane ya products add karne me koi help ya live demo chahiye? '
          'Aapka business badhana hamara lakshya hai — hume yahan reply karein, hum turant call par assist karenge!';
    } else {
      greeting = 'Namaste ${b.ownerName.isNotEmpty ? b.ownerName : b.name} ji! 🙏\n\n'
          'Humne notice kiya ki aapke store "${b.name}" par pichle kuch dino se billing nahi hui hai. '
          'KamaiPlus ke naye release me Counter UPI QR, tez billing aur stock matrix add ho chuka hai. '
          'Kya aapko app chalane me koi samasya aa rahi hai? Hum aapki madad ke liye taiyar hain!';
    }

    final url = 'https://wa.me/$phone?text=${Uri.encodeComponent(greeting)}';
    html.window.open(url, '_blank');
  }

  void _makeCall(AdminBusiness b) {
    var phone = b.phone.replaceAll(RegExp(r'[^0-9]'), '');
    html.window.open('tel:$phone', '_self');
  }

  List<AdminBusiness> _filterList(List<AdminBusiness> all) {
    // Keep only genuinely inactive businesses
    final inactives = all.where((b) {
      if (b.isDisabled) return false;
      return b.isNeverBilled || b.isDormant7Days || b.isDormant30Days;
    }).toList();

    // Specific category filter
    final categoryFiltered = inactives.where((b) {
      switch (_filter) {
        case 'never_billed':
          return b.isNeverBilled;
        case 'dormant_7d':
          return b.isDormant7Days && !b.isDormant30Days;
        case 'dormant_30d':
          return b.isDormant30Days;
        default:
          return true;
      }
    }).toList();

    // Query filter
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return categoryFiltered;

    return categoryFiltered.where((b) {
      return b.name.toLowerCase().contains(q) ||
          b.ownerName.toLowerCase().contains(q) ||
          b.phone.toLowerCase().contains(q) ||
          b.businessType.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bgDark,
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

            final all = snapshot.data!;
            final neverBilled = all.where((b) => !b.isDisabled && b.isNeverBilled).toList();
            final dormant7d = all.where((b) => !b.isDisabled && b.isDormant7Days && !b.isDormant30Days).toList();
            final dormant30d = all.where((b) => !b.isDisabled && b.isDormant30Days).toList();
            final totalInactive = neverBilled.length + dormant7d.length + dormant30d.length;

            final visible = _filterList(all);

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
                          color: AdminColors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AdminColors.red.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.radar_rounded, color: AdminColors.red, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Inactive Merchant Radar & Drop-off Recovery', style: AdminTheme.heading(22)),
                          const SizedBox(height: 2),
                          const Text(
                            'Detect dropped-off signups, dormant stores, and trigger 1-click WhatsApp re-engagement.',
                            style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 4 Summary Metric Cards
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 1080 ? 4 : (constraints.maxWidth >= 600 ? 2 : 1);
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: cols == 4 ? 2.3 : 2.8,
                        children: [
                          _buildMetricCard(
                            title: 'Total Inactive Stores',
                            value: totalInactive.toString(),
                            subtitle: 'Drop-off & churn risk',
                            color: AdminColors.red,
                            bgColor: AdminColors.red.withValues(alpha: 0.12),
                            icon: Icons.person_off_rounded,
                            active: _filter == 'all',
                            onTap: () => setState(() => _filter = 'all'),
                          ),
                          _buildMetricCard(
                            title: '0 Bills Ever (Drop-off)',
                            value: neverBilled.length.toString(),
                            subtitle: 'Signed up, never created a bill',
                            color: const Color(0xFFEF4444),
                            bgColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            icon: Icons.receipt_long_outlined,
                            active: _filter == 'never_billed',
                            onTap: () => setState(() => _filter = 'never_billed'),
                          ),
                          _buildMetricCard(
                            title: 'Dormant (7 - 30 Days)',
                            value: dormant7d.length.toString(),
                            subtitle: 'No sale in the last week',
                            color: AdminColors.amber,
                            bgColor: AdminColors.amber.withValues(alpha: 0.12),
                            icon: Icons.hourglass_empty_rounded,
                            active: _filter == 'dormant_7d',
                            onTap: () => setState(() => _filter = 'dormant_7d'),
                          ),
                          _buildMetricCard(
                            title: 'Dormant (30+ Days)',
                            value: dormant30d.length.toString(),
                            subtitle: 'Inactive for over a month',
                            color: AdminColors.violet,
                            bgColor: AdminColors.violet.withValues(alpha: 0.12),
                            icon: Icons.event_busy_rounded,
                            active: _filter == 'dormant_30d',
                            onTap: () => setState(() => _filter = 'dormant_30d'),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Search Bar & Filter Tabs
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AdminColors.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.borderDark),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
                            onChanged: (val) => setState(() => _query = val),
                            decoration: InputDecoration(
                              hintText: 'Search inactive merchants by store name, owner, or phone…',
                              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textFaint),
                              fillColor: AdminColors.bgSidebar,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AdminColors.textFaint),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _query = '';
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Inactive Merchants List
                  if (visible.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AdminColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.border),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 48, color: AdminColors.accent),
                          const SizedBox(height: 12),
                          Text('No dropped-off merchants found in this filter!', style: AdminTheme.heading(16)),
                          const SizedBox(height: 4),
                          const Text('All merchants in this view are actively generating bills.', style: TextStyle(color: AdminColors.inkMuted)),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final b = visible[index];
                        return _buildMerchantCard(b);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? color : AdminColors.borderDark, width: active ? 1.8 : 1),
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AdminColors.textMuted), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantCard(AdminBusiness b) {
    String badgeText;
    Color badgeColor;
    Color badgeBg;

    if (b.isNeverBilled) {
      badgeText = '0 BILLS (DROP-OFF)';
      badgeColor = const Color(0xFFEF4444);
      badgeBg = const Color(0xFFEF4444).withValues(alpha: 0.15);
    } else if (b.isDormant30Days) {
      badgeText = 'DORMANT 30+ DAYS';
      badgeColor = AdminColors.violet;
      badgeBg = AdminColors.violet.withValues(alpha: 0.15);
    } else {
      badgeText = 'SLIPPING (7+ DAYS)';
      badgeColor = AdminColors.amber;
      badgeBg = AdminColors.amber.withValues(alpha: 0.15);
    }

    final lastActiveStr = b.lastSaleAt != null
        ? 'Last sale: ${_dateFmt.format(b.lastSaleAt!)} (${b.daysSinceLastActive}d ago)'
        : (b.createdAt != null ? 'Joined: ${_dateFmt.format(b.createdAt!)} (${b.daysSinceSignup}d ago)' : 'No activity recorded');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.borderDark, width: 1.1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with Name and Inactivity Badge
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(b.name, style: AdminTheme.heading(16)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AdminColors.bgElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AdminColors.borderDark),
                          ),
                          child: Text(
                            b.businessType.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${b.ownerName.isNotEmpty ? b.ownerName : 'Store Owner'} • 📞 ${b.phone}',
                      style: const TextStyle(color: AdminColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AdminColors.borderDark),
          const SizedBox(height: 12),

          // Metadata & Re-engagement Action Bar
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 15, color: AdminColors.textFaint),
              const SizedBox(width: 6),
              Text(lastActiveStr, style: const TextStyle(fontSize: 12, color: AdminColors.textMuted)),
              const Spacer(),

              // Direct WhatsApp Re-engagement CTA
              ElevatedButton.icon(
                onPressed: () => _openWhatsApp(b),
                icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                label: const Text('WhatsApp Re-engage'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366), // Official WhatsApp Green
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 8),

              // Direct Phone Call CTA
              OutlinedButton.icon(
                onPressed: () => _makeCall(b),
                icon: const Icon(Icons.call_rounded, size: 15, color: AdminColors.textWhite),
                label: const Text('Call', style: TextStyle(color: AdminColors.textWhite)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AdminColors.borderDark),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),

              // View Store Details
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AdminColors.textFaint),
                tooltip: 'View Full Store Profile',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MerchantDetailScreen(business: b)),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
