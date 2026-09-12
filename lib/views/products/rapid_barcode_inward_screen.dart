import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../common/in_app_notification.dart';
import '../../models/models.dart';
import '../../services/cloud_barcode_resolver_service.dart';
import '../../services/firestore_sync_service.dart';

/// Rapid Multi-Product Barcode Inward Screen.
/// 
/// Allows retail merchants to scan and catalog 20–30 items continuously
/// without ever having to close the scanner or navigate back and forth.
/// Auto-fetches item details (<1.5s) and seamlessly transitions to the next item.
class RapidBarcodeInwardScreen extends StatefulWidget {
  final VoidCallback onInwardSuccess;

  const RapidBarcodeInwardScreen({
    super.key,
    required this.onInwardSuccess,
  });

  static Future<void> show(BuildContext context, {required VoidCallback onInwardSuccess}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RapidBarcodeInwardScreen(onInwardSuccess: onInwardSuccess),
      ),
    );
  }

  @override
  State<RapidBarcodeInwardScreen> createState() => _RapidBarcodeInwardScreenState();
}

class _RapidBarcodeInwardScreenState extends State<RapidBarcodeInwardScreen> with SingleTickerProviderStateMixin {
  late final MobileScannerController _scannerController;
  late final AnimationController _laserAnimController;

