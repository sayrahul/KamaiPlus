import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/pro_upgrade_modal.dart';
import '../../models/models.dart';
import '../../services/invoice_pdf_service.dart';

class InvoiceThemesScreen extends StatefulWidget {
  const InvoiceThemesScreen({super.key});

  @override
  State<InvoiceThemesScreen> createState() => _InvoiceThemesScreenState();
}

class _InvoiceThemesScreenState extends State<InvoiceThemesScreen> {
  int _selectedColorIndex = 0; // Default Navy Slate
  final List<Color> _palette = [
    const Color(0xFF0F172A), // Navy Slate (Free)
    const Color(0xFF0284C7), // Sky Blue (Pro)
    const Color(0xFF059669), // Emerald Green (Pro)
    const Color(0xFFB45309), // Terracotta Amber (Pro)
    const Color(0xFF7E22CE), // Royal Purple (Pro)
    const Color(0xFF0D9488), // Teal (Pro)
    const Color(0xFF334155), // Charcoal (Pro)
  ];

  bool _isPro = false;
  String _selectedHeading = 'TAX INVOICE';

  // Display Option Checkboxes
  bool _showLogo = true;
  bool _showTagline = true;
  bool _showOwnerPhone = true;
  bool _showDynamicUpiQr = true;
  bool _showSignatory = true;

  // Pro Toggles
  bool _showGstTaxBreakup = false;
  bool _showHsnCode = false;
  bool _showMrpSavings = false;
  bool _showTerms = false;
  bool _showPharmacyRx = false;

  final TextEditingController _termsCtrl = TextEditingController(
    text: '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.',
  );
  late final TextEditingController _footerCtrl;

  @override
  void initState() {
    super.initState();
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
    _footerCtrl = TextEditingController(text: vert.placeholders.invoiceFooterNote);
    _loadSavedFooter();
  }

