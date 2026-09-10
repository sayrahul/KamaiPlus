import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../models/models.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/home_widget_service.dart';
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

class _PosBillingScreenState extends State<PosBillingScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  List<ProductModel> _allProducts = [];
  List<CategoryModel> _categories = [];
  List<CustomerModel> _customers = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryId; // null = 'all'
  bool _isLoading = true;

  // Master Catalog Search Results (<2ms offline lookup)
  List<MasterProductModel> _matchingMasterProducts = [];
  bool _isSearchingMaster = false;

  // Multi-cart Hold & Resume system
  late List<CartTab> _tabs;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = [
      CartTab(id: 'tab_1', name: 'Bill #1', number: 1, items: {}),
    ];
    _loadBusinessType();
    BusinessVerticals.activeBusinessTypeNotifier.addListener(_onBusinessTypeChanged);
    FirestoreSyncService.instance.liveSyncCounter.addListener(_handleCloudSyncUpdate);
  }

  Future<void> _loadBusinessType() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (profile.businessType.isNotEmpty) {
        BusinessVerticals.updateActiveBusinessType(profile.businessType);
      }
    } catch (_) {}
    _loadData();
  }

  void _onBusinessTypeChanged() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    BusinessVerticals.activeBusinessTypeNotifier.removeListener(_onBusinessTypeChanged);
    FirestoreSyncService.instance.liveSyncCounter.removeListener(_handleCloudSyncUpdate);
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
    return _allProducts.where((p) {
      final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.barcode != null && p.barcode!.contains(_searchQuery));
      final matchesCat = _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
      return matchesSearch && matchesCat;
    }).toList();
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

  Future<void> _importAndAddToCart(MasterProductModel masterItem) async {
    HapticFeedback.selectionClick();
    final imported = await LocalDatabase.instance.importMasterProductToStore(masterItem);
    _addToCart(imported);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Added to Bill: ${imported.name}')),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    final currentQty = _cart[product.id]?.quantity.toInt() ?? 0;
    final isUnlimited = product.stockQuantity >= 900000;

    if (!isUnlimited && (product.stockQuantity <= 0 || currentQty >= product.stockQuantity)) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.block_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ "${product.name}" is Out of Stock! (Available: ${product.stockQuantity.toInt()})',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      if (_cart.containsKey(product.id)) {
        _cart[product.id]!.quantity += 1;
      } else {
        _cart[product.id] = CartItemModel(product: product, quantity: 1);
      }
    });
  }

  void _updateItemQuantity(CartItemModel item, int newQty) {
    HapticFeedback.lightImpact();
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
    });
  }

  void _holdBillAndNew() {
    HapticFeedback.mediumImpact();
    if (_tabs.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 5 parallel bills supported'), duration: Duration(seconds: 1)),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Naya Bill #${_tabs.last.number} open ho gaya. Products add karein.'),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
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
      final matched = await LocalDatabase.instance.findProductByBarcode(barcode);
      if (matched != null) {
        _addToCart(matched);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Scanned: ${matched.name}')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Fallback: Check Master Catalog (<2ms)
        final masterMatch = await LocalDatabase.instance.findMasterProductByBarcode(barcode);
        if (masterMatch != null && mounted) {
          final imported = await LocalDatabase.instance.importMasterProductToStore(masterMatch);
          _addToCart(imported);
          _loadData(); // Update background products list
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Master SKU Added: ${imported.name}')),
                  ],
                ),
                backgroundColor: const Color(0xFF1E293B),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No item found with barcode: $barcode'),
                backgroundColor: const Color(0xFFF59E0B),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

          // Camera Barcode Button
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

          // Filter / Settings Button with Yellow Lock Badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('POS Filter: Showing all available items'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, size: 20, color: Colors.white),
                ),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFBBF24),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock, size: 9, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
        ],
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
            // + New Bill button
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: _holdBillAndNew,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0), width: 1.1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 15, color: Color(0xFF059669)),
                      const SizedBox(width: 4),
                      Text(
                        'New Bill',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF059669),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              'No items match your search',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
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
        title: Text(
          product.name,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        subtitle: Row(
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added $queryName to bill!'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
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
    final isUnlimited = widget.product.stockQuantity >= 900000;
    final effectiveStock = (widget.product.stockQuantity - widget.inCartQty);
    final isStockDepleted = !isUnlimited && effectiveStock <= 0;

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
                // Top Row: Category Subtitle + 'X in cart' Gold Badge or OUT OF STOCK Red Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.categoryDisplay,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: const Color(0xFF94A3B8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                              text: '/$unitDisplay',
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
                      isStockDepleted ? 'Out of Stock' : stockLeftStr,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isStockDepleted ? const Color(0xFFDC2626) : const Color(0xFF64748B),
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
