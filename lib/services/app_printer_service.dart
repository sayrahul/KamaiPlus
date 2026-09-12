import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../core/database/local_database.dart';
import 'thermal_printer_service.dart';
import 'invoice_pdf_service.dart';
import '../views/settings/printer_settings_screen.dart';
import '../views/common/in_app_notification.dart';

/// Central Unified Printer Service for KamaiPlus.
///
/// Ensures that whenever ANY print button is tapped across the entire app
/// (Sale Completed, Transaction Detail, POS Billing, Khata, etc.),
/// it automatically routes the job directly to the merchant's configured
/// default printer (Bluetooth ESC/POS thermal vs. Android System A4 Spooler)
/// without prompting or causing friction.
class AppPrinterService {
  AppPrinterService._();

  /// Automatically prints a completed or historical sale according to merchant settings
  static Future<bool> printSale({
    required BuildContext context,
    required SaleModel sale,
    bool showToast = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final printerType = prefs.getString('default_printer_type') ?? 'thermal'; // 'thermal' or 'a4'
    final printerAddress = prefs.getString('printer_mac_address');
    final printerName = prefs.getString('printer_device_name') ?? 'Bluetooth Thermal Printer';
    final is80mm = prefs.getBool('printer_is_80mm') ?? false;
    final kickDrawer = prefs.getBool('printer_kick_drawer') ?? true;

    // 1. THERMAL BLUETOOTH PRINTING (58mm / 80mm ESC/POS)
    if (printerType == 'thermal') {
      if (printerAddress == null || printerAddress.isEmpty) {
        // No Bluetooth printer configured yet -> prompt user to set it up
        if (context.mounted) {
          InAppNotification.show(
            context: context,
            message: 'No Bluetooth printer configured. Please select your printer.',
            customIcon: Icons.print_rounded,
            customColor: Colors.amberAccent,
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
          );
        }
        return false;
      }

      if (showToast && context.mounted) {
        InAppNotification.info(
          'Printing bill #${sale.invoiceNumber} to $printerName...',
          context: context,
        );
      }

      final success = await ThermalPrinterService.printReceipt(
        sale: sale,
        printerMacAddress: printerAddress,
        is80mm: is80mm,
        kickCashDrawer: kickDrawer,
      );

      if (!success && context.mounted) {
        InAppNotification.error('Could not connect to "$printerName". Check printer power & Bluetooth.', context: context);
      }
      return success;
    }

    // 2. STANDARD A4 PRINTING (Android PrintManager Spooler)
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final storeName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';

      if (showToast && context.mounted) {
        InAppNotification.show(
          context: context,
          message: 'Opening A4 Print Spooler...',
          type: NotificationType.info,
          duration: const Duration(milliseconds: 1200),
        );
      }

      final pdfPath = await InvoicePdfService.generateAndDownloadPdf(
        sale: sale,
        storeName: storeName,
        storePhone: profile.phone,
        storeAddress: profile.address,
        gstin: profile.gstin,
        logoPath: profile.logoUrl,
        customerPhone: sale.customerPhone,
      );

      if (pdfPath == null || pdfPath.isEmpty) {
        if (context.mounted) {
          InAppNotification.error('Failed to generate invoice document.', context: context);
        }
        return false;
      }

      return await InvoicePdfService.printPdf(
        filePath: pdfPath,
        documentName: 'Invoice #${sale.invoiceNumber}',
      );
    } catch (e) {
      if (context.mounted) {
        InAppNotification.error('Print error: $e', context: context);
      }
      return false;
    }
  }
}
