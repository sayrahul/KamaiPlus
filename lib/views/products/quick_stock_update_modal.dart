import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/quantity_config.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';

/// Modal bottom sheet for 1-Tap Rapid Quantity Inward & Retail Stock Adjustments.
/// Supports wholesale box chips ([+6], [+12], [+24], [+48]), Unlimited Stock toggle,
/// and standard retail loss reasons (Damaged, Expired, Personal Use, Physical Audit).
class QuickStockUpdateModal extends StatefulWidget {
  final ProductModel product;
  final VoidCallback onUpdated;

  const QuickStockUpdateModal({
    super.key,
    required this.product,
    required this.onUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required ProductModel product,
    required VoidCallback onUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuickStockUpdateModal(
        product: product,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<QuickStockUpdateModal> createState() => _QuickStockUpdateModalState();
}

class _QuickStockUpdateModalState extends State<QuickStockUpdateModal> {
  // Mode: 0 = Inward (+Stock), 1 = Adjustment / Loss (-Stock / Audit)
  int _activeTab = 0;

  // Inward State
  late TextEditingController _priceCtrl;
  late TextEditingController _customInwardCtrl;
  double _inwardDelta = 0.0;
  bool _isUnlimitedStock = false;

  // Adjustment State
  String _selectedReason = 'Damaged / Wastage';
  String _movementType = 'DAMAGE';
  late TextEditingController _adjustQtyCtrl;
  late TextEditingController _adjustNoteCtrl;

  final List<Map<String, String>> _adjustmentReasons = [
    {
      'label': 'Damaged / Wastage',
      'hindi': 'Torn pack, leak, broken',
      'type': 'DAMAGE',
      'icon': '🗑️',
    },
    {
      'label': 'Expired Item',
      'hindi': 'Expiry date passed, spoiled',
      'type': 'EXPIRED',
      'icon': '⏳',
    },
    {
      'label': 'Personal / Home Use',
      'hindi': 'Ghar ke liye le gaye',
      'type': 'PERSONAL',
      'icon': '🏠',
    },
    {
      'label': 'Physical Audit Recount',
      'hindi': 'Counter ginti correction',
      'type': 'ADJUSTMENT',
      'icon': '⚖️',
    },
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _isUnlimitedStock = p.isUnlimitedStock;
    _priceCtrl = TextEditingController(
      text: (p.sellingPricePaise / 100).toStringAsFixed(0),
    );
    _customInwardCtrl = TextEditingController();
    _adjustQtyCtrl = TextEditingController(text: '1');
    _adjustNoteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _customInwardCtrl.dispose();
    _adjustQtyCtrl.dispose();
    _adjustNoteCtrl.dispose();
    super.dispose();
  }

  double get _currentStock => widget.product.stockQuantity;
  double get _effectiveInwardStock {
    if (_isUnlimitedStock) return 99999.0;
    return (_currentStock + _inwardDelta).clamp(0.0, 99999.0);
  }

  QuantityUnitConfig get _quantityConfig => quantityConfigForUnit(
        widget.product.unit,
        subUnitsPerPack: widget.product.subUnitsPerPack,
      );

  void _addInwardChip(double amount) {
    HapticFeedback.selectionClick();
    setState(() {
      _inwardDelta += amount;
      _isUnlimitedStock = false;
    });
  }

  Future<void> _saveInward() async {
    final p = widget.product;
    final parsedRupees = double.tryParse(_priceCtrl.text) ?? (p.sellingPricePaise / 100.0);
    final sellingPricePaise = (parsedRupees * 100).round();
    final newStock = _effectiveInwardStock;

    // copyWith, not a field-by-field ProductModel(...) reconstruction — the
    // old version here silently dropped businessType (defaulting every
    // stock-updated product back to 'grocery', breaking the vertical
    // isolation fixed elsewhere this session), plus size/color/imeiSerial/
    // hsnCode/isFavorite/subUnitsPerPack. copyWith carries every field
    // forward by default, so a future field added to ProductModel can't be
    // silently lost here again the way this one already was.
    final updated = p.copyWith(
      sellingPricePaise: sellingPricePaise,
      stockQuantity: newStock,
      syncStatus: 'pending',
    );

    await LocalDatabase.instance.upsertProduct(updated);
    FirestoreSyncService.instance.pushProductToCloud(updated).catchError((_) {});

    // Record Inward Movement Audit if delta > 0
    if (_inwardDelta > 0 && !_isUnlimitedStock) {
      final movement = InventoryMovementModel(
        id: 'inv_inw_${DateTime.now().millisecondsSinceEpoch}',
        businessId: p.businessId,
        productId: p.id,
        productName: p.name,
        movementType: 'PURCHASE',
        quantity: _inwardDelta,
        previousStock: _currentStock,
        newStock: newStock,
        referenceId: 'Quick Inward: +${_inwardDelta.toInt()} ${p.unit}',
        createdAt: DateTime.now(),
      );
      await LocalDatabase.instance.recordInventoryMovement(movement);
    }

    widget.onUpdated();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isUnlimitedStock
                ? '✓ ${p.name}: Stock set to Unlimited (∞)'
                : '✓ ${p.name}: Stock updated to ${newStock.toInt()} ${p.unit}',
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveAdjustment() async {
    final p = widget.product;
    final qty = double.tryParse(_adjustQtyCtrl.text) ?? 0.0;
    if (qty <= 0) return;

    double newStock;
    if (_movementType == 'ADJUSTMENT') {
      // Physical Audit Recount (=N)
      newStock = qty;
    } else {
      // Deduction (-N)
      newStock = (_currentStock - qty).clamp(0.0, 99999.0);
    }

    // See the same fix in _saveInward above — copyWith, not a fresh
    // ProductModel(...), so businessType and every other field survive.
    final updated = p.copyWith(
      stockQuantity: newStock,
      syncStatus: 'pending',
    );

    await LocalDatabase.instance.upsertProduct(updated);
    FirestoreSyncService.instance.pushProductToCloud(updated).catchError((_) {});

    // Record Inventory Movement
    final note = _adjustNoteCtrl.text.trim();
    final movement = InventoryMovementModel(
      id: 'inv_adj_${DateTime.now().millisecondsSinceEpoch}',
      businessId: p.businessId,
      productId: p.id,
      productName: p.name,
      movementType: _movementType,
      quantity: qty,
      previousStock: _currentStock,
      newStock: newStock,
      referenceId: note.isNotEmpty ? '$_selectedReason: $note' : _selectedReason,
      createdAt: DateTime.now(),
    );
    await LocalDatabase.instance.recordInventoryMovement(movement);

    widget.onUpdated();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Stock adjusted for ${p.name}: Now ${newStock.toInt()} ${p.unit}'),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Current Stock: ${p.isUnlimitedStock ? "∞ Unlimited" : "${p.stockQuantity.toInt()} ${p.unit}"} • Selling: ${MoneyFormatter.formatINR(p.sellingPricePaise)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Mode Tabs: "⚡ Inward / Add Stock" vs "📉 Stock Adjustment / Loss"
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _activeTab = 0);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == 0 ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _activeTab == 0
                                ? [const BoxShadow(color: Color(0x0A000000), blurRadius: 4)]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_box_outlined, size: 16, color: Color(0xFF059669)),
                              const SizedBox(width: 6),
                              Text(
                                '+ Inward Stock',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: _activeTab == 0 ? FontWeight.w800 : FontWeight.w600,
                                  color: _activeTab == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _activeTab = 1);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == 1 ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _activeTab == 1
                                ? [const BoxShadow(color: Color(0x0A000000), blurRadius: 4)]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_outlined, size: 16, color: Color(0xFFDC2626)),
                              const SizedBox(width: 6),
                              Text(
                                '- Loss / Adjust',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: _activeTab == 1 ? FontWeight.w800 : FontWeight.w600,
                                  color: _activeTab == 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
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
              const SizedBox(height: 18),

              // TAB 0: RAPID INWARD / ADD STOCK
              if (_activeTab == 0) ...[
                // Quick-add chips, sized to how this product is actually sold —
                // a kg-priced loose item (kaju, badam, atta) gets 10g-500g chips
                // instead of the old fixed dozen/carton set that never fit it.
                Text(
                  'QUICK ADD QUANTITY (${p.unit.toUpperCase()})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quantityConfig.chips
                      .map((chip) => _buildInwardChip('+${chip.label}', chip.value))
                      .toList(),
                ),
                const SizedBox(height: 16),

                // Calculator Preview Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      // Stepper: Minus
                      IconButton(
                        onPressed: () {
                          if (_inwardDelta > 0) {
                            HapticFeedback.lightImpact();
                            setState(() => _inwardDelta--);
                          }
                        },
                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF64748B), size: 24),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _isUnlimitedStock ? '∞ Unlimited' : '${_effectiveInwardStock.toInt()} ${p.unit}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            if (!_isUnlimitedStock && _inwardDelta > 0)
                              Text(
                                '(${_currentStock.toInt()} existing + ${_inwardDelta.toInt()} added)',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: const Color(0xFF059669),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Stepper: Plus
                      IconButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _inwardDelta++;
                            _isUnlimitedStock = false;
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0F172A), size: 24),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Unlimited Stock Switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isUnlimitedStock ? const Color(0xFFF0FDF4) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isUnlimitedStock ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.all_inclusive_rounded, size: 20, color: Color(0xFF16A34A)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unlimited Stock (∞)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Never blocks billing with zero stock',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isUnlimitedStock,
                        activeThumbColor: const Color(0xFF10B981),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isUnlimitedStock = val;
                            if (val) _inwardDelta = 0;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Selling Price Input
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SELLING PRICE (₹)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Save Inward Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saveInward,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      'Save Stock Update',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // TAB 1: RETAIL LOSS & STOCK ADJUSTMENT
                Text(
                  'SELECT ADJUSTMENT REASON',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),

                // 4 Standard Retail Reason Tiles
                ..._adjustmentReasons.map((reason) {
                  final isSel = _selectedReason == reason['label'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedReason = reason['label']!;
                          _movementType = reason['type']!;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFFEF2F2) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSel ? const Color(0xFFF87171) : const Color(0xFFE2E8F0),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(reason['icon']!, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reason['label']!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    reason['hindi']!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSel)
                              const Icon(Icons.check_circle, size: 18, color: Color(0xFFDC2626)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // Quantity to adjust
                Text(
                  _movementType == 'ADJUSTMENT'
                      ? 'PHYSICAL AUDIT COUNT (${p.unit})'
                      : 'QUANTITY TO DEDUCT (${p.unit})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _adjustQtyCtrl,
                  // Decimal, not plain 'number' — a damaged/spilled loose item
                  // (e.g. 0.25kg of kaju) needs the same fractional entry as
                  // adding stock does, not just whole units.
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFDC2626),
                  ),
                  decoration: InputDecoration(
                    prefixText: _movementType == 'ADJUSTMENT' ? '= ' : '- ',
                    prefixStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFDC2626),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFFF1F2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFFECDD3)),
                    ),
                  ),
                ),
                // Same unit-aware quick chips as the Inward tab — only for a
                // deduction, not a physical recount (that's a direct total,
                // not an increment, so a "+250g" chip wouldn't make sense there).
                if (_movementType != 'ADJUSTMENT') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quantityConfig.chips.map((chip) {
                      final chipValStr = chip.value % 1 == 0 ? chip.value.toInt().toString() : chip.value.toString();
                      final isSelected = _adjustQtyCtrl.text == chipValStr;
                      return InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _adjustQtyCtrl.text = chipValStr);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFECACA) : const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECDD3), width: 1.1),
                          ),
                          child: Text(
                            chip.label,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),

                // Optional Note
                TextField(
                  controller: _adjustNoteCtrl,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Note / Remarks (Optional)',
                    hintText: 'e.g. Broken in transit, rat bite',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Save Adjustment Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saveAdjustment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      'Record Adjustment & Update Stock',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInwardChip(String label, double qty) {
    return InkWell(
      onTap: () => _addInwardChip(qty),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFA7F3D0), width: 1.1),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF047857),
          ),
        ),
      ),
    );
  }
}
