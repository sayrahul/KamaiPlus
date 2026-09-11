import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/app_validators.dart';
import '../../services/soundbox_service.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/app_printer_service.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/constants/business_vertical_config.dart';
import 'pos_item_edit_modal.dart';
import 'sale_completed_modal.dart';
import '../common/in_app_notification.dart';
import '../../services/upi_payment_detector_service.dart';

class PosCheckoutModal extends StatefulWidget {
  final List<CartItemModel> cartItems;
  final CustomerModel? selectedCustomer;
  final List<CustomerModel> allCustomers;
  final String activeBillTitle;
  final int activeBillTabNumber;
  final List<CartTabModel>? tabs;
  final int activeTabIndex;
  final Function(int index)? onSwitchTab;
  final Function()? onAddNewBill;
  final Function(int index)? onCloseTab;
  final Function(CartItemModel item, int newQty) onUpdateQuantity;
  final Function(CartItemModel item) onRemoveItem;
  final Function() onClearCart;
  final Function() onHoldBill;
  final Function(CustomerModel? customer) onCustomerChanged;
  final Function() onSaleCompleted;
  final bool autoOpenCustomerDropdown;
  final bool autoOpenSplit;

  const PosCheckoutModal({
    super.key,
    required this.cartItems,
    this.selectedCustomer,
    required this.allCustomers,
    required this.activeBillTitle,
    this.activeBillTabNumber = 1,
    this.tabs,
    this.activeTabIndex = 0,
    this.onSwitchTab,
    this.onAddNewBill,
    this.onCloseTab,
    required this.onUpdateQuantity,
    required this.onRemoveItem,
    required this.onClearCart,
    required this.onHoldBill,
    required this.onCustomerChanged,
    required this.onSaleCompleted,
    this.autoOpenCustomerDropdown = false,
    this.autoOpenSplit = false,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CartItemModel> cartItems,
    CustomerModel? selectedCustomer,
    required List<CustomerModel> allCustomers,
    required String activeBillTitle,
    int activeBillTabNumber = 1,
    List<CartTabModel>? tabs,
    int activeTabIndex = 0,
    Function(int index)? onSwitchTab,
    Function()? onAddNewBill,
    Function(int index)? onCloseTab,
    required Function(CartItemModel item, int newQty) onUpdateQuantity,
    required Function(CartItemModel item) onRemoveItem,
    required Function() onClearCart,
    required Function() onHoldBill,
    required Function(CustomerModel? customer) onCustomerChanged,
    required Function() onSaleCompleted,
    bool autoOpenCustomerDropdown = false,
    bool autoOpenSplit = false,
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
        tabs: tabs,
        activeTabIndex: activeTabIndex,
        onSwitchTab: onSwitchTab,
        onAddNewBill: onAddNewBill,
        onCloseTab: onCloseTab,
        onUpdateQuantity: onUpdateQuantity,
        onRemoveItem: onRemoveItem,
        onClearCart: onClearCart,
        onHoldBill: onHoldBill,
        onCustomerChanged: onCustomerChanged,
        onSaleCompleted: onSaleCompleted,
        autoOpenCustomerDropdown: autoOpenCustomerDropdown,
        autoOpenSplit: autoOpenSplit,
      ),
    );
  }

  @override
  State<PosCheckoutModal> createState() => _PosCheckoutModalState();
}

class _PosCheckoutModalState extends State<PosCheckoutModal> {
  late int _currentTabIndex;
  CustomerModel? _currentCustomer;
  String _paymentMode = 'cash'; // 'cash', 'upi', 'credit', 'split'

  // Cash Tendered state
  late TextEditingController _cashTenderedController;

  // Split payment state
  late TextEditingController _splitCashController;
  late TextEditingController _splitUpiController;
  late TextEditingController _splitCreditController;

  // Bill Discount state
  String _billDiscountType = 'flat'; // 'flat' | 'percentage'
  final TextEditingController _billDiscountController = TextEditingController();
  bool _isDiscountExpanded = false;

  // Customer search
  final TextEditingController _customerSearchController = TextEditingController();
  bool _isSearchingCustomer = false;
  List<CustomerModel> _filteredCustomers = [];

  // Pharmacy: Doctor Management
  List<DoctorModel> _doctors = [];
  DoctorModel? _selectedDoctor;

  // Restaurant: Table Selection
  String _selectedTable = 'Takeaway';

