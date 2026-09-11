import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../settings/pro_membership_screen.dart';
import '../../services/razorpay_service.dart';
import '../../services/firestore_sync_service.dart';

class ProUpgradeModal extends StatefulWidget {
  const ProUpgradeModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC020617), // Deep obsidian slate overlay
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
    HapticFeedback.mediumImpact();
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
    if (_profile.isProEffective || FirestoreSyncService.isProNotifier.value) {
      return _buildAlreadyProDialog(context);
    }

    final businessTitle = _profile.storeName.isNotEmpty
        ? _profile.storeName
        : (_profile.ownerName.isNotEmpty ? _profile.ownerName : 'Retail Merchant');

    final priceAmount = _isAnnual ? '1,499' : '199';
    final periodText = _isAnnual ? '/ year' : '/ month';
    final billingSubtext = _isAnnual
        ? 'Just ₹125 / month • Instant 1-Year Full Access'
        : 'Billed monthly • Cancel anytime';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xF51E293B), // Slate 800 glass
                  Color(0xF50F172A), // Slate 900 glass
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  blurRadius: 36,
                  spreadRadius: -4,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. TOP HEADER (Glass Frost)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Pro Glow Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF0F172A)),
                                const SizedBox(width: 4.5),
                                Text(
                                  'KAMAI+ PRO',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
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
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Unlock Full Store Power',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.storefront_rounded, size: 14, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              businessTitle,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. SCROLLABLE BODY
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Dual Plan Toggle Cards
                        Row(
                          children: [
                            // Annual Plan Card
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _isAnnual = true);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: _isAnnual
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _isAnnual ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: 0.08),
                                      width: _isAnnual ? 1.6 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Annual',
                                            style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: _isAnnual ? const Color(0xFFFDE68A) : Colors.white70,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF059669),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '50% OFF',
                                              style: GoogleFonts.inter(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '₹1,499 / yr',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        '₹125 / month',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF34D399),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Monthly Plan Card
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _isAnnual = false);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: !_isAnnual
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: !_isAnnual ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: 0.08),
                                      width: !_isAnnual ? 1.6 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Monthly',
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: !_isAnnual ? const Color(0xFFFDE68A) : Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '₹199 / mo',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Cancel anytime',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Subtitle note
                        Center(
                          child: Text(
                            billingSubtext,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFDE68A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Pro Unlocked Features Glass Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFFBBF24)),
                                  const SizedBox(width: 5),
                                  Text(
                                    'ALL PRO CAPABILITIES INCLUDED:',
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                      color: const Color(0xFFFDE68A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildGlassFeature('Cloud Backup & Multi-Device Realtime Sync'),
                              const SizedBox(height: 7),
                              _buildGlassFeature('Govt GSTR-1 Tax Filing & HSN CA Reports'),
                              const SizedBox(height: 7),
                              _buildGlassFeature('Batch & Expiry Radar with Shelf-Life Alerts'),
                              const SizedBox(height: 7),
                              _buildGlassFeature('Custom Barcode Label Sticker Print Studio'),
                              const SizedBox(height: 7),
                              _buildGlassFeature('Custom Logo on Invoices (Zero Watermark)'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Upgrade CTA Button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : _handleUpgrade,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Color(0xFF0F172A),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Upgrade to Kamai+ Pro • ₹$priceAmount $periodText',
                                            style: GoogleFonts.outfit(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w900,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF0F172A)),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Trust Security Note
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF64748B)),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '256-bit Secure Razorpay UPI • 7-Day Money Back • 18% GST ITC',
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

                        // Compare Plans Link
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProMembershipScreen()),
                              );
                            },
                            child: Text(
                              'Compare Free vs Pro Plans & FAQs →',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF38BDF8),
                              ),
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
      ),
    );
  }

  Widget _buildGlassFeature(String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Color(0xFF065F46),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 12,
            color: Color(0xFF34D399),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE2E8F0),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlreadyProDialog(BuildContext context) {
    final businessTitle = _profile.storeName.isNotEmpty
        ? _profile.storeName
        : (_profile.ownerName.isNotEmpty ? _profile.ownerName : 'Retail Merchant');

    DateTime? expiryDate;
    if (_profile.proExpiry.isNotEmpty) {
      expiryDate = DateTime.tryParse(_profile.proExpiry);
    }
    final formattedExpiry = expiryDate != null
        ? DateFormat('dd MMMM yyyy').format(expiryDate)
        : 'Active / 1-Year License';

    final planTitle = _profile.proPlan.isNotEmpty && _profile.proPlan != 'free'
        ? 'KAMAI+ ${_profile.proPlan.toUpperCase()} TIER'
        : 'KAMAI+ PRO BUSINESS TIER';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xF5064E3B), // Emerald 900 glass
                  Color(0xF5022C22), // Deep Forest glass
                  Color(0xF50F172A), // Slate 900
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                  blurRadius: 36,
                  spreadRadius: -4,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Close Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded, size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              'VERIFIED PRO',
                              style: GoogleFonts.outfit(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Hero Center Badge
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF34D399), Color(0xFF059669)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.workspace_premium_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'You are a Pro Member! 🎉',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aapka store $businessTitle full power par chal raha hai. Sabhi premium retail features 100% unlocked hain.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFFCBD5E1),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // License Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              planTitle,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF34D399),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF065F46),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '● ACTIVE',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF6EE7B7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.event_available_rounded, size: 14, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Text(
                              'Valid until: $formattedExpiry',
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFE2E8F0)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 4 Unlocked Feature Badges Grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildGlassFeature('Unlimited Counter Billing & Parallel Hold Tabs'),
                      const SizedBox(height: 8),
                      _buildGlassFeature('Bluetooth Thermal (58/80mm) & Auto Cash Drawer'),
                      const SizedBox(height: 8),
                      _buildGlassFeature('Official GSTR-1, Tally XML & Real CA Audit Pack'),
                      const SizedBox(height: 8),
                      _buildGlassFeature('Real-time Encrypted Cloud Sync & WhatsApp Ledger'),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Action Buttons Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      // WhatsApp Priority Support
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            final uri = Uri.parse('https://wa.me/919595997711?text=Hello%20KamaiPlus%20Team%2C%20I%20am%20a%20Pro%20Subscriber%20for%20store%20$businessTitle');
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {}
                          },
                          icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
                          label: Text(
                            'VIP Support',
                            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Primary Close Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            'Done',
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
