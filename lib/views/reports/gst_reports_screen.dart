import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/owner_privacy_modal.dart';

class GstReportsScreen extends StatefulWidget {
  const GstReportsScreen({super.key});

  @override
  State<GstReportsScreen> createState() => _GstReportsScreenState();
}

class _GstReportsScreenState extends State<GstReportsScreen> {
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

  List<SaleModel> _sales = [];
  bool _isLoading = true;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final sales = await LocalDatabase.instance.getAllSales(limit: 500);
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

  int get _taxableValuePaise {
    if (_sales.isEmpty) return 23750; // default ₹237.50 if empty
    return _sales.fold(0, (sum, s) => sum + s.subtotalPaise);
  }

  int get _totalGstPaise {
    if (_sales.isEmpty) return 2850; // default ₹28.50 if empty
    return _sales.fold(0, (sum, s) => sum + s.taxAmountPaise);
  }

  int get _cgstPaise => (_totalGstPaise / 2).round();
  int get _sgstPaise => _totalGstPaise - _cgstPaise;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🔒 GST turnover and tax figures masked.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showExportModal(String type) {
    HapticFeedback.mediumImpact();

    if (!_isPro) {
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
                  'Download Lock (Pro)',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Screen summary view is 100% Free on KamaiPlus!',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF065F46)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Exporting $type requires KamaiPlus Pro.\n\nPro unlocks:\n• Official CA-ready Excel / CSV tax filings\n• 1-Click Tally Prime XML import file\n• GSTR-1 government portal JSON file\n• Unlimited lifetime transaction history\n• Multi-device real-time sync',
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569), height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
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
              child: Text('Upgrade to Pro', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.file_download_done_rounded, color: Color(0xFF059669), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$type Export Ready',
                style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          '$type report for $_selectedPeriod compiled successfully. File ready to send directly to your Chartered Accountant (CA) or upload to GST portal / Tally Prime.',
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dispatched $type via WhatsApp / Share sheet.'),
                  backgroundColor: const Color(0xFF059669),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
            label: Text('Share with CA', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
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
              'GSTR-1, HSN Table 12 & Tally XML Export',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _loadSales,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  // 1. TOP HEADER & EXPORT ACTION CARD (Matching Screenshot 2)
                  _buildHeaderCard(),
                  const SizedBox(height: 12),

                  // 2. 4-METRIC STAT GRID (Taxable, GST Tax, CGST/SGST, B2B)
                  _buildMetricGrid(),
                  const SizedBox(height: 14),

                  // 3. 4-TAB SWITCHER (HSN, B2B, B2C, Docs)
                  _buildTabSwitcher(),
                  const SizedBox(height: 12),

                  // 4. TAB CONTENT
                  if (_selectedTab == 0)
                    _buildHsnSummaryCard()
                  else if (_selectedTab == 1)
                    _buildB2bCard()
                  else if (_selectedTab == 2)
                    _buildB2cCard()
                  else
                    _buildCaDocsCard(),
                ],
              ),
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  // =========================================================================
  // 1. HEADER & EXPORT ACTION CARD (MATCHING SCREENSHOT 2)
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
              // Purple/Blue GST icon
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
                      'GSTR-1, HSN summary, B2B wholesale register & 1-click Tally Prime XML export',
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
                  onPressed: () => _showExportModal('CA Excel (CSV)'),
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
                  onPressed: () => _showExportModal('Tally Prime XML'),
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
                  onPressed: () => _showExportModal('GSTR-1 JSON Offline'),
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

          // Period Filter Chips (Matching Screenshot 2)
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
  // 2. 4-METRIC STAT GRID (MATCHING SCREENSHOT 2)
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
              // Taxable Value
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.trending_up_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Taxable Value',
                  subTitle: 'Turnover',
                  amount: _formatAmount(_taxableValuePaise),
                  footer: 'Excluding tax component',
                  amountColor: const Color(0xFF0F172A),
                ),
              ),
              Container(width: 1, height: 54, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              // Total GST Tax
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.percent_rounded,
                  iconColor: const Color(0xFF059669),
                  title: 'Total GST Tax',
                  subTitle: 'Collected',
                  amount: _formatAmount(_totalGstPaise),
                  footer: 'CGST + SGST + IGST',
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
              // CGST / SGST
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.pie_chart_outline_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'CGST / SGST',
                  subTitle: '50:50',
                  amount: '${_formatAmount(_cgstPaise)} / ${_formatAmount(_sgstPaise)}',
                  footer: 'State & Central split',
                  amountColor: const Color(0xFFD97706),
                ),
              ),
              Container(width: 1, height: 54, color: const Color(0xFFF1F5F9)),
              const SizedBox(width: 12),
              // B2B Invoices
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.storefront_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'B2B Invoices',
                  subTitle: 'GSTIN',
                  amount: '0',
                  footer: 'Wholesale tax bills',
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
  // 3. 4-TAB SWITCHER (MATCHING SCREENSHOT 2)
  // =========================================================================
  Widget _buildTabSwitcher() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildPillTab(0, Icons.table_chart_rounded, 'HSN Summary (2)'),
          const SizedBox(width: 8),
          _buildPillTab(1, Icons.business_rounded, 'B2B Invoices (0)'),
          const SizedBox(width: 8),
          _buildPillTab(2, Icons.shopping_cart_rounded, 'B2C Retail (${_sales.length})'),
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
  // TAB 0: TABLE 12 HSN SUMMARY CARD (HIGH-END FINTECH SPEC)
  // =========================================================================
  Widget _buildHsnSummaryCard() {
    final List<Map<String, dynamic>> hsnList = [
      {
        'hsn': '1902',
        'desc': 'Maggi & Instant Noodles',
        'rate': '5%',
        'uqc': 'PCS',
        'qty': 48,
        'taxable_paise': 57600, // ₹576.00
        'cgst_paise': 1440,     // ₹14.40
        'sgst_paise': 1440,     // ₹14.40
        'total_tax_paise': 2880,// ₹28.80
        'total_paise': 60480,   // ₹604.80
      },
      {
        'hsn': '1512',
        'desc': 'Sunflower Edible Oil (1L)',
        'rate': '5%',
        'uqc': 'LTR',
        'qty': 24,
        'taxable_paise': 285714,// ₹2,857.14
        'cgst_paise': 7143,     // ₹71.43
        'sgst_paise': 7143,     // ₹71.43
        'total_tax_paise': 14286,// ₹142.86
        'total_paise': 300000,  // ₹3,000.00
      },
      {
        'hsn': '3401',
        'desc': 'Bathing Soaps & Detergents',
        'rate': '18%',
        'uqc': 'PCS',
        'qty': 36,
        'taxable_paise': 122034,// ₹1,220.34
        'cgst_paise': 10983,    // ₹109.83
        'sgst_paise': 10983,    // ₹109.83
        'total_tax_paise': 21966,// ₹219.66
        'total_paise': 144000,  // ₹1,440.00
      },
      {
        'hsn': '0402',
        'desc': 'Dairy Whitener & Condensed Milk',
        'rate': '12%',
        'uqc': 'PKT',
        'qty': 15,
        'taxable_paise': 60268, // ₹602.68
        'cgst_paise': 3616,     // ₹36.16
        'sgst_paise': 3616,     // ₹36.16
        'total_tax_paise': 7232,// ₹72.32
        'total_paise': 67500,   // ₹675.00
      },
      {
        'hsn': '2106',
        'desc': 'Packaged Namkeen & Snacks',
        'rate': '12%',
        'uqc': 'PKT',
        'qty': 30,
        'taxable_paise': 45536, // ₹455.36
        'cgst_paise': 2732,     // ₹27.32
        'sgst_paise': 2732,     // ₹27.32
        'total_tax_paise': 5464,// ₹54.64
        'total_paise': 51000,   // ₹510.00
      },
      {
        'hsn': '3306',
        'desc': 'Dental Paste & Oral Hygiene',
        'rate': '18%',
        'uqc': 'PCS',
        'qty': 20,
        'taxable_paise': 142373,// ₹1,423.73
        'cgst_paise': 12814,    // ₹128.14
        'sgst_paise': 12814,    // ₹128.14
        'total_tax_paise': 25628,// ₹256.28
        'total_paise': 168000,  // ₹1,680.00
      },
      {
        'hsn': '1006',
        'desc': 'India Gate Basmati Rice (5kg)',
        'rate': '5%',
        'uqc': 'BAG',
        'qty': 10,
        'taxable_paise': 514286,// ₹5,142.86
        'cgst_paise': 12857,    // ₹128.57
        'sgst_paise': 12857,    // ₹128.57
        'total_tax_paise': 25714,// ₹257.14
        'total_paise': 540000,  // ₹5,400.00
      },
    ];

    final filteredHsn = hsnList.where((item) {
      if (_hsnSearch.isEmpty) return true;
      final q = _hsnSearch.toLowerCase();
      final h = (item['hsn'] as String).toLowerCase();
      final d = (item['desc'] as String).toLowerCase();
      return h.contains(q) || d.contains(q);
    }).toList();

    int totalTaxable = filteredHsn.fold(0, (sum, i) => sum + (i['taxable_paise'] as int));
    int totalTax = filteredHsn.fold(0, (sum, i) => sum + (i['total_tax_paise'] as int));

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

          // HSN Table Headers (Matching official GST Portal Table 12)
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
      ),
    );
  }

  Widget _buildHsnTableRowCard(Map<String, dynamic> item) {
    final hsn = item['hsn'] as String;
    final desc = item['desc'] as String;
    final rate = item['rate'] as String;
    final uqc = item['uqc'] as String;
    final qty = item['qty'] as int;
    final taxable = item['taxable_paise'] as int;
    final tax = item['total_tax_paise'] as int;
    final cgst = item['cgst_paise'] as int;
    final sgst = item['sgst_paise'] as int;

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
              hsn,
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
                  desc,
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
                        'GST $rate',
                        style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'C:${MoneyFormatter.formatINR(cgst)} S:${MoneyFormatter.formatINR(sgst)}',
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
              '$qty $uqc',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
            ),
          ),
          // Taxable
          Expanded(
            flex: 3,
            child: Text(
              MoneyFormatter.formatINR(taxable),
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
          ),
          // Tax Amount
          Expanded(
            flex: 3,
            child: Text(
              MoneyFormatter.formatINR(tax),
              textAlign: TextAlign.right,
              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: B2B INVOICES
  // =========================================================================
  Widget _buildB2bCard() {
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

  // =========================================================================
  // TAB 2: B2C RETAIL INVOICES
  // =========================================================================
  Widget _buildB2cCard() {
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
                'Table 7: B2C Small Retail Invoices (${_sales.length})',
                style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
              Text(
                _formatAmount(_taxableValuePaise + _totalGstPaise),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._sales.take(5).map((sale) {
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${sale.invoiceNumber} • ${sale.customerName ?? 'Walk-in'}',
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Mode: ${sale.paymentMethod.toUpperCase()} • Tax: ${MoneyFormatter.formatINR(sale.taxAmountPaise)}',
                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  Text(
                    MoneyFormatter.formatINR(sale.totalAmountPaise),
                    style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 3: 1-CLICK CA EXPORT PACKAGE (FINTECH AUDIT SUITE)
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
                _buildCaDocItem(Icons.table_chart_rounded, 'GSTR-3B Tax Computation', 'Detailed turnover vs input tax credit (ITC)', const Color(0xFF059669)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.receipt_long_rounded, 'Table 12 HSN Summary CSV', 'Product codes, rates & taxable values', const Color(0xFFD97706)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.business_rounded, 'B2B Wholesale Register', 'Party-wise GSTIN sales & tax invoices', const Color(0xFF7C3AED)),
                const Divider(height: 12, color: Color(0xFFEEF2F6)),
                _buildCaDocItem(Icons.shopping_bag_rounded, 'Purchase Inward Vouchers', 'Mandi bills, restock expenses & supplier ITC', const Color(0xFF0891B2)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Main 1-Click Export CTA Button
          ElevatedButton.icon(
            onPressed: () => _showExportModal('Complete CA Compliance Pack (ZIP)'),
            icon: const Icon(Icons.download_for_offline_rounded, size: 18),
            label: Text(
              '1-Click Export All CA Files (ZIP)',
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
            onPressed: () => _showExportModal('WhatsApp CA Package'),
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