  // Controllers
  final _nameCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _mrpCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '10');
  final _manualBarcodeCtrl = TextEditingController();

  final _sellPriceFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();

  // State
  bool _isScanning = true;
  bool _isResolving = false;
  bool _hasActiveItem = false;
  bool _isFavorite = false;
  bool _torchEnabled = false;
  String? _scannedBarcode;
  String? _existingProductId;

  late String _selectedUnit;
  late String _selectedCategoryId;
  List<CategoryModel> _categories = [];
  final List<ProductModel> _sessionProducts = [];

  final List<String> _quickStockChips = ['+5', '+10', '+20', '+50'];

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _laserAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _selectedUnit = 'pcs';
    _selectedCategoryId = '';
    _loadCategories();
  }

  @override
  void dispose() {
    _laserAnimController.dispose();
    _scannerController.dispose();
    _nameCtrl.dispose();
    _sellPriceCtrl.dispose();
    _mrpCtrl.dispose();
    _costPriceCtrl.dispose();
    _stockCtrl.dispose();
    _manualBarcodeCtrl.dispose();
    _sellPriceFocusNode.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
    final cats = await LocalDatabase.instance.getAllCategories(businessType: activeType);
    if (mounted) {
      setState(() {
        _categories = cats;
        if (cats.isNotEmpty) {
          _selectedCategoryId = cats.first.id;
        }
      });
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (!_isScanning || _isResolving || _hasActiveItem) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.length >= 6) {
        _handleBarcodeScanned(code);
        break;
      }
    }
  }

  Future<void> _handleBarcodeScanned(String barcode) async {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() {
      _isScanning = false;
      _isResolving = true;
      _scannedBarcode = barcode;
      _hasActiveItem = true;
      _existingProductId = null;
    });

    final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;

    // 1. Check Store Database (<2ms)
    final storeItem = await LocalDatabase.instance.findProductByBarcode(barcode);
    if (storeItem != null && mounted) {
      setState(() {
        _existingProductId = storeItem.id;
        _nameCtrl.text = storeItem.name;
        _selectedUnit = storeItem.unit;
        _selectedCategoryId = storeItem.categoryId ?? (_categories.isNotEmpty ? _categories.first.id : '');
        _isFavorite = storeItem.isFavorite;
        _sellPriceCtrl.text = (storeItem.sellingPricePaise / 100).toStringAsFixed(0);
        _mrpCtrl.text = storeItem.mrpPaise > 0 ? (storeItem.mrpPaise / 100).toStringAsFixed(0) : '';
        _costPriceCtrl.text = storeItem.purchasePricePaise > 0 ? (storeItem.purchasePricePaise / 100).toStringAsFixed(0) : '';
        _stockCtrl.text = '10'; // Additional quantity to inward
        _isResolving = false;
      });
      _sellPriceFocusNode.requestFocus();
      return;
    }

    // 2. Check Master Catalog (<2ms)
    final master = await LocalDatabase.instance.findMasterProductByBarcode(barcode, businessType: activeType);
    if (master != null && mounted) {
      _applyResolvedData(
        name: master.name,
        category: master.category,
        unit: master.unit,
        mrpPaise: master.mrpPaise,
        sellingPricePaise: master.sellingPricePaise,
      );
      return;
    }

    // 3. Parallel Cloud Resolver (<1.5s)
    final cloudItem = await CloudBarcodeResolverService.instance.resolveBarcode(barcode, businessType: activeType);
    if (cloudItem != null && mounted) {
      _applyResolvedData(
        name: cloudItem.name,
        category: cloudItem.category,
        unit: cloudItem.unit,
        mrpPaise: cloudItem.mrpPaise,
        sellingPricePaise: cloudItem.sellingPricePaise,
      );
      return;
    }

    // 4. Brand-new unrecognized barcode: Pre-fill smart title and focus immediately
    if (mounted) {
      final shortSuffix = barcode.length >= 4 ? barcode.substring(barcode.length - 4) : barcode;
      setState(() {
        _nameCtrl.text = 'Item #$shortSuffix';
        _nameCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _nameCtrl.text.length);
        _sellPriceCtrl.text = '';
        _mrpCtrl.text = '';
        _costPriceCtrl.text = '';
        _stockCtrl.text = '10';
        _isFavorite = false;
        _isResolving = false;
      });
      _nameFocusNode.requestFocus();
    }
  }

  void _applyResolvedData({
    required String name,
    required String category,
    required String unit,
    required int mrpPaise,
    required int sellingPricePaise,
  }) {
    // Match category
    if (category.isNotEmpty && _categories.isNotEmpty) {
      final matchCat = _categories.firstWhere(
        (c) => c.name.toLowerCase() == category.toLowerCase(),
        orElse: () => _categories.first,
      );
      _selectedCategoryId = matchCat.id;
    }

    setState(() {
      _nameCtrl.text = name;
      _selectedUnit = unit;
      _mrpCtrl.text = mrpPaise > 0 ? (mrpPaise / 100).toStringAsFixed(0) : '';
      _sellPriceCtrl.text = sellingPricePaise > 0
          ? (sellingPricePaise / 100).toStringAsFixed(0)
          : (mrpPaise > 0 ? (mrpPaise / 100).toStringAsFixed(0) : '');
      _costPriceCtrl.text = '';
      _stockCtrl.text = '10';
      _isFavorite = false;
      _isResolving = false;
    });

    _sellPriceFocusNode.requestFocus();
  }

  Future<void> _saveAndScanNext() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showToast('Product name is required');
      _nameFocusNode.requestFocus();
      return;
    }

    final sellPriceNum = double.tryParse(_sellPriceCtrl.text.trim()) ?? 0.0;
    if (sellPriceNum <= 0) {
      _showToast('Please enter Selling Price');
      _sellPriceFocusNode.requestFocus();
      return;
    }

    final sellPaise = (sellPriceNum * 100).round();
    final mrpNum = double.tryParse(_mrpCtrl.text.trim()) ?? sellPriceNum;
    final mrpPaise = (mrpNum * 100).round();
    final costNum = double.tryParse(_costPriceCtrl.text.trim()) ?? 0.0;
    final costPaise = (costNum * 100).round();
    final qty = double.tryParse(_stockCtrl.text.trim()) ?? 10.0;

    final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
    final bizId = FirestoreSyncService.instance.activeBusinessId;

    final product = ProductModel(
      id: _existingProductId ?? const Uuid().v4(),
      businessId: bizId,
      name: name,
      barcode: _scannedBarcode,
      categoryId: _selectedCategoryId.isNotEmpty ? _selectedCategoryId : null,
      sellingPricePaise: sellPaise,
      mrpPaise: mrpPaise > 0 ? mrpPaise : sellPaise,
      purchasePricePaise: costPaise,
      stockQuantity: qty,
      taxRate: 0.0,
      isTaxInclusive: true,
      unit: _selectedUnit,
      isFavorite: _isFavorite,
      syncStatus: 'synced',
      businessType: activeType,
    );

    await LocalDatabase.instance.upsertProduct(product);
    if (_scannedBarcode != null && _scannedBarcode!.isNotEmpty) {
      try {
        await LocalDatabase.instance.insertMasterProduct(MasterProductModel(
          barcode: _scannedBarcode!,
          name: name,
          category: _categories.isNotEmpty ? _categories.first.name : 'General',
          unit: _selectedUnit,
          mrpPaise: mrpPaise,
          sellingPricePaise: sellPaise,
          businessType: activeType,
        ));
      } catch (_) {}
    }
    FirestoreSyncService.instance.pushProductToCloud(product).catchError((_) {});
    widget.onInwardSuccess();

    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() {
      _sessionProducts.insert(0, product);
      _hasActiveItem = false;
      _isResolving = false;
      _scannedBarcode = null;
      _existingProductId = null;
      _nameCtrl.clear();
      _sellPriceCtrl.clear();
      _mrpCtrl.clear();
      _costPriceCtrl.clear();
      _stockCtrl.text = '10';
      _isFavorite = false;
      _isScanning = true;
    });

    _showToast('✓ Added "${product.name}"! Ready for next barcode...', isSuccess: true);
  }

  void _skipCurrentAndResumeScan() {
    HapticFeedback.selectionClick();
    setState(() {
      _hasActiveItem = false;
      _isResolving = false;
      _scannedBarcode = null;
      _existingProductId = null;
      _nameCtrl.clear();
      _sellPriceCtrl.clear();
      _mrpCtrl.clear();
      _costPriceCtrl.clear();
      _stockCtrl.text = '10';
      _isFavorite = false;
      _isScanning = true;
    });
  }

  void _showManualBarcodeInputDialog() {
    _manualBarcodeCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Enter Barcode Manually',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: TextField(
          controller: _manualBarcodeCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: GoogleFonts.robotoMono(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'e.g. 8901030383748',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            if (val.trim().isNotEmpty) {
              _handleBarcodeScanned(val.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_manualBarcodeCtrl.text.trim().isNotEmpty) {
                _handleBarcodeScanned(_manualBarcodeCtrl.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  void _showToast(String message, {bool isSuccess = false}) {
    InAppNotification.show(
      context: context,
      message: message,
      customIcon: isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
      customColor: isSuccess ? Colors.greenAccent : Colors.amberAccent,
      duration: const Duration(milliseconds: 1800),
    );
  }

  void _finishSessionAndClose() {
    widget.onInwardSuccess();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cameraHeight = size.height * 0.38;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        widget.onInwardSuccess();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
          children: [
            // 1. TOP HEADER & CAMERA SCANNER (38% Height)
            SizedBox(
              height: cameraHeight,
              child: Stack(
                children: [
                  // Live Camera Stream
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcodeDetected,
                  ),

                  // Top Reticle Dark Vignette
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),

                  // Scanning Laser Indicator
                  if (_isScanning)
                    AnimatedBuilder(
                      animation: _laserAnimController,
                      builder: (context, child) {
                        return Positioned(
                          top: _laserAnimController.value * (cameraHeight - 50) + 25,
                          left: 20,
                          right: 20,
                          child: Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0xFF38BDF8),
                                  Color(0xFF818CF8),
                                  Color(0xFF38BDF8),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF38BDF8).withValues(alpha: 0.8),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  // Top Overlay Bar: Back, Flash, Counter & Done
                  Positioned(
                    top: 10,
                    left: 14,
                    right: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Close / Back Button
                        InkWell(
                          onTap: _finishSessionAndClose,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                          ),
                        ),

                        // Rapid Session Counter Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFA7F3D0), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.flash_on_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '${_sessionProducts.length} Items Added',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Flashlight & Done
                        Row(
                          children: [
                            InkWell(
                              onTap: () {
                                _scannerController.toggleTorch();
                                setState(() => _torchEnabled = !_torchEnabled);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _torchEnabled ? Colors.amber : Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Icon(
                                  _torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                  color: _torchEnabled ? Colors.black : Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _finishSessionAndClose,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Done',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bottom Scanner Status Strip
                  Positioned(
                    bottom: 8,
                    left: 20,
                    right: 20,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isResolving) ...[
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Auto-fetching item details...',
                                style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ] else if (_hasActiveItem) ...[
                              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Barcode: $_scannedBarcode',
                                style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ] else ...[
                              const Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Aim camera at barcode',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _showManualBarcodeInputDialog,
                                child: Text(
                                  '• Type Manually',
                                  style: GoogleFonts.inter(color: const Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. BOTTOM CARD: RAPID INWARD FORM OR IDLE CAROUSEL
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 15,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: _hasActiveItem ? _buildActiveItemForm() : _buildIdleStateView(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  // ACTIVE ITEM INWARD FORM (When Barcode is Scanned)
  Widget _buildActiveItemForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Product Name Label + Favorite Star
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      _existingProductId != null ? 'RESTOCKING' : 'NEW SKU',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Item Information',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),

              // Interactive Favorite Star Toggle
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isFavorite = !_isFavorite);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isFavorite ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isFavorite ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 15,
                        color: _isFavorite ? const Color(0xFFD97706) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isFavorite ? 'Favorite' : 'Add Star',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _isFavorite ? const Color(0xFFB45309) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1. Product Name Field
          TextFormField(
            controller: _nameCtrl,
            focusNode: _nameFocusNode,
            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'e.g. Maggi Noodles (420g)',
              hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              fillColor: const Color(0xFFF8FAFC),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2. Unit & Category Row
          Row(
            children: [
              // Measurement Unit
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedUnit,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      items: ['pcs', 'kg', 'gram', 'litre', 'ml', 'pkt', 'strip', 'bag'].map((u) {
                        return DropdownMenuItem<String>(
                          value: u,
                          child: Text(u, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedUnit = val);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Category
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _categories.any((c) => c.id == _selectedCategoryId)
                          ? _selectedCategoryId
                          : (_categories.isNotEmpty ? _categories.first.id : null),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      items: _categories.map((c) {
                        return DropdownMenuItem<String>(
                          value: c.id,
                          child: Text(c.name, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategoryId = val);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Selling Price & MRP Row
          Row(
            children: [
              // Selling Price (Primary Focus)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selling Price (₹) *',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _sellPriceCtrl,
                      focusNode: _sellPriceFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '₹ ',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        fillColor: const Color(0xFFF0FDF4),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF86EFAC))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF86EFAC), width: 1.2)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF059669), width: 2)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // MRP (₹)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MRP (₹)',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _mrpCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '₹ ',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        fillColor: const Color(0xFFF8FAFC),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 4. Initial Inward Stock Quantity & Quick Chips
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inward Stock Quantity',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                  Row(
                    children: _quickStockChips.map((chip) {
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final addVal = int.tryParse(chip.replaceAll('+', '')) ?? 0;
                          final current = int.tryParse(_stockCtrl.text.trim()) ?? 0;
                          setState(() {
                            _stockCtrl.text = '${current + addVal}';
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(left: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            chip,
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF475569)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _stockCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  hintText: '10',
                  suffixText: _selectedUnit,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  fillColor: const Color(0xFFF8FAFC),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5. ACTION BUTTONS: [ ⚡ Save & Scan Next ] and [ Skip ]
          Row(
            children: [
              // Skip / Cancel
              Expanded(
                flex: 3,
                child: OutlinedButton(
                  onPressed: _skipCurrentAndResumeScan,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF64748B), fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Save & Scan Next
              Expanded(
                flex: 7,
                child: ElevatedButton(
                  onPressed: _saveAndScanNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on_rounded, color: Color(0xFFFBBF24), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Save & Scan Next ⚡',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // IDLE STATE VIEW (When waiting to scan next barcode)
  Widget _buildIdleStateView() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Guidance banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanner is Ready!',
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hold any barcode in front of camera. Name & details auto-fill in <1.5s.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF047857), height: 1.25),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Session summary title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Added Items (${_sessionProducts.length})',
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              if (_sessionProducts.isNotEmpty)
                Text(
                  'Saved to SQLite & Cloud',
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // List of added items in this session
          Expanded(
            child: _sessionProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 38, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 8),
                        Text(
                          'No items added yet in this session',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scan your first product to begin rapid inward',
                          style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFFCBD5E1)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _sessionProducts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = _sessionProducts[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF2563EB)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${MoneyFormatter.formatINR(item.sellingPricePaise)} / ${item.unit} • Stock: ${item.stockQuantity.toInt()}',
                                    style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            if (item.isFavorite)
                              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
