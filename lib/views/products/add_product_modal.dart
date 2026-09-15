import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/quantity_config.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/cloud_barcode_resolver_service.dart';
import '../pos/barcode_scanner_view.dart';
import '../common/in_app_notification.dart';

class _VariantInputData {
  final TextEditingController priceCtrl;
  final TextEditingController mrpCtrl;
  final TextEditingController stockCtrl;

  _VariantInputData({
    required String defaultPrice,
    required String defaultMrp,
    required String defaultStock,
  })  : priceCtrl = TextEditingController(text: defaultPrice),
        mrpCtrl = TextEditingController(text: defaultMrp),
        stockCtrl = TextEditingController(text: defaultStock);

  void dispose() {
    priceCtrl.dispose();
    mrpCtrl.dispose();
    stockCtrl.dispose();
  }
}

class AddProductModal extends StatefulWidget {
  final ProductModel? existingProduct;
  final String? parentIdForNewVariant;
  final List<CategoryModel> categories;
  final VoidCallback onSaved;
  final VoidCallback onSwitchToAiInward;

  const AddProductModal({
    super.key,
    this.existingProduct,
    this.parentIdForNewVariant,
    required this.categories,
    required this.onSaved,
    required this.onSwitchToAiInward,
  });

  static Future<void> show(
    BuildContext context, {
    ProductModel? existingProduct,
    String? parentIdForNewVariant,
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
        parentIdForNewVariant: parentIdForNewVariant,
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
  late final TextEditingController _batchNumberCtrl;
  late final TextEditingController _subUnitsPerPackCtrl;
  late final TextEditingController _expiryDateCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _fitNotesCtrl;
  late final TextEditingController _imeiCtrl;
  late final TextEditingController _warrantyCtrl;
  final FocusNode _nameFocusNode = FocusNode();

  late String _selectedCategoryId;
  late String _selectedUnit;
  late double _selectedTaxRate;
  late List<CategoryModel> _localCategories;
  bool _isSaving = false;
  bool _isUnlimitedStock = false;
  bool _isStockExpanded = false;
  bool _isFavorite = false;
  bool _isResolvingBarcode = false;
  bool _enableVariants = false;
  final Set<String> _selectedVariants = {};
  final Map<String, _VariantInputData> _variantConfigs = {};
  late final TextEditingController _customVariantCtrl;

  late final List<Map<String, String>> _units;

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
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
    _units = vert.recommendedUnits.map((u) {
      final label = BusinessVerticals.unitDisplayLabels[u] ?? '$u ($u)';
      return {'label': label, 'val': u};
    }).toList();

    _isFavorite = p?.isFavorite ?? false;
    // New products default to unlimited stock across every vertical — most
    // shopkeepers don't track exact counts from day one, and this matches
    // rapid barcode inward's no-friction philosophy. Editing an existing
    // product still reflects its real saved state.
    _isUnlimitedStock = p != null ? (p.stockQuantity >= 99999) : true;
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
      text: p != null ? (_isUnlimitedStock ? '' : p.stockQuantity.toInt().toString()) : (_isUnlimitedStock ? '' : '0'),
    );
    _thresholdCtrl = TextEditingController(text: '5');
    _batchNumberCtrl = TextEditingController(text: p?.batchNumber ?? '');
    _subUnitsPerPackCtrl = TextEditingController(text: p?.subUnitsPerPack?.toString() ?? '');
    _expiryDateCtrl = TextEditingController(text: p?.expiryDate ?? '');
    _sizeCtrl = TextEditingController(text: p?.size ?? '');
    _colorCtrl = TextEditingController(text: p?.color ?? '');
    _fitNotesCtrl = TextEditingController(text: p?.fitNotes ?? '');
    _imeiCtrl = TextEditingController(text: p?.imeiSerial ?? '');
    _warrantyCtrl = TextEditingController();
    _customVariantCtrl = TextEditingController();

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
        final customLabel = BusinessVerticals.unitDisplayLabels[unitClean.toLowerCase()] ?? '$unitClean (Saved)';
        _units.add({'label': customLabel, 'val': unitClean});
        _selectedUnit = unitClean;
      }
    } else {
      _selectedUnit = vert.defaultUnit.isNotEmpty && _units.any((u) => u['val'] == vert.defaultUnit)
          ? vert.defaultUnit
          : (_units.isNotEmpty ? _units.first['val']! : 'pcs');
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
    _batchNumberCtrl.dispose();
    _subUnitsPerPackCtrl.dispose();
    _expiryDateCtrl.dispose();
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    _fitNotesCtrl.dispose();
    _imeiCtrl.dispose();
    _warrantyCtrl.dispose();
    _customVariantCtrl.dispose();
    _nameFocusNode.dispose();
    for (final cfg in _variantConfigs.values) {
      cfg.dispose();
    }
    super.dispose();
  }

  void _addVariant(String label) {
    final clean = label.trim();
    if (clean.isEmpty) return;
    if (!_selectedVariants.contains(clean)) {
      _selectedVariants.add(clean);
      final defaultStock = _isUnlimitedStock ? '999999' : (_stockCtrl.text.isNotEmpty ? _stockCtrl.text : '10');
      _variantConfigs[clean] = _VariantInputData(
        defaultPrice: _sellPriceCtrl.text,
        defaultMrp: _mrpCtrl.text,
        defaultStock: defaultStock,
      );
    }
  }

  void _removeVariant(String label) {
    _selectedVariants.remove(label);
    _variantConfigs[label]?.dispose();
    _variantConfigs.remove(label);
  }

  double get _profitMargin {
    final sell = double.tryParse(_sellPriceCtrl.text) ?? 0.0;
    final cost = double.tryParse(_costPriceCtrl.text) ?? 0.0;
    return sell - cost;
  }

  // Reacts live to _selectedUnit — a merchant picking "kg" for a new loose
  // item (kaju, badam) sees opening-stock chips in grams, not the generic
  // whole-count list every other unit fell back to before this.
  QuantityUnitConfig get _quantityConfig => quantityConfigForUnit(_selectedUnit);

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 180)),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F172A),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final dayStr = picked.day.toString().padLeft(2, '0');
      final monthStr = picked.month.toString().padLeft(2, '0');
      setState(() {
        _expiryDateCtrl.text = '$dayStr/$monthStr/${picked.year}';
      });
      final now = DateTime.now();
      if (picked.isBefore(DateTime(now.year, now.month, now.day))) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          InAppNotification.show(
            context: context,
            message: '⚠️ Warning: Selected expiry date is in the past (Expired)!',
            type: NotificationType.warning,
          );
        }
      }
    }
  }

  bool get _isCurrentExpiryExpired {
    final raw = _expiryDateCtrl.text.trim();
    if (raw.isEmpty) return false;
    DateTime? exp = DateTime.tryParse(raw);
    if (exp == null && raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]);
        var y = int.tryParse(parts[1]);
        if (m != null && y != null) {
          if (y < 100) y += 2000;
          exp = DateTime(y, m, 28);
        }
      } else if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          exp = DateTime(y, m, d);
        }
      }
    }
    if (exp == null) return false;
    final now = DateTime.now();
    return exp.isBefore(DateTime(now.year, now.month, now.day));
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
      await _lookupAndAutofillBarcode(scanned);
    }
  }

  Future<void> _lookupAndAutofillBarcode(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return;

    setState(() => _isResolvingBarcode = true);
    try {
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;

      // 0. Check if this product already exists in merchant's own store database
      final existingStoreItem = await LocalDatabase.instance.findProductByBarcode(barcode, businessType: activeType);
      if (existingStoreItem != null && mounted) {
        setState(() {
          _nameCtrl.text = existingStoreItem.name;
          if (existingStoreItem.mrpPaise > 0) {
            _mrpCtrl.text = (existingStoreItem.mrpPaise / 100).toStringAsFixed(2);
          }
          if (existingStoreItem.sellingPricePaise > 0) {
            _sellPriceCtrl.text = (existingStoreItem.sellingPricePaise / 100).toStringAsFixed(2);
          }
          if (existingStoreItem.purchasePricePaise > 0) {
            _costPriceCtrl.text = (existingStoreItem.purchasePricePaise / 100).toStringAsFixed(2);
          }
          _autofillUnit(existingStoreItem.unit);
          if (existingStoreItem.categoryId != null && existingStoreItem.categoryId!.isNotEmpty) {
            if (_localCategories.any((c) => c.id == existingStoreItem.categoryId)) {
              _selectedCategoryId = existingStoreItem.categoryId!;
            }
          }
          _autofillTaxRate(existingStoreItem.taxRate);
          _isStockExpanded = true;
        });
        if (mounted) {
          InAppNotification.success(
            'Loaded from Store: ${existingStoreItem.name} (${existingStoreItem.unit})',
            context: context,
          );
        }
        return;
      }

      // 1. Check Master Catalog for instant autofill (<2ms)
      final master = await LocalDatabase.instance.findMasterProductByBarcode(
        barcode,
        businessType: activeType,
      );
      if (master != null && mounted) {
        await _applyMasterData(master, source: 'Master Catalog');
        return;
      }

      // 2. Cloud Fallback: Query Online Barcode Database (Open Food Facts / GS1)
      final cloudItem = await CloudBarcodeResolverService.instance.resolveBarcode(
        barcode,
        businessType: activeType,
      );
      if (cloudItem != null && mounted) {
        await _applyMasterData(cloudItem, source: 'Indian Barcode Cloud');
        return;
      }

      if (mounted) {
        InAppNotification.info(
          'New barcode: $barcode. Please enter name and unit.',
          context: context,
        );
        _nameFocusNode.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _isResolvingBarcode = false);
    }
  }

  Future<void> _applyMasterData(MasterProductModel master, {required String source}) async {
    setState(() {
      _nameCtrl.text = master.name;
      if (master.mrpPaise > 0) {
        _mrpCtrl.text = (master.mrpPaise / 100).toStringAsFixed(0);
      }
      final sPrice = master.sellingPricePaise > 0 ? master.sellingPricePaise : master.mrpPaise;
      if (sPrice > 0) {
        _sellPriceCtrl.text = (sPrice / 100).toStringAsFixed(0);
      }
      _autofillUnit(master.unit);
      _autofillCategory(master.category);
      _autofillTaxRate(master.taxRate);
      _isStockExpanded = true;
    });

    if (mounted) {
      InAppNotification.show(
        context: context,
        message: 'Auto-filled ($source): ${master.name} • Unit: ${_selectedUnit.toUpperCase()}',
        customIcon: source == 'Master Catalog' ? Icons.bolt_rounded : Icons.cloud_done_rounded,
        customColor: source == 'Master Catalog' ? Colors.amber : Colors.cyanAccent,
      );
    }
  }

  void _autofillUnit(String unitRaw) {
    if (unitRaw.trim().isEmpty) return;
    final clean = unitRaw.trim().toLowerCase();
    final match = _units.firstWhere(
      (u) => (u['val'] ?? '').toLowerCase() == clean,
      orElse: () => {},
    );
    if (match.isNotEmpty) {
      _selectedUnit = match['val']!;
    } else {
      final customLabel = BusinessVerticals.unitDisplayLabels[clean] ?? '${unitRaw.trim()} (${unitRaw.trim()})';
      _units.add({'label': customLabel, 'val': unitRaw.trim()});
      _selectedUnit = unitRaw.trim();
    }
  }

  void _autofillCategory(String catRaw) {
    if (catRaw.trim().isEmpty || catRaw.trim().toLowerCase() == 'general') return;
    final clean = catRaw.trim();
    final match = _localCategories.firstWhere(
      (c) => c.name.trim().toLowerCase() == clean.toLowerCase(),
      orElse: () => CategoryModel(id: '', businessId: '', name: ''),
    );
    if (match.id.isNotEmpty) {
      _selectedCategoryId = match.id;
    } else {
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      final newCat = CategoryModel(
        id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
        businessId: _localCategories.isNotEmpty ? _localCategories.first.businessId : 'biz_default',
        name: clean,
        businessType: activeType,
      );
      _localCategories.add(newCat);
      _selectedCategoryId = newCat.id;
      LocalDatabase.instance.upsertCategory(newCat);
    }
  }

  void _autofillTaxRate(double rate) {
    if (rate <= 0) return;
    final matchTax = _taxRates.firstWhere(
      (t) => ((t['val'] as num).toDouble() - rate).abs() < 0.01,
      orElse: () => {},
    );
    if (matchTax.isNotEmpty) {
      _selectedTaxRate = (matchTax['val'] as num).toDouble();
    } else {
      _taxRates.add({'label': '$rate% GST', 'val': rate});
      _selectedTaxRate = rate;
    }
  }

  void _showAddCategoryDialog() {
    final catCtrl = TextEditingController();
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Add Category', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick category suggestion chips
                Text('Quick suggestions:', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: vert.quickCategories.map((cat) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => catCtrl.text = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(cat, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: catCtrl,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Or type custom category name...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
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
                    businessType: BusinessVerticals.activeBusinessTypeNotifier.value,
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
      ),
    );
  }

  Future<void> _saveProduct({bool continueAddingNext = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final sellPaise = ((double.tryParse(_sellPriceCtrl.text.trim()) ?? 0.0) * 100).round();
      final mrpPaise = ((double.tryParse(_mrpCtrl.text.trim()) ?? (sellPaise / 100.0)) * 100).round();
      final costPaise = ((double.tryParse(_costPriceCtrl.text.trim()) ?? 0.0) * 100).round();
      final stockQty = _isUnlimitedStock ? 999999.0 : (double.tryParse(_stockCtrl.text.trim()) ?? 0.0);

      final shouldCreateVariants = widget.existingProduct == null &&
          widget.parentIdForNewVariant == null &&
          _enableVariants &&
          _selectedVariants.isNotEmpty;

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
        batchNumber: _batchNumberCtrl.text.trim().isNotEmpty ? _batchNumberCtrl.text.trim() : widget.existingProduct?.batchNumber,
        expiryDate: _expiryDateCtrl.text.trim().isNotEmpty ? _expiryDateCtrl.text.trim() : widget.existingProduct?.expiryDate,
        size: _sizeCtrl.text.trim().isNotEmpty ? _sizeCtrl.text.trim() : widget.existingProduct?.size,
        color: _colorCtrl.text.trim().isNotEmpty ? _colorCtrl.text.trim() : widget.existingProduct?.color,
        fitNotes: _fitNotesCtrl.text.trim().isNotEmpty ? _fitNotesCtrl.text.trim() : widget.existingProduct?.fitNotes,
        imeiSerial: _imeiCtrl.text.trim().isNotEmpty ? _imeiCtrl.text.trim() : widget.existingProduct?.imeiSerial,
        isFavorite: _isFavorite,
        syncStatus: 'synced',
        businessType: widget.existingProduct?.businessType ?? BusinessVerticals.activeBusinessTypeNotifier.value,
        subUnitsPerPack: _selectedUnit == 'strip' && _subUnitsPerPackCtrl.text.trim().isNotEmpty
            ? int.tryParse(_subUnitsPerPackCtrl.text.trim())
            : (_selectedUnit == 'strip' ? widget.existingProduct?.subUnitsPerPack : null),
        parentId: widget.parentIdForNewVariant ?? widget.existingProduct?.parentId,
        hasVariants: shouldCreateVariants ? true : (widget.existingProduct?.hasVariants ?? false),
        variantLabel: widget.parentIdForNewVariant != null
            ? (_sizeCtrl.text.trim().isNotEmpty ? _sizeCtrl.text.trim() : null)
            : widget.existingProduct?.variantLabel,
      );

      if (shouldCreateVariants) {
        final customVariants = _selectedVariants.map((label) {
          final cfg = _variantConfigs[label];
          final pSellPaise = cfg != null && cfg.priceCtrl.text.trim().isNotEmpty
              ? ((double.tryParse(cfg.priceCtrl.text.trim()) ?? 0.0) * 100).round()
              : sellPaise;
          final pMrpPaise = cfg != null && cfg.mrpCtrl.text.trim().isNotEmpty
              ? ((double.tryParse(cfg.mrpCtrl.text.trim()) ?? 0.0) * 100).round()
              : (mrpPaise > 0 ? mrpPaise : pSellPaise);
          final pStock = cfg != null && cfg.stockCtrl.text.trim().isNotEmpty
              ? (double.tryParse(cfg.stockCtrl.text.trim()) ?? stockQty)
              : stockQty;

          return VariantCustomData(
            label: label,
            sellingPricePaise: pSellPaise,
            mrpPaise: pMrpPaise,
            purchasePricePaise: costPaise,
            stockQuantity: pStock,
          );
        }).toList();

        final variants = await LocalDatabase.instance.createProductWithVariants(
          parentProduct: p,
          customVariants: customVariants,
        );
        for (final v in variants) {
          FirestoreSyncService.instance.pushProductToCloud(v).catchError((_) {});
        }
        FirestoreSyncService.instance.pushProductToCloud(p).catchError((_) {});
      } else {
        await LocalDatabase.instance.upsertProduct(p);
        if (p.barcode != null && p.barcode!.isNotEmpty) {
          try {
            final catName = _localCategories.firstWhere(
              (c) => c.id == p.categoryId,
              orElse: () => CategoryModel(id: '', businessId: '', name: 'General'),
            ).name;
            await LocalDatabase.instance.insertMasterProduct(MasterProductModel(
              barcode: p.barcode!,
              name: p.name,
              category: catName,
              unit: p.unit,
              mrpPaise: p.mrpPaise,
              sellingPricePaise: p.sellingPricePaise,
              taxRate: p.taxRate,
              businessType: p.businessType,
            ));
          } catch (_) {}
        }
        FirestoreSyncService.instance.pushProductToCloud(p).catchError((_) {});
      }

      if (!mounted) return;

      if (continueAddingNext) {
        widget.onSaved();
        InAppNotification.success(
          'Saved "${p.name}". Scanning next barcode...',
          context: context,
        );
        setState(() {
          _nameCtrl.clear();
          _barcodeCtrl.clear();
          _sellPriceCtrl.clear();
          _mrpCtrl.clear();
          _costPriceCtrl.clear();
          _stockCtrl.text = '10';
          _isFavorite = false;
        });
        _openBarcodeScanner();
        return;
      }

      Navigator.of(context).pop();
      widget.onSaved();

      InAppNotification.success(
        widget.existingProduct != null
            ? 'Product updated successfully!'
            : 'New product added to catalog!',
        context: context,
      );
    } catch (e) {
      InAppNotification.error('Failed to save product: $e', context: context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingProduct != null;
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);

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
                        isEditing
                            ? 'Edit ${vert.bottomNavLabel} Item'
                            : 'Add New ${vert.bottomNavLabel} Item',
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
                  vert.id == 'restaurant'
                      ? 'Enter dish name, category, selling price, and food GST tax.'
                      : 'Enter product details, barcode, selling price, and initial stock.',
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


                      // 1. Dynamic Item Name *
                      _buildLabel(vert.itemFieldLabel),
                      const SizedBox(height: 5),
                      TextFormField(
                        controller: _nameCtrl,
                        focusNode: _nameFocusNode,
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
                        decoration: _buildInputDecoration(
                          BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).placeholders.newProductName,
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: _isFavorite ? 'Remove from Favorite' : 'Mark as Favorite (Top in Billing)',
                            icon: Icon(
                              _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                              color: _isFavorite ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                              size: 22,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _isFavorite = !_isFavorite);
                            },
                          ),
                        ),
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

                      // Tablets/pieces per strip — only when the unit is actually
                      // "strip". Real strips are 10, 15, 20 or 30 tablets, never
                      // a fixed number, so billing can't sell "3 tablets"
                      // correctly without knowing this. Left blank, quantity
                      // entry falls back to whole/half-strip only.
                      if (_selectedUnit == 'strip') ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Tablets per Strip'),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _subUnitsPerPackCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                              decoration: _buildInputDecoration('e.g. 10, 15, 20').copyWith(
                                helperText: 'Lets billing sell an exact tablet count, not just a whole or half strip',
                                helperMaxLines: 2,
                                helperStyle: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

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

                      // Batch Number & Expiry Date (Pharmacy Only)
                      if (vert.toggles.showBatchExpiry) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Batch Number'),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: _batchNumberCtrl,
                                    style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                    decoration: _buildInputDecoration('e.g. BATCH-2026-X'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Expiry Date'),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: _pickExpiryDate,
                                    borderRadius: BorderRadius.circular(12),
                                    child: IgnorePointer(
                                      child: TextFormField(
                                        controller: _expiryDateCtrl,
                                        style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                        decoration: _buildInputDecoration('MM/YYYY').copyWith(
                                          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF64748B)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_isCurrentExpiryExpired) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFFCA5A5)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFDC2626)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'EXPIRED PRODUCT',
                                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 4. Barcode / EAN-13 (hidden for restaurant)
                      // 4. Barcode / EAN-13 with Unified In-Field Scan & Auto-Fill
                      if (vert.toggles.showBarcode) ...[
                        _buildLabel('Barcode / EAN-13'),
                        const SizedBox(height: 5),
                        TextFormField(
                          controller: _barcodeCtrl,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.robotoMono(fontSize: 13.5, fontWeight: FontWeight.w700),
                          textInputAction: TextInputAction.search,
                          onFieldSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              _lookupAndAutofillBarcode(val.trim());
                            }
                          },
                          decoration: _buildInputDecoration('e.g. 8901030383748').copyWith(
                            suffixIcon: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Scan Camera Button within field
                                  InkWell(
                                    onTap: _openBarcodeScanner,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.qr_code_scanner_rounded, size: 14, color: Color(0xFF0F172A)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Scan',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Auto-fill Button within field
                                  InkWell(
                                    onTap: _isResolvingBarcode
                                        ? null
                                        : () {
                                            if (_barcodeCtrl.text.trim().isNotEmpty) {
                                              _lookupAndAutofillBarcode(_barcodeCtrl.text.trim());
                                            }
                                          },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F9FF),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFBAE6FD)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isResolvingBarcode) ...[
                                            const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF0284C7),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Finding...',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF0284C7),
                                              ),
                                            ),
                                          ] else ...[
                                            const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF0284C7)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Auto-fill',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF0284C7),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],



                      // Variant Matrix Generator (Sizes / Colors)
                      if (widget.existingProduct == null && widget.parentIdForNewVariant == null) ...[
                        _buildVariantMatrixSection(),
                        const SizedBox(height: 12),
                      ],

                      // Row 6: IMEI / Serial + Warranty (Hardware/Electrical only)
                      if (vert.toggles.showImeiWarranty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('IMEI / Serial No.'),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: _imeiCtrl,
                                    style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.w600),
                                    decoration: _buildInputDecoration('e.g. SN-20240701-X'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Warranty (Months)'),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: _warrantyCtrl,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                    decoration: _buildInputDecoration('e.g. 12, 24'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 5. Stock & Inventory Card (Collapsible Accordion - Solved Issue 10)
                      Container(
                        decoration: BoxDecoration(
                          color: _isStockExpanded
                              ? (_isUnlimitedStock ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC))
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isStockExpanded
                                ? (_isUnlimitedStock ? const Color(0xFFBBF7D0) : const Color(0xFFCBD5E1))
                                : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Accordion Header (Tappable)
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _isStockExpanded = !_isStockExpanded);
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: _isUnlimitedStock ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            _isUnlimitedStock ? Icons.all_inclusive_rounded : Icons.inventory_2_outlined,
                                            size: 16,
                                            color: _isUnlimitedStock ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Stock & Inventory',
                                              style: GoogleFonts.outfit(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF0F172A),
                                              ),
                                            ),
                                            Text(
                                              _isUnlimitedStock
                                                  ? 'Unlimited (No tracking)'
                                                  : 'Available: ${_stockCtrl.text.isEmpty ? "0" : _stockCtrl.text} • Alert: ${_thresholdCtrl.text}',
                                              style: GoogleFonts.inter(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                                color: _isUnlimitedStock ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            _isStockExpanded ? 'Collapse' : 'Expand',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          _isStockExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                          color: const Color(0xFF64748B),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Accordion Content Body
                            if (_isStockExpanded) ...[
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Inline Unlimited Toggle
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Unlimited Stock (No Count Limit)',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: _isUnlimitedStock ? const Color(0xFF16A34A) : const Color(0xFF334155),
                                          ),
                                        ),
                                        Transform.scale(
                                          scale: 0.8,
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
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
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
                                                  // Decimal — a loose item priced per kg (kaju,
                                                  // badam, atta) needs an opening stock like
                                                  // 0.25 or 1.5, not just whole numbers.
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700),
                                                  decoration: _buildInputDecoration('e.g. 25'),
                                                  onChanged: (_) => setState(() {}),
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
                                                  onChanged: (_) => setState(() {}),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                          const SizedBox(height: 8),
                                          // Unit-aware quick fill — same config used by the
                                          // POS billing cart-item editor and the Products
                                          // screen's stock-update modal, so a kg-priced
                                          // loose item sees gram chips here too, not just
                                          // after it's already been saved once.
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: _quantityConfig.chips.map((chip) {
                                              final chipValStr = chip.value % 1 == 0
                                                  ? chip.value.toInt().toString()
                                                  : chip.value.toString();
                                              final isSelected = _stockCtrl.text == chipValStr;
                                              return InkWell(
                                                onTap: () {
                                                  HapticFeedback.selectionClick();
                                                  setState(() => _stockCtrl.text = chipValStr);
                                                },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: isSelected ? const Color(0xFFFBBF24) : const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    chip.label,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 11.5,
                                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                                      color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Bottom Action Buttons: Cancel, Save & Next, and Save Product
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          if (!isEditing) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: OutlinedButton.icon(
                                onPressed: _isSaving ? null : () => _saveProduct(continueAddingNext: true),
                                icon: const Icon(Icons.flash_on_rounded, size: 16, color: Color(0xFFD97706)),
                                label: Text(
                                  'Save & Next',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFD97706),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFFBEB),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: const BorderSide(color: Color(0xFFFDE68A), width: 1.2),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : () => _saveProduct(continueAddingNext: false),
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
                                      isEditing ? 'Update' : 'Save',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
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

  Widget _buildVariantMatrixSection() {
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);

    // Business vertical-specific presets and matrix configuration
    final List<String> presets;
    final String matrixTitle;
    final String matrixSubtitle;
    final String hintText;

    switch (vert.id) {
      case 'grocery':
        matrixTitle = 'Variants Matrix (Weight / Pack)';
        matrixSubtitle = 'Create weight or pack variants (e.g. 500g, 1kg, 5kg)';
        hintText = 'Custom variant (e.g. 250g, 2kg, Combo)...';
        presets = ['100g', '250g', '500g', '1kg', '2kg', '5kg', '10kg', '500ml', '1 Litre', 'Pack of 2', 'Pack of 4', 'Combo'];
        break;
      case 'pharmacy':
        matrixTitle = 'Variants Matrix (Dosage / Pack)';
        matrixSubtitle = 'Create dosage or pack variants (e.g. 500mg, Strip of 10)';
        hintText = 'Custom variant (e.g. Strip 15, 650mg, 100ml)...';
        presets = ['Strip (10 Tab)', 'Strip (15 Tab)', 'Bottle (60ml)', 'Bottle (100ml)', '100mg', '250mg', '500mg', '650mg', 'Sachet', 'Box of 10'];
        break;
      case 'hardware':
        matrixTitle = 'Variants Matrix (Size / Dimension)';
        matrixSubtitle = 'Create dimension or volume variants (e.g. 1/2 Inch, 1 Litre)';
        hintText = 'Custom variant (e.g. 1.5 Inch, 10 Litre)...';
        presets = ['1/2 Inch', '3/4 Inch', '1 Inch', '1.5 Inch', '2 Inch', '50mm', '100mm', '500ml', '1 Ltr', '4 Ltr', '10 Ltr', '20 Ltr'];
        break;
      case 'restaurant':
        matrixTitle = 'Variants Matrix (Portion / Serving)';
        matrixSubtitle = 'Create portion or serving variants (e.g. Half, Full, Large)';
        hintText = 'Custom variant (e.g. Medium, Spicy, Jain)...';
        presets = ['Regular', 'Medium', 'Large', 'Half', 'Full', 'Single', 'Double', 'Jain', 'Spicy', 'Combo'];
        break;
      case 'clothing':
      default:
        matrixTitle = 'Variants Matrix (Size / Color)';
        matrixSubtitle = 'Create multiple sizes or colors under this item';
        hintText = 'Custom variant (e.g. 36, Red-XL)...';
        presets = [
          'S', 'M', 'L', 'XL', 'XXL', '3XL',
          '28', '30', '32', '34', '36', '38', '40', '42',
          'Red', 'Blue', 'Black', 'White', 'Green', 'Yellow', 'Grey', 'Navy'
        ];
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: _enableVariants ? const Color(0xFFFAF5FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _enableVariants ? const Color(0xFFD8B4FE) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.style_rounded, size: 16, color: Color(0xFF7E22CE)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        matrixTitle,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        matrixSubtitle,
                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _enableVariants,
                  activeThumbColor: const Color(0xFF7E22CE),
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    setState(() => _enableVariants = val);
                  },
                ),
              ],
            ),
          ),
          if (_enableVariants) ...[
            const Divider(height: 1, color: Color(0xFFE9D5FF)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Presets (Tap to Add):',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presets.map((s) => _buildPresetChip(s)).toList(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _customVariantCtrl,
                            style: GoogleFonts.inter(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: hintText,
                              hintStyle: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () {
                          final text = _customVariantCtrl.text.trim();
                          if (text.isNotEmpty) {
                            setState(() {
                              _addVariant(text);
                              _customVariantCtrl.clear();
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7E22CE),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (_selectedVariants.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Selected Variants (${_selectedVariants.length}):',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF7E22CE)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedVariants.map((label) {
                        return Chip(
                          label: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF7E22CE))),
                          backgroundColor: const Color(0xFFF3E8FF),
                          deleteIconColor: const Color(0xFF7E22CE),
                          onDeleted: () {
                            setState(() => _removeVariant(label));
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFD8B4FE)),
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Variant Pricing & Stock:',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF7E22CE)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Set individual selling price and stock for each variant:',
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    ..._selectedVariants.map((label) {
                      final cfg = _variantConfigs.putIfAbsent(
                        label,
                        () => _VariantInputData(
                          defaultPrice: _sellPriceCtrl.text,
                          defaultMrp: _mrpCtrl.text,
                          defaultStock: _isUnlimitedStock ? '999999' : (_stockCtrl.text.isNotEmpty ? _stockCtrl.text : '10'),
                        ),
                      );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE9D5FF), width: 1.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3E8FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    label,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF7E22CE),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() => _removeVariant(label));
                                  },
                                  child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Selling Price (₹)', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                      const SizedBox(height: 3),
                                      SizedBox(
                                        height: 36,
                                        child: TextFormField(
                                          controller: cfg.priceCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.w700),
                                          decoration: _buildInputDecoration('₹0.00').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('MRP (₹)', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                      const SizedBox(height: 3),
                                      SizedBox(
                                        height: 36,
                                        child: TextFormField(
                                          controller: cfg.mrpCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.w700),
                                          decoration: _buildInputDecoration('MRP').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Stock Qty', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                                      const SizedBox(height: 3),
                                      SizedBox(
                                        height: 36,
                                        child: TextFormField(
                                          controller: cfg.stockCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.w700),
                                          decoration: _buildInputDecoration('Qty').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label) {
    final isSelected = _selectedVariants.contains(label);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (isSelected) {
            _removeVariant(label);
          } else {
            _addVariant(label);
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7E22CE) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF7E22CE) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
