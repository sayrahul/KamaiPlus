import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/app_validators.dart';
import '../../services/soundbox_service.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/thermal_printer_service.dart';
import 'pos_item_edit_modal.dart';

class PosCheckoutModal extends StatefulWidget {
  final List<CartItemModel> cartItems;
  final CustomerModel? selectedCustomer;
  final List<CustomerModel> allCustomers;
  final String activeBillTitle;
  final int activeBillTabNumber;
  final Function(CartItemModel item, int newQty) onUpdateQuantity;
  final Function(CartItemModel item) onRemoveItem;
  final Function() onClearCart;
  final Function() onHoldBill;
  final Function(CustomerModel? customer) onCustomerChanged;
  final Function() onSaleCompleted;

  const PosCheckoutModal({
    super.key,
    required this.cartItems,
    this.selectedCustomer,
    required this.allCustomers,
    required this.activeBillTitle,
    this.activeBillTabNumber = 1,
    required this.onUpdateQuantity,
    required this.onRemoveItem,
    required this.onClearCart,
    required this.onHoldBill,
    required this.onCustomerChanged,
    required this.onSaleCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CartItemModel> cartItems,
    CustomerModel? selectedCustomer,
    required List<CustomerModel> allCustomers,
    required String activeBillTitle,
    int activeBillTabNumber = 1,
    required Function(CartItemModel item, int newQty) onUpdateQuantity,
    required Function(CartItemModel item) onRemoveItem,
    required Function() onClearCart,
    required Function() onHoldBill,
    required Function(CustomerModel? customer) onCustomerChanged,
    required Function() onSaleCompleted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PosCheckoutModal(
        cartItems: cartItems,
        selectedCustomer: selectedCustomer,
        allCustomers: allCustomers,
        activeBillTitle: activeBillTitle,
        activeBillTabNumber: activeBillTabNumber,
        onUpdateQuantity: onUpdateQuantity,
        onRemoveItem: onRemoveItem,
        onClearCart: onClearCart,
        onHoldBill: onHoldBill,
        onCustomerChanged: onCustomerChanged,
        onSaleCompleted: onSaleCompleted,
      ),
    );
  }

  @override
  State<PosCheckoutModal> createState() => _PosCheckoutModalState();
}

class _PosCheckoutModalState extends State<PosCheckoutModal> {
  static const _btChannel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  CustomerModel? _currentCustomer;
  String _paymentMode = 'cash'; // 'cash', 'upi', 'credit', 'split'

  // Cash Tendered state
  late TextEditingController _cashTenderedController;

  // Bill Discount state
  String _billDiscountType = 'flat'; // 'flat' | 'percentage'
  final TextEditingController _billDiscountController = TextEditingController();

