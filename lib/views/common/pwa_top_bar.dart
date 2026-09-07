import 'upi_standee_modal.dart';
import 'pro_upgrade_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../settings/store_profile_screen.dart';
import '../growth/growth_campaigns_screen.dart';

class PwaTopBar extends StatefulWidget implements PreferredSizeWidget {
  const PwaTopBar({super.key});

  @override
  State<PwaTopBar> createState() => _PwaTopBarState();

  @override
  Size get preferredSize => const Size.fromHeight(62);
}

class _PwaTopBarState extends State<PwaTopBar> {
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

  @override
  Widget build(BuildContext context) {
    final storeName = _profile.storeName.isNotEmpty ? _profile.storeName : 'KamaiPlus Store';
    final categoryClean = _profile.category.isNotEmpty
        ? (_profile.category.contains('/') ? _profile.category.split('/').first.trim() : _profile.category)
        : 'Retail';
    final ownerSubtitle = '${_profile.ownerName.isNotEmpty ? _profile.ownerName : "Store Owner"} • $categoryClean';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF2F6), width: 1.2)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Pro Badge
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => ProUpgradeModal.show(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
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
                        const SizedBox(width: 3),
                        Text(
                          'Pro',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 2. Official Counter UPI Standee QR Button
              _buildSquareButton(
                icon: Icons.qr_code_2_rounded,
                iconColor: const Color(0xFF334155),
                onTap: () {
                  UpiStandeeModal.show(context);
                },
              ),
              const SizedBox(width: 6),

              // 3. Official WhatsApp Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GrowthCampaignsScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/images/whatsapp_logo.png',
                      width: 18,
                      height: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 4. Store Details & Avatar Button (Responsive Right aligned)
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StoreProfileScreen()),
                    );
                    _loadProfile();
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 1),
                                Flexible(
                                  child: Text(
                                    storeName,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              ownerSubtitle,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                color: const Color(0xFF64748B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1528),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1E293B)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          size: 18,
                          color: Color(0xFFF59E0B),
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

  Widget _buildSquareButton({
    required IconData icon,
    required Color iconColor,
    Color? bgColor,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bgColor ?? Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor ?? const Color(0xFFE2E8F0)),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}
