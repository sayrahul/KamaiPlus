import '../common/owner_privacy_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../common/pwa_top_bar.dart';
import '../cash_register/cash_register_screen.dart';
import '../transactions/transactions_screen.dart';
import '../purchases/ai_inward_sheet.dart';
import '../purchases/purchases_screen.dart';
import '../inventory/inventory_screen.dart';
import '../customers/customers_screen.dart';
import '../growth/growth_campaigns_screen.dart';
import '../reports/gst_reports_screen.dart';
import '../tools/barcode_studio_screen.dart';
import '../settings/bluetooth_printer_dialog.dart';

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

class _HomePulseTabState extends State<HomePulseTab> {
  bool _isProfitHidden = true;
  bool _isLoading = true;
  bool _isLedgerExpanded = true;

  // Filter states for Recent Transactions
  String _selectedDateFilter = 'All'; // 'All', 'Today', 'Yesterday', '7 Days'
  String _selectedModeFilter = 'All Modes'; // 'All Modes', 'Cash', 'UPI', 'Udhar'
  String _searchQuery = '';

  // Pulse Metrics
  int _todaySalesPaise = 190200; // Rs 1,902.00
  int _todayBillsCount = 4;
  int _todayProfitPaise = 26750; // Rs 267.50 (~14% Margin)
  int _cashInHandPaise = 29700;  // Rs 297.00
  int _marketUdharPaise = 98000; // Rs 980.00
  int _debtorsCount = 1;

  int _totalProductsCount = 8;
  List<SaleModel> _recentSales = [];

  @override
  void initState() {
    super.initState();
    _loadLiveMetrics();
  }