  StoreProfileModel? _storeProfile;

  bool _isProcessing = false;

  // UPI Auto-Detection State
  bool _isUpiPaymentDetected = false;
  DetectedPaymentEvent? _detectedUpiEvent;
  bool _hasNotificationAccess = true;
  bool _soundboxAnnouncedForUpi = false;

  List<CartItemModel> get currentCartItems {
    if (widget.tabs != null && widget.tabs!.isNotEmpty) {
      if (_currentTabIndex < widget.tabs!.length) {
        return widget.tabs![_currentTabIndex].items.values.toList();
      }
    }
    return widget.cartItems;
  }

  String get currentBillTitle {
    if (widget.tabs != null && widget.tabs!.isNotEmpty) {
      if (_currentTabIndex < widget.tabs!.length) {
        return widget.tabs![_currentTabIndex].name;
      }
    }
    return widget.activeBillTitle;
  }

  int get currentBillNumber {
    if (widget.tabs != null && widget.tabs!.isNotEmpty) {
      if (_currentTabIndex < widget.tabs!.length) {
        return widget.tabs![_currentTabIndex].number;
      }
    }
    return widget.activeBillTabNumber;
  }

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.activeTabIndex;
    if (widget.tabs != null && widget.tabs!.isNotEmpty && _currentTabIndex < widget.tabs!.length) {
      _currentCustomer = widget.tabs![_currentTabIndex].customer ?? widget.selectedCustomer;
    } else {
      _currentCustomer = widget.selectedCustomer;
    }

    final totalRupees = (grossCartPaise / 100.0).ceil();
    _cashTenderedController = TextEditingController(text: totalRupees.toString());

    final half = (totalRupees / 2).floor();
    final other = totalRupees - half;
    _splitCashController = TextEditingController(text: half.toString());
    _splitUpiController = TextEditingController(text: other.toString());
    _splitCreditController = TextEditingController(text: '0');

    if (widget.autoOpenCustomerDropdown) {
      _isSearchingCustomer = true;
      _filteredCustomers = widget.allCustomers;
    }
    if (widget.autoOpenSplit) {
      _paymentMode = 'split';
    }

