import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/state/app_data_bus.dart';
import '../../core/state/data_bus_refresh.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/owner_privacy_modal.dart';
import '../common/empty_state_card.dart';
import '../dashboard/home_dashboard_screen.dart';
import '../purchases/ai_inward_sheet.dart';
import '../../services/csv_inward_service.dart';
import 'low_stock_reorder_modal.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with DataBusRefresh<InventoryScreen> {
  @override
  List<ValueNotifier<int>> get dataBusSignals => [
        AppDataBus.instance.productsRevision,
      ];

  @override
  void onDataBusChanged() => _loadData();

  List<ProductModel> _products = [];
  List<SaleModel> _sales = [];
  List<InventoryMovementModel> _movements = [];
  List<Map<String, dynamic>> _nearExpiryBatchesData = [];
  bool _isLoading = true;
  bool _isAssetMasked = false;
  String _search = '';
  int _activeTabIndex = 0; // 0: Reorder Radar, 1: Near Expiry, 2: Stock Audit Trail

  @override
  void initState() {
    super.initState();
    _loadData();
    BusinessVerticals.activeBusinessTypeNotifier.addListener(_onVerticalChanged);
  }

  void _onVerticalChanged() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    BusinessVerticals.activeBusinessTypeNotifier.removeListener(_onVerticalChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      final products = await LocalDatabase.instance.getAllProducts(businessType: activeType);
      final sales = await LocalDatabase.instance.getAllSales(limit: 50);
      final movements = await LocalDatabase.instance.getAllInventoryMovements(limit: 50);
      // Real per-batch near-expiry data (pharmacy only) — see
      // getNearExpiryBatches' doc comment for why this replaced computing
      // it from each product's single denormalized expiryDate field.
      final showExpiry = BusinessVerticals.resolve(activeType).toggles.showBatchExpiry;
      final nearExpiry = showExpiry ? await LocalDatabase.instance.getNearExpiryBatches(activeType) : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _products = products;
          _sales = sales;
          _movements = movements;
          _nearExpiryBatchesData = nearExpiry;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  int get _totalValuationPaise => _products.fold(
      0, (sum, p) => sum + (p.purchasePricePaise * p.stockQuantity).round());

  List<ProductModel> get _lowStockProducts =>
      _products.where((p) => p.stockQuantity <= 5).toList();

  // Real per-batch near-expiry data, loaded in _loadData() via
  // LocalDatabase.getNearExpiryBatches — see that method's doc comment.
  List<Map<String, dynamic>> get _nearExpiryBatches => _nearExpiryBatchesData;

  String _formatValuation(int paise) {
    if (_isAssetMasked) return '••••••';
    return MoneyFormatter.formatINR(paise);
  }

  void _toggleAssetMask() {
    HapticFeedback.selectionClick();
    if (_isAssetMasked) {
      OwnerPrivacyModal.show(
        context,
        onUnlocked: () => setState(() => _isAssetMasked = false),
      );
    } else {
      setState(() => _isAssetMasked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🔒 Inventory asset valuation masked.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _openInwardSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiInwardSheet(onInwardComplete: _loadData),
    );
  }

  void _openWhatsAppReorderModal(List<ProductModel> products) {
    HapticFeedback.selectionClick();
    LowStockReorderModal.show(
      context,
      initialProducts: products,
      onReorderDispatched: () => _loadData(),
    );
  }

  void _navigateToProducts() {
    HapticFeedback.selectionClick();
    HomeDashboardScreen.switchTab(context, 1);
  }

  void _exportStockAuditCsv() {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Stock Valuation Report exported (${_products.length} SKUs)'),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _downloadSampleCsvTemplate() async {
    HapticFeedback.lightImpact();
    final businessType = BusinessVerticals.activeBusinessTypeNotifier.value;
    final csvContent = CsvInwardService.generateSampleInwardCsv(businessType: businessType);

    await Clipboard.setData(ClipboardData(text: csvContent));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.table_chart_rounded, color: Color(0xFF2563EB), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sample Inward CSV Template', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('Copied to clipboard! Ready to paste into Excel / Sheets.', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  csvContent,
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF334155)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openInwardSheet();
                  },
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text('Open Inward Sheet to Upload CSV', style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lowStock = _lowStockProducts
        .where((p) => _search.isEmpty || p.name.toLowerCase().contains(_search))
        .toList();

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
              'Inventory & Expiry Radar',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              '${_products.length} SKUs • Valuation ${_formatValuation(_totalValuationPaise)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sample Inward CSV Template',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Icon(Icons.table_view_rounded, size: 18, color: Color(0xFF2563EB)),
            ),
            onPressed: _downloadSampleCsvTemplate,
          ),
          IconButton(
            tooltip: 'Export CSV Audit',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.file_download_outlined, size: 18, color: Color(0xFF0F172A)),
            ),
            onPressed: _exportStockAuditCsv,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _loadData,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  // 1. HERO HEADER CARD (Matching Screenshot 1)
                  _buildHeroHeaderCard(),
                  const SizedBox(height: 12),

                  // 2. 4-METRIC STAT GRID (Tracked SKUs, Asset, Reorder, Expiry)
                  _buildMetricGrid(),
                  const SizedBox(height: 14),

                  // 3. 3-PILL INTERACTIVE TAB BAR (2 tabs for non-pharmacy, 3 for pharmacy)
                  _buildInteractiveTabBar(),
                  const SizedBox(height: 12),

                  // 4. SEARCH FILTER TOOLBAR (when in Reorder Radar)
                  Builder(builder: (ctx) {
                    final showExpiry = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).toggles.showBatchExpiry;
                    // Tab index 0=Reorder, 1=NearExpiry(pharmacy only), last=Audit
                    final auditIndex = showExpiry ? 2 : 1;
                    return _activeTabIndex != auditIndex ? Column(children: [_buildSearchToolbar(), const SizedBox(height: 12)]) : const SizedBox.shrink();
                  }),

                  // 5. TAB CONTENT
                  Builder(builder: (ctx) {
                    final showExpiry = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).toggles.showBatchExpiry;
                    if (_activeTabIndex == 0) return _buildReorderRadarContent(lowStock);
                    if (showExpiry && _activeTabIndex == 1) return _buildNearExpiryContent();
                    return _buildStockAuditTrailContent();
                  }),
                ],
              ),
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  // =========================================================================
  // 1. HERO HEADER CARD (MATCHING SCREENSHOT 1)
  // =========================================================================
  Widget _buildHeroHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Purple Radar Icon Container
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Color(0xFF9333EA),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Inventory & Stock Intelligence',
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        // Eye Toggle Button
                        InkWell(
                          onTap: _toggleAssetMask,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _isAssetMasked ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              size: 16,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real-time stock valuation, near-expiry radar, supplier re-order alerts & audit trails',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Action Buttons Row (Matching Screenshot 1)
          Row(
            children: [
              // Export Icon Button [ 📄 ]
              InkWell(
                onTap: _exportStockAuditCsv,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.description_outlined, color: Color(0xFF16A34A), size: 18),
                ),
              ),
              const SizedBox(width: 8),

              // WhatsApp Reorder Icon Button [ 📲 ]
              InkWell(
                onTap: () => _openWhatsAppReorderModal(_lowStockProducts),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/images/whatsapp_logo.png',
                    width: 20,
                    height: 20,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.send_rounded, color: Color(0xFF16A34A), size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ✨ Inward Bills Button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openInwardSheet,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFFD97706)),
                  label: Text(
                    'Inward Bills',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFDE68A), width: 1.2),
                    backgroundColor: const Color(0xFFFFFBEB),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 📦 Manage Products Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _navigateToProducts,
                  icon: const Icon(Icons.inventory_2_outlined, size: 15),
                  label: Text(
                    'Manage Products',
                    style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. 4-METRIC STAT GRID (MATCHING SCREENSHOT 1)
  // =========================================================================
  Widget _buildMetricGrid() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Tracked SKUs
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.inventory_2_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Tracked SKUs',
                  subTitle: 'Catalog',
                  amount: '${_products.length}',
                  footer: 'Active stock units',
                  amountColor: const Color(0xFF0F172A),
                ),
              ),
              Container(width: 1, height: 54, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              // Inventory Asset (Valuation)
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.trending_up_rounded,
                  iconColor: const Color(0xFF059669),
                  title: 'Inventory Asset',
                  subTitle: 'Cost',
                  amount: _formatValuation(_totalValuationPaise),
                  footer: 'Total cost valuation',
                  amountColor: const Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          Row(
            children: [
              // Reorder Alert
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.warning_amber_rounded,
                  iconColor: const Color(0xFFDC2626),
                  title: 'Reorder Alert',
                  subTitle: 'Low',
                  amount: '${_lowStockProducts.length}',
                  footer: 'Requires stock inward',
                  amountColor: _lowStockProducts.isNotEmpty ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                ),
              ),
              Container(width: 1, height: 54, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              // Near Expiry
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'Near Expiry',
                  subTitle: '<60d',
                  amount: '${_nearExpiryBatches.length}',
                  footer: 'Batch expiry radar',
                  amountColor: _nearExpiryBatches.isNotEmpty ? const Color(0xFFD97706) : const Color(0xFF64748B),
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
    required String subTitle,
    required String amount,
    required String footer,
    required Color amountColor,
  }) {
    return Column(
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
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
              ],
            ),
            Text(
              subTitle,
              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: amountColor,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          footer,
          style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  // =========================================================================
  // 3. INTERACTIVE 3-PILL TAB BAR
  // =========================================================================
  Widget _buildInteractiveTabBar() {
    final showExpiry = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).toggles.showBatchExpiry;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildPillTab(
            index: 0,
            icon: Icons.warning_amber_rounded,
            title: 'Reorder Radar (${_lowStockProducts.length})',
          ),
          if (showExpiry) ...[
            const SizedBox(width: 8),
            _buildPillTab(
              index: 1,
              icon: Icons.access_time_rounded,
              title: 'Near Expiry (${_nearExpiryBatches.length})',
            ),
          ],
          const SizedBox(width: 8),
          _buildPillTab(
            index: showExpiry ? 2 : 1,
            icon: Icons.history_rounded,
            title: 'Stock Audit Trail',
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab({required int index, required IconData icon, required String title}) {
    final isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeTabIndex = index);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SEARCH TOOLBAR
  // =========================================================================
  Widget _buildSearchToolbar() {
    return TextField(
      onChanged: (v) => setState(() => _search = v.toLowerCase()),
      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Search stock by item name or barcode...',
        hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0F172A))),
      ),
    );
  }

  // =========================================================================
  // TAB 0: REORDER RADAR CONTENT (MATCHING SCREENSHOT 1)
  // =========================================================================
  Widget _buildReorderRadarContent(List<ProductModel> lowStock) {
    if (lowStock.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2F6)),
        ),
        child: Column(
          children: [
            // Green Hexagonal Box (Matching Screenshot 1)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.check_circle_outline_rounded, size: 28, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 12),
            Text(
              'All items are well stocked!',
              style: GoogleFonts.outfit(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No products are currently below safety threshold.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _openInwardSheet,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
              label: Text('Inward Wholesale Batch', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 📲 1-Tap Send WhatsApp Order to Distributor Banner
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset(
                  'assets/images/whatsapp_logo.png',
                  width: 22,
                  height: 22,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.send_rounded, color: Color(0xFF16A34A), size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lowStock.length} Low Stock Items Detected',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF14532D),
                      ),
                    ),
                    Text(
                      'Generate and send 1-Tap Restock Purchase Order to your distributor',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _openWhatsAppReorderModal(lowStock),
                icon: const Icon(Icons.send_rounded, size: 13, color: Colors.white),
                label: Text(
                  'Order',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        ...lowStock.map((prod) => _buildReorderItemCard(prod)),
      ],
    );
  }

  Widget _buildReorderItemCard(ProductModel product) {
    final isOut = product.stockQuantity <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isOut ? const Color(0xFFFECACA) : const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOut ? const Color(0xFFFEE2E2) : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOut ? Icons.cancel_outlined : Icons.warning_amber_rounded,
              color: isOut ? const Color(0xFFDC2626) : const Color(0xFFD97706),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Cost: ${MoneyFormatter.formatINR(product.purchasePricePaise)} • MRP: ${MoneyFormatter.formatINR(product.mrpPaise)}',
                  style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isOut ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isOut ? 'OUT OF STOCK' : '${product.stockQuantity.toStringAsFixed(0)} ${product.unit} LEFT',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isOut ? const Color(0xFFDC2626) : const Color(0xFFB45309),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              InkWell(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  final updated = product.copyWith(stockQuantity: product.stockQuantity + 10);
                  await LocalDatabase.instance.upsertProduct(updated);
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('+10 ${product.unit} added to ${product.name}'),
                        backgroundColor: const Color(0xFF059669),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    '+10 Restock',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: NEAR EXPIRY CONTENT
  // =========================================================================
  Widget _buildNearExpiryContent() {
    if (_nearExpiryBatches.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2F6)),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.verified_rounded, size: 28, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 12),
            Text(
              'No near-expiry products detected!',
              style: GoogleFonts.outfit(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All inventory batches are fresh and well within shelf-life.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _nearExpiryBatches.map((batch) {
        final days = batch['days_left'] as int;
        final isUrgent = batch['is_urgent'] as bool;
        final expiryStr = DateFormat('dd MMM yyyy').format(batch['expiry_date'] as DateTime);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isUrgent ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isUrgent ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.medication_liquid_rounded,
                  color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batch['product_name'],
                      style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Batch: ${batch['batch_no']} • Qty: ${batch['qty']} ${batch['unit']}',
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                    ),
                    Text(
                      'Expires on: $expiryStr',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFFD97706)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$days DAYS',
                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // =========================================================================
  // TAB 2: STOCK AUDIT TRAIL CONTENT
  // =========================================================================
  Widget _buildStockAuditTrailContent() {
    if (_movements.isNotEmpty) {
      return Column(
        children: _movements.take(12).map((m) {
          final timeStr = DateFormat('dd MMM, hh:mm a').format(m.createdAt);
          final isSale = m.movementType == 'SALE';
          final isPurchase = m.movementType == 'PURCHASE';

          final icon = isSale
              ? Icons.arrow_downward_rounded
              : (isPurchase ? Icons.arrow_upward_rounded : Icons.sync_rounded);
          final color = isSale
              ? const Color(0xFFDC2626)
              : (isPurchase ? const Color(0xFF059669) : const Color(0xFFD97706));
          final bgColor = isSale
              ? const Color(0xFFFEE2E2)
              : (isPurchase ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7));

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.productName,
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${m.movementType} • ${m.previousStock.toInt()} → ${m.newStock.toInt()} stock • $timeStr',
                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${isSale ? "-" : "+"}${m.quantity.toStringAsFixed(0)}',
                  style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    if (_sales.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.history_toggle_off_rounded,
        title: 'No Stock Movements Recorded',
        description: 'Sales and inward deliveries will automatically record audit logs here.',
      );
    }

    return Column(
      children: _sales.take(8).map((s) {
        final timeStr = DateFormat('dd MMM, hh:mm a').format(s.createdAt);
        final itemCount = s.items.length;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEF2F6)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.receipt_rounded, size: 16, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill #${s.invoiceNumber} ($itemCount items deducted)',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      'Sold to ${s.customerName ?? 'Walk-in Customer'} • $timeStr',
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Text(
                '-$itemCount SKUs',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
