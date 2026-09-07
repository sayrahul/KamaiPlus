import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/thermal_printer_service.dart';

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
  static const _printerChannel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  // Label Layout Option
  // 'standard': 50x25mm, 'compact': 38x25mm, 'detailed': 50x38mm
  String _selectedLayout = 'standard';

  // Label Element Toggles
  bool _showStoreName = true;
  bool _showProductName = true;
  bool _showBarcode = true;
  bool _showPrice = true;
  bool _showBatchExp = false;
  bool _showTaxNotice = true;

  // Batch & Expiry simulation
  final String _batchNumber = 'B-2609';
  final String _expDate = '12/2027';

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

  Future<void> _dispatchPrint() async {
    HapticFeedback.mediumImpact();
    final product = _selectedProduct;
    if (product == null) return;
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('printer_mac_address');
    if (address == null || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bluetooth printer connect karein')));
      return;
    }
    final bytes = ThermalPrinterService.generateLabelBytes(
      product: product,
      storeName: _storeName,
      copies: _copies,
    );
    await _printerChannel.invokeMethod('printBytes', {'address': address, 'bytes': bytes});
    final name = _selectedProduct?.name ?? 'Item';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.print_rounded, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sent $_copies thermal label(s) for "$name" to Bluetooth printer',
                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
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
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Barcode Studio & Stickers',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
            ),
            Text(
              'Thermal Price Tags & Barcode Maker',
              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(
                  '58/80mm Ready',
                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. SELECT PRODUCT SKU CARD
                  _buildProductSelectorCard(),
                  const SizedBox(height: 14),

                  // 2. LABEL SIZE / LAYOUT SELECTOR
                  _buildLayoutSelectorCard(),
                  const SizedBox(height: 14),

                  // 3. STICKER ELEMENTS TOGGLES
                  _buildElementsToggleCard(),
                  const SizedBox(height: 14),

                  // 4. PRINT QUANTITY COUNTER
                  _buildCopiesSelectorCard(),
                  const SizedBox(height: 20),

                  // 5. LIVE STICKER PREVIEW SECTION
                  _buildLiveStickerPreview(),
                ],
              ),
            ),
      bottomSheet: _buildBottomActionBar(),
    );
  }

  // =========================================================================
  // 1. PRODUCT SELECTOR CARD
  // =========================================================================
  Widget _buildProductSelectorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF2563EB), size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                'TARGET PRODUCT SKU',
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_products.isEmpty)
            Text(
              'No products in catalog. Add products first.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            )
          else
            DropdownButtonFormField<ProductModel>(
              initialValue: _selectedProduct,
              isExpanded: true,
              items: _products.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        MoneyFormatter.formatPaise(p.sellingPricePaise),
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (p) => setState(() => _selectedProduct = p),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. LAYOUT / SIZE SELECTOR
  // =========================================================================
  Widget _buildLayoutSelectorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.aspect_ratio_rounded, color: Color(0xFF7C3AED), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LABEL FORMAT & SIZE',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
                  ),
                ],
              ),
              Text(
                'Roll: 58mm Thermal',
                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildLayoutOption(
                id: 'standard',
                title: 'Standard',
                size: '50 × 25 mm',
                subtitle: 'Most Retail Items',
              ),
              const SizedBox(width: 8),
              _buildLayoutOption(
                id: 'compact',
                title: 'Compact',
                size: '38 × 25 mm',
                subtitle: 'Jewelry / Small Box',
              ),
              const SizedBox(width: 8),
              _buildLayoutOption(
                id: 'detailed',
                title: 'Detailed',
                size: '50 × 38 mm',
                subtitle: 'Grocery / Batch & Exp',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutOption({
    required String id,
    required String title,
    required String size,
    required String subtitle,
  }) {
    final isSel = _selectedLayout == id;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedLayout = id;
            if (id == 'detailed') {
              _showBatchExp = true;
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
              width: isSel ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isSel ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                size,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSel ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 8.5,
                  color: isSel ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. ELEMENTS TOGGLES
  // =========================================================================
  Widget _buildElementsToggleCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF059669), size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                'STICKER ELEMENTS TO DISPLAY',
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip('Store Name', _showStoreName, () => setState(() => _showStoreName = !_showStoreName)),
              _buildFilterChip('Product Title', _showProductName, () => setState(() => _showProductName = !_showProductName)),
              _buildFilterChip('Barcode & Code', _showBarcode, () => setState(() => _showBarcode = !_showBarcode)),
              _buildFilterChip('Selling Price / MRP', _showPrice, () => setState(() => _showPrice = !_showPrice)),
              _buildFilterChip('Batch & Expiry', _showBatchExp, () => setState(() => _showBatchExp = !_showBatchExp)),
              _buildFilterChip('Tax Info', _showTaxNotice, () => setState(() => _showTaxNotice = !_showTaxNotice)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onToggle) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onToggle();
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 13,
              color: isSelected ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 4. PRINT COPIES COUNTER
  // =========================================================================
  Widget _buildCopiesSelectorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.copy_rounded, color: Color(0xFFD97706), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'PRINT COPIES',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _copies > 1 ? () => setState(() => _copies -= 1) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 22, color: Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$_copies',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () => setState(() => _copies += 1),
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: Color(0xFF10B981)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [5, 10, 25, 50, 100].map((preset) {
              final isCur = _copies == preset;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _copies = preset);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isCur ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isCur ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$preset',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isCur ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. LIVE STICKER PREVIEW SECTION
  // =========================================================================
  Widget _buildLiveStickerPreview() {
    final String barcodeVal = (_selectedProduct?.barcode != null && _selectedProduct!.barcode!.isNotEmpty)
        ? _selectedProduct!.barcode!
        : '8901234567890';
    final pName = _selectedProduct?.name ?? 'Sample Product SKU';
    final pricePaise = _selectedProduct?.sellingPricePaise ?? 49900;

    // Dimensions based on selected layout
    final double cardWidth = _selectedLayout == 'compact' ? 240 : 290;
    final double minHeight = _selectedLayout == 'detailed' ? 200 : (_selectedLayout == 'compact' ? 140 : 160);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LIVE STICKER PREVIEW',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 0.6,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _selectedLayout == 'compact' ? '38×25 mm' : (_selectedLayout == 'detailed' ? '50×38 mm' : '50×25 mm'),
                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Centered Thermal Sticker Label
        Center(
          child: Container(
            width: cardWidth,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF0F172A), width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Store Name
                if (_showStoreName) ...[
                  Text(
                    _storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],

                // Product Name
                if (_showProductName) ...[
                  Text(
                    pName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],

                // Barcode Graphic & Text
                if (_showBarcode) ...[
                  Container(
                    height: _selectedLayout == 'compact' ? 34 : 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        _selectedLayout == 'compact' ? 28 : 36,
                        (i) => Container(
                          width: (i % 4 == 0) ? 3.0 : ((i % 3 == 0) ? 2.0 : ((i % 2 == 0) ? 1.4 : 0.8)),
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    barcodeVal,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],

                // Batch & Expiry (Grocery/Pharma)
                if (_showBatchExp) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black87, width: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('BATCH: $_batchNumber', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Text('EXP: $_expDate', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],

                // Price / MRP
                if (_showPrice) ...[
                  Text(
                    'MRP: ${MoneyFormatter.formatPaise(pricePaise)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: _selectedLayout == 'compact' ? 14 : 16.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ],

                // Tax Notice
                if (_showTaxNotice) ...[
                  Text(
                    '(Incl. of all taxes)',
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 6. BOTTOM ACTION BAR
  // =========================================================================
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: const Border(top: BorderSide(color: Color(0xFFEEF2F6))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _dispatchPrint,
                icon: const Icon(Icons.print_rounded, size: 18),
                label: Text(
                  'Print $_copies Sticker(s) via Bluetooth',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
