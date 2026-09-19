import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../core/database/reports_repository.dart';
import '../../core/utils/datetime_utils.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../models/report_models.dart';
import '../../services/advanced_report_pdf_service.dart';
import '../../services/app_printer_service.dart';
import '../../services/invoice_pdf_service.dart';
import '../common/in_app_notification.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/owner_privacy_modal.dart';
import '../transactions/sale_detail_modal.dart';

class PartyReportDetailScreen extends StatefulWidget {
  final PartySalesSummary party;
  final DateTime start;
  final DateTime end;
  final String dateRangeText;

  /// Whether the owner already unlocked profit on the report screen.
  final bool showProfit;

  const PartyReportDetailScreen({
    super.key,
    required this.party,
    required this.start,
    required this.end,
    required this.dateRangeText,
    this.showProfit = false,
  });

  @override
  State<PartyReportDetailScreen> createState() => _PartyReportDetailScreenState();
}

class _PartyReportDetailScreenState extends State<PartyReportDetailScreen> {
  static const Color _kIndigo = Color(0xFF4F46E5);
  static const Color _kIndigoLight = Color(0xFFEEF2FF);
  static const Color _kGreen = Color(0xFF059669);
  static const Color _kGreenLight = Color(0xFFECFDF5);
  static const Color _kSlate50 = Color(0xFFF8FAFC);
  static const Color _kSlate200 = Color(0xFFE2E8F0);
  static const Color _kSlate500 = Color(0xFF64748B);
  static const Color _kSlate900 = Color(0xFF0F172A);
  static const Color _kBlue = Color(0xFF0284C7);
  static const Color _kAmber = Color(0xFFD97706);
  static const Color _kRed = Color(0xFFDC2626);

  List<SaleModel> _invoices = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _searchQuery = '';
  late bool _profitUnlocked = widget.showProfit;

