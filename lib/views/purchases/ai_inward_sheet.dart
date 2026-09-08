import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/csv_inward_service.dart';
import '../../services/gemini_ai_service.dart';
import 'bill_scan_review_sheet.dart';

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
                title: Text('Gallery / Photos', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                subtitle: Text('Pick bill photo from gallery or WhatsApp', style: GoogleFonts.plusJakartaSans(fontSize: 11)),
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

      _runExtraction(context, bytes, mimeType: 'image/jpeg', title: 'Analyzing Bill Photo');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _processPdfScan(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read PDF file.')),
          );
        }
        return;
      }

      if (!context.mounted) return;
      _runExtraction(context, bytes, mimeType: 'application/pdf', title: 'Parsing PDF Invoice');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Picker error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _processCsvScan(BuildContext context) async {
    try {
      final res = await CsvInwardService.pickAndParseCsv();
      if (!context.mounted) return;

      if (!res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorMessage ?? 'Failed to parse CSV/Excel file.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Open review sheet with parsed items
      BillScanReviewSheet.show(
        context,
        items: res.items,
        billNumber: res.fileName != null ? 'FILE-${res.fileName}' : null,
        onInwardComplete: onInwardComplete,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _runExtraction(
    BuildContext context,
    Uint8List bytes, {
    required String mimeType,
    required String title,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => FutureBuilder<AiInwardResult>(
        future: GeminiAiService.extractItemsFromImage(bytes, mimeType: mimeType),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Scanning viewfinder animation
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.all(22),
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
                            title,
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
                          'AI VISION',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF34D399)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 150,
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
                            'Reading items, quantities & wholesale rates...',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 11),
                          ),
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
                      isQuota ? 'Monthly Limit Reached' : 'OCR Scan Failed',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: Text(
                res?.errorMessage ?? 'Could not parse bill slip. Please check photo clarity or configure API key.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF475569)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Close', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _showApiKeyDialog(context);
                  },
                  child: Text('AI Key Settings', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF0284C7), fontWeight: FontWeight.w700)),
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

          // SUCCESS: Dismiss scanning dialog and open full review sheet
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pop(dialogCtx);
            BillScanReviewSheet.show(
              context,
              items: res.items,
              supplierName: res.supplierName,
              billNumber: res.billNumber,
              billDate: res.billDate,
              onInwardComplete: onInwardComplete,
            );
          });

          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context) async {
    final currentKey = await GeminiAiService.getEffectiveApiKey();
    final ctrl = TextEditingController(text: currentKey);

    if (!context.mounted) return;

    bool isTesting = false;
    String? testStatus;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.key_rounded, color: Color(0xFF059669), size: 20),
                ),
                const SizedBox(width: 8),
                Text('Gemini AI Vision Key', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your Google AI Studio Gemini API Key for OCR scanning of bills and mandi parchas.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'Gemini API Key (AIzaSy...)',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  style: GoogleFonts.jetBrainsMono(fontSize: 12),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => launchUrl(Uri.parse('https://aistudio.google.com/app/apikey'), mode: LaunchMode.externalApplication),
                  child: Text(
                    '🔗 Get a 100% Free Gemini API Key from Google AI Studio',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF0284C7), fontWeight: FontWeight.w700),
                  ),
                ),
                if (testStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    testStatus!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: testStatus!.contains('✅') ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
              ),
              TextButton(
                onPressed: isTesting
                    ? null
                    : () async {
                        setDlgState(() {
                          isTesting = true;
                          testStatus = 'Testing API Key...';
                        });
                        final ok = await GeminiAiService.testApiKey(ctrl.text.trim());
                        setDlgState(() {
                          isTesting = false;
                          testStatus = ok ? '✅ API Key is Valid & Active!' : '❌ Invalid API Key. Please verify.';
                        });
                      },
                child: Text('Test Key', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await GeminiAiService.setCustomApiKey(ctrl.text.trim());
                  if (ctx.mounted) Navigator.pop(dlgCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Gemini API Key saved successfully!'), backgroundColor: Color(0xFF059669)),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Save Key', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
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
                'Wholesale Inward & Restock',
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
                  'REAL OCR',
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.key_rounded, size: 20, color: Color(0xFF64748B)),
                tooltip: 'Configure Gemini API Key',
                onPressed: () => _showApiKeyDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            'Scan mandi parchas, digital PDF bills, or upload Excel/CSV spreadsheets directly into stock.',
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
            badge: 'AI VISION',
            badgeColor: const Color(0xFF0284C7),
            subtitle: 'Single or multi-page digital wholesale invoice PDF',
            onTap: () {
              Navigator.pop(context);
              _processPdfScan(context);
            },
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
            badge: '100% OFFLINE',
            badgeColor: const Color(0xFF059669),
            subtitle: 'Instant spreadsheet inward with item names, prices & stock',
            onTap: () {
              Navigator.pop(context);
              _processCsvScan(context);
            },
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