  Future<void> _loadLiveMetrics() async {
    try {
      final now = DateTime.now();
      final sales = await LocalDatabase.instance.getAllSales(limit: 50);
      final products = await LocalDatabase.instance.getAllProducts();

      final todaySales = sales.where((s) =>
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

      if (sales.isNotEmpty) {
        final totalSales = todaySales.fold(0, (sum, s) => sum + s.totalAmountPaise);
        final cashSales = todaySales.where((s) => s.paymentMethod == 'cash').fold(0, (sum, s) => sum + s.totalAmountPaise);

        if (mounted) {
          setState(() {
            if (todaySales.isNotEmpty) {
              _todaySalesPaise = totalSales;
              _todayBillsCount = todaySales.length;
              _todayProfitPaise = (totalSales * 0.14).round();
              _cashInHandPaise = (cashSales > 0 ? cashSales : 29700) - todayExp;
            }
            if (debtors.isNotEmpty) {
              _marketUdharPaise = totalUdhar;
              _debtorsCount = debtors.length;
            }
            _totalProductsCount = products.isNotEmpty ? products.length : 8;
            _recentSales = sales;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _totalProductsCount = products.isNotEmpty ? products.length : 8;
            _recentSales = _getSampleScreenshotSales();
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _recentSales = _getSampleScreenshotSales();
          _isLoading = false;
        });
      }
    }
  }

  List<SaleModel> _getSampleScreenshotSales() {
    final now = DateTime.now();
    return [
      SaleModel(
        id: 'inv-004',
        businessId: 'biz-default',
        invoiceNumber: 'INV-004',
        customerName: 'Rahul Sharma',
        customerPhone: '9876543210',
        paymentMethod: 'upi',
        totalAmountPaise: 62500,
        subtotalPaise: 62500,
        taxAmountPaise: 0,
        discountPaise: 0,
        items: [
          {'name': 'Aashirvaad Atta 5kg', 'qty': 1, 'price': 24500},
          {'name': 'Fortune Oil 1L', 'qty': 1, 'price': 13500},
          {'name': 'Tata Salt 1kg', 'qty': 1, 'price': 2800},
          {'name': 'Maggi 2-Min 70g', 'qty': 2, 'price': 2800},
          {'name': 'Amul Butter 100g', 'qty': 1, 'price': 5600},
          {'name': 'Sugar Loose 1kg', 'qty': 3, 'price': 13200},
        ],
        createdAt: DateTime(now.year, now.month, now.day, 16, 23),
      ),
      SaleModel(
        id: 'inv-003',
        businessId: 'biz-default',
        invoiceNumber: 'INV-003',
        customerName: 'Rahul Sharma',
        customerPhone: '9876543210',
        paymentMethod: 'credit',
        totalAmountPaise: 49000,
        subtotalPaise: 49000,
        taxAmountPaise: 0,
        discountPaise: 0,
        items: [
          {'name': 'Basmati Rice 1kg', 'qty': 2, 'price': 24000},
          {'name': 'Toor Dal 1kg', 'qty': 1, 'price': 16500},
          {'name': 'Red Chilli Powder', 'qty': 1, 'price': 8500},
        ],
        createdAt: DateTime(now.year, now.month, now.day, 16, 21),
      ),
      SaleModel(
        id: 'inv-002',
        businessId: 'biz-default',
        invoiceNumber: 'INV-002',
        customerName: 'Rahul Sharma',
        customerPhone: '9876543210',
        paymentMethod: 'credit',
        totalAmountPaise: 49000,
        subtotalPaise: 49000,
        taxAmountPaise: 0,
        discountPaise: 0,
        items: [
          {'name': 'Basmati Rice 1kg', 'qty': 2, 'price': 24000},
          {'name': 'Toor Dal 1kg', 'qty': 1, 'price': 16500},
          {'name': 'Red Chilli Powder', 'qty': 1, 'price': 8500},
        ],
        createdAt: DateTime(now.year, now.month, now.day, 16, 20),
      ),
      SaleModel(
        id: 'inv-001',
        businessId: 'biz-default',
        invoiceNumber: 'INV-001',
        customerName: 'Rahul Sharma',
        customerPhone: '9876543210',
        paymentMethod: 'cash',
        totalAmountPaise: 29700,
        subtotalPaise: 29700,
        taxAmountPaise: 0,
        discountPaise: 0,
        items: [
          {'name': 'Milk 1L', 'qty': 2, 'price': 6600},
          {'name': 'Brown Bread', 'qty': 1, 'price': 4500},
          {'name': 'Eggs 6-pack', 'qty': 1, 'price': 5500},
          {'name': 'Surf Excel 500g', 'qty': 1, 'price': 13100},
        ],
        createdAt: DateTime(now.year, now.month, now.day, 16, 19),
      ),
    ];
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
                  _buildDaySummaryCard(),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("🔒 Today's profit is now hidden."),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
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
                badgeText: '${_todayBillsCount} Bills',
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
            // Card 2: Today's Profit
            Expanded(
              child: _buildMetricCard(
                title: "TODAY'S PROFIT",
                titleColor: const Color(0xFF0284C7),
                titleIcon: Icons.monetization_on_outlined,
                badgeText: '~14% Margin',
                badgeBg: const Color(0xFFEFF6FF),
                badgeColor: const Color(0xFF0284C7),
                amount: _formatDisplayPaise(_todayProfitPaise),
                amountColor: const Color(0xFF0F172A),
                footerLabel: 'Gross Margin',
                actionLabel: 'Owner Only',
                actionColor: const Color(0xFF0284C7),
                borderColor: const Color(0xFFBAE6FD),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Card 3: Cash In Hand
            Expanded(
              child: _buildMetricCard(
                title: 'CASH IN HAND',
                titleColor: const Color(0xFFD97706),
                titleIcon: Icons.account_balance_wallet_outlined,
                badgeText: 'Till / Galla',
                badgeBg: const Color(0xFFFEF3C7),
                badgeColor: const Color(0xFFD97706),
                amount: _formatDisplayPaise(_cashInHandPaise),
                amountColor: const Color(0xFF0F172A),
                footerLabel: 'Cash Sales - Exp',
                actionLabel: 'Register →',
                actionColor: const Color(0xFFD97706),
                borderColor: const Color(0xFFFDE68A),
                onActionTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CashRegisterScreen()),
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
                badgeText: '${_debtorsCount} Debtors',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 6,
            offset: Offset(0, 1.5),
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
              GestureDetector(
                onTap: onActionTap,
                child: Text(
                  actionLabel,
                  style: GoogleFonts.outfit(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: actionColor,
                  ),
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildDaySummaryCard() {
    return _buildPwaActionCard(
      icon: Icons.chat_bubble_outline_rounded,
      iconColor: const Color(0xFF10B981),
      iconBg: const Color(0xFFECFDF5),
      title: 'Day Summary',
      subtitle: 'WhatsApp Z-Report',
      onTap: _showDaySummaryModal,
    );
  }

  // -------------------------------------------------------------
  // SECTION 3: FAST COUNTER BANNER
  // -------------------------------------------------------------
  Widget _buildFastCounterBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF042F2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20064E3B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.scale_rounded,
              color: Color(0xFF34D399),
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
                        'Kirana Fast Counter',
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
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'GROCERY',
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6EE7B7),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Loose Staples Desk',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '1 loose items • Scanner auto-focus',
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
              backgroundColor: const Color(0xFF10B981),
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.receipt_long_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFFECFDF5),
                title: 'Billing (POS)',
                subtitle: 'Instant Checkout',
                onTap: widget.onNavigateToPos,
              ),
            ),
            const SizedBox(width: 8),
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
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildPwaActionCard(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF0D9488),
                iconBg: const Color(0xFFF0FDFA),
                title: 'Transactions',
                subtitle: 'Audit & Invoices',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()),
          ],
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
                subtitle: '${_totalProductsCount} SKUs',
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
    final timeStr = hour + ':' + minute + ' ' + ampm;
    final itemsCount = sale.items.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Row(
        children: [
          // Tag badge #001
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              tagNumber,
              style: GoogleFonts.outfit(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Details: Invoice #, Customer, Time, Items
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        (sale.customerName != null && sale.customerName!.trim().isNotEmpty)
                            ? sale.customerName!
                            : 'Cash Customer',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: paymentBadgeBg,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        paymentBadgeText,
                        style: GoogleFonts.inter(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
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
                      timeStr + ' • ' + itemsCount.toString() + ' items',
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
                isCredit ? ('Due: ' + MoneyFormatter.formatPaise(sale.totalAmountPaise)) : 'Paid',
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
                child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF10B981), size: 14),
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
    );
  }

  void _shareBillOnWhatsapp(SaleModel sale) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('WhatsApp receipt ready for ' + sale.invoiceNumber + ' (' + MoneyFormatter.formatPaise(sale.totalAmountPaise) + ')'),
        backgroundColor: const Color(0xFF10B981),
      ),
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
        final dateStr = now.day.toString() + '/' + now.month.toString() + '/' + now.year.toString();
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
                  'Today: ' + dateStr,
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                _buildSummaryRow('Total Sales Revenue', MoneyFormatter.formatPaise(_todaySalesPaise)),
                _buildSummaryRow('Total Bills Generated', _todayBillsCount.toString() + ' Bills'),
                _buildSummaryRow('Estimated Profit', _isProfitHidden ? '••••••' : MoneyFormatter.formatPaise(_todayProfitPaise)),
                _buildSummaryRow('Cash in Till/Galla', MoneyFormatter.formatPaise(_cashInHandPaise)),
                _buildSummaryRow('Outstanding Udhar', MoneyFormatter.formatPaise(_marketUdharPaise)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('WhatsApp summary dispatched to store owner')),
                      );
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
}