  Future<void> _loadSavedFooter() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      _isPro = profile.isPro;

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_invoice_footer');
      if (saved != null && saved.isNotEmpty) {
        _footerCtrl.text = saved;
      }
      final savedHeading = prefs.getString('invoice_heading');
      if (savedHeading != null && savedHeading.isNotEmpty) {
        _selectedHeading = savedHeading;
      }
      final savedColorIdx = prefs.getInt('invoice_selected_palette_index');
      if (savedColorIdx != null && savedColorIdx >= 0 && savedColorIdx < _palette.length) {
        _selectedColorIndex = (_isPro || savedColorIdx == 0) ? savedColorIdx : 0;
      }
      final savedTerms = prefs.getString('invoice_terms');
      if (savedTerms != null && savedTerms.isNotEmpty) {
        _termsCtrl.text = savedTerms;
      }
      if (prefs.containsKey('invoice_show_dynamic_upi_qr')) {
        _showDynamicUpiQr = prefs.getBool('invoice_show_dynamic_upi_qr') ?? true;
      }
      if (prefs.containsKey('invoice_show_logo')) {
        _showLogo = prefs.getBool('invoice_show_logo') ?? true;
      }
      if (prefs.containsKey('invoice_show_tagline')) {
        _showTagline = prefs.getBool('invoice_show_tagline') ?? true;
      }
      if (prefs.containsKey('invoice_show_owner_phone')) {
        _showOwnerPhone = prefs.getBool('invoice_show_owner_phone') ?? true;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _termsCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_invoice_footer', _footerCtrl.text.trim());
      await prefs.setString('invoice_heading', _selectedHeading);
      await prefs.setInt('invoice_selected_palette_index', _selectedColorIndex);
      final activeColor = _palette[_selectedColorIndex];
      final hex = '#${activeColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      await prefs.setString('invoice_theme_color_hex', hex);
      await prefs.setString('invoice_terms', _termsCtrl.text.trim());
      await prefs.setBool('invoice_show_dynamic_upi_qr', _showDynamicUpiQr);
      await prefs.setBool('invoice_show_logo', _showLogo);
      await prefs.setBool('invoice_show_tagline', _showTagline);
      await prefs.setBool('invoice_show_owner_phone', _showOwnerPhone);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text('Invoice theme & options saved successfully!'),
          ],
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _generateSamplePdf() async {
    HapticFeedback.mediumImpact();
    _saveSettings();
    StoreProfileModel profile = StoreProfileModel.empty();
    try {
      profile = await LocalDatabase.instance.getStoreProfile();
    } catch (_) {}

    final sampleSale = SaleModel(
      id: 'SAMPLE-GST-01',
      businessId: 'default',
      invoiceNumber: 'INV-2026-0842',
      subtotalPaise: 1392050,
      totalAmountPaise: 1499000,
      taxAmountPaise: 106950,
      discountPaise: 0,
      paymentMethod: 'upi',
      status: 'completed',
      customerName: 'Arihant Retail Traders Pvt Ltd',
      customerPhone: '9890198765',
      customerGstin: '27AAACA1234F1Z8',
      placeOfSupply: '27 (Maharashtra)',
      createdAt: DateTime.now(),
      items: [
        {
          'product_name': 'Aashirvaad Shudh Chakki Atta (10kg)',
          'hsn_code': '1101',
          'quantity': 10,
          'unit_price_paise': 42000,
          'gross_total_paise': 420000,
          'tax_rate': 5.0,
          'is_tax_inclusive': true,
        },
        {
          'product_name': 'Fortune Sunlite Sunflower Oil (15L Tin)',
          'hsn_code': '1512',
          'quantity': 4,
          'unit_price_paise': 185000,
          'gross_total_paise': 740000,
          'tax_rate': 5.0,
          'is_tax_inclusive': true,
        },
        {
          'product_name': 'Dettol Antiseptic Liquid (500ml)',
          'hsn_code': '3004',
          'quantity': 12,
          'unit_price_paise': 19500,
          'gross_total_paise': 234000,
          'tax_rate': 18.0,
          'is_tax_inclusive': true,
        },
        {
          'product_name': 'Cadbury Dairy Milk Silk Chocolate (Pack)',
          'hsn_code': '1806',
          'quantity': 6,
          'unit_price_paise': 17500,
          'gross_total_paise': 105000,
          'tax_rate': 18.0,
          'is_tax_inclusive': true,
        },
      ],
    );

    final path = await InvoicePdfService.generateAndDownloadPdf(
      sale: sampleSale,
      storeName: profile.storeName.isNotEmpty ? profile.storeName : 'Shree Ganesh Enterprises',
      storePhone: profile.phone.isNotEmpty ? profile.phone : '9822012345',
      storeAddress: profile.address.isNotEmpty ? profile.address : 'Shop 12-14, Market Yard, Pune',
      gstin: profile.gstin.isNotEmpty ? profile.gstin : '27AAAAA0000A1Z5',
      customerPhone: '9890198765',
    );

    if (path != null && mounted) {
      await InvoicePdfService.openPdf(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _palette[_selectedColorIndex];

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
              'Invoice Themes & Design',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Custom PDF styling, A4 & 80mm thermal themes',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          // PDF Export Button
          OutlinedButton.icon(
            onPressed: _generateSamplePdf,
            icon: const Icon(Icons.download_rounded, size: 15, color: Color(0xFF0F172A)),
            label: Text('PDF', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 6),
          // Save Button
          ElevatedButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save_rounded, size: 15),
            label: Text('Save', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // =================================================================
          // 1. SELECT INVOICE THEME & COLOR (PRO) - SCREENSHOT 3
          // =================================================================
          _buildSection1ThemeAndColors(activeColor),
          const SizedBox(height: 14),

          // =================================================================
          // 2. HEADER & INVOICE DISPLAY OPTIONS - SCREENSHOT 3
          // =================================================================
          _buildSection2DisplayOptions(),
          const SizedBox(height: 14),

          // =================================================================
          // 3. PLATFORM BRANDING (FREE TIER) - SCREENSHOT 4
          // =================================================================
          _buildSection3PlatformBranding(),
          const SizedBox(height: 14),

          // =================================================================
          // 4. TERMS & FOOTER NOTE - SCREENSHOT 4
          // =================================================================
          _buildSection4TermsAndFooter(),
          const SizedBox(height: 16),

          // =================================================================
          // 5. LIVE INTERACTIVE A4 PREVIEW - SCREENSHOT 4 & 5
          // =================================================================
          _buildSection5LiveA4Preview(activeColor),
        ],
      ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  // =========================================================================
  // SECTION 1: THEME & COLOR PICKER (SCREENSHOT 3)
  // =========================================================================
  Widget _buildSection1ThemeAndColors(Color activeColor) {
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
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('1', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Text('Select Invoice Theme & Color', style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                    child: Text('👑 PRO', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFFB45309))),
                  ),
                ],
              ),
              Text('Pharma & Retail Rx', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 12),

          // Pharmacy Pro Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Text(
                      'Default RETAIL theme active.',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => ProUpgradeModal.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Unlock Pro',
                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Palette Circles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_palette.length, (idx) {
              final isSel = _selectedColorIndex == idx;
              final col = _palette[idx];

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (!_isPro && idx != 0) {
                    ProUpgradeModal.show(context).then((_) => _loadSavedFooter());
                    return;
                  }
                  setState(() => _selectedColorIndex = idx);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: isSel ? Border.all(color: Colors.white, width: 2.5) : null,
                    boxShadow: [
                      if (isSel)
                        BoxShadow(
                          color: col.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: isSel
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : (!_isPro && idx != 0
                          ? const Icon(Icons.lock_rounded, color: Colors.white70, size: 13)
                          : null),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 2: HEADER & DISPLAY OPTIONS (SCREENSHOT 3)
  // =========================================================================
  Widget _buildSection2DisplayOptions() {
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
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('2', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text('Header & Invoice Display Options', style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            'INVOICE DOCUMENT HEADING',
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),

          // 2x2 Heading Pills (Matching Screenshot 3)
          Row(
            children: [
              Expanded(child: _buildHeadingChoicePill('TAX INVOICE')),
              const SizedBox(width: 8),
              Expanded(child: _buildHeadingChoicePill('RETAIL INVOICE')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildHeadingChoicePill('CASH MEMO')),
              const SizedBox(width: 8),
              Expanded(child: _buildHeadingChoicePill('ESTIMATE / BILL')),
            ],
          ),
          const SizedBox(height: 14),

          // 2-Column Checkboxes (Matching Screenshot 3)
          Row(
            children: [
              Expanded(child: _buildCheckboxTile('Show Store Logo', _showLogo, (v) => setState(() => _showLogo = v))),
              const SizedBox(width: 8),
              Expanded(child: _buildCheckboxTile('Show Tagline', _showTagline, (v) => setState(() => _showTagline = v))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildCheckboxTile('Show Owner & Phone', _showOwnerPhone, (v) => setState(() => _showOwnerPhone = v))),
              const SizedBox(width: 8),
              Expanded(child: _buildCheckboxTile('Show Dynamic UPI QR', _showDynamicUpiQr, (v) => setState(() => _showDynamicUpiQr = v))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildCheckboxTile('Authorised Signatory', _showSignatory, (v) => setState(() => _showSignatory = v))),
              const SizedBox(width: 8),
              Expanded(child: _buildCheckboxTile('Show GST Tax Breakup', _showGstTaxBreakup, (v) => setState(() => _showGstTaxBreakup = v), isPro: true)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildCheckboxTile('Show HSN/SAC Code', _showHsnCode, (v) => setState(() => _showHsnCode = v), isPro: true)),
              const SizedBox(width: 8),
              Expanded(child: _buildCheckboxTile('Show MRP Savings Badge', _showMrpSavings, (v) => setState(() => _showMrpSavings = v), isPro: true)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildCheckboxTile('Show Terms & Conditions', _showTerms, (v) => setState(() => _showTerms = v), isPro: true)),
              const SizedBox(width: 8),
              Expanded(child: _buildCheckboxTile('💊 Pharmacy Rx & D.L.', _showPharmacyRx, (v) => setState(() => _showPharmacyRx = v), isPro: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeadingChoicePill(String heading) {
    final isSel = _selectedHeading == heading;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedHeading = heading);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
        ),
        alignment: Alignment.center,
        child: Text(
          heading,
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: isSel ? Colors.white : const Color(0xFF334155),
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxTile(String label, bool value, ValueChanged<bool> onChanged, {bool isPro = false}) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        if (isPro && !_isPro) {
          ProUpgradeModal.show(context).then((_) => _loadSavedFooter());
        } else {
          onChanged(!value);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: value ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: value ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPro) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                child: Text('PRO', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: const Color(0xFFB45309))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SECTION 3: PLATFORM BRANDING (SCREENSHOT 4)
  // =========================================================================
  Widget _buildSection3PlatformBranding() {
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
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('3', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.campaign_outlined, size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 4),
                  Text('Platform Branding', style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                child: Text('Free Tier', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Text(
                      'Free Tier includes footer promotion strip',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF92400E), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => ProUpgradeModal.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(6)),
                    child: Text('Remove Ads', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 4: TERMS & FOOTER NOTE (SCREENSHOT 4)
  // =========================================================================
  Widget _buildSection4TermsAndFooter() {
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
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('4', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text('Terms & Footer Note', style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Terms & Conditions', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
          const SizedBox(height: 4),
          TextField(
            controller: _termsCtrl,
            maxLines: 2,
            style: GoogleFonts.inter(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'e.g. 1. Goods replaced within 7 days. 2. Subject to local jurisdiction.',
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
          const SizedBox(height: 10),
          Text('Footer Thank You Note', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
          const SizedBox(height: 4),
          TextField(
            controller: _footerCtrl,
            style: GoogleFonts.inter(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 5: LIVE INTERACTIVE A4 PREVIEW (SCREENSHOT 4 & 5)
  // =========================================================================
  Widget _buildSection5LiveA4Preview(Color activeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_rounded, size: 16, color: Color(0xFF0F172A)),
                const SizedBox(width: 6),
                Text('Live Interactive Preview', style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              ],
            ),
            Text('A4 High-Res Format', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 8),

        // A4 Paper Canvas Container
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: activeColor.withValues(alpha: 0.35), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Theme-colored Header Block (Statutory GST Store Banner)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showLogo) ...[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shree Ganesh Enterprises',
                            style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          if (_showTagline)
                            Text(
                              'Complete Kirana, FMCG & Wholesale Store',
                              style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.85)),
                            ),
                          if (_showOwnerPhone)
                            Text(
                              'Ph: +91 98220 12345 • Pune, Maharashtra',
                              style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          Text(
                            'GSTIN: 27AAAAA0000A1Z5 (27 Maharashtra)',
                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _selectedHeading,
                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('#INV-2026-0842', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text('11 Sep 2026', style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withValues(alpha: 0.8))),
                        Text('POS: 27 (MH)', style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 2. Billed To Card (B2B Buyer Details)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BILLED TO (BUYER / CUSTOMER):', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
                          Text('Arihant Retail Traders Pvt Ltd', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          Text('Mob: +91 98901 98765 • MIDC Industrial Area, Pune', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                          Row(
                            children: [
                              Text('Buyer GSTIN: ', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF64748B))),
                              Text('27AAACA1234F1Z8', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: activeColor)),
                              Text(' • State: 27 (MH)', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Text('PAID (UPI)', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 3. Table Header Bar (Statutory GST Columns)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text('ITEM DESCRIPTION', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                    Expanded(flex: 2, child: Text('HSN', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                    Expanded(flex: 2, child: Text('QTY', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                    Expanded(flex: 2, child: Text('RATE', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                    Expanded(flex: 2, child: Text('TAXABLE', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                    Expanded(flex: 2, child: Text('GST', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                    Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white))),
                  ],
                ),
              ),

              // 4. Sample Item Rows with GST Details
              _buildInvoicePreviewRow('Aashirvaad Shudh Atta (10kg)', '1101', '10 Bg', '₹420.00', '₹4,000.00', '₹200.00', '₹4,200.00'),
              _buildInvoicePreviewRow('Fortune Sunlite Oil (15L)', '1512', '4 Tin', '₹1,850.00', '₹7,047.62', '₹352.38', '₹7,400.00'),
              _buildInvoicePreviewRow('Dettol Antiseptic (500ml)', '3004', '12 Pc', '₹195.00', '₹1,983.05', '₹356.95', '₹2,340.00'),
              _buildInvoicePreviewRow('Cadbury Silk Pack', '1806', '6 Pc', '₹175.00', '₹889.83', '₹160.17', '₹1,050.00'),
              const Divider(height: 12),

              // 5. Amount in Words Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  'Amount in Words: Indian Rupees Fourteen Thousand Nine Hundred Ninety Only.',
                  style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                ),
              ),
              const SizedBox(height: 8),

              // 6. Mini GST Tax Slab Breakup Table
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TAX SLAB BREAKUP (GST SUMMARY)', style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(flex: 3, child: Text('HSN (RATE)', style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)))),
                        Expanded(flex: 2, child: Text('TAXABLE', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)))),
                        Expanded(flex: 2, child: Text('CGST', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)))),
                        Expanded(flex: 2, child: Text('SGST', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)))),
                        Expanded(flex: 2, child: Text('TOTAL TAX', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)))),
                      ],
                    ),
                    const Divider(height: 6),
                    _buildGstSummaryRow('1101, 1512 (5%)', '₹11,047.62', '₹276.19', '₹276.19', '₹552.38'),
                    _buildGstSummaryRow('3004, 1806 (18%)', '₹2,872.88', '₹258.56', '₹258.56', '₹517.12'),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 7. Payment Details & Totals Grid
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showDynamicUpiQr)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEEF2F6)),
                        ),
                        child: Row(
                          children: [
                            QrImageView(
                              data: 'upi://pay?pa=store@upi&pn=SampleStore&am=14990.00&cu=INR',
                              version: QrVersions.auto,
                              size: 38,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Instant UPI Pay', style: GoogleFonts.outfit(fontSize: 9.5, fontWeight: FontWeight.w800)),
                                  Text('ganeshent@icici', style: GoogleFonts.inter(fontSize: 8.5, color: const Color(0xFF64748B))),
                                  Text('✓ Verified Merchant', style: GoogleFonts.inter(fontSize: 7.5, color: const Color(0xFF059669), fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // Totals Column
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Taxable Value: ', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF64748B))),
                          Text('₹13,920.50', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Total GST: ', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF64748B))),
                          Text('₹1,069.50', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Grand Total: ₹14,990.00',
                          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 8. Platform Promotion Strip (Kamai+ Branding)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: activeColor, borderRadius: BorderRadius.circular(4)),
                      child: Text('⚡ KAMAI+ POS', style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "India's #1 Retail POS & GST Billing App",
                        style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                      ),
                    ),
                    Text(
                      'www.kamaiplus.com',
                      style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: activeColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // 9. Footer Terms & Signatory
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _footerCtrl.text.isNotEmpty ? _footerCtrl.text : 'Thank you for shopping with us! Visit again.',
                    style: GoogleFonts.inter(fontSize: 8.5, fontStyle: FontStyle.italic, color: const Color(0xFF64748B)),
                  ),
                  if (_showSignatory)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('For SHREE GANESH ENT.', style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                        Text('AUTHORISED SIGNATORY', style: GoogleFonts.inter(fontSize: 7, fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInvoicePreviewRow(String name, String hsn, String qty, String rate, String taxable, String gst, String total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(name, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(hsn, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)))),
          Expanded(flex: 2, child: Text(qty, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)))),
          Expanded(flex: 2, child: Text(rate, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF475569)))),
          Expanded(flex: 2, child: Text(taxable, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF475569)))),
          Expanded(flex: 2, child: Text(gst, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B)))),
          Expanded(flex: 2, child: Text(total, textAlign: TextAlign.right, style: GoogleFonts.outfit(fontSize: 8.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)))),
        ],
      ),
    );
  }

  Widget _buildGstSummaryRow(String slab, String taxable, String cgst, String sgst, String total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(slab, style: GoogleFonts.inter(fontSize: 7.5, color: const Color(0xFF334155)))),
          Expanded(flex: 2, child: Text(taxable, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, color: const Color(0xFF334155)))),
          Expanded(flex: 2, child: Text(cgst, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, color: const Color(0xFF334155)))),
          Expanded(flex: 2, child: Text(sgst, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 7.5, color: const Color(0xFF334155)))),
          Expanded(flex: 2, child: Text(total, textAlign: TextAlign.right, style: GoogleFonts.outfit(fontSize: 7.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)))),
        ],
      ),
    );
  }
}
