import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/local_database.dart';
import '../core/utils/gst_helper.dart';
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
      String upiId = prefs.getString('store_upi_id') ?? '';
      if (upiId.isEmpty) {
        try {
          final profile = await LocalDatabase.instance.getStoreProfile();
          upiId = profile.upiVpa;
        } catch (_) {}
      }

      // Generate Crisp UPI QR Code bitmap bytes for the PDF engine
      Uint8List? qrBytes;
      if (showDynamicUpiQr && upiId.trim().isNotEmpty) {
        try {
          final cleanAmt = (sale.totalAmountPaise / 100).toStringAsFixed(2);
          final upiPayload =
              'upi://pay?pa=${upiId.trim()}&pn=${Uri.encodeComponent(storeName)}&am=$cleanAmt&cu=INR';
          final painter = QrPainter(
            data: upiPayload,
            version: QrVersions.auto,
            gapless: true,
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: ui.Color(0xFF0F172A),
            ),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: ui.Color(0xFF0F172A),
            ),
          );
          final pic = await painter.toImageData(240, format: ui.ImageByteFormat.png);
          qrBytes = pic?.buffer.asUint8List();
        } catch (_) {}
      }

      final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(sale.createdAt);
      final totalAmount = MoneyFormatter.formatPaise(sale.totalAmountPaise);
      final subtotalAmount = MoneyFormatter.formatPaise(sale.subtotalPaise);
      final discountAmount = sale.discountPaise > 0 ? MoneyFormatter.formatPaise(sale.discountPaise) : '0';
      final taxAmount = sale.taxAmountPaise > 0 ? MoneyFormatter.formatPaise(sale.taxAmountPaise) : '0';

      final Map<double, Map<String, dynamic>> slabs = {};
      int taxableTotalPaise = 0;

      final List<Map<String, dynamic>> itemsList = sale.items.map((it) {
        final name = (it['product_name'] ?? it['name'] ?? 'Item').toString();
        final qty = (it['quantity'] ?? it['qty'] as num?)?.toDouble() ?? 1.0;
        final qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
        final unitPricePaise = (it['unit_price_paise'] ?? it['price'] as num?)?.toInt() ?? 0;
        final grossTotalPaise = (it['gross_total_paise'] as num?)?.toInt() ?? (unitPricePaise * qty).toInt();
        final hsn = (it['hsn_code'] ?? it['hsn'] ?? '').toString();
        final taxRate = (it['tax_rate'] as num?)?.toDouble() ?? 0.0;

        int itemTaxPaise = 0;
        int itemTaxablePaise = grossTotalPaise;
        if (taxRate > 0) {
          final bool isInclusive = it['is_tax_inclusive'] != false;
          if (isInclusive) {
            itemTaxablePaise = ((grossTotalPaise * 100) / (100 + taxRate)).round();
            itemTaxPaise = grossTotalPaise - itemTaxablePaise;
          } else {
            itemTaxablePaise = grossTotalPaise;
            itemTaxPaise = ((grossTotalPaise * taxRate) / 100).round();
          }
        }
        taxableTotalPaise += itemTaxablePaise;

        if (taxRate > 0) {
          if (!slabs.containsKey(taxRate)) {
            slabs[taxRate] = {
              'rate': taxRate,
              'hsns': <String>{},
              'taxablePaise': 0,
              'taxPaise': 0,
            };
          }
          if (hsn.isNotEmpty) {
            (slabs[taxRate]!['hsns'] as Set<String>).add(hsn);
          }
          slabs[taxRate]!['taxablePaise'] = (slabs[taxRate]!['taxablePaise'] as int) + itemTaxablePaise;
          slabs[taxRate]!['taxPaise'] = (slabs[taxRate]!['taxPaise'] as int) + itemTaxPaise;
        }

        final cgstPaise = itemTaxPaise ~/ 2;
        final sgstPaise = itemTaxPaise - cgstPaise;

        return {
          'name': name,
          'hsn': hsn.isNotEmpty ? hsn : '-',
          'qty': qtyStr,
          'rate': MoneyFormatter.formatPaise(unitPricePaise),
          'taxable': MoneyFormatter.formatPaise(itemTaxablePaise),
          'taxRate': taxRate,
          'cgstRate': taxRate > 0 ? '${(taxRate / 2).toStringAsFixed(1)}%' : '',
          'cgstAmt': MoneyFormatter.formatPaise(cgstPaise),
          'sgstRate': taxRate > 0 ? '${(taxRate / 2).toStringAsFixed(1)}%' : '',
          'sgstAmt': MoneyFormatter.formatPaise(sgstPaise),
          'taxAmt': MoneyFormatter.formatPaise(itemTaxPaise),
          'amount': MoneyFormatter.formatPaise(grossTotalPaise),
        };
      }).toList();

      final List<Map<String, dynamic>> taxBreakupList = slabs.values.map((s) {
        final rate = s['rate'] as double;
        final hsnSet = s['hsns'] as Set<String>;
        final hsnStr = hsnSet.isEmpty ? 'GST ${rate.toInt()}%' : hsnSet.join(', ');
        final taxable = s['taxablePaise'] as int;
        final totalTax = s['taxPaise'] as int;
        final halfTax = totalTax ~/ 2;
        final remTax = totalTax - halfTax;

        return {
          'hsn': '$hsnStr (${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%)',
          'taxable': MoneyFormatter.formatPaise(taxable),
          'cgstRate': '${(rate / 2).toStringAsFixed(1)}%',
          'cgstAmt': MoneyFormatter.formatPaise(halfTax),
          'sgstRate': '${(rate / 2).toStringAsFixed(1)}%',
          'sgstAmt': MoneyFormatter.formatPaise(remTax),
          'totalTax': MoneyFormatter.formatPaise(totalTax),
        };
      }).toList();

      final amountInWords = GstHelper.numberToWordsINR(sale.totalAmountPaise);
      final storeState = GstHelper.getStateFromGstin(gstin);
      final customerGstin = sale.customerGstin ?? '';
      final placeOfSupply = sale.placeOfSupply?.isNotEmpty == true
          ? sale.placeOfSupply!
          : (customerGstin.isNotEmpty ? GstHelper.getStateFromGstin(customerGstin) : storeState);

      final isPro = prefs.getBool('is_pro') ?? false;

      final String? filePath = await _channel.invokeMethod<String>('generateAndSaveInvoicePdf', {
        'invoiceNumber': sale.invoiceNumber,
        'storeName': storeName,
        'storePhone': storePhone ?? '',
        'storeAddress': storeAddress ?? '',
        'gstin': gstin ?? '',
        'storeState': storeState,
        'logoPath': logoPath ?? '',
        'customerName': sale.customerName?.isNotEmpty == true ? sale.customerName : 'Cash Customer',
        'customerPhone': customerPhone ?? sale.customerPhone ?? '',
        'customerGstin': customerGstin,
        'placeOfSupply': placeOfSupply,
        'doctorName': sale.doctorName ?? '',
        'tableNumber': sale.tableNumber ?? '',
        'isPro': isPro,
        'dateStr': dateStr,
        'paymentMode': sale.paymentMethod,
        'subtotalAmount': subtotalAmount,
        'taxableSubtotal': MoneyFormatter.formatPaise(taxableTotalPaise > 0 ? taxableTotalPaise : sale.subtotalPaise),
        'discountAmount': discountAmount,
        'taxAmount': taxAmount,
        'totalAmount': totalAmount,
        'amountInWords': amountInWords,
        'items': itemsList,
        'taxBreakup': taxBreakupList,
        'themeColorHex': themeColorHex,
        'headingText': headingText,
        'termsText': termsText,
        'footerNote': footerNote,
        'showDynamicUpiQr': showDynamicUpiQr,
        'upiId': upiId,
        'qrBytes': qrBytes,
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

  /// Sends PDF directly to native Android PrintManager for A4/Standard printing (Wi-Fi, USB, Mopria)
  static Future<bool> printPdf({required String filePath, String? documentName}) async {
    try {
      final res = await _channel.invokeMethod<bool>('printPdf', {
        'path': filePath,
        'name': documentName ?? 'Tax_Invoice',
      });
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

      String effectiveUpiId = (upiId != null && upiId.isNotEmpty) ? upiId : '';
      if (effectiveUpiId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        effectiveUpiId = prefs.getString('store_upi_id') ?? '';
        if (effectiveUpiId.isEmpty) {
          try {
            final profile = await LocalDatabase.instance.getStoreProfile();
            effectiveUpiId = profile.upiVpa;
          } catch (_) {}
        }
      }

      final String? path = await _channel.invokeMethod<String>('generateAndSaveKhataStatementPdf', {
        'storeName': storeName,
        'storePhone': storePhone ?? '',
        'customerName': customer.name,
        'customerPhone': customer.phone,
        'dateStr': dateStr,
        'totalBalance': totalBalance,
        'upiId': effectiveUpiId,
        'transactions': txList,
      });

      if (path == null || path.isEmpty) return false;

      final defaultSubject = 'Khata Statement - $storeName';
      final upiSuffix = effectiveUpiId.isNotEmpty
          ? '\n\n📲 *Pay via UPI:* upi://pay?pa=$effectiveUpiId&pn=${Uri.encodeComponent(storeName)}&am=${(customer.currentBalancePaise / 100).toStringAsFixed(2)}&cu=INR'
          : '';
      final defaultMsg = customMessage ??
          'Namaste ${customer.name} ji! 🙏\n\n$storeName par aapka baki hisaab $totalBalance hai. Kripya samay par chukta karein.$upiSuffix\n\nDhanyawad!';

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

