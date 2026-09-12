import 'package:flutter/services.dart';
import '../../services/soundbox_service.dart';
import 'upi_standee_modal.dart';
import 'pro_upgrade_modal.dart';
import 'store_logo_avatar.dart';
import 'in_app_notification.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../settings/store_profile_screen.dart';

class PwaTopBar extends StatefulWidget implements PreferredSizeWidget {
  const PwaTopBar({super.key});

  @override
  State<PwaTopBar> createState() => _PwaTopBarState();

  @override
  Size get preferredSize => const Size.fromHeight(62);
}

class _PwaTopBarState extends State<PwaTopBar> {
  StoreProfileModel _profile = StoreProfileModel();
  bool _isSoundboxEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _isSoundboxEnabled = SoundboxService.instance.isAudioEnabled;
  }

  Future<void> _loadProfile() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  Future<void> _toggleSoundbox() async {
    HapticFeedback.mediumImpact();
    final newState = !_isSoundboxEnabled;
    await SoundboxService.instance.setAudioEnabled(newState);
    if (!mounted) return;
    setState(() => _isSoundboxEnabled = newState);
    InAppNotification.show(
      context: context,
      message: newState
          ? 'Voice Soundbox ON (Payment bolkar batayega)'
          : 'Voice Soundbox MUTE (Audio off hai)',
      customIcon: newState ? Icons.volume_up_rounded : Icons.volume_off_rounded,
      customColor: newState ? const Color(0xFF059669) : const Color(0xFF475569),
    );
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
              ValueListenableBuilder<bool>(
                valueListenable: FirestoreSyncService.isProNotifier,
                builder: (context, isProLive, _) {
                  final isPro = _profile.isProEffective || isProLive;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => ProUpgradeModal.show(context).then((_) => _loadProfile()),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isPro
                                ? const [Color(0xFF059669), Color(0xFF10B981)]
                                : const [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: isPro
                                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                  : const Color(0xFFF59E0B).withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPro ? Icons.verified_rounded : Icons.stars_rounded,
                              size: 13,
                              color: isPro ? Colors.white : const Color(0xFF0F172A),
                            ),
                            const SizedBox(width: 3.5),
                            Text(
                              isPro ? '★ Pro' : 'Pro',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isPro ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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

              // 3. Voice Soundbox Audio Toggle Button (Mute / Unmute)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleSoundbox,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _isSoundboxEnabled ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSoundboxEnabled ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      _isSoundboxEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      size: 19,
                      color: _isSoundboxEnabled ? const Color(0xFF059669) : const Color(0xFF64748B),
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
                      StoreLogoAvatar(
                        logoUrl: _profile.logoUrl,
                        size: 34,
                        radius: 10,
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
