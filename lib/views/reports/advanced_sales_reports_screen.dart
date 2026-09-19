import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/reports_repository.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/report_models.dart';
import '../../services/advanced_report_pdf_service.dart';
import '../common/in_app_notification.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/owner_privacy_modal.dart';
import 'category_report_detail_screen.dart';
import 'party_report_detail_screen.dart';

class AdvancedSalesReportsScreen extends StatefulWidget {
  const AdvancedSalesReportsScreen({super.key});

  @override
  State<AdvancedSalesReportsScreen> createState() => _AdvancedSalesReportsScreenState();
}

class _AdvancedSalesReportsScreenState extends State<AdvancedSalesReportsScreen> with SingleTickerProviderStateMixin {
  // Brand Palette matching Transactions & Dashboard
  static const Color _kIndigo = Color(0xFF4F46E5);
  static const Color _kIndigoLight = Color(0xFFEEF2FF);
  static const Color _kGreen = Color(0xFF059669);
  static const Color _kGreenLight = Color(0xFFECFDF5);
  static const Color _kSlate50 = Color(0xFFF8FAFC);
  static const Color _kSlate100 = Color(0xFFF1F5F9);
  static const Color _kSlate200 = Color(0xFFE2E8F0);
  static const Color _kSlate500 = Color(0xFF64748B);
  static const Color _kSlate900 = Color(0xFF0F172A);
  static const Color _kRed = Color(0xFFDC2626);
  static const Color _kBlue = Color(0xFF0284C7);
  static const Color _kOrange = Color(0xFFEA580C);

  String _selectedPeriod = 'This Month';
  String _sortOption = 'Sales (High to Low)';
  String _searchQuery = '';

  final List<String> _periods = ReportPeriod.labels;

  AdvancedReportsData? _data;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _exportingPartyId;
  late TabController _tabController;

  /// Profit and margins stay masked until the owner PIN is entered — the
  /// same gate Home puts on today's profit. This screen is one tap from Home,
  /// so showing every party's and item's margin openly defeated that gate.
  bool _profitUnlocked = false;

  /// Bumped per load so a slow, older load (e.g. after tapping two period
  /// chips quickly) can't overwrite the newer period's figures.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  ReportPeriod get _period => ReportPeriod.resolve(_selectedPeriod);

  /// [silent] refreshes in place (after returning from a party's bills,
  /// where a bill may have been returned) instead of flashing the spinner.
  Future<void> _loadData({bool silent = false}) async {
    final token = ++_loadToken;
    if (!silent) setState(() => _isLoading = true);
    try {
      final period = _period;
      final data = await ReportsRepository.instance.getAdvancedReportsData(
        period.start,
        period.end,
        businessType: BusinessVerticals.activeBusinessTypeNotifier.value,
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _data = data;
        _applySort();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() => _isLoading = false);
      InAppNotification.error('Could not load sales analytics: $e', context: context);
    }
  }

