import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/native_notification_service.dart';
import '../../services/thermal_printer_service.dart';
import '../common/store_logo_avatar.dart';
import '../common/pro_upgrade_modal.dart';

class SaleDetailModal extends StatelessWidget {
  final SaleModel sale;
  final VoidCallback? onVoidOrRefund;

  const SaleDetailModal({
    super.key,
    required this.sale,
    this.onVoidOrRefund,
  });

  static Future<void> show(
    BuildContext context, {
    required SaleModel sale,
    VoidCallback? onVoidOrRefund,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SaleDetailModal(
        sale: sale,
        onVoidOrRefund: onVoidOrRefund,
      ),
    );
  }

  static const _btChannel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  void _printThermal(BuildContext context) async {
    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final printerAddress = prefs.getString('printer_mac_address');
      final is80mm = prefs.getBool('printer_is_80mm') ?? false;

      if (printerAddress == null || printerAddress.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No Bluetooth printer configured. Connect via Menu > Hardware & Bluetooth.'),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }

      final bytes = ThermalPrinterService.generateReceiptBytes(
        sale: sale,
        storeName: 'KamaiPlus Store',
        is80mm: is80mm,
        kickCashDrawer: sale.paymentMethod == 'cash',
      );

      await _btChannel.invokeMethod('printBytes', {
        'address': printerAddress,
        'bytes': bytes,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Sent bill #${sale.invoiceNumber} to thermal printer'),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _shareWhatsApp(BuildContext context) async {
    HapticFeedback.selectionClick();
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);
    final amtRupees = sale.totalAmountPaise ~/ 100;
    final totalRupees = (sale.totalAmountPaise / 100.0).toStringAsFixed(2);

    final profile = await LocalDatabase.instance.getStoreProfile();
    final sName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';
    final upiId = profile.upiVpa.isNotEmpty ? profile.upiVpa : 'proventure@icici';
    final upiPayLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(sName)}&am=$totalRupees&cu=INR&tn=Bill_${sale.invoiceNumber}';

    final buffer = StringBuffer();
    buffer.writeln('🧾 *INVOICE #${sale.invoiceNumber}*');
    buffer.writeln('🏪 *$sName*');
    if (sale.customerName != null && sale.customerName!.isNotEmpty) {
      buffer.writeln('👤 Customer: ${sale.customerName}');
    }
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('--------------------------');
    for (final it in sale.items) {
      final name = it['product_name'] ?? it['name'] ?? 'Item';
      final qty = it['quantity'] ?? it['qty'] ?? 1;
      final pricePaise = it['gross_total_paise'] ?? ((it['price'] as int? ?? 0) * (qty as num).toInt());
      buffer.writeln('• ${qty}x $name = ₹${(pricePaise as int) ~/ 100}');
    }
    buffer.writeln('--------------------------');
    buffer.writeln('💰 *Total Amount: ₹$amtRupees*');
    buffer.writeln('💳 Paid via: ${sale.paymentMethod.toUpperCase()}');
    buffer.writeln('📲 *Instant UPI Pay / Receipt:* $upiPayLink');
    buffer.writeln('\nDhanyawad! Phir Padhaarein 🙏');

    final phone = sale.customerPhone ?? '';
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final targetPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;

    // 1. Generate and share PDF with text & payment link
    final filePath = await InvoicePdfService.generateAndDownloadPdf(
      sale: sale,
      storeName: sName,
      storePhone: profile.phone,
      storeAddress: profile.address,
      gstin: profile.gstin,
      logoPath: profile.logoUrl,
      customerPhone: targetPhone,
    );

    bool shared = false;
    if (filePath != null && filePath.isNotEmpty) {
      shared = await InvoicePdfService.sharePdf(
        filePath: filePath,
        invoiceNumber: sale.invoiceNumber,
        storeName: sName,
        phone: targetPhone,
        message: buffer.toString(),
        subject: 'Tax Invoice #${sale.invoiceNumber} - $sName',
      );
    }

    if (!shared) {
      final url = targetPhone.isNotEmpty
          ? Uri.parse('https://wa.me/$targetPhone?text=${Uri.encodeComponent(buffer.toString())}')
          : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}');

      try {
        final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!launched) {
          final directWa = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(buffer.toString())}');
          await launchUrl(directWa, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: buffer.toString()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Bill details copied to clipboard!')),
          );
        }
      }
    }
  }

  void _downloadPdf(BuildContext context) async {
    HapticFeedback.selectionClick();
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final storeName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';
      final path = await InvoicePdfService.generateAndDownloadPdf(
        sale: sale,
        storeName: storeName,
        storePhone: profile.phone,
        storeAddress: profile.address,
        gstin: profile.gstin,
        logoPath: profile.logoUrl,
        customerPhone: sale.customerPhone,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Tax Invoice #${sale.invoiceNumber} PDF saved to Downloads!'),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.white,
              onPressed: () => InvoicePdfService.openPdf(path),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  void _sharePdf(BuildContext context) async {
    HapticFeedback.selectionClick();
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final storeName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';
      final ok = await InvoicePdfService.generateAndSharePdf(
        sale: sale,
        storeName: storeName,
        storePhone: profile.phone,
        storeAddress: profile.address,
        gstin: profile.gstin,
        logoPath: profile.logoUrl,
        customerPhone: sale.customerPhone,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open share dialog')),
        );
      }
    } catch (_) {}
  }

  void _confirmSalesReturn(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final profile = await LocalDatabase.instance.getStoreProfile();
    if (!profile.isPro) {
      if (context.mounted) {
        ProUpgradeModal.show(context);
      }
      return;
    }

    final creditDue = sale.paymentMethod == 'credit'
        ? sale.totalAmountPaise
        : (sale.paymentMethod == 'split' ? sale.splitCreditPaise : 0);
    final isUdhar = creditDue > 0;

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.replay_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sales Return (Refund)?',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice #${sale.invoiceNumber} ke sabhi items inventory me wapas add honge:',
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEEF2F6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...sale.items.map((it) {
                    final name = it['product_name'] ?? it['name'] ?? 'Item';
                    final qty = it['quantity'] ?? it['qty'] ?? 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_right_rounded, size: 18, color: Color(0xFF059669)),
                          Expanded(
                            child: Text(
                              '$name (+$qty stock)',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (isUdhar) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Customer ${sale.customerName ?? ""} ka Udhar ${MoneyFormatter.formatINR(creditDue)} turant reverse ho jayega.',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 18, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Customer ko ${MoneyFormatter.formatINR(sale.totalAmountPaise)} (${sale.paymentMethod.toUpperCase()}) refund karein.',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              HapticFeedback.heavyImpact();

              try {
                await LocalDatabase.instance.processSalesReturn(sale: sale);

                await NativeNotificationService.showNotification(
                  title: '↩️ Sales Return Done: #${sale.invoiceNumber}',
                  body: 'Stock restored to inventory & ${isUdhar ? "Udhar reversed" : "Refund recorded"}.',
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '✓ Invoice #${sale.invoiceNumber} returned! Stock restocked & ${isUdhar ? "Udhar reversed" : "Refund completed"}.',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF059669),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
                onVoidOrRefund?.call();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Return error: $e'),
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.replay_rounded, size: 16, color: Colors.white),
            label: Text('Confirm 1-Tap Return', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);
    final isRefunded = sale.isRefunded;
    final isUdhar = sale.paymentMethod == 'credit';
    final isUpi = sale.paymentMethod == 'upi';
    final modeBadgeText = isRefunded
        ? 'REFUNDED / RETURNED'
        : (isUdhar ? 'CREDIT / UDHAR' : (isUpi ? 'UPI DIGITAL' : 'CASH COUNTER'));
    final modeBadgeBg = isRefunded
        ? const Color(0xFFFEE2E2)
        : (isUdhar ? const Color(0xFFFEF2F2) : (isUpi ? const Color(0xFFF0F9FF) : const Color(0xFFECFDF5)));
    final modeBadgeColor = isRefunded
        ? const Color(0xFFDC2626)
        : (isUdhar ? const Color(0xFFDC2626) : (isUpi ? const Color(0xFF0284C7) : const Color(0xFF059669)));

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with Store Logo
          FutureBuilder<StoreProfileModel>(
            future: LocalDatabase.instance.getStoreProfile(),
            builder: (ctx, snap) {
              final logoUrl = snap.data?.logoUrl ?? '';
              final storeName = (snap.data?.storeName.isNotEmpty == true) ? snap.data!.storeName : 'KamaiPlus Store';

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      StoreLogoAvatar(
                        logoUrl: logoUrl,
                        size: 42,
                        radius: 10,
                        fallbackIcon: Icons.receipt_long_rounded,
                        fallbackBgColor: const Color(0xFFF1F5F9),
                        fallbackIconColor: const Color(0xFF0F172A),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice #${sale.invoiceNumber}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '$storeName • $dateStr',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // Customer info & Payment Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      sale.customerName != null && sale.customerName!.isNotEmpty
                          ? sale.customerName!
                          : 'Walk-in Customer',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    if (sale.customerPhone != null && sale.customerPhone!.isNotEmpty) ...[
                      Text(
                        ' • ${sale.customerPhone}',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: modeBadgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    modeBadgeText,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: modeBadgeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Items Container
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEF2F6), width: 1.2),
            ),
            child: ListView(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                ...sale.items.map((it) {
                  final name = it['product_name'] ?? it['name'] ?? 'Item';
                  final qty = it['quantity'] ?? it['qty'] ?? 1;
                  final pricePaise = it['gross_total_paise'] ?? ((it['price'] as int? ?? 0) * (qty as num).toInt());

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${qty}x $name',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        Text(
                          MoneyFormatter.formatINR(pricePaise as int),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 16, color: Color(0xFFE2E8F0)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Payable',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      MoneyFormatter.formatINR(sale.totalAmountPaise),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Actions: Print Thermal + Download PDF + Share PDF
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _printThermal(context),
                  icon: const Icon(Icons.print_rounded, size: 15, color: Color(0xFF0F172A)),
                  label: Text(
                    'Thermal',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _downloadPdf(context),
                  icon: const Icon(Icons.download_rounded, size: 15, color: Color(0xFF0284C7)),
                  label: Text(
                    'A4 PDF',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0284C7),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sharePdf(context),
                  icon: const Icon(Icons.share_rounded, size: 15, color: Color(0xFF4F46E5)),
                  label: Text(
                    'Share PDF',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF4F46E5),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareWhatsApp(context),
              icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
              label: Text(
                'Send Bill via WhatsApp',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 1-Tap Sales Return (Refund) Action OR Refunded Confirmation Strip
          if (isRefunded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Text(
                    'Bill Returned • Stock Restored & Udhar Reversed',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmSalesReturn(context),
                icon: const Icon(Icons.replay_rounded, size: 17, color: Color(0xFFDC2626)),
                label: Text(
                  'Sales Return (1-Tap Refund & Restock)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFDC2626),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
