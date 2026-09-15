import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../core/state/app_data_bus.dart';
import '../../core/state/data_bus_refresh.dart';
import '../../core/utils/datetime_utils.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/app_printer_service.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/in_app_notification.dart';
import '../common/pro_upgrade_modal.dart';
import '../../core/utils/app_validators.dart';
import 'sale_detail_modal.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> with DataBusRefresh<TransactionsScreen> {
  @override
  List<ValueNotifier<int>> get dataBusSignals => [
        AppDataBus.instance.salesRevision,
      ];

  @override
  void onDataBusChanged() => _loadSales();

  List<SaleModel> _sales = [];
  bool _isLoading = true;
  bool _isPro = false;
  String _searchQuery = '';
  String _selectedDateFilter = 'All'; // 'All' | 'Today' | 'Yesterday' | '7 Days' | 'Month' | 'Custom'
  DateTimeRange? _customDateRange;
  String _selectedModeFilter = 'All'; // 'All' | 'Cash' | 'UPI' | 'Udhar'
  String _sortOrder = 'Newest'; // 'Newest' | 'Highest'

  final List<String> _dateFilters = ['All', 'Today', 'Yesterday', '7 Days', 'Month', 'Pick Date 📅'];
  final List<String> _modeFilters = ['All', 'Cash', 'UPI', 'Udhar'];

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final sales = await LocalDatabase.instance.getAllSales(limit: 300);
      if (mounted) {
        setState(() {
          _isPro = profile.isPro;
          _sales = sales;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF059669),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedDateFilter = 'Custom';
      });
    }
  }

  void _show7DayLimitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '7-Day History Limit',
                style: GoogleFonts.plusJakartaSans(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          'KamaiPlus Free plan provides 7 days sales history with unlimited daily billing.\n\nUpgrade to KamaiPlus Pro for Lifetime Sales History, Unlimited CA Reports, GSTR-1, and Real-time Cloud Backup.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/settings');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Upgrade to Pro', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  List<SaleModel> get _filteredSales {
    final now = DateTime.now();
    var list = _sales.where((sale) {
      // 0. Free Plan: Enforce 7-Day History Limit
      if (!_isPro) {
        if (now.difference(sale.createdAt).inDays > 7) {
          return false;
        }
      }

      // 1. Search Filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final invMatch = sale.invoiceNumber.toLowerCase().contains(query);
        final custMatch = (sale.customerName ?? '').toLowerCase().contains(query);
        final phoneMatch = (sale.customerPhone ?? '').contains(query);
        bool itemMatch = false;
        for (final it in sale.items) {
          final n = (it['product_name'] ?? it['name'] ?? '').toString().toLowerCase();
          if (n.contains(query)) {
            itemMatch = true;
            break;
          }
        }
        if (!invMatch && !custMatch && !phoneMatch && !itemMatch) return false;
      }

      // 2. Date Filter
      if (_selectedDateFilter == 'Today') {
        if (sale.createdAt.year != now.year ||
            sale.createdAt.month != now.month ||
            sale.createdAt.day != now.day) {
          return false;
        }
      } else if (_selectedDateFilter == 'Yesterday') {
        final yest = now.subtract(const Duration(days: 1));
        if (sale.createdAt.year != yest.year ||
            sale.createdAt.month != yest.month ||
            sale.createdAt.day != yest.day) {
          return false;
        }
      } else if (_selectedDateFilter == '7 Days') {
        if (now.difference(sale.createdAt).inDays > 7) return false;
      } else if (_selectedDateFilter == 'Month') {
        if (sale.createdAt.year != now.year || sale.createdAt.month != now.month) {
          return false;
        }
      } else if (_selectedDateFilter == 'Custom' && _customDateRange != null) {
        final start = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day);
        final end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59);
        if (sale.createdAt.isBefore(start) || sale.createdAt.isAfter(end)) {
          return false;
        }
      }

      // 3. Payment Mode Filter
      if (_selectedModeFilter == 'Cash' && sale.paymentMethod != 'cash' && !(sale.paymentMethod == 'split' && sale.splitCashPaise > 0)) return false;
      if (_selectedModeFilter == 'UPI' && sale.paymentMethod != 'upi' && !(sale.paymentMethod == 'split' && sale.splitUpiPaise > 0)) return false;
      if (_selectedModeFilter == 'Udhar' && sale.paymentMethod != 'credit' && !(sale.paymentMethod == 'split' && sale.splitCreditPaise > 0)) return false;

      return true;
    }).toList();

    // 4. Sorting
    if (_sortOrder == 'Highest') {
      list.sort((a, b) => b.totalAmountPaise.compareTo(a.totalAmountPaise));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return list;
  }

  int get _totalRevenuePaise => _filteredSales.where((s) => !s.isRefunded).fold(0, (sum, s) => sum + s.totalAmountPaise);
  int get _cashRevenuePaise => _filteredSales.where((s) => !s.isRefunded).fold(0, (sum, s) {
    if (s.paymentMethod == 'cash') return sum + s.totalAmountPaise;
    if (s.paymentMethod == 'split') return sum + s.splitCashPaise;
    return sum;
  });
  int get _upiRevenuePaise => _filteredSales.where((s) => !s.isRefunded).fold(0, (sum, s) {
    if (s.paymentMethod == 'upi') return sum + s.totalAmountPaise;
    if (s.paymentMethod == 'split') return sum + s.splitUpiPaise;
    return sum;
  });
  int get _creditDuePaise => _filteredSales.where((s) => !s.isRefunded).fold(0, (sum, s) {
    if (s.paymentMethod == 'credit') return sum + s.totalAmountPaise;
    if (s.paymentMethod == 'split') return sum + s.splitCreditPaise;
    return sum;
  });

  void _sendWhatsAppReceipt(SaleModel sale) async {
    HapticFeedback.lightImpact();
    final phone = sale.customerPhone != null && sale.customerPhone!.isNotEmpty
        ? sale.customerPhone!
        : null;

    if (phone == null) {
      _promptCustomerPhoneModal(sale);
      return;
    }

    _launchWhatsAppForSale(sale, phone);
  }

  void _launchWhatsAppForSale(SaleModel sale, String phone) async {
    final amtRupees = sale.totalAmountPaise ~/ 100;
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);

    final profile = await LocalDatabase.instance.getStoreProfile();
    final sName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';
    final upiId = profile.upiVpa.trim();

    final buffer = StringBuffer();
    buffer.writeln('🧾 *TAX INVOICE #${sale.invoiceNumber}*');
    buffer.writeln('🏪 *$sName*');
    buffer.writeln('👤 Customer: ${sale.customerName ?? "Valued Customer"}');
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('--------------------------');
    for (final it in sale.items) {
      final name = it['product_name'] ?? it['name'] ?? 'Item';
      final qty = it['quantity'] ?? it['qty'] ?? 1;
      final pricePaise = it['gross_total_paise'] ?? ((it['price'] as int? ?? 0) * (qty as num).toInt());
      final priceRupees = (pricePaise as int) ~/ 100;
      buffer.writeln('• ${qty}x $name = ₹$priceRupees');
    }
    buffer.writeln('--------------------------');
    buffer.writeln('💰 *Total Amount: ₹$amtRupees*');
    buffer.writeln('📌 Mode: ${sale.paymentMethod.toUpperCase()} (${sale.status.toUpperCase()})');
    if (upiId.isNotEmpty) {
      buffer.writeln('📌 *UPI ID:* $upiId');
    }
    buffer.writeln('\nThank you for your business! Visit again! 🙏');

    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final fullPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;

    // 1. Generate and share PDF with text & payment link
    final filePath = await InvoicePdfService.generateAndDownloadPdf(
      sale: sale,
      storeName: sName,
      storePhone: profile.phone,
      storeAddress: profile.address,
      gstin: profile.gstin,
      logoPath: profile.logoUrl,
      customerPhone: fullPhone,
    );

    bool shared = false;
    if (filePath != null && filePath.isNotEmpty) {
      shared = await InvoicePdfService.sharePdf(
        filePath: filePath,
        invoiceNumber: sale.invoiceNumber,
        storeName: sName,
        phone: fullPhone,
        message: buffer.toString(),
        subject: 'Tax Invoice #${sale.invoiceNumber} - $sName',
        forceChooser: false,
      );
    }

    if (!shared) {
      final url = Uri.parse('https://wa.me/$fullPhone?text=${Uri.encodeComponent(buffer.toString())}');
      try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            InAppNotification.error('Could not open WhatsApp.', context: context);
          }
        }
      } catch (_) {}
    }
  }

  void _promptCustomerPhoneModal(SaleModel sale) {
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Image.asset('assets/images/whatsapp_logo.png', width: 22, height: 22),
            const SizedBox(width: 8),
            Text('Send Bill on WhatsApp', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter customer mobile number to dispatch #${sale.invoiceNumber} invoice directly.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
            const SizedBox(height: 14),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                prefixText: '+91 ',
                labelText: 'Mobile Number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final ph = phoneCtrl.text.trim();
              final err = AppValidators.validatePhone(ph);
              if (err != null) {
                InAppNotification.error(err, context: context);
                return;
              }
              Navigator.pop(ctx);
              _launchWhatsAppForSale(sale, AppValidators.cleanPhone(ph));
            },
            icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
            label: Text('Send Now', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _printBill(SaleModel sale) async {
    HapticFeedback.lightImpact();
    await AppPrinterService.printSale(
      context: context,
      sale: sale,
    );
  }

  // =========================================================================
  // BUILD METHOD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final list = _filteredSales;
    final totalAccounts = _sales.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transaction History',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              '${list.length} Invoices • ${MoneyFormatter.formatINR(_totalRevenuePaise)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          // Export & Tally Action Button
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF0F172A)),
                  const SizedBox(width: 4),
                  Text(
                    'Export',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'csv') _showExportCsvModal();
              if (val == 'tally') _showTallyModal();
              if (val == 'return') {
                if (!_isPro) {
                  ProUpgradeModal.show(
                    context,
                    triggerFeature: 'Sales Return & Refund Restocking (Pro Only)',
                  );
                } else {
                  _showSalesReturnInfo();
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    const Icon(Icons.table_chart_outlined, color: Color(0xFF0284C7), size: 18),
                    const SizedBox(width: 8),
                    Text('Export CSV (Excel)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'tally',
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 8),
                    Text('Tally Prime XML', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'return',
                child: Row(
                  children: [
                    Icon(!_isPro ? Icons.lock_rounded : Icons.replay_rounded, color: !_isPro ? const Color(0xFFD97706) : const Color(0xFFDC2626), size: 18),
                    const SizedBox(width: 8),
                    Text(!_isPro ? 'Sales Return (Pro 🔒)' : 'Sales Return (Refund)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _loadSales,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                children: [
                  // 1. Compact Hero Revenue Summary Strip (~72px height, space-saving)
                  _buildRevenueHeroBanner(),
                  const SizedBox(height: 12),

                  // 2. Sleek Search Bar
                  _buildSearchBar(),
                  const SizedBox(height: 10),

                  // 3. Compact Smart Filter Toolbar (Date + Mode + Sort)
                  _buildSmartFiltersToolbar(totalAccounts),
                  const SizedBox(height: 14),

                  // 4. Invoices Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'TRANSACTIONS (${list.length})',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF64748B),
                              letterSpacing: 0.8,
                            ),
                          ),
                          if (_selectedModeFilter != 'All') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _selectedModeFilter == 'Udhar'
                                    ? const Color(0xFFFEE2E2)
                                    : _selectedModeFilter == 'UPI'
                                        ? const Color(0xFFE0F2FE)
                                        : const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _selectedModeFilter.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: _selectedModeFilter == 'Udhar'
                                      ? const Color(0xFFDC2626)
                                      : _selectedModeFilter == 'UPI'
                                          ? const Color(0xFF0284C7)
                                          : const Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_selectedDateFilter != 'All' || _selectedModeFilter != 'All' || _searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedDateFilter = 'All';
                              _selectedModeFilter = 'All';
                              _searchQuery = '';
                            });
                          },
                          child: Text(
                            'Clear Filters ✕',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF059669),
                            ),
                          ),
                        )
                      else
                        Text(
                          'Tap row to view & print',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Free Plan 7-Day Notice Banner
                  if (!_isPro)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 16, color: Color(0xFFD97706)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Free Plan: Showing last 7 days. Upgrade for lifetime history.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _show7DayLimitDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'UNLOCK',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 5. Transaction Invoices List
                  if (list.isEmpty)
                    _buildEmptyState()
                  else
                    ...list.map((sale) => _buildSaleInvoiceCard(sale)),
                ],
              ),
            ),
      bottomNavigationBar: const KamaiBottomNav(activeScreen: 'transactions'),
    );
  }

  // =========================================================================
  // 1. UNIFIED 2x2 METRIC RIBBON GRID (PRODUCT SCREEN DESIGN STYLE)
  // =========================================================================
  Widget _buildRevenueHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Card 1: Total Revenue
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.trending_up_rounded,
                  iconColor: const Color(0xFF059669),
                  title: 'Total Revenue',
                  tag: 'Turnover',
                  value: MoneyFormatter.formatINR(_totalRevenuePaise),
                  valueColor: const Color(0xFF059669),
                  subtitle: 'Net sales volume',
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFF1F5F9)),
              // Card 2: Invoices Issued
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Invoices Issued',
                  tag: 'Bills',
                  value: _filteredSales.length.toString(),
                  valueColor: const Color(0xFF0F172A),
                  subtitle: 'Total billed receipts',
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFF1F5F9), height: 16),
          Row(
            children: [
              // Card 3: Cash / UPI Collected
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.payments_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Cash & UPI',
                  tag: 'Liquid',
                  value: MoneyFormatter.formatINR(_cashRevenuePaise + _upiRevenuePaise),
                  valueColor: const Color(0xFF0284C7),
                  subtitle: 'Direct collections',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_selectedModeFilter == 'Cash') {
                        _selectedModeFilter = 'UPI';
                      } else if (_selectedModeFilter == 'UPI') {
                        _selectedModeFilter = 'All';
                      } else {
                        _selectedModeFilter = 'Cash';
                      }
                    });
                  },
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFF1F5F9)),
              // Card 4: Market Udhar Dues
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.menu_book_rounded,
                  iconColor: const Color(0xFFE11D48),
                  title: 'Market Udhar',
                  tag: 'Udhar',
                  value: MoneyFormatter.formatINR(_creditDuePaise),
                  valueColor: _creditDuePaise > 0 ? const Color(0xFFE11D48) : const Color(0xFF0F172A),
                  subtitle: 'Uncollected credit',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedModeFilter = _selectedModeFilter == 'Udhar' ? 'All' : 'Udhar';
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String tag,
    required String value,
    required Color valueColor,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: iconColor),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  tag,
                  style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 2. SEARCH BAR
  // =========================================================================
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
        decoration: InputDecoration(
          hintText: 'Search invoice #, customer name, phone, item...',
          hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  // =========================================================================
  // 3. SMART COMPACT FILTERS (Dual Horizontal Strip)
  // =========================================================================
  Widget _buildSmartFiltersToolbar(int totalAccounts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ..._dateFilters.map((df) {
                final isSel = _selectedDateFilter == df;
                final isLockedForFree = !_isPro && (df == 'Month' || df == 'Pick Date 📅');
                final label = df == 'All'
                    ? (!_isPro ? '7 Days ($totalAccounts)' : 'All Dates ($totalAccounts)')
                    : df == 'Today'
                        ? '⚡ Today'
                        : df == 'Yesterday'
                            ? '◀ Yesterday'
                            : df == '7 Days'
                                ? '📅 7 Days'
                                : df == 'Month'
                                    ? (isLockedForFree ? '🔒 This Month' : '📊 This Month')
                                    : (isLockedForFree ? '🔒 Pick Date' : '📅 $df');
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: isSel,
                    showCheckmark: false,
                    label: Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                        color: isSel ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFF0F172A),
                    side: BorderSide(
                      color: isSel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                      width: 1.1,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) async {
                      HapticFeedback.selectionClick();
                      if (isLockedForFree) {
                        ProUpgradeModal.show(
                          context,
                          triggerFeature: 'Custom Date & Lifetime History (Free plan: last 7 days)',
                        );
                        return;
                      }
                      if (df == 'Pick Date 📅') {
                        await _pickCustomDateRange();
                        return;
                      }
                      setState(() => _selectedDateFilter = df);
                    },
                  ),
                );
              }),
              if (_selectedDateFilter == 'Custom' && _customDateRange != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: true,
                    showCheckmark: false,
                    label: Text(
                      '${DateFormat('dd MMM').format(_customDateRange!.start)} - ${DateFormat('dd MMM').format(_customDateRange!.end)} ✕',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: const Color(0xFF059669),
                    selectedColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFF059669), width: 1.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedDateFilter = 'All';
                        _customDateRange = null;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Mode & Sort Row
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _modeFilters.map((mf) {
                    final isSel = _selectedModeFilter == mf;
                    final iconStr = mf == 'Cash'
                        ? '💵 '
                        : mf == 'UPI'
                            ? '📱 '
                            : mf == 'Udhar'
                                ? '📒 '
                                : '';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: isSel,
                        showCheckmark: false,
                        label: Text(
                          '$iconStr$mf',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                            color: isSel
                                ? Colors.white
                                : mf == 'Udhar'
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF475569),
                          ),
                        ),
                        backgroundColor: Colors.white,
                        selectedColor: mf == 'Udhar' ? const Color(0xFFDC2626) : const Color(0xFF059669),
                        side: BorderSide(
                          color: isSel
                              ? Colors.transparent
                              : mf == 'Udhar'
                                  ? const Color(0xFFFECACA)
                                  : const Color(0xFFE2E8F0),
                          width: 1.1,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedModeFilter = mf);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // Sort Dropdown
            PopupMenuButton<String>(
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort_rounded, size: 13, color: Color(0xFF475569)),
                    const SizedBox(width: 3),
                    Text(
                      _sortOrder,
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) => setState(() => _sortOrder = val),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'Newest',
                  child: Text('Newest First ↓', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                PopupMenuItem(
                  value: 'Highest',
                  child: Text('Highest Amount ↑', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // 4. INTERACTIVE SALE INVOICE CARD (BEST IN INDUSTRY & COMPACT)
  // =========================================================================
  Widget _buildSaleInvoiceCard(SaleModel sale) {
    final isRefunded = sale.isRefunded;
    final isUdhar = sale.paymentMethod == 'credit';
    final isUpi = sale.paymentMethod == 'upi';
    final isSplit = sale.paymentMethod == 'split';
    final dateStr = DateFormat('d MMM, hh:mm a').format(sale.createdAt);

    final modeColor = isRefunded
        ? const Color(0xFFDC2626)
        : (isSplit
            ? const Color(0xFF6366F1)
            : (isUdhar
                ? const Color(0xFFDC2626)
                : isUpi
                    ? const Color(0xFF0284C7)
                    : const Color(0xFF059669)));

    final modeBg = isRefunded
        ? const Color(0xFFFEE2E2)
        : (isSplit
            ? const Color(0xFFEEF2FF)
            : (isUdhar
                ? const Color(0xFFFEF2F2)
                : isUpi
                    ? const Color(0xFFF0F9FF)
                    : const Color(0xFFECFDF5)));

    // Items preview
    String itemsSummary = '';
    if (sale.items.isNotEmpty) {
      final names = sale.items.map((it) => '${it['quantity'] ?? it['qty'] ?? 1}x ${it['product_name'] ?? it['name'] ?? 'Item'}').take(2).join(', ');
      itemsSummary = '$names${sale.items.length > 2 ? " +${sale.items.length - 2} more" : ""}';
    } else {
      itemsSummary = 'Retail checkout sale';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isRefunded ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRefunded
              ? const Color(0xFFFCA5A5)
              : (isUdhar ? const Color(0xFFFED7AA) : const Color(0xFFE2E8F0)),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _showSaleDetailModal(sale),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                // Top Row: Mode icon + Details + Amount & Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Mode Avatar Box
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: modeBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: modeColor.withValues(alpha: 0.3)),
                      ),
                      child: Icon(
                        isRefunded
                            ? Icons.replay_rounded
                            : (isSplit
                                ? Icons.call_split_rounded
                                : (isUdhar
                                    ? Icons.book_rounded
                                    : isUpi
                                        ? Icons.qr_code_2_rounded
                                        : Icons.payments_rounded)),
                        color: modeColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Center: Invoice # + Customer + Date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '#${sale.invoiceNumber}',
                                style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: modeBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isRefunded ? 'RETURNED' : sale.paymentMethod.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: modeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sale.customerName != null && sale.customerName!.isNotEmpty ? sale.customerName! : "Walk-in Customer"} • ${DateTimeUtils.formatRelativeTime(sale.createdAt)} • $dateStr',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Right: Amount + Status Pill
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          MoneyFormatter.formatINR(sale.totalAmountPaise),
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            decoration: isRefunded ? TextDecoration.lineThrough : null,
                            color: isRefunded
                                ? const Color(0xFF94A3B8)
                                : (isUdhar ? const Color(0xFFDC2626) : const Color(0xFF0F172A)),
                          ).copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isRefunded
                                ? const Color(0xFFFEE2E2)
                                : (isSplit
                                    ? const Color(0xFFEEF2FF)
                                    : (isUdhar ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5))),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isRefunded
                                ? 'REFUNDED'
                                : (isSplit ? 'SPLIT' : (isUdhar ? 'UDHAR' : 'PAID')),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isRefunded
                                  ? const Color(0xFFDC2626)
                                  : (isSplit
                                      ? const Color(0xFF6366F1)
                                      : (isUdhar ? const Color(0xFFDC2626) : const Color(0xFF059669))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Items summary note
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          itemsSummary,
                          style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF475569)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Split breakdown preview if payment is split
                if (isSplit) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFDDD6FE), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.call_split_rounded, size: 12, color: Color(0xFF6366F1)),
                        const SizedBox(width: 5),
                        Text(
                          'Split: ',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF4C1D95)),
                        ),
                        Expanded(
                          child: Text(
                            [
                              if (sale.splitCashPaise > 0) 'Cash: ${MoneyFormatter.formatINR(sale.splitCashPaise)}',
                              if (sale.splitUpiPaise > 0) 'UPI: ${MoneyFormatter.formatINR(sale.splitUpiPaise)}',
                              if (sale.splitCreditPaise > 0) 'Udhar: ${MoneyFormatter.formatINR(sale.splitCreditPaise)}',
                            ].join(' • '),
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF4338CA)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Interactive Quick Actions Toolbar (Space-Saving)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // View Bill Detail button
                    InkWell(
                      onTap: () => _showSaleDetailModal(sale),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_outlined, size: 13, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            Text(
                              'View Bill',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Print Thermal & WhatsApp Dispatch Buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Thermal Print
                        Material(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () => _printBill(sale),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.print_rounded, size: 13, color: Color(0xFF334155)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Print',
                                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Official WhatsApp Logo Share
                        Material(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () => _sendWhatsAppReceipt(sale),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset('assets/images/whatsapp_logo.png', width: 14, height: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'WhatsApp',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF065F46),
                                    ),
                                  ),
                                ],
                              ),
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
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            'No Transactions Found',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
          ),
          const SizedBox(height: 4),
          Text(
            'Change filter criteria or create a new bill from Billing counter.',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. BILL DETAIL MODAL
  // =========================================================================
  void _showSaleDetailModal(SaleModel sale) {
    SaleDetailModal.show(
      context,
      sale: sale,
      onVoidOrRefund: _loadSales,
    );
  }

  // =========================================================================
  // 6. EXPORT CSV & TALLY XML
  // =========================================================================
  void _showExportCsvModal() {
    final csvRows = StringBuffer();
    csvRows.writeln('InvoiceNumber,Date,Customer,Phone,PaymentMode,Status,TotalAmountINR');
    for (final s in _filteredSales) {
      final d = DateFormat('yyyy-MM-dd HH:mm').format(s.createdAt);
      final amt = (s.totalAmountPaise / 100).toStringAsFixed(2);
      csvRows.writeln('${s.invoiceNumber},$d,"${s.customerName ?? ''}","${s.customerPhone ?? ''}",${s.paymentMethod},${s.status},$amt');
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.table_chart_outlined, color: Color(0xFF0284C7)),
            const SizedBox(width: 8),
            Text('Export Sales CSV', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_filteredSales.length} filtered sales records ready for Excel / Google Sheets export.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Total Revenue: ${MoneyFormatter.formatINR(_totalRevenuePaise)}\nCash: ${MoneyFormatter.formatINR(_cashRevenuePaise)}\nUPI: ${MoneyFormatter.formatINR(_upiRevenuePaise)}\nUdhar: ${MoneyFormatter.formatINR(_creditDuePaise)}',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvRows.toString()));
              Navigator.pop(ctx);
              InAppNotification.success('CSV Data copied to clipboard! Ready to paste into Excel.', context: context);
            },
            icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
            label: Text('Copy CSV Data', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showTallyModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.code_rounded, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Text('Tally Prime XML Export', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Text(
          'Export ${_filteredSales.length} sales vouchers formatted directly for Tally Prime ERP XML import.\n\nAll tax ledgers (CGST/SGST) and customer khata accounts will automatically map.',
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              InAppNotification.show(
                context: context,
                message: 'Tally Prime XML vouchers generated successfully!',
                customColor: const Color(0xFFD97706),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Download Tally XML', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSalesReturnInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.replay_rounded, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Text('Sales Return (Refund)', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Text(
          'To return or refund any transaction, tap the invoice row and select "Return Item". Items will be automatically restocked in inventory and ledger balance will be reversed.',
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Theek Hai', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
