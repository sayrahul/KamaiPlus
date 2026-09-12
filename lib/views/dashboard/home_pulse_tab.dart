import '../common/owner_privacy_modal.dart';
import '../common/in_app_notification.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../common/pwa_top_bar.dart';
import '../cash_register/cash_register_screen.dart';
import '../cash_register/denomination_tally_modal.dart';
import '../transactions/transactions_screen.dart';
import '../transactions/sale_detail_modal.dart';
import '../purchases/ai_inward_sheet.dart';
import '../purchases/purchases_screen.dart';
import '../inventory/inventory_screen.dart';
import '../customers/customers_screen.dart';
import '../growth/growth_campaigns_screen.dart';
import '../reports/gst_reports_screen.dart';
import '../tools/barcode_studio_screen.dart';
import '../settings/bluetooth_printer_dialog.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/state/app_data_bus.dart';
import '../../core/state/data_bus_refresh.dart';
import '../../services/firestore_sync_service.dart';

class HomePulseTab extends StatefulWidget {
  final VoidCallback onNavigateToPos;
  final VoidCallback onNavigateToKhata;
  final VoidCallback onNavigateToProducts;

  const HomePulseTab({
    super.key,
    required this.onNavigateToPos,
    required this.onNavigateToKhata,
    required this.onNavigateToProducts,
  });

  @override
  State<HomePulseTab> createState() => _HomePulseTabState();
}

class _HomePulseTabState extends State<HomePulseTab> with DataBusRefresh<HomePulseTab> {
  // The Home KPIs summarise everything, so this tab watches every signal.
  @override
  List<ValueNotifier<int>> get dataBusSignals => [
        AppDataBus.instance.salesRevision,
        AppDataBus.instance.productsRevision,
        AppDataBus.instance.customersRevision,
        AppDataBus.instance.cashRevision,
      ];

  @override
  void onDataBusChanged() => _loadLiveMetrics();

  bool _isProfitHidden = true;
  bool _isLoading = true;
  bool _isLedgerExpanded = true;

  // Filter states for Recent Transactions
  String _selectedDateFilter = 'All'; // 'All', 'Today', 'Yesterday', '7 Days'
  String _selectedModeFilter = 'All Modes'; // 'All Modes', 'Cash', 'UPI', 'Udhar'
  String _searchQuery = '';

  // Pulse Metrics (Default to 0 for clean merchant state)
  int _todaySalesPaise = 0;
  int _todayBillsCount = 0;
  int _todayProfitPaise = 0;
  int _cashInHandPaise = 0;
  int _marketUdharPaise = 0;
  int _debtorsCount = 0;