  /// Header totals. Recomputed from the reloaded bills, so returning a bill
  /// from the sale modal updates the totals as well as the list.
  late PartySalesSummary _party = widget.party;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final invoices = await ReportsRepository.instance.getInvoicesForParty(
        widget.start,
        widget.end,
        widget.party.partyId,
      );
      if (mounted) {
        setState(() {
          _invoices = invoices;
          _party = ReportsRepository.summarizeParty(
            widget.party.partyId,
            invoices,
            fallbackName: widget.party.partyName,
            fallbackPhone: widget.party.partyPhone,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        InAppNotification.error('Could not load bills: $e', context: context);
      }
    }
  }

  void _toggleProfit() {
    if (_profitUnlocked) {
      setState(() => _profitUnlocked = false);
      return;
    }
    OwnerPrivacyModal.show(
      context,
      onUnlocked: () {
        if (mounted) setState(() => _profitUnlocked = true);
      },
    );
  }

  Future<void> _exportPdf() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();
    try {
      await AdvancedReportPdfService.sharePartyReportPdf(
        _party,
        _invoices,
        widget.dateRangeText,
        start: widget.start,
        end: widget.end,
      );
    } catch (e) {
      if (mounted) {
        InAppNotification.error('Failed to generate PDF: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSaleDetailModal(SaleModel sale) {
    HapticFeedback.lightImpact();
    SaleDetailModal.show(
      context,
      sale: sale,
      onVoidOrRefund: _loadData,
    );
  }

  void _printBill(SaleModel sale) async {
    HapticFeedback.lightImpact();
    await AppPrinterService.printSale(
      context: context,
      sale: sale,
    );
  }

  void _sendWhatsAppReceipt(SaleModel sale) async {
    HapticFeedback.lightImpact();
    final salePhone = sale.customerPhone?.trim() ?? '';
    final phone = salePhone.isNotEmpty ? salePhone : _party.partyPhone;
    if (phone.isEmpty) {
      InAppNotification.error('Customer phone number not available.', context: context);
      return;
    }

    final amtRupees = sale.totalAmountPaise ~/ 100;
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);
    final profile = await LocalDatabase.instance.getStoreProfile();
    final sName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';

    final buffer = StringBuffer();
    buffer.writeln('🧾 *TAX INVOICE #${sale.invoiceNumber}*');
    buffer.writeln('🏪 *$sName*');
    buffer.writeln('👤 Customer: ${_party.partyName}');
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
    buffer.writeln('📌 Mode: ${sale.paymentMethod.toUpperCase()}');
    buffer.writeln('\nThank you for your business! Visit again 🙏');

    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final fullPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;

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
        }
      } catch (_) {}
    }
  }

  List<SaleModel> get _filteredInvoices {
    if (_searchQuery.trim().isEmpty) return _invoices;
    final q = _searchQuery.toLowerCase();
    return _invoices.where((inv) {
      if (inv.invoiceNumber.toLowerCase().contains(q)) return true;
      for (final it in inv.items) {
        final n = (it['product_name'] ?? it['name'] ?? '').toString().toLowerCase();
        if (n.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = _party;
    final margin = p.isProfitPartial ? 'partial' : '${p.marginPercent.toStringAsFixed(1)}% margin';
    final avgBillPaise = p.invoiceCount > 0 ? (p.totalSalesPaise ~/ p.invoiceCount) : 0;
    final list = _filteredInvoices;

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
              p.partyName,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kSlate900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${p.invoiceCount} Bills • ${widget.dateRangeText}',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _kSlate500,
              ),
            ),
          ],
        ),
        actions: [
          // PDF Export Button in AppBar
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: _isLoading || _isExporting ? null : _exportPdf,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _kIndigoLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kIndigo.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isExporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kIndigo))
                        : const Icon(Icons.picture_as_pdf_rounded, size: 15, color: _kIndigo),
                    const SizedBox(width: 5),
                    Text(
                      'PDF Statement',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _kIndigo,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const KamaiBottomNav(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kGreen))
          : RefreshIndicator(
              color: _kGreen,
              onRefresh: _loadData,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                children: [
                  // 1. Customer Hero Card
                  _buildCustomerHeroCard(p, margin, avgBillPaise),
                  const SizedBox(height: 12),

                  // 2. Search Invoices Bar
                  if (_invoices.length > 3) ...[
                    _buildSearchBar(),
                    const SizedBox(height: 12),
                  ],

                  // 3. Invoices Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ALL INVOICES (${list.length})',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _kSlate500,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Tap invoice for details',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 4. Invoices List
                  if (list.isEmpty)
                    _buildEmptyState()
                  else
                    ...list.map((inv) => _buildInvoiceCard(inv)),
                ],
              ),
            ),
    );
  }

  // =========================================================================
  // 1. CUSTOMER HERO CARD WITH DEDICATED PDF OPTION
  // =========================================================================
  Widget _buildCustomerHeroCard(PartySalesSummary p, String margin, int avgBillPaise) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Row: Avatar + Name & Phone + Direct PDF Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kIndigoLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kIndigo.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Text(
                    p.partyName.isNotEmpty ? p.partyName[0].toUpperCase() : '?',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      color: _kIndigo,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name & Phone
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.partyName,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _kSlate900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 12, color: _kSlate500),
                        const SizedBox(width: 4),
                        Text(
                          p.partyPhone.isNotEmpty ? p.partyPhone : 'Walk-in Customer',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _kSlate500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Direct PDF Download / Share Button next to Customer Name
              Material(
                color: _kGreenLight,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _isExporting ? null : _exportPdf,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download_rounded, size: 16, color: _kGreen),
                        const SizedBox(width: 4),
                        Text(
                          'PDF',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 12),

          // 2x2 Metric Ribbon
          Row(
            children: [
              Expanded(
                child: _buildHeroMetricTile(
                  icon: Icons.trending_up_rounded,
                  iconColor: _kGreen,
                  title: 'Total Sales',
                  value: MoneyFormatter.formatINR(p.totalSalesPaise),
                  valueColor: _kGreen,
                ),
              ),
              Container(width: 1, height: 42, color: const Color(0xFFF1F5F9)),
              Expanded(
                child: GestureDetector(
                  onTap: _toggleProfit,
                  behavior: HitTestBehavior.opaque,
                  child: _buildHeroMetricTile(
                    icon: _profitUnlocked ? Icons.pie_chart_outline_rounded : Icons.lock_outline_rounded,
                    iconColor: _kIndigo,
                    title: 'Est. Profit',
                    value: _profitUnlocked ? MoneyFormatter.formatINR(p.totalProfitPaise) : '₹ ••••',
                    subtitle: _profitUnlocked ? margin : 'PIN',
                    valueColor: _kSlate900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildHeroMetricTile(
                  icon: Icons.receipt_long_rounded,
                  iconColor: _kBlue,
                  title: 'Invoices Billed',
                  value: '${p.invoiceCount}',
                  valueColor: _kSlate900,
                ),
              ),
              Container(width: 1, height: 42, color: const Color(0xFFF1F5F9)),
              Expanded(
                child: _buildHeroMetricTile(
                  icon: Icons.analytics_outlined,
                  iconColor: _kAmber,
                  title: 'Avg Bill Size',
                  value: MoneyFormatter.formatINR(avgBillPaise),
                  valueColor: _kSlate900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
    required Color valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
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
                        style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: valueColor)
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

  // =========================================================================
  // 2. SEARCH BAR
  // =========================================================================
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSlate200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: GoogleFonts.inter(fontSize: 13, color: _kSlate900),
        decoration: InputDecoration(
          icon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
          hintText: 'Search by invoice number or item name...',
          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() => _searchQuery = ''),
                  child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                )
              : null,
        ),
      ),
    );
  }

  // =========================================================================
  // 3. INTERACTIVE INVOICE CARD (MATCHES TRANSACTIONS SCREEN AESTHETIC)
  // =========================================================================
  Widget _buildInvoiceCard(SaleModel sale) {
    final isRefunded = sale.isRefunded;
    final isPartiallyRefunded = sale.isPartiallyRefunded;
    final isUdhar = sale.paymentMethod == 'credit';
    final isUpi = sale.paymentMethod == 'upi';
    final isSplit = sale.paymentMethod == 'split';
    final dateStr = DateFormat('d MMM, hh:mm a').format(sale.createdAt);

    final modeColor = isRefunded
        ? _kRed
        : (isPartiallyRefunded
            ? _kAmber
            : (isSplit
                ? _kIndigo
                : (isUdhar
                    ? _kRed
                    : isUpi
                        ? _kBlue
                        : _kGreen)));

    final modeBg = isRefunded
        ? const Color(0xFFFEE2E2)
        : (isPartiallyRefunded
            ? const Color(0xFFFEF3C7)
            : (isSplit
                ? const Color(0xFFEEF2FF)
                : (isUdhar
                    ? const Color(0xFFFEF2F2)
                    : isUpi
                        ? const Color(0xFFF0F9FF)
                        : const Color(0xFFECFDF5))));

    // Items preview note
    String itemsSummary = '';
    if (sale.items.isNotEmpty) {
      final names = sale.items
          .map((it) => '${it['quantity'] ?? it['qty'] ?? 1}x ${it['product_name'] ?? it['name'] ?? 'Item'}')
          .take(2)
          .join(', ');
      itemsSummary = '$names${sale.items.length > 2 ? " +${sale.items.length - 2} more" : ""}';
    } else {
      itemsSummary = 'Retail sale invoice';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isRefunded
            ? const Color(0xFFFFF1F2)
            : (isPartiallyRefunded ? const Color(0xFFFFFBEB) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRefunded
              ? const Color(0xFFFCA5A5)
              : (isPartiallyRefunded
                  ? const Color(0xFFFCD34D)
                  : (isUdhar ? const Color(0xFFFED7AA) : const Color(0xFFE2E8F0))),
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
                // Top Row: Avatar Box + Invoice details + Amount
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Mode Avatar Icon
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
                            : (isPartiallyRefunded
                                ? Icons.assignment_return_rounded
                                : (isSplit
                                    ? Icons.call_split_rounded
                                    : (isUdhar
                                        ? Icons.book_rounded
                                        : isUpi
                                            ? Icons.qr_code_2_rounded
                                            : Icons.payments_rounded))),
                        color: modeColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Invoice # + Date
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
                                  color: _kSlate900,
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
                                  isRefunded
                                      ? 'RETURNED'
                                      : (isPartiallyRefunded
                                          ? '${sale.paymentMethod.toUpperCase()} • RET'
                                          : sale.paymentMethod.toUpperCase()),
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
                            '${DateTimeUtils.formatRelativeTime(sale.createdAt)} • $dateStr',
                            style: GoogleFonts.inter(fontSize: 11, color: _kSlate500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Amount + Status Pill
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          MoneyFormatter.formatINR(isPartiallyRefunded ? sale.netAmountPaise : sale.totalAmountPaise),
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            decoration: isRefunded ? TextDecoration.lineThrough : null,
                            color: isRefunded
                                ? const Color(0xFF94A3B8)
                                : (isUdhar ? _kRed : _kSlate900),
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
                                  ? _kRed
                                  : (isSplit
                                      ? _kIndigo
                                      : (isUdhar ? _kRed : _kGreen)),
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
                const SizedBox(height: 8),

                // Quick Actions Row: View Bill, WhatsApp, Print
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // View Bill Button (opens bottom sheet)
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

                    // Action buttons: Thermal & WhatsApp
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
                                  const Icon(Icons.print_rounded, size: 13, color: Color(0xFF475569)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Print',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // WhatsApp Share
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
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            'No Invoices Found',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
          ),
          const SizedBox(height: 4),
          Text(
            'No bills recorded for this customer in the selected date period.',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
