import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'menu_scan_sheet.dart';
import 'rapid_barcode_inward_screen.dart';

/// Restaurant's equivalent of [AiInwardModal] — restaurant never gets that
/// sheet directly because its "Scan Bill / Parcha", "Upload Invoice PDF" and
/// "Upload Excel/CSV" options are all modelled around a wholesale supplier
/// bill, which a restaurant doesn't have (`toggles.hasBillScan == false`).
///
/// Previously, tapping "Inward with AI" on the restaurant Products screen
/// jumped straight into [MenuScanSheet] with no other option — if the
/// merchant hadn't configured a Gemini API key yet, that was a dead end with
/// no visible way to add a dish any other way from that entry point. This
/// sheet gives restaurant the same "pick how you want to add" pattern
/// grocery/pharmacy/clothing/hardware already get: a barcode-based option
/// (for packaged items like bottled drinks — genuinely has real EAN
/// barcodes, unlike a hand-written dish) sits alongside the AI menu scan and
/// a plain manual add, so a missing API key never blocks adding a dish.
class RestaurantInwardOptionsSheet extends StatelessWidget {
  final VoidCallback onMenuAddSuccess;
  final VoidCallback onSelectManual;

  const RestaurantInwardOptionsSheet({
    super.key,
    required this.onMenuAddSuccess,
    required this.onSelectManual,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onMenuAddSuccess,
    required VoidCallback onSelectManual,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RestaurantInwardOptionsSheet(
        onMenuAddSuccess: onMenuAddSuccess,
        onSelectManual: onSelectManual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 25, offset: Offset(0, -5)),
        ],
      ),
      padding: EdgeInsets.only(top: 12, left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Add to Menu',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick how you want to add a dish or packaged item.',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), height: 1.3),
            ),
            const SizedBox(height: 16),
            _buildOptionCard(
              context: context,
              icon: Icons.restaurant_menu_rounded,
              iconColor: const Color(0xFFD97706),
              iconBgColor: const Color(0xFFFEF3C7),
              borderColor: const Color(0xFFFDE68A),
              title: 'Scan Menu Photo',
              badgeLabel: 'AI VISION',
              badgeBg: const Color(0xFFFEF3C7),
              badgeColor: const Color(0xFFB45309),
              subtitle: 'Camera or gallery photo of your printed menu',
              onTap: () {
                Navigator.pop(context);
                MenuScanSheet.show(context, onMenuAddSuccess: onMenuAddSuccess);
              },
            ),
            const SizedBox(height: 10),
            _buildOptionCard(
              context: context,
              icon: Icons.edit_note_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBgColor: const Color(0xFFEFF6FF),
              borderColor: const Color(0xFFBFDBFE),
              title: 'Add Dish Manually',
              badgeLabel: 'ALWAYS WORKS',
              badgeBg: const Color(0xFFEFF6FF),
              badgeColor: const Color(0xFF1D4ED8),
              subtitle: 'Type name, price & category — no photo needed',
              onTap: () {
                Navigator.pop(context);
                onSelectManual();
              },
            ),
            const SizedBox(height: 10),
            _buildOptionCard(
              context: context,
              icon: Icons.qr_code_scanner_rounded,
              iconColor: const Color(0xFF7C3AED),
              iconBgColor: const Color(0xFFF5F3FF),
              borderColor: const Color(0xFFDDD6FE),
              title: 'Rapid Barcode Inward',
              badgeLabel: 'LIGHTNING FAST ⚡',
              badgeBg: const Color(0xFFF5F3FF),
              badgeColor: const Color(0xFF6D28D9),
              subtitle: 'For packaged drinks, snacks & bottled items with a real barcode',
              onTap: () {
                Navigator.pop(context);
                RapidBarcodeInwardScreen.show(context, onInwardSuccess: onMenuAddSuccess);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required Color borderColor,
    required String title,
    required String badgeLabel,
    required Color badgeBg,
    required Color badgeColor,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.3),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            badgeLabel,
                            style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w900, color: badgeColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
