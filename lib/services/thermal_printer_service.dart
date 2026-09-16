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

      // Invoice Themes settings apply to thermal receipts too. They used to
      // be read only by the A4 PDF engine, so a shopkeeper who set their bill
      // heading to "CASH MEMO" and wrote their own footer saw neither on the
      // 58mm roll — which, for most kirana counters, is the ONLY bill the
      // customer ever receives.
      final invoiceHeading = prefs.getString('invoice_heading') ?? '';
      final footerNote = prefs.getString('custom_invoice_footer') ?? '';
      final showOwnerPhone = prefs.getBool('invoice_show_owner_phone') ?? true;
      final showTagline = prefs.getBool('invoice_show_tagline') ?? true;

      final bytes = generateReceiptBytes(
        sale: sale,
        storeName: resolvedStoreName,
        storePhone: showOwnerPhone ? profile.phone : null,
        storeAddress: profile.address,
        storeUpiVpa: profile.upiVpa.trim(),
        storeGstin: profile.gstin.trim(),
        storeTagline: showTagline ? profile.tagline.trim() : null,
        invoiceHeading: invoiceHeading,
        footerNote: footerNote,
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

  /// Encodes text for an ESC/POS printer.
  ///
  /// `String.codeUnits` (what this used to use everywhere) hands the printer
  /// raw UTF-16 units truncated to bytes. For plain ASCII that is harmless,
  /// but a Devanagari store name like "कमाई किराना" truncates each character
  /// to an arbitrary low byte — printing gibberish, and worse, occasionally
  /// emitting a byte the printer reads as an ESC/GS control code, which can
  /// corrupt or abort the whole print job mid-receipt. Anything outside
  /// Latin-1 is dropped instead, so an unprintable name degrades to a shorter
  /// line rather than to a broken bill.
  static List<int> _escText(String text) {
    // ₹ (U+20B9) is outside Latin-1 and outside every codepage these printers
    // ship with. Truncating it to a byte produced '¹', so receipts read
    // "TOTAL: ¹499.00". Spell it out instead — "Rs." is what Indian thermal
    // bills have always printed anyway.
    final normalised = text.replaceAll('₹', 'Rs.');
    final out = <int>[];
    for (final rune in normalised.runes) {
      if (rune == 0x0A || rune == 0x0D) {
        out.add(rune);
      } else if (rune >= 0x20 && rune <= 0xFF) {
        out.add(rune);
      }
      // Everything else is silently skipped — see doc comment.
    }
    return out;
  }

  static Uint8List generateReceiptBytes({
    required SaleModel sale,
    required String storeName,
    String? storePhone,
    String? storeAddress,
    String? storeUpiVpa,
    String? storeGstin,
    String? storeTagline,
    String? invoiceHeading,
    String? footerNote,
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
    bytes.addAll(_escText('$storeName\n'));
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

    if (storeTagline != null && storeTagline.trim().isNotEmpty) {
      bytes.addAll(_escText('${storeTagline.trim()}\n'));
    }
    if (storePhone != null && storePhone.isNotEmpty) {
      bytes.addAll(_escText('Ph: $storePhone\n'));
    }
    if (storeAddress != null && storeAddress.isNotEmpty) {
      bytes.addAll(_escText('$storeAddress\n'));
    }
    if (storeGstin != null && storeGstin.isNotEmpty) {
      bytes.addAll(_escText('GSTIN: $storeGstin\n'));
    }
    if (invoiceHeading != null && invoiceHeading.trim().isNotEmpty) {
      bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll(_escText('${invoiceHeading.trim().toUpperCase()}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);
    }

    // Divider
    bytes.addAll(_escText('${"-" * width}\n'));

    // Left align body (ESC a 0)
    bytes.addAll([0x1B, 0x61, 0x00]);
    bytes.addAll(_escText('Invoice: ${sale.invoiceNumber}\n'));
    bytes.addAll(_escText('Date: ${sale.createdAt.day}/${sale.createdAt.month}/${sale.createdAt.year} ${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}\n'));

    if (sale.customerName != null && sale.customerName!.isNotEmpty) {
      bytes.addAll(_escText('Customer: ${sale.customerName}\n'));
    }
    bytes.addAll(_escText('Payment: ${sale.paymentMethod.toUpperCase()}\n'));

    bytes.addAll(_escText('${"-" * width}\n'));

    // Column Headers: ITEM | QTY | AMT
    if (width == cols58mm) {
      bytes.addAll(_escText('Item             Qty      Amt\n'));
    } else {
      bytes.addAll(_escText('Item                          Qty       Amount\n'));
    }
    bytes.addAll(_escText('${"-" * width}\n'));

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
        bytes.addAll(_escText('$shortName $q $a\n'));
      } else {
        final shortName = name.length > 26 ? name.substring(0, 26) : name.padRight(26);
        final q = qtyStr.padLeft(8);
        final a = amtStr.padLeft(12);
        bytes.addAll(_escText('$shortName $q $a\n'));
      }
    }

    bytes.addAll(_escText('${"-" * width}\n'));

    // Total Amount (Bold)
    bytes.addAll([0x1B, 0x45, 0x01]);
    final String totalText = 'TOTAL: ${MoneyFormatter.formatINR(sale.totalAmountPaise)}';
    bytes.addAll([0x1B, 0x61, 0x02]); // Right align
    bytes.addAll(_escText('$totalText\n'));
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

    // UPI ID line if available
    if (storeUpiVpa != null && storeUpiVpa.isNotEmpty) {
      bytes.addAll([0x1B, 0x61, 0x01]); // Center
      bytes.addAll(_escText('UPI: $storeUpiVpa\n'));
    }

    // Footer — the merchant's own note from Invoice Themes when they set one,
    // falling back to the generic line only when they haven't.
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    final resolvedFooter = (footerNote != null && footerNote.trim().isNotEmpty)
        ? footerNote.trim()
        : 'Thank you for your visit!';
    bytes.addAll(_escText('\n$resolvedFooter\nKamaiPlus Smart POS\n\n\n'));

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
    bytes.addAll(_escText('KITCHEN ORDER\n'));
    bytes.addAll([0x1D, 0x21, 0x00]); // back to normal size

    if (sale.tableNumber != null && sale.tableNumber!.isNotEmpty) {
      bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll(_escText('TABLE ${sale.tableNumber}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);
    } else {
      bytes.addAll(_escText('PARCEL / TAKEAWAY\n'));
    }

    bytes.addAll(_escText('${"-" * width}\n'));
    bytes.addAll([0x1B, 0x61, 0x00]); // Left align
    bytes.addAll(_escText('Order: ${sale.invoiceNumber}\n'));
    bytes.addAll(_escText('Time: ${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}\n'));
    bytes.addAll(_escText('${"-" * width}\n'));

    // Items — name + qty large and bold, no prices anywhere on a KOT.
    for (var item in sale.items) {
      final String name = (item['product_name'] ?? 'Item').toString();
      final double qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final String qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
      final String? notes = item['notes']?.toString();

      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll(_escText('${qtyStr}x $name\n'));
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

      if (notes != null && notes.trim().isNotEmpty) {
        bytes.addAll(_escText('   >> ${notes.trim()}\n'));
      }
    }

    bytes.addAll(_escText('${"-" * width}\n'));
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll(_escText('\n\n'));

    // Auto-cut paper — no cash-drawer kick on a KOT.
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(bytes);
  }
}
