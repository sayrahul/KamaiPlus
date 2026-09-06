import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';

class AiInwardSheet extends StatelessWidget {
  final VoidCallback? onInwardComplete;

  const AiInwardSheet({super.key, this.onInwardComplete});

  void _simulateAiScan(BuildContext context, String mode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
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
                  child: Text(
                    'AI Vision OCR Extraction',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Extracted from: Wholesaler Purchase Invoice #INV-9821',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                _buildExtractedRow('Fortune Sunlite Oil (1L)', '24 Pcs', '₹125.00', '₹145.00'),
                _buildExtractedRow('Tata Sampann Toor Dal (1kg)', '30 Pcs', '₹140.00', '₹165.00'),
                _buildExtractedRow('Aashirvaad Shudh Chakki Atta (10kg)', '15 Pcs', '₹380.00', '₹425.00'),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Inward Value:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('₹12,900.00', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF10B981))),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                  await LocalDatabase.instance.upsertProduct(p1);
                  await LocalDatabase.instance.upsertProduct(p2);

                  onInwardComplete?.call();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('✓ 3 items successfully added to inventory via AI Inward!')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Confirm & Save Stock'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExtractedRow(String name, String qty, String buy, String sell) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                Text('Buy: $buy • Sell: $sell', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
            child: Text(qty, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
          ),
        ],
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
