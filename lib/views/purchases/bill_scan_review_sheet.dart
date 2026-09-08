import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/gemini_ai_service.dart';

class BillScanReviewSheet extends StatefulWidget {
  final List<ExtractedBillItem> initialItems;
  final String? initialSupplierName;
  final String? initialBillNumber;
  final String? initialBillDate;
  final VoidCallback? onInwardComplete;

  const BillScanReviewSheet({
    super.key,
    required this.initialItems,
    this.initialSupplierName,
    this.initialBillNumber,
    this.initialBillDate,
    this.onInwardComplete,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ExtractedBillItem> items,
    String? supplierName,
    String? billNumber,
    String? billDate,
    VoidCallback? onInwardComplete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BillScanReviewSheet(
        initialItems: items,
        initialSupplierName: supplierName,
        initialBillNumber: billNumber,
        initialBillDate: billDate,
        onInwardComplete: onInwardComplete,
      ),
    );
  }

  @override
  State<BillScanReviewSheet> createState() => _BillScanReviewSheetState();
}

class _ReviewItemState {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
  final TextEditingController sellingCtrl;
  final TextEditingController mrpCtrl;
  String unit;
  String category;
  ProductModel? matchedProduct;

  _ReviewItemState({
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.costCtrl,
    required this.sellingCtrl,
    required this.mrpCtrl,
    required this.unit,
    required this.category,
    this.matchedProduct,
  });

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    costCtrl.dispose();
    sellingCtrl.dispose();
    mrpCtrl.dispose();
  }
}

class _BillScanReviewSheetState extends State<BillScanReviewSheet> {
  late TextEditingController _supplierCtrl;
  late TextEditingController _billNoCtrl;
  final List<_ReviewItemState> _items = [];
  List<ProductModel> _existingCatalog = [];
  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _availableUnits = [
    'pcs',
    'kg',
    'gram',
    'litre',
    'ml',
    'strip',
    'box',
    'packet',
    'bag',
    'meter',
  ];

  @override
  void initState() {
    super.initState();
    _supplierCtrl = TextEditingController(text: widget.initialSupplierName ?? '');
    _billNoCtrl = TextEditingController(text: widget.initialBillNumber ?? 'BILL-${DateTime.now().millisecondsSinceEpoch % 10000}');
    _loadCatalogAndInitialize();
  }

