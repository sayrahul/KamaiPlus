import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';

class AiInwardSheet extends StatelessWidget {
  final VoidCallback? onInwardComplete;

  const AiInwardSheet({super.key, this.onInwardComplete});

  void _simulateAiScan(BuildContext context, String mode) {
    int scanStep = 0; // 0: Scanning viewfinder, 1: Review extracted parcha
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (scanStep == 0) {
            // Auto transition from scanning to extracted items after 1.5 seconds
            Future.delayed(const Duration(milliseconds: 1600), () {
              if (ctx.mounted && scanStep == 0) {
                setDialogState(() => scanStep = 1);
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.all(20),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Viewfinder Header
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
                            'AI Vision Parcha OCR',
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
                          'PROCESSING',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF34D399)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Simulated Camera Viewfinder with Parcha Paper
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155), width: 1.5),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Parcha Paper Graphic
                        Container(
                          width: 170,
                          height: 130,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('MANDI INWARD SLIP', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w900, color: const Color(0xFF78350F))),
                                  Text('#9821', style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF92400E))),
                                ],
                              ),
                              const Divider(height: 8, color: Color(0xFFFDE68A)),
                              Text('1. Fortune Oil 1L x 24', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF451A03))),
                              Text('2. Toor Dal 1kg x 30', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF451A03))),
                              Text('3. Chakki Atta 10kg x 15', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: const Color(0xFF451A03))),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('TOTAL DUE:', style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w800, color: const Color(0xFF78350F))),
                                  Text('₹12,900', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w900, color: const Color(0xFFB45309))),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Corner Reticles
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

                        // Scanning Laser Line
                        Positioned(
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF34D399).withValues(alpha: 0.8), blurRadius: 8, spreadRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress & Status
                  const LinearProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                    backgroundColor: Color(0xFF334155),
                    minHeight: 4,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reading handwritten mandi parcha & bill rates...',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Stage 1: Extracted items with verification
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Vision OCR Extraction',
                        style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Matched: 3 Products • 99.1% Confidence',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.store_rounded, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Wholesale Invoice: Metro Cash & Carry #INV-9821',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildExtractedRow('Fortune Sunlite Oil (1L)', '24 Pcs', '₹125.00', '₹145.00', '+16% Margin'),
                _buildExtractedRow('Tata Sampann Toor Dal (1kg)', '30 Pcs', '₹140.00', '₹165.00', '+18% Margin'),
                _buildExtractedRow('Aashirvaad Chakki Atta (10kg)', '15 Bags', '₹380.00', '₹425.00', '+12% Margin'),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Inward Value:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                    Text('₹12,900.00', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF059669))),
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
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  // Insert or update extracted products
                  final p1 = ProductModel(
                    id: const Uuid().v4(),
                    businessId: 'default_business',
                    name: 'Fortune Sunlite Oil (1L)',
                    purchasePricePaise: 12500,
                    sellingPricePaise: 14500,
                    mrpPaise: 15000,
                    stockQuantity: 24,
                    unit: 'bottle',
                  );
                  final p2 = ProductModel(
                    id: const Uuid().v4(),
                    businessId: 'default_business',
                    name: 'Tata Sampann Toor Dal (1kg)',
                    purchasePricePaise: 14000,
                    sellingPricePaise: 16500,
                    mrpPaise: 17500,
                    stockQuantity: 30,
                    unit: 'packet',
                  );
                  final p3 = ProductModel(
                    id: const Uuid().v4(),
                    businessId: 'default_business',
                    name: 'Aashirvaad Shudh Chakki Atta (10kg)',
                    purchasePricePaise: 38000,
                    sellingPricePaise: 42500,
                    mrpPaise: 44000,
                    stockQuantity: 15,
                    unit: 'bag',
                  );
                  await LocalDatabase.instance.upsertProduct(p1);
                  await LocalDatabase.instance.upsertProduct(p2);
                  await LocalDatabase.instance.upsertProduct(p3);

                  onInwardComplete?.call();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('✓ 3 items successfully added to inventory via AI Inward!'),
                        ],
                      ),
                      backgroundColor: Color(0xFF059669),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Confirm & Save Stock', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExtractedRow(String name, String qty, String buy, String sell, String margin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEF2F6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text('Buy: $buy • Sell: $sell', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(margin, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(6)),
              child: Text(qty, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
            ),
          ],
        ),
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
                'AI Wholesale Invoice & Inward',
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
                  'AI VISION',
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
            'Scan wholesale invoices, parchas, or upload PDFs to auto-add products, prices & stock.',
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
            badge: 'RECOMMENDED',
            badgeColor: const Color(0xFFD97706),
            subtitle: 'Camera photo of invoice, slip or wholesale parcha',
            onTap: () {
              Navigator.pop(context);
              _simulateAiScan(context, 'camera');
            },
          ),
          const SizedBox(height: 10),

          // Option 2: Upload PDF [FASTER]
          _buildOptionCard(
            context: context,
            icon: Icons.picture_as_pdf_rounded,
            iconBg: const Color(0xFFF0F9FF),
            iconColor: const Color(0xFF0284C7),
            borderColor: const Color(0xFFBAE6FD),
            title: 'Upload Invoice PDF',
            badge: 'FASTER',
            badgeColor: const Color(0xFF0284C7),
            subtitle: 'Single or multi-page digital invoice / tariff document',
            onTap: () {
              Navigator.pop(context);
              _simulateAiScan(context, 'pdf');
            },
          ),
          const SizedBox(height: 10),

          // Option 3: Upload Excel [BULK]
          _buildOptionCard(
            context: context,
            icon: Icons.table_chart_rounded,
            iconBg: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF059669),
            borderColor: const Color(0xFFA7F3D0),
            title: 'Upload Excel / CSV File',
            badge: 'BULK',
            badgeColor: const Color(0xFF059669),
            subtitle: 'Spreadsheet with item names, prices & stock',
            onTap: () {
              Navigator.pop(context);
              _simulateAiScan(context, 'excel');
            },
          ),
          const SizedBox(height: 10),

          // Option 4: Add Single Item Manually
          _buildOptionCard(
            context: context,
            icon: Icons.post_add_rounded,
            iconBg: const Color(0xFFF5F3FF),
            iconColor: const Color(0xFF7C3AED),
            borderColor: const Color(0xFFDDD6FE),
            title: 'Add Single Item Manually',
            badge: 'MANUAL FORM',
            badgeColor: const Color(0xFF7C3AED),
            subtitle: 'Fill in product name, rate, category and stock individually',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open Add Product in Products tab to add single item manually.')),
              );
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
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: badgeColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: badgeColor),
          ],
        ),
      ),
    );
  }
}
