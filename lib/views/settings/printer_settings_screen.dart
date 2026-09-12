import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../common/in_app_notification.dart';
import '../../services/thermal_printer_service.dart';
import '../../services/invoice_pdf_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  static const _channel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  String _printerType = 'thermal'; // 'thermal' or 'a4'
  String? _selectedMac;
  String? _selectedDeviceName;
  bool _is80mm = false;
  bool _kickDrawer = true;
  bool _autoPrintOnCheckout = false;
  bool _directOneTapPrint = true;

  List<Map<String, String>> _pairedDevices = [];
  bool _isLoadingDevices = false;
  bool _isTestingPrint = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchPairedDevices();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _printerType = prefs.getString('default_printer_type') ?? 'thermal';
      _selectedMac = prefs.getString('printer_mac_address');
      _selectedDeviceName = prefs.getString('printer_device_name');
      _is80mm = prefs.getBool('printer_is_80mm') ?? false;
      _kickDrawer = prefs.getBool('printer_kick_drawer') ?? true;
      _autoPrintOnCheckout = prefs.getBool('auto_print_on_checkout') ?? false;
      _directOneTapPrint = prefs.getBool('direct_one_tap_print') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_printer_type', _printerType);
    if (_selectedMac != null) {
      await prefs.setString('printer_mac_address', _selectedMac!);
    }
    if (_selectedDeviceName != null) {
      await prefs.setString('printer_device_name', _selectedDeviceName!);
    }
    await prefs.setBool('printer_is_80mm', _is80mm);
    await prefs.setBool('printer_kick_drawer', _kickDrawer);
    await prefs.setBool('auto_print_on_checkout', _autoPrintOnCheckout);
    await prefs.setBool('direct_one_tap_print', _directOneTapPrint);
  }

  Future<void> _fetchPairedDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getPairedDevices');
      final list = <Map<String, String>>[];
      if (res != null) {
        for (var d in res) {
          final m = Map<String, dynamic>.from(d);
          list.add({
            'name': m['name']?.toString() ?? 'Bluetooth Printer',
            'address': m['address']?.toString() ?? '',
          });
        }
      }
      setState(() {
        _pairedDevices = list;
        _isLoadingDevices = false;
      });
    } catch (_) {
      setState(() => _isLoadingDevices = false);
    }
  }

  Future<void> _selectDevice(String address, String name) async {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMac = address;
      _selectedDeviceName = name;
    });
    await _saveSettings();
  }

  Future<void> _testThermalPrint() async {
    if (_selectedMac == null || _selectedMac!.isEmpty) {
      InAppNotification.error('Please select a paired Bluetooth printer first!', context: context);
      return;
    }

    setState(() => _isTestingPrint = true);
    HapticFeedback.mediumImpact();

    final testSale = SaleModel(
      id: 'test_print',
      businessId: 'test_biz',
      invoiceNumber: 'TEST-${DateTime.now().millisecondsSinceEpoch % 10000}',
      subtotalPaise: 49900,
      totalAmountPaise: 49900,
      discountPaise: 0,
      taxAmountPaise: 0,
      paymentMethod: 'cash',
      status: 'completed',
      customerName: 'Test Customer',
      customerPhone: '9876543210',
      createdAt: DateTime.now(),
      items: [
        {
          'product_name': 'KamaiPlus Thermal Test',
          'quantity': 1,
          'gross_total_paise': 49900,
          'unit_price_paise': 49900,
        },
      ],
    );

    final success = await ThermalPrinterService.printReceipt(
      sale: testSale,
      printerMacAddress: _selectedMac,
      is80mm: _is80mm,
      kickCashDrawer: _kickDrawer,
    );

    setState(() => _isTestingPrint = false);

    if (mounted) {
      if (success) {
        InAppNotification.success('Test receipt printed successfully!', context: context);
      } else {
        InAppNotification.error('Failed to print. Check printer connection.', context: context);
      }
    }
  }

  Future<void> _testA4Print() async {
    setState(() => _isTestingPrint = true);
    HapticFeedback.mediumImpact();

    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final storeName = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store';

      final testSale = SaleModel(
        id: 'test_a4',
        businessId: 'test_biz',
        invoiceNumber: 'TEST-${DateTime.now().millisecondsSinceEpoch % 10000}',
        subtotalPaise: 49900,
        totalAmountPaise: 49900,
        discountPaise: 0,
        taxAmountPaise: 0,
        paymentMethod: 'cash',
        status: 'completed',
        customerName: 'Test Customer',
        customerPhone: '9876543210',
        createdAt: DateTime.now(),
        items: [
          {
            'product_name': 'Sample Retail Item 1',
            'quantity': 2,
            'gross_total_paise': 29900,
            'unit_price_paise': 14950,
          },
          {
            'product_name': 'Sample Retail Item 2',
            'quantity': 1,
            'gross_total_paise': 20000,
            'unit_price_paise': 20000,
          },
        ],
      );

      final pdfPath = await InvoicePdfService.generateAndDownloadPdf(
        sale: testSale,
        storeName: storeName,
        storePhone: profile.phone,
        storeAddress: profile.address,
        gstin: profile.gstin,
        customerPhone: '9876543210',
      );

      if (pdfPath != null) {
        await InvoicePdfService.printPdf(
          filePath: pdfPath,
          documentName: 'Sample Tax Invoice',
        );
      }
    } catch (_) {}

    setState(() => _isTestingPrint = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'Printer & Hardware Setup',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Bluetooth Devices',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0284C7)),
            onPressed: _fetchPairedDevices,
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Current Active Printer Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _printerType == 'thermal' ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _printerType == 'thermal' ? Icons.receipt_rounded : Icons.print_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _printerType == 'thermal' ? 'THERMAL RECEIPT PRINTER' : 'STANDARD A4 PRINTER',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF94A3B8),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _printerType == 'thermal'
                            ? (_selectedDeviceName != null ? '$_selectedDeviceName (${_is80mm ? "80mm" : "58mm"})' : 'No Bluetooth Printer Paired')
                            : 'Android Print Spooler (Wi-Fi / USB)',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF34D399),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Select Default Printer Mode
          _buildSectionHeader('SELECT DEFAULT PRINTER MODE'),
          const SizedBox(height: 8),

          // Option A: Bluetooth Thermal Printer
          _buildPrinterTypeCard(
            type: 'thermal',
            title: 'Bluetooth Thermal Printer (ESC/POS)',
            badge: 'FASTEST ⚡',
            badgeColor: const Color(0xFF7C3AED),
            subtitle: 'Portable 58mm / 80mm wireless receipt roll printer. Instant zero-ink printing.',
            icon: Icons.receipt_long_rounded,
          ),
          const SizedBox(height: 10),

          // Option B: Standard A4 Printer
          _buildPrinterTypeCard(
            type: 'a4',
            title: 'Standard A4 / Full Page Printer',
            badge: 'TAX INVOICE',
            badgeColor: const Color(0xFF0284C7),
            subtitle: 'Full-size GST Tax Invoice PDF via Wi-Fi, USB, Mopria or Canon/HP/Epson spooler.',
            icon: Icons.description_rounded,
          ),
          const SizedBox(height: 22),

          // 3. Properties for Thermal Printer
          if (_printerType == 'thermal') ...[
            _buildSectionHeader('THERMAL PRINTER PROPERTIES'),
            const SizedBox(height: 8),

            // Roll Width Selector
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paper Roll Width',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select paper width matching your thermal device roll.',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildWidthOption(
                          label: '58 mm',
                          desc: '2 Inch (32 columns)',
                          selected: !_is80mm,
                          onTap: () {
                            setState(() => _is80mm = false);
                            _saveSettings();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildWidthOption(
                          label: '80 mm',
                          desc: '3 Inch (48 columns)',
                          selected: _is80mm,
                          onTap: () {
                            setState(() => _is80mm = true);
                            _saveSettings();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Bluetooth Devices List
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Paired Bluetooth Printers',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                      if (_isLoadingDevices)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        InkWell(
                          onTap: _fetchPairedDevices,
                          child: Text(
                            'Refresh',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to select your thermal printer from bonded Bluetooth devices.',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),

                  if (_pairedDevices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bluetooth_searching_rounded, color: Color(0xFFD97706), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No paired Bluetooth printers found.',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF92400E)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Please turn on your printer, open Android Settings > Bluetooth, pair the device, then tap Refresh.',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _pairedDevices.length,
                      separatorBuilder: (_, _) => const Divider(height: 8, color: Color(0xFFF1F5F9)),
                      itemBuilder: (context, idx) {
                        final d = _pairedDevices[idx];
                        final name = d['name'] ?? 'Printer';
                        final address = d['address'] ?? '';
                        final isSel = _selectedMac == address;

                        return InkWell(
                          onTap: () => _selectDevice(address, name),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFF0FDF4) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isSel ? Border.all(color: const Color(0xFF86EFAC)) : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.bluetooth_connected_rounded,
                                  color: isSel ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                          color: isSel ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        address,
                                        style: GoogleFonts.robotoMono(fontSize: 10.5, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSel)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Cash Drawer Kick Switch
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _kickDrawer,
                onChanged: (val) {
                  setState(() => _kickDrawer = val);
                  _saveSettings();
                },
                title: Text(
                  'Kick Cash Drawer on Print',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                ),
                subtitle: Text(
                  'Sends ESC/POS pulse to open electronic cash drawer automatically',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
                activeTrackColor: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 14),

            // Test Thermal Print Button
            ElevatedButton(
              onPressed: _isTestingPrint ? null : _testThermalPrint,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flash_on_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _isTestingPrint ? 'Sending Test Print...' : '⚡ Print Test Receipt',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Properties for A4 Printer
            _buildSectionHeader('A4 PRINTER PROPERTIES'),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Spooler Integration',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kamai+ uses the Android System PrintManager to send crisp vector PDF invoices to all Wi-Fi, Network, USB, and Cloud printers.',
                    style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Test A4 Print Button
            ElevatedButton(
              onPressed: _isTestingPrint ? null : _testA4Print,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.print_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _isTestingPrint ? 'Opening Spooler...' : '⚡ Print Test A4 Bill',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // 4. Global Printing Workflow
          _buildSectionHeader('PRINT WORKFLOW SETTINGS'),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _directOneTapPrint,
                  onChanged: (val) {
                    setState(() => _directOneTapPrint = val);
                    _saveSettings();
                  },
                  title: Text(
                    'Direct 1-Tap Print Everywhere',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  ),
                  subtitle: Text(
                    'Tapping "Print" anywhere instantly sends bill to active printer without showing extra dialogs',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                  activeTrackColor: const Color(0xFF10B981),
                ),
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _autoPrintOnCheckout,
                  onChanged: (val) {
                    setState(() => _autoPrintOnCheckout = val);
                    _saveSettings();
                  },
                  title: Text(
                    'Auto-Print on Checkout',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  ),
                  subtitle: Text(
                    'Automatically trigger print job as soon as payment is confirmed',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                  activeTrackColor: const Color(0xFF10B981),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF64748B),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildPrinterTypeCard({
    required String type,
    required String title,
    required String badge,
    required Color badgeColor,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _printerType == type;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _printerType = type);
        _saveSettings();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? badgeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? badgeColor.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? badgeColor : const Color(0xFF64748B), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? badgeColor : const Color(0xFFCBD5E1),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidthOption({
    required String label,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF5F3FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? const Color(0xFF7C3AED) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