  void _applySort() {
    final d = _data;
    if (d == null) return;

    if (_sortOption == 'Sales (High to Low)') {
      d.partyData.sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));
      d.categoryData.sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));
      d.itemData.sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));
    } else if (_sortOption == 'Profit (High to Low)') {
      d.partyData.sort((a, b) => b.totalProfitPaise.compareTo(a.totalProfitPaise));
      d.categoryData.sort((a, b) => b.totalProfitPaise.compareTo(a.totalProfitPaise));
      d.itemData.sort((a, b) => b.totalProfitPaise.compareTo(a.totalProfitPaise));
    } else {
      d.partyData.sort((a, b) => b.invoiceCount.compareTo(a.invoiceCount));
      d.categoryData.sort((a, b) => b.quantitySold.compareTo(a.quantitySold));
      d.itemData.sort((a, b) => b.quantitySold.compareTo(a.quantitySold));
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

  String _profitText(int paise) => _profitUnlocked ? MoneyFormatter.formatINR(paise) : '₹ ••••';

  String _marginText(ProfitCoverage p) => _profitUnlocked ? ' (${p.marginPercent.toStringAsFixed(1)}%)' : '';

  Future<void> _exportGeneralPdf() async {
    if (_data == null || _isExporting) return;
    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();
    try {
      final period = _period;
      await AdvancedReportPdfService.shareGeneralReportPdf(
        _data!,
        _selectedPeriod,
        start: period.start,
        end: period.end,
        includeProfit: _profitUnlocked,
      );
    } catch (e) {
      if (mounted) {
        InAppNotification.error('Failed to generate report: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPartyPdfDirect(PartySalesSummary party) async {
    if (_exportingPartyId != null) return;
    setState(() => _exportingPartyId = party.partyId);
    HapticFeedback.mediumImpact();
    try {
      final period = _period;
      final invoices = await ReportsRepository.instance.getInvoicesForParty(
        period.start,
        period.end,
        party.partyId,
      );
      await AdvancedReportPdfService.sharePartyReportPdf(
        party,
        invoices,
        _selectedPeriod,
        start: period.start,
        end: period.end,
      );
    } catch (e) {
      if (mounted) {
        InAppNotification.error('Failed to export party statement: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _exportingPartyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = _data?.paymentSummary;

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
              'Sales Analytics',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kSlate900,
              ),
            ),
            Text(
              _isLoading || ps == null
                  ? 'Analyzing counter sales...'
                  : '$_selectedPeriod • ${MoneyFormatter.formatINR(ps.totalPaise)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _kSlate500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _profitUnlocked ? 'Hide profit' : 'Show profit (owner PIN)',
            visualDensity: VisualDensity.compact,
            onPressed: _toggleProfit,
            icon: Icon(
              _profitUnlocked ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 19,
              color: const Color(0xFF475569),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: _isLoading || _isExporting ? null : _exportGeneralPdf,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _kSlate100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kSlate200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isExporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kIndigo))
                        : const Icon(Icons.file_download_outlined, size: 16, color: _kSlate900),
                    const SizedBox(width: 4),
                    Text(
                      'PDF Report',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _kSlate900,
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
          : _data == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error loading analytics', style: GoogleFonts.inter(color: _kSlate500)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: _kGreen),
                        label: Text('Retry', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: _kGreen)),
                      ),
                    ],
                  ),
                )
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            // 1. Period Selector Chips & Sort Bar
                            _buildPeriodAndSortToolbar(),

                            // 2. 2x2 Metric Ribbon Banner
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                              child: _buildRevenueHeroBanner(ps!),
                            ),

                            // 3. Search Bar
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                              child: _buildSearchBar(),
                            ),
                          ],
                        ),
                      ),
                      // Sticky Tab Bar
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverAppBarDelegate(
                          TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            indicatorColor: _kGreen,
                            indicatorWeight: 3,
                            labelColor: _kGreen,
                            unselectedLabelColor: _kSlate500,
                            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13),
                            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                            tabs: [
                              Tab(text: 'Parties (${_data!.partyData.length})'),
                              Tab(text: 'Categories (${_data!.categoryData.length})'),
                              Tab(text: 'Items (${_data!.itemData.where((i) => !i.isDeadStock).length})'),
                              Tab(text: 'Dead Stock (${_data!.itemData.where((i) => i.isDeadStock).length})'),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPartyList(),
                      _buildCategoryList(),
                      _buildItemList(),
                      _buildDeadStockList(),
                    ],
                  ),
                ),
    );
  }

  // =========================================================================
  // 1. PERIOD & SORT TOOLBAR (MATCHES TRANSACTIONS SCREEN)
  // =========================================================================
  Widget _buildPeriodAndSortToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              // Period Filter Chips
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _periods.map((p) {
                      final isSel = _selectedPeriod == p;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          selected: isSel,
                          showCheckmark: false,
                          label: Text(
                            p,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                          backgroundColor: Colors.white,
                          selectedColor: _kGreen,
                          side: BorderSide(
                            color: isSel ? Colors.transparent : const Color(0xFFE2E8F0),
                            width: 1.1,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedPeriod = p);
                            _loadData();
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
                        _sortOption.split(' ').first,
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _sortOption = val;
                    _applySort();
                  });
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'Sales (High to Low)',
                    child: Text('Sales (High to Low) ↓', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  PopupMenuItem(
                    value: 'Profit (High to Low)',
                    child: Text('Profit (High to Low) ↑', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  PopupMenuItem(
                    value: 'Qty (High to Low)',
                    child: Text('Quantity Sold ↓', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. UNIFIED 2x2 METRIC RIBBON GRID (FINTECH CLEAN DESIGN)
  // =========================================================================
  Widget _buildRevenueHeroBanner(PaymentModeSummary ps) {
    return Container(
      padding: const EdgeInsets.all(12),
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
              // Card 1: Total Revenue
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.trending_up_rounded,
                  iconColor: _kGreen,
                  title: 'Total Revenue',
                  tag: 'Turnover',
                  value: MoneyFormatter.formatINR(ps.totalPaise),
                  valueColor: _kGreen,
                  subtitle: 'Billed, net of returns',
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFF1F5F9)),
              // Card 2: Estimated gross profit (owner PIN). Expenses are not
              // deducted here, so it is not "net" profit.
              Expanded(
                child: GestureDetector(
                  onTap: _profitUnlocked ? null : _toggleProfit,
                  behavior: HitTestBehavior.opaque,
                  child: _buildMetricTile(
                    icon: Icons.pie_chart_outline_rounded,
                    iconColor: _data!.isProfitPartial ? const Color(0xFFB45309) : _kIndigo,
                    title: 'Est. Profit',
                    tag: !_profitUnlocked
                        ? 'PIN'
                        : (_data!.isProfitPartial
                            ? 'Partial'
                            : '${_data!.marginPercent.toStringAsFixed(1)}%'),
                    value: _profitText(_data!.totalProfitPaise),
                    valueColor: _kSlate900,
                    subtitle: !_profitUnlocked
                        ? 'Tap to unlock with owner PIN'
                        : (_data!.isProfitPartial
                            ? '${_data!.uncostedLineCount} line(s) lack buying price'
                            : 'Sales − buying cost'),
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFF1F5F9), height: 16),
          Row(
            children: [
              // Card 3: Liquid Collections (Cash + UPI)
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.payments_rounded,
                  iconColor: _kBlue,
                  title: 'Cash & UPI',
                  tag: 'Liquid',
                  value: MoneyFormatter.formatINR(ps.totalCashPaise + ps.totalUpiPaise),
                  valueColor: _kBlue,
                  subtitle: 'Cash: ${MoneyFormatter.formatINR(ps.totalCashPaise)}',
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFF1F5F9)),
              // Card 4: Udhar given in this period (not the outstanding
              // khata balance, which Home shows as "Market Udhar").
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.menu_book_rounded,
                  iconColor: _kOrange,
                  title: 'Udhar Given',
                  tag: 'Credit',
                  value: MoneyFormatter.formatINR(ps.totalCreditPaise),
                  valueColor: ps.totalCreditPaise > 0 ? _kOrange : _kSlate900,
                  subtitle: 'Credit sales in period',
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _kSlate500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ).copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              color: const Color(0xFF94A3B8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. SEARCH BAR
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
          hintText: 'Filter by customer, category or product...',
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
  // 4. PARTIES TAB WITH PROMINENT DIRECT PDF EXPORT
  // =========================================================================
  Widget _buildPartyList() {
    var parties = _data!.partyData;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      parties = parties.where((p) => p.partyName.toLowerCase().contains(q) || p.partyPhone.contains(q)).toList();
    }

    if (parties.isEmpty) {
      return _buildEmptyState('No Customer Sales', 'Sales with customer information will be indexed here.');
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
      itemCount: parties.length,
      itemBuilder: (context, index) {
        final p = parties[index];
        final isGenerating = _exportingPartyId == p.partyId;

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
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final period = _period;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartyReportDetailScreen(
                      party: p,
                      start: period.start,
                      end: period.end,
                      dateRangeText: _selectedPeriod,
                      showProfit: _profitUnlocked,
                    ),
                  ),
                );
                // A bill may have been returned from the party screen.
                if (mounted) _loadData(silent: true);
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar Box
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _kIndigoLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kIndigo.withValues(alpha: 0.2)),
                      ),
                      child: Center(
                        child: Text(
                          p.partyName.isNotEmpty ? p.partyName[0].toUpperCase() : '?',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            color: _kIndigo,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Customer Name & Subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.partyName,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: _kSlate900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Dedicated 1-Tap PDF Download Button right next to Customer Name
                              InkWell(
                                onTap: () => _exportPartyPdfDirect(p),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _kGreenLight,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      isGenerating
                                          ? const SizedBox(
                                              width: 10,
                                              height: 10,
                                              child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGreen),
                                            )
                                          : const Icon(Icons.picture_as_pdf_rounded, size: 11, color: _kGreen),
                                      const SizedBox(width: 3),
                                      Text(
                                        'PDF',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: _kGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${p.invoiceCount} Bills • ${p.partyPhone.isNotEmpty ? p.partyPhone : "Walk-in"}',
                            style: GoogleFonts.inter(fontSize: 11, color: _kSlate500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Financial Amount & Margin
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          MoneyFormatter.formatINR(p.totalSalesPaise),
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _kSlate900,
                          ).copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _profitText(p.totalProfitPaise),
                              style: GoogleFonts.inter(
                                color: _kGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _marginText(p),
                              style: GoogleFonts.inter(color: _kSlate500, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // 5. CATEGORIES TAB
  // =========================================================================
  Widget _buildCategoryList() {
    var categories = _data!.categoryData;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      categories = categories.where((c) => c.categoryName.toLowerCase().contains(q)).toList();
    }

    if (categories.isEmpty) {
      return _buildEmptyState('No Categories Found', 'Category sales will appear here.');
    }

    int maxSales = 0;
    for (var c in categories) {
      if (c.totalSalesPaise > maxSales) maxSales = c.totalSalesPaise;
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final c = categories[index];
        final fraction = maxSales > 0 ? c.totalSalesPaise / maxSales : 0.0;

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
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                final catItems = _data!.itemData
                    .where((i) => i.categoryName == c.categoryName && !i.isDeadStock)
                    .toList();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryReportDetailScreen(
                      category: c,
                      items: catItems,
                      dateRangeText: _selectedPeriod,
                      showProfit: _profitUnlocked,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Rank Badge
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
                            c.categoryName,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: _kSlate900,
                            ),
                          ),
                        ),
                        Text(
                          MoneyFormatter.formatINR(c.totalSalesPaise),
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
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
                        valueColor: const AlwaysStoppedAnimation<Color>(_kGreen),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle Details
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Qty Sold: ${formatReportQty(c.quantitySold)}',
                          style: GoogleFonts.inter(fontSize: 11, color: _kSlate500, fontWeight: FontWeight.w500),
                        ),
                        Row(
                          children: [
                            Text('Profit: ', style: GoogleFonts.inter(fontSize: 11, color: _kSlate500)),
                            Text(
                              _profitText(c.totalProfitPaise),
                              style: GoogleFonts.inter(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w700),
                            ),
                            Text(_marginText(c), style: GoogleFonts.inter(fontSize: 10.5, color: _kSlate500)),
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
      },
    );
  }

  // =========================================================================
  // 6. ITEMS TAB
  // =========================================================================
  Widget _buildItemList() {
    var validItems = _data!.itemData.where((i) => !i.isDeadStock).toList();
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      validItems = validItems
          .where((i) => i.itemName.toLowerCase().contains(q) || i.categoryName.toLowerCase().contains(q))
          .toList();
    }

    if (validItems.isEmpty) {
      return _buildEmptyState('No Items Sold', 'Product sales for this period will appear here.');
    }

    int maxSales = 0;
    for (var i in validItems) {
      if (i.totalSalesPaise > maxSales) maxSales = i.totalSalesPaise;
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
      itemCount: validItems.length,
      itemBuilder: (context, index) {
        final item = validItems[index];
        final fraction = maxSales > 0 ? item.totalSalesPaise / maxSales : 0.0;

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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemName,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: _kSlate900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.categoryName,
                              style: GoogleFonts.inter(fontSize: 10, color: _kSlate500, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
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
                    valueColor: const AlwaysStoppedAnimation<Color>(_kBlue),
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
                        Text(_marginText(item), style: GoogleFonts.inter(fontSize: 10.5, color: _kSlate500)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // 7. DEAD STOCK TAB
  // =========================================================================
  Widget _buildDeadStockList() {
    var deadItems = _data!.itemData.where((i) => i.isDeadStock).toList();
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      deadItems = deadItems
          .where((i) => i.itemName.toLowerCase().contains(q) || i.categoryName.toLowerCase().contains(q))
          .toList();
    }

    if (deadItems.isEmpty) {
      return _buildEmptyState(
        'Zero Dead Stock! 🎉',
        'Every single item in your store generated sales in this period.',
        isPositive: true,
      );
    }

    return Column(
      children: [
        // Warning Banner
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${deadItems.length} items have inventory but 0 sales in $_selectedPeriod.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF92400E), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
            itemCount: deadItems.length,
            itemBuilder: (context, index) {
              final item = deadItems[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.inventory_2_outlined, color: _kRed, size: 18),
                  ),
                  title: Text(
                    item.itemName,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: _kSlate900,
                    ),
                  ),
                  subtitle: Text(
                    '${item.categoryName} • ${formatReportQty(item.stockQuantity)} ${item.unit} in stock',
                    style: GoogleFonts.inter(fontSize: 11, color: _kSlate500),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '0 SOLD',
                      style: GoogleFonts.inter(color: _kRed, fontWeight: FontWeight.w800, fontSize: 10),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle, {bool isPositive = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isPositive ? _kGreenLight : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isPositive ? Icons.check_circle_outline_rounded : Icons.search_off_rounded,
                color: isPositive ? _kGreen : const Color(0xFF94A3B8),
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _SliverAppBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: tabBar,
    );
  }

  // The tab labels carry live counts, so a new TabBar must repaint.
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}
