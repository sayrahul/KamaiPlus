import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../core/database/local_database.dart';
import 'thermal_printer_service.dart';
import 'invoice_pdf_service.dart';
import '../views/settings/printer_settings_screen.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.print_rounded, color: Colors.amberAccent, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('No Bluetooth printer configured. Please select your printer.')),
                ],
              ),
              action: SnackBarAction(
                label: 'Setup',
                textColor: Colors.amberAccent,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
                  );
                },
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
          );
        }
        return false;
      }

      if (showToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Printing bill #${sale.invoiceNumber} to $printerName...')),
              ],
            ),
            backgroundColor: const Color(0xFF0F172A),
            duration: const Duration(milliseconds: 1400),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

      final success = await ThermalPrinterService.printReceipt(
        sale: sale,
        printerMacAddress: printerAddress,
        is80mm: is80mm,
        kickCashDrawer: kickDrawer,
      );

      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not connect to "$printerName". Check printer power & Bluetooth.'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return success;
    }

    // 2. STANDARD A4 PRINTING (Android PrintManager Spooler)
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final storeName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';

      if (showToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 10),
                Expanded(child: Text('Opening A4 Print Spooler...')),
              ],
            ),
            backgroundColor: const Color(0xFF0F172A),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate invoice document.')),
          );
        }
        return false;
      }

      return await InvoicePdfService.printPdf(
        filePath: pdfPath,
        documentName: 'Invoice #${sale.invoiceNumber}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e')),
        );
      }
      return false;
    }
  }
}
