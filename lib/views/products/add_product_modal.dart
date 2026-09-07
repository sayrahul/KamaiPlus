import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../pos/barcode_scanner_view.dart';

class AddProductModal extends StatefulWidget {
  final ProductModel? existingProduct;
  final List<CategoryModel> categories;
  final VoidCallback onSaved;
  final VoidCallback onSwitchToAiInward;

  const AddProductModal({
    super.key,
    this.existingProduct,
    required this.categories,
    required this.onSaved,
    required this.onSwitchToAiInward,
  });

  static Future<void> show(
    BuildContext context, {
    ProductModel? existingProduct,
    required List<CategoryModel> categories,
    required VoidCallback onSaved,
    required VoidCallback onSwitchToAiInward,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddProductModal(
        existingProduct: existingProduct,
        categories: categories,
        onSaved: onSaved,
        onSwitchToAiInward: onSwitchToAiInward,
      ),
    );
  }

  @override
  State<AddProductModal> createState() => _AddProductModalState();
}

class _AddProductModalState extends State<AddProductModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _sellPriceCtrl;
  late final TextEditingController _mrpCtrl;
  late final TextEditingController _costPriceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _thresholdCtrl;

  late String _selectedCategoryId;
  late String _selectedUnit;
  late double _selectedTaxRate;
  late List<CategoryModel> _localCategories;
  bool _isSaving = false;
  bool _isUnlimitedStock = false;

  final List<Map<String, String>> _units = [
    {'label': 'Packet / Pouch (pkt)', 'val': 'pkt'},
    {'label': 'Pieces (pcs)', 'val': 'pcs'},
    {'label': 'Kilogram (kg)', 'val': 'kg'},
    {'label': 'Gram (g)', 'val': 'g'},
    {'label': 'Liter (ltr)', 'val': 'ltr'},
    {'label': 'Milliliter (ml)', 'val': 'ml'},
    {'label': 'Bottle (btl)', 'val': 'btl'},
    {'label': 'Box (box)', 'val': 'box'},
    {'label': 'Bag / Borri (bag)', 'val': 'bag'},
    {'label': 'Pouch (pouch)', 'val': 'pouch'},
    {'label': 'Can / Tin (can)', 'val': 'can'},
    {'label': 'Jar (jar)', 'val': 'jar'},
    {'label': 'Meter (m)', 'val': 'm'},
    {'label': 'Dozen (dz)', 'val': 'dz'},
    {'label': 'Bundle (bdl)', 'val': 'bdl'},
  ];

  final List<Map<String, dynamic>> _taxRates = [
    {'label': '0% (Exempt / Nil Rated)', 'val': 0.0},
    {'label': '5% GST', 'val': 5.0},
    {'label': '12% GST', 'val': 12.0},
    {'label': '18% GST', 'val': 18.0},
    {'label': '28% GST', 'val': 28.0},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _isUnlimitedStock = p != null && p.stockQuantity >= 99999;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _sellPriceCtrl = TextEditingController(
      text: p != null ? (p.sellingPricePaise / 100).toStringAsFixed(2) : '',
    );
    _mrpCtrl = TextEditingController(
      text: p != null ? (p.mrpPaise / 100).toStringAsFixed(2) : '',
    );
    _costPriceCtrl = TextEditingController(
      text: p != null ? (p.purchasePricePaise / 100).toStringAsFixed(2) : '',
    );
    _stockCtrl = TextEditingController(
      text: p != null ? (_isUnlimitedStock ? '' : p.stockQuantity.toInt().toString()) : '0',
    );
    _thresholdCtrl = TextEditingController(text: '5');

    // Deduplicate categories by ID
    final uniqueCats = <String, CategoryModel>{};
    for (final c in widget.categories) {
      uniqueCats[c.id] = c;
    }
    _localCategories = uniqueCats.values.toList();
    if (_localCategories.isEmpty) {
      _localCategories.add(CategoryModel(id: 'cat_gen', businessId: 'biz_default', name: 'General Products'));
    }

    // Safe Category Selection
    if (p?.categoryId != null && p!.categoryId!.isNotEmpty) {
      if (!_localCategories.any((c) => c.id == p.categoryId)) {
        _localCategories.add(CategoryModel(
          id: p.categoryId!,
          businessId: p.businessId,
          name: 'Category (${p.categoryId})',
        ));
      }
      _selectedCategoryId = p.categoryId!;
    } else {
      _selectedCategoryId = _localCategories.first.id;
    }

    // Safe Unit Selection & Dynamic Registration
    if (p != null && p.unit.isNotEmpty) {
      final unitClean = p.unit.trim();
      final match = _units.firstWhere(
        (u) => u['val']?.toLowerCase() == unitClean.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        _selectedUnit = match['val']!;
      } else {
        _units.add({'label': '$unitClean (Custom)', 'val': unitClean});
        _selectedUnit = unitClean;
      }
    } else {
      _selectedUnit = 'pkt';
    }

    // Safe Tax Rate Selection & Dynamic Registration
    if (p != null) {
      final taxRateVal = p.taxRate;
      final matchTax = _taxRates.firstWhere(
        (t) => ((t['val'] as num).toDouble() - taxRateVal).abs() < 0.001,
        orElse: () => {},
      );
      if (matchTax.isNotEmpty) {
        _selectedTaxRate = (matchTax['val'] as num).toDouble();
      } else {
        _taxRates.add({'label': '$taxRateVal% GST', 'val': taxRateVal});
        _selectedTaxRate = taxRateVal;
      }
    } else {
      _selectedTaxRate = 0.0;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _sellPriceCtrl.dispose();
    _mrpCtrl.dispose();
    _costPriceCtrl.dispose();
    _stockCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  double get _profitMargin {
    final sell = double.tryParse(_sellPriceCtrl.text) ?? 0.0;
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0.0;
    return sell - cost;
  }

  Future<void> _openBarcodeScanner() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerView()),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      setState(() {
        _barcodeCtrl.text = scanned;
      });
    }
  }

  void _showAddCategoryDialog() {
    final catCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Add New Category', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: catCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Beverages, Dairy',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = catCtrl.text.trim();
              if (name.isNotEmpty) {
                final newCat = CategoryModel(
                  id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
                  businessId: FirestoreSyncService.instance.activeBusinessId,
                  name: name,
                );
                await LocalDatabase.instance.upsertCategory(newCat);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  setState(() {
                    _localCategories.add(newCat);
                    _selectedCategoryId = newCat.id;
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final sellPaise = ((double.tryParse(_sellPriceCtrl.text.trim()) ?? 0.0) * 100).round();
      final mrpPaise = ((double.tryParse(_mrpCtrl.text.trim()) ?? (sellPaise / 100.0)) * 100).round();
      final costPaise = ((double.tryParse(_costPriceCtrl.text.trim()) ?? 0.0) * 100).round();
      final stockQty = _isUnlimitedStock ? 999999.0 : (double.tryParse(_stockCtrl.text.trim()) ?? 0.0);

      final p = ProductModel(
        id: widget.existingProduct?.id ?? const Uuid().v4(),
        businessId: widget.existingProduct?.businessId ?? FirestoreSyncService.instance.activeBusinessId,
        name: _nameCtrl.text.trim(),
        barcode: _barcodeCtrl.text.trim().isNotEmpty ? _barcodeCtrl.text.trim() : null,
        categoryId: _selectedCategoryId,
        sellingPricePaise: sellPaise,
        mrpPaise: mrpPaise > 0 ? mrpPaise : sellPaise,
        purchasePricePaise: costPaise,
        stockQuantity: stockQty,
        taxRate: _selectedTaxRate,
        isTaxInclusive: true,
        unit: _selectedUnit,
        syncStatus: 'synced',
      );

      await LocalDatabase.instance.upsertProduct(p);
      if (!mounted) return;

      Navigator.of(context).pop();
      widget.onSaved();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingProduct != null
                ? 'Product updated successfully!'
                : 'New product added to catalog!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save product: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingProduct != null;

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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Drag Handle
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
            const SizedBox(height: 12),

            // Modal Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isEditing ? Icons.edit_note_rounded : Icons.add_rounded,
                        size: 20,
                        color: const Color(0xFF0284C7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isEditing ? 'Edit Catalog Item' : 'Add New Item to Catalog',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Enter product details, barcode, selling price, and initial stock.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Scrollable Form Body
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wholesale AI Inward Suggestion Banner
                      if (!isEditing) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFDF5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFBBF24),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0F172A), size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Have a Wholesale Bill / Parcha?',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      "Don't type items one by one. Scan distributor invoice...",
                                      style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onSwitchToAiInward();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.camera_alt_outlined, size: 12, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Inward with AI',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // 1. Product Full Name *
                      _buildLabel('Product / Item Full Name *'),
                      const SizedBox(height: 5),
                      TextFormField(
                        controller: _nameCtrl,
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
                        decoration: _buildInputDecoration('e.g. Fortune Sunflower Oil 1L'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null,
                      ),
                      const SizedBox(height: 12),

                      // 2. Row of Category & Measurement Unit (2-in-1 Row)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildLabel('Category'),
                                    GestureDetector(
                                      onTap: _showAddCategoryDialog,
                                      child: Text(
                                        '+ New',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0284C7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _localCategories.any((c) => c.id == _selectedCategoryId)
                                          ? _selectedCategoryId
                                          : _localCategories.first.id,
                                      isExpanded: true,
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569)),
                                      items: _localCategories.map((c) {
                                        return DropdownMenuItem<String>(
                                          value: c.id,
                                          child: Text(c.name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _selectedCategoryId = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Unit'),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _units.any((u) => u['val'] == _selectedUnit)
                                          ? _selectedUnit
                                          : _units.first['val'],
                                      isExpanded: true,
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569)),
                                      items: _units.map((u) {
                                        return DropdownMenuItem<String>(
                                          value: u['val'],
                                          child: Text(u['label']!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _selectedUnit = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 3. Compact Pricing & Profit Margins Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Pricing & Margins',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                if (_profitMargin > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: Text(
                                      'Margin: +₹${_profitMargin.toStringAsFixed(2)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Row 1: Selling Price & MRP (2 in 1)
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Selling Price (₹) *'),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        controller: _sellPriceCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                        decoration: _buildInputDecoration('e.g. 150.00'),
                                        onChanged: (_) => setState(() {}),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) return 'Selling price required';
                                          if ((double.tryParse(v) ?? 0.0) <= 0) return 'Must be > 0';
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('MRP (₹)'),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        controller: _mrpCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                        decoration: _buildInputDecoration('e.g. 165.00'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Row 2: Purchase Cost & GST Rate (2 in 1)
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Purchase Cost (₹)'),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        controller: _costPriceCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                        decoration: _buildInputDecoration('e.g. 120.00'),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('GST Tax Rate (%)'),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFCBD5E1)),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<double>(
                                            value: _taxRates.any((t) => ((t['val'] as num).toDouble() - _selectedTaxRate).abs() < 0.001)
                                                ? _selectedTaxRate
                                                : 0.0,
                                            isExpanded: true,
                                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569)),
                                            items: _taxRates.map((t) {
                                              return DropdownMenuItem<double>(
                                                value: t['val'] as double,
                                                child: Text(t['label'] as String, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) setState(() => _selectedTaxRate = val);
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 4. Barcode / EAN-13 + Scan Camera Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLabel('Barcode / EAN-13'),
                          GestureDetector(
                            onTap: _openBarcodeScanner,
                            child: Row(
                              children: [
                                const Icon(Icons.qr_code_scanner_rounded, size: 14, color: Color(0xFF0284C7)),
                                const SizedBox(width: 4),
                                Text(
                                  'Scan Camera',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0284C7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      TextFormField(
                        controller: _barcodeCtrl,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.robotoMono(fontSize: 13.5, fontWeight: FontWeight.w700),
                        decoration: _buildInputDecoration('e.g. 8901030383748'),
                      ),
                      const SizedBox(height: 12),

                      // 5. Stock & Inventory Card (With Unlimited Stock Toggle!)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isUnlimitedStock ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isUnlimitedStock ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _isUnlimitedStock ? Icons.all_inclusive_rounded : Icons.inventory_2_outlined,
                                      size: 16,
                                      color: _isUnlimitedStock ? const Color(0xFF16A34A) : const Color(0xFF475569),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Stock & Inventory',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                                // Inline Unlimited Toggle
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Unlimited Stock ∞',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: _isUnlimitedStock ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Transform.scale(
                                      scale: 0.75,
                                      child: Switch(
                                        value: _isUnlimitedStock,
                                        activeThumbColor: const Color(0xFF16A34A),
                                        onChanged: (val) {
                                          setState(() {
                                            _isUnlimitedStock = val;
                                            if (val) {
                                              _stockCtrl.text = '';
                                            } else {
                                              _stockCtrl.text = '10';
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (_isUnlimitedStock)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFDCFCE7)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Unlimited stock enabled — No inventory warnings or count tracking needed.',
                                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF15803D), fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildLabel('Current Available Stock *'),
                                        const SizedBox(height: 4),
                                        TextFormField(
                                          controller: _stockCtrl,
                                          keyboardType: TextInputType.number,
                                          style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                          decoration: _buildInputDecoration('e.g. 25'),
                                          validator: (v) {
                                            if (_isUnlimitedStock) return null;
                                            if (v == null || v.trim().isEmpty) return 'Stock required';
                                            return null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildLabel('Low Alert Threshold'),
                                        const SizedBox(height: 4),
                                        TextFormField(
                                          controller: _thresholdCtrl,
                                          keyboardType: TextInputType.number,
                                          style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                          decoration: _buildInputDecoration('e.g. 5'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Bottom Action Buttons: Cancel and Save Product
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveProduct,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 2,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      isEditing ? 'Update Product' : 'Save Product',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF334155),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
      ),
    );
  }
}
