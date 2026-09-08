import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../../services/razorpay_service.dart';

class ProMembershipScreen extends StatefulWidget {
  const ProMembershipScreen({super.key});

  @override
  State<ProMembershipScreen> createState() => _ProMembershipScreenState();
}

class _ProMembershipScreenState extends State<ProMembershipScreen> {
  bool _isAnnual = true;
  bool _isLoading = false;
  StoreProfileModel _profile = StoreProfileModel();

  final List<Map<String, dynamic>> _matrixSections = [
    {
      'title': 'COUNTER BILLING & SPEED',
      'icon': Icons.flash_on_rounded,
      'color': Color(0xFFF59E0B),
      'features': [
        {'name': 'Daily Counter Invoices', 'free': '30 Bills / Day', 'pro': 'Unlimited (<10ms)'},
        {'name': 'Offline SQLite Billing Engine', 'free': 'Included', 'pro': 'Included (Ultra-Fast)'},
        {'name': 'Multi-Billing Hold & Draft Tabs', 'free': 'Max 2 Tabs', 'pro': 'Unlimited Parallel Tabs'},
        {'name': 'Instant Barcode Camera Scanning', 'free': 'Basic', 'pro': 'High-Speed Rapid Scan'},
      ],
    },
    {
      'title': 'HARDWARE & THERMAL PRINTERS',
      'icon': Icons.print_rounded,
      'color': Color(0xFF2563EB),
      'features': [
        {'name': '58mm & 80mm Bluetooth Printers', 'free': 'Standard Format', 'pro': 'All ESC/POS Wireless'},
        {'name': 'Thermal Invoice Customization', 'free': 'Watermark', 'pro': 'Custom Logo + Header/Footer'},
        {'name': 'Cash Drawer Kick & Soundbox', 'free': 'Not Included', 'pro': 'Auto Pulse Kick + Voice Alert'},
        {'name': 'Barcode Studio & Label Maker', 'free': '5 / Day', 'pro': 'Unlimited Batch Printing'},
      ],
    },
    {
      'title': 'WHATSAPP CRM & KHATA UDHAR',
      'icon': Icons.chat_rounded,
      'color': Color(0xFF10B981),
      'features': [
        {'name': '1-Tap WhatsApp Tax Invoicing', 'free': 'Manual Copy', 'pro': 'Instant PDF + Message'},
        {'name': 'Digital Khata Customer Ledger', 'free': 'Basic Ledger', 'pro': 'Auto Due Reminders + UPI'},
        {'name': 'WhatsApp Growth Hub (Campaigns)', 'free': 'Not Included', 'pro': 'Birthday Radar + Deals'},
        {'name': 'Audio Voice Notes on Ledger', 'free': '3 per customer', 'pro': 'Unlimited Voice Memos'},
      ],
    },
    {
      'title': 'GST, ACCOUNTING & CLOUD',
      'icon': Icons.cloud_done_rounded,
      'color': Color(0xFF8B5CF6),
      'features': [
        {'name': 'Real-Time Encrypted Cloud Sync', 'free': 'Local Only', 'pro': 'Firestore Cloud Backup'},
        {'name': 'Multi-Device Cashier Staff Login', 'free': '1 Phone Only', 'pro': 'Unlimited Linked Phones'},
        {'name': 'GSTR-1 JSON & GSTR-3B Excel', 'free': 'PDF Only', 'pro': '1-Click CA Export Package'},
        {'name': 'Tally Prime / ERP XML Export', 'free': 'Not Included', 'pro': 'Direct Tally XML Format'},
      ],
    },
  ];

  final List<Map<String, String>> _faqs = [
    {
      'q': 'Will Kamai+ work when there is no internet at my counter?',
      'a': 'Yes, 100%! Kamai+ is built on an offline-first local SQLite engine. You can create bills, print thermal receipts, scan barcodes, and record udhar without any internet. When connectivity returns, your data automatically syncs to cloud backup in the background.',
    },
    {
      'q': 'Which Bluetooth thermal printers are compatible?',
      'a': 'Kamai+ supports all standard 58mm (2-inch) and 80mm (3-inch) ESC/POS Bluetooth printers, including Everycom, NGX, Pegasus, BluPrints, TVS, Rugtek, and generic thermal roll printers.',
    },
    {
      'q': 'Can my shop cashiers bill from their own smartphones?',
      'a': 'Yes! With the Pro Business plan, you can connect multiple staff smartphones to your shop profile. All transactions, inventory stock, and customer khata stay synchronized.',
    },
    {
      'q': 'How does the 7-day money-back guarantee work?',
      'a': 'If you are not completely delighted with Kamai+ Pro within your first 7 days, tap support or email us for an instant 100% refund without any questions asked.',
    },
    {
      'q': 'Can I claim GST input tax credit (ITC) on this plan?',
      'a': 'Yes! We provide an official B2B Tax Invoice with 18% GST ITC breakdown registered with your store GSTIN so you can claim full tax deduction.',
    },
  ];

  final List<bool> _faqExpanded = [true, false, false, false, false];

  @override
  void initState() {
    super.initState();
    _loadStoreProfile();
  }

