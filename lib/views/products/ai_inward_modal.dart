import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AiInwardModal extends StatelessWidget {
  final VoidCallback onSelectManual;
  final VoidCallback onInwardSuccess;

  const AiInwardModal({
    super.key,
    required this.onSelectManual,
    required this.onInwardSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onSelectManual,
    required VoidCallback onInwardSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AiInwardModal(
        onSelectManual: onSelectManual,
        onInwardSuccess: onInwardSuccess,
      ),
    );
  }

  void _simulateAiScan(BuildContext context, String modeName) {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFD97706), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI Vision OCR Extraction',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extracted from: $modeName (Wholesale Invoice #INV-8832)',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            _buildExtractedRow('Fortune Sunlite Oil (1L)', '24 Pcs', '₹125.00', '₹145.00'),
            const SizedBox(height: 6),
            _buildExtractedRow('Tata Sampann Toor Dal (1kg)', '30 Pcs', '₹140.00', '₹165.00'),
            const SizedBox(height: 6),
            _buildExtractedRow('Aashirvaad Chakki Atta (10kg)', '15 Pcs', '₹380.00', '₹425.00'),
            const Divider(height: 20, color: Color(0xFFE2E8F0)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Inward Value:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(
                  '₹12,900.00',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onInwardSuccess();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '3 wholesale items added to catalog & stock updated!',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF0F172A),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Import to Catalog', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedRow(String name, String qty, String cost, String sell) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                Text(name, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                Text('$qty • Cost: $cost', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          Text(sell, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
        ],
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
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 25,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Title + AI Vision Badge + Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Wholesale Invoice & Inward',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Text(
                        'AI VISION',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ],
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Scan wholesale invoices, parchas, or upload PDFs to auto-add products, prices & stock.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),

            // Option 1: Scan Bill / Parcha Photo (RECOMMENDED)
            _buildOptionCard(
              context: context,
              icon: Icons.camera_alt_outlined,
              iconColor: const Color(0xFFD97706),
              iconBgColor: const Color(0xFFFEF3C7),
              borderColor: const Color(0xFFFDE68A),
              title: 'Scan Bill / Parcha Photo',
              badgeLabel: 'RECOMMENDED',
              badgeBg: const Color(0xFFFEF3C7),
              badgeColor: const Color(0xFFB45309),
              subtitle: 'Camera photo of invoice, slip or wholesale parcha',
              onTap: () => _simulateAiScan(context, 'Parcha Photo Camera Scan'),
            ),
            const SizedBox(height: 10),

            // Option 2: Upload Invoice PDF (FASTER)
            _buildOptionCard(
              context: context,
              icon: Icons.picture_as_pdf_outlined,
              iconColor: const Color(0xFF2563EB),
              iconBgColor: const Color(0xFFEFF6FF),
              borderColor: const Color(0xFFBFDBFE),
              title: 'Upload Invoice PDF',
              badgeLabel: 'FASTER',
              badgeBg: const Color(0xFFEFF6FF),
              badgeColor: const Color(0xFF1D4ED8),
              subtitle: 'Single or multi-page digital invoice / tariff document',
              onTap: () => _simulateAiScan(context, 'PDF Invoice Import'),
            ),
            const SizedBox(height: 10),

            // Option 3: Upload Excel / CSV File (BULK)
            _buildOptionCard(
              context: context,
              icon: Icons.table_chart_outlined,
              iconColor: const Color(0xFF059669),
              iconBgColor: const Color(0xFFECFDF5),
              borderColor: const Color(0xFFA7F3D0),
              title: 'Upload Excel / CSV File',
              badgeLabel: 'BULK',
              badgeBg: const Color(0xFFECFDF5),
              badgeColor: const Color(0xFF047857),
              subtitle: 'Spreadsheet with item names, prices & stock',
              onTap: () => _simulateAiScan(context, 'CSV / Excel Spreadsheet'),
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
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
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
                            style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeLabel,
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: const Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
