import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/state/app_data_bus.dart';
import '../../core/state/data_bus_refresh.dart';
import '../../models/models.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/expiry_utils.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/home_widget_service.dart';
import '../../services/cloud_barcode_resolver_service.dart';
import '../common/in_app_notification.dart';
import '../common/pro_upgrade_modal.dart';
import 'pos_checkout_modal.dart';
import 'barcode_scanner_view.dart';

class PosBillingScreen extends StatefulWidget {
  final bool autoOpenCheckout;
  final bool autoOpenCustomerDropdown;
  final bool autoOpenSplit;

  const PosBillingScreen({
    super.key,
    this.autoOpenCheckout = false,
    this.autoOpenCustomerDropdown = false,
    this.autoOpenSplit = false,
  });

  @override
  State<PosBillingScreen> createState() => _PosBillingScreenState();
}

class PosBillingSessionStore {
  static List<CartTab>? savedTabs;
  static int activeTabIndex = 0;
}

class _PosBillingScreenState extends State<PosBillingScreen>
    with DataBusRefresh<PosBillingScreen>, AutomaticKeepAliveClientMixin<PosBillingScreen> {
  @override
  bool get wantKeepAlive => true;
  // A price or stock edit made on the Products tab must reach the billing grid,
  // otherwise the cashier rings up a stale price and the out-of-stock guard
  // works off stock loaded at startup.
  @override
  List<ValueNotifier<int>> get dataBusSignals => [
        AppDataBus.instance.productsRevision,
        AppDataBus.instance.customersRevision,
      ];

  @override
  void onDataBusChanged() => _loadData();

  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  List<ProductModel> _allProducts = [];
  List<CategoryModel> _categories = [];
  List<CustomerModel> _customers = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryId; // null = 'all'
  bool _isLoading = true;
  String _restaurantOrderType = 'Dine-In';

  // Master Catalog Search Results (<2ms offline lookup)
  List<MasterProductModel> _matchingMasterProducts = [];
  bool _isSearchingMaster = false;

  // Multi-cart Hold & Resume system
  late List<CartTab> _tabs;
  int _activeTabIndex = 0;
  bool _isPro = false;

  // POS Catalog Filter Mode: 'all', 'in_stock', 'favorites'
  String _posFilterMode = 'all';

  int get _inStockCount => _allProducts.where((p) => !p.isVariant && (p.isUnlimitedStock || p.stockQuantity > 0)).length;
  int get _favoritesCount => _allProducts.where((p) => !p.isVariant && p.isFavorite).length;
  int get _totalCatalogCount => _allProducts.where((p) => !p.isVariant).length;

  @override
  void initState() {
    super.initState();
    if (PosBillingSessionStore.savedTabs != null && PosBillingSessionStore.savedTabs!.isNotEmpty) {
      _tabs = PosBillingSessionStore.savedTabs!;
      _activeTabIndex = PosBillingSessionStore.activeTabIndex;
      if (_activeTabIndex >= _tabs.length) _activeTabIndex = 0;
    } else {
      _tabs = [
        CartTab(id: 'tab_1', name: 'Bill #1', number: 1, items: {}),
      ];
      PosBillingSessionStore.savedTabs = _tabs;
      PosBillingSessionStore.activeTabIndex = 0;
    }
    _loadBusinessType();
    BusinessVerticals.activeBusinessTypeNotifier.addListener(_onBusinessTypeChanged);
    FirestoreSyncService.instance.liveSyncCounter.addListener(_handleCloudSyncUpdate);
    FirestoreSyncService.isProNotifier.addListener(_handleProStatusUpdate);
    HardwareKeyboard.instance.addHandler(_handleHardwareBarcodeScan);
  }

  // Hardware USB/OTG Barcode Scanner Gun Buffer
  final StringBuffer _hardwareBarcodeBuffer = StringBuffer();
  DateTime _lastHardwareKeyTime = DateTime.now();

  bool _handleHardwareBarcodeScan(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Enter indicates end of barcode transmission from scanner gun
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_hardwareBarcodeBuffer.isNotEmpty && _hardwareBarcodeBuffer.length >= 3) {
        final scanned = _hardwareBarcodeBuffer.toString().trim();
        _hardwareBarcodeBuffer.clear();
        _processHardwareScannedBarcode(scanned);
        return true;
      }
      _hardwareBarcodeBuffer.clear();
      return false;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
      final now = DateTime.now();
      // Scanners type at blazing speeds (<70ms per char). If user took >800ms between keys, reset buffer
      if (now.difference(_lastHardwareKeyTime).inMilliseconds > 800) {
        _hardwareBarcodeBuffer.clear();
      }
      _lastHardwareKeyTime = now;
      _hardwareBarcodeBuffer.write(char);
      return false;
    }
    return false;
  }

  Future<void> _processHardwareScannedBarcode(String barcode) async {
    HapticFeedback.mediumImpact();
    // 1. Search in loaded active store products
    ProductModel? match;
    for (final p in _allProducts) {
      if (p.barcode != null && p.barcode!.trim() == barcode) {
        match = p;
        break;
      }
    }

    // 2. If not in memory, query SQLite
    if (match == null) {
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      match = await LocalDatabase.instance.findProductByBarcode(barcode, businessType: activeType);
    }

    if (match != null) {
      _addToCart(match);
      if (mounted) {
        InAppNotification.show(
          context: context,
          message: '🔫 Scanned: ${match.name}',
          customIcon: Icons.qr_code_scanner_rounded,
          customColor: const Color(0xFF10B981),
          duration: const Duration(milliseconds: 1400),
        );
      }
      return;
    }

    // 3. Check master catalog or cloud resolver
    try {
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      final master = await LocalDatabase.instance.findMasterProductByBarcode(barcode, businessType: activeType);
      if (master != null) {
        await _importAndAddToCart(master);
        return;
      }
      final cloudItem = await CloudBarcodeResolverService.instance.resolveBarcode(barcode, businessType: activeType);
      if (cloudItem != null) {
        await _importAndAddToCart(cloudItem);
        return;
      }
    } catch (_) {}

    if (mounted) {
      InAppNotification.error('Barcode "$barcode" not found in store catalog', context: context);
    }
  }

  Future<void> _loadBusinessType() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() => _isPro = profile.isPro);
      }
      if (profile.businessType.isNotEmpty) {
        BusinessVerticals.updateActiveBusinessType(profile.businessType);
      }
    } catch (_) {}
    _loadData();
  }

  void _handleProStatusUpdate() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _isPro = profile.isPro);
    } catch (_) {}
  }

  void _onBusinessTypeChanged() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareBarcodeScan);
    BusinessVerticals.activeBusinessTypeNotifier.removeListener(_onBusinessTypeChanged);
    FirestoreSyncService.instance.liveSyncCounter.removeListener(_handleCloudSyncUpdate);
    FirestoreSyncService.isProNotifier.removeListener(_handleProStatusUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _handleCloudSyncUpdate() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
    final prods = await LocalDatabase.instance.getAllProducts(businessType: activeType);
    final cats = await LocalDatabase.instance.getAllCategories(businessType: activeType);
    final custs = await LocalDatabase.instance.getAllCustomers();

    if (mounted) {
      setState(() {
        _allProducts = prods;
        _categories = cats;
        _customers = custs;
        _isLoading = false;
      });

      if (widget.autoOpenCheckout && prods.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _cart.isEmpty) {
            _addToCart(prods.first);
            if (prods.length > 1) {
              _addToCart(prods[1]);
            }
            _openCheckoutModal();
          }
        });
      }
    }
  }

  CartTab get currentTab => _tabs[_activeTabIndex];
  Map<String, CartItemModel> get _cart => currentTab.items;

  List<ProductModel> get filteredProducts {
    final list = _allProducts.where((p) {
      // 1. Hide child variants from main POS grid so catalog is clean
      if (p.isVariant) return false;

      // 2. POS Filter Mode (Issue 10)
      if (_posFilterMode == 'in_stock') {
        final isInStock = p.isUnlimitedStock || p.stockQuantity > 0;
        if (!isInStock) return false;
      } else if (_posFilterMode == 'favorites') {
        if (!p.isFavorite) return false;
      }

      // 3. Search filter: matches parent or any child variant
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matchesSelf = p.name.toLowerCase().contains(q) ||
            (p.barcode != null && p.barcode!.contains(q));
        final matchesVariant = p.hasVariants &&
            _allProducts.any((v) => v.parentId == p.id && (v.name.toLowerCase().contains(q) || (v.barcode != null && v.barcode!.contains(q))));
        if (!matchesSelf && !matchesVariant) return false;
      }

      // 4. Category filter
      final matchesCat = _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
      return matchesCat;
    }).toList();
    list.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Real-time dual search: local store products + background master catalog (<2ms)
  Future<void> _performSearch(String val) async {
    setState(() => _searchQuery = val);
    final clean = val.trim();
    if (clean.length >= 2) {
      setState(() => _isSearchingMaster = true);
      try {
        final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
        final results = await LocalDatabase.instance.searchMasterCatalog(
          clean,
          businessType: activeType,
          limit: 15,
        );
        final storeBarcodes = _allProducts.map((p) => p.barcode).whereType<String>().toSet();
        final storeNames = _allProducts.map((p) => p.name.toLowerCase().trim()).toSet();
        final nonDuplicates = results.where((m) {
          final barMatch = m.barcode.isNotEmpty && storeBarcodes.contains(m.barcode);
          final nameMatch = storeNames.contains(m.name.toLowerCase().trim());
          return !barMatch && !nameMatch;
        }).toList();

        if (mounted && _searchQuery.trim() == clean) {
          setState(() {
            _matchingMasterProducts = nonDuplicates;
            _isSearchingMaster = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingMaster = false);
      }
    } else {
      if (_matchingMasterProducts.isNotEmpty || _isSearchingMaster) {
        setState(() {
          _matchingMasterProducts = [];
          _isSearchingMaster = false;
        });
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _matchingMasterProducts = [];
      _isSearchingMaster = false;
    });
  }

  /// Single funnel for "scanned barcode resolved to something not yet in this
  /// store's catalog → create it and drop it in the bill".
  ///
  /// Two things here are load-bearing and were previously missing:
  ///
  /// 1. **Price guard.** Online barcode repositories (Open Food Facts,
  ///    UPCitemdb, ...) carry no Indian MRP, so a cloud-resolved item arrives
  ///    with `sellingPricePaise == 0`. The old code imported it as-is and
  ///    cheerfully announced "Added to Bill" — the cashier scanned, saw a
  ///    green toast, and billed the item at **₹0**. The shop silently ate the
  ///    whole sale. Now a zero-priced item stops and asks for the rate first.
  /// 2. **Vertical tag.** Importing without `targetVertical` tagged the new
  ///    product with whatever vertical the resolver guessed, so a pharmacy
  ///    could bill an item that then never appeared in its own catalog
  ///    (`getAllProducts` filters on that column). The other call site
  ///    already passed it; this one did not.
  Future<void> _importAndAddToCart(MasterProductModel masterItem, {String? sourceLabel}) async {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;

    int? priceOverride;
    if (masterItem.sellingPricePaise <= 0 && masterItem.mrpPaise <= 0) {
      priceOverride = await _promptSellingPriceForNewScan(masterItem);
      if (priceOverride == null) return; // Cashier cancelled — bill nothing.
      if (!mounted) return;
    }

    final imported = await LocalDatabase.instance.importMasterProductToStore(
      masterItem,
      targetVertical: activeType,
      customSellingPricePaise: priceOverride,
    );
    _addToCart(imported);
    await _loadData();
    if (mounted) {
      InAppNotification.show(
        context: context,
        message: '${sourceLabel ?? 'Added to Bill'}: ${imported.name}',
        customIcon: Icons.auto_awesome,
        customColor: Colors.amber,
        duration: const Duration(milliseconds: 1200),
      );
    }
  }

  /// Asks the cashier for a selling price for a barcode that resolved online
  /// but has no price attached. Returns paise, or null if cancelled.
  Future<int?> _promptSellingPriceForNewScan(MasterProductModel item) async {
    final priceCtrl = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.sell_rounded, color: Color(0xFF059669), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Set Selling Price',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            Text(
              'Found online, but no Indian MRP is available for this barcode. '
              'Enter the rate you sell it at — it will be saved to your catalog.',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: priceCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.robotoMono(fontSize: 20, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '0.00',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (v) {
                final p = MoneyFormatter.parseRupeesToPaise(v);
                if (p > 0) Navigator.pop(ctx, p);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              final p = MoneyFormatter.parseRupeesToPaise(priceCtrl.text);
              if (p <= 0) return;
              Navigator.pop(ctx, p);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Add to Bill', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    priceCtrl.dispose();
    return result;
  }

  int get cartTotalPaise {
    int total = 0;
    for (var item in _cart.values) {
      total += item.grossTotalPaise;
    }
    return total;
  }

  int get cartTotalItemsCount {
    int count = 0;
    for (var item in _cart.values) {
      count += item.quantity.toInt();
    }
    return count;
  }

  int _getCategoryProductCount(String? catId) {
    if (catId == null) return _allProducts.length;
    return _allProducts.where((p) => p.categoryId == catId).length;
  }

  void _addToCart(ProductModel product) {
    if (product.hasVariants) {
      _showVariantPicker(product);
      return;
    }
    final exp = parseProductExpiry(product);
    if (exp != null && exp.isExpired) {
      _showExpiredWarningModal(product);
      return;
    }
    _addProductDirectlyToCart(product);
  }

  void _showExpiredWarningModal(ProductModel product) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
            const SizedBox(width: 8),
            Text('Expired Product!', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
          ],
        ),
        content: Text(
          '"${product.name}" has expired (${product.expiryDate ?? ''}). Do you still want to add this item to the bill?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addProductDirectlyToCart(product);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
  }

  void _showVariantPicker(ProductModel parent) async {
    HapticFeedback.mediumImpact();
    final variants = await LocalDatabase.instance.getVariantsForProduct(parent.id);
    if (!mounted) return;

    if (variants.isEmpty) {
      _addProductDirectlyToCart(parent);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.style_rounded, color: Color(0xFF4F46E5), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parent.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Select Variant (Size / Color) to Add',
                            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: variants.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final v = variants[i];
                      // Uses the single canonical sentinel from ProductModel.
                      // This line (and the two below) hardcoded 900000 while
                      // models.dart defines unlimited as >= 99990, and the
                      // master-catalog import writes exactly 99999 — so the
                      // same product read "∞ Unlimited" in one widget and
                      // "99999 pcs" in the next, with the out-of-stock guard
                      // disagreeing with its own badge.
                      final isOutOfStock = !v.isUnlimitedStock && v.stockQuantity <= 0;
                      final sizeText = (v.size != null && v.size!.isNotEmpty) ? v.size! : 'V${i + 1}';
                      return InkWell(
                        onTap: isOutOfStock
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _addProductDirectlyToCart(v);
                              },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isOutOfStock ? const Color(0xFFF8FAFC) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isOutOfStock ? const Color(0xFFE2E8F0) : const Color(0xFFC7D2FE),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isOutOfStock ? const Color(0xFFE2E8F0) : const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  sizeText,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isOutOfStock ? const Color(0xFF94A3B8) : const Color(0xFF4338CA),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.variantLabel ?? (v.color != null ? 'Color: ${v.color}' : v.name),
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isOutOfStock ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isOutOfStock ? 'Out of Stock' : 'Stock: ${v.stockQuantity.toInt()} units',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: isOutOfStock ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                MoneyFormatter.formatINR(v.sellingPricePaise),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF4F46E5)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _addProductDirectlyToCart(ProductModel product) {
    final currentQty = _cart[product.id]?.quantity.toInt() ?? 0;
    final isUnlimited = product.isUnlimitedStock;

    if (!isUnlimited && (product.stockQuantity <= 0 || currentQty >= product.stockQuantity)) {
      HapticFeedback.heavyImpact();
      InAppNotification.error(
        '"${product.name}" is Out of Stock! (Available: ${product.stockQuantity.toInt()})',
        context: context,
      );
      return;
    }

    // Subtle tactile mechanical "tick" feel on add to cart
    HapticFeedback.selectionClick();
    setState(() {
      if (_cart.containsKey(product.id)) {
        _cart[product.id]!.quantity += 1;
      } else {
        _cart[product.id] = CartItemModel(product: product, quantity: 1);
      }
    });
  }

  void _updateItemQuantity(CartItemModel item, int newQty) {
    HapticFeedback.selectionClick();
    setState(() {
      if (newQty <= 0) {
        _cart.remove(item.product.id);
      } else {
        item.quantity = newQty.toDouble();
      }
    });
  }

  void _removeItem(CartItemModel item) {
    HapticFeedback.lightImpact();
    setState(() {
      _cart.remove(item.product.id);
    });
  }

  void _clearCart() {
    HapticFeedback.mediumImpact();
    setState(() {
      _cart.clear();
      currentTab.customer = null;
    });
  }

  void _holdBillAndNew() {
    HapticFeedback.mediumImpact();
    // Strict Pro Lock: Free user limited to 3 simultaneous bills (4th is locked)
    if (!_isPro && _tabs.length >= 3) {
      HapticFeedback.heavyImpact();
      ProUpgradeModal.show(
        context,
        triggerFeature: 'Simultaneous Multi-Counter Billing (Free plan: max 3 parallel bills. Upgrade to Pro for unlimited parallel billing)',
      );
      return;
    }
    if (_tabs.length >= 10) {
      InAppNotification.info('Max 10 parallel bills supported', context: context);
      return;
    }
    setState(() {
      int maxNum = 0;
      for (final t in _tabs) {
        if (t.number > maxNum) maxNum = t.number;
      }
      final newNum = maxNum + 1;
      _tabs.add(CartTab(id: 'tab_$newNum', name: 'Bill #$newNum', number: newNum, items: {}));
      _activeTabIndex = _tabs.length - 1;
    });
    InAppNotification.info(
      'New Bill #${_tabs.last.number} created. Add items to cart.',
      context: context,
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _openCheckoutModal() {
    HapticFeedback.mediumImpact();
    PosCheckoutModal.show(
      context,
      cartItems: _cart.values.toList(),
      selectedCustomer: currentTab.customer,
      allCustomers: _customers,
      activeBillTitle: currentTab.name,
      activeBillTabNumber: currentTab.number,
      tabs: _tabs,
      activeTabIndex: _activeTabIndex,
      onSwitchTab: (newIndex) {
        setState(() {
          _activeTabIndex = newIndex;
        });
      },
      onAddNewBill: () {
        _holdBillAndNew();
      },
      onCloseTab: (idx) {
        _closeTab(idx);
      },
      onUpdateQuantity: _updateItemQuantity,
      onRemoveItem: _removeItem,
      onClearCart: _clearCart,
      onHoldBill: () {
        Navigator.of(context).pop();
        _holdBillAndNew();
      },
      onCustomerChanged: (cust) {
        setState(() {
          currentTab.customer = cust;
        });
      },
      onSaleCompleted: () {
        setState(() {
          if (_tabs.length > 1) {
            _tabs.removeAt(_activeTabIndex);
            if (_activeTabIndex >= _tabs.length) {
              _activeTabIndex = _tabs.length - 1;
            }
          } else {
            _cart.clear();
            currentTab.customer = null;
          }
        });
        _loadData(); // refresh stock numbers
        HomeWidgetService.instance.updateTodayMetrics();
      },
      autoOpenCustomerDropdown: widget.autoOpenCustomerDropdown,
      autoOpenSplit: widget.autoOpenSplit,
    );
  }

  Future<void> _openCameraBarcodeScanner() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerView()),
    );

    if (barcode != null && barcode.isNotEmpty && mounted) {
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      final matched = await LocalDatabase.instance.findProductByBarcode(barcode, businessType: activeType);
      if (matched != null) {
        _addToCart(matched);
        if (mounted) {
          InAppNotification.success(
            'Scanned: ${matched.name}',
            context: context,
          );
        }
      } else {
        // Fallback 1: Check Local Master Catalog (<2ms) with vertical filter
        final masterMatch = await LocalDatabase.instance.findMasterProductByBarcode(
          barcode,
          businessType: activeType,
        );
        if (masterMatch != null && mounted) {
          // Routed through _importAndAddToCart so the zero-price guard and
          // the active-vertical tag apply here too, exactly as they do on
          // the hardware-scanner path.
          await _importAndAddToCart(masterMatch, sourceLabel: 'Master SKU Added');
        } else {
          // Fallback 2: Cloud Barcode Resolver (Open Food Facts & Indian Barcode DB)
          final cloudMatch = await CloudBarcodeResolverService.instance.resolveBarcode(
            barcode,
            businessType: activeType,
          );
          if (cloudMatch != null && mounted) {
            await _importAndAddToCart(cloudMatch, sourceLabel: 'Cloud SKU Added');
          } else {
            if (mounted) {
              InAppNotification.show(
                context: context,
                message: 'No item found with barcode: $barcode',
                type: NotificationType.warning,
              );
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Top Search & Barcode Row
                _buildTopSearchBar(),

                // 2. Dynamic Bill Counter Tabs (Multi-Bill System)
                _buildBillTabsBar(),

                // 3. Category Filter Pills (hidden when searching for maximum vertical space)
                if (_searchQuery.trim().isEmpty) _buildCategoryPills(),

                // 3.5 Active POS Filter Banner
                if (_posFilterMode != 'all') _buildActiveFilterBanner(),

                // 4. Content: Real-Time Dual Search Results or Standard Product Grid
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                      : (_searchQuery.trim().isNotEmpty
                          ? _buildSearchResultsView()
                          : _buildProductGrid()),
                ),

                // Space buffer so products don't get covered by bottom floating bar
                const SizedBox(height: 85),
              ],
            ),

            // 4. Bottom Floating Cart Bar
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: _buildBottomFloatingCartBar(),
            ),
          ],
        ),
      ),
    );
  }

  // 1. TOP SEARCH BAR
  Widget _buildTopSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Search Input
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _performSearch,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).placeholders.searchProduct,
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: const Color(0xFF94A3B8),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: _clearSearch,
                      child: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Camera Barcode Button (or Dine-In / Parcel Toggle for Restaurants)
          if (BusinessVerticals.activeBusinessTypeNotifier.value == 'restaurant')
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _restaurantOrderType = _restaurantOrderType == 'Dine-In' ? 'Parcel' : 'Dine-In';
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                height: 48,
                decoration: BoxDecoration(
                  color: _restaurantOrderType == 'Dine-In' ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _restaurantOrderType == 'Dine-In' ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _restaurantOrderType == 'Dine-In' ? '🍽️' : '🥡',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _restaurantOrderType,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _restaurantOrderType == 'Dine-In' ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            InkWell(
              onTap: _openCameraBarcodeScanner,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: const Icon(Icons.camera_alt_outlined, size: 22, color: Color(0xFF334155)),
              ),
            ),
          const SizedBox(width: 8),

          // Functional POS Filter Button
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: _showPosFilterModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _posFilterMode != 'all' ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: _posFilterMode != 'all'
                        ? Border.all(color: const Color(0xFF60A5FA), width: 1.5)
                        : null,
                  ),
                  child: const Icon(Icons.tune_rounded, size: 20, color: Colors.white),
                ),
              ),
              if (_posFilterMode != 'all')
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterBanner() {
    final filterLabel = _posFilterMode == 'in_stock'
        ? 'In Stock Only ($_inStockCount items)'
        : 'Favorites Only ($_favoritesCount items)';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _posFilterMode == 'in_stock' ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _posFilterMode == 'in_stock' ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _posFilterMode == 'in_stock' ? Icons.inventory_2_outlined : Icons.star_rounded,
            size: 14,
            color: _posFilterMode == 'in_stock' ? const Color(0xFF059669) : const Color(0xFFD97706),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Filtered: $filterLabel',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _posFilterMode == 'in_stock' ? const Color(0xFF065F46) : const Color(0xFF92400E),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _posFilterMode = 'all');
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Clear',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _posFilterMode == 'in_stock' ? const Color(0xFF059669) : const Color(0xFFD97706),
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: _posFilterMode == 'in_stock' ? const Color(0xFF059669) : const Color(0xFFD97706),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPosFilterModal() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.tune_rounded, color: Color(0xFF2563EB), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POS Catalog Filter',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Filter items displayed on the billing counter',
                            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildFilterOption(
                  id: 'all',
                  title: 'All Products',
                  subtitle: 'Show entire catalog without restrictions',
                  count: _totalCatalogCount,
                  icon: Icons.grid_view_rounded,
                  iconColor: const Color(0xFF0F172A),
                  iconBg: const Color(0xFFF1F5F9),
                  ctx: ctx,
                ),
                const SizedBox(height: 8),
                _buildFilterOption(
                  id: 'in_stock',
                  title: 'In Stock Only',
                  subtitle: 'Hide zero or negative stock items',
                  count: _inStockCount,
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFECFDF5),
                  ctx: ctx,
                ),
                const SizedBox(height: 8),
                _buildFilterOption(
                  id: 'favorites',
                  title: 'Favorites / Fast Billing',
                  subtitle: 'Starred items for rapid counter checkout',
                  count: _favoritesCount,
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFEF3C7),
                  ctx: ctx,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterOption({
    required String id,
    required String title,
    required String subtitle,
    required int count,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required BuildContext ctx,
  }) {
    final isSelected = _posFilterMode == id;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(ctx);
        setState(() => _posFilterMode = id);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count items',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    );
  }

  // 1.5 DYNAMIC BILL COUNTER TABS
  Widget _buildBillTabsBar() {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _tabs.length) {
            final isLockedForFree = !_isPro && _tabs.length >= 3;
            // + New Bill button
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: _holdBillAndNew,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLockedForFree ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isLockedForFree ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                      width: 1.1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLockedForFree ? Icons.lock_rounded : Icons.add_rounded,
                        size: 14,
                        color: isLockedForFree ? const Color(0xFFD97706) : const Color(0xFF059669),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isLockedForFree ? 'New Bill (Pro)' : 'New Bill',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isLockedForFree ? const Color(0xFFD97706) : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final tab = _tabs[i];
          final isSel = i == _activeTabIndex;
          final count = tab.items.values.fold<int>(0, (sum, it) => sum + it.quantity.toInt());

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _activeTabIndex = i);
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSel ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                    width: isSel ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSel ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tab.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isSel ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '$count',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isSel ? const Color(0xFF34D399) : const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                    if (_tabs.length > 1 && !isSel) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _closeTab(i);
                        },
                        child: const Icon(Icons.close_rounded, size: 13, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 2. CATEGORY PILLS
  Widget _buildCategoryPills() {
    final allCount = _getCategoryProductCount(null);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          // "All Items" Pill
          _buildCategoryPill(
            label: 'All Items',
            count: allCount,
            isSelected: _selectedCategoryId == null,
            hasTagIcon: false,
            onTap: () => setState(() => _selectedCategoryId = null),
          ),
          const SizedBox(width: 8),

          // Dynamic Categories
          ..._categories.map((cat) {
            final count = _getCategoryProductCount(cat.id);
            final isSelected = _selectedCategoryId == cat.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryPill(
                label: cat.name,
                count: count,
                isSelected: isSelected,
                hasTagIcon: true,
                onTap: () => setState(() => _selectedCategoryId = cat.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryPill({
    required String label,
    required int count,
    required bool isSelected,
    required bool hasTagIcon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasTagIcon) ...[
              Icon(
                Icons.local_offer_outlined,
                size: 13,
                color: isSelected ? Colors.white70 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3. 2-COLUMN PRODUCT GRID
  Widget _buildProductGrid() {
    final prods = filteredProducts;

    if (prods.isEmpty) {
      // This grid only renders when there's no active search (see the
      // caller) — so emptiness here means either a genuinely empty catalog
      // or an active category filter with no matches, never "no search
      // results" (that has its own separate view/copy below).
      final isGenuinelyEmpty = _allProducts.isEmpty && _selectedCategoryId == null;
      final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isGenuinelyEmpty ? vert.navActiveIcon : Icons.filter_alt_off_rounded,
                size: 48,
                color: const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 12),
              Text(
                isGenuinelyEmpty ? vert.emptyCatalogTitle : 'No items in this category',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF334155),
                ),
              ),
              if (isGenuinelyEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  vert.emptyCatalogDescription,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.72,
      ),
      itemCount: prods.length,
      itemBuilder: (context, index) {
        final product = prods[index];
        final cartItem = _cart[product.id];
        final inCartQty = cartItem?.quantity.toInt() ?? 0;

        // Find category name
        final cat = _categories.firstWhere(
          (c) => c.id == product.categoryId,
          orElse: () => CategoryModel(id: '', businessId: '', name: 'GENERAL'),
        );
        final categoryDisplay = cat.name.toUpperCase();

        return _PosProductGridItem(
          product: product,
          inCartQty: inCartQty,
          categoryDisplay: categoryDisplay,
          onTap: () => _addToCart(product),
        );
      },
    );
  }

  // 3.5 REAL-TIME DUAL SEARCH RESULTS VIEW (STORE + MASTER CATALOG)
  Widget _buildSearchResultsView() {
    final storeMatches = filteredProducts;
    final hasStoreMatches = storeMatches.isNotEmpty;
    final hasMasterMatches = _matchingMasterProducts.isNotEmpty;

    if (!hasStoreMatches && !hasMasterMatches && !_isSearchingMaster) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search_off_rounded, size: 40, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Text(
                'No matching items found',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '"$_searchQuery" is not in your store or master catalog',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _openQuickAddCustomDialog(_searchQuery.trim()),
                icon: const Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFF0F172A)),
                label: Text(
                  'Quick Bill "$_searchQuery"',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBF24),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      children: [
        // A. STORE ITEMS MATCHING QUERY
        if (hasStoreMatches) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'IN YOUR STORE (${storeMatches.length})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          ...storeMatches.map((product) {
            final cartItem = _cart[product.id];
            final inCartQty = cartItem?.quantity.toInt() ?? 0;
            return _buildStoreSearchItem(product, inCartQty);
          }),
          const SizedBox(height: 12),
        ],

        // B. MASTER CATALOG SUGGESTIONS (1-TAP BILLING)
        if (hasMasterMatches) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFD97706)),
                const SizedBox(width: 6),
                Text(
                  'FROM MASTER CATALOG (${_matchingMasterProducts.length})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFFD97706),
                  ),
                ),
                const Spacer(),
                Text(
                  '1-Tap Add & Bill',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          ..._matchingMasterProducts.map((masterItem) {
            return _buildMasterCatalogSearchItem(masterItem);
          }),
          const SizedBox(height: 12),
        ],

        // C. Searching spinner
        if (_isSearchingMaster)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
              ),
            ),
          ),

        // D. Quick Custom Bill Option at bottom
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_shopping_cart_rounded, size: 18, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Can\'t find item?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Bill custom "$_searchQuery"',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _openQuickAddCustomDialog(_searchQuery.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text(
                  '+ Bill Custom',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStoreSearchItem(ProductModel product, int inCartQty) {
    final priceStr = MoneyFormatter.formatINR(product.sellingPricePaise);
    final mrpStr = MoneyFormatter.formatINR(product.mrpPaise);
    final isUnlimited = product.isUnlimitedStock;

    final vertToggles = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).toggles;
    final expiryStatus = parseProductExpiry(product);
    final isExpired = expiryStatus?.isExpired ?? false;
    final isExpiringSoon = expiryStatus?.isExpiringSoon ?? false;
    final showFitNote = vertToggles.showSizeVariants && (product.fitNotes?.trim().isNotEmpty ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: inCartQty > 0 ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inCartQty > 0 ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: inCartQty > 0 ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        onTap: () => _addToCart(product),
        title: Row(
          children: [
            if (product.isFavorite) ...[
              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                product.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
          children: [
            Text(
              priceStr,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (product.mrpPaise > product.sellingPricePaise) ...[
              const SizedBox(width: 6),
              Text(
                mrpStr,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  decoration: TextDecoration.lineThrough,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isUnlimited ? '∞ Unlimited' : '${product.stockQuantity.toInt()} ${product.unit}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            if (isExpired || isExpiringSoon) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isExpired ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isExpired ? 'EXPIRED' : 'SELL FIRST · ${expiryStatus!.daysLeft}d',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isExpired ? const Color(0xFFDC2626) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ],
            ),
            if (showFitNote) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.straighten_rounded, size: 11, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      product.fitNotes!.trim(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF7C3AED),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: inCartQty > 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$inCartQty in Bill',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF0F172A), size: 24),
                    onPressed: () => _addToCart(product),
                  ),
                ],
              )
            : IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0F172A), size: 24),
                onPressed: () => _addToCart(product),
              ),
      ),
    );
  }

  Widget _buildMasterCatalogSearchItem(MasterProductModel masterItem) {
    final mrpStr = MoneyFormatter.formatINR(masterItem.mrpPaise);
    final sellStr = MoneyFormatter.formatINR(
      masterItem.sellingPricePaise > 0 ? masterItem.sellingPricePaise : masterItem.mrpPaise,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFDE68A),
          width: 1.2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        onTap: () => _importAndAddToCart(masterItem),
        title: Row(
          children: [
            Expanded(
              child: Text(
                masterItem.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 10, color: Color(0xFFD97706)),
                  const SizedBox(width: 3),
                  Text(
                    'Master SKU',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              sellStr,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (masterItem.mrpPaise > masterItem.sellingPricePaise && masterItem.sellingPricePaise > 0) ...[
              const SizedBox(width: 6),
              Text(
                mrpStr,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  decoration: TextDecoration.lineThrough,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Text(
              masterItem.category,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _importAndAddToCart(masterItem),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: Text(
            '+ Add & Bill',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _openQuickAddCustomDialog(String queryName) {
    final priceCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '⚡ Quick Bill Custom Item',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Item Name',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    queryName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Selling Price (₹)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: priceCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                    hintText: '0.00',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final rupees = double.tryParse(priceCtrl.text) ?? 0.0;
                      if (rupees <= 0) return;
                      final pricePaise = (rupees * 100).round();
                      final customProduct = ProductModel(
                        id: 'prod_custom_${DateTime.now().millisecondsSinceEpoch}',
                        businessId: _allProducts.isNotEmpty ? _allProducts.first.businessId : 'biz_default_retail',
                        name: queryName,
                        sellingPricePaise: pricePaise,
                        mrpPaise: pricePaise,
                        purchasePricePaise: (pricePaise * 0.85).round(),
                        stockQuantity: 99999.0, // Unlimited
                        taxRate: 0.0,
                        isTaxInclusive: true,
                        unit: 'pcs',
                        isLooseItem: false,
                        syncStatus: 'pending',
                      );
                      await LocalDatabase.instance.upsertProduct(customProduct);
                      _addToCart(customProduct);
                      await _loadData();
                      if (ctx.mounted) Navigator.pop(ctx);
                      _clearSearch();
                      if (mounted) {
                        InAppNotification.success('Added $queryName to bill!', context: context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Add to Bill (₹)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 4. BOTTOM FLOATING CART BAR
  Widget _buildBottomFloatingCartBar() {
    final count = cartTotalItemsCount;
    final totalRupees = (cartTotalPaise / 100.0).toStringAsFixed(2);
    final hasItems = count > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Yellow Cart Circle with Black Count Badge + Items & Price text
          Expanded(
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shopping_cart_rounded, size: 20, color: Color(0xFF0F172A)),
                    ),
                    if (hasItems)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F172A),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$count',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${currentTab.name} • $count items',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '₹$totalRupees',
                        maxLines: 1,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right: View Cart & Pay Button
          InkWell(
            onTap: hasItems ? _openCheckoutModal : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: hasItems ? const Color(0xFFFBBF24) : const Color(0xFFFDE68A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(
                    'View Cart & Pay',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: hasItems ? const Color(0xFF0F172A) : const Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: hasItems ? const Color(0xFF0F172A) : const Color(0xFF92400E),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosProductGridItem extends StatefulWidget {
  final ProductModel product;
  final int inCartQty;
  final String categoryDisplay;
  final VoidCallback onTap;

  const _PosProductGridItem({
    required this.product,
    required this.inCartQty,
    required this.categoryDisplay,
    required this.onTap,
  });

  @override
  State<_PosProductGridItem> createState() => _PosProductGridItemState();
}

class _PosProductGridItemState extends State<_PosProductGridItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isInCart = widget.inCartQty > 0;
    final isUnlimited = widget.product.isUnlimitedStock;
    final effectiveStock = (widget.product.stockQuantity - widget.inCartQty);
    final isStockDepleted = !isUnlimited && effectiveStock <= 0;

    // Pharmacy FEFO nudge (Phase 4, KamaiPlus Playbook): flag a near/past
    // expiry item right on the billing tile so the cashier naturally reaches
    // for it before newer stock of the same medicine.
    final expiryStatus = parseProductExpiry(widget.product);
    final isExpired = expiryStatus?.isExpired ?? false;
    final isExpiringSoon = expiryStatus?.isExpiringSoon ?? false;

    final stockLeftStr = isUnlimited
        ? '∞ Unlimited'
        : (effectiveStock <= 0 ? '0 left' : '${effectiveStock.toInt()} left');
    final priceRupees = (widget.product.sellingPricePaise / 100.0).toStringAsFixed(2);
    final unitDisplay = widget.product.unit.isNotEmpty ? widget.product.unit : 'packet';

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isStockDepleted ? const Color(0xFFFFF1F2) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isStockDepleted
                  ? const Color(0xFFEF4444)
                  : (isInCart ? const Color(0xFFFBBF24) : const Color(0xFFEEF2F6)),
              width: (isStockDepleted || isInCart) ? 1.4 : 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: isStockDepleted
                    ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                    : (isInCart ? const Color(0xFFFBBF24).withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.02)),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Opacity(
            opacity: isStockDepleted ? 0.75 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Category Subtitle + Favorite Gold Star + 'X in cart' Gold Badge or OUT OF STOCK Red Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.product.isFavorite) ...[
                            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              widget.categoryDisplay,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: widget.product.isFavorite ? const Color(0xFFD97706) : const Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isStockDepleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                        ),
                        child: Text(
                          'OUT OF STOCK',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      )
                    else if (isExpired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                        ),
                        child: Text(
                          'EXPIRED',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      )
                    else if (isExpiringSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
                        ),
                        child: Text(
                          'SELL FIRST · ${expiryStatus!.daysLeft}d',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      )
                    else if (widget.product.hasVariants)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFFD8B4FE), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.style_rounded, size: 9, color: Color(0xFF7E22CE)),
                            const SizedBox(width: 2.5),
                            Text(
                              'Variants ▾',
                              style: GoogleFonts.outfit(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF7E22CE),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isInCart)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
                        ),
                        child: Text(
                          '${widget.inCartQty} in cart',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                  ],
                ),
                // Middle: Product Name
                Text(
                  widget.product.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isStockDepleted ? const Color(0xFF475569) : const Color(0xFF0F172A),
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Bottom Row: Price / unit and Stock left
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '₹$priceRupees ',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: isStockDepleted ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                              ),
                            ),
                            TextSpan(
                              text: widget.product.hasVariants ? 'starts' : '/$unitDisplay',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.product.hasVariants
                          ? 'Choose ▾'
                          : (isStockDepleted ? 'Out of Stock' : stockLeftStr),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: widget.product.hasVariants
                            ? const Color(0xFF7E22CE)
                            : (isStockDepleted ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
