import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/utils/money_formatter.dart';
import '../models/models.dart';

class InvoicePdfService {
  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/pdf_engine');

  /// Generates a real Tax Invoice PDF, saves to Downloads, and triggers a tap-to-open status bar notification
  static Future<String?> generateAndDownloadPdf({
    required SaleModel sale,
    required String storeName,
    String? storePhone,
  }) async {
    try {
      final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(sale.createdAt);
      final totalAmount = MoneyFormatter.formatPaise(sale.totalAmountPaise);

      final List<Map<String, dynamic>> itemsList = sale.items.map((it) {
        final name = (it['product_name'] ?? 'Item').toString();
        final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
        final qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
        final unitPricePaise = (it['unit_price_paise'] as num?)?.toInt() ?? 0;
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
        'customerName': sale.customerName?.isNotEmpty == true ? sale.customerName : 'Walk-in Customer',
        'dateStr': dateStr,
        'paymentMode': sale.paymentMethod,
        'tableNumber': sale.tableNumber,
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
}
