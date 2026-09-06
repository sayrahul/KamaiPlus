import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../common/kamai_bottom_nav.dart';

class BarcodeStudioScreen extends StatefulWidget {
  const BarcodeStudioScreen({super.key});

  @override
  State<BarcodeStudioScreen> createState() => _BarcodeStudioScreenState();
}

class _BarcodeStudioScreenState extends State<BarcodeStudioScreen> {
  List<ProductModel> _products = [];
  ProductModel? _selectedProduct;
  int _copies = 10;
  bool _isLoading = true;
  String _storeName = 'KAMAI STORE';

  @override
  void initState() {
    super.initState();
    _loadProductsAndStore();
  }

  Future<void> _loadProductsAndStore() async {
    try {
      final products = await LocalDatabase.instance.getAllProducts();
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() {
          _products = products;
          if (products.isNotEmpty) _selectedProduct = products.first;
          if (profile.storeName.isNotEmpty) _storeName = profile.storeName.toUpperCase();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _dispatchPrint() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.print_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '✓ Sent $_copies barcode label(s) for "${_selectedProduct?.name ?? 'Item'}" to 58mm printer',
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Barcode Studio & Stickers',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Header Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF7C3AED), size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Barcode Studio & Label Maker', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                                Text('Generate Code128 thermal price stickers for products', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('SELECT PRODUCT SKU', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      if (_products.isNotEmpty)
                        DropdownButtonFormField<ProductModel>(
                          initialValue: _selectedProduct,
                          items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (p) => setState(() => _selectedProduct = p),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('LABEL COPIES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _copies > 1 ? () => setState(() => _copies -= 1) : null,
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                              ),
                              Text('$_copies', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
                              IconButton(
                                onPressed: () => setState(() => _copies += 1),
                                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF10B981)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Label Mockup
                Text('STICKER PREVIEW (50mm × 25mm Thermal Roll)', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _storeName,
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedProduct?.name ?? 'Product SKU',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Barcode simulation graphic
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            38,
                            (i) => Container(
                              width: (i % 4 == 0) ? 3.5 : ((i % 3 == 0) ? 2.5 : ((i % 2 == 0) ? 1.5 : 1)),
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedProduct?.barcode ?? '8901234567890',
                        style: GoogleFonts.inter(fontSize: 12, letterSpacing: 2.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'MRP: ₹${((_selectedProduct?.sellingPricePaise ?? 0) / 100).toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        '(Incl. of all taxes)',
                        style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _dispatchPrint,
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: Text('Print $_copies Labels via Bluetooth', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }
}