  Future<void> _loadCatalogAndInitialize() async {
    try {
      _existingCatalog = await LocalDatabase.instance.getAllProducts();
    } catch (_) {}

    for (final it in widget.initialItems) {
      final matched = _findMatch(it.productName);

      final itemState = _ReviewItemState(
        nameCtrl: TextEditingController(text: it.productName),
        qtyCtrl: TextEditingController(text: (it.quantity % 1 == 0 ? it.quantity.toInt() : it.quantity).toString()),
        costCtrl: TextEditingController(text: (it.purchasePricePaise / 100.0).toStringAsFixed(2)),
        sellingCtrl: TextEditingController(text: (it.sellingPricePaise / 100.0).toStringAsFixed(2)),
        mrpCtrl: TextEditingController(text: (it.mrpPaise / 100.0).toStringAsFixed(2)),
        unit: _availableUnits.contains(it.unit.toLowerCase()) ? it.unit.toLowerCase() : 'pcs',
        category: it.categoryName,
        matchedProduct: matched,
      );

      _items.add(itemState);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ProductModel? _findMatch(String name) {
    if (name.trim().isEmpty) return null;
    final clean = name.trim().toLowerCase();
    for (final p in _existingCatalog) {
      final pName = p.name.trim().toLowerCase();
      if (pName == clean || pName.contains(clean) || clean.contains(pName)) {
        return p;
      }
    }
    return null;
  }

  void _onNameChanged(int index, String newName) {
    final matched = _findMatch(newName);
    setState(() {
      _items[index].matchedProduct = matched;
    });
  }

  void _removeItem(int index) {
    setState(() {
      final it = _items.removeAt(index);
      it.dispose();
    });
  }

  void _addNewItem() {
    setState(() {
      _items.add(_ReviewItemState(
        nameCtrl: TextEditingController(text: 'New Inward Product'),
        qtyCtrl: TextEditingController(text: '1'),
        costCtrl: TextEditingController(text: '100.00'),
        sellingCtrl: TextEditingController(text: '120.00'),
        mrpCtrl: TextEditingController(text: '130.00'),
        unit: 'pcs',
        category: 'General',
      ));
    });
  }

  int get _totalInwardCostPaise {
    int total = 0;
    for (final it in _items) {
      final qty = double.tryParse(it.qtyCtrl.text.trim()) ?? 0.0;
      final cost = MoneyFormatter.parseRupeesToPaise(it.costCtrl.text.trim());
      total += (qty * cost).round();
    }
    return total;
  }

  Future<void> _saveInwardToStock() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 1 item to inward.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final bizId = FirestoreSyncService.instance.activeBusinessId;
      final supplierName = _supplierCtrl.text.trim();
      final billNo = _billNoCtrl.text.trim();

      int updatedCount = 0;
      int createdCount = 0;

      for (final it in _items) {
        final name = it.nameCtrl.text.trim();
        if (name.isEmpty) continue;

        final qty = double.tryParse(it.qtyCtrl.text.trim()) ?? 1.0;
        final costPaise = MoneyFormatter.parseRupeesToPaise(it.costCtrl.text.trim());
        final sellingPaise = MoneyFormatter.parseRupeesToPaise(it.sellingCtrl.text.trim());
        final mrpPaise = MoneyFormatter.parseRupeesToPaise(it.mrpCtrl.text.trim());

        final matched = it.matchedProduct ?? _findMatch(name);

        if (matched != null) {
          // Increment stock of existing SKU
          final oldStock = matched.stockQuantity;
          final newStock = oldStock + qty;

          final updatedProd = matched.copyWith(
            stockQuantity: newStock,
            purchasePricePaise: costPaise > 0 ? costPaise : matched.purchasePricePaise,
            sellingPricePaise: sellingPaise > 0 ? sellingPaise : matched.sellingPricePaise,
            mrpPaise: mrpPaise > 0 ? mrpPaise : matched.mrpPaise,
          );

          await LocalDatabase.instance.upsertProduct(updatedProd);

          // Audit movement
          await LocalDatabase.instance.recordInventoryMovement(
            InventoryMovementModel(
              id: const Uuid().v4(),
              businessId: bizId,
              productId: matched.id,
              productName: matched.name,
              movementType: 'PURCHASE',
              quantity: qty,
              previousStock: oldStock,
              newStock: newStock,
              referenceId: billNo.isNotEmpty ? billNo : 'AI-INWARD',
              createdAt: DateTime.now(),
            ),
          );

          FirestoreSyncService.instance.pushProductToCloud(updatedProd);
          updatedCount++;
        } else {
          // Insert brand new SKU
          final newId = const Uuid().v4();
          final newProd = ProductModel(
            id: newId,
            businessId: bizId,
            name: name,
            purchasePricePaise: costPaise,
            sellingPricePaise: sellingPaise > 0 ? sellingPaise : (costPaise * 1.15).round(),
            mrpPaise: mrpPaise > 0 ? mrpPaise : (costPaise * 1.2).round(),
            stockQuantity: qty,
            unit: it.unit,
          );

          await LocalDatabase.instance.upsertProduct(newProd);

          // Audit movement
          await LocalDatabase.instance.recordInventoryMovement(
            InventoryMovementModel(
              id: const Uuid().v4(),
              businessId: bizId,
              productId: newId,
              productName: name,
              movementType: 'PURCHASE',
              quantity: qty,
              previousStock: 0.0,
              newStock: qty,
              referenceId: billNo.isNotEmpty ? billNo : 'AI-INWARD',
              createdAt: DateTime.now(),
            ),
          );

          FirestoreSyncService.instance.pushProductToCloud(newProd);
          createdCount++;
        }
      }

      // Upsert supplier if provided
      if (supplierName.isNotEmpty) {
        final sup = SupplierModel(
          id: 'sup_${supplierName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}',
          businessId: bizId,
          name: supplierName,
          phone: '',
          category: 'Wholesale Supplier',
          currentBalancePaise: 0,
        );
        await LocalDatabase.instance.upsertSupplier(sup);
      }

      HapticFeedback.mediumImpact();
      widget.onInwardComplete?.call();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ Inward Successful! $createdCount new products added, $updatedCount stock quantities updated.',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save inward: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _billNoCtrl.dispose();
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),

            // Sheet Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review Inward Items',
                          style: GoogleFonts.plusJakartaSans(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                        ),
                        Text(
                          '${_items.length} items detected • Edit quantities or prices before saving',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16, color: Color(0xFFE2E8F0)),

            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF059669)),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Bill Metadata Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _supplierCtrl,
                              decoration: InputDecoration(
                                labelText: 'Supplier / Mandi Vendor',
                                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                prefixIcon: const Icon(Icons.store_rounded, size: 18, color: Color(0xFF64748B)),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: _billNoCtrl,
                              decoration: InputDecoration(
                                labelText: 'Bill / Memo #',
                                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Detected Items Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'INWARD PRODUCTS (${_items.length})',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF475569), letterSpacing: 0.5),
                        ),
                        TextButton.icon(
                          onPressed: _addNewItem,
                          icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF059669)),
                          label: Text(
                            '+ Add Row',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                          ),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Items List
                    ...List.generate(_items.length, (idx) {
                      return _buildItemCard(idx);
                    }),
                    const SizedBox(height: 100), // padding for floating footer
                  ],
                ),
              ),

            // Floating Bottom Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Inward Cost',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      Text(
                        MoneyFormatter.formatINR(_totalInwardCostPaise),
                        style: GoogleFonts.jetBrainsMono(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveInwardToStock,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Row(
                            children: [
                              const Icon(Icons.inventory_2_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Confirm & Save Stock',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final it = _items[index];
    final isMatched = it.matchedProduct != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMatched ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
          width: isMatched ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Product Name & Delete button
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: it.nameCtrl,
                  onChanged: (val) => _onNameChanged(index, val),
                  decoration: InputDecoration(
                    labelText: 'Product Name',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                onPressed: () => _removeItem(index),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Match badge status
          if (isMatched)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sync_rounded, color: Color(0xFF2563EB), size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Existing SKU • Current Stock: ${it.matchedProduct!.stockQuantity.toInt()} ➔ New: ${(it.matchedProduct!.stockQuantity + (double.tryParse(it.qtyCtrl.text) ?? 1.0)).toInt()} ${it.matchedProduct!.unit}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF1D4ED8)),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFF059669), size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '✨ New SKU • Will be added to catalog',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),

          // Row 2: Qty, Unit, Cost Price, Selling Price
          Row(
            children: [
              // Quantity
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: it.qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Qty',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 10.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),

              // Unit Dropdown
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: it.unit,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Unit',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 10.5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _availableUnits.map((u) {
                    return DropdownMenuItem(value: u, child: Text(u, style: GoogleFonts.plusJakartaSans(fontSize: 11.5)));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => it.unit = val);
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Purchase Cost ₹
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: it.costCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Buy ₹',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 10.5),
                    prefixText: '₹',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),

              // Selling Price ₹
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: it.sellingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Sell ₹',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 10.5),
                    prefixText: '₹',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