    _loadDoctors();
    _loadStoreProfile();
    _checkNotificationAccess();
    if (_paymentMode == 'upi') {
      _startUpiPaymentListening();
    }
  }

  Future<void> _checkNotificationAccess() async {
    try {
      final granted = await UpiPaymentDetectorService.instance.isNotificationAccessGranted();
      if (mounted) {
        setState(() => _hasNotificationAccess = granted);
      }
    } catch (_) {}
  }

  void _startUpiPaymentListening() {
    if (grandTotalPaise <= 0) return;
    _checkNotificationAccess();
    UpiPaymentDetectorService.instance.startListeningForBill(
      amountPaise: grandTotalPaise,
      onMatchedPayment: (event) async {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        setState(() {
          _isUpiPaymentDetected = true;
          _detectedUpiEvent = event;
          _soundboxAnnouncedForUpi = true;
        });

        // 1. Voice soundbox announcement in Hindi
        await SoundboxService.instance.announceHindiPayment(
          grandTotalPaise,
          paymentMethod: event.appName.toUpperCase(),
        );

        // 2. Exactly 1 second delay as requested by user
        await Future.delayed(const Duration(milliseconds: 1000));

        // 3. Auto complete sale and launch Success modal
        if (mounted && !_isProcessing) {
          _handleCompleteSale();
        }
      },
    );
  }

  void _stopUpiPaymentListening() {
    UpiPaymentDetectorService.instance.stopListening();
  }

  Future<void> _loadStoreProfile() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() => _storeProfile = p);
      }
    } catch (_) {}
  }

  String get _activeUpiVpa {
    final v = _storeProfile?.upiVpa.trim();
    if (v != null && v.isNotEmpty) return v;
    return '';
  }

  String get _activeStoreName {
    final n = _storeProfile?.storeName.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'KamaiPlus Store';
  }

  Future<void> _loadDoctors() async {
    try {
      final docs = await LocalDatabase.instance.getDoctors();
      if (mounted) {
        setState(() {
          _doctors = docs;
          if (_selectedDoctor == null && docs.isNotEmpty) {
            _selectedDoctor = docs.first;
          }
        });
      }
    } catch (_) {}
  }

  void _switchToTab(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentTabIndex = index;
      if (widget.tabs != null && index < widget.tabs!.length) {
        _currentCustomer = widget.tabs![index].customer;
      }
      _recalcForActiveTab();
    });
    widget.onSwitchTab?.call(index);
  }

  void _recalcForActiveTab() {
    final totalRupees = (grossCartPaise / 100.0).ceil();
    _cashTenderedController.text = totalRupees.toString();
    final half = (totalRupees / 2).floor();
    final other = totalRupees - half;
    _splitCashController.text = half.toString();
    _splitUpiController.text = other.toString();
    _splitCreditController.text = '0';
    _billDiscountController.clear();
    if (_paymentMode == 'upi') {
      _startUpiPaymentListening();
    }
  }

  @override
  void dispose() {
    _stopUpiPaymentListening();
    _cashTenderedController.dispose();
    _splitCashController.dispose();
    _splitUpiController.dispose();
    _splitCreditController.dispose();
    _billDiscountController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  int get splitCashPaise {
    final val = double.tryParse(_splitCashController.text) ?? 0.0;
    return (val * 100).round();
  }

  int get splitUpiPaise {
    final val = double.tryParse(_splitUpiController.text) ?? 0.0;
    return (val * 100).round();
  }

  int get splitCreditPaise {
    final val = double.tryParse(_splitCreditController.text) ?? 0.0;
    return (val * 100).round();
  }

  int get totalSplitPaise => splitCashPaise + splitUpiPaise + splitCreditPaise;
  int get splitDifferencePaise => grandTotalPaise - totalSplitPaise;
  bool get isSplitBalanced => totalSplitPaise == grandTotalPaise;

  int get grossCartPaise {
    int total = 0;
    for (var item in currentCartItems) {
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
    final q = query.trim().toLowerCase();
    setState(() {
      _isSearchingCustomer = true;
      if (q.isEmpty) {
        _filteredCustomers = widget.allCustomers;
      } else {
        _filteredCustomers = widget.allCustomers.where((c) {
          return c.name.toLowerCase().contains(q) || c.phone.contains(q);
        }).toList();
      }
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
                InAppNotification.error('Customer name is required', context: context);
                return;
              }

              // Check Free plan customer limit (100 customers)
              final profile = await LocalDatabase.instance.getStoreProfile();
              if (!mounted) return;
              if (!profile.isPro && widget.allCustomers.length >= 100) {
                if (ctx.mounted) Navigator.of(ctx).pop();
                _showCustomerLimitReachedDialog();
                return;
              }

              final rawPhone = phoneCtrl.text.trim();
              String cleanPhone = '';
              if (rawPhone.isNotEmpty) {
                final phoneErr = AppValidators.validatePhone(rawPhone);
                if (phoneErr != null) {
                  InAppNotification.error(phoneErr, context: context);
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

  void _showCustomerLimitReachedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Customer Limit Reached',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          'KamaiPlus Free plan allows up to 100 customer ledgers.\n\nUpgrade to KamaiPlus Pro for Unlimited Customer Khata, 1-Click WhatsApp Reminders, and Multi-Device Sync.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushNamed(context, '/settings');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Upgrade to Pro', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showAddDoctorDialog() {
    final nameCtrl = TextEditingController();
    final qualCtrl = TextEditingController();
    final regCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.medical_services_rounded, color: Color(0xFF2563EB), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Add Doctor (Rx)',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Doctor Name *',
                hintText: 'e.g. Dr. Rajesh Sharma',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qualCtrl,
              decoration: InputDecoration(
                labelText: 'Degree / Specialty',
                hintText: 'e.g. MBBS, MD (General Medicine)',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: regCtrl,
              decoration: InputDecoration(
                labelText: 'Registration No. (Optional)',
                hintText: 'e.g. MCI-12345',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              final rawName = nameCtrl.text.trim();
              if (rawName.isEmpty) return;
              final name = rawName.startsWith('Dr.') ? rawName : 'Dr. $rawName';
              final doc = DoctorModel(
                id: const Uuid().v4(),
                businessId: FirestoreSyncService.instance.activeBusinessId,
                name: name,
                qualification: qualCtrl.text.trim().isNotEmpty ? qualCtrl.text.trim() : null,
                registrationNumber: regCtrl.text.trim().isNotEmpty ? regCtrl.text.trim() : null,
              );
              await LocalDatabase.instance.upsertDoctor(doc);
              await _loadDoctors();
              setState(() => _selectedDoctor = doc);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save Doctor', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _deleteDoctor(DoctorModel doc) async {
    await LocalDatabase.instance.deleteDoctor(doc.id);
    if (_selectedDoctor?.id == doc.id) {
      _selectedDoctor = null;
    }
    await _loadDoctors();
  }

  Widget _buildDoctorSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.medical_services_outlined, size: 14, color: Color(0xFF16A34A)),
                  const SizedBox(width: 6),
                  Text(
                    'PRESCRIBING DOCTOR (Rx)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _showAddDoctorDialog,
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF2563EB)),
                    const SizedBox(width: 4),
                    Text(
                      '+ Add Doctor',
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
          const SizedBox(height: 8),
          if (_doctors.isEmpty)
            InkWell(
              onTap: _showAddDoctorDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Text(
                      'No doctor saved. Tap "+ Add Doctor" to set doctor name',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...List.generate(_doctors.length, (i) {
                  final doc = _doctors[i];
                  final isSel = _selectedDoctor?.id == doc.id;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedDoctor = isSel ? null : doc;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF059669) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
                          width: isSel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSel ? Icons.check_circle_rounded : Icons.person_outline,
                            size: 14,
                            color: isSel ? Colors.white : const Color(0xFF475569),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            doc.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                          if (doc.qualification != null && doc.qualification!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${doc.qualification})',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: isSel ? Colors.white70 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _deleteDoctor(doc),
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: isSel ? Colors.white70 : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTableSection() {
    const tableOptions = [
      'Takeaway',
      'Table 1',
      'Table 2',
      'Table 3',
      'Table 4',
      'Table 5',
      'Table 6',
      'Table 7',
      'Table 8',
      'Table 9',
      'Table 10',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_restaurant_rounded, size: 14, color: Color(0xFFEA580C)),
                  const SizedBox(width: 6),
                  Text(
                    'TABLE / ORDER TYPE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: const Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedTable,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tableOptions.map((opt) {
                final isSel = _selectedTable == opt;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      opt,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                        color: isSel ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                    selected: isSel,
                    selectedColor: const Color(0xFFEA580C),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSel ? const Color(0xFFEA580C) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    onSelected: (val) {
                      if (val) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedTable = opt);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCompleteSale() async {
    if (currentCartItems.isEmpty) return;

    if (_paymentMode == 'credit' && _currentCustomer == null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select or add a customer for Credit (Udhar) bill',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_paymentMode == 'split') {
      if (!isSplitBalanced) {
        final diffRupees = (splitDifferencePaise / 100.0).abs().toStringAsFixed(2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              splitDifferencePaise > 0
                  ? 'Split total ₹${(totalSplitPaise / 100.0).toStringAsFixed(2)} is less than bill total ₹${(grandTotalPaise / 100.0).toStringAsFixed(2)} (₹$diffRupees remaining). Use Auto button.'
                  : 'Split total exceeds bill total by ₹$diffRupees. Please balance the amounts.',
            ),
            backgroundColor: const Color(0xFFEA580C),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (splitCreditPaise > 0 && _currentCustomer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select or add a Customer above for Udhar/Credit split portion'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      final bizId = FirestoreSyncService.instance.activeBusinessId;
      final activeType = BusinessVerticals.activeBusinessTypeNotifier.value;
      final vertical = BusinessVerticals.resolve(activeType);

      final sale = await LocalDatabase.instance.processPosBill(
        businessId: bizId,
        cartItems: currentCartItems,
        paymentMethod: _paymentMode,
        customer: _currentCustomer,
        doctorName: vertical.toggles.showDoctorPrescription ? _selectedDoctor?.name : null,
        tableNumber: vertical.toggles.showTableOrderType ? _selectedTable : null,
        discountPaise: billDiscountPaise,
        splitCashPaise: _paymentMode == 'split' ? splitCashPaise : (_paymentMode == 'cash' ? grandTotalPaise : 0),
        splitUpiPaise: _paymentMode == 'split' ? splitUpiPaise : (_paymentMode == 'upi' ? grandTotalPaise : 0),
        splitCreditPaise: _paymentMode == 'split' ? splitCreditPaise : (_paymentMode == 'credit' ? grandTotalPaise : 0),
      );

      // Soundbox Voice announcement (if not already announced during UPI auto-detect)
      if (!_soundboxAnnouncedForUpi) {
        await SoundboxService.instance.announceHindiPayment(
          grandTotalPaise,
          paymentMethod: _paymentMode == 'split' ? 'SPLIT' : _paymentMode.toUpperCase(),
        );
      }

      // Push to cloud in background
      FirestoreSyncService.instance.pushSaleToCloud(sale);

      // Auto-print receipt if configured
      _autoPrintReceipt(sale);

      _stopUpiPaymentListening();
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
      final autoPrint = prefs.getBool('auto_print_on_checkout') ?? false;
      if (autoPrint && mounted) {
        await AppPrinterService.printSale(
          context: context,
          sale: sale,
          showToast: false,
        );
      }
    } catch (_) {}
  }

  void _showSaleCelebrationDialog(SaleModel sale) {
    SaleCompletedModal.show(
      context,
      sale: sale,
      onNewBill: widget.onSaleCompleted,
    );
  }

  Widget _buildCheckoutDraftTabs() {
    final tabsList = widget.tabs ?? [
      CartTabModel(
        id: 'tab_1',
        name: widget.activeBillTitle,
        number: widget.activeBillTabNumber,
        items: {},
        customer: widget.selectedCustomer,
      ),
    ];

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 14),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...List.generate(tabsList.length, (i) {
            final tab = tabsList[i];
            final isSel = i == _currentTabIndex;
            final count = tab.items.values.fold<int>(0, (sum, it) => sum + it.quantity.toInt());
            final amountPaise = tab.items.values.fold<int>(0, (sum, it) => sum + it.grossTotalPaise);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => _switchToTab(i),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSel ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                      width: isSel ? 1.5 : 1.0,
                    ),
                    boxShadow: isSel
                        ? [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSel
                              ? const Color(0xFF10B981)
                              : (count > 0 ? const Color(0xFF059669) : const Color(0xFF94A3B8)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                          color: isSel ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$count • ₹${(amountPaise / 100.0).toStringAsFixed(0)}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isSel ? const Color(0xFF34D399) : const Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                      if (tabsList.length > 1 && !isSel && widget.onCloseTab != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onCloseTab!(i);
                            setState(() {
                              if (_currentTabIndex >= tabsList.length) {
                                _currentTabIndex = tabsList.length - 1;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, size: 12, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),

          // + New Bill Button: pops modal and creates new bill on billing screen
          InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop();
              widget.onAddNewBill?.call();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 16, color: Color(0xFF059669)),
                  const SizedBox(width: 4),
                  Text(
                    'New Bill',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF059669),
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

  @override
  Widget build(BuildContext context) {
    final totalItemsCount = currentCartItems.fold<int>(0, (sum, it) => sum + it.quantity.toInt());
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
                  'POS Checkout — $currentBillTitle',
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
                  // 1. Multi-Bill Draft Tabs (Bill 1, Bill 2, +, etc.)
                  _buildCheckoutDraftTabs(),
                  const SizedBox(height: 16),

                  // 2. Customer Section
                  Builder(
                    builder: (context) {
                      final isCustomerCompulsoryMissing = (_paymentMode == 'credit' || (_paymentMode == 'split' && splitCreditPaise > 0)) && _currentCustomer == null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'CUSTOMER',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: isCustomerCompulsoryMissing ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                                ),
                              ),
                              GestureDetector(
                                onTap: _showNewCustomerDialog,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_add_alt_1,
                                      size: 14,
                                      color: isCustomerCompulsoryMissing ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '+ New Customer',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isCustomerCompulsoryMissing ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
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
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                _currentCustomer!.name,
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(0xFF1E3A8A),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (_currentCustomer!.isVip) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFEF3C7),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(color: const Color(0xFFF59E0B), width: 0.7),
                                                ),
                                                child: Text(
                                                  '👑 VIP',
                                                  style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                                                ),
                                              ),
                                            ],
                                          ],
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
                            Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: isCustomerCompulsoryMissing ? const Color(0xFFFEF2F2) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCustomerCompulsoryMissing
                                      ? const Color(0xFFEF4444)
                                      : (_isSearchingCustomer ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
                                  width: isCustomerCompulsoryMissing ? 1.5 : (_isSearchingCustomer ? 1.4 : 1.0),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    isCustomerCompulsoryMissing ? Icons.person_search_outlined : Icons.search,
                                    size: 18,
                                    color: isCustomerCompulsoryMissing ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _customerSearchController,
                                      onTap: () {
                                        setState(() {
                                          _isSearchingCustomer = true;
                                          if (_customerSearchController.text.trim().isEmpty) {
                                            _filteredCustomers = widget.allCustomers;
                                          } else {
                                            _onCustomerSearch(_customerSearchController.text);
                                          }
                                        });
                                      },
                                      onChanged: _onCustomerSearch,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      decoration: InputDecoration(
                                        hintText: isCustomerCompulsoryMissing
                                            ? 'Select or add customer for Credit (Udhar)...'
                                            : BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).placeholders.customerSearch,
                                        hintStyle: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: isCustomerCompulsoryMissing ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                                          fontWeight: isCustomerCompulsoryMissing ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  if (_isSearchingCustomer)
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _isSearchingCustomer = false;
                                          _customerSearchController.clear();
                                        });
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (_isSearchingCustomer)
                            Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: _filteredCustomers.isEmpty
                                ? Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'No matching customer found.\nTap "+ New Customer" above to add.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11.5,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _filteredCustomers.length,
                                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
                      );
                    },
                  ),

                  // Pharmacy Doctor or Restaurant Table Section
                  ValueListenableBuilder<String>(
                    valueListenable: BusinessVerticals.activeBusinessTypeNotifier,
                    builder: (context, activeType, _) {
                      final vertical = BusinessVerticals.resolve(activeType);
                      final isPharmacy = vertical.toggles.showDoctorPrescription;
                      final isRestaurant = vertical.toggles.showTableOrderType;

                      if (!isPharmacy && !isRestaurant) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          if (isPharmacy) _buildDoctorSection(),
                          if (isRestaurant) _buildTableSection(),
                        ],
                      );
                    },
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
                  if (currentCartItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_basket_outlined, size: 32, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 8),
                          Text(
                            '$currentBillTitle me abhi koi product nahi hai',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Products add karne ke liye modal close karein',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.add_shopping_cart, size: 16),
                            label: const Text('Add Products to Bill'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 230),
                      child: Scrollbar(
                        thumbVisibility: currentCartItems.length > 3,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const BouncingScrollPhysics(),
                          itemCount: currentCartItems.length,
                          itemBuilder: (context, idx) {
                            final item = currentCartItems[idx];
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
                          },
                        ),
                      ),
                    ),
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
                          const SizedBox(height: 12),

                          // Auto-Detect Live Radar or Notification Access Banner
                          if (!_isUpiPaymentDetected) ...[
                            if (!_hasNotificationAccess) ...[
                              InkWell(
                                onTap: () async {
                                  await UpiPaymentDetectorService.instance.openNotificationAccessSettings();
                                  await Future.delayed(const Duration(milliseconds: 600));
                                  _checkNotificationAccess();
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.notifications_active_rounded, size: 15, color: Color(0xFFD97706)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Enable Auto-Detect: Tap to grant Notification Access',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF92400E),
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFD97706)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF10B981),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Live Auto-Detect Active',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF34D399),
                                          ),
                                        ),
                                      ],
                                    ),
                                    InkWell(
                                      onTap: () {
                                        // Trigger instant test detection simulation
                                        UpiPaymentDetectorService.instance.simulatePayment(amountPaise: grandTotalPaise);
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.bolt_rounded, size: 11, color: Color(0xFF34D399)),
                                            const SizedBox(width: 2),
                                            Text(
                                              'Test Detect',
                                              style: GoogleFonts.inter(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF34D399),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],

                          if (_isUpiPaymentDetected)
                            // Green Animated Success Checkmark Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF064E3B),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF10B981), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 34,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '₹${(grandTotalPaise / 100.0).toStringAsFixed(2)} Received!',
                                    style: GoogleFonts.outfit(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Detected via ${_detectedUpiEvent?.appName ?? 'UPI'} • Auto-Completing Bill...',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFA7F3D0),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
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
                                    data: 'upi://pay?pa=$_activeUpiVpa&pn=${Uri.encodeComponent(_activeStoreName)}&am=${(grandTotalPaise / 100.0).toStringAsFixed(2)}&cu=INR&tn=POS+Bill',
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
                          if (_currentCustomer != null && _currentCustomer!.phone.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () async {
                                final phone = _currentCustomer!.phone.replaceAll(RegExp(r'\D'), '');
                                final cleanPhone = phone.length == 10 ? '91$phone' : phone;
                                final amountRupees = (grandTotalPaise / 100.0).toStringAsFixed(2);
                                final upiUri = 'upi://pay?pa=$_activeUpiVpa&pn=${Uri.encodeComponent(_activeStoreName)}&am=$amountRupees&cu=INR&tn=POS+Bill';
                                final text = Uri.encodeComponent(
                                  '🙏 Namaste ${_currentCustomer!.name} Ji!\n\n'
                                  'Aapka KamaiPlus Bill amount: ₹$amountRupees\n'
                                  'Direct 1-Tap UPI se pay karne ke liye niche link par click karein:\n'
                                  '$upiUri\n\n'
                                  'Payment hone par bill turant update ho jayega. Dhanyawad! ✨'
                                );
                                final url = Uri.parse('https://wa.me/$cleanPhone?text=$text');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF25D366), width: 1.2),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.send_rounded, size: 14, color: Color(0xFF25D366)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Send 1-Tap UPI Link to ${_currentCustomer!.name}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF25D366),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              '💡 Select customer above to send 1-Tap UPI WhatsApp pay link',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else if (_paymentMode == 'split') ...[
                    _buildSplitPaymentSection(),
                    const SizedBox(height: 14),
                  ],

                  // 6. Bill Discount Section (Space-Saving Expandable Dropdown)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: billDiscountPaise > 0 ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                        width: billDiscountPaise > 0 ? 1.4 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setState(() => _isDiscountExpanded = !_isDiscountExpanded),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.local_offer_outlined,
                                  size: 16,
                                  color: billDiscountPaise > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    billDiscountPaise > 0
                                        ? 'Discount: -${MoneyFormatter.formatINR(billDiscountPaise)} (${_billDiscountType == 'flat' ? '₹ Flat' : '${_billDiscountController.text}%'})'
                                        : 'Add Bill Discount / Coupon',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: billDiscountPaise > 0 ? FontWeight.w700 : FontWeight.w600,
                                      color: billDiscountPaise > 0 ? const Color(0xFF047857) : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                                if (billDiscountPaise > 0)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _billDiscountController.clear();
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Text(
                                        'Remove',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                  ),
                                Icon(
                                  _isDiscountExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: const Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isDiscountExpanded) ...[
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Type:',
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            onTap: () => setState(() => _billDiscountType = 'flat'),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _billDiscountType == 'flat' ? Colors.white : Colors.transparent,
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: _billDiscountType == 'flat'
                                                    ? [const BoxShadow(color: Color(0x0D000000), blurRadius: 2)]
                                                    : null,
                                              ),
                                              child: Text(
                                                '₹ Flat',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: _billDiscountType == 'flat' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                                ),
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => setState(() => _billDiscountType = 'percentage'),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _billDiscountType == 'percentage' ? Colors.white : Colors.transparent,
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: _billDiscountType == 'percentage'
                                                    ? [const BoxShadow(color: Color(0x0D000000), blurRadius: 2)]
                                                    : null,
                                              ),
                                              child: Text(
                                                '% Percent',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
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
                                            hintText: _billDiscountType == 'flat' ? 'Enter discount amount (e.g. 50)' : 'Enter discount percentage (e.g. 10)',
                                            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8)),
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
                        ],
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
          final prevMode = _paymentMode;
          setState(() {
            _paymentMode = mode;
            if (prevMode == 'upi' && mode != 'upi') {
              _stopUpiPaymentListening();
              _isUpiPaymentDetected = false;
              _soundboxAnnouncedForUpi = false;
            } else if (mode == 'upi' && prevMode != 'upi') {
              _isUpiPaymentDetected = false;
              _soundboxAnnouncedForUpi = false;
              _startUpiPaymentListening();
            }
            if (mode == 'split' && !isSplitBalanced) {
              final half = (grandTotalPaise / 200.0).floor();
              final other = (grandTotalPaise / 100.0) - half;
              _splitCashController.text = half.toString();
              _splitUpiController.text = other.toString();
              _splitCreditController.text = '0';
            }
          });
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

  Widget _buildSplitPaymentSection() {
    final grandTotalRupees = grandTotalPaise / 100.0;
    final diffRupees = splitDifferencePaise / 100.0;
    final isBalanced = isSplitBalanced;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBalanced ? const Color(0xFFA7F3D0) : const Color(0xFFFED7AA),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title + Balance Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.splitscreen_rounded, size: 16, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SPLIT PAYMENT AMOUNTS',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isBalanced ? const Color(0xFFECFDF5) : (diffRupees > 0 ? const Color(0xFFFFF7ED) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isBalanced ? const Color(0xFFA7F3D0) : (diffRupees > 0 ? const Color(0xFFFDBA74) : const Color(0xFFFECACA)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBalanced ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 13,
                      color: isBalanced ? const Color(0xFF059669) : (diffRupees > 0 ? const Color(0xFFEA580C) : const Color(0xFFDC2626)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isBalanced
                          ? 'Balanced'
                          : (diffRupees > 0 ? '₹${diffRupees.toStringAsFixed(2)} Left' : '₹${(-diffRupees).toStringAsFixed(2)} Extra'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isBalanced ? const Color(0xFF059669) : (diffRupees > 0 ? const Color(0xFFEA580C) : const Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. Cash Portion
          _buildSplitRow(
            icon: Icons.money_rounded,
            iconColor: const Color(0xFF059669),
            label: 'Cash Amount (₹)',
            controller: _splitCashController,
            onQuickAction: () {
              final rem = (grandTotalPaise - splitUpiPaise - splitCreditPaise).clamp(0, grandTotalPaise);
              setState(() {
                _splitCashController.text = (rem / 100.0).toStringAsFixed(0);
              });
            },
          ),
          const SizedBox(height: 10),

          // 2. UPI Portion
          _buildSplitRow(
            icon: Icons.qr_code_rounded,
            iconColor: const Color(0xFF0284C7),
            label: 'UPI / Online Amount (₹)',
            controller: _splitUpiController,
            onQuickAction: () {
              final rem = (grandTotalPaise - splitCashPaise - splitCreditPaise).clamp(0, grandTotalPaise);
              setState(() {
                _splitUpiController.text = (rem / 100.0).toStringAsFixed(0);
              });
            },
          ),
          const SizedBox(height: 10),

          // 3. Udhar / Credit Portion
          _buildSplitRow(
            icon: Icons.menu_book_rounded,
            iconColor: const Color(0xFFD97706),
            label: _currentCustomer != null
                ? 'Credit (Udhar) - ${_currentCustomer!.name} (₹)'
                : 'Credit / Udhar (Select Customer) (₹)',
            controller: _splitCreditController,
            onQuickAction: _currentCustomer != null
                ? () {
                    final rem = (grandTotalPaise - splitCashPaise - splitUpiPaise).clamp(0, grandTotalPaise);
                    setState(() {
                      _splitCreditController.text = (rem / 100.0).toStringAsFixed(0);
                    });
                  }
                : null,
            helperNote: _currentCustomer == null ? 'Requires customer selection above' : null,
          ),
          const SizedBox(height: 12),

          // Quick Split Helper Shortcuts
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildSplitShortcutChip('50% Cash + 50% UPI', () {
                final half = (grandTotalPaise / 200.0).floor();
                final other = (grandTotalPaise / 100.0) - half;
                setState(() {
                  _splitCashController.text = half.toString();
                  _splitUpiController.text = other.toString();
                  _splitCreditController.text = '0';
                });
              }),
              _buildSplitShortcutChip('All Cash', () {
                setState(() {
                  _splitCashController.text = (grandTotalPaise / 100.0).toString();
                  _splitUpiController.text = '0';
                  _splitCreditController.text = '0';
                });
              }),
              _buildSplitShortcutChip('All UPI', () {
                setState(() {
                  _splitCashController.text = '0';
                  _splitUpiController.text = (grandTotalPaise / 100.0).toString();
                  _splitCreditController.text = '0';
                });
              }),
              if (_currentCustomer != null)
                _buildSplitShortcutChip('All Udhar', () {
                  setState(() {
                    _splitCashController.text = '0';
                    _splitUpiController.text = '0';
                    _splitCreditController.text = (grandTotalPaise / 100.0).toString();
                  });
                }),
            ],
          ),

          const SizedBox(height: 10),
          // Total Calculation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bill Grand Total:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  '₹${grandTotalRupees.toStringAsFixed(2)}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required TextEditingController controller,
    VoidCallback? onQuickAction,
    String? helperNote,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (helperNote != null)
                  Text(
                    helperNote,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
          ),
          if (onQuickAction != null)
            InkWell(
              onTap: onQuickAction,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Auto',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2563EB),
                  ),
                ),
              ),
            ),
          Container(
            width: 85,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            alignment: Alignment.center,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitShortcutChip(String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