  int _totalProductsCount = 0;
  List<SaleModel> _recentSales = [];
  bool _isBroadcastDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadLiveMetrics();
    BusinessVerticals.activeBusinessTypeNotifier.addListener(_onVerticalChanged);
  }

  void _onVerticalChanged() {
    if (mounted) _loadLiveMetrics();
  }

  @override
  void dispose() {
    BusinessVerticals.activeBusinessTypeNotifier.removeListener(_onVerticalChanged);
    super.dispose();
  }

  Future<void> _loadLiveMetrics() async {
    try {
      final now = DateTime.now();
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      final sales = await LocalDatabase.instance.getAllSales(limit: 50);
      final products = await LocalDatabase.instance.getAllProducts(businessType: activeType);


      final todaySales = sales.where((s) =>
          !s.isRefunded &&
          s.createdAt.year == now.year &&
          s.createdAt.month == now.month &&
          s.createdAt.day == now.day).toList();

      final customers = await LocalDatabase.instance.getAllCustomers();
      final debtors = customers.where((c) => c.currentBalancePaise > 0).toList();
      final totalUdhar = debtors.fold(0, (sum, c) => sum + c.currentBalancePaise);

      final expenses = await LocalDatabase.instance.getAllExpenses();
      final todayExp = expenses.where((e) =>
          e.createdAt.year == now.year &&
          e.createdAt.month == now.month &&
          e.createdAt.day == now.day).fold(0, (sum, e) => sum + e.amountPaise);

      final totalSales = todaySales.fold(0, (sum, s) => sum + s.totalAmountPaise);
      final cashSales = todaySales.where((s) => s.paymentMethod == 'cash').fold(0, (sum, s) => sum + s.totalAmountPaise);
      final calculatedCash = (cashSales - todayExp);

      if (mounted) {
        setState(() {
          _todaySalesPaise = totalSales;
          _todayBillsCount = todaySales.length;
          _todayProfitPaise = (totalSales * 0.14).round();
          _cashInHandPaise = calculatedCash > 0 ? calculatedCash : 0;
          _marketUdharPaise = totalUdhar;
          _debtorsCount = debtors.length;
          _totalProductsCount = products.length;
          _recentSales = sales;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _recentSales = [];
          _isLoading = false;
        });
      }
    }
  }



  String _formatDisplayPaise(int paise, [bool isMasked = false]) {
    if (isMasked) return '••••••';
    return MoneyFormatter.formatPaise(paise);
  }

  List<SaleModel> _getFilteredSales() {
    return _recentSales.where((sale) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchInv = sale.invoiceNumber.toLowerCase().contains(q);
        final matchCust = (sale.customerName ?? '').toLowerCase().contains(q);
        if (!matchInv && !matchCust) return false;
      }

      if (_selectedModeFilter == 'Cash' && sale.paymentMethod != 'cash') return false;
      if (_selectedModeFilter == 'UPI' && sale.paymentMethod != 'upi') return false;
      if (_selectedModeFilter == 'Udhar' && sale.paymentMethod != 'credit') return false;

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const PwaTopBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: _loadLiveMetrics,
              child: ListView(
                physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 100),
                children: [
                  // SECTION 0: LIVE BROADCAST ANNOUNCEMENT BANNER
                  _buildLiveBroadcastBanner(),

                  // SECTION 1: TODAY'S BUSINESS PULSE
                  _buildPulseHeader(),
                  const SizedBox(height: 10),
                  _buildPulseCardsGrid(),
                  const SizedBox(height: 18),

                  // SECTION 2: 1-TAP QUICK ACTIONS
                  _buildQuickActionsHeader(),
                  const SizedBox(height: 10),
                  _buildHeroNewBillCard(),
                  const SizedBox(height: 10),
                  _buildDualKhataInwardRow(),
                  const SizedBox(height: 10),
                  _buildDaySummaryAndTallyRow(),
                  const SizedBox(height: 18),

                  // SECTION 3: Kirana Fast Counter & Loose Staples Banner
                  _buildFastCounterBanner(),
                  const SizedBox(height: 18),

                  // SECTION 4: DAILY COUNTER & OPS
                  _buildSectionHeader('DAILY COUNTER & OPS', const Color(0xFF10B981)),
                  const SizedBox(height: 10),
                  _buildDailyOpsGrid(),
                  const SizedBox(height: 18),

                  // SECTION 5: STOCK & SOURCING
                  _buildSectionHeader('STOCK & SOURCING', const Color(0xFF2563EB)),
                  const SizedBox(height: 10),
                  _buildStockSourcingGrid(),
                  const SizedBox(height: 18),

                  // SECTION 6: LEDGER, GROWTH & GST
                  _buildSectionHeader('LEDGER, GROWTH & GST', const Color(0xFF7C3AED)),
                  const SizedBox(height: 10),
                  _buildLedgerGrowthGrid(),
                  const SizedBox(height: 18),

                  // SECTION 7: Recent Transactions Ledger Card
                  _buildRecentTransactionsLedgerCard(),
                ],
              ),
            ),
    );
  }


  // -------------------------------------------------------------
  // SECTION 1: TODAY'S BUSINESS PULSE
  // -------------------------------------------------------------
  Widget _buildPulseHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              "TODAY'S BUSINESS PULSE",
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        InkWell(
          onTap: () {
            if (_isProfitHidden) {
              OwnerPrivacyModal.show(
                context,
                onUnlocked: () => setState(() => _isProfitHidden = false),
              );
            } else {
              setState(() => _isProfitHidden = true);
              InAppNotification.info("Today's profit is now hidden.", context: context);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(
              _isProfitHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 16,
              color: const Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPulseCardsGrid() {
    return Column(
      children: [
        Row(
          children: [
            // Card 1: Today's Sales
            Expanded(
              child: _buildMetricCard(
                title: "TODAY'S SALES",
                titleColor: const Color(0xFF059669),
                titleIcon: Icons.trending_up_rounded,
                badgeText: '$_todayBillsCount Bills',
                badgeBg: const Color(0xFFECFDF5),
                badgeColor: const Color(0xFF059669),
                amount: _formatDisplayPaise(_todaySalesPaise),
                amountColor: const Color(0xFF0F172A),
                footerLabel: 'Total Revenue',
                actionLabel: 'Bills →',
                actionColor: const Color(0xFF059669),
                borderColor: const Color(0xFFA7F3D0),
                onActionTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Card 2: Estimated Net Profit
            Expanded(
              child: _buildMetricCard(
                title: 'EST. PROFIT',
                titleColor: const Color(0xFF0284C7),
                titleIcon: Icons.currency_rupee_rounded,
                badgeText: 'Live Margin',
                badgeBg: const Color(0xFFF0F9FF),
                badgeColor: const Color(0xFF0284C7),
                amount: _formatDisplayPaise(_todayProfitPaise, _isProfitHidden),
                amountColor: const Color(0xFF0284C7),
                footerLabel: 'Net Margin',
                actionLabel: _isProfitHidden ? 'Show' : 'Hide',
                actionColor: const Color(0xFF0284C7),
                borderColor: const Color(0xFFBAE6FD),
                onActionTap: () {
                  if (_isProfitHidden) {
                    OwnerPrivacyModal.show(
                      context,
                      onUnlocked: () => setState(() => _isProfitHidden = false),
                    );
                  } else {
                    setState(() => _isProfitHidden = true);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Card 3: Total Orders
            Expanded(
              child: _buildMetricCard(
                title: 'TOTAL BILLS',
                titleColor: const Color(0xFF7C3AED),
                titleIcon: Icons.receipt_long_rounded,
                badgeText: 'Counter POS',
                badgeBg: const Color(0xFFF5F3FF),
                badgeColor: const Color(0xFF7C3AED),
                amount: '$_todayBillsCount',
                amountColor: const Color(0xFF0F172A),
                footerLabel: 'Invoices Issued',
                actionLabel: 'Report →',
                actionColor: const Color(0xFF7C3AED),
                borderColor: const Color(0xFFDDD6FE),
                onActionTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Card 4: Market Udhar
            Expanded(
              child: _buildMetricCard(
                title: 'MARKET UDHAR',
                titleColor: const Color(0xFFE11D48),
                titleIcon: Icons.menu_book_outlined,
                badgeText: '$_debtorsCount Debtors',
                badgeBg: const Color(0xFFFEE2E2),
                badgeColor: const Color(0xFFE11D48),
                amount: _formatDisplayPaise(_marketUdharPaise),
                amountColor: const Color(0xFFE11D48),
                footerLabel: 'Pending Ledger',
                actionLabel: 'Khata →',
                actionColor: const Color(0xFFE11D48),
                borderColor: const Color(0xFFFECACA),
                onActionTap: widget.onNavigateToKhata,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required Color titleColor,
    required IconData titleIcon,
    String? badgeText,
    Color? badgeBg,
    Color? badgeColor,
    required String amount,
    required Color amountColor,
    required String footerLabel,
    required String actionLabel,
    required Color actionColor,
    required Color borderColor,
    VoidCallback? onActionTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            (badgeBg ?? const Color(0xFFF8FAFC)).withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(titleIcon, size: 13, color: titleColor),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeText != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeBg ?? const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: badgeColor ?? const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  footerLabel,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    color: const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                actionLabel,
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: actionColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // The whole card is tappable, not just the small "Bills →" style link —
    // that link used to be the only hit target on the card, which was easy
    // to miss and made the KPI cards feel inert.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onActionTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }

  // -------------------------------------------------------------
  // SECTION 2: 1-TAP QUICK ACTIONS
  // -------------------------------------------------------------
  Widget _buildQuickActionsHeader() {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFFF59E0B),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFF59E0B)),
        const SizedBox(width: 3),
        Text(
          '1-TAP QUICK ACTIONS',
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroNewBillCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onNavigateToPos,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1528),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_rounded, color: Color(0xFFFBBF24), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '+ New Bill (POS)',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Fast Barcode Checkout',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFF0F172A), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDualKhataInwardRow() {
    return Row(
      children: [
        Expanded(
          child: _buildPwaActionCard(
            icon: Icons.menu_book_rounded,
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFF5F3FF),
            title: 'Digital Khata',
            subtitle: 'Customer Udhar',
            onTap: widget.onNavigateToKhata,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPwaActionCard(
            icon: Icons.inventory_2_rounded,
            iconColor: const Color(0xFF0284C7),
            iconBg: const Color(0xFFF0F9FF),
            title: 'Stock Inward',
            subtitle: 'Bills & Restock',
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AiInwardSheet(onInwardComplete: _loadLiveMetrics),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDaySummaryAndTallyRow() {
    return Row(
      children: [
        Expanded(
          child: _buildPwaActionCard(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: const Color(0xFF10B981),
            iconBg: const Color(0xFFECFDF5),
            title: 'Day Summary',
            subtitle: 'WhatsApp Z-Report',
            onTap: _showDaySummaryModal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPwaActionCard(
            icon: Icons.calculate_rounded,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
            title: 'Tally Counter',
            subtitle: 'Notes & Coins Calc',
            onTap: () {
              DenominationTallyModal.show(
                context,
                expectedCashPaise: _todaySalesPaise,
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // SECTION 3: FAST COUNTER BANNER
  // -------------------------------------------------------------
  Widget _buildFastCounterBanner() {
    return ValueListenableBuilder<String>(
      valueListenable: BusinessVerticals.activeBusinessTypeNotifier,
      builder: (context, verticalId, _) {
        final vert = BusinessVerticals.resolve(verticalId);

        String counterTitle;
        String counterTag;
        String counterDesk;
        String counterSub;
        IconData counterIcon;
        List<Color> gradientColors;
        Color accentColor;
        Color tagBg;
        Color tagColor;

        switch (vert.id) {
          case 'pharmacy':
            counterTitle = 'Prescription Counter';
            counterTag = 'PHARMACY';
            counterDesk = 'Rx & OTC Quick Checkout';
            counterSub = 'Batch & expiry tracked • Instant dosage bill';
            counterIcon = Icons.medication_rounded;
            gradientColors = const [Color(0xFF0C4A6E), Color(0xFF082F49)];
            accentColor = const Color(0xFF0284C7);
            tagBg = const Color(0xFF0284C7).withValues(alpha: 0.3);
            tagColor = const Color(0xFF7DD3FC);
            break;
          case 'restaurant':
            counterTitle = 'Table & Dine-in Express';
            counterTag = 'RESTAURANT';
            counterDesk = 'KOT & Table Billing';
            counterSub = 'Quick dish punch • Dine-in & parcel billing';
            counterIcon = Icons.restaurant_rounded;
            gradientColors = const [Color(0xFF7C2D12), Color(0xFF451A03)];
            accentColor = const Color(0xFFEA580C);
            tagBg = const Color(0xFFEA580C).withValues(alpha: 0.3);
            tagColor = const Color(0xFFFDBA74);
            break;
          case 'clothing':
            counterTitle = 'Tag & Barcode Express';
            counterTag = 'APPAREL';
            counterDesk = 'Garment & Footwear Billing';
            counterSub = 'Size & color variants • Rapid tag scan';
            counterIcon = Icons.checkroom_rounded;
            gradientColors = const [Color(0xFF581C87), Color(0xFF3B0764)];
            accentColor = const Color(0xFF9333EA);
            tagBg = const Color(0xFF9333EA).withValues(alpha: 0.3);
            tagColor = const Color(0xFFD8B4FE);
            break;
          case 'hardware':
            counterTitle = 'Contractor & Retail Counter';
            counterTag = 'HARDWARE';
            counterDesk = 'Fast Measurement & Estimate Billing';
            counterSub = 'Unit conversions • Quick proforma bill';
            counterIcon = Icons.handyman_rounded;
            gradientColors = const [Color(0xFF1E293B), Color(0xFF0F172A)];
            accentColor = const Color(0xFF2563EB);
            tagBg = const Color(0xFF2563EB).withValues(alpha: 0.3);
            tagColor = const Color(0xFF93C5FD);
            break;
          case 'grocery':
          default:
            counterTitle = 'Quick Kirana Counter';
            counterTag = 'GROCERY';
            counterDesk = 'Loose Staples & FMCG Desk';
            counterSub = 'Rapid weigh items • Scanner auto-focus';
            counterIcon = Icons.scale_rounded;
            gradientColors = const [Color(0xFF064E3B), Color(0xFF042F2E)];
            accentColor = const Color(0xFF10B981);
            tagBg = const Color(0xFF10B981).withValues(alpha: 0.3);
            tagColor = const Color(0xFF6EE7B7);
            break;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  counterIcon,
                  color: tagColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            counterTitle,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: tagBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            counterTag,
                            style: GoogleFonts.inter(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: tagColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      counterDesk,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      counterSub,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: const Color(0xFF94A3B8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: widget.onNavigateToPos,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Counter',
                      style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_rounded, size: 12),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // SECTIONS 4, 5, 6: CATEGORY GRIDS
  // -------------------------------------------------------------
  Widget _buildSectionHeader(String title, Color dotColor) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyOpsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildPwaActionCard(
            icon: Icons.point_of_sale_rounded,
            iconColor: const Color(0xFFF59E0B),
            iconBg: const Color(0xFFFFFBEB),
            title: 'Cash Register',
            subtitle: 'Shift & Z-Report',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CashRegisterScreen()),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPwaActionCard(
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF0D9488),
            iconBg: const Color(0xFFF0FDFA),
            title: 'Transactions',
            subtitle: 'History & Invoices',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TransactionsScreen()),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildStockSourcingGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                title: 'Products Master',
                subtitle: '$_totalProductsCount SKUs',
                onTap: widget.onNavigateToProducts,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.hub_outlined,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFF0F9FF),
                title: 'Inventory & Expiry',
                subtitle: 'Stock Radar',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.description_outlined,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
                title: 'Purchases & Bills',
                subtitle: 'Vendor Inward',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PurchasesScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.qr_code_2_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBg: const Color(0xFFF5F3FF),
                title: 'Barcode Studio',
                subtitle: 'Print & Labels',
                badge: 'PRO',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BarcodeStudioScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLedgerGrowthGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.menu_book_outlined,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFFFBEB),
                title: 'Khata Ledger',
                subtitle: 'Customer Udhar',
                onTap: widget.onNavigateToKhata,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.people_outline_rounded,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFF0F9FF),
                title: 'Customers CRM',
                subtitle: 'Loyalty & Visits',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomersScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.trending_up_rounded,
                iconColor: const Color(0xFFE11D48),
                iconBg: const Color(0xFFFFF1F2),
                title: 'WhatsApp Grow...',
                subtitle: 'Festival Offers',
                badge: 'PRO',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GrowthCampaignsScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.assessment_outlined,
                iconColor: const Color(0xFF4F46E5),
                iconBg: const Color(0xFFEEF2FF),
                title: 'GST & Accounting',
                subtitle: 'GSTR-1 Reports',
                badge: 'PRO',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GstReportsScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPwaActionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEF2F6), width: 1.1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 6,
                offset: Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              badge,
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: const Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // SECTION 7: RECENT TRANSACTIONS LEDGER
  // -------------------------------------------------------------
  Widget _buildRecentTransactionsLedgerCard() {
    final filteredSales = _getFilteredSales();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF334155), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Recent Transactions',
                            style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${_recentSales.length} bills',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Tap any invoice to view, print, or share WhatsApp bill',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Full Ledger Link + Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Full Ledger',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_forward_rounded, size: 13, color: Color(0xFF0F172A)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _isLedgerExpanded = !_isLedgerExpanded),
                  icon: Icon(
                    _isLedgerExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF475569),
                    size: 18,
                  ),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          if (_isLedgerExpanded) ...[
            const SizedBox(height: 8),
            // 3. Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Search invoice # or customer...',
                    hintStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 4. Filter Pills Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _buildFilterPill('All', _selectedDateFilter == 'All', () => setState(() => _selectedDateFilter = 'All')),
                  const SizedBox(width: 5),
                  _buildFilterPill('Today', _selectedDateFilter == 'Today', () => setState(() => _selectedDateFilter = 'Today')),
                  const SizedBox(width: 5),
                  _buildFilterPill('Yesterday', _selectedDateFilter == 'Yesterday', () => setState(() => _selectedDateFilter = 'Yesterday')),
                  const SizedBox(width: 5),
                  _buildFilterPill('7 Days', _selectedDateFilter == '7 Days', () => setState(() => _selectedDateFilter = '7 Days')),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 18, color: const Color(0xFFE2E8F0)),
                  const SizedBox(width: 8),
                  _buildModePill('All Modes', _selectedModeFilter == 'All Modes', () => setState(() => _selectedModeFilter = 'All Modes')),
                  const SizedBox(width: 5),
                  _buildModePill('Cash', _selectedModeFilter == 'Cash', () => setState(() => _selectedModeFilter = 'Cash')),
                  const SizedBox(width: 5),
                  _buildModePill('UPI', _selectedModeFilter == 'UPI', () => setState(() => _selectedModeFilter = 'UPI')),
                  const SizedBox(width: 5),
                  _buildModePill('Udhar', _selectedModeFilter == 'Udhar', () => setState(() => _selectedModeFilter = 'Udhar')),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 5. Invoices List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: filteredSales.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No transactions found for filter',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                        ),
                      ),
                    )
                  : Column(
                      children: filteredSales.asMap().entries.map((entry) {
                        final index = entry.key;
                        final sale = entry.value;
                        final tagNumber = '#${(filteredSales.length - index).toString().padLeft(3, '0')}';
                        return _buildInvoiceListItem(sale, tagNumber);
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildModePill(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceListItem(SaleModel sale, String tagNumber) {
    final isCredit = sale.paymentMethod == 'credit';
    final isUpi = sale.paymentMethod == 'upi';
    final paymentBadgeText = isCredit ? 'CREDIT' : (isUpi ? 'UPI' : 'CASH');
    final paymentBadgeBg = isCredit ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5);
    final paymentBadgeColor = isCredit ? const Color(0xFFE11D48) : const Color(0xFF059669);

    final hour = sale.createdAt.hour.toString().padLeft(2, "0");
    final minute = sale.createdAt.minute.toString().padLeft(2, "0");
    final ampm = sale.createdAt.hour >= 12 ? "pm" : "am";
    final timeStr = '$hour:$minute $ampm';
    final itemsCount = sale.items.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => SaleDetailModal.show(context, sale: sale),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
        children: [
          // Tag badge #001
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '#${sale.invoiceNumber.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0').substring(sale.invoiceNumber.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0').length - 3)}',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Customer / Bill Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        sale.customerName ?? 'Walk-in Customer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: paymentBadgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        paymentBadgeText,
                        style: GoogleFonts.inter(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: paymentBadgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1.5),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 10, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text(
                      '$timeStr • $itemsCount items',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Total Amount & Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                MoneyFormatter.formatPaise(sale.totalAmountPaise),
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                isCredit ? 'Due: ${MoneyFormatter.formatPaise(sale.totalAmountPaise)}' : 'Paid',
                style: GoogleFonts.inter(
                  fontSize: 8.5,
                  fontWeight: isCredit ? FontWeight.w700 : FontWeight.w500,
                  color: isCredit ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),

          // WhatsApp Share Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _shareBillOnWhatsapp(sale),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Image.asset('assets/images/whatsapp_logo.png', width: 14, height: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),

          // Print Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _printInvoice(sale),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(Icons.print_outlined, color: Color(0xFF475569), size: 14),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
),
);
  }

  void _shareBillOnWhatsapp(SaleModel sale) {
    InAppNotification.success(
      'WhatsApp receipt ready for ${sale.invoiceNumber} (${MoneyFormatter.formatPaise(sale.totalAmountPaise)})',
      context: context,
    );
  }

  void _printInvoice(SaleModel sale) {
    showDialog(
      context: context,
      builder: (_) => const BluetoothPrinterDialog(),
    );
  }

  void _showDaySummaryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final now = DateTime.now();
        final dateStr = '${now.day}/${now.month}/${now.year}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Daily Closing Z-Report',
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Today: $dateStr',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                _buildSummaryRow('Total Sales Revenue', MoneyFormatter.formatPaise(_todaySalesPaise)),
                _buildSummaryRow('Total Bills Generated', '$_todayBillsCount Bills'),
                _buildSummaryRow('Estimated Profit', _isProfitHidden ? '••••••' : MoneyFormatter.formatPaise(_todayProfitPaise)),
                _buildSummaryRow('Cash in Till/Galla', MoneyFormatter.formatPaise(_cashInHandPaise)),
                _buildSummaryRow('Outstanding Udhar', MoneyFormatter.formatPaise(_marketUdharPaise)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      InAppNotification.success('WhatsApp summary dispatched to store owner', context: context);
                    },
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      'Share on WhatsApp',
                      style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569))),
          Text(value, style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildLiveBroadcastBanner() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: FirestoreSyncService.instance.broadcastNotifier,
      builder: (context, broadcast, _) {
        if (broadcast == null || _isBroadcastDismissed) {
          return const SizedBox.shrink();
        }

        final message = broadcast['message']?.toString() ?? '';
        if (message.isEmpty) return const SizedBox.shrink();

        final type = broadcast['type']?.toString().toLowerCase() ?? 'info';
        List<Color> gradientColors;
        IconData iconData;
        Color badgeColor;
        String badgeText;

        switch (type) {
          case 'festive':
            gradientColors = const [Color(0xFF881337), Color(0xFFE11D48)];
            iconData = Icons.auto_awesome_rounded;
            badgeColor = const Color(0xFFFBBF24);
            badgeText = 'SPECIAL UPDATE';
            break;
          case 'warning':
            gradientColors = const [Color(0xFF78350F), Color(0xFFD97706)];
            iconData = Icons.warning_amber_rounded;
            badgeColor = const Color(0xFFFDE68A);
            badgeText = 'NOTICE';
            break;
          case 'success':
            gradientColors = const [Color(0xFF064E3B), Color(0xFF059669)];
            iconData = Icons.verified_rounded;
            badgeColor = const Color(0xFFA7F3D0);
            badgeText = 'ANNOUNCEMENT';
            break;
          default:
            gradientColors = const [Color(0xFF1E3A8A), Color(0xFF2563EB)];
            iconData = Icons.campaign_rounded;
            badgeColor = const Color(0xFFBFDBFE);
            badgeText = 'BROADCAST';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: gradientColors.last.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isBroadcastDismissed = true;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
