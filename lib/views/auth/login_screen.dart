import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pos/barcode_scanner_view.dart';
import '../../services/firestore_sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handlePhonePinLogin() async {
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();

    if (phone.length < 10) {
      setState(() => _errorMessage = "Please enter a valid 10-digit mobile number");
      return;
    }
    if (pin.length < 4) {
      setState(() => _errorMessage = "Please enter your 4-digit store PIN");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('businesses')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final bizDoc = snap.docs.first;
        final bizData = bizDoc.data();
        final bizId = bizDoc.id;
        final bizName = bizData['name'] ?? 'My Retail Store';

        await _saveAndInitialize(bizId, bizName, phone);
      } else {
        final fallbackBizId = 'biz_$phone';
        await _saveAndInitialize(fallbackBizId, 'Kamai Store ($phone)', phone);
      }
    } catch (e) {
      final offlineBizId = 'biz_$phone';
      await _saveAndInitialize(offlineBizId, 'Kamai Store ($phone)', phone);
    }
  }

  Future<void> _scanPairingQR() async {
    final qrData = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerView()),
    );

    if (qrData != null && qrData.isNotEmpty) {
      setState(() => _isLoading = true);

      String bizId = qrData;
      String storeName = "Linked Store";

      if (qrData.contains('biz=')) {
        final uri = Uri.tryParse(qrData);
        if (uri != null) {
          bizId = uri.queryParameters['biz'] ?? qrData;
          storeName = uri.queryParameters['name'] ?? storeName;
        }
      }

      await _saveAndInitialize(bizId, storeName, "");
    }
  }

  Future<void> _saveAndInitialize(String bizId, String storeName, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('business_id', bizId);
    await prefs.setString('business_name', storeName);
    await prefs.setString('merchant_phone', phone);
    await prefs.setBool('is_logged_in', true);

    await FirestoreSyncService.instance.initialize(businessId: bizId);

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Connected to $storeName!"),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.storefront, color: Color(0xFF0F172A), size: 40),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Connect Your Store",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Sync live stock and bills with your Desktop Web Counter in real-time.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              OutlinedButton.icon(
                onPressed: _isLoading ? null : _scanPairingQR,
                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFF59E0B)),
                label: const Text(
                  "1-Tap Pair via Desktop Web QR",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                ),
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      "OR LOGIN WITH PHONE",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                ],
              ),
              const SizedBox(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.phone_iphone, color: Color(0xFFF59E0B)),
                    hintText: "10-digit Mobile Number",
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.lock_outline, color: Color(0xFFF59E0B)),
                    hintText: "Store Cashier PIN",
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    counterText: "",
                  ),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _handlePhonePinLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                      )
                    : const Text(
                        "Sign In & Sync Store",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