  Future<void> _loadStoreProfile() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  void _handleSubscribe() {
    HapticFeedback.mediumImpact();
    final plan = _isAnnual ? 'annual' : 'monthly';
    setState(() => _isLoading = true);

    RazorpayService.instance.openCheckout(
      plan: plan,
      profile: _profile,
      onSuccess: (response) async {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await _loadStoreProfile();

        _showSuccessCelebrationDialog(response.paymentId ?? 'pay_success');
      },
      onError: (response) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment cancelled or incomplete: ${response.message ?? "Try again"}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _showSuccessCelebrationDialog(String paymentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                ),
              ),
              child: const Icon(Icons.workspace_premium_rounded, size: 38, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 16),
            Text(
              '🎉 Payment Successful!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Kamai+ Pro Business Plan is now active for ${_profile.storeName}.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(
                    'Payment ID: $paymentId',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF059669)),
                      const SizedBox(width: 6),
                      Text(
                        'Unlimited Billing (<10ms)',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF065F46)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF059669)),
                      const SizedBox(width: 6),
                      Text(
                        'All Bluetooth Thermal Printers Supported',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF065F46)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF059669)),
                      const SizedBox(width: 6),
                      Text(
                        'WhatsApp CRM & Real-time Cloud Sync',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF065F46)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Start Pro Billing 🚀',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final priceStr = _isAnnual ? '₹1,499' : '₹199';
    final billingCycle = _isAnnual ? '/ year' : '/ month';
    final monthlyBreakdown = _isAnnual ? 'Just ₹125 / month • 2 Months Free' : 'Billed monthly • Cancel anytime';

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kamai+ Membership Plans',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
            ),
            Text(
              'Official Retail Business License',
              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded, size: 13, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
                Text(
                  'Verified POS',
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HERO FINTECH CARD
            _buildHeroFintechCard(priceStr, billingCycle, monthlyBreakdown),
            const SizedBox(height: 16),

            // 2. ANNUAL vs MONTHLY TOGGLE
            _buildBillingSwitcher(),
            const SizedBox(height: 20),

            // 3. TIER COMPARISON CARDS (Free vs Pro vs Enterprise)
            _buildTierCards(),
            const SizedBox(height: 20),

            // 4. VALUE PROPOSITION / ROI CARD
            _buildRoiCard(),
            const SizedBox(height: 20),

            // 5. DEEP-DIVE FEATURE MATRIX
            _buildFeatureMatrix(),
            const SizedBox(height: 20),

            // 6. CURRENT STORE LICENSE DETAILS
            _buildLicenseDetailsCard(),
            const SizedBox(height: 20),

            // 7. TRUST & SECURITY BADGES
            _buildTrustBadges(),
            const SizedBox(height: 20),

            // 8. FAQS ACCORDION
            _buildFaqsAccordion(),
          ],
        ),
      ),
      bottomSheet: _buildBottomStickyBar(priceStr, billingCycle),
    );
  }

  // =========================================================================
  // 1. HERO FINTECH CARD
  // =========================================================================
  Widget _buildHeroFintechCard(String price, String cycle, String breakdown) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background decorative glow
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFF0F172A)),
                          const SizedBox(width: 4),
                          Text(
                            'PRO BUSINESS SUITE',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isAnnual)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'SAVE 50% TODAY',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF34D399),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Supercharge Your Counter.\nScale Your Retail Store.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.2,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Zero billing lags, instant WhatsApp invoices, automated customer udhar recovery, and encrypted cloud backup.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cycle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  breakdown,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF38BDF8),
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
  // 2. BILLING SWITCHER
  // =========================================================================
  Widget _buildBillingSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isAnnual = true);
              },
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _isAnnual ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: _isAnnual
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Annual Plan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: _isAnnual ? FontWeight.w800 : FontWeight.w600,
                        color: _isAnnual ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '50% OFF',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isAnnual = false);
              },
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: !_isAnnual ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: !_isAnnual
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Monthly (₹199)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: !_isAnnual ? FontWeight.w800 : FontWeight.w600,
                    color: !_isAnnual ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. TIER COMPARISON CARDS
  // =========================================================================
  Widget _buildTierCards() {
    return Column(
      children: [
        // Free Starter Tier
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Kamai+ Starter',
                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                  Text(
                    '₹0 / Free',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Good for testing basic single-counter retail billing',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              _buildTierBullet('Up to 30 bills per day', isIncluded: true),
              _buildTierBullet('Local SQLite offline storage', isIncluded: true),
              _buildTierBullet('Basic cash & UPI QR checkout', isIncluded: true),
              _buildTierBullet('Bluetooth printer branding & logo', isIncluded: false),
              _buildTierBullet('1-Tap WhatsApp marketing & reminders', isIncluded: false),
              _buildTierBullet('Encrypted cloud backup & multi-device', isIncluded: false),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Pro Business Tier (Elevated Highlight)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Kamai+ Pro Business',
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'MOST POPULAR',
                      style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Everything your retail store needs to run at maximum speed',
                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF78350F)),
              ),
              const SizedBox(height: 14),
              _buildTierBullet('Unlimited bills with zero counter lag (<10ms)', isIncluded: true, isHighlight: true),
              _buildTierBullet('All 58mm & 80mm wireless Bluetooth thermal printers', isIncluded: true, isHighlight: true),
              _buildTierBullet('1-Tap WhatsApp tax invoice & PDF dispatch', isIncluded: true, isHighlight: true),
              _buildTierBullet('Customer Khata ledger with auto payment links', isIncluded: true),
              _buildTierBullet('WhatsApp Growth Hub (Birthday radar & coupons)', isIncluded: true),
              _buildTierBullet('Encrypted Cloud Backup & Multi-device cashier login', isIncluded: true),
              _buildTierBullet('GSTR-1, GSTR-3B Excel & Tally Prime XML export', isIncluded: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTierBullet(String text, {required bool isIncluded, bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            isIncluded ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 15,
            color: isIncluded ? (isHighlight ? const Color(0xFFD97706) : const Color(0xFF059669)) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
                color: isIncluded ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 4. VALUE PROPOSITION / ROI CARD
  // =========================================================================
  Widget _buildRoiCard() {
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.savings_outlined, color: Color(0xFF059669), size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'HOW PRO PAYS FOR ITSELF',
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669), letterSpacing: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRoiRow('Save ~₹6,000 / year', 'on paper bill rolls by using digital WhatsApp receipts.'),
          _buildRoiRow('Recover 38% faster', 'pending customer Khata udhar dues via automated UPI links.'),
          _buildRoiRow('Save 12+ hours / month', 'on manual tax accounting with 1-click GSTR-1 & Tally exports.'),
        ],
      ),
    );
  }

  Widget _buildRoiRow(String boldText, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚡ ', style: TextStyle(fontSize: 12)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF334155), height: 1.3),
                children: [
                  TextSpan(text: '$boldText ', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. DEEP-DIVE FEATURE MATRIX
  // =========================================================================
  Widget _buildFeatureMatrix() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'CAPABILITY',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'FREE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'PRO',
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFFFBBF24), letterSpacing: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEF2F6)),

          // Sections
          ..._matrixSections.map((sec) {
            final List<Map<String, String>> fList = sec['features'];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFFFAFAFE),
                  child: Row(
                    children: [
                      Icon(sec['icon'], size: 14, color: sec['color']),
                      const SizedBox(width: 6),
                      Text(
                        sec['title'],
                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: sec['color'], letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                ...fList.map((f) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            f['name']!,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            f['free']!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  f['pro']!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          }),
        ],
      ),
    );
  }

  // =========================================================================
  // 6. CURRENT STORE LICENSE DETAILS
  // =========================================================================
  Widget _buildLicenseDetailsCard() {
    final storeName = _profile.storeName.isNotEmpty ? _profile.storeName : 'KamaiPlus Retail Store';
    final storePhone = _profile.phone.isNotEmpty ? _profile.phone : '+91 98765 43210';

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR STORE LICENSE',
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ACTIVE LICENSE',
                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded, color: Color(0xFF0F172A), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      'Registered Mobile: $storePhone',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 7. TRUST & SECURITY BADGES
  // =========================================================================
  Widget _buildTrustBadges() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTrustPill(Icons.verified_user_rounded, '100% Secure\nUPI & RuPay'),
          _buildTrustPill(Icons.receipt_long_rounded, '18% GST Input\nCredit (ITC)'),
          _buildTrustPill(Icons.history_rounded, '7-Day Money\nBack Guarantee'),
        ],
      ),
    );
  }

  Widget _buildTrustPill(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF0F172A)),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155), height: 1.15),
        ),
      ],
    );
  }

  // =========================================================================
  // 8. FAQS ACCORDION
  // =========================================================================
  Widget _buildFaqsAccordion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FREQUENTLY ASKED QUESTIONS',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        ...List.generate(_faqs.length, (i) {
          final faq = _faqs[i];
          final isExp = _faqExpanded[i];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _faqExpanded[i] = !isExp);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            faq['q']!,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                          ),
                        ),
                        Icon(
                          isExp ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: const Color(0xFF64748B),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExp) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Text(
                      faq['a']!,
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF475569), height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  // =========================================================================
  // 9. STICKY BOTTOM BAR
  // =========================================================================
  Widget _buildBottomStickyBar(String price, String cycle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: const Border(top: BorderSide(color: Color(0xFFEEF2F6))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profile.isPro ? 'Pro Active' : '$price $cycle',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    color: _profile.isPro ? const Color(0xFF059669) : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  _profile.isPro
                      ? (_profile.proExpiry.isNotEmpty ? 'Renews: ${_profile.proExpiry.substring(0, 10)}' : 'License Active')
                      : '100% Tax Deductible (GST)',
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF059669), fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _profile.isPro ? const Color(0xFF059669) : const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _profile.isPro ? Icons.verified_rounded : Icons.stars_rounded,
                            color: const Color(0xFFFBBF24),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _profile.isPro ? 'Extend Pro via Razorpay' : 'Upgrade via Razorpay',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
