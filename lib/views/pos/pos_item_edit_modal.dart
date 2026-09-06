import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';

class PosItemEditModal extends StatefulWidget {
  final CartItemModel cartItem;
  final Function(CartItemModel updatedItem) onUpdate;

  const PosItemEditModal({
    super.key,
    required this.cartItem,
    required this.onUpdate,
  });

  static Future<void> show(
    BuildContext context, {
    required CartItemModel cartItem,
    required Function(CartItemModel updatedItem) onUpdate,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PosItemEditModal(
        cartItem: cartItem,
        onUpdate: onUpdate,
      ),
    );
  }

  @override
  State<PosItemEditModal> createState() => _PosItemEditModalState();
}

class _PosItemEditModalState extends State<PosItemEditModal> {
  late TextEditingController _qtyController;
  late TextEditingController _priceController;
  late TextEditingController _discountController;

  late String _discountType; // 'flat' or 'percentage'
  late String _currentUnit;

  @override
  void initState() {
    super.initState();
    final item = widget.cartItem;
    // Format quantity: if whole number, show without decimals
    final qtyStr = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toString();
    _qtyController = TextEditingController(text: qtyStr);

    final priceRupees = (item.unitPricePaise / 100.0);
    _priceController = TextEditingController(
      text: priceRupees % 1 == 0 ? priceRupees.toInt().toString() : priceRupees.toStringAsFixed(2),
    );

    _discountType = item.discountType;
    final discVal = item.discountValue;
    _discountController = TextEditingController(
      text: discVal > 0
          ? (discVal % 1 == 0 ? discVal.toInt().toString() : discVal.toStringAsFixed(2))
          : '0',
    );

    _currentUnit = (item.product.unit.isNotEmpty ? item.product.unit : 'packet').toLowerCase();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _getQuantityConfig() {
    final norm = _currentUnit;
    if (norm == 'kg') {
      return {
        'unitLabel': 'Weight (Kilograms - kg)',
        'decimalNotice': 'Decimals supported (Grams / Kg)',
        'chips': [
          {'label': '10g', 'val': '0.01'},
          {'label': '25g', 'val': '0.025'},
          {'label': '50g', 'val': '0.05'},
          {'label': '100g', 'val': '0.1'},
          {'label': '250g', 'val': '0.25'},
          {'label': '500g', 'val': '0.5'},
          {'label': '1 kg', 'val': '1'},
          {'label': '2 kg', 'val': '2'},
          {'label': '5 kg', 'val': '5'},
        ],
      };
    } else if (norm == 'gram' || norm == 'g') {
      return {
        'unitLabel': 'Weight (Grams - g)',
        'decimalNotice': 'Grams count',
        'chips': [
          {'label': '10g', 'val': '10'},
          {'label': '25g', 'val': '25'},
          {'label': '50g', 'val': '50'},
          {'label': '100g', 'val': '100'},
          {'label': '250g', 'val': '250'},
          {'label': '500g', 'val': '500'},
          {'label': '1000g', 'val': '1000'},
        ],
      };
    } else if (norm == 'litre' || norm == 'l') {
      return {
        'unitLabel': 'Volume (Litres - L)',
        'decimalNotice': 'Decimals supported (ml / Litres)',
        'chips': [
          {'label': '100ml', 'val': '0.1'},
          {'label': '250ml', 'val': '0.25'},
          {'label': '500ml', 'val': '0.5'},
          {'label': '1 L', 'val': '1'},
          {'label': '2 L', 'val': '2'},
          {'label': '5 L', 'val': '5'},
        ],
      };
    } else if (norm == 'strip') {
      return {
        'unitLabel': 'Quantity (Strips)',
        'decimalNotice': 'Strip counts (0.5 for loose/half)',
        'chips': [
          {'label': '1 Strip', 'val': '1'},
          {'label': '2 Strips', 'val': '2'},
          {'label': '3 Strips', 'val': '3'},
          {'label': '4 Strips', 'val': '4'},
          {'label': '5 Strips', 'val': '5'},
          {'label': '10 Strips', 'val': '10'},
          {'label': '½ Strip', 'val': '0.5'},
        ],
      };
    } else if (norm == 'dozen') {
      return {
        'unitLabel': 'Quantity (Dozen)',
        'decimalNotice': 'Dozen count (0.5 = 6 pcs)',
        'chips': [
          {'label': '½ Dozen (6)', 'val': '0.5'},
          {'label': '1 Dozen (12)', 'val': '1'},
          {'label': '1.5 Dozen (18)', 'val': '1.5'},
          {'label': '2 Dozen (24)', 'val': '2'},
          {'label': '3 Dozen (36)', 'val': '3'},
          {'label': '5 Dozen (60)', 'val': '5'},
        ],
      };
    }

    // Default: Packet, Piece, Box, Bottle, etc.
    final displayUnitName = norm.isNotEmpty ? (norm[0].toUpperCase() + norm.substring(1)) : 'Packet';
    return {
      'unitLabel': 'Quantity ($displayUnitName)',
      'decimalNotice': 'Whole count / Units',
      'chips': [
        {'label': '1', 'val': '1'},
        {'label': '2', 'val': '2'},
        {'label': '3', 'val': '3'},
        {'label': '4', 'val': '4'},
        {'label': '5', 'val': '5'},
        {'label': '6', 'val': '6'},
        {'label': '10', 'val': '10'},
        {'label': '12', 'val': '12'},
        {'label': '24', 'val': '24'},
      ],
    };
  }

  void _handleSave() {
    final qty = double.tryParse(_qtyController.text) ?? 1.0;
    final price = double.tryParse(_priceController.text) ?? (widget.cartItem.product.sellingPricePaise / 100.0);
    final disc = double.tryParse(_discountController.text) ?? 0.0;

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0'), backgroundColor: Colors.red),
      );
      return;
    }

