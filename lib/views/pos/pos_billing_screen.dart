import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../core/database/local_database.dart';
import '../../services/firestore_sync_service.dart';
import 'pos_checkout_modal.dart';
import 'barcode_scanner_view.dart';

class CartTab {
  String id;
  String name;
  int number;
  Map<String, CartItemModel> items;
  CustomerModel? customer;

  CartTab({
    required this.id,
    required this.name,
    required this.number,
    required this.items,
    this.customer,
  });
}

class PosBillingScreen extends StatefulWidget {
  const PosBillingScreen({super.key});

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

  // Multi-cart Hold & Resume system
  late List<CartTab> _tabs;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = [
      CartTab(id: 'tab_1', name: 'Bill #1', number: 1, items: {}),
    ];
    _loadData();
    FirestoreSyncService.instance.liveSyncCounter.addListener(_handleCloudSyncUpdate);
  }

  @override
  void dispose() {
    FirestoreSyncService.instance.liveSyncCounter.removeListener(_handleCloudSyncUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _handleCloudSyncUpdate() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    final prods = await LocalDatabase.instance.getAllProducts();
    final cats = await LocalDatabase.instance.getAllCategories();
    final custs = await LocalDatabase.instance.getAllCustomers();

    if (mounted) {
      setState(() {
        _allProducts = prods;
        _categories = cats;
        _customers = custs;
        _isLoading = false;
      });
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
      final newIndex = _tabs.length + 1;
      _tabs.add(CartTab(id: 'tab_$newIndex', name: 'Bill #$newIndex', number: newIndex, items: {}));
      _activeTabIndex = _tabs.length - 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bill #${_tabs.length - 1} held. Switched to Bill #${_tabs.length}'),
        backgroundColor: const Color(0xFF0F172A),
        duration: const Duration(seconds: 1),
      ),
    );
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
          _cart.clear();
          currentTab.customer = null;
        });
        _loadData(); // refresh stock numbers
      },
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

                // 2. Category Filter Pills
                _buildCategoryPills(),

                // 3. 2-Column Product Cards Grid
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                      : _buildProductGrid(),
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
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Scan barcode or type Atta, Rice, Oil, Maggi...',
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
                      onTap: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.18,
      ),
      itemCount: prods.length,
      itemBuilder: (context, index) {
        final product = prods[index];
        final cartItem = _cart[product.id];
        final inCartQty = cartItem?.quantity.toInt() ?? 0;
        final isInCart = inCartQty > 0;

        // Find category name
        final cat = _categories.firstWhere(
          (c) => c.id == product.categoryId,
          orElse: () => CategoryModel(id: '', businessId: '', name: 'GENERAL'),
        );
        final categoryDisplay = cat.name.toUpperCase();

        // Calculate available stock on screen
        final effectiveStock = (product.stockQuantity - inCartQty).clamp(0.0, 99999.0);
        final stockLeftStr = effectiveStock % 1 == 0
            ? effectiveStock.toInt().toString()
            : effectiveStock.toStringAsFixed(1);

        final priceRupees = (product.sellingPricePaise / 100.0).toStringAsFixed(2);
        final unitDisplay = product.unit.isNotEmpty ? product.unit : 'packet';

        return InkWell(
          onTap: () => _addToCart(product),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isInCart ? const Color(0xFFFBBF24) : const Color(0xFFEEF2F6),
                width: isInCart ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isInCart ? const Color(0xFFFBBF24).withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Category Subtitle + 'X in cart' Gold Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        categoryDisplay,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: const Color(0xFF94A3B8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isInCart)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          '$inCartQty in cart',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                  ],
                ),

                // Middle: Product Name
                Text(
                  product.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                  maxLines: 2,
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
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            TextSpan(
                              text: '/$unitDisplay',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10.5,
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
                      '$stockLeftStr left',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.shopping_cart_rounded, size: 22, color: Color(0xFF0F172A)),
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
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count items',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    '₹$totalRupees',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Right: View Cart & Pay Button
          InkWell(
            onTap: hasItems ? _openCheckoutModal : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
