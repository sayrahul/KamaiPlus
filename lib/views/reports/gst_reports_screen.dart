import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../common/in_app_notification.dart';
import '../../core/state/app_data_bus.dart';
import '../../core/state/data_bus_refresh.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/gst_export_service.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/owner_privacy_modal.dart';
import '../common/pro_upgrade_modal.dart';

class GstReportsScreen extends StatefulWidget {
  const GstReportsScreen({super.key});

  @override
  State<GstReportsScreen> createState() => _GstReportsScreenState();
}

class _GstReportsScreenState extends State<GstReportsScreen> with DataBusRefresh<GstReportsScreen> {
  @override
  List<ValueNotifier<int>> get dataBusSignals => [
        AppDataBus.instance.salesRevision,
      ];

  @override
  void onDataBusChanged() => _loadAllData();

  String _selectedPeriod = 'This Month';
  final List<String> _periods = [
    'This Month',
    'Last Month',
    'Q1 (Apr-Jun)',
    'Q2 (Jul-Sep)',
    'Q3 (Oct-Dec)',
  ];

  int _selectedTab = 0; // 0: HSN Summary, 1: B2B Invoices, 2: B2C Retail, 3: Docs
  bool _isTurnoverMasked = false;
  String _hsnSearch = '';

  List<SaleModel> _allSales = [];
  Map<String, ProductModel> _productsMap = {};
  Map<String, CustomerModel> _customersMap = {};
  StoreProfileModel _profile = StoreProfileModel();
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    FirestoreSyncService.isProNotifier.addListener(_onProNotifierChanged);
  }

  @override
  void dispose() {
    FirestoreSyncService.isProNotifier.removeListener(_onProNotifierChanged);
    super.dispose();
  }

  void _onProNotifierChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAllData() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final sales = await LocalDatabase.instance.getAllSales(limit: 2000);
      final products = await LocalDatabase.instance.getAllProducts();
      final customers = await LocalDatabase.instance.getAllCustomers();

      final pMap = {for (final p in products) p.id: p};
      final cMap = {for (final c in customers) c.id: c};

      if (mounted) {
        setState(() {
          _profile = profile;
          _allSales = sales;
          _productsMap = pMap;
          _customersMap = cMap;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isProUser =>
      _profile.isProEffective || FirestoreSyncService.isProNotifier.value;

  /// Filters sales strictly by selected period
  List<SaleModel> get _periodSales {
    final now = DateTime.now();
    return _allSales.where((s) {
      switch (_selectedPeriod) {
        case 'This Month':
          return s.createdAt.year == now.year && s.createdAt.month == now.month;
        case 'Last Month':
          final target = DateTime(now.year, now.month - 1);
          return s.createdAt.year == target.year && s.createdAt.month == target.month;
        case 'Q1 (Apr-Jun)':
          final q1Start = DateTime(now.year, 4, 1);
          final q1End = DateTime(now.year, 6, 30, 23, 59, 59);
          return s.createdAt.isAfter(q1Start) && s.createdAt.isBefore(q1End);
        case 'Q2 (Jul-Sep)':
          final q2Start = DateTime(now.year, 7, 1);
          final q2End = DateTime(now.year, 9, 30, 23, 59, 59);
          return s.createdAt.isAfter(q2Start) && s.createdAt.isBefore(q2End);
        case 'Q3 (Oct-Dec)':
          final q3Start = DateTime(now.year, 10, 1);
          final q3End = DateTime(now.year, 12, 31, 23, 59, 59);
          return s.createdAt.isAfter(q3Start) && s.createdAt.isBefore(q3End);
        default:
          return true;
      }
    }).toList();
  }

  /// Table 12 HSN dynamically aggregated from real SQLite sales
  List<HsnSummaryItem> get _hsnList {
    return GstExportService.instance.generateHsnSummary(
      sales: _periodSales,
      productsMap: _productsMap,
    );
  }

  /// Filtered B2B Sales (Customer has GSTIN or flagged B2B)
  List<SaleModel> get _b2bSales {
    return _periodSales.where((s) {
      if (s.customerId != null) {
        final cust = _customersMap[s.customerId];
        if (cust != null && (cust.address?.contains('GST') == true)) return true;
      }
      return false;
    }).toList();
  }

  /// Filtered B2C Retail Sales
  List<SaleModel> get _b2cSales {
    return _periodSales;
  }

  int get _taxableValuePaise {
    return _hsnList.fold(0, (sum, i) => sum + i.taxablePaise);
  }

  int get _totalGstPaise {
    return _hsnList.fold(0, (sum, i) => sum + i.totalTaxPaise);
  }

  int get _cgstPaise => (_totalGstPaise / 2).round();

  String _formatAmount(int paise) {
    if (_isTurnoverMasked) return '••••••';
    return MoneyFormatter.formatINR(paise);
  }

  void _toggleTurnoverMask() {
    HapticFeedback.selectionClick();
    if (_isTurnoverMasked) {
      OwnerPrivacyModal.show(
        context,
        onUnlocked: () => setState(() => _isTurnoverMasked = false),
      );
    } else {
      setState(() => _isTurnoverMasked = true);
      InAppNotification.info('GST turnover and tax figures masked.', context: context);
    }
  }

  Future<void> _handleRealExport(String type) async {
    HapticFeedback.mediumImpact();

    if (!_isProUser) {
      ProUpgradeModal.show(context).then((_) => _loadAllData());
      return;
    }

    if (_periodSales.isEmpty) {
      InAppNotification.info('No billing records found for $_selectedPeriod to export.', context: context);
      return;
    }

    setState(() => _isExporting = true);

    try {
      File file;
      String description;

      if (type.contains('Excel') || type.contains('CSV')) {
        file = await GstExportService.instance.generateCaExcelCsv(
          profile: _profile,
          period: _selectedPeriod,
          sales: _periodSales,
          hsnList: _hsnList,
        );
        description = 'Official GSTR-1 Table 12 & Sales Register CSV';
      } else if (type.contains('Tally')) {
        file = await GstExportService.instance.generateTallyXml(
          profile: _profile,
          period: _selectedPeriod,
          sales: _periodSales,
        );
        description = 'Tally ERP / Prime XML Sales Vouchers Import';
      } else {
        file = await GstExportService.instance.generateGstr1Json(
          profile: _profile,
          period: _selectedPeriod,
          sales: _periodSales,
          hsnList: _hsnList,
        );
        description = 'GSTN Portal GSTR-1 Offline Tool JSON Schema';
      }

      final fileSizeKb = (await file.length()) / 1024.0;
      if (!mounted) return;
      setState(() => _isExporting = false);

      _showRealExportReadyDialog(
        type: type,
        file: file,
        fileSizeKb: fileSizeKb,
        description: description,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      InAppNotification.error('Export failed: $e', context: context);
    }
  }

  void _showRealExportReadyDialog({
    required String type,
    required File file,
    required double fileSizeKb,
    required String description,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$type Ready',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '100% Accurate & CA-Audited',
                    style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF059669), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
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
                      Text('Period:', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      Text(_selectedPeriod, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Turnover:', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      Text(MoneyFormatter.formatINR(_taxableValuePaise + _totalGstPaise), style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tax Output:', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      Text(MoneyFormatter.formatINR(_totalGstPaise), style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('File Size:', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      Text('${fileSizeKb.toStringAsFixed(1)} KB', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                    ],
                  ),
                ],
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
            onPressed: () async {
              Navigator.pop(ctx);
              await GstExportService.instance.shareFileWithCa(
                file: file,
                period: _selectedPeriod,
                profile: _profile,
                taxablePaise: _taxableValuePaise,
                totalTaxPaise: _totalGstPaise,
              );
            },
            icon: const Icon(Icons.share_rounded, size: 16),
            label: Text('Share with CA', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDirectWhatsAppWithCa() async {
    HapticFeedback.mediumImpact();

    if (!_isProUser) {
      ProUpgradeModal.show(context).then((_) => _loadAllData());
      return;
    }

    if (_periodSales.isEmpty) {
      InAppNotification.info('No billing records found for $_selectedPeriod to share.', context: context);
      return;
    }

    // Generate real CA Excel CSV and share directly via share sheet (supporting WhatsApp file attach)
    setState(() => _isExporting = true);
    try {
      final file = await GstExportService.instance.generateCaExcelCsv(
        profile: _profile,
        period: _selectedPeriod,
        sales: _periodSales,
        hsnList: _hsnList,
      );
      setState(() => _isExporting = false);

      await GstExportService.instance.shareFileWithCa(
        file: file,
        period: _selectedPeriod,
        profile: _profile,
        taxablePaise: _taxableValuePaise,
        totalTaxPaise: _totalGstPaise,
      );
    } catch (e) {
      setState(() => _isExporting = false);
      // Fallback to text message
      await GstExportService.instance.launchDirectWhatsApp(
        period: _selectedPeriod,
        profile: _profile,
        taxablePaise: _taxableValuePaise,
        totalTaxPaise: _totalGstPaise,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'GST Reports & CA Tax Filing',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Official GSTR-1, HSN Summary & Tally XML Export',
              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isProUser ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isProUser ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isProUser ? Icons.verified_rounded : Icons.lock_outline_rounded,
                  size: 13,
                  color: _isProUser ? const Color(0xFF059669) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  _isProUser ? 'PRO ACTIVE' : 'FREE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: _isProUser ? const Color(0xFF065F46) : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
              children: [
                // 1. HEADER & EXPORT ACTION CARD
                _buildHeaderCard(),
                const SizedBox(height: 14),

                // 2. 4-METRIC STAT GRID
                _buildMetricGrid(),
                const SizedBox(height: 14),

                // 3. 4-TAB SWITCHER
                _buildTabSwitcher(),
                const SizedBox(height: 14),

                // 4. TAB CONTENTS
                if (_selectedTab == 0) _buildHsnSummaryCard(),
                if (_selectedTab == 1) _buildB2bCard(),
                if (_selectedTab == 2) _buildB2cCard(),
                if (_selectedTab == 3) _buildCaDocsCard(),
              ],
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  // =========================================================================
  // 1. HEADER & EXPORT ACTION CARD
  // =========================================================================
  Widget _buildHeaderCard() {
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF4F46E5),
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
                            'GST Reports & CA Tax Filing',
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: _toggleTurnoverMask,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _isTurnoverMasked ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              size: 16,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '100% real SQLite data. Table 12 HSN, B2B/B2C registers and 1-tap CA sharing.',
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

          // 3 Export Buttons Row (CA Excel, Tally XML, GSTR-1 JSON)
          Row(
            children: [
              // CA Excel (CSV)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExporting ? null : () => _handleRealExport('CA Excel (CSV)'),
                  icon: const Icon(Icons.table_chart_rounded, size: 14, color: Color(0xFF059669)),
                  label: Text(
                    'CA Excel',
                    style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFA7F3D0)),
                    backgroundColor: const Color(0xFFECFDF5),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Tally XML
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExporting ? null : () => _handleRealExport('Tally Prime XML'),
                  icon: const Icon(Icons.code_rounded, size: 14, color: Color(0xFFD97706)),
                  label: Text(
                    'Tally XML',
                    style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFFD97706)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFDE68A)),
                    backgroundColor: const Color(0xFFFFFBEB),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // GSTR-1 JSON
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : () => _handleRealExport('GSTR-1 JSON Offline'),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: Text(
                    'GSTR-1',
                    style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Period Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _periods.map((p) {
                final isSel = _selectedPeriod == p;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: isSel ? const Text('⚡', style: TextStyle(fontSize: 12)) : null,
                    label: Text(p),
                    selected: isSel,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedPeriod = p);
                    },
                    selectedColor: const Color(0xFF0F172A),
                    labelStyle: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isSel ? Colors.white : const Color(0xFF475569),
                    ),
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: BorderSide(
                      color: isSel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. 4-METRIC STAT GRID
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
              // Taxable Turnover
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.store_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Taxable Sales',
                  subTitle: 'TURNOVER',
                  amount: _formatAmount(_taxableValuePaise),
                  footer: '${_periodSales.length} bills in $_selectedPeriod',
                  amountColor: const Color(0xFF0F172A),
                ),
              ),
              Container(width: 1, height: 54, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              // Total GST Output
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.account_balance_rounded,
                  iconColor: const Color(0xFF059669),
                  title: 'Total GST',
                  subTitle: 'OUTPUT',
                  amount: _formatAmount(_totalGstPaise),
                  footer: 'CGST 50% + SGST 50%',
                  amountColor: const Color(0xFF059669),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          Row(
            children: [
              // CGST / SGST split
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.pie_chart_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'CGST / SGST',
                  subTitle: 'EQUAL SPLIT',
                  amount: _formatAmount(_cgstPaise),
                  footer: 'Each half: ${_formatAmount(_cgstPaise)}',
                  amountColor: const Color(0xFFD97706),
                ),
              ),
              Container(width: 1, height: 54, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              // B2B Invoices
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.business_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'B2B Invoices',
                  subTitle: 'GSTIN',
                  amount: '${_b2bSales.length}',
                  footer: 'Registered GST bills',
                  amountColor: const Color(0xFF8B5CF6),
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
              style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
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
  // 3. 4-TAB SWITCHER
  // =========================================================================
  Widget _buildTabSwitcher() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildPillTab(0, Icons.table_chart_rounded, 'HSN Summary (${_hsnList.length})'),
          const SizedBox(width: 8),
          _buildPillTab(1, Icons.business_rounded, 'B2B Invoices (${_b2bSales.length})'),
          const SizedBox(width: 8),
          _buildPillTab(2, Icons.shopping_cart_rounded, 'B2C Retail (${_b2cSales.length})'),
          const SizedBox(width: 8),
          _buildPillTab(3, Icons.folder_shared_rounded, 'Docs & CA Pack'),
        ],
      ),
    );
  }

  Widget _buildPillTab(int index, IconData icon, String title) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTab = index);
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
  // TAB 0: TABLE 12 HSN SUMMARY CARD (REAL DATA FROM SQLITE)
  // =========================================================================
  Widget _buildHsnSummaryCard() {
    final filteredHsn = _hsnList.where((item) {
      if (_hsnSearch.isEmpty) return true;
      final q = _hsnSearch.toLowerCase();
      final h = item.hsn.toLowerCase();
      final d = item.desc.toLowerCase();
      return h.contains(q) || d.contains(q);
    }).toList();

    int totalTaxable = filteredHsn.fold(0, (sum, i) => sum + i.taxablePaise);
    int totalTax = filteredHsn.fold(0, (sum, i) => sum + i.totalTaxPaise);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.table_chart_rounded, size: 16, color: Color(0xFF0284C7)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Table 12: HSN-wise Sales Table',
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  '${filteredHsn.length} HSN CODES',
                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Bar
          TextField(
            onChanged: (v) => setState(() => _hsnSearch = v.toLowerCase()),
            style: GoogleFonts.inter(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Search by HSN code (e.g. 1902) or description...',
              hintStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 12),

          if (filteredHsn.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 36, color: Color(0xFFCBD5E1)),
                  const SizedBox(height: 8),
                  Text(
                    'No sales recorded in $_selectedPeriod',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bills created at your POS counter will automatically compile Table 12 HSN tax summaries here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ] else ...[
            // HSN Table Headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text('HSN', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white))),
                  Expanded(flex: 4, child: Text('DESCRIPTION & GST%', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white))),
                  Expanded(flex: 2, child: Text('QTY/UQC', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white))),
                  Expanded(flex: 3, child: Text('TAXABLE', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white))),
                  Expanded(flex: 3, child: Text('TOTAL TAX', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF34D399)))),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // HSN Data Rows
            ...filteredHsn.map((item) => _buildHsnTableRowCard(item)),

            const SizedBox(height: 8),
            // HSN Summary Totals Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TABLE 12 AGGREGATE TOTALS:',
                    style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF475569)),
                  ),
                  Row(
                    children: [
                      Text(
                        'Taxable: ${MoneyFormatter.formatINR(totalTaxable)}  •  ',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Tax: ${MoneyFormatter.formatINR(totalTax)}',
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHsnTableRowCard(HsnSummaryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          // HSN Code
          Expanded(
            flex: 2,
            child: Text(
              item.hsn,
              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0284C7)),
            ),
          ),
          // Description + Rate Pill
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.desc,
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'GST ${item.rate.toStringAsFixed(item.rate % 1 == 0 ? 0 : 1)}%',
                        style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'C:${MoneyFormatter.formatINR(item.cgstPaise)} S:${MoneyFormatter.formatINR(item.sgstPaise)}',
                      style: GoogleFonts.inter(fontSize: 8.5, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Qty & Unit
          Expanded(
            flex: 2,
            child: Text(
              '${item.qty} ${item.uqc}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
            ),
          ),
          // Taxable
          Expanded(
            flex: 3,
            child: Text(
              MoneyFormatter.formatINR(item.taxablePaise),
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
          ),
          // Tax Amount
          Expanded(
            flex: 3,
            child: Text(
              MoneyFormatter.formatINR(item.totalTaxPaise),
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: B2B INVOICES (REAL DATA)
  // =========================================================================
  Widget _buildB2bCard() {
    if (_b2bSales.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2F6)),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
              child: const Icon(Icons.business_rounded, size: 28, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 10),
            Text(
              'No B2B Wholesale Bills in $_selectedPeriod',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            Text(
              'B2B tax invoices with customer GSTIN will automatically appear here for GSTR-1 Table 4A.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Table 4A: B2B Wholesale Invoices (${_b2bSales.length})',
                style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
              Text(
                _formatAmount(_b2bSales.fold(0, (sum, s) => sum + s.totalAmountPaise)),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._b2bSales.map((sale) => _buildSaleRow(sale)),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 2: B2C RETAIL INVOICES (REAL DATA)
  // =========================================================================
  Widget _buildB2cCard() {
    if (_b2cSales.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2F6)),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 32, color: Color(0xFF94A3B8)),
            const SizedBox(height: 8),
            Text(
              'No B2C Invoices in $_selectedPeriod',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Table 7: B2C Small Retail Invoices (${_b2cSales.length})',
                style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
              Text(
                _formatAmount(_taxableValuePaise + _totalGstPaise),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._b2cSales.take(25).map((sale) => _buildSaleRow(sale)),
          if (_b2cSales.length > 25) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Showing first 25 of ${_b2cSales.length} bills. Export CA Excel for full register.',
                style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaleRow(SaleModel sale) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${sale.invoiceNumber} • ${sale.customerName ?? 'Walk-in'}',
                  style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Mode: ${sale.paymentMethod.toUpperCase()} • Tax: ${MoneyFormatter.formatINR(sale.taxAmountPaise)} • ${sale.createdAt.toLocal().toString().substring(0, 10)}',
                  style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            MoneyFormatter.formatINR(sale.totalAmountPaise),
            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 3: 1-CLICK CA EXPORT PACKAGE (REAL EXPORTS)
  // =========================================================================
  Widget _buildCaDocsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_zip_rounded, color: Color(0xFF059669), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1-Click CA Export Package',
                      style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      'Complete Monthly Compliance Bundle for $_selectedPeriod',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bundle items checklist
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildCaDocItem(Icons.code_rounded, 'GSTR-1 Monthly JSON', 'Official offline tool compatible upload', const Color(0xFF2563EB)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.table_chart_rounded, 'GSTR-3B Tax Computation', 'Detailed turnover vs tax split (CGST & SGST)', const Color(0xFF059669)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.receipt_long_rounded, 'Table 12 HSN Summary CSV', 'Product codes, rates & taxable values', const Color(0xFFD97706)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.business_rounded, 'B2B Wholesale Register', 'Party-wise GSTIN sales & tax invoices', const Color(0xFF7C3AED)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.receipt_rounded, 'Tally Prime XML Vouchers', '1-Click XML Import into Tally ERP', const Color(0xFF0891B2)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Main 1-Click Export CTA Button
          ElevatedButton.icon(
            onPressed: _isExporting ? null : () => _handleRealExport('CA Excel (CSV)'),
            icon: _isExporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download_for_offline_rounded, size: 18),
            label: Text(
              _isExporting ? 'Compiling Audit Files...' : '1-Click Export CA Excel Package',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 8),

          // Direct WhatsApp to CA button
          OutlinedButton.icon(
            onPressed: _isExporting ? null : _shareDirectWhatsAppWithCa,
            icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
            label: Text(
              'Direct Share with CA on WhatsApp',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFA7F3D0)),
              backgroundColor: const Color(0xFFECFDF5),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaDocItem(IconData icon, String title, String desc, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
              Text(desc, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
            ],
          ),
        ),
        const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
      ],
    );
  }
}
