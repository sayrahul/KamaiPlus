import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';

/// Modal bottom sheet for 1-Tap Low-Stock Radar & Wholesale WhatsApp Reorder.
/// Generates formatted purchase orders for wholesale distributors and agencies.
class LowStockReorderModal extends StatefulWidget {
  final List<ProductModel> initialProducts;
  final VoidCallback? onReorderDispatched;

  const LowStockReorderModal({
    super.key,
    required this.initialProducts,
    this.onReorderDispatched,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ProductModel> initialProducts,
    VoidCallback? onReorderDispatched,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LowStockReorderModal(
        initialProducts: initialProducts,
        onReorderDispatched: onReorderDispatched,
      ),
    );
  }

  @override
  State<LowStockReorderModal> createState() => _LowStockReorderModalState();
}

class _ReorderItemState {
  final ProductModel product;
  bool isSelected;
  int orderQty;

  _ReorderItemState({
    required this.product,
    this.isSelected = true,
    required this.orderQty,
  });
}

class _LowStockReorderModalState extends State<LowStockReorderModal> {
  late TextEditingController _supplierCtrl;
  late TextEditingController _phoneCtrl;
  final List<_ReorderItemState> _items = [];
  bool _showPreview = false;
  String _storeName = 'My Store';
  String _storePhone = '';

