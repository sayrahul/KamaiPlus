import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/database/local_database.dart';
import '../common/pwa_top_bar.dart';
import '../common/owner_privacy_modal.dart';
import 'ai_inward_modal.dart';
import 'add_product_modal.dart';
import 'quick_stock_update_modal.dart';
import '../pos/barcode_scanner_view.dart';
import '../../services/firestore_sync_service.dart';

class ProductsScreen extends StatefulWidget {
  final bool autoOpenFirstEdit;
  const ProductsScreen({super.key, this.autoOpenFirstEdit = false});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  bool _filterLowStockOnly = false;
  bool _filterExpiringOnly = false;
  bool _isAssetHidden = true; // Hidden by default, unlocked via Owner PIN
  bool _isGridView = false; // Instant List / Grid view toggle

  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _favoriteProductIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prods = await LocalDatabase.instance.getAllProducts();
    final cats = await LocalDatabase.instance.getAllCategories();
    if (!mounted) return;
    setState(() {
      _products = prods;
      _categories = cats;
      _isLoading = false;
    });

    if (widget.autoOpenFirstEdit && prods.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openAddProductSheet(existingProduct: prods.first);
        }
      });
    }
  }

  int get _totalInventoryCostValuationPaise {
    return _products.fold<int>(0, (sum, p) {
      final cost = p.purchasePricePaise > 0 ? p.purchasePricePaise : (p.sellingPricePaise * 0.85).round();
      return sum + (p.stockQuantity * cost).toInt();
    });
  }

  int get _lowStockCount {
    return _products.where((p) => p.stockQuantity <= 15).length;
  }

  List<ProductModel> get _filteredProducts {
    return _products.where((p) {
      final matchesSearch = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.barcode != null && p.barcode!.contains(_searchQuery));
      final matchesCategory = _selectedCategory == 'ALL' || p.categoryId == _selectedCategory;
      final matchesLowStock = !_filterLowStockOnly || p.stockQuantity <= 15;
      return matchesSearch && matchesCategory && matchesLowStock;
    }).toList();
  }

  Future<void> _adjustStock(ProductModel product, double delta) async {
    HapticFeedback.lightImpact();
    final newQty = (product.stockQuantity + delta).clamp(0.0, 99999.0);
    final updated = ProductModel(
      id: product.id,
      businessId: product.businessId,
      name: product.name,
      barcode: product.barcode,
      categoryId: product.categoryId,
      sellingPricePaise: product.sellingPricePaise,
      mrpPaise: product.mrpPaise,
      purchasePricePaise: product.purchasePricePaise,
      stockQuantity: newQty,
      taxRate: product.taxRate,
      isTaxInclusive: product.isTaxInclusive,
      unit: product.unit,
      syncStatus: 'pending',
    );

    await LocalDatabase.instance.upsertProduct(updated);
    FirestoreSyncService.instance.pushProductToCloud(updated).catchError((_) {});
    _loadData();
  }

  void _openAiInwardSheet() {
    AiInwardModal.show(
      context,
      onSelectManual: () => _openAddProductSheet(),
      onInwardSuccess: () => _loadData(),
    );
  }

  void _openAddProductSheet({ProductModel? existingProduct}) {
    AddProductModal.show(
      context,
      existingProduct: existingProduct,
      categories: _categories,
      onSaved: () => _loadData(),
      onSwitchToAiInward: () => _openAiInwardSheet(),
    );
  }

  Future<void> _openBarcodeScanner() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerView()),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      final existing = await LocalDatabase.instance.findProductByBarcode(scanned);
      if (existing != null) {
        setState(() {
          _searchCtrl.text = scanned;
          _searchQuery = scanned;
        });
      } else {
        // Fallback: Check Master Catalog (<2ms)
        final master = await LocalDatabase.instance.findMasterProductByBarcode(scanned);
        if (master != null && mounted) {
          final imported = await LocalDatabase.instance.importMasterProductToStore(master);
          await _loadData();
          setState(() {
            _searchCtrl.text = imported.name;
            _searchQuery = imported.name;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Imported from Master Catalog: ${imported.name}')),
                  ],
                ),
                backgroundColor: const Color(0xFF1E293B),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          setState(() {
            _searchCtrl.text = scanned;
            _searchQuery = scanned;
          });
        }
      }
    }
  }

  void _openQuickUpdateDialog(ProductModel product) {
    QuickStockUpdateModal.show(
      context,
      product: product,
      onUpdated: () => _loadData(),
    );
  }

  void _confirmDeleteProduct(ProductModel product) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Product?',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          'Kya aap sach me "${product.name}" ko product catalog se delete karna chahte hain?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDatabase.instance.deleteProduct(product.id);
              FirestoreSyncService.instance.deleteProductFromCloud(product.id).catchError((_) {});
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ "${product.name}" deleted from catalog'),
                    backgroundColor: const Color(0xFF0F172A),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildStockTrafficBadge(double qty, String unit, {bool isLooseOrInfinite = false}) {
    if (isLooseOrInfinite || qty >= 99999) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.all_inclusive_rounded, size: 11, color: Color(0xFF16A34A)),
            const SizedBox(width: 3),
            Text(
              'Unlimited',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
      );
    }

    final Color bg;
    final Color text;
    final String label;
    final IconData icon;

    if (qty <= 0) {
      bg = const Color(0xFFFEE2E2);
      text = const Color(0xFFDC2626);
      label = 'Out of Stock';
      icon = Icons.cancel_outlined;
    } else if (qty <= 5) {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFFD97706);
      label = 'Low: ${qty.toInt()} left';
      icon = Icons.warning_amber_rounded;
    } else {
      bg = const Color(0xFFECFDF5);
      text = const Color(0xFF059669);
      label = '${qty.toInt()} $unit';
      icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: text.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: text),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAssetVisibility() {
    if (_isAssetHidden) {
      OwnerPrivacyModal.show(
        context,
        onUnlocked: () {
          setState(() => _isAssetHidden = false);
        },
      );
    } else {
      setState(() => _isAssetHidden = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🔒 Inventory asset valuation hidden.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  String _getCategoryName(String? catId) {
    if (catId == null) return 'General';
    final found = _categories.firstWhere((c) => c.id == catId, orElse: () => CategoryModel(id: '', businessId: '', name: 'General'));
    return found.name.isNotEmpty ? found.name : 'General';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0F172A))),
      );
    }

    final filtered = _filteredProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const PwaTopBar(),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. PRODUCTS MASTER HEADER CARD (Screenshot 1)
            _buildHeaderCard(),
            const SizedBox(height: 12),

            // 2. METRICS RIBBON 2x2 GRID
            _buildMetricsGrid(),
            const SizedBox(height: 14),

            // 3. SEARCH & FILTERS TOOLBAR
            _buildSearchToolbar(),
            const SizedBox(height: 10),

            // 4. CATEGORY HORIZONTAL PILLS
            _buildCategoryPills(),
            const SizedBox(height: 12),

            // 5. PRODUCT LIST / GRID ITEMS
            if (filtered.isEmpty)
              _buildEmptyState()
            else if (_isGridView)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.88,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (ctx, i) => _buildProductGridCard(filtered[i]),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) => _buildProductCard(filtered[i]),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0x080F172A),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Package Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 22,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 10),

              // Title, Eye Button & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Products Master & Items',
                          style: GoogleFonts.outfit(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _toggleAssetVisibility,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Icon(
                              _isAssetHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 14,
                              color: const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_products.length} registered products with barcodes, batch expiry & instant stock tracking',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: const Color(0xFF64748B),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Two Action Buttons: Inward with AI & + Add Product
          Row(
            children: [
              // Inward with AI
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openAiInwardSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 4),
                          const Icon(Icons.receipt_long_outlined, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 5),
                          Text(
                            'Inward with AI',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // + Add Product
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openAddProductSheet(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Add Product',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildMetricsGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Card 1: Catalog Items
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.layers_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Catalog Items',
                  tag: 'Master',
                  value: _products.length.toString(),
                  valueColor: const Color(0xFF0F172A),
                  subtitle: 'Registered products',
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFF1F5F9)),
              // Card 2: Low Stock Alerts
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.warning_amber_rounded,
                  iconColor: const Color(0xFFE11D48),
                  title: 'Low Stock Alerts',
                  tag: 'Reorder',
                  value: _lowStockCount.toString(),
                  valueColor: _lowStockCount > 0 ? const Color(0xFFE11D48) : const Color(0xFF0F172A),
                  subtitle: 'Below safety threshold',
                  onTap: () => setState(() => _filterLowStockOnly = !_filterLowStockOnly),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFF1F5F9), height: 16),
          Row(
            children: [
              // Card 3: Inventory Asset (Eye toggles this!)
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.trending_up_rounded,
                  iconColor: const Color(0xFF059669),
                  title: 'Inventory Asset',
                  tag: 'Valuation',
                  value: _isAssetHidden ? '••••••' : MoneyFormatter.formatINR(_totalInventoryCostValuationPaise),
                  valueColor: const Color(0xFF059669),
                  subtitle: 'Stock at cost price',
                  onTap: _toggleAssetVisibility,
                ),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFF1F5F9)),
              // Card 4: Categories
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.category_outlined,
                  iconColor: const Color(0xFF7C3AED),
                  title: 'Categories',
                  tag: 'Groups',
                  value: _categories.length.toString(),
                  valueColor: const Color(0xFF7C3AED),
                  subtitle: 'Product groups',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String tag,
    required String value,
    required Color valueColor,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: iconColor),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  tag,
                  style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchToolbar() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Row(
        children: [
          // Search Field
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Search by product name, barcode, HSN...',
                        hintStyle: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: const Icon(Icons.cancel_rounded, size: 15, color: Color(0xFF94A3B8)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Barcode Button ||||| (Screenshot 5)
          _buildToolbarButton(
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
            borderColor: const Color(0xFFBFDBFE),
            onTap: _openBarcodeScanner,
          ),
          const SizedBox(width: 4),

          // Low Stock Alert Filter Toggle
          _buildToolbarButton(
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFE11D48),
            bgColor: _filterLowStockOnly ? const Color(0xFFFFE4E6) : const Color(0xFFFFF1F2),
            borderColor: _filterLowStockOnly ? const Color(0xFFE11D48) : const Color(0xFFFECDD3),
            onTap: () => setState(() => _filterLowStockOnly = !_filterLowStockOnly),
          ),
          const SizedBox(width: 4),

          // Expiring Filter Toggle
          _buildToolbarButton(
            icon: Icons.access_time_rounded,
            iconColor: const Color(0xFFD97706),
            bgColor: _filterExpiringOnly ? const Color(0xFFFEF3C7) : const Color(0xFFFFFBEB),
            borderColor: _filterExpiringOnly ? const Color(0xFFD97706) : const Color(0xFFFDE68A),
            onTap: () => setState(() => _filterExpiringOnly = !_filterExpiringOnly),
          ),
          const SizedBox(width: 4),

          // Instant Grid / List Toggle
          _buildToolbarButton(
            icon: _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            iconColor: const Color(0xFF0F172A),
            bgColor: const Color(0xFFF1F5F9),
            borderColor: const Color(0xFFCBD5E1),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isGridView = !_isGridView);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.1),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildCategoryPills() {
    final allCats = [CategoryModel(id: 'ALL', businessId: '', name: 'All Items'), ..._categories];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: allCats.map((cat) {
          final isSelected = _selectedCategory == cat.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Text(
                  cat.name,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product) {
    final profitPaise = product.sellingPricePaise - product.purchasePricePaise;
    final profitStr = profitPaise > 0 ? '+₹${(profitPaise / 100).toStringAsFixed(2)}' : '₹0.00';
    final isFav = _favoriteProductIds.contains(product.id);
    final categoryName = _getCategoryName(product.categoryId);
    final isLowStock = product.stockQuantity <= 15;
    final isInfinite = product.isLooseItem || product.stockQuantity >= 99999;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 6,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title, Star, Fast Bolt Update, Edit Pencil & Delete Trash
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Favorite Star
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isFav) {
                      _favoriteProductIds.remove(product.id);
                    } else {
                      _favoriteProductIds.add(product.id);
                    }
                  });
                },
                child: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 20,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 6),
              // Quick In-Line Price & Stock Update Button
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openQuickUpdateDialog(product);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Dedicated Pencil Edit Button
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openAddProductSheet(existingProduct: product);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Dedicated Delete Button
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _confirmDeleteProduct(product);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Category Badge + Traffic Light Stock Badge (Clean listing: barcode digits removed per request)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  categoryName,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
              InkWell(
                onTap: () => _openQuickUpdateDialog(product),
                borderRadius: BorderRadius.circular(6),
                child: _buildStockTrafficBadge(product.stockQuantity, product.unit, isLooseOrInfinite: isInfinite),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Details: Selling Price, Profit Margin & Stock Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Selling Price (Tap for Quick Update)
              InkWell(
                onTap: () => _openQuickUpdateDialog(product),
                borderRadius: BorderRadius.circular(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELLING PRICE',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          MoneyFormatter.formatINR(product.sellingPricePaise),
                          style: GoogleFonts.robotoMono(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ],
                ),
              ),

              // Profit Margin (Only visible if not asset hidden)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PROFIT MARGIN',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isAssetHidden ? '••••••' : profitStr,
                    style: GoogleFonts.robotoMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),

              // Stock Counter: Hide Stepper (+/-) for Infinite/Loose Stock items
              if (isInfinite)
                InkWell(
                  onTap: () => _openQuickUpdateDialog(product),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.all_inclusive_rounded, size: 13, color: Color(0xFF16A34A)),
                        const SizedBox(width: 4),
                        Text(
                          'Unlimited',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Stock Stepper (+ / -)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLowStock ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isLowStock ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _adjustStock(product, -1),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.remove_rounded, size: 14, color: Color(0xFF475569)),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openQuickUpdateDialog(product),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '${product.stockQuantity.toInt()} ${product.unit}',
                            style: GoogleFonts.robotoMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isLowStock ? const Color(0xFFE11D48) : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _adjustStock(product, 1),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.add_rounded, size: 14, color: Color(0xFF475569)),
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
  }

  Widget _buildProductGridCard(ProductModel product) {
    final categoryName = _getCategoryName(product.categoryId);
    final isInfinite = product.isLooseItem || product.stockQuantity >= 99999;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 6,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Category + Pencil Edit + Delete Trash
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  categoryName,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => _openAddProductSheet(existingProduct: product),
                    child: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF475569)),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _confirmDeleteProduct(product),
                    child: const Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFDC2626)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Product Name
          Text(
            product.name,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          // Stock Traffic Badge
          InkWell(
            onTap: () => _openQuickUpdateDialog(product),
            borderRadius: BorderRadius.circular(6),
            child: _buildStockTrafficBadge(product.stockQuantity, product.unit, isLooseOrInfinite: isInfinite),
          ),

          const Spacer(),

          // Selling Price & Stock Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => _openQuickUpdateDialog(product),
                child: Text(
                  MoneyFormatter.formatINR(product.sellingPricePaise),
                  style: GoogleFonts.robotoMono(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              // If infinite, show badge with no +/- stepper
              if (isInfinite)
                InkWell(
                  onTap: () => _openQuickUpdateDialog(product),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Text(
                      '∞ Unlimited',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)),
                    ),
                  ),
                )
              else
                // Stock Stepper (+ / -)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _adjustStock(product, -1),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.remove_rounded, size: 13, color: Color(0xFF475569)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openQuickUpdateDialog(product),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${product.stockQuantity.toInt()}',
                          style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _adjustStock(product, 1),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.add_rounded, size: 13, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.search_off_rounded, size: 36, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),
          Text(
            'No matching products found',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search query or category filters.',
            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => _openAddProductSheet(),
            icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            label: Text('Add New Product SKU', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
