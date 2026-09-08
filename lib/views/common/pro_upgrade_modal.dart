import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../settings/pro_membership_screen.dart';
import '../../services/razorpay_service.dart';

class ProUpgradeModal extends StatefulWidget {
  const ProUpgradeModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC020617), // Slate 950 with 80% opacity
      builder: (ctx) => const ProUpgradeModal(),
    );
  }

  @override
  State<ProUpgradeModal> createState() => _ProUpgradeModalState();
}

class _ProUpgradeModalState extends State<ProUpgradeModal> {
  bool _isAnnual = true;
  bool _isLoading = false;
  StoreProfileModel _profile = StoreProfileModel();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  void _handleUpgrade() {
    setState(() => _isLoading = true);
    final plan = _isAnnual ? 'annual' : 'monthly';

    RazorpayService.instance.openCheckout(
      plan: plan,
      profile: _profile,
      onSuccess: (response) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFFBBF24), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🎉 Kamai+ Pro Activated! Payment ID: ${response.paymentId ?? ""}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
      onError: (response) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment cancelled or failed: ${response.message ?? "Try again"}'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final businessTitle = _profile.ownerName.isNotEmpty
        ? _profile.ownerName
        : (_profile.storeName.isNotEmpty ? _profile.storeName : 'Rahul Shramas');

    final priceAmount = _isAnnual ? '1499' : '199';
    final originalPrice = _isAnnual ? '2998' : '398';
    final periodText = _isAnnual ? '/ year' : '/ month';
    final billingSubtext = _isAnnual
        ? 'Just ₹125 / month • Instant 1-Year Access'
        : 'Billed monthly • Cancel anytime';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. TOP HEADER WITH GRADIENT TINT
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFDF5),
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Unlock Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBBF24),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.stars_rounded, size: 13, color: Color(0xFF0F172A)),
                              const SizedBox(width: 4),
                              Text(
                                'UNLOCK FULL POS POWER',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Close Button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Upgrade to Kamai+ Pro',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      businessTitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SCROLLABLE MODAL BODY
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Toggle Switcher (Annual vs Monthly)
                      Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isAnnual = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _isAnnual ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: _isAnnual
                                        ? Border.all(color: const Color(0xFFCBD5E1), width: 1)
                                        : null,
                                    boxShadow: _isAnnual
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 3,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Annual (₹1,499 / yr - 50% Off) 🔥',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _isAnnual
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isAnnual = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !_isAnnual ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: !_isAnnual
                                        ? Border.all(color: const Color(0xFFCBD5E1), width: 1)
                                        : null,
                                    boxShadow: !_isAnnual
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 3,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Monthly (₹199 / mo)',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: !_isAnnual
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Highlighted Pricing Card
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFDE68A), width: 1.4),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '₹$originalPrice',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF94A3B8),
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₹$priceAmount',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  periodText,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              billingSubtext,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Free Forever Features Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('🎁 ', style: TextStyle(fontSize: 12)),
                                Text(
                                  '100% FREE FOREVER ON ALL ACCOUNTS:',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                    color: const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildFreeItem('Unlimited POS Billing'),
                                      const SizedBox(height: 4),
                                      _buildFreeItem('Customer Khata Ledger'),
                                      const SizedBox(height: 4),
                                      _buildFreeItem('Thermal & PDF Invoices'),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildFreeItem('100% Offline Database'),
                                      const SizedBox(height: 4),
                                      _buildFreeItem('Full JSON Backup/Restore'),
                                      const SizedBox(height: 4),
                                      _buildFreeItem('Dynamic UPI QR on Bills'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Pro Unlocked Features
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('⚡ ', style: TextStyle(fontSize: 12)),
                              Text(
                                'WHAT YOU UNLOCK WITH PRO:',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                  color: const Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildProFeature('Automatic Cloud Backup & Multi-Device Sync'),
                          const SizedBox(height: 6),
                          _buildProFeature('Batch Numbers & Expiry Date Radar (15/30 Days Alert)'),
                          const SizedBox(height: 6),
                          _buildProFeature('Government GSTR-1 & HSN Tax Filing Reports'),
                          const SizedBox(height: 6),
                          _buildProFeature('Custom Barcode Sticker Label Printing Studio'),
                          const SizedBox(height: 6),
                          _buildProFeature('WhatsApp Festival Greetings & Customer Win-Back'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Upgrade CTA Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isLoading ? null : _handleUpgrade,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Color(0xFF0F172A),
                                      ),
                                    )
                                  : Text(
                                      'Upgrade to Kamai+ Pro (₹$priceAmount) 🚀',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Trust Footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🔒 ', style: TextStyle(fontSize: 10)),
                          Flexible(
                            child: Text(
                              '256-bit Secure Payment via Razorpay UPI & Cards • Instant Invoice with 18% GST ITC',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProMembershipScreen()),
                          );
                        },
                        child: Text(
                          'Compare Free vs Pro Plans & FAQs →',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFreeItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '✓ ',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProFeature(String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_rounded,
          size: 16,
          color: Color(0xFF059669),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
