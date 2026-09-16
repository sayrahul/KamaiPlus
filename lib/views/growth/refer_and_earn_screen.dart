import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../services/remote_config_service.dart';
import '../../services/referral_service.dart';
import '../common/in_app_notification.dart';

class ReferAndEarnScreen extends StatefulWidget {
  const ReferAndEarnScreen({super.key});

  @override
  State<ReferAndEarnScreen> createState() => _ReferAndEarnScreenState();
}

class _ReferAndEarnScreenState extends State<ReferAndEarnScreen> {
  String _referralCode = '';
  String _storeName = '';
  ReferralStats _stats = ReferralStats(totalInvited: 0, storesActivated: 0, freeDaysEarned: 0);
  bool _isLoading = true;
  final TextEditingController _claimCodeCtrl = TextEditingController();
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  @override
  void dispose() {
    _claimCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReferralData() async {
    try {
      final code = await ReferralService.instance.getMerchantReferralCode();
      final stats = await ReferralService.instance.getStats();
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() {
          _referralCode = code;
          _stats = stats;
          _storeName = profile.storeName;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyCode() async {
    HapticFeedback.selectionClick();
    await ReferralService.instance.copyCode(_referralCode);
    if (!mounted) return;
    InAppNotification.show(
      context: context,
      message: '✓ Referral code copied: $_referralCode',
      customIcon: Icons.content_copy_rounded,
      customColor: const Color(0xFF059669),
    );
  }

  Future<void> _shareWhatsApp() async {
    HapticFeedback.lightImpact();
    await ReferralService.instance.shareOnWhatsApp(_referralCode, storeName: _storeName);
    await _loadReferralData();
  }

  Future<void> _shareOther() async {
    HapticFeedback.lightImpact();
    await ReferralService.instance.shareGeneral(_referralCode, storeName: _storeName);
    await _loadReferralData();
  }

  Future<void> _claimCode() async {
    final raw = _claimCodeCtrl.text.trim();
    if (raw.isEmpty) {
      InAppNotification.error('Please enter a referral code', context: context);
      return;
    }
    setState(() => _isClaiming = true);
    final res = await ReferralService.instance.applyReferralCode(raw);
    if (!mounted) return;
    setState(() => _isClaiming = false);
    if (res.success) {
      _claimCodeCtrl.clear();
      await _loadReferralData();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.celebration_rounded, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              Text('Bonus Unlocked!', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Text(
            res.message,
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
              child: const Text('Great!'),
            ),
          ],
        ),
      );
    } else {
      InAppNotification.error(res.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Refer & Earn',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.card_giftcard_rounded, size: 13, color: Color(0xFFB45309)),
                const SizedBox(width: 4),
                Text(
                  '30D FREE PRO',
                  style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w900, color: const Color(0xFF92400E)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. COMPACT HERO CARD
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 18),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Invite Merchants • Get ${RemoteConfigService.instance.referralRewardDays} Days Free PRO',
                                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                  Text(
                                    'When referred store starts billing, you earn ${RemoteConfigService.instance.referralRewardDays} days of PRO.',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 3-Step Milestone Graphic
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildMilestonePill('1', 'Share Code', Icons.share_rounded),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF64748B)),
                              _buildMilestonePill('2', 'Friend Bills', Icons.receipt_long_rounded),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF64748B)),
                              _buildMilestonePill('3', '30d Free PRO', Icons.card_giftcard_rounded, isHighlight: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. REFERRAL CODE & SHARING CARD
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR REFERRAL CODE',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _referralCode,
                                style: GoogleFonts.spaceMono(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                  letterSpacing: 2,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _copyCode,
                                icon: const Icon(Icons.copy_rounded, size: 13),
                                label: const Text('Copy'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  textStyle: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Action Buttons in Single Row
                        Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: SizedBox(
                                height: 42,
                                child: ElevatedButton.icon(
                                  onPressed: _shareWhatsApp,
                                  icon: const Icon(Icons.send_rounded, size: 16),
                                  label: Text(
                                    'Share on WhatsApp',
                                    style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: SizedBox(
                                height: 42,
                                child: OutlinedButton.icon(
                                  onPressed: _shareOther,
                                  icon: const Icon(Icons.share_rounded, size: 14, color: Color(0xFF0F172A)),
                                  label: Text(
                                    'More Apps',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3. REWARDS STATS RIBBON
                  Row(
                    children: [
                      Expanded(child: _buildCompactStat('👥 Invited', '${_stats.totalInvited}', 'Merchants')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactStat('⚡ Active', '${_stats.storesActivated}', 'Stores Billing')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactStat('🎁 Earned', '${_stats.freeDaysEarned}d', 'Free PRO Days', isGold: true)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 4. CLAIM INVITATION CODE CARD
                  if (_stats.appliedReferralCode == null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD97706), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Have a Referral Code?',
                                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                              ),
                              const Spacer(),
                              Text(
                                'GET 30 DAYS FREE',
                                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _claimCodeCtrl,
                                    textCapitalization: TextCapitalization.characters,
                                    style: GoogleFonts.spaceMono(fontSize: 13, fontWeight: FontWeight.w700),
                                    decoration: InputDecoration(
                                      hintText: 'Enter friend\'s code (e.g. KAMAI99)',
                                      hintStyle: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.4)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 38,
                                child: ElevatedButton(
                                  onPressed: _isClaiming ? null : _claimCode,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    elevation: 0,
                                  ),
                                  child: _isClaiming
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                                      : Text('Claim Bonus', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF059669)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Referral Code "${_stats.appliedReferralCode}" applied • ${RemoteConfigService.instance.referralRewardDays} Days Free PRO Unlocked',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF065F46)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMilestonePill(String step, String label, IconData icon, {bool isHighlight = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isHighlight ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isHighlight ? const Color(0xFF0F172A) : Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isHighlight ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStat(String label, String value, String sub, {bool isGold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isGold ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isGold ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isGold ? const Color(0xFFB45309) : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isGold ? const Color(0xFF92400E) : const Color(0xFF64748B),
            ),
          ),
          Text(
            sub,
            style: GoogleFonts.inter(fontSize: 8.5, color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}
