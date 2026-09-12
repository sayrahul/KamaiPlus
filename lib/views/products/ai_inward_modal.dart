import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/csv_inward_service.dart';
import '../purchases/ai_inward_sheet.dart';
import '../purchases/bill_scan_review_sheet.dart';
import 'rapid_barcode_inward_screen.dart';
import '../common/in_app_notification.dart';

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

  Future<void> _handleCsvImport(BuildContext context) async {
    Navigator.of(context).pop();
    final res = await CsvInwardService.pickAndParseCsv();
    if (!context.mounted) return;

    if (!res.success) {
      InAppNotification.error(res.errorMessage ?? 'Could not parse CSV file.', context: context);
      return;
    }

    BillScanReviewSheet.show(
      context,
      items: res.items,
      billNumber: res.fileName != null ? 'FILE-${res.fileName}' : null,
      onInwardComplete: onInwardSuccess,
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
                      'AI Wholesale Inward & Restock',
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
                        'REAL OCR',
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
              'Scan wholesale invoices, mandi slips, or upload PDFs/CSVs to auto-add products, prices & stock.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),

            // Option 0: Rapid Continuous Barcode Inward (SUPER FAST)
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
              subtitle: 'Scan 20–30 items continuously with instant auto-fill',
              onTap: () {
                Navigator.pop(context);
                RapidBarcodeInwardScreen.show(context, onInwardSuccess: onInwardSuccess);
              },
            ),
            const SizedBox(height: 10),

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
              onTap: () {
                Navigator.pop(context);
                AiInwardSheet.show(context, onInwardComplete: onInwardSuccess);
              },
            ),
            const SizedBox(height: 10),

            // Option 2: Upload Invoice PDF
            _buildOptionCard(
              context: context,
              icon: Icons.picture_as_pdf_outlined,
              iconColor: const Color(0xFF2563EB),
              iconBgColor: const Color(0xFFEFF6FF),
              borderColor: const Color(0xFFBFDBFE),
              title: 'Upload Invoice PDF',
              badgeLabel: 'AI VISION',
              badgeBg: const Color(0xFFEFF6FF),
              badgeColor: const Color(0xFF1D4ED8),
              subtitle: 'Single or multi-page digital invoice document',
              onTap: () {
                Navigator.pop(context);
                AiInwardSheet.show(context, onInwardComplete: onInwardSuccess);
              },
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
              badgeLabel: '100% OFFLINE',
              badgeBg: const Color(0xFFECFDF5),
              badgeColor: const Color(0xFF047857),
              subtitle: 'Spreadsheet with item names, prices & stock (<20ms)',
              onTap: () => _handleCsvImport(context),
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
