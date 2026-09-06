import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/money_formatter.dart';
import '../common/kamai_bottom_nav.dart';
import 'ai_inward_sheet.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All' | 'Received' | 'In-Transit' | 'Udhar Due'
  final TextEditingController _searchCtrl = TextEditingController();

  // Inward Purchase Orders state (Money invariant: integer paise)
  final List<Map<String, dynamic>> _purchases = [
    {
      'id': 'PO-1084',
      'invoice_no': 'METRO-9821',
      'supplier': 'Metro Cash & Carry India',
      'category': 'FMCG & Staples Wholesale',
      'phone': '+919820011223',
      'date': DateTime.now().subtract(const Duration(days: 1)),
      'expected_date': null,
      'amount_paise': 3425000, // ₹34,250.00
      'due_paise': 0, // Paid
      'payment_status': 'Paid (Bank)',
      'status': 'Received',
      'items_count': 18,
      'items': [
        {'name': 'Aashirvaad Shudh Chakki Atta (10kg)', 'qty': 15, 'unit': 'bag', 'rate_paise': 38000, 'total_paise': 570000},
        {'name': 'Fortune Sunlite Sunflower Oil (1L)', 'qty': 48, 'unit': 'bottle', 'rate_paise': 12500, 'total_paise': 600000},
        {'name': 'Tata Sampann Toor Dal Premium (1kg)', 'qty': 30, 'unit': 'pkt', 'rate_paise': 14000, 'total_paise': 420000},
        {'name': 'Madhur Pure & Hygienic Sugar (5kg)', 'qty': 20, 'unit': 'bag', 'rate_paise': 21000, 'total_paise': 420000},
        {'name': 'India Gate Basmati Rice Classic (5kg)', 'qty': 12, 'unit': 'bag', 'rate_paise': 54000, 'total_paise': 648000},
        {'name': 'Everest Turmeric / Haldi Powder (500g)', 'qty': 24, 'unit': 'pkt', 'rate_paise': 11500, 'total_paise': 276000},
        {'name': 'Tata Salt Vacuum Evaporated (1kg)', 'qty': 50, 'unit': 'pkt', 'rate_paise': 2100, 'total_paise': 105000},
        {'name': 'Colgate Strong Teeth Toothpaste (200g)', 'qty': 24, 'unit': 'pcs', 'rate_paise': 8500, 'total_paise': 204000},
      ],
    },
    {
      'id': 'PO-1083',
      'invoice_no': 'HUL-BOM-4412',
      'supplier': 'Hindustan Unilever Distributor',
      'category': 'Personal & Home Care',
      'phone': '+919819922334',
      'date': DateTime.now().subtract(const Duration(days: 3)),
      'expected_date': null,
      'amount_paise': 1860000, // ₹18,600.00
      'due_paise': 1860000, // Full credit due
      'payment_status': 'Credit (Udhar)',
      'status': 'Received',
      'items_count': 12,
      'items': [
        {'name': 'Surf Excel Easy Wash Detergent (1kg)', 'qty': 36, 'unit': 'pkt', 'rate_paise': 13000, 'total_paise': 468000},
        {'name': 'Dove Deeply Nourishing Soap (100g x 3)', 'qty': 24, 'unit': 'pack', 'rate_paise': 16500, 'total_paise': 396000},
        {'name': 'Red Label Strong Tea Leaf (500g)', 'qty': 30, 'unit': 'pkt', 'rate_paise': 21000, 'total_paise': 630000},
        {'name': 'Clinic Plus Strong Health Shampoo (340ml)', 'qty': 18, 'unit': 'bottle', 'rate_paise': 15000, 'total_paise': 270000},
        {'name': 'Vim Lemon Dishwash Bar (300g)', 'qty': 48, 'unit': 'pcs', 'rate_paise': 2000, 'total_paise': 96000},
      ],
    },
    {
      'id': 'PO-1082',
      'invoice_no': 'PARLE-AG-8819',
      'supplier': 'Parle & Britannia Agencies',
      'category': 'Biscuits & Confectionery',
      'phone': '+919867733445',
      'date': DateTime.now(),
      'expected_date': DateTime.now().add(const Duration(days: 1)),
      'amount_paise': 840000, // ₹8,400.00
      'due_paise': 340000, // Partial due ₹3,400.00
      'payment_status': 'Partial Due',
      'status': 'In-Transit',
      'items_count': 7,
      'items': [
        {'name': 'Parle-G Gold Biscuits (1kg family pack)', 'qty': 40, 'unit': 'pkt', 'rate_paise': 9000, 'total_paise': 360000},
        {'name': 'Britannia Good Day Butter (600g pack)', 'qty': 24, 'unit': 'pkt', 'rate_paise': 11000, 'total_paise': 264000},
        {'name': 'Parle Krackjack Sweet & Salty (400g)', 'qty': 20, 'unit': 'pkt', 'rate_paise': 6500, 'total_paise': 130000},
        {'name': 'Britannia Marie Gold Tea Biscuits (250g)', 'qty': 28, 'unit': 'pkt', 'rate_paise': 3100, 'total_paise': 86000},
      ],
    },
    {
      'id': 'PO-1081',
      'invoice_no': 'ITC-WHS-2201',
      'supplier': 'ITC Wholesale Foods Distributor',
      'category': 'Snacks & Packaged Foods',
      'phone': '+919833344556',
      'date': DateTime.now().subtract(const Duration(days: 6)),
      'expected_date': null,
      'amount_paise': 1490000, // ₹14,900.00
      'due_paise': 0, // Paid
      'payment_status': 'Paid (Cash)',
      'status': 'Received',
      'items_count': 9,
      'items': [
        {'name': 'Sunfeast Dark Fantasy Choco Fills (300g)', 'qty': 30, 'unit': 'box', 'rate_paise': 12000, 'total_paise': 360000},
        {'name': 'Bingo Tedhe Medhe Masala (90g x 10)', 'qty': 20, 'unit': 'pack', 'rate_paise': 17000, 'total_paise': 340000},
        {'name': 'Aashirvaad Pure Cow Ghee (1L Ceka pack)', 'qty': 10, 'unit': 'pack', 'rate_paise': 62000, 'total_paise': 620000},
        {'name': 'Sunfeast Mom’s Magic Cashew & Almond', 'qty': 25, 'unit': 'pkt', 'rate_paise': 6800, 'total_paise': 170000},
      ],
    },
    {
      'id': 'PO-1080',
      'invoice_no': 'NESTLE-IND-674',
      'supplier': 'Nestlé Distribution Hub',
      'category': 'Dairy & Instant Foods',
      'phone': '+919892255667',
      'date': DateTime.now().subtract(const Duration(days: 2)),
      'expected_date': DateTime.now().add(const Duration(days: 2)),
      'amount_paise': 2280000, // ₹22,800.00
      'due_paise': 2280000, // Full credit due
      'payment_status': 'Credit (Udhar)',
      'status': 'In-Transit',
      'items_count': 15,
      'items': [
        {'name': 'Maggi 2-Minute Masala Noodles (70g x 12)', 'qty': 35, 'unit': 'pack', 'rate_paise': 14400, 'total_paise': 504000},
        {'name': 'Nescafé Classic Instant Coffee Jar (100g)', 'qty': 20, 'unit': 'jar', 'rate_paise': 31000, 'total_paise': 620000},
        {'name': 'Nestlé Everyday Dairy Whitener (1kg)', 'qty': 15, 'unit': 'pkt', 'rate_paise': 45000, 'total_paise': 675000},
        {'name': 'Nestlé Milkmaid Sweetened Condensed Milk', 'qty': 24, 'unit': 'can', 'rate_paise': 13000, 'total_paise': 312000},
        {'name': 'Maggi Hot & Sweet Tomato Chilli Sauce', 'qty': 20, 'unit': 'bottle', 'rate_paise': 8400, 'total_paise': 168000},
      ],
    },
    {
      'id': 'PO-1079',
      'invoice_no': 'DABUR-STK-091',
      'supplier': 'Dabur India Stockist',
      'category': 'Ayurvedic & Healthcare',
      'phone': '+919821177889',
      'date': DateTime.now().subtract(const Duration(days: 10)),
      'expected_date': null,
      'amount_paise': 675000, // ₹6,750.00
      'due_paise': 0, // Paid
      'payment_status': 'Paid (UPI)',
      'status': 'Received',
      'items_count': 5,
      'items': [
        {'name': 'Dabur Red Toothpaste Ayurvedic (300g)', 'qty': 24, 'unit': 'pcs', 'rate_paise': 11500, 'total_paise': 276000},
        {'name': 'Dabur Chyawanprash Immunity (1kg jar)', 'qty': 8, 'unit': 'jar', 'rate_paise': 34000, 'total_paise': 272000},
        {'name': 'Dabur 100% Pure Honey Squeezy (250g)', 'qty': 12, 'unit': 'bottle', 'rate_paise': 10500, 'total_paise': 126000},
      ],
    },
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Filtered purchases
  List<Map<String, dynamic>> get _filteredPurchases {
    return _purchases.where((p) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchSup = (p['supplier'] as String).toLowerCase().contains(query);
        final matchId = (p['id'] as String).toLowerCase().contains(query);
        final matchInv = ((p['invoice_no'] as String?) ?? '').toLowerCase().contains(query);
        bool matchItem = false;
        final items = p['items'] as List<dynamic>? ?? [];
        for (final it in items) {
          if ((it['name'] as String).toLowerCase().contains(query)) {
            matchItem = true;
            break;
          }
        }
        if (!matchSup && !matchId && !matchInv && !matchItem) return false;
      }

      if (_selectedFilter == 'Received' && p['status'] != 'Received') return false;
      if (_selectedFilter == 'In-Transit' && p['status'] != 'In-Transit') return false;
      if (_selectedFilter == 'Udhar Due' && (p['due_paise'] as int) <= 0) return false;

      return true;
    }).toList();
  }

  // Summary Aggregates (Strict integer paise math)
  int get _totalPurchasesPaise => _purchases.fold(0, (sum, p) => sum + (p['amount_paise'] as int));
  int get _totalDuePaise => _purchases.fold(0, (sum, p) => sum + (p['due_paise'] as int));
  int get _receivedOrdersCount => _purchases.where((p) => p['status'] == 'Received').length;
  int get _inTransitOrdersCount => _purchases.where((p) => p['status'] == 'In-Transit').length;
  int get _creditOrdersCount => _purchases.where((p) => (p['due_paise'] as int) > 0).length;

  void _openAiBillScanner() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiInwardSheet(
        onInwardComplete: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Wholesale bill products updated into inventory!'),
                ],
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
      ),
    );
  }

  void _openWhatsAppSupplier(Map<String, dynamic> purchase) async {
    HapticFeedback.selectionClick();
    final phone = purchase['phone'] as String? ?? '';
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final sup = purchase['supplier'];
    final id = purchase['id'];
    final due = purchase['due_paise'] as int;
    final total = purchase['amount_paise'] as int;

    String msg;
    if (due > 0) {
      msg = 'Namaste $sup ji, regarding PO $id (Total: ${MoneyFormatter.formatINR(total)}). Outstanding payment of ${MoneyFormatter.formatINR(due)} is acknowledged and will be processed. - Sent via KamaiPlus';
    } else {
      msg = 'Namaste $sup ji, regarding PO $id (Total: ${MoneyFormatter.formatINR(total)}). Stock inward received and settled. Thank you! - Sent via KamaiPlus';
    }

    final encoded = Uri.encodeComponent(msg);
    final uri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encoded');
    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encoded');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch WhatsApp')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp application not found')),
        );
      }
    }
  }

  void _showOrderDetailsSheet(Map<String, dynamic> purchase) {
    HapticFeedback.selectionClick();
    final items = purchase['items'] as List<dynamic>? ?? [];
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(purchase['date'] as DateTime);
    final duePaise = purchase['due_paise'] as int;
    final totalPaise = purchase['amount_paise'] as int;
    final isReceived = purchase['status'] == 'Received';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Top Handle
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                ),

                // Sheet Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0F172A), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(purchase['id'], style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                            Text('${purchase['supplier']} • Inv #${purchase['invoice_no']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEEF2F6)),

                // Sheet Body Scrollable
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      // Status & Meta Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isReceived ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isReceived ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(isReceived ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                              size: 13, color: isReceived ? const Color(0xFF059669) : const Color(0xFFD97706)),
                                          const SizedBox(width: 4),
                                          Text(
                                            purchase['status'],
                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isReceived ? const Color(0xFF059669) : const Color(0xFFD97706)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: duePaise > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: duePaise > 0 ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
                                      ),
                                      child: Text(
                                        duePaise > 0 ? 'Due: ${MoneyFormatter.formatINR(duePaise)}' : 'Fully Paid',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: duePaise > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Contact Vendor:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569))),
                                Row(
                                  children: [
                                    Text(purchase['phone'], style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _openWhatsAppSupplier(purchase),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF25D366),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.chat_bubble_rounded, size: 12, color: Colors.white),
                                            const SizedBox(width: 4),
                                            Text('WhatsApp', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Items Table Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('INWARD ITEMS (${items.length})', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF475569), letterSpacing: 0.5)),
                          Text('Purchase Rate', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Items List
                      ...items.map((it) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFEEF2F6)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text('${items.indexOf(it) + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it['name'], style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                                    Text('${it['qty']} ${it['unit']} @ ${MoneyFormatter.formatINR(it['rate_paise'])}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                              Text(
                                MoneyFormatter.formatINR(it['total_paise']),
                                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 12),

                      // Inward Cost Summary Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Subtotal Inward Value:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                Text(MoneyFormatter.formatINR(totalPaise), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Wholesale GST Tax Included:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                Text('Included', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
                              ],
                            ),
                            const Divider(height: 16, color: Color(0xFFCBD5E1)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Grand Inward Total:', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                                Text(MoneyFormatter.formatINR(totalPaise), style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Sheet Bottom Sticky Actions
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, -4))],
                  ),
                  child: Row(
                    children: [
                      if (!isReceived) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              setState(() {
                                purchase['status'] = 'Received';
                              });
                              setSheetState(() {});
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('✓ ${purchase['id']} marked as Received into Stock!')),
                              );
                            },
                            icon: const Icon(Icons.done_all_rounded, size: 16),
                            label: Text('Mark Inward Received', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (duePaise > 0) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showSettlePaymentSheet(purchase);
                            },
                            icon: const Icon(Icons.payment_rounded, size: 16),
                            label: Text('Pay Vendor Udhar', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openWhatsAppSupplier(purchase),
                            icon: const Icon(Icons.share_rounded, size: 16),
                            label: Text('Share Inward Slip', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F172A),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettlePaymentSheet(Map<String, dynamic> purchase) {
    HapticFeedback.selectionClick();
    final duePaise = purchase['due_paise'] as int;
    final TextEditingController amountCtrl = TextEditingController(text: (duePaise / 100).toStringAsFixed(0));
    String paymentMode = 'Bank / UPI';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Record Vendor Payment', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          Text('${purchase['supplier']} • ${purchase['id']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Credit Pending:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF991B1B))),
                        Text(MoneyFormatter.formatINR(duePaise), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Payment Amount (₹)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 20, color: Color(0xFF0F172A)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildChip('Full Payment', () {
                        amountCtrl.text = (duePaise / 100).toStringAsFixed(0);
                        setModalState(() {});
                      }),
                      const SizedBox(width: 8),
                      _buildChip('50% (Half)', () {
                        amountCtrl.text = ((duePaise / 2) / 100).toStringAsFixed(0);
                        setModalState(() {});
                      }),
                      const SizedBox(width: 8),
                      _buildChip('₹5,000', () {
                        amountCtrl.text = '5000';
                        setModalState(() {});
                      }),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Payment Mode', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                  const SizedBox(height: 6),
                  Row(
                    children: ['Bank / UPI', 'Cash', 'Cheque'].map((mode) {
                      final isSel = paymentMode == mode;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => paymentMode = mode),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              mode,
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isSel ? Colors.white : const Color(0xFF475569)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final rupees = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                      final payPaise = (rupees * 100).round();
                      if (payPaise <= 0) return;

                      HapticFeedback.heavyImpact();
                      setState(() {
                        final remaining = (duePaise - payPaise).clamp(0, duePaise);
                        purchase['due_paise'] = remaining;
                        if (remaining == 0) {
                          purchase['payment_status'] = 'Paid ($paymentMode)';
                        } else {
                          purchase['payment_status'] = 'Partial Due';
                        }
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Payment of ${MoneyFormatter.formatINR(payPaise)} recorded for ${purchase['supplier']}!'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Confirm & Update Khata', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
      ),
    );
  }

  void _showCreateManualOrderSheet() {
    HapticFeedback.selectionClick();
    final supplierCtrl = TextEditingController();
    final invoiceCtrl = TextEditingController(text: 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController(text: '5');
    String status = 'Received';
    String paymentMode = 'Credit (Udhar)';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Record New Inward Bill', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        Text('Supplier / Wholesaler Name', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                        const SizedBox(height: 6),
                        TextField(
                          controller: supplierCtrl,
                          decoration: InputDecoration(
                            hintText: 'e.g. Metro Cash & Carry, Parle Agency...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Quick Supplier Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: ['Metro Wholesale', 'Hindustan Unilever', 'Parle Agency', 'Amul Dairy Agency', 'Local Mandi'].map((name) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () => setModalState(() => supplierCtrl.text = name),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(name, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Invoice / Bill #', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: invoiceCtrl,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total Inward (₹)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: amountCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: '0.00',
                                      prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 16, color: Color(0xFF0F172A)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Items Inwarded', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: itemsCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Delivery Status', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Row(
                                      children: ['Received', 'In-Transit'].map((st) {
                                        final isSel = status == st;
                                        return Expanded(
                                          child: GestureDetector(
                                            onTap: () => setModalState(() => status = st),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: isSel ? const Color(0xFF0F172A) : Colors.transparent,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                st,
                                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isSel ? Colors.white : const Color(0xFF475569)),
                                              ),
                                            ),
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
                        const SizedBox(height: 14),
                        Text('Payment Mode', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                        const SizedBox(height: 6),
                        Row(
                          children: ['Credit (Udhar)', 'Paid (Cash)', 'Paid (UPI)'].map((mode) {
                            final isSel = paymentMode == mode;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => paymentMode = mode),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    mode,
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: isSel ? Colors.white : const Color(0xFF475569)),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      final supName = supplierCtrl.text.trim();
                      if (supName.isEmpty) return;
                      final rupees = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                      final amountPaise = (rupees * 100).round();
                      final itemsCount = int.tryParse(itemsCtrl.text.trim()) ?? 1;
                      final isCredit = paymentMode.contains('Credit');

                      final newOrder = {
                        'id': 'PO-${1085 + _purchases.length}',
                        'invoice_no': invoiceCtrl.text.trim(),
                        'supplier': supName,
                        'category': 'Wholesale Inward',
                        'phone': '+919800011222',
                        'date': DateTime.now(),
                        'expected_date': status == 'In-Transit' ? DateTime.now().add(const Duration(days: 2)) : null,
                        'amount_paise': amountPaise,
                        'due_paise': isCredit ? amountPaise : 0,
                        'payment_status': paymentMode,
                        'status': status,
                        'items_count': itemsCount,
                        'items': [
                          {'name': 'Wholesale Inward Consignment', 'qty': itemsCount, 'unit': 'lots', 'rate_paise': itemsCount > 0 ? (amountPaise ~/ itemsCount) : amountPaise, 'total_paise': amountPaise}
                        ],
                      };

                      HapticFeedback.heavyImpact();
                      setState(() {
                        _purchases.insert(0, newOrder);
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Inward bill for $supName (${MoneyFormatter.formatINR(amountPaise)}) added!'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Save & Update Wholesale Inward', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPurchases;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purchases & Restock Orders',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
            ),
            Text(
              'Wholesale Inward, Stock Restock & Vendor Khata',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Record Inward Bill',
            onPressed: _showCreateManualOrderSheet,
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          // 1. Sleek Hero Hub Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEEF2F6)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Icon(Icons.inventory_2_rounded, color: Color(0xFFD97706), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Wholesale & Mandi Inward Hub',
                                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFA7F3D0)),
                                ),
                                child: Text('AI VISION', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Scan paper bills / parchas via AI Vision or record inward stock manually.',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openAiBillScanner,
                        icon: const Icon(Icons.document_scanner_rounded, size: 16),
                        label: Text('AI Bill / Parcha OCR', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showCreateManualOrderSheet,
                        icon: const Icon(Icons.post_add_rounded, size: 16),
                        label: Text('+ Manual Inward', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Supplier Udhar Status Pill & Summary Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _totalDuePaise > 0 ? const Color(0xFFFFF1F2) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _totalDuePaise > 0 ? const Color(0xFFFECDD3) : const Color(0xFFA7F3D0),
                width: 1.1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _totalDuePaise > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _totalDuePaise > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: _totalDuePaise > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            _totalDuePaise > 0 ? 'Supplier Udhar Outstanding' : 'Supplier Dues Cleared',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _totalDuePaise > 0 ? const Color(0xFF9F1239) : const Color(0xFF065F46),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _totalDuePaise > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _totalDuePaise > 0 ? '$_creditOrdersCount BILLS' : 'ALL CLEAR',
                              style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _totalDuePaise > 0
                          ? 'Total ${MoneyFormatter.formatINR(_totalDuePaise)} pending payment to wholesale vendors'
                          : 'Zero outstanding dues to all wholesale suppliers & mandi vendors',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: _totalDuePaise > 0 ? const Color(0xFFBE123C) : const Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_totalDuePaise > 0)
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedFilter = 'Udhar Due');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'View Dues',
                        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. 4-Metric Grid (Strict integer paise math & space saving)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.trending_up_rounded,
                        iconColor: const Color(0xFF2563EB),
                        iconBg: const Color(0xFFEFF6FF),
                        label: 'Total Purchases',
                        subLabel: '${_purchases.length} Orders Inwarded',
                        value: MoneyFormatter.formatINR(_totalPurchasesPaise),
                        valueColor: const Color(0xFF0F172A),
                      ),
                    ),
                    Container(width: 1, height: 48, color: const Color(0xFFF1F5F9)),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: const Color(0xFFDC2626),
                        iconBg: const Color(0xFFFEF2F2),
                        label: 'Vendor Udhar Due',
                        subLabel: '$_creditOrdersCount Pending Bills',
                        value: MoneyFormatter.formatINR(_totalDuePaise),
                        valueColor: const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.check_circle_outline_rounded,
                        iconColor: const Color(0xFF059669),
                        iconBg: const Color(0xFFECFDF5),
                        label: 'Received Stock',
                        subLabel: 'In Inventory',
                        value: '$_receivedOrdersCount Orders',
                        valueColor: const Color(0xFF0F172A),
                      ),
                    ),
                    Container(width: 1, height: 48, color: const Color(0xFFF1F5F9)),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.local_shipping_outlined,
                        iconColor: const Color(0xFFD97706),
                        iconBg: const Color(0xFFFFFBEB),
                        label: 'In-Transit Orders',
                        subLabel: 'Expected Inward',
                        value: '$_inTransitOrdersCount Orders',
                        valueColor: const Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Search Bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Search supplier, PO#, item...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(Icons.cancel_rounded, size: 16, color: Color(0xFF94A3B8)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 4. Filter Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterPill('All', 'All (${_purchases.length})'),
                _buildFilterPill('Received', 'Received ($_receivedOrdersCount)'),
                _buildFilterPill('In-Transit', 'In-Transit ($_inTransitOrdersCount)'),
                _buildFilterPill('Udhar Due', 'Udhar Due ($_creditOrdersCount)'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 5. Orders List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PURCHASE & RESTOCK ORDERS',
                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
              ),
              Text(
                '${filtered.length} shown',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 6. Orders List
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEEF2F6)),
              ),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(Icons.inbox_rounded, size: 40, color: Color(0xFFCBD5E1)),
                  const SizedBox(height: 8),
                  Text('No purchase orders match criteria', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text('Tap "+ Manual Inward" or "AI Bill OCR" to record wholesale inward.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                ],
              ),
            )
          else
            ...filtered.map((p) => _buildPurchaseCard(p)),
        ],
      ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String subLabel,
    required String value,
    required Color valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: valueColor),
                  ),
                ),
                Text(subLabel, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String key, String label) {
    final isSelected = _selectedFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilter = key);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseCard(Map<String, dynamic> purchase) {
    final isReceived = purchase['status'] == 'Received';
    final duePaise = purchase['due_paise'] as int;
    final totalPaise = purchase['amount_paise'] as int;
    final dateStr = DateFormat('dd MMM yyyy').format(purchase['date'] as DateTime);
    final itemsCount = purchase['items_count'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showOrderDetailsSheet(purchase),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Vendor info & status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isReceived ? Icons.inventory_2_rounded : Icons.local_shipping_rounded,
                        color: isReceived ? const Color(0xFF059669) : const Color(0xFFD97706),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            purchase['supplier'],
                            style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${purchase['id']} • Inv #${purchase['invoice_no']} • $dateStr',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    // Delivery Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isReceived ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isReceived ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isReceived ? Icons.check_circle_rounded : Icons.schedule_rounded,
                              size: 11, color: isReceived ? const Color(0xFF059669) : const Color(0xFFD97706)),
                          const SizedBox(width: 3),
                          Text(
                            isReceived ? 'Received' : 'In-Transit',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isReceived ? const Color(0xFF059669) : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Middle Row: Items & Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            '$itemsCount Items',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: duePaise > 0 ? () => _showSettlePaymentSheet(purchase) : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: duePaise > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: duePaise > 0 ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  duePaise > 0 ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                                  size: 11,
                                  color: duePaise > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  duePaise > 0 ? 'Supplier Udhar: ${MoneyFormatter.formatINR(duePaise)}' : 'Dues: Settled (Chukta)',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: duePaise > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                  ),
                                ),
                                if (duePaise > 0) ...[
                                  const SizedBox(width: 3),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 8, color: Color(0xFFDC2626)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      MoneyFormatter.formatINR(totalPaise),
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const Divider(height: 16, color: Color(0xFFF1F5F9)),

                // Bottom Action Buttons Row
                Row(
                  children: [
                    InkWell(
                      onTap: () => _showOrderDetailsSheet(purchase),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.list_alt_rounded, size: 13, color: Color(0xFF475569)),
                            const SizedBox(width: 4),
                            Text('View Items', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // WhatsApp Supplier
                    InkWell(
                      onTap: () => _openWhatsAppSupplier(purchase),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.chat_bubble_rounded, size: 12, color: Color(0xFF25D366)),
                            const SizedBox(width: 4),
                            Text('WhatsApp', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF15803D))),
                          ],
                        ),
                      ),
                    ),
                    if (duePaise > 0) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _showSettlePaymentSheet(purchase),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.payment_rounded, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('Pay Udhar', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
