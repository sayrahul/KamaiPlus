import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/money_formatter.dart';
import '../models/models.dart';

class InvoicePdfService {
  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/pdf_engine');

  /// Generates a professional multi-page Tax Invoice PDF, saves to Downloads, and triggers a tap-to-open notification
  static Future<String?> generateAndDownloadPdf({
    required SaleModel sale,
    required String storeName,
    String? storePhone,
    String? storeAddress,
    String? gstin,
    String? logoPath,
    String? customerPhone,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeColorHex = prefs.getString('invoice_theme_color_hex') ?? '#0284C7';
      final headingText = prefs.getString('invoice_heading') ?? 'TAX INVOICE';
      final termsText = prefs.getString('invoice_terms') ??
          '1. Goods once sold cannot be taken back or exchanged.\n2. Electronic invoice generated via Kamai+ POS System.';
      final footerNote = prefs.getString('custom_invoice_footer') ?? 'Thank you for shopping with us! Visit again.';
      final showDynamicUpiQr = prefs.getBool('invoice_show_dynamic_upi_qr') ?? true;
      final upiId = prefs.getString('store_upi_id') ?? 'proventure@icici';

      final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(sale.createdAt);
      final totalAmount = MoneyFormatter.formatPaise(sale.totalAmountPaise);
      final subtotalAmount = MoneyFormatter.formatPaise(sale.subtotalPaise);
      final discountAmount = sale.discountPaise > 0 ? MoneyFormatter.formatPaise(sale.discountPaise) : '0';
      final taxAmount = sale.taxAmountPaise > 0 ? MoneyFormatter.formatPaise(sale.taxAmountPaise) : '0';

      final List<Map<String, dynamic>> itemsList = sale.items.map((it) {
        final name = (it['product_name'] ?? it['name'] ?? 'Item').toString();
        final qty = (it['quantity'] ?? it['qty'] as num?)?.toDouble() ?? 1.0;
        final qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
        final unitPricePaise = (it['unit_price_paise'] ?? it['price'] as num?)?.toInt() ?? 0;
        final grossTotalPaise = (it['gross_total_paise'] as num?)?.toInt() ?? (unitPricePaise * qty).toInt();

        return {
          'name': name,
          'qty': qtyStr,
          'rate': MoneyFormatter.formatPaise(unitPricePaise),
          'amount': MoneyFormatter.formatPaise(grossTotalPaise),
        };
      }).toList();

      final isPro = prefs.getBool('is_pro') ?? false;

      final String? filePath = await _channel.invokeMethod<String>('generateAndSaveInvoicePdf', {
        'invoiceNumber': sale.invoiceNumber,
        'storeName': storeName,
        'storePhone': storePhone ?? '',
        'storeAddress': storeAddress ?? '',
        'gstin': gstin ?? '',
        'logoPath': logoPath ?? '',
        'customerName': sale.customerName?.isNotEmpty == true ? sale.customerName : 'Cash Customer',
        'customerPhone': customerPhone ?? sale.customerPhone ?? '',
        'doctorName': sale.doctorName ?? '',
        'tableNumber': sale.tableNumber ?? '',
        'isPro': isPro,
        'dateStr': dateStr,
        'paymentMode': sale.paymentMethod,
        'subtotalAmount': subtotalAmount,
        'discountAmount': discountAmount,
        'taxAmount': taxAmount,
        'totalAmount': totalAmount,
        'items': itemsList,
        'themeColorHex': themeColorHex,
        'headingText': headingText,
        'termsText': termsText,
        'footerNote': footerNote,
        'showDynamicUpiQr': showDynamicUpiQr,
        'upiId': upiId,
      });

      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// Opens a previously generated PDF file in the system default PDF viewer
  static Future<bool> openPdf(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('openPdf', {'path': filePath});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Triggers native Android Share Sheet or directs to WhatsApp with the PDF attached
  static Future<bool> sharePdf({
    required String filePath,
    required String invoiceNumber,
    required String storeName,
    String? phone,
    String? message,
    String? subject,
    bool forceChooser = false,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('sharePdf', {
        'path': filePath,
        'invoiceNumber': invoiceNumber,
        'storeName': storeName,
        'phone': phone ?? '',
        'message': message ?? '',
        'subject': subject ?? '',
        'forceChooser': forceChooser,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Generates the PDF and immediately launches the native Android System Share Chooser (always attaches PDF)
  static Future<bool> generateAndSharePdf({
    required SaleModel sale,
    required String storeName,
    String? storePhone,
    String? storeAddress,
    String? gstin,
    String? logoPath,
    String? customerPhone,
    String? phone,
    String? message,
    bool forceChooser = true,
  }) async {
    final path = await generateAndDownloadPdf(
      sale: sale,
      storeName: storeName,
      storePhone: storePhone,
      storeAddress: storeAddress,
      gstin: gstin,
      logoPath: logoPath,
      customerPhone: customerPhone,
    );
    if (path == null || path.isEmpty) return false;
    return await sharePdf(
      filePath: path,
      invoiceNumber: sale.invoiceNumber,
      storeName: storeName,
      phone: forceChooser ? '' : (phone ?? customerPhone ?? sale.customerPhone),
      message: message,
      subject: 'Tax Invoice #${sale.invoiceNumber} - $storeName',
      forceChooser: forceChooser,
    );
  }

  /// Generates a professional Khata Statement PDF and shares via WhatsApp / Share Sheet
  static Future<bool> generateAndShareKhataStatementPdf({
    required CustomerModel customer,
    required String storeName,
    String? storePhone,
    String? upiId,
    required List<LedgerTransactionModel> ledger,
    String? customMessage,
  }) async {
    try {
      final totalBalance = MoneyFormatter.formatPaise(customer.currentBalancePaise);
      final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

      final txList = ledger.map((tx) {
        final amt = MoneyFormatter.formatPaise(tx.amountPaise);
        final bal = MoneyFormatter.formatPaise(tx.balanceAfterPaise);
        final dStr = DateFormat('dd MMM, hh:mm a').format(tx.createdAt);
        return {
          'date': dStr,
          'type': tx.type,
          'note': tx.description.isNotEmpty ? tx.description : 'Khata entry',
          'amount': amt,
          'balance': bal,
        };
      }).toList();

      final String? path = await _channel.invokeMethod<String>('generateAndSaveKhataStatementPdf', {
        'storeName': storeName,
        'storePhone': storePhone ?? '',
        'customerName': customer.name,
        'customerPhone': customer.phone,
        'dateStr': dateStr,
        'totalBalance': totalBalance,
        'upiId': upiId ?? 'proventure@icici',
        'transactions': txList,
      });

      if (path == null || path.isEmpty) return false;

      final defaultSubject = 'Khata Statement - $storeName';
      final defaultMsg = customMessage ??
          'Namaste ${customer.name} ji! 🙏\n\n$storeName par aapka baki hisaab $totalBalance hai. Kripya samay par chukta karein.\n\n📲 *Pay via UPI:* upi://pay?pa=${upiId ?? "proventure@icici"}&pn=${Uri.encodeComponent(storeName)}&am=${(customer.currentBalancePaise / 100).toStringAsFixed(2)}&cu=INR\n\nDhanyawad!';

      return await sharePdf(
        filePath: path,
        invoiceNumber: 'KHATA-${customer.phone}',
        storeName: storeName,
        phone: customer.phone,
        message: defaultMsg,
        subject: defaultSubject,
      );
    } catch (_) {
      return false;
    }
  }
}

