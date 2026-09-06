import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';

class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();

  String _selectedCategory = 'Grocery / Kirana';
  final List<Map<String, String>> _categories = [
    {
      'title': 'Grocery / Kirana',
      'desc': 'Loose weights, FMCG, Rice, Atta & Barcodes',
      'icon': 'store',
    },
    {
      'title': 'Apparel / Clothing',
      'desc': 'Sizes S/M/L/XL, Colors & Garments',
      'icon': 'checkroom',
    },
    {
      'title': 'Electronics & Mobile',
      'desc': 'Serial numbers, Accessories & Gadgets',
      'icon': 'devices',
    },
    {
      'title': 'Cafe / Restaurant',
      'desc': 'Table orders, Food Items & KOT tokens',
      'icon': 'restaurant',
    },
  ];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      _storeNameCtrl.text = profile.storeName;
      _ownerNameCtrl.text = profile.ownerName;
      _phoneCtrl.text = profile.phone;
      _upiCtrl.text = profile.upiVpa;
      _addressCtrl.text = profile.address;
      _gstinCtrl.text = profile.gstin;
      _selectedCategory = profile.category;
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = StoreProfileModel(
      storeName: _storeNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      upiVpa: _upiCtrl.text.trim(),
      category: _selectedCategory,
      address: _addressCtrl.text.trim(),
      gstin: _gstinCtrl.text.trim(),
    );
    await LocalDatabase.instance.saveStoreProfile(profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ Store Profile updated successfully!')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Store Profile & Settings',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : Form(
              key: _formKey,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  // Top Badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 6),
                          Text(
                            'Store Onboarding • Fast & Free Setup',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Setup Your Store Profile',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Fill in your shop details to launch your digital billing counter and khata.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Form Container
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEEF2F6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('STORE / BUSINESS NAME *'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _storeNameCtrl,
                          validator: (v) => v!.trim().isEmpty ? 'Store name required' : null,
                          decoration: _inputDecoration(
                            hint: 'e.g. Sharma Kirana & General Store',
                            icon: Icons.storefront_rounded,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('OWNER / MANAGER NAME'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _ownerNameCtrl,
                          decoration: _inputDecoration(
                            hint: 'e.g. Rahul Jadhav',
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('WHATSAPP / CONTACT NUMBER *'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          validator: (v) => v!.trim().length < 10 ? '10-digit number required' : null,
                          decoration: InputDecoration(
                            prefixIcon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Text(
                                '🇮🇳 +91',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                            hintText: '98765 43210',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Printed on invoice headers & used for WhatsApp bill dispatches.', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            _buildLabel('UPI ID / VPA *'),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(4)),
                              child: Text('Required for Bill QR Codes', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFD97706))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _upiCtrl,
                          validator: (v) => v!.trim().isEmpty ? 'UPI VPA required' : null,
                          decoration: _inputDecoration(
                            hint: 'e.g. 9876543210@paytm or store@okaxis',
                            icon: Icons.qr_code_rounded,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Printed as dynamic NPCI UPI QR code on all bills & WhatsApp links.', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                        const SizedBox(height: 20),

                        _buildLabel('BUSINESS CATEGORY *'),
                        const SizedBox(height: 8),
                        ..._categories.map((cat) {
                          final isSel = _selectedCategory == cat['title'];
                          return GestureDetector(
                            onTap: () => setState(() => _selectedCategory = cat['title']!),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSel ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                                  width: isSel ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSel ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      cat['icon'] == 'store'
                                          ? Icons.store_rounded
                                          : cat['icon'] == 'checkroom'
                                              ? Icons.checkroom_rounded
                                              : cat['icon'] == 'devices'
                                                  ? Icons.devices_other_rounded
                                                  : Icons.restaurant_rounded,
                                      color: isSel ? Colors.white : const Color(0xFF64748B),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(cat['title']!, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                                        Text(cat['desc']!, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                  if (isSel) const Icon(Icons.check_circle_rounded, color: Color(0xFFF59E0B), size: 20),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),

                        _buildLabel('STORE ADDRESS & CITY'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _addressCtrl,
                          decoration: _inputDecoration(
                            hint: 'Shop #4, Main Market, Mumbai',
                            icon: Icons.location_on_outlined,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildLabel('GSTIN (OPTIONAL)'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _gstinCtrl,
                          decoration: _inputDecoration(
                            hint: '27AAAAA0000A1Z5',
                            icon: Icons.business_outlined,
                          ),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Text(
                              'Save Store Profile',
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    );
  }
}
