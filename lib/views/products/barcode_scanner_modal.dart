import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BarcodeScannerModal extends StatefulWidget {
  final Function(String barcode) onBarcodeScanned;

  const BarcodeScannerModal({super.key, required this.onBarcodeScanned});

  static Future<void> show(BuildContext context, {required Function(String barcode) onBarcodeScanned}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC020617),
      builder: (ctx) => BarcodeScannerModal(onBarcodeScanned: onBarcodeScanned),
    );
  }

  @override
  State<BarcodeScannerModal> createState() => _BarcodeScannerModalState();
}

class _BarcodeScannerModalState extends State<BarcodeScannerModal> with SingleTickerProviderStateMixin {
  final TextEditingController _manualCtrl = TextEditingController();
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _laserAnimation = Tween<double>(begin: -70.0, end: 70.0).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _submitBarcode(String code) {
    final clean = code.trim();
    if (clean.isEmpty) return;
    Navigator.of(context).pop();
    widget.onBarcodeScanned(clean);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.qr_code_scanner_rounded, size: 18, color: Color(0xFF0F172A)),
                        const SizedBox(width: 8),
                        Text(
                          'Scan Product Barcode',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
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
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Point camera at barcode/QR code on packaging or enter barcode manually.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Camera Viewfinder Box
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF080C14),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Center target box
                          Container(
                            width: 220,
                            height: 130,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          // Top-Left corner bracket
                          Positioned(
                            top: 45,
                            left: 55,
                            child: _buildCornerBracket(isTop: true, isLeft: true),
                          ),
                          // Top-Right corner bracket
                          Positioned(
                            top: 45,
                            right: 55,
                            child: _buildCornerBracket(isTop: true, isLeft: false),
                          ),
                          // Bottom-Left corner bracket
                          Positioned(
                            bottom: 45,
                            left: 55,
                            child: _buildCornerBracket(isTop: false, isLeft: true),
                          ),
                          // Bottom-Right corner bracket
                          Positioned(
                            bottom: 45,
                            right: 55,
                            child: _buildCornerBracket(isTop: false, isLeft: false),
                          ),

                          // Red Laser Scan Line (Animated)
                          AnimatedBuilder(
                            animation: _laserAnimation,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, _laserAnimation.value),
                                child: Container(
                                  width: 200,
                                  height: 2.2,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.8),
                                        blurRadius: 8,
                                        spreadRadius: 1.5,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          // Quick Simulator Tap (Demo Scanner tap)
                          Positioned(
                            bottom: 12,
                            child: GestureDetector(
                              onTap: () => _submitBarcode('8901030383748'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.touch_app_rounded, size: 12, color: Color(0xFFFBBF24)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Tap to Simulate Barcode Scan',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Manual Entry Section
                    Text(
                      '⌨ OR ENTER BARCODE NUMBER',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualCtrl,
                            keyboardType: TextInputType.number,
                            onSubmitted: _submitBarcode,
                            style: GoogleFonts.robotoMono(fontSize: 13.5, fontWeight: FontWeight.w700),
                            decoration: InputDecoration(
                              hintText: 'e.g. 890103000001',
                              hintStyle: GoogleFonts.robotoMono(fontSize: 13, color: const Color(0xFF94A3B8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _submitBarcode(_manualCtrl.text),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF64748B),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'Add',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCornerBracket({required bool isTop, required bool isLeft}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
          bottom: !isTop ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
          left: isLeft ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
          right: !isLeft ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: Color(0xFFFBBF24), width: 2) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: Color(0xFFFBBF24), width: 2) : BorderSide.none,
            left: isLeft ? const BorderSide(color: Color(0xFFFBBF24), width: 2) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: Color(0xFFFBBF24), width: 2) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
