import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/thermal_printer_service.dart';

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

    final buffer = StringBuffer();
    buffer.writeln('🧾 *INVOICE #${sale.invoiceNumber}*');
    buffer.writeln('🏪 *KamaiPlus Store*');
    if (sale.customerName != null && sale.customerName!.isNotEmpty) {
      buffer.writeln('👤 Customer: ${sale.customerName}');
    }
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('--------------------------');
    for (final it in sale.items) {
      final name = it['product_name'] ?? it['name'] ?? 'Item';
      final qty = it['quantity'] ?? it['qty'] ?? 1;
      final pricePaise = it['gross_total_paise'] ?? ((it['price'] as int? ?? 0) * (qty as num).toInt());
      buffer.writeln('• ${qty}x $name = ₹${pricePaise ~/ 100}');
    }
    buffer.writeln('--------------------------');
    buffer.writeln('💰 *Total Amount: ₹$amtRupees*');
    buffer.writeln('💳 Paid via: ${sale.paymentMethod.toUpperCase()}');
    buffer.writeln('\nDhanyawad! Phir Padhaarein 🙏');

    final phone = sale.customerPhone ?? '';
    final url = phone.isNotEmpty
        ? Uri.parse('https://wa.me/91$phone?text=${Uri.encodeComponent(buffer.toString())}')
        : Uri.parse('whatsapp://send?text=${Uri.encodeComponent(buffer.toString())}');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: buffer.toString()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Bill details copied to clipboard!')),
          );
        }
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

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);
    final isUdhar = sale.paymentMethod == 'credit';
    final isUpi = sale.paymentMethod == 'upi';

    final modeBadgeText = isUdhar ? 'CREDIT / UDHAR' : (isUpi ? 'UPI DIGITAL' : 'CASH COUNTER');
    final modeBadgeBg = isUdhar ? const Color(0xFFFEF2F2) : (isUpi ? const Color(0xFFF0F9FF) : const Color(0xFFECFDF5));
    final modeBadgeColor = isUdhar ? const Color(0xFFDC2626) : (isUpi ? const Color(0xFF0284C7) : const Color(0xFF059669));

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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0F172A), size: 20),
                  ),
                  const SizedBox(width: 8),
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
                        dateStr,
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

          // Actions: Print Thermal + WhatsApp Bill
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _printThermal(context),
                  icon: const Icon(Icons.print_rounded, size: 16, color: Color(0xFF0F172A)),
                  label: Text(
                    'Print Thermal',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareWhatsApp(context),
                  icon: Image.asset('assets/images/whatsapp_logo.png', width: 17, height: 17),
                  label: Text(
                    'WhatsApp Bill',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
