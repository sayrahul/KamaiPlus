import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/native_notification_service.dart';
import '../../services/app_printer_service.dart';
import '../../services/owner_pin_service.dart';
import '../../services/biometric_service.dart';
import '../common/store_logo_avatar.dart';
import '../common/pro_upgrade_modal.dart';
import '../common/in_app_notification.dart';

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

  void _printThermal(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await AppPrinterService.printSale(
      context: context,
      sale: sale,
    );
  }

  void _shareWhatsApp(BuildContext context) async {
    HapticFeedback.selectionClick();
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);
    final amtRupees = sale.totalAmountPaise ~/ 100;

    final profile = await LocalDatabase.instance.getStoreProfile();
    final sName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';
    final upiId = profile.upiVpa.trim();

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
    if (sale.paymentMethod == 'split') {
      final parts = <String>[];
      if (sale.splitCashPaise > 0) parts.add('Cash: ₹${sale.splitCashPaise ~/ 100}');
      if (sale.splitUpiPaise > 0) parts.add('UPI: ₹${sale.splitUpiPaise ~/ 100}');
      if (sale.splitCreditPaise > 0) parts.add('Udhar: ₹${sale.splitCreditPaise ~/ 100}');
      buffer.writeln('   Breakdown: ${parts.join(" • ")}');
    }
    if (upiId.isNotEmpty) {
      buffer.writeln('📌 *UPI ID:* $upiId');
    }
    buffer.writeln('\nThank you for your business! Visit again 🙏');

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
          InAppNotification.success('✓ Bill details copied to clipboard!', context: context);
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
        InAppNotification.show(
          context: context,
          message: '✓ Tax Invoice #${sale.invoiceNumber} PDF saved to Downloads!',
          actionLabel: 'OPEN',
          onAction: () => InvoicePdfService.openPdf(path),
        );
      } else if (context.mounted) {
        InAppNotification.error('Could not generate PDF invoice.', context: context);
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
        forceChooser: true,
      );
      if (!ok && context.mounted) {
        InAppNotification.error('Could not open share dialog', context: context);
      }
    } catch (_) {}
  }

  Future<CustomerModel?> _pickOrAddCustomer(BuildContext context) async {
    final customers = await LocalDatabase.instance.getAllCustomers();
    if (!context.mounted) return null;

    return await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        String query = '';
        final nameCtrl = TextEditingController();
        final phoneCtrl = TextEditingController();
        bool isCreatingNew = false;
        String? createError;

        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final filtered = customers.where((c) {
              final q = query.toLowerCase();
              return c.name.toLowerCase().contains(q) || c.phone.contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isCreatingNew ? 'New Customer for Credit' : 'Select Customer for Credit',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setLocalState(() {
                            isCreatingNew = !isCreatingNew;
                            createError = null;
                          });
                        },
                        child: Text(
                          isCreatingNew ? 'Search Existing' : '+ Add New',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!isCreatingNew) ...[
                    TextField(
                      onChanged: (v) => setLocalState(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name or mobile number...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  'No matching customer found.\nTap "+ Add New" above to create.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) => const Divider(height: 1),
                              itemBuilder: (c, idx) {
                                final cust = filtered[idx];
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFFEFF6FF),
                                    child: Text(
                                      cust.name.isNotEmpty ? cust.name[0].toUpperCase() : 'C',
                                      style: const TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(cust.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                                  subtitle: Text(cust.phone, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                  trailing: Text(
                                    cust.currentBalancePaise > 0
                                        ? 'Udhar: ${MoneyFormatter.formatINR(cust.currentBalancePaise)}'
                                        : (cust.currentBalancePaise < 0
                                            ? 'Jama: ${MoneyFormatter.formatINR(cust.currentBalancePaise.abs())}'
                                            : 'Settled'),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: cust.currentBalancePaise > 0
                                          ? const Color(0xFFDC2626)
                                          : (cust.currentBalancePaise < 0 ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(sheetCtx, cust),
                                );
                              },
                            ),
                    ),
                  ] else ...[
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Customer Name *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: '10-Digit Mobile Number *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        counterText: '',
                        errorText: createError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          if (name.isEmpty) {
                            setLocalState(() => createError = 'Please enter name');
                            return;
                          }
                          if (phone.length != 10) {
                            setLocalState(() => createError = 'Please enter valid 10-digit mobile number');
                            return;
                          }
                          final existing = await LocalDatabase.instance.findCustomerByPhone(phone);
                          if (existing != null) {
                            if (sheetCtx.mounted) {
                              Navigator.pop(sheetCtx, existing);
                            }
                            return;
                          }
                          final newCust = CustomerModel(
                            id: const Uuid().v4(),
                            businessId: sale.businessId,
                            name: name,
                            phone: phone,
                            currentBalancePaise: 0,
                          );
                          await LocalDatabase.instance.upsertCustomer(newCust);
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx, newCust);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Save & Select Customer'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
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

    CustomerModel? linkedCustomer;
    if (sale.customerId != null && sale.customerId!.isNotEmpty) {
      final custs = await LocalDatabase.instance.getAllCustomers();
      try {
        linkedCustomer = custs.firstWhere((c) => c.id == sale.customerId);
      } catch (_) {}
    } else if (sale.customerPhone != null && sale.customerPhone!.isNotEmpty) {
      linkedCustomer = await LocalDatabase.instance.findCustomerByPhone(sale.customerPhone!);
    }

    String selectedRefundMethod = isUdhar ? 'credit' : 'cash';
    final pinController = TextEditingController();
    String? pinError;
    // Resolved before the dialog is built: the fingerprint button only appears
    // on a handset that actually has an enrolled biometric, rather than
    // offering an option that fails when tapped.
    final bool biometricAvailable = await BiometricService.instance.isBiometricAvailable();
    bool verifiedByBiometric = false;

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                child: const Icon(Icons.shield_outlined, color: Color(0xFFDC2626), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Security PIN & Refund',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Authorized return & stock reversal',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All items of Invoice #${sale.invoiceNumber} will be restored to inventory:',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                ),
                const SizedBox(height: 8),
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
                Text(
                  'REFUND METHOD',
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569), letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ChoiceChip(
                      label: Text('Cash', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      selected: selectedRefundMethod == 'cash',
                      selectedColor: const Color(0xFFECFDF5),
                      labelStyle: TextStyle(color: selectedRefundMethod == 'cash' ? const Color(0xFF065F46) : const Color(0xFF64748B)),
                      onSelected: (v) {
                        if (v) setDialogState(() => selectedRefundMethod = 'cash');
                      },
                    ),
                    const SizedBox(width: 8),
                    if (isUdhar) ...[
                      ChoiceChip(
                        label: Text('Reverse Udhar', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        selected: selectedRefundMethod == 'credit',
                        selectedColor: const Color(0xFFFFF1F2),
                        labelStyle: TextStyle(color: selectedRefundMethod == 'credit' ? const Color(0xFF991B1B) : const Color(0xFF64748B)),
                        onSelected: (v) {
                          if (v) setDialogState(() => selectedRefundMethod = 'credit');
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    ChoiceChip(
                      label: Text('Store Credit', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      selected: selectedRefundMethod == 'credit_note',
                      selectedColor: const Color(0xFFEFF6FF),
                      labelStyle: TextStyle(color: selectedRefundMethod == 'credit_note' ? const Color(0xFF1D4ED8) : const Color(0xFF64748B)),
                      onSelected: (v) {
                        if (v) setDialogState(() => selectedRefundMethod = 'credit_note');
                      },
                    ),
                  ],
                ),
                if (selectedRefundMethod == 'credit_note') ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await _pickOrAddCustomer(context);
                      if (picked != null) {
                        setDialogState(() => linkedCustomer = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: linkedCustomer != null ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: linkedCustomer != null ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            linkedCustomer != null ? Icons.account_circle_rounded : Icons.person_add_alt_1_rounded,
                            size: 16,
                            color: linkedCustomer != null ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              linkedCustomer != null
                                  ? 'Credit to: ${linkedCustomer!.name} (${linkedCustomer!.phone})'
                                  : 'Tap to Link Customer *',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: linkedCustomer != null ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                          Text(
                            linkedCustomer != null ? 'Change' : 'Select',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: linkedCustomer != null ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'ENTER OWNER / MANAGER PIN *',
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569), letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '••••',
                    hintStyle: GoogleFonts.outfit(fontSize: 22, color: const Color(0xFF94A3B8), letterSpacing: 8),
                    counterText: '',
                    errorText: pinError,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  verifiedByBiometric
                      ? '✅ Fingerprint verified • Action will be logged to Audit Trail'
                      : '🔒 Owner PIN (same as the one behind the eye button) • Action will be logged to Audit Trail',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: verifiedByBiometric ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                    fontWeight: verifiedByBiometric ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (biometricAvailable && !verifiedByBiometric) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await BiometricService.instance.authenticateOwner(
                          reason: 'Confirm this return with your fingerprint',
                        );
                        if (ok) {
                          HapticFeedback.mediumImpact();
                          setDialogState(() {
                            verifiedByBiometric = true;
                            pinError = null;
                          });
                        }
                      },
                      icon: const Icon(Icons.fingerprint_rounded, size: 20, color: Color(0xFF0F172A)),
                      label: Text(
                        'Use Fingerprint Instead',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final enteredPin = pinController.text.trim();
                // A fingerprint IS the owner check — do not then demand the PIN
                // as well. Otherwise the biometric option is decoration.
                if (!verifiedByBiometric) {
                  if (enteredPin.length < 4) {
                    setDialogState(() => pinError = 'Enter your 4-digit owner PIN');
                    HapticFeedback.heavyImpact();
                    return;
                  }
                  // The owner's real PIN, not a hardcoded '1234'/'0000' pair.
                  // Those literals meant an owner who changed their PIN still
                  // had two publicly-known codes authorising a cash refund.
                  if (!await OwnerPinService.instance.verify(enteredPin)) {
                    setDialogState(() => pinError = 'Wrong PIN. Use your owner PIN (the one set on the eye button).');
                    HapticFeedback.heavyImpact();
                    return;
                  }
                }
                if (selectedRefundMethod == 'credit_note' && linkedCustomer == null) {
                  setDialogState(() => pinError = 'Please link a customer for Store Credit');
                  HapticFeedback.heavyImpact();
                  return;
                }

                // Verifying the PIN is now async, so the dialog could have been
                // dismissed while we were waiting on it.
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                HapticFeedback.heavyImpact();

                try {
                  // 1. Record in Security Audit Logs
                  await LocalDatabase.instance.logAuditAction(
                    action: 'SALES_RETURN_REFUND',
                    details: 'Invoice #${sale.invoiceNumber} returned (${sale.items.length} items). Method: $selectedRefundMethod.',
                    amountPaise: sale.totalAmountPaise,
                    userPin: verifiedByBiometric ? 'BIOMETRIC' : enteredPin,
                  );

                  // 2. Process Sales Return
                  await LocalDatabase.instance.processSalesReturn(
                    sale: sale,
                    refundMethod: selectedRefundMethod,
                    reason: 'Full Void / Customer Return',
                    customerId: linkedCustomer?.id,
                  );

                  await NativeNotificationService.showNotification(
                    title: '↩️ Sales Return Done: #${sale.invoiceNumber}',
                    body: 'Stock restored to inventory & $selectedRefundMethod refund recorded.',
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    InAppNotification.success(
                      'Invoice #${sale.invoiceNumber} returned! Stock restocked & records updated.',
                      context: context,
                    );
                  }
                  onVoidOrRefund?.call();
                } catch (e) {
                  if (context.mounted) {
                    InAppNotification.error('Return error: $e', context: context);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: Text('Authorize & Return', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _openPartialReturnSheet(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final profile = await LocalDatabase.instance.getStoreProfile();
    if (!profile.isPro) {
      if (context.mounted) {
        ProUpgradeModal.show(
          context,
          triggerFeature: 'Sales Return & Item Refund (Strictly Pro Feature)',
        );
      }
      return;
    }
    if (!context.mounted) return;

    final isUdhar = sale.paymentMethod == 'credit' || (sale.paymentMethod == 'split' && sale.splitCreditPaise > 0);

    CustomerModel? linkedCustomer;
    if (sale.customerId != null && sale.customerId!.isNotEmpty) {
      final custs = await LocalDatabase.instance.getAllCustomers();
      try {
        linkedCustomer = custs.firstWhere((c) => c.id == sale.customerId);
      } catch (_) {}
    } else if (sale.customerPhone != null && sale.customerPhone!.isNotEmpty) {
      linkedCustomer = await LocalDatabase.instance.findCustomerByPhone(sale.customerPhone!);
    }

    final returnQtys = <int, double>{};
    for (int i = 0; i < sale.items.length; i++) {
      returnQtys[i] = 0.0;
    }

    String selectedRefundMethod = isUdhar ? 'credit' : 'cash';
    final reasonController = TextEditingController(text: 'Customer Return');
    final pinController = TextEditingController();
    String? pinError;
    final bool biometricAvailable = await BiometricService.instance.isBiometricAvailable();
    bool verifiedByBiometric = false;

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          int totalRefundPaise = 0;
          int totalItemsToReturn = 0;

          for (int i = 0; i < sale.items.length; i++) {
            final qty = returnQtys[i] ?? 0.0;
            if (qty > 0) {
              // Valued by SaleModel, the same helper processPartialSalesReturn
              // uses — so what this sheet shows is exactly what gets refunded.
              // This previously read `price_paise`/`selling_price_paise`, keys
              // that do not exist on a sale item, so the total stayed ₹0 no
              // matter how many items the cashier picked.
              totalRefundPaise += sale.refundPaiseForItem(i, qty);
              totalItemsToReturn += qty.toInt();
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.assignment_return_rounded, color: Color(0xFFE11D48), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Return Items / टुकड़ों में वापसी',
                              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            ),
                            Text(
                              'Invoice #${sale.invoiceNumber} • Choose items to return',
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SELECT ITEMS & QUANTITY TO RETURN',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569), letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(sale.items.length, (i) {
                    final it = sale.items[i];
                    final name = it['product_name'] ?? it['name'] ?? 'Item';
                    final num soldQty = it['quantity'] ?? it['qty'] ?? 1;
                    // Per-unit value the customer actually paid, derived from
                    // the line total so it matches the refund maths exactly
                    // (tax and bill discount included). The old
                    // `price_paise`/`selling_price_paise` lookup found nothing
                    // and rendered every row as "₹0.00/unit".
                    final int price = soldQty > 0
                        ? (sale.lineEffectivePaidPaise(i) / soldQty).round()
                        : 0;
                    final num alreadyReturned = it['returned_quantity'] ?? 0;
                    final maxReturnable = (soldQty - alreadyReturned).clamp(0, soldQty).toDouble();
                    final currentReturnQty = returnQtys[i] ?? 0.0;
                    final bool isFullyReturned = maxReturnable <= 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isFullyReturned ? const Color(0xFFF8FAFC) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: currentReturnQty > 0 ? const Color(0xFFFDA4AF) : const Color(0xFFE2E8F0),
                          width: currentReturnQty > 0 ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.toString(),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isFullyReturned ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                                    decoration: isFullyReturned ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${MoneyFormatter.formatINR(price)}/unit • Sold: $soldQty ${alreadyReturned > 0 ? "(Prev ret: $alreadyReturned)" : ""}',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          if (isFullyReturned) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Fully Returned',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8)),
                              ),
                            ),
                          ] else ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: currentReturnQty > 0
                                        ? () {
                                            HapticFeedback.selectionClick();
                                            setSheetState(() {
                                              returnQtys[i] = (currentReturnQty - 1).clamp(0.0, maxReturnable);
                                            });
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: currentReturnQty > 0 ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.remove, size: 16, color: currentReturnQty > 0 ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    currentReturnQty.toInt().toString(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: currentReturnQty > 0 ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: currentReturnQty < maxReturnable
                                        ? () {
                                            HapticFeedback.selectionClick();
                                            setSheetState(() {
                                              returnQtys[i] = (currentReturnQty + 1).clamp(0.0, maxReturnable);
                                            });
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: currentReturnQty < maxReturnable ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.add, size: 16, color: currentReturnQty < maxReturnable ? const Color(0xFFE11D48) : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    'REFUND METHOD',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569), letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: Text('Cash Refund', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        selected: selectedRefundMethod == 'cash',
                        selectedColor: const Color(0xFFECFDF5),
                        labelStyle: TextStyle(color: selectedRefundMethod == 'cash' ? const Color(0xFF065F46) : const Color(0xFF64748B)),
                        onSelected: (v) {
                          if (v) setSheetState(() => selectedRefundMethod = 'cash');
                        },
                      ),
                      const SizedBox(width: 8),
                      if (isUdhar) ...[
                        ChoiceChip(
                          label: Text('Reverse Udhar', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          selected: selectedRefundMethod == 'credit',
                          selectedColor: const Color(0xFFFFF1F2),
                          labelStyle: TextStyle(color: selectedRefundMethod == 'credit' ? const Color(0xFF991B1B) : const Color(0xFF64748B)),
                          onSelected: (v) {
                            if (v) setSheetState(() => selectedRefundMethod = 'credit');
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      ChoiceChip(
                        label: Text('Store Credit', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        selected: selectedRefundMethod == 'credit_note',
                        selectedColor: const Color(0xFFEFF6FF),
                        labelStyle: TextStyle(color: selectedRefundMethod == 'credit_note' ? const Color(0xFF1D4ED8) : const Color(0xFF64748B)),
                        onSelected: (v) {
                          if (v) setSheetState(() => selectedRefundMethod = 'credit_note');
                        },
                      ),
                    ],
                  ),
                  if (selectedRefundMethod == 'credit_note') ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await _pickOrAddCustomer(context);
                        if (picked != null) {
                          setSheetState(() => linkedCustomer = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: linkedCustomer != null ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: linkedCustomer != null ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              linkedCustomer != null ? Icons.account_circle_rounded : Icons.person_add_alt_1_rounded,
                              size: 18,
                              color: linkedCustomer != null ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                linkedCustomer != null
                                    ? 'Store Credit Account: ${linkedCustomer!.name} (${linkedCustomer!.phone})'
                                    : 'Tap to Link Customer for Store Credit *',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: linkedCustomer != null ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                            Text(
                              linkedCustomer != null ? 'Change' : 'Select',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: linkedCustomer != null ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Refund Amount ($totalItemsToReturn items)',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                        ),
                        Text(
                          MoneyFormatter.formatINR(totalRefundPaise),
                          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFFE11D48)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    verifiedByBiometric ? 'OWNER VERIFIED BY FINGERPRINT' : 'OWNER PIN *',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: verifiedByBiometric ? const Color(0xFF16A34A) : const Color(0xFF475569),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (biometricAvailable && !verifiedByBiometric) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await BiometricService.instance.authenticateOwner(
                            reason: 'Confirm this return with your fingerprint',
                          );
                          if (ok) {
                            HapticFeedback.mediumImpact();
                            setSheetState(() {
                              verifiedByBiometric = true;
                              pinError = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.fingerprint_rounded, size: 20, color: Color(0xFF0F172A)),
                        label: Text(
                          'Use Fingerprint',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle: GoogleFonts.outfit(fontSize: 20, color: const Color(0xFF94A3B8), letterSpacing: 8),
                      counterText: '',
                      errorText: pinError,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE11D48), width: 1.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: totalItemsToReturn == 0
                              ? null
                              : () async {
                                  final enteredPin = pinController.text.trim();
                                  // Same single owner PIN as the eye button, or
                                  // a fingerprint in its place.
                                  if (!verifiedByBiometric &&
                                      !await OwnerPinService.instance.verify(enteredPin)) {
                                    setSheetState(() => pinError =
                                        'Wrong PIN. Use your owner PIN (the one set on the eye button).');
                                    HapticFeedback.heavyImpact();
                                    return;
                                  }
                                  if (selectedRefundMethod == 'credit_note' && linkedCustomer == null) {
                                    setSheetState(() => pinError = 'Please link a customer for Store Credit');
                                    HapticFeedback.heavyImpact();
                                    return;
                                  }

                                  // Verifying the PIN is now async, so the
                                  // sheet could have been dismissed meanwhile.
                                  if (!sheetCtx.mounted) return;
                                  Navigator.pop(sheetCtx);
                                  HapticFeedback.heavyImpact();

                                  final itemsToReturn = <Map<String, dynamic>>[];
                                  for (int i = 0; i < sale.items.length; i++) {
                                    final it = sale.items[i];
                                    final returnQty = returnQtys[i] ?? 0.0;
                                    if (returnQty > 0) {
                                      itemsToReturn.add({
                                        // `item_index` lets the database value
                                        // this against the exact line it came
                                        // from — two lines on one bill can be
                                        // the same product at different prices.
                                        'item_index': i,
                                        'product_id': it['product_id'] ?? it['id'],
                                        'product_name': it['product_name'] ?? it['name'] ?? 'Item',
                                        'return_quantity': returnQty,
                                        // Recorded on the return receipt for
                                        // reference. The refund the customer
                                        // actually gets is recomputed from the
                                        // sale inside processPartialSalesReturn
                                        // — the screen does not get to decide
                                        // the money.
                                        'refund_paise': sale.refundPaiseForItem(i, returnQty),
                                        if (it['batch_id'] != null) 'batch_id': it['batch_id'],
                                      });
                                    }
                                  }

                                  try {
                                    final retNum = await LocalDatabase.instance.processPartialSalesReturn(
                                      sale: sale,
                                      returnItems: itemsToReturn,
                                      refundMethod: selectedRefundMethod,
                                      reason: reasonController.text.trim(),
                                      userPin: verifiedByBiometric ? 'BIOMETRIC' : enteredPin,
                                      customerId: linkedCustomer?.id,
                                    );

                                    await NativeNotificationService.showNotification(
                                      title: '↩️ Return Processed: $retNum',
                                      body: '$totalItemsToReturn item(s) restocked. Refund: ${MoneyFormatter.formatINR(totalRefundPaise)} ($selectedRefundMethod)',
                                    );

                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      InAppNotification.success(
                                        'Return #$retNum processed! $totalItemsToReturn item(s) restocked.',
                                        context: context,
                                      );
                                    }
                                    onVoidOrRefund?.call();
                                  } catch (e) {
                                    if (context.mounted) {
                                      InAppNotification.error('Return failed: $e', context: context);
                                    }
                                  }
                                },
                          icon: const Icon(Icons.check_circle_rounded, size: 16),
                          label: Text(
                            'Process Return (${MoneyFormatter.formatINR(totalRefundPaise)})',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE11D48),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(sale.createdAt);
    final isRefunded = sale.isRefunded;
    final isPartiallyRefunded = sale.status == 'partially_refunded';
    final isUdhar = sale.paymentMethod == 'credit';
    final isUpi = sale.paymentMethod == 'upi';
    final isSplit = sale.paymentMethod == 'split';
    final modeBadgeText = isRefunded
        ? 'REFUNDED / RETURNED'
        : (isPartiallyRefunded
            ? 'PARTIALLY RETURNED'
            : (isSplit
                ? 'SPLIT PAYMENT'
                : (isUdhar ? 'CREDIT / UDHAR' : (isUpi ? 'UPI DIGITAL' : 'CASH COUNTER'))));
    final modeBadgeBg = isRefunded
        ? const Color(0xFFFEE2E2)
        : (isPartiallyRefunded
            ? const Color(0xFFFEF3C7)
            : (isSplit
                ? const Color(0xFFEEF2FF)
                : (isUdhar ? const Color(0xFFFEF2F2) : (isUpi ? const Color(0xFFF0F9FF) : const Color(0xFFECFDF5)))));
    final modeBadgeColor = isRefunded
        ? const Color(0xFFDC2626)
        : (isPartiallyRefunded
            ? const Color(0xFFD97706)
            : (isSplit
                ? const Color(0xFF6366F1)
                : (isUdhar ? const Color(0xFFDC2626) : (isUpi ? const Color(0xFF0284C7) : const Color(0xFF059669)))));

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
                  final num returnedQty = it['returned_quantity'] ?? 0;
                  final pricePaise = it['gross_total_paise'] ?? ((it['price'] as int? ?? 0) * (qty as num).toInt());
                  final isItemReturned = returnedQty >= qty;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${qty}x $name',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: isItemReturned ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                                    decoration: isItemReturned ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              if (returnedQty > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isItemReturned ? 'Returned' : 'Ret: $returnedQty',
                                    style: GoogleFonts.inter(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          MoneyFormatter.formatINR(pricePaise as int),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isItemReturned ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                            decoration: isItemReturned ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 16, color: Color(0xFFE2E8F0)),
                if (sale.isPartiallyRefunded) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Original Billed',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                      Text(
                        MoneyFormatter.formatINR(sale.totalAmountPaise),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Refunded Items',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFE11D48)),
                      ),
                      Text(
                        '- ${MoneyFormatter.formatINR(sale.totalRefundedPaise)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE11D48),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      sale.isPartiallyRefunded ? 'Net Payable / Kept' : 'Total Payable',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      MoneyFormatter.formatINR(sale.isPartiallyRefunded ? sale.netAmountPaise : sale.totalAmountPaise),
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

          // Split Payment Breakdown Card
          if (sale.paymentMethod == 'split') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.call_split_rounded, size: 15, color: Color(0xFF6366F1)),
                      const SizedBox(width: 6),
                      Text(
                        'Split Payment Breakdown',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (sale.splitCashPaise > 0)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cash', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                                const SizedBox(height: 2),
                                Text(
                                  MoneyFormatter.formatINR(sale.splitCashPaise),
                                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (sale.splitCashPaise > 0 && sale.splitUpiPaise > 0) const SizedBox(width: 6),
                      if (sale.splitUpiPaise > 0)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('UPI', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                                const SizedBox(height: 2),
                                Text(
                                  MoneyFormatter.formatINR(sale.splitUpiPaise),
                                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0284C7)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if ((sale.splitCashPaise > 0 || sale.splitUpiPaise > 0) && sale.splitCreditPaise > 0) const SizedBox(width: 6),
                      if (sale.splitCreditPaise > 0)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Udhar (Credit)', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                                const SizedBox(height: 2),
                                Text(
                                  MoneyFormatter.formatINR(sale.splitCreditPaise),
                                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Return Receipts History (If any return occurred)
          if (sale.isPartiallyRefunded || sale.isRefunded) ...[
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: LocalDatabase.instance.getSaleReturns(sale.id),
              builder: (ctx, snapshot) {
                final returns = snapshot.data ?? [];
                if (returns.isEmpty) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.assignment_return_rounded, size: 16, color: Color(0xFFE11D48)),
                              const SizedBox(width: 6),
                              Text(
                                'Return Receipts History (${returns.length})',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF9F1239),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '- ${MoneyFormatter.formatINR(sale.totalRefundedPaise)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFE11D48),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...returns.map((ret) {
                        final retNum = ret['return_number'] ?? 'RET';
                        final method = (ret['refund_method'] ?? 'cash').toString().toUpperCase();
                        final amt = (ret['total_refund_paise'] as int?) ?? 0;
                        final dateStr = ret['created_at'] != null
                            ? DateFormat('d MMM, hh:mm a').format(DateTime.tryParse(ret['created_at']) ?? DateTime.now())
                            : '';
                        final methodLabel = method == 'CREDIT_NOTE'
                            ? 'STORE CREDIT'
                            : (method == 'CREDIT' ? 'UDHAR REVERSAL' : 'CASH REFUND');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFFE4E6)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$retNum • $methodLabel',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF881337),
                                    ),
                                  ),
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                              Text(
                                MoneyFormatter.formatINR(amt),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFE11D48),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ],
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

          // Sales Return Actions
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
                    'Bill Fully Returned • Stock Restored',
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
            Row(
              children: [
                // Partial Return (Return Specific Items)
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _openPartialReturnSheet(context),
                    icon: const Icon(Icons.assignment_return_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'Return Items (टुकड़ों में वापसी)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Full Bill Cancel / Void
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmSalesReturn(context),
                    icon: const Icon(Icons.cancel_outlined, size: 15, color: Color(0xFF64748B)),
                    label: Text(
                      'Full Void',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
