import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/database/local_database.dart';
import '../../services/soundbox_service.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/thermal_printer_service.dart';
import 'sale_completed_modal.dart';

class PaymentModal extends StatefulWidget {
  final List<CartItemModel> cartItems;
  final CustomerModel? selectedCustomer;
  final VoidCallback onBillCompleted;

  const PaymentModal({
    super.key,
    required this.cartItems,
    this.selectedCustomer,
    required this.onBillCompleted,
  });

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  static const _btChannel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  String _selectedMethod = 'upi'; // 'cash' | 'upi' | 'credit'
  bool _isProcessing = false;
  StoreProfileModel? _storeProfile;

  @override
  void initState() {
    super.initState();
    _loadStoreProfile();
  }

  Future<void> _loadStoreProfile() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _storeProfile = p);
    } catch (_) {}
  }

  int get totalPaise {
    int sum = 0;
    for (var item in widget.cartItems) {
      sum += item.grossTotalPaise;
    }
    return sum;
  }

  // Generates standard UPI payment URI
  String get upiPaymentUrl {
    final double rupees = totalPaise / 100.0;
    final vpa = _storeProfile?.upiVpa.trim();
    final activeVpa = (vpa != null && vpa.isNotEmpty) ? vpa : 'proventure@icici';
    final sName = _storeProfile?.storeName.trim();
    final activeName = (sName != null && sName.isNotEmpty) ? sName : 'KamaiPlus Store';
    return 'upi://pay?pa=$activeVpa&pn=${Uri.encodeComponent(activeName)}&am=${rupees.toStringAsFixed(2)}&cu=INR&tn=POS+Bill';
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);

    try {
      final bizId = FirestoreSyncService.instance.activeBusinessId;

      final sale = await LocalDatabase.instance.processPosBill(
        businessId: bizId,
        cartItems: widget.cartItems,
        paymentMethod: _selectedMethod,
        customer: widget.selectedCustomer,
      );

      // 1. Trigger Smart Soundbox Voice Announcement (Hindi)
      await SoundboxService.instance.announceHindiPayment(
        totalPaise,
        paymentMethod: _selectedMethod.toUpperCase(),
      );

      // 2. Push to Cloud Firestore in Background
      FirestoreSyncService.instance.pushSaleToCloud(sale);

      // 3. Auto-print if thermal printer is configured
      _autoPrintReceipt(sale);

      setState(() => _isProcessing = false);
      if (mounted) {
        Navigator.of(context).pop();
        SaleCompletedModal.show(
          context,
          sale: sale,
          onNewBill: widget.onBillCompleted,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving bill: $e'), backgroundColor: Colors.red),
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
          kickCashDrawer: _selectedMethod == 'cash',
        );

        await _btChannel.invokeMethod('printBytes', {
          'address': printerAddress,
          'bytes': bytes,
        });
      }
    } catch (_) {
      // Non-blocking silent catch for auto-print
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Payment Mode',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Payment Mode Tabs
          Row(
            children: [
              _buildMethodTab('upi', 'UPI QR', Icons.qr_code_scanner_outlined),
              const SizedBox(width: 8),
              _buildMethodTab('cash', 'Cash', Icons.payments_outlined),
              const SizedBox(width: 8),
              _buildMethodTab('credit', 'Udhar (Khata)', Icons.book_outlined),
            ],
          ),
          const SizedBox(height: 16),

          // Content based on method
          if (_selectedMethod == 'upi')
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: upiPaymentUrl,
                      version: QrVersions.auto,
                      size: 160.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan with any UPI App (GPay, PhonePe, Paytm)',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else if (_selectedMethod == 'cash')
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF0F172A)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Collect ${MoneyFormatter.formatINR(totalPaise)} physical cash. Drawer will kick automatically.',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            )
          else if (_selectedMethod == 'credit')
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFE11D48)),
                      const SizedBox(width: 8),
                      Text(
                        widget.selectedCustomer != null
                            ? 'Udhar Customer: ${widget.selectedCustomer!.name}'
                            : '⚠️ Please select a customer for Khata credit',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF9F1239)),
                      ),
                    ],
                  ),
                  if (widget.selectedCustomer != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Current Balance: ${MoneyFormatter.formatINR(widget.selectedCustomer!.currentBalancePaise)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C)),
                    ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Complete Button
          ElevatedButton(
            onPressed: (_isProcessing || (_selectedMethod == 'credit' && widget.selectedCustomer == null))
                ? null
                : _processPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isProcessing
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _selectedMethod == 'credit' ? 'Record Udhar & Complete' : 'Confirm & Print Receipt',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodTab(String method, String label, IconData icon) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedMethod = method),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF64748B)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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