  // Customer search
  final TextEditingController _customerSearchController = TextEditingController();
  bool _isSearchingCustomer = false;
  List<CustomerModel> _filteredCustomers = [];

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentCustomer = widget.selectedCustomer;
    final totalRupees = (grossCartPaise / 100.0).ceil();
    _cashTenderedController = TextEditingController(text: totalRupees.toString());
  }

  @override
  void dispose() {
    _cashTenderedController.dispose();
    _billDiscountController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  int get grossCartPaise {
    int total = 0;
    for (var item in widget.cartItems) {
      total += item.grossTotalPaise;
    }
    return total;
  }

  int get billDiscountPaise {
    final disc = double.tryParse(_billDiscountController.text) ?? 0.0;
    if (disc <= 0) return 0;
    if (_billDiscountType == 'percentage') {
      final pct = disc.clamp(0.0, 100.0);
      return (grossCartPaise * pct / 100.0).round();
    } else {
      final flatPaise = (disc * 100.0).round();
      return flatPaise.clamp(0, grossCartPaise);
    }
  }

  int get grandTotalPaise {
    return (grossCartPaise - billDiscountPaise).clamp(0, grossCartPaise);
  }

  // Tax breakdown (included in retail gross)
  int get calculatedGstPaise {
    // Standard estimated GST component included in retail sales
    return (grandTotalPaise * 0.05).round(); // ~5% blended rate for display
  }

  int get subtotalBeforeGstPaise {
    return grandTotalPaise - calculatedGstPaise;
  }

  List<int> _getQuickTenderChips() {
    final totalRupees = (grandTotalPaise / 100.0).ceil();
    final List<int> chips = [totalRupees];

    final standardNotes = [50, 100, 200, 500, 1000, 2000];
    for (final note in standardNotes) {
      if (!chips.contains(note)) {
        chips.add(note);
      }
    }
    return chips;
  }

  void _onCustomerSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearchingCustomer = false;
        _filteredCustomers = [];
      });
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _isSearchingCustomer = true;
      _filteredCustomers = widget.allCustomers.where((c) {
        return c.name.toLowerCase().contains(q) || c.phone.contains(q);
      }).toList();
    });
  }

  void _selectCustomer(CustomerModel cust) {
    setState(() {
      _currentCustomer = cust;
      _isSearchingCustomer = false;
      _customerSearchController.clear();
    });
    widget.onCustomerChanged(cust);
  }

  void _showNewCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add New Customer',
          style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Customer Name *',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number (Optional)',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Customer name is required'),
                    backgroundColor: Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              final rawPhone = phoneCtrl.text.trim();
              String cleanPhone = '';
              if (rawPhone.isNotEmpty) {
                final phoneErr = AppValidators.validatePhone(rawPhone);
                if (phoneErr != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(phoneErr),
                      backgroundColor: const Color(0xFFDC2626),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                cleanPhone = AppValidators.cleanPhone(rawPhone);
              }

              final newCust = CustomerModel(
                id: const Uuid().v4(),
                businessId: FirestoreSyncService.instance.activeBusinessId,
                name: name,
                phone: cleanPhone,
              );
              await LocalDatabase.instance.upsertCustomer(newCust);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
              }
              if (mounted) {
                _selectCustomer(newCust);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: const Color(0xFF0F172A),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save & Select', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCompleteSale() async {
    if (widget.cartItems.isEmpty) return;

    if (_paymentMode == 'credit' && _currentCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or add a Customer above to record Credit (Udhar)'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final bizId = FirestoreSyncService.instance.activeBusinessId;

      final sale = await LocalDatabase.instance.processPosBill(
        businessId: bizId,
        cartItems: widget.cartItems,
        paymentMethod: _paymentMode,
        customer: _currentCustomer,
        discountPaise: billDiscountPaise,
      );

      // Soundbox Voice announcement
      await SoundboxService.instance.announceHindiPayment(
        grandTotalPaise,
        paymentMethod: _paymentMode.toUpperCase(),
      );

      // Push to cloud in background
      FirestoreSyncService.instance.pushSaleToCloud(sale);

      // Auto-print receipt if configured
      _autoPrintReceipt(sale);

      setState(() => _isProcessing = false);

      if (mounted) {
        Navigator.of(context).pop(); // Close checkout sheet
        _showSaleCelebrationDialog(sale);
        widget.onSaleCompleted();
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving sale: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _autoPrintReceipt(SaleModel sale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printerAddress = prefs.getString('printer_mac_address');
      final is80mm = prefs.getBool('printer_is_80mm') ?? false;
      final storeName = prefs.getString('business_name') ?? 'KamaiPlus Store';

      if (printerAddress != null && printerAddress.isNotEmpty) {
        final bytes = ThermalPrinterService.generateReceiptBytes(
          sale: sale,
          storeName: storeName,
          is80mm: is80mm,
          kickCashDrawer: _paymentMode == 'cash',
        );

        await _btChannel.invokeMethod('printBytes', {
          'address': printerAddress,
          'bytes': bytes,
        });
      }
    } catch (_) {}
  }

  void _showSaleCelebrationDialog(SaleModel sale) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, size: 56, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 16),
            Text(
              'Sale Completed!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Invoice: ${sale.invoiceNumber}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '₹${(sale.totalAmountPaise / 100.0).toStringAsFixed(2)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBF24),
                  foregroundColor: const Color(0xFF0F172A),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Done / New Bill',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalItemsCount = widget.cartItems.fold<int>(0, (sum, it) => sum + it.quantity.toInt());
    final cashTenderedVal = double.tryParse(_cashTenderedController.text) ?? 0.0;
    final grandTotalRupees = grandTotalPaise / 100.0;
    final returnChangeRupees = cashTenderedVal - grandTotalRupees;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 16, top: 16, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'POS Checkout — ${widget.activeBillTitle}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 22, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Multi-Bill Tabs Pill
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Bill #${widget.activeBillTabNumber}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFBBF24),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$totalItemsCount',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: widget.onHoldBill,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            child: const Icon(Icons.add, size: 18, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Customer Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CUSTOMER',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      GestureDetector(
                        onTap: _showNewCustomerDialog,
                        child: Row(
                          children: [
                            const Icon(Icons.person_add_alt_1, size: 14, color: Color(0xFF2563EB)),
                            const SizedBox(width: 4),
                            Text(
                              '+ New Customer',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (_currentCustomer != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_circle, size: 24, color: Color(0xFF2563EB)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentCustomer!.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E3A8A),
                                  ),
                                ),
                                if (_currentCustomer!.phone.isNotEmpty)
                                  Text(
                                    _currentCustomer!.phone,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: const Color(0xFF3B82F6),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
                            onPressed: () {
                              setState(() => _currentCustomer = null);
                              widget.onCustomerChanged(null);
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: [
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _customerSearchController,
                                  onChanged: _onCustomerSearch,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search by name or any phone digits (e.g. 7711)...',
                                    hintStyle: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isSearchingCustomer && _filteredCustomers.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(maxHeight: 140),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredCustomers.length,
                              itemBuilder: (ctx, i) {
                                final c = _filteredCustomers[i];
                                final isUdhar = c.currentBalancePaise > 0;
                                final isAdvance = c.currentBalancePaise < 0;
                                final balanceAbsPaise = c.currentBalancePaise.abs();
                                final balanceText = isUdhar
                                    ? '₹${(balanceAbsPaise / 100.0).toStringAsFixed(0)} Baki'
                                    : isAdvance
                                        ? '₹${(balanceAbsPaise / 100.0).toStringAsFixed(0)} Advance'
                                        : '₹0 Clear';
                                final badgeBg = isUdhar
                                    ? const Color(0xFFFEE2E2)
                                    : isAdvance
                                        ? const Color(0xFFECFDF5)
                                        : const Color(0xFFF1F5F9);
                                final badgeColor = isUdhar
                                    ? const Color(0xFFDC2626)
                                    : isAdvance
                                        ? const Color(0xFF059669)
                                        : const Color(0xFF64748B);

                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFFEFF6FF),
                                    child: Text(
                                      c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF2563EB)),
                                    ),
                                  ),
                                  title: Text(c.name, style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  subtitle: Text(c.phone, style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: const Color(0xFF64748B))),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badgeBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      balanceText,
                                      style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w700, color: badgeColor),
                                    ),
                                  ),
                                  onTap: () => _selectCustomer(c),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),

                  // 3. Cart Items Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CART ITEMS ($totalItemsCount)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: widget.onHoldBill,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.pause_circle_outline, size: 13, color: Color(0xFFD97706)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Hold Bill',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: widget.onClearCart,
                            child: Text(
                              'Clear',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Cart Item Rows
                  if (widget.cartItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Text(
                        'No items in cart',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  else
                    ...widget.cartItems.map((item) {
                      final itemPriceRupees = item.unitPricePaise / 100.0;
                      final itemTotalRupees = item.grossTotalPaise / 100.0;
                      final unitDisplay = item.product.unit.isNotEmpty ? item.product.unit : 'packet';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.product.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '₹${itemTotalRupees.toStringAsFixed(2)}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '₹${itemPriceRupees.toStringAsFixed(2)} × ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} $unitDisplay',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Row(
                                  children: [
                                    // Stepper [-]
                                    InkWell(
                                      onTap: () {
                                        if (item.quantity > 1) {
                                          widget.onUpdateQuantity(item, (item.quantity - 1).toInt());
                                        } else {
                                          widget.onRemoveItem(item);
                                        }
                                        setState(() {});
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.remove, size: 14, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString(),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Stepper [+]
                                    InkWell(
                                      onTap: () {
                                        widget.onUpdateQuantity(item, (item.quantity + 1).toInt());
                                        setState(() {});
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.add, size: 14, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Pencil Edit Icon -> opens PosItemEditModal
                                    InkWell(
                                      onTap: () {
                                        PosItemEditModal.show(
                                          context,
                                          cartItem: item,
                                          onUpdate: (updated) {
                                            setState(() {});
                                          },
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Trash Icon
                                    InkWell(
                                      onTap: () {
                                        widget.onRemoveItem(item);
                                        setState(() {});
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF94A3B8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),

                  // 4. Payment Mode Selector
                  Text(
                    'PAYMENT MODE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildPaymentModeButton('Cash', 'cash', Icons.money_rounded),
                      const SizedBox(width: 6),
                      _buildPaymentModeButton('UPI / QR', 'upi', Icons.qr_code_rounded),
                      const SizedBox(width: 6),
                      _buildPaymentModeButton('Credit', 'credit', Icons.menu_book_rounded),
                      const SizedBox(width: 6),
                      _buildPaymentModeButton('Split', 'split', Icons.splitscreen_rounded),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 5. Extended Cash Section (when Cash is active)
                  if (_paymentMode == 'cash') ...[
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
                                'Cash Tendered / Received:',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                              Container(
                                width: 90,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: TextField(
                                  controller: _cashTenderedController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.only(top: 8),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Tender Chips Row
                          Row(
                            children: [
                              Text(
                                'TENDER:  ',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _getQuickTenderChips().map((chip) {
                                      final isSelected = _cashTenderedController.text == chip.toString();
                                      final isExact = chip == (grandTotalPaise / 100.0).ceil();
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              _cashTenderedController.text = chip.toString();
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Text(
                                              isExact ? 'Exact ₹$chip' : '₹$chip',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected ? Colors.white : const Color(0xFF334155),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Return Change to Customer
                          if (returnChangeRupees > 0) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '💵 Return Change to Customer:',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF065F46),
                                    ),
                                  ),
                                  Text(
                                    '₹${returnChangeRupees.toStringAsFixed(2)}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF047857),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else if (_paymentMode == 'upi') ...[
                    // UPI Dynamic QR - High-End Merchant Counter Display
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'DYNAMIC BILL UPI QR',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF34D399),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF059669)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.volume_up_rounded, size: 12, color: Color(0xFF34D399)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Soundbox Ready',
                                      style: GoogleFonts.inter(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF34D399),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // QR White Canvas Container
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                QrImageView(
                                  data: 'upi://pay?pa=proventure@icici&pn=KamaiPlus+Store&am=${(grandTotalPaise / 100.0)}&cu=INR&tn=POS+Bill',
                                  version: QrVersions.auto,
                                  size: 150,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Scan to Pay Exact ₹${(grandTotalPaise / 100.0).toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Accepted UPI Apps Strip & Timer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'PhonePe • GPay • Paytm • BHIM',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 12, color: Color(0xFFFBBF24)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Valid: 05:00',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFFBBF24),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 6. Bill Discount Section
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.local_offer_outlined, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  'Bill Discount',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _billDiscountType = 'flat'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _billDiscountType == 'flat' ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '₹ Flat',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: _billDiscountType == 'flat' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _billDiscountType = 'percentage'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _billDiscountType == 'percentage' ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '% Percent',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: _billDiscountType == 'percentage' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Text(
                                _billDiscountType == 'flat' ? '₹ ' : '% ',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _billDiscountController,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. 50',
                                    hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8)),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 7. Totals Breakdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtotal',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '₹${(subtotalBeforeGstPaise / 100.0).toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total GST',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '+₹${(calculatedGstPaise / 100.0).toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (billDiscountPaise > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Bill Discount',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        Text(
                          '-₹${(billDiscountPaise / 100.0).toStringAsFixed(2)}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'GRAND TOTAL',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '₹${(grandTotalPaise / 100.0).toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 8. Complete Sale Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleCompleteSale,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFBBF24),
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.attach_money_rounded, size: 20, color: Color(0xFF0F172A)),
                                const SizedBox(width: 6),
                                Text(
                                  'Complete Sale & Generate Bill',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentModeButton(String label, String mode, IconData icon) {
    final isSelected = _paymentMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _paymentMode = mode);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
