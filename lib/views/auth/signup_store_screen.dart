import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../dashboard/home_dashboard_screen.dart';
import '../purchases/purchases_screen.dart';

class SignupStoreScreen extends StatefulWidget {
  final String? initialPhone;

  const SignupStoreScreen({super.key, this.initialPhone});

  @override
  State<SignupStoreScreen> createState() => _SignupStoreScreenState();
}

class _SignupStoreScreenState extends State<SignupStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameCtrl = TextEditingController(text: 'Sharma Kirana & General Store');
  final _ownerNameCtrl = TextEditingController(text: 'Rahul Jadhav');
  late final TextEditingController _phoneCtrl;
  final _upiCtrl = TextEditingController(text: 'sharmakirana@paytm');

  String _selectedCategory = 'Grocery / Kirana';
  bool _preloadCatalog = true;
  bool _scanSupplierBill = false;
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _categories = [
    {
      'title': 'Grocery / Kirana',
      'desc': 'Loose weights, FMCG, Rice, Atta & Barcodes',
      'icon': Icons.storefront_rounded,
    },
    {
      'title': 'Apparel / Clothing',
      'desc': 'Sizes S/M/L/XL, Colors & Garments',
      'icon': Icons.checkroom_rounded,
    },
    {
      'title': 'Electronics & Mobile',
      'desc': 'Serial numbers, Accessories & Gadgets',
      'icon': Icons.devices_other_rounded,
    },
    {
      'title': 'Cafe / Restaurant',
      'desc': 'Table orders, Food items & KOT tokens',
      'icon': Icons.restaurant_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.initialPhone ?? '98765 43210');
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.heavyImpact();
    setState(() => _isSubmitting = true);

    try {
      final storeName = _storeNameCtrl.text.trim();
      final ownerName = _ownerNameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim().replaceAll(' ', '');
      final upiVpa = _upiCtrl.text.trim();

      // Setup initial UPI accounts JSON
      final upiAccounts = [
        {
          'id': 'upi_primary',
          'label': 'Shop Primary QR',
          'upi_vpa': upiVpa.isNotEmpty ? upiVpa : 'rahuljadhav44@ybl',
          'is_default': 1,
        }
      ];

      final profile = StoreProfileModel(
        storeName: storeName.isNotEmpty ? storeName : 'Sharma Kirana Store',
        tagline: 'Always Fresh, Best Wholesale Rates',
        ownerName: ownerName.isNotEmpty ? ownerName : 'Rahul Jadhav',
        phone: phone.isNotEmpty ? phone : '9876543210',
        email: '',
        upiVpa: upiVpa.isNotEmpty ? upiVpa : 'sharmakirana@paytm',
        category: _selectedCategory,
        address: 'Shop #4, Main Market Road',
        pincode: '400001',
        gstin: '',
        fssai: '',
        upiAccountsJson: jsonEncode(upiAccounts),
      );

      // Save to SQLite
      await LocalDatabase.instance.saveStoreProfile(profile);

      // Save login & onboarding status
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('is_onboarded', true);
      await prefs.setString('business_name', storeName);
      await prefs.setString('merchant_phone', phone);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.stars_rounded, color: Color(0xFFFBBF24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🎉 Swagat hai $storeName! Aapka store setup poora hua.',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      if (_scanSupplierBill) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PurchasesScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey)),
        );

      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing setup: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Top Onboarding Pill Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161A29),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.6), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 6),
                      Text(
                        'Store Onboarding • Fast & Free Setup',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFBBF24),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Official Logo
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title & Subtitle
              Center(
                child: Text(
                  'Setup Your Store Profile',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Fill in your shop details to launch your digital billing counter and khata.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Main Form Container Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field 1: Store / Business Name *
                    _buildFieldLabel('STORE / BUSINESS NAME *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _storeNameCtrl,
                      validator: (v) => v!.trim().isEmpty ? 'Please enter store name' : null,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                      decoration: _buildInputDecoration(
                        hint: 'e.g. Sharma Kirana & General Store',
                        icon: Icons.storefront_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        isGoldFocus: true,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Field 2: Owner / Manager Name
                    _buildFieldLabel('OWNER / MANAGER NAME'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _ownerNameCtrl,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
                      decoration: _buildInputDecoration(
                        hint: 'Rahul Jadhav',
                        icon: Icons.person_outline_rounded,
                        iconColor: const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Field 3: WhatsApp / Contact Number *
                    _buildFieldLabel('WHATSAPP / CONTACT NUMBER *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      validator: (v) => v!.replaceAll(' ', '').length < 10 ? '10-digit number required' : null,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF070C18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(
                            border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'IN',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '+91',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFF59E0B)),
                              ),
                            ],
                          ),
                        ),
                        hintText: '98765 43210',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF1E293B)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF1E293B)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Printed on invoice headers & used for WhatsApp bill dispatches.',
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 18),

                    // Field 4: UPI ID / VPA *
                    Row(
                      children: [
                        _buildFieldLabel('UPI ID / VPA *'),
                        const Spacer(),
                        Text(
                          'Required for Bill QR Codes',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiCtrl,
                      validator: (v) => v!.trim().isEmpty ? 'UPI VPA required' : null,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
                      decoration: _buildInputDecoration(
                        hint: 'e.g. 9876543210@paytm or store@okaxis',
                        icon: Icons.qr_code_2_rounded,
                        iconColor: const Color(0xFF06B6D4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Printed as dynamic NPCI UPI QR code on all bills & WhatsApp payment links.',
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 22),

                    // Field 5: Business Category *
                    _buildFieldLabel('BUSINESS CATEGORY *'),
                    const SizedBox(height: 10),
                    ..._categories.map((cat) {
                      final isSel = _selectedCategory == cat['title'];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = cat['title'] as String);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFF1C1917).withValues(alpha: 0.9) : const Color(0xFF070C18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                              width: isSel ? 1.6 : 1,
                            ),
                            boxShadow: isSel
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  cat['icon'] as IconData,
                                  color: isSel ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat['title'] as String,
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isSel ? const Color(0xFFFBBF24) : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      cat['desc'] as String,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSel)
                                const Icon(Icons.check_circle_rounded, color: Color(0xFFF59E0B), size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),

                    // Feature Card 1: Pre-load Starter Catalog
                    GestureDetector(
                      onTap: () => setState(() => _preloadCatalog = !_preloadCatalog),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF070C18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _preloadCatalog,
                              onChanged: (v) => setState(() => _preloadCatalog = v ?? false),
                              activeColor: const Color(0xFFF59E0B),
                              checkColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pre-load starter product catalog',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Automatically seeds 8 popular items for Grocery / Kirana with standard prices.',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Feature Card 2: 1-Tap Wholesaler Bill / Parcha Setup (AI VISION)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071B19),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.6), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0F172A), size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '📦 1-Tap Wholesaler Bill / Parcha Setup',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF064E3B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981)),
                                ),
                                child: Text(
                                  '✨ AI VISION',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF6EE7B7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Take a photo of your supplier invoice, parcha, or purchase bill. Our AI will auto-extract all products, quantities, and rates!',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Checkbox(
                                value: _scanSupplierBill,
                                onChanged: (v) => setState(() => _scanSupplierBill = v ?? false),
                                activeColor: const Color(0xFFF59E0B),
                                checkColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Open Camera to Scan Supplier Bill immediately after setup',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Primary Setup Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _completeSetup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.auto_awesome_rounded, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Complete Setup & Launch POS 🚀',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: const Color(0xFF94A3B8),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required IconData icon,
    required Color iconColor,
    bool isGoldFocus = false,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF070C18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      prefixIcon: Icon(icon, color: iconColor, size: 20),
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isGoldFocus ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
          width: 1.5,
        ),
      ),
    );
  }
}
