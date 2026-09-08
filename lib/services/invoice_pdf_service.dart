import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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

      final String? filePath = await _channel.invokeMethod<String>('generateAndSaveInvoicePdf', {
        'invoiceNumber': sale.invoiceNumber,
        'storeName': storeName,
        'storePhone': storePhone ?? '',
        'storeAddress': storeAddress ?? '',
        'gstin': gstin ?? '',
        'logoPath': logoPath ?? '',
        'customerName': sale.customerName?.isNotEmpty == true ? sale.customerName : 'Cash Customer',
        'customerPhone': customerPhone ?? sale.customerPhone ?? '',
        'dateStr': dateStr,
        'paymentMode': sale.paymentMethod,
        'subtotalAmount': subtotalAmount,
        'discountAmount': discountAmount,
        'taxAmount': taxAmount,
        'totalAmount': totalAmount,
        'items': itemsList,
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

  /// Triggers native Android Share Sheet (WhatsApp, Email, Drive, Nearby Share) with the PDF attached
  static Future<bool> sharePdf({
    required String filePath,
    required String invoiceNumber,
    required String storeName,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('sharePdf', {
        'path': filePath,
        'invoiceNumber': invoiceNumber,
        'storeName': storeName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Generates the PDF and immediately launches the native Android Share Sheet
  static Future<bool> generateAndSharePdf({
    required SaleModel sale,
    required String storeName,
    String? storePhone,
    String? storeAddress,
    String? gstin,
    String? logoPath,
    String? customerPhone,
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
    );
  }
}