    widget.cartItem.quantity = qty;
    widget.cartItem.unitPricePaise = (price * 100).round();
    widget.cartItem.discountType = _discountType;
    widget.cartItem.discountValue = disc;

    widget.onUpdate(widget.cartItem);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final config = _getQuantityConfig();
    final List<Map<String, String>> chips = List<Map<String, String>>.from(config['chips'] as List);

    final qty = double.tryParse(_qtyController.text) ?? 0.0;
    final unitPrice = double.tryParse(_priceController.text) ?? 0.0;
    final disc = double.tryParse(_discountController.text) ?? 0.0;

    double discountRupees = 0.0;
    if (disc > 0 && qty > 0 && unitPrice > 0) {
      if (_discountType == 'percentage') {
        discountRupees = (qty * unitPrice * (disc.clamp(0, 100))) / 100.0;
      } else {
        discountRupees = disc.clamp(0, qty * unitPrice);
      }
    }
    final netTotalRupees = (qty * unitPrice - discountRupees).clamp(0.0, double.infinity);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Header with Close '✕' Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Edit Item: ${widget.cartItem.product.name}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 2. Quantity Label, Unit Pill, and Notice
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      config['unitLabel'] as String,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _currentUnit.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  config['decimalNotice'] as String,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quantity Input Box with Stepper buttons
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18, color: Color(0xFF334155)),
                    onPressed: () {
                      final cur = double.tryParse(_qtyController.text) ?? 1.0;
                      if (cur > 1) {
                        setState(() {
                          final next = cur - 1;
                          _qtyController.text = next % 1 == 0 ? next.toInt().toString() : next.toString();
                        });
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18, color: Color(0xFF334155)),
                    onPressed: () {
                      final cur = double.tryParse(_qtyController.text) ?? 0.0;
                      setState(() {
                        final next = cur + 1;
                        _qtyController.text = next % 1 == 0 ? next.toInt().toString() : next.toString();
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Quick Quantity Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: chips.map((chip) {
                  final isSelected = _qtyController.text == chip['val'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _qtyController.text = chip['val']!;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFBBF24) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          chip['label']!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Unit Price (₹)
            Text(
              'Unit Price (₹)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    '₹ ',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Line Item Discount Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Line Item Discount',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      // Segmented toggle: Flat vs Percent
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _discountType = 'flat'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _discountType == 'flat' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: _discountType == 'flat'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  '₹ Flat',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _discountType == 'flat' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _discountType = 'percentage'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _discountType == 'percentage' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: _discountType == 'percentage'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  '% Percent',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _discountType == 'percentage' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Discount text field
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Text(
                          _discountType == 'flat' ? '₹ ' : '% ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: _discountType == 'flat' ? '0' : 'e.g. 10 for 10%',
                              hintStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quick chips if percentage
                  if (_discountType == 'percentage') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: ['5', '10', '15', '20', '50'].map((pct) {
                        final isSel = _discountController.text == pct;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() => _discountController.text = pct),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFF10B981) : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSel ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                '$pct%',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.white : const Color(0xFF334155),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // Savings feedback row
                  if (discountRupees > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Savings: -₹${discountRupees.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF047857),
                          ),
                        ),
                        Text(
                          'Net Total: ₹${netTotalRupees.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Action Buttons (Cancel & Update Line Item)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text(
                    'Update Line Item',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
