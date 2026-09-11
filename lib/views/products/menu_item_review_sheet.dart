import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/gemini_ai_service.dart';

class _ReviewDishState {
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  String category;
  ProductModel? matchedProduct; // an existing dish with the same name, if any

  _ReviewDishState({
    required this.nameCtrl,
    required this.priceCtrl,
    required this.category,
    this.matchedProduct,
  });

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

/// Review screen shown after a menu photo scan: one editable row per dish
/// (name, price, category), before anything is written to the catalog.
///
/// Intentionally much simpler than [BillScanReviewSheet] (its purchase-bill
/// counterpart) — a menu item has no cost price, MRP, quantity received, or
/// supplier to review, so none of those fields are shown here.
class MenuItemReviewSheet extends StatefulWidget {
  final List<ExtractedMenuItem> initialItems;
  final VoidCallback? onMenuAddComplete;

  const MenuItemReviewSheet({
    super.key,
    required this.initialItems,
    this.onMenuAddComplete,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ExtractedMenuItem> initialItems,
    VoidCallback? onMenuAddComplete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MenuItemReviewSheet(
        initialItems: initialItems,
        onMenuAddComplete: onMenuAddComplete,
      ),
    );
  }

  @override
  State<MenuItemReviewSheet> createState() => _MenuItemReviewSheetState();
}

class _MenuItemReviewSheetState extends State<MenuItemReviewSheet> {
  final List<_ReviewDishState> _items = [];
  List<ProductModel> _existingCatalog = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCatalogAndInitialize();
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalogAndInitialize() async {
    try {
      _existingCatalog = await LocalDatabase.instance.getAllProducts(
        businessType: BusinessVerticals.activeBusinessTypeNotifier.value,
      );
    } catch (_) {}

    for (final it in widget.initialItems) {
      final matched = _findMatch(it.dishName);
      _items.add(_ReviewDishState(
        nameCtrl: TextEditingController(text: it.dishName),
        priceCtrl: TextEditingController(
          text: (it.priceInPaise / 100.0).toStringAsFixed(2),
        ),
        category: it.category.trim().isNotEmpty ? it.category.trim() : 'General',
        matchedProduct: matched,
      ));
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // Same case-insensitive substring match used by BillScanReviewSheet, so a
  // second scan of the same menu updates prices instead of duplicating dishes.
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

  void _removeItem(int index) {
    setState(() {
      final it = _items.removeAt(index);
      it.dispose();
    });
  }

  void _addNewItem() {
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
    setState(() {
      _items.add(_ReviewDishState(
        nameCtrl: TextEditingController(),
        priceCtrl: TextEditingController(text: '0.00'),
        category: vert.quickCategories.isNotEmpty ? vert.quickCategories.first : 'General',
      ));
    });
  }

  Future<void> _saveDishesToMenu() async {
    final validItems = _items.where((it) => it.nameCtrl.text.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 1 dish.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final bizId = FirestoreSyncService.instance.activeBusinessId;
      final businessType = BusinessVerticals.activeBusinessTypeNotifier.value;
      const uuid = Uuid();

      int updatedCount = 0;
      int createdCount = 0;

      for (final it in validItems) {
        final name = it.nameCtrl.text.trim();
        final pricePaise = MoneyFormatter.parseRupeesToPaise(it.priceCtrl.text.trim());
        final matched = it.matchedProduct ?? _findMatch(name);

        if (matched != null) {
          // Dish already on the menu — refresh its price rather than duplicating it.
          final updatedDish = matched.copyWith(
            sellingPricePaise: pricePaise > 0 ? pricePaise : matched.sellingPricePaise,
            mrpPaise: pricePaise > 0 ? pricePaise : matched.mrpPaise,
            syncStatus: 'pending',
          );
          await LocalDatabase.instance.upsertProduct(updatedDish);
          FirestoreSyncService.instance.pushProductToCloud(updatedDish).catchError((_) {});
          updatedCount++;
        } else {
          final categoryId = await LocalDatabase.instance.findOrCreateCategoryId(
            name: it.category,
            businessId: bizId,
            businessType: businessType,
          );

          final newDish = ProductModel(
            id: uuid.v4(),
            businessId: bizId,
            name: name,
            categoryId: categoryId,
            sellingPricePaise: pricePaise,
            mrpPaise: pricePaise,
            purchasePricePaise: 0,
            // Restaurant dishes default to unlimited stock, matching the same
            // convention used when a dish is added manually (AddProductModal).
            stockQuantity: 99999.0,
            taxRate: 0.0,
            isTaxInclusive: true,
            unit: 'plate',
            syncStatus: 'pending',
            businessType: businessType,
          );

          await LocalDatabase.instance.upsertProduct(newDish);

          // Audit trail entry. 'ADJUSTMENT' (not 'PURCHASE') — a scanned menu
          // dish was never bought from a supplier, so labelling it a purchase
          // would misrepresent the store's actual purchase history.
          await LocalDatabase.instance.recordInventoryMovement(
            InventoryMovementModel(
              id: uuid.v4(),
              businessId: bizId,
              productId: newDish.id,
              productName: newDish.name,
              movementType: 'ADJUSTMENT',
              quantity: 99999.0,
              previousStock: 0.0,
              newStock: 99999.0,
              referenceId: 'MENU-SCAN',
              createdAt: DateTime.now(),
            ),
          );

          FirestoreSyncService.instance.pushProductToCloud(newDish).catchError((_) {});
          createdCount++;
        }
      }

      HapticFeedback.mediumImpact();
      widget.onMenuAddComplete?.call();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$createdCount dish(es) added, $updatedCount price(s) updated.',
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save menu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Review Menu (${_items.length})',
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
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
                      const SizedBox(height: 2),
                      Text(
                        'Check names & prices before adding to your menu. Nothing is saved yet.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFD97706)))
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) => _buildDishRow(i),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      TextButton.icon(
                        onPressed: _addNewItem,
                        icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFF0F172A)),
                        label: Text(
                          'Add Dish Manually',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveDishesToMenu,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                )
                              : Text(
                                  'Confirm & Add to Menu',
                                  style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDishRow(int index) {
    final it = _items[index];
    final isDuplicate = it.matchedProduct != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDuplicate ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: it.nameCtrl,
                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Dish name',
                    border: InputBorder.none,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _removeItem(index),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                ),
              ),
            ],
          ),
          if (isDuplicate)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Already on your menu — price will be updated',
                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFB45309), fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: it.priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '₹ ',
                    prefixStyle: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _categoryOptions().contains(it.category) ? it.category : null,
                      hint: Text(it.category, style: GoogleFonts.inter(fontSize: 11.5)),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      items: _categoryOptions()
                          .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.inter(fontSize: 11.5), overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => it.category = val);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _categoryOptions() {
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
    final options = <String>{...vert.quickCategories};
    for (final it in _items) {
      options.add(it.category);
    }
    return options.toList();
  }
}
