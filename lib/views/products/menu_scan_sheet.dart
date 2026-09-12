import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../services/gemini_ai_service.dart';
import '../common/gemini_api_key_dialog.dart';
import 'menu_item_review_sheet.dart';
import '../common/in_app_notification.dart';

/// Entry point for Restaurant vertical: "Scan Menu Photo" → AI extracts dish
/// names, prices and categories → merchant reviews and confirms → dishes are
/// added to the Products (Menu) catalog.
///
/// Deliberately separate from [AiInwardSheet]/[AiInwardModal] rather than a
/// branch inside them: those are worded and modelled around wholesale supplier
/// bills (cost price, quantity received, supplier name) which do not apply to a
/// menu card. Restaurant is already the one vertical with
/// `toggles.hasBillScan == false` for exactly this reason (see
/// purchases_screen.dart's AI Bill Scan gating) — this sheet is the
/// restaurant-appropriate replacement for that entry point on the Products screen.
class MenuScanSheet extends StatelessWidget {
  final VoidCallback? onMenuAddSuccess;

  const MenuScanSheet({super.key, this.onMenuAddSuccess});

  static Future<void> show(BuildContext context, {VoidCallback? onMenuAddSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MenuScanSheet(onMenuAddSuccess: onMenuAddSuccess),
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
                'Select Menu Photo Source',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFFD97706)),
                ),
                title: Text('Camera (Click Menu Card)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                subtitle: Text('Capture your printed menu or price board directly', style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processMenuScan(context, ImageSource.camera);
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
                subtitle: Text('Pick a menu photo from gallery or WhatsApp', style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processMenuScan(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processMenuScan(BuildContext context, ImageSource source) async {
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

      _runExtraction(context, bytes, mimeType: 'image/jpeg');
    } catch (e) {
      if (context.mounted) {
        InAppNotification.error('Could not open image: $e', context: context);
      }
    }
  }

  void _runExtraction(BuildContext context, Uint8List bytes, {required String mimeType}) {
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => FutureBuilder<MenuScanResult>(
        future: GeminiAiService.extractMenuItemsFromImage(
          bytes,
          mimeType: mimeType,
          knownCategories: vert.quickCategories,
        ),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
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
                            child: const Icon(Icons.restaurant_menu_rounded, color: Color(0xFF34D399), size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Reading Menu',
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
                        const Icon(Icons.menu_book_rounded, color: Color(0xFF64748B), size: 54),
                        Positioned(
                          bottom: 16,
                          child: Text(
                            'Reading dish names & prices...',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          final result = snapshot.data;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!dialogCtx.mounted) return;
            Navigator.of(dialogCtx).pop();

            if (!context.mounted) return;

            if (result == null || !result.success) {
              final needsApiKey = (result?.errorMessage ?? '').contains('API Key');
              InAppNotification.show(
                context: context,
                message: result?.errorMessage ?? 'Could not read the menu photo.',
                type: NotificationType.error,
                duration: const Duration(seconds: 6),
                actionLabel: needsApiKey ? 'Settings' : null,
                onAction: needsApiKey ? () => GeminiApiKeyDialog.show(context) : null,
              );
              return;
            }

            Navigator.pop(context); // close this sheet
            MenuItemReviewSheet.show(
              context,
              initialItems: result.items,
              onMenuAddComplete: onMenuAddSuccess,
            );
          });

          return const SizedBox.shrink();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Scan Menu Photo',
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
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
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4, color: const Color(0xFF059669)),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.key_rounded, size: 20, color: Color(0xFF64748B)),
                      tooltip: 'Configure Gemini API Key',
                      onPressed: () => GeminiApiKeyDialog.show(context),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Take or upload a photo of your printed menu card — dish names and prices are read automatically. Review before adding.',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), height: 1.3),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showImageSourcePicker(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A), width: 1.3),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.camera_alt_outlined, color: Color(0xFFD97706), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan Menu Card',
                              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Camera or gallery photo of your ${vert.name} menu',
                              style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
