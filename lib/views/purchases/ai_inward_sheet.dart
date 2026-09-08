import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/gemini_ai_service.dart';
import '../../services/firestore_sync_service.dart';

class AiInwardSheet extends StatelessWidget {
  final VoidCallback? onInwardComplete;

  const AiInwardSheet({super.key, this.onInwardComplete});

  static Future<void> show(BuildContext context, {VoidCallback? onInwardComplete}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AiInwardSheet(onInwardComplete: onInwardComplete),
    );
  }

  void _showImageSourcePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Bill Photo Source',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFFD97706)),
                ),
                title: Text('Camera (Click Live Parcha)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                subtitle: Text('Capture paper bill or mandi slip directly', style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processImageScan(context, ImageSource.camera);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF2563EB)),
                ),
                title: Text('Gallery / Files', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                subtitle: Text('Pick photo from phone gallery or WhatsApp download', style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processImageScan(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processImageScan(BuildContext context, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!context.mounted) return;

      _runGeminiExtraction(context, bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open image picker: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _runGeminiExtraction(BuildContext context, Uint8List imageBytes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return FutureBuilder<AiInwardResult>(
            future: GeminiAiService.extractItemsFromImage(imageBytes),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                // Scanning viewfinder animation
                return AlertDialog(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.all(20),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.document_scanner_rounded, color: Color(0xFF34D399), size: 18),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Gemini 1.5 Vision OCR',
                                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'ANALYZING',
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF34D399)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF334155), width: 1.5),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.receipt_long_rounded, color: Color(0xFF64748B), size: 54),
                            Positioned(
                              bottom: 16,
                              child: Text(
                                'Reading rates, quantities & items...',
                                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF34D399), width: 2), left: BorderSide(color: Color(0xFF34D399), width: 2)))),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF34D399), width: 2), right: BorderSide(color: Color(0xFF34D399), width: 2)))),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF34D399), width: 2), left: BorderSide(color: Color(0xFF34D399), width: 2)))),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(width: 14, height: 14, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF34D399), width: 2), right: BorderSide(color: Color(0xFF34D399), width: 2)))),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                        backgroundColor: Color(0xFF334155),
                        minHeight: 4,
                      ),
                    ],
                  ),
                );
              }

              final res = snapshot.data;
              if (res == null || !res.success) {
                // Quota exceeded or error
                final isQuota = res?.isQuotaExceeded ?? false;
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isQuota ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(isQuota ? Icons.lock_rounded : Icons.error_outline, color: isQuota ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isQuota ? 'Monthly Limit Reached' : 'Scan Failed',
                          style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    res?.errorMessage ?? 'Could not parse bill slip. Please check photo clarity.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF475569)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text('Close', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
                    ),
                    if (isQuota)
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          Navigator.pushNamed(context, '/settings');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFBBF24),
                          foregroundColor: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Upgrade to Pro', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
                      ),
                  ],
                );
              }

              // SUCCESS: Review and confirm inward dialog
              final items = res.items;
              int totalCostPaise = items.fold<int>(0, (sum, it) => sum + (it.purchasePricePaise * it.quantity).round());

              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF059669), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Inward Extraction', style: GoogleFonts.plusJakartaSans(fontSize: 15.5, fontWeight: FontWeight.w800)),
                          Text('${items.length} Products Detected', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF059669), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (c, idx) {
                            final it = items[idx];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(it.productName, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Buy: ${MoneyFormatter.formatINR(it.purchasePricePaise)} • Sell: ${MoneyFormatter.formatINR(it.sellingPricePaise)}',
                                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      '${it.quantity % 1 == 0 ? it.quantity.toInt() : it.quantity} ${it.unit}',
                                      style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Inward Cost:', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                          Text(MoneyFormatter.formatINR(totalCostPaise), style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF059669))),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text('Discard', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(dialogCtx);
                      final bizId = FirestoreSyncService.instance.activeBusinessId;

                      // Save extracted items into SQLite database
                      for (final item in items) {
                        final prod = ProductModel(
                          id: const Uuid().v4(),
                          businessId: bizId,
                          name: item.productName,
                          purchasePricePaise: item.purchasePricePaise,
                          sellingPricePaise: item.sellingPricePaise,
                          mrpPaise: item.mrpPaise,
                          stockQuantity: item.quantity,
                          unit: item.unit,
                        );
                        await LocalDatabase.instance.upsertProduct(prod);
                      }

                      onInwardComplete?.call();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ ${items.length} items successfully inwarded to Inventory!'),
                            backgroundColor: const Color(0xFF059669),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Confirm & Save Stock', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _simulateFileScan(BuildContext context, String mode) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📄 Unlimited $mode Inward: Please upload file or select bill photo.'),
        backgroundColor: const Color(0xFF0284C7),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Text(
                'AI Wholesale Inward (OCR)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  'GEMINI 1.5',
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            'Scan mandi parchas or wholesale bills. 10 picture scans/month on Free (Unlimited on Pro).',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 18),

          // Option 1: Scan Photo [RECOMMENDED]
          _buildOptionCard(
            context: context,
            icon: Icons.camera_alt_rounded,
            iconBg: const Color(0xFFFFFBEB),
            iconColor: const Color(0xFFD97706),
            borderColor: const Color(0xFFFDE68A),
            title: 'Scan Bill / Parcha Photo',
            badge: 'GEMINI AI',
            badgeColor: const Color(0xFFD97706),
            subtitle: 'Camera or gallery photo of mandi slip or invoice',
            onTap: () {
              Navigator.pop(context);
              _showImageSourcePicker(context);
            },
          ),
          const SizedBox(height: 10),

          // Option 2: Upload PDF [UNLIMITED FREE]
          _buildOptionCard(
            context: context,
            icon: Icons.picture_as_pdf_rounded,
            iconBg: const Color(0xFFF0F9FF),
            iconColor: const Color(0xFF0284C7),
            borderColor: const Color(0xFFBAE6FD),
            title: 'Upload Invoice PDF',
            badge: 'FREE UNLIMITED',
            badgeColor: const Color(0xFF0284C7),
            subtitle: 'Single or multi-page digital invoice document',
            onTap: () => _simulateFileScan(context, 'PDF'),
          ),
          const SizedBox(height: 10),

          // Option 3: Upload Excel [UNLIMITED FREE]
          _buildOptionCard(
            context: context,
            icon: Icons.table_chart_rounded,
            iconBg: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF059669),
            borderColor: const Color(0xFFA7F3D0),
            title: 'Upload Excel / CSV File',
            badge: 'FREE UNLIMITED',
            badgeColor: const Color(0xFF059669),
            subtitle: 'Spreadsheet with item names, prices & stock',
            onTap: () => _simulateFileScan(context, 'Excel'),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required Color borderColor,
    required String title,
    required String badge,
    required Color badgeColor,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
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
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
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
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
    );
  }
}
