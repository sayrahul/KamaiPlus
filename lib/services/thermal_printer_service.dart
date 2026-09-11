import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/local_database.dart';
import '../models/models.dart';
import '../core/utils/money_formatter.dart';

class ThermalPrinterService {
  static const int cols58mm = 32;
  static const int cols80mm = 48;
  static const MethodChannel _btChannel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  /// Prints raw ESC/POS receipt via connected Bluetooth thermal printer
  static Future<bool> printReceipt({
    required SaleModel sale,
    String? storeName,
    String? printerMacAddress,
    bool? is80mm,
    bool kickCashDrawer = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = printerMacAddress ?? prefs.getString('printer_mac_address');
      if (address == null || address.isEmpty) {
        return false;
      }
      final bool use80mm = is80mm ?? (prefs.getBool('printer_is_80mm') ?? false);
      final profile = await LocalDatabase.instance.getStoreProfile();
      final resolvedStoreName = (storeName != null && storeName.isNotEmpty)
          ? storeName
          : (profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store');

      final bytes = generateReceiptBytes(
        sale: sale,
        storeName: resolvedStoreName,
        storePhone: profile.phone,
        storeAddress: profile.address,
        is80mm: use80mm,
        kickCashDrawer: kickCashDrawer,
      );

      final result = await _btChannel.invokeMethod<bool>('printBytes', {
        'address': address,
        'bytes': bytes,
      });
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  static Uint8List generateReceiptBytes({
    required SaleModel sale,
    required String storeName,
    String? storePhone,
    String? storeAddress,
    bool is80mm = false,
    bool kickCashDrawer = true,
  }) {
    final int width = is80mm ? cols80mm : cols58mm;
    final List<int> bytes = [];

    // 1. Initialize Printer (ESC @)
    bytes.addAll([0x1B, 0x40]);

    // 2. Center align header (ESC a 1)
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Bold ON (ESC E 1)
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll('$storeName\n'.codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

    if (storePhone != null && storePhone.isNotEmpty) {
      bytes.addAll('Ph: $storePhone\n'.codeUnits);
    }
    if (storeAddress != null && storeAddress.isNotEmpty) {
      bytes.addAll('$storeAddress\n'.codeUnits);
    }

    // Divider
    bytes.addAll('${"-" * width}\n'.codeUnits);

    // Left align body (ESC a 0)
    bytes.addAll([0x1B, 0x61, 0x00]);
    bytes.addAll('Invoice: ${sale.invoiceNumber}\n'.codeUnits);
    bytes.addAll('Date: ${sale.createdAt.day}/${sale.createdAt.month}/${sale.createdAt.year} ${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}\n'.codeUnits);

    if (sale.customerName != null && sale.customerName!.isNotEmpty) {
      bytes.addAll('Customer: ${sale.customerName}\n'.codeUnits);
    }
    bytes.addAll('Payment: ${sale.paymentMethod.toUpperCase()}\n'.codeUnits);

    bytes.addAll('${"-" * width}\n'.codeUnits);

    // Column Headers: ITEM | QTY | AMT
    if (width == cols58mm) {
      bytes.addAll('Item             Qty      Amt\n'.codeUnits);
    } else {
      bytes.addAll('Item                          Qty       Amount\n'.codeUnits);
    }
    bytes.addAll('${"-" * width}\n'.codeUnits);

    // Items list
    for (var item in sale.items) {
      final String name = (item['product_name'] ?? 'Item').toString();
      final double qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final int totalPaise = (item['gross_total_paise'] as num?)?.toInt() ?? 0;
      final String amtStr = (totalPaise / 100.0).toStringAsFixed(2);
      final String qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();

      if (width == cols58mm) {
        final shortName = name.length > 14 ? name.substring(0, 14) : name.padRight(14);
        final q = qtyStr.padLeft(5);
        final a = amtStr.padLeft(10);
        bytes.addAll('$shortName $q $a\n'.codeUnits);
      } else {
        final shortName = name.length > 26 ? name.substring(0, 26) : name.padRight(26);
        final q = qtyStr.padLeft(8);
        final a = amtStr.padLeft(12);
        bytes.addAll('$shortName $q $a\n'.codeUnits);
      }
    }

    bytes.addAll('${"-" * width}\n'.codeUnits);

    // Total Amount (Bold)
    bytes.addAll([0x1B, 0x45, 0x01]);
    final String totalText = 'TOTAL: ${MoneyFormatter.formatINR(sale.totalAmountPaise)}';
    bytes.addAll([0x1B, 0x61, 0x02]); // Right align
    bytes.addAll('$totalText\n'.codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

    // Footer
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll('\nThank you for your visit!\nKamaiPlus Smart POS\n\n\n'.codeUnits);

    // Drawer Kick (ESC p 0 25 250)
    if (kickCashDrawer) {
      bytes.addAll([0x1B, 0x70, 0x00, 0x19, 0xFA]);
    }

    // Auto-cut paper (GS V 66 0)
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(bytes);
  }

  /// Prints a Kitchen Order Ticket — Phase 4 of the KamaiPlus Playbook
  /// (restaurant vertical feature depth). Deliberately a separate method
  /// from [printReceipt], not a flag on it: a KOT carries no prices (the
  /// kitchen doesn't need them, and showing them invites a mix-up with the
  /// customer's bill) and puts dish modifiers front and centre — exactly
  /// the opposite emphasis of a customer receipt, where modifiers are a
  /// secondary detail and the total is what matters.
  static Future<bool> printKOT({
    required SaleModel sale,
    String? printerMacAddress,
    bool? is80mm,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = printerMacAddress ?? prefs.getString('kot_printer_mac_address') ?? prefs.getString('printer_mac_address');
      if (address == null || address.isEmpty) {
        return false;
      }
      final bool use80mm = is80mm ?? (prefs.getBool('printer_is_80mm') ?? false);

      final bytes = generateKOTBytes(sale: sale, is80mm: use80mm);

      final result = await _btChannel.invokeMethod<bool>('printBytes', {
        'address': address,
        'bytes': bytes,
      });
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  static Uint8List generateKOTBytes({
    required SaleModel sale,
    bool is80mm = false,
  }) {
    final int width = is80mm ? cols80mm : cols58mm;
    final List<int> bytes = [];

    bytes.addAll([0x1B, 0x40]); // Initialize printer
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align

    // Large + bold "KOT" header — this ticket is read fast, standing at a
    // kitchen counter, not sat down with a bill.
    bytes.addAll([0x1D, 0x21, 0x11]); // GS ! — double width + double height
    bytes.addAll('KITCHEN ORDER\n'.codeUnits);
    bytes.addAll([0x1D, 0x21, 0x00]); // back to normal size

    if (sale.tableNumber != null && sale.tableNumber!.isNotEmpty) {
      bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll('TABLE ${sale.tableNumber}\n'.codeUnits);
      bytes.addAll([0x1B, 0x45, 0x00]);
    } else {
      bytes.addAll('PARCEL / TAKEAWAY\n'.codeUnits);
    }

    bytes.addAll('${"-" * width}\n'.codeUnits);
    bytes.addAll([0x1B, 0x61, 0x00]); // Left align
    bytes.addAll('Order: ${sale.invoiceNumber}\n'.codeUnits);
    bytes.addAll('Time: ${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}\n'.codeUnits);
    bytes.addAll('${"-" * width}\n'.codeUnits);

    // Items — name + qty large and bold, no prices anywhere on a KOT.
    for (var item in sale.items) {
      final String name = (item['product_name'] ?? 'Item').toString();
      final double qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final String qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
      final String? notes = item['notes']?.toString();

      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll('${qtyStr}x $name\n'.codeUnits);
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

      if (notes != null && notes.trim().isNotEmpty) {
        bytes.addAll('   >> ${notes.trim()}\n'.codeUnits);
      }
    }

    bytes.addAll('${"-" * width}\n'.codeUnits);
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll('\n\n'.codeUnits);

    // Auto-cut paper — no cash-drawer kick on a KOT.
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(bytes);
  }
}
