import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/thermal_printer_service.dart';
import '../../models/models.dart';

class BluetoothPrinterDialog extends StatefulWidget {
  const BluetoothPrinterDialog({super.key});

  @override
  State<BluetoothPrinterDialog> createState() => _BluetoothPrinterDialogState();
}

class _BluetoothPrinterDialogState extends State<BluetoothPrinterDialog> {
  static const _channel = MethodChannel('com.kamaiplus.pos/bluetooth_printer');

  List<Map<dynamic, dynamic>> _devices = [];
  String? _selectedAddress;
  String? _selectedName;
  bool _is80mm = false;
  bool _isLoading = true;
  bool _isPrinting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _fetchPairedDevices();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedAddress = prefs.getString('printer_mac_address');
      _selectedName = prefs.getString('printer_device_name');
      _is80mm = prefs.getBool('printer_is_80mm') ?? false;
    });
  }

  Future<void> _fetchPairedDevices() async {
    setState(() => _isLoading = true);
    try {
      final List<dynamic>? list = await _channel.invokeListMethod('getPairedDevices');
      if (list != null) {
        setState(() {
          _devices = list.map((item) => Map<dynamic, dynamic>.from(item as Map)).toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Could not scan Bluetooth devices: $e";
      });
    }
  }

  Future<void> _saveSettings(String address, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_mac_address', address);
    await prefs.setString('printer_device_name', name);
    await prefs.setBool('printer_is_80mm', _is80mm);
    setState(() {
      _selectedAddress = address;
      _selectedName = name;
      _statusMessage = "Printer saved: $name";
    });
  }

  Future<void> _testPrint() async {
    if (_selectedAddress == null) {
      setState(() => _statusMessage = "Please select a printer first!");
      return;
    }

    setState(() {
      _isPrinting = true;
      _statusMessage = "Sending test slip to $_selectedName...";
    });

    try {
      // Create a dummy test sale
      final testSale = SaleModel(
        id: 'test_receipt',
        businessId: 'test',
        invoiceNumber: 'TEST-001',
        subtotalPaise: 15000,
        taxAmountPaise: 750,
        discountPaise: 0,
        totalAmountPaise: 15000,
        paymentMethod: 'cash',
        items: [
          {
            'product_name': 'Test Item 1',
            'quantity': 1.0,
            'gross_total_paise': 10000,
          },
          {
            'product_name': 'Test Item 2',
            'quantity': 2.0,
            'gross_total_paise': 5000,
          }
        ],
        createdAt: DateTime.now(),
        syncStatus: 'synced',
      );

      final bytes = ThermalPrinterService.generateReceiptBytes(
        sale: testSale,
        storeName: "KamaiPlus Thermal Test",
        storePhone: "9876543210",
        is80mm: _is80mm,
        kickCashDrawer: true,
      );

      await _channel.invokeMethod('printBytes', {
        'address': _selectedAddress,
        'bytes': bytes,
      });

      setState(() {
        _isPrinting = false;
        _statusMessage = "Test print successful! ✅";
      });
    } catch (e) {
      setState(() {
        _isPrinting = false;
        _statusMessage = "Print failed: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.print, color: Color(0xFFF59E0B), size: 24),
                    SizedBox(width: 10),
                    Text(
                      "Thermal Printer Setup",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Paper Size Selection
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text("58mm (2-Inch)"),
                    selected: !_is80mm,
                    selectedColor: const Color(0xFFF59E0B),
                    onSelected: (val) {
                      if (val) setState(() => _is80mm = false);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: const Text("80mm (3-Inch)"),
                    selected: _is80mm,
                    selectedColor: const Color(0xFFF59E0B),
                    onSelected: (val) {
                      if (val) setState(() => _is80mm = true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text(
              "Paired Bluetooth Printers:",
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Devices list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                  : _devices.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "No paired Bluetooth printers found. Please pair your thermal printer in Android Bluetooth Settings first.",
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _devices.length,
                          itemBuilder: (ctx, idx) {
                            final dev = _devices[idx];
                            final name = dev['name'] ?? 'Unknown';
                            final address = dev['address'] ?? '';
                            final isSelected = _selectedAddress == address;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFF59E0B) : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.bluetooth,
                                  color: isSelected ? const Color(0xFFF59E0B) : Colors.white60,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(address, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle, color: Color(0xFFF59E0B), size: 20)
                                    : null,
                                onTap: () => _saveSettings(address, name),
                              ),
                            );
                          },
                        ),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusMessage!.contains('successful') ? const Color(0xFF10B981) : Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _fetchPairedDevices,
                    icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                    label: const Text("Refresh", style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _testPrint,
                    icon: _isPrinting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                        : const Icon(Icons.receipt_long, size: 18),
                    label: const Text("Test Print", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

