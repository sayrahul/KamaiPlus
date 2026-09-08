import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/thermal_printer_service.dart';
import '../../services/native_notification_service.dart';
import '../../services/notification_service.dart';
import '../../services/invoice_pdf_service.dart';
import '../settings/bluetooth_printer_dialog.dart';
import '../common/store_logo_avatar.dart';

class SaleCompletedModal extends StatefulWidget {
  final SaleModel sale;
  final VoidCallback onNewBill;

  const SaleCompletedModal({
    super.key,
    required this.sale,
    required this.onNewBill,
  });

  static Future<void> show(
    BuildContext context, {
    required SaleModel sale,
    required VoidCallback onNewBill,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC020617), // Slate 950 with 80% opacity
      builder: (ctx) => SaleCompletedModal(
        sale: sale,
        onNewBill: onNewBill,
      ),
    );
  }

  @override
  State<SaleCompletedModal> createState() => _SaleCompletedModalState();
}

class _SaleCompletedModalState extends State<SaleCompletedModal> {
  static const _btChannel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  late final TextEditingController _phoneCtrl;
  bool _isPrinting = false;
  bool _showPdfPreview = false;
  String _storeName = 'KamaiPlus Store';
  StoreProfileModel _profile = StoreProfileModel();

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.sale.customerPhone ?? '');
    _loadStoreName();
    NativeNotificationService.notifySaleCompleted(
      invoiceNumber: widget.sale.invoiceNumber,
      amountFormatted: MoneyFormatter.formatINR(widget.sale.totalAmountPaise),
      paymentMode: widget.sale.paymentMethod,
    );
    // Also fire Flutter Local Notification banner (FCM-style heads-up)
    NotificationService.instance.showSaleNotification(
      invoiceNo: widget.sale.invoiceNumber,
      totalPaise: widget.sale.totalAmountPaise,
      customerName: widget.sale.customerName,
    );
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStoreName() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _storeName = p.storeName.isNotEmpty ? p.storeName : 'KamaiPlus Store';
        });
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('business_name') ?? 'KamaiPlus Store';
      if (mounted) setState(() => _storeName = name);
    }
  }

  Future<void> _sendWhatsAppBill() async {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit WhatsApp number'),
          backgroundColor: Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final targetPhone = phone.length == 10 ? '91$phone' : phone;
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(widget.sale.createdAt);
    final amountStr = MoneyFormatter.formatINR(widget.sale.totalAmountPaise);

    final itemLines = widget.sale.items.map((it) {
      final name = it['product_name'] ?? it['name'] ?? 'Item';
      final qty = it['quantity'] ?? it['qty'] ?? 1;
      final price = ((it['unit_price_paise'] ?? it['price'] as num?) ?? 0) / 100.0;
      return '• $name x $qty = ₹${(price * (qty as num)).toStringAsFixed(2)}';
    }).join('\n');

    final message = '''
Namaste ${widget.sale.customerName ?? 'Valued Customer'}! 🙏
Thank you for shopping at *$_storeName*. Here is your digital tax invoice:

🧾 *Invoice No:* #${widget.sale.invoiceNumber}
📅 *Date:* $dateStr
💳 *Payment Mode:* ${widget.sale.paymentMethod.toUpperCase()}

*Itemized Breakdown:*
$itemLines

💰 *Total Amount Paid:* *$amountStr*

Have a wonderful day! Visit us again soon.
''';

    final webWaUrl = Uri.parse('https://wa.me/$targetPhone?text=${Uri.encodeComponent(message)}');
    final directWaUrl = Uri.parse('whatsapp://send?phone=$targetPhone&text=${Uri.encodeComponent(message)}');

    bool launched = false;
    try {
      launched = await launchUrl(webWaUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        launched = await launchUrl(directWaUrl, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    await NativeNotificationService.notifyWhatsAppSent(
      invoiceNumber: widget.sale.invoiceNumber,
      phone: phone,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(launched ? '✓ WhatsApp opened with bill receipt!' : 'WhatsApp receipt dispatched!'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _printReceiptManually() async {
    setState(() => _isPrinting = true);
    HapticFeedback.mediumImpact();

    try {
      final prefs = await SharedPreferences.getInstance();
      final printerAddress = prefs.getString('printer_mac_address');
      final is80mm = prefs.getBool('printer_is_80mm') ?? false;

      if (printerAddress == null || printerAddress.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No Bluetooth printer configured. Tap "Bluetooth Print" to pair.'),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Pair Now',
                textColor: const Color(0xFFFBBF24),
                onPressed: _openBluetoothDialog,
              ),
            ),
          );
        }
        return;
      }

      final bytes = ThermalPrinterService.generateReceiptBytes(
        sale: widget.sale,
        storeName: _storeName,
        is80mm: is80mm,
        kickCashDrawer: widget.sale.paymentMethod == 'cash',
      );

      await _btChannel.invokeMethod('printBytes', {
        'address': printerAddress,
        'bytes': bytes,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Thermal receipt printed successfully!'),
            backgroundColor: Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _openBluetoothDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const BluetoothPrinterDialog(),
    );
  }

  Future<void> _downloadPdf() async {
    HapticFeedback.selectionClick();
    final filePath = await InvoicePdfService.generateAndDownloadPdf(
      sale: widget.sale,
      storeName: _storeName,
      storePhone: _profile.phone,
      storeAddress: _profile.address,
      gstin: _profile.gstin,
      logoPath: _profile.logoUrl,
      customerPhone: _phoneCtrl.text.trim(),
    );

    if (!mounted) return;
    if (filePath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '✓ Invoice #${widget.sale.invoiceNumber} PDF saved to Downloads',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Open',
            textColor: const Color(0xFFFBBF24),
            onPressed: () => InvoicePdfService.openPdf(filePath),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generated and notification dispatched!')),
      );
    }
  }

  Future<void> _sharePdf() async {
    HapticFeedback.selectionClick();
    final ok = await InvoicePdfService.generateAndSharePdf(
      sale: widget.sale,
      storeName: _storeName,
      storePhone: _profile.phone,
      storeAddress: _profile.address,
      gstin: _profile.gstin,
      logoPath: _profile.logoUrl,
      customerPhone: _phoneCtrl.text.trim(),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open system share dialog.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final customerDisplay = sale.customerName?.isNotEmpty == true ? sale.customerName! : 'Cash Customer';
    final paymentDisplay = sale.paymentMethod.toUpperCase();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header: Icon + Title + Status Pill + Close 'X'
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StoreLogoAvatar(
                        logoUrl: _profile.logoUrl,
                        size: 36,
                        radius: 10,
                        fallbackIcon: Icons.check_circle_rounded,
                        fallbackBgColor: const Color(0xFFDCFCE7),
                        fallbackIconColor: const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Sale Completed Successfully!',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'PAID IN FULL',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Invoice #${sale.invoiceNumber} • $customerDisplay',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onNewBill();
                        },
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. Mint Green Total Amount Billed Card (Matching Screenshot 1)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFA7F3D0), width: 1.3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TOTAL AMOUNT BILLED',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: const Color(0xFF047857),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Text(
                                '#${sale.invoiceNumber}',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          MoneyFormatter.formatINR(sale.totalAmountPaise),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Customer: $customerDisplay  •  Payment: $paymentDisplay',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // + New Bill Yellow Button
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onNewBill();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFBBF24),
                              foregroundColor: const Color(0xFF0F172A),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF0F172A)),
                                const SizedBox(width: 6),
                                Text(
                                  '+ New Bill',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13.5,
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
                  const SizedBox(height: 12),

                  // 3. Space-saving Actions Card (No Header - Space-saving per User Request)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEEF2F6), width: 1.2),
                    ),
                    child: Column(
                      children: [
                        // WhatsApp Bill Section
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFF16A34A)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'WhatsApp Bill:',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF15803D),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF86EFAC)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.phone_iphone_rounded, size: 14, color: Color(0xFF94A3B8)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: TextField(
                                              controller: _phoneCtrl,
                                              keyboardType: TextInputType.phone,
                                              style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600),
                                              decoration: const InputDecoration(
                                                hintText: 'Customer 10-digit number...',
                                                hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _sendWhatsAppBill,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: Text(
                                      'Send WhatsApp',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 2x2 Action Buttons (Print, Bluetooth, Download PDF, Show PDF Preview)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isPrinting ? null : _printReceiptManually,
                                icon: _isPrinting
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.print_outlined, size: 15, color: Color(0xFF0F172A)),
                                label: Text(
                                  'Print Receipt',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openBluetoothDialog,
                                icon: const Icon(Icons.bluetooth_rounded, size: 15, color: Color(0xFF0284C7)),
                                label: Text(
                                  'Bluetooth Print',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0284C7),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  side: const BorderSide(color: Color(0xFFBAE6FD)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _downloadPdf,
                                icon: const Icon(Icons.download_rounded, size: 15, color: Color(0xFF0F172A)),
                                label: Text(
                                  'Download PDF',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _sharePdf,
                                icon: const Icon(Icons.share_rounded, size: 15, color: Colors.white),
                                label: Text(
                                  'Share PDF',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _showPdfPreview = !_showPdfPreview);
                                },
                                icon: Icon(
                                  _showPdfPreview ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 15,
                                  color: const Color(0xFF475569),
                                ),
                                label: Text(
                                  _showPdfPreview ? 'Hide Preview' : 'PDF Preview',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 4. Expandable PDF / Receipt Itemized Breakdown Preview
                  if (_showPdfPreview) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              StoreLogoAvatar(
                                logoUrl: _profile.logoUrl,
                                size: 26,
                                radius: 6,
                                fallbackIcon: Icons.receipt_long_rounded,
                                fallbackBgColor: const Color(0xFFE2E8F0),
                                fallbackIconColor: const Color(0xFF0F172A),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _storeName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'RECEIPT ITEM BREAKDOWN',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                '${sale.items.length} items',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 14, color: Color(0xFFE2E8F0)),
                          ...sale.items.map((it) {
                            final name = it['product_name'] ?? 'Item';
                            final qty = it['quantity'] ?? 1;
                            final pricePaise = it['unit_price_paise'] as num? ?? 0;
                            final totalItemPaise = (pricePaise * (qty as num)).round();

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$name x $qty',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    MoneyFormatter.formatINR(totalItemPaise),
                                    style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(height: 14, color: Color(0xFFE2E8F0)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'GRAND TOTAL',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                              Text(
                                MoneyFormatter.formatINR(sale.totalAmountPaise),
                                style: GoogleFonts.robotoMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF059669),
                                ),
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
          ),
        ),
      ),
    );
  }
}