  @override
  void initState() {
    super.initState();
    _supplierCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _initItems();
    _loadStoreDetails();
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _initItems() {
    for (final p in widget.initialProducts) {
      if (p.isUnlimitedStock) continue;
      // Suggested order qty: round up to nearest dozen or box
      int suggested;
      if (p.stockQuantity <= 0) {
        suggested = 24;
      } else if (p.stockQuantity <= 5) {
        suggested = 12;
      } else {
        suggested = 6;
      }
      _items.add(_ReorderItemState(
        product: p,
        isSelected: true,
        orderQty: suggested,
      ));
    }
  }

  Future<void> _loadStoreDetails() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() {
          if (profile.storeName.isNotEmpty) _storeName = profile.storeName;
          if (profile.phone.isNotEmpty) _storePhone = profile.phone;
        });
      }
    } catch (_) {}
  }

  List<_ReorderItemState> get _selectedItems =>
      _items.where((i) => i.isSelected && i.orderQty > 0).toList();

  int get _totalSelectedUnits =>
      _selectedItems.fold(0, (sum, i) => sum + i.orderQty);

  int get _estimatedValuationPaise => _selectedItems.fold(0, (sum, i) {
        final cost = i.product.purchasePricePaise > 0
            ? i.product.purchasePricePaise
            : (i.product.sellingPricePaise * 0.8).round();
        return sum + (cost * i.orderQty);
      });

  List<String> get _supplierChips {
    final vert = BusinessVerticals.resolve(
        BusinessVerticals.activeBusinessTypeNotifier.value);
    switch (vert.id) {
      case 'pharmacy':
        return [
          'Zenith Pharma',
          'Apex Distributors',
          'Cipla Stockist',
          'Sun Pharma Agency',
          'Local Chemist Wholesaler'
        ];
      case 'restaurant':
        return [
          'Local Sabzi Mandi',
          'Amul Dairy',
          'Bakery Supplier',
          'Dry Fruits & Spices',
          'Local Grocery Vendor'
        ];
      case 'electronics':
        return [
          'City Tech Distributors',
          'Mobile Accessories Agency',
          'Cable & Parts Depot',
          'Wholesale Bazaar'
        ];
      default:
        return [
          'Metro Wholesale',
          'Hindustan Unilever',
          'Parle Agency',
          'Amul Dairy & FMCG',
          'ITC Distributor',
          'Local Mandi Vendor'
        ];
    }
  }

  String _generateWhatsAppOrderMessage() {
    final buffer = StringBuffer();
    final supplierName = _supplierCtrl.text.trim();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    buffer.writeln('📦 *WHOLESALE RESTOCK ORDER*');
    buffer.writeln('🏪 *$_storeName*');
    if (_storePhone.isNotEmpty) {
      buffer.writeln('📞 Contact: $_storePhone');
    }
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('------------------------------');

    if (supplierName.isNotEmpty) {
      buffer.writeln('Dear *$supplierName*,');
      buffer.writeln('Please dispatch the following restock items:');
    } else {
      buffer.writeln('Dear Supplier / Wholesaler,');
      buffer.writeln('Please dispatch the following restock items:');
    }
    buffer.writeln('');

    int index = 1;
    for (final item in _selectedItems) {
      final p = item.product;
      final cur = p.stockQuantity.toInt();
      buffer.writeln(
          '$index. *${p.name}* — ${item.orderQty} ${p.unit} (Current: $cur)');
      index++;
    }

    buffer.writeln('');
    buffer.writeln(
        '📊 *Total: ${_selectedItems.length} SKUs | $_totalSelectedUnits Units*');
    if (_estimatedValuationPaise > 0) {
      buffer.writeln(
          '💰 *Est. Value: ~${MoneyFormatter.formatINR(_estimatedValuationPaise)}*');
    }
    buffer.writeln('------------------------------');
    buffer.writeln('Please confirm dispatch & delivery timing. Thank you!');
    buffer.writeln('— Sent via KamaiPlus Retail POS');

    return buffer.toString();
  }

  Future<void> _dispatchWhatsApp() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 item to reorder.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final message = _generateWhatsAppOrderMessage();
    final rawPhone = _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final cleanPhone = rawPhone.length == 10 ? '91$rawPhone' : rawPhone;
    final encoded = Uri.encodeComponent(message);

    final Uri nativeWaUri = cleanPhone.isNotEmpty
        ? Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encoded')
        : Uri.parse('whatsapp://send?text=$encoded');

    final Uri webWaUri = cleanPhone.isNotEmpty
        ? Uri.parse('https://wa.me/$cleanPhone?text=$encoded')
        : Uri.parse('https://wa.me/?text=$encoded');

    bool launched = false;
    try {
      if (await canLaunchUrl(nativeWaUri)) {
        await launchUrl(nativeWaUri, mode: LaunchMode.externalApplication);
        launched = true;
      } else if (await canLaunchUrl(webWaUri)) {
        await launchUrl(webWaUri, mode: LaunchMode.externalApplication);
        launched = true;
      }
    } catch (_) {}

    if (!launched) {
      await Clipboard.setData(ClipboardData(text: message));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'WhatsApp app not detected. Purchase Order copied to Clipboard! 📋'),
            backgroundColor: Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        widget.onReorderDispatched?.call();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF10B981), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Restock order dispatched to WhatsApp for ${_selectedItems.length} items!'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _copyToClipboard() async {
    HapticFeedback.selectionClick();
    final message = _generateWhatsAppOrderMessage();
    await Clipboard.setData(ClipboardData(text: message));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Order text copied to clipboard!'),
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Column(
                children: [
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Image.asset(
                          'assets/images/whatsapp_logo.png',
                          width: 22,
                          height: 22,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.send_rounded,
                            color: Color(0xFF16A34A),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'WhatsApp Restock Order',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_selectedItems.length} SKUs',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Generate 1-Tap purchase order for wholesale distributor',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFF64748B), size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                children: [
                  // Supplier Selection Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DISTRIBUTOR / WHOLESALER DETAILS',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _supplierCtrl,
                                onChanged: (_) => setState(() {}),
                                style: GoogleFonts.inter(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Metro Wholesale / Agency',
                                  hintStyle: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFF94A3B8)),
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.store_outlined,
                                      size: 16, color: Color(0xFF64748B)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFCBD5E1)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                style: GoogleFonts.robotoMono(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  hintText: 'WhatsApp #',
                                  hintStyle: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8)),
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.phone_outlined,
                                      size: 15, color: Color(0xFF64748B)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFCBD5E1)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Quick Supplier Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: _supplierChips.map((name) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _supplierCtrl.text = name);
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text(
                                      name,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header with Select All toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ITEMS TO REORDER (${_selectedItems.length}/${_items.length})',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final allSelected =
                              _items.every((i) => i.isSelected);
                          setState(() {
                            for (var i in _items) {
                              i.isSelected = !allSelected;
                            }
                          });
                        },
                        child: Text(
                          _items.every((i) => i.isSelected)
                              ? 'Deselect All'
                              : 'Select All',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Low Stock Items List
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      child: Text(
                        'No low stock items found. All products are well stocked!',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    )
                  else
                    ..._items.map((item) => _buildReorderRow(item)),

                  const SizedBox(height: 14),

                  // Live Preview Toggle & Box
                  InkWell(
                    onTap: () =>
                        setState(() => _showPreview = !_showPreview),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.remove_red_eye_outlined,
                                  size: 15, color: Color(0xFF475569)),
                              const SizedBox(width: 6),
                              Text(
                                _showPreview
                                    ? 'Hide Message Preview'
                                    : 'Preview WhatsApp Message',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            _showPreview
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: const Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showPreview) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F6EA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Text(
                        _generateWhatsAppOrderMessage(),
                        style: GoogleFonts.robotoMono(
                          fontSize: 11,
                          color: const Color(0xFF14532D),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Fixed Bottom Summary & Action Bar
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Valuation & Counts
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORDER SUMMARY',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedItems.length} SKUs • $_totalSelectedUnits Units',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      if (_estimatedValuationPaise > 0)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'EST. VALUE (~)',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              MoneyFormatter.formatINR(_estimatedValuationPaise),
                              style: GoogleFonts.robotoMono(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Actions Row
                  Row(
                    children: [
                      // Copy Button
                      IconButton(
                        onPressed: _copyToClipboard,
                        tooltip: 'Copy Order Text',
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: const Icon(Icons.copy_rounded,
                              size: 18, color: Color(0xFF334155)),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // WhatsApp Dispatch Primary Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _dispatchWhatsApp,
                          icon: Image.asset(
                            'assets/images/whatsapp_logo.png',
                            width: 18,
                            height: 18,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          label: Text(
                            'Send via WhatsApp',
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReorderRow(_ReorderItemState item) {
    final p = item.product;
    final isZero = p.stockQuantity <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
      decoration: BoxDecoration(
        color: item.isSelected ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isSelected
              ? (isZero ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0))
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: item.isSelected,
            activeColor: const Color(0xFF16A34A),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              setState(() => item.isSelected = val ?? false);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: item.isSelected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isZero
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isZero
                            ? '0 OUT'
                            : '${p.stockQuantity.toInt()} left',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isZero
                              ? const Color(0xFFDC2626)
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cost: ${MoneyFormatter.formatINR(p.purchasePricePaise)}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Stepper & Quick Bump
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  if (item.orderQty > 1) {
                    HapticFeedback.selectionClick();
                    setState(() => item.orderQty--);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.remove_rounded,
                      size: 14, color: Color(0xFF475569)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${item.orderQty}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: item.isSelected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => item.orderQty++);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 14, color: Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 4),

              // Quick Bump +12 Chip
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => item.orderQty += 12);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '+12',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
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
}
