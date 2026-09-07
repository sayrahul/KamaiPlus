import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/app_validators.dart';
import '../../models/models.dart';
import '../common/pro_upgrade_modal.dart';
import '../common/upi_standee_modal.dart';
import '../common/kamai_bottom_nav.dart';
import '../growth/growth_campaigns_screen.dart';
import '../auth/login_screen.dart';

class StoreProfileScreen extends StatefulWidget {
  final int initialTab;

  const StoreProfileScreen({super.key, this.initialTab = 0});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  late int _currentTab; // 0: Store & GST Profile, 1: UPI QR & Banking, 2: Invoice & Bill Rules

  // Store Profile Controllers
  final _formKey = GlobalKey<FormState>();
  final _storeNameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _fssaiCtrl = TextEditingController();

  String _selectedCategory = 'Grocery / Kirana';
  String _selectedBusinessType = 'grocery';

  // UPI Accounts
  final _addUpiLabelCtrl = TextEditingController();
  final _addUpiVpaCtrl = TextEditingController();
  List<UpiAccountModel> _upiAccounts = [];

  // Invoice Theme Settings
  int _selectedColorIndex = 0;
  final List<Color> _palette = [
    const Color(0xFF10B981), // Emerald
    const Color(0xFF0284C7), // Blue
    const Color(0xFFD97706), // Amber
    const Color(0xFF7C3AED), // Purple
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF0F172A), // Slate Dark
  ];
  String _selectedHeading = 'TAX INVOICE';
  final List<String> _headings = ['TAX INVOICE', 'RETAIL INVOICE', 'CASH MEMO', 'ESTIMATE / BILL'];
  bool _showLogo = true;
  bool _showTagline = true;
  bool _showPhone = true;
  bool _showUpiQr = true;
  bool _showSignatory = true;
  bool _showGstBreakup = true;
  bool _showMrpSavings = true;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _loadProfile();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _taglineCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _pincodeCtrl.dispose();
    _gstinCtrl.dispose();
    _fssaiCtrl.dispose();
    _addUpiLabelCtrl.dispose();
    _addUpiVpaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      _storeNameCtrl.text = profile.storeName;
      _taglineCtrl.text = profile.tagline;
      _ownerNameCtrl.text = profile.ownerName;
      _phoneCtrl.text = profile.phone;
      _emailCtrl.text = profile.email;
      _addressCtrl.text = profile.address;
      _pincodeCtrl.text = profile.pincode;
      _gstinCtrl.text = profile.gstin;
      _fssaiCtrl.text = profile.fssai;
      _selectedBusinessType = profile.businessType.isNotEmpty ? profile.businessType : 'grocery';
      _selectedCategory = profile.category;

      try {
        final List decoded = jsonDecode(profile.upiAccountsJson);
        _upiAccounts = decoded.map((m) => UpiAccountModel.fromMap(m)).toList();
      } catch (_) {
        _upiAccounts = [];
      }

      if (_upiAccounts.isEmpty) {
        _upiAccounts = [
          UpiAccountModel(
            id: 'upi_primary',
            label: 'Shop Primary QR',
            upiVpa: profile.upiVpa.isNotEmpty ? profile.upiVpa : 'rahuljadhav44@ybl',
            isDefault: true,
          ),
        ];
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _defaultUpiVpa {
    final def = _upiAccounts.firstWhere((a) => a.isDefault, orElse: () => _upiAccounts.first);
    return def.upiVpa.isNotEmpty ? def.upiVpa : 'rahuljadhav44@ybl';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final upiJson = jsonEncode(_upiAccounts.map((a) => a.toMap()).toList());
    final primaryVpa = _defaultUpiVpa;

    final profile = StoreProfileModel(
      storeName: _storeNameCtrl.text.trim(),
      tagline: _taglineCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      upiVpa: primaryVpa,
      category: _selectedCategory,
      businessType: _selectedBusinessType,
      address: _addressCtrl.text.trim(),
      pincode: _pincodeCtrl.text.trim(),
      gstin: _gstinCtrl.text.trim(),
      fssai: _fssaiCtrl.text.trim(),
      upiAccountsJson: upiJson,
    );

    await LocalDatabase.instance.saveStoreProfile(profile);
    BusinessVerticals.updateActiveBusinessType(_selectedBusinessType);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('business_type', _selectedBusinessType);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              '✓ Store & GST Profile updated successfully!',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _addUpiAccount() {
    final label = _addUpiLabelCtrl.text.trim();
    final vpa = _addUpiVpaCtrl.text.trim();

    final vpaError = AppValidators.validateUpi(vpa);
    if (vpaError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vpaError),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _upiAccounts.add(
        UpiAccountModel(
          id: 'upi_${DateTime.now().millisecondsSinceEpoch}',
          label: label.isNotEmpty ? label : 'Counter QR',
          upiVpa: vpa,
          isDefault: _upiAccounts.isEmpty,
        ),
      );
      _addUpiLabelCtrl.clear();
      _addUpiVpaCtrl.clear();
    });

    _saveProfile();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Added $vpa to linked UPI accounts!'),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _setDefaultUpi(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _upiAccounts = _upiAccounts.map((a) {
        return UpiAccountModel(
          id: a.id,
          label: a.label,
          upiVpa: a.upiVpa,
          isDefault: a.id == id,
        );
      }).toList();
    });
    _saveProfile();
  }

  void _deleteUpiAccount(String id) {
    if (_upiAccounts.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least 1 UPI account is required for customer billing QR.')),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      final wasDefault = _upiAccounts.firstWhere((a) => a.id == id).isDefault;
      _upiAccounts.removeWhere((a) => a.id == id);
      if (wasDefault && _upiAccounts.isNotEmpty) {
        _upiAccounts[0] = UpiAccountModel(
          id: _upiAccounts[0].id,
          label: _upiAccounts[0].label,
          upiVpa: _upiAccounts[0].upiVpa,
          isDefault: true,
        );
      }
    });
    _saveProfile();
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Logout Account?',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Aapka current device session sign out ho jayega. Data offline database me surakshit rahega.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Logout', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _storeNameCtrl.text.isNotEmpty ? _storeNameCtrl.text : 'Rahul Shramas';
    final ownerName = _ownerNameCtrl.text.isNotEmpty ? _ownerNameCtrl.text : 'Divyaang Pratishthan';
    final categoryShort = _selectedCategory.split('/').first.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildTopBar(storeName, ownerName, categoryShort),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  // Segmented Sub-Tabs
                  _buildSegmentedTabs(),

                  // Active Tab Content
                  Expanded(
                    child: IndexedStack(
                      index: _currentTab,
                      children: [
                        _buildStoreProfileTab(),
                        _buildUpiBankingTab(),
                        _buildInvoiceRulesTab(),
                      ],
                    ),
                  ),

                  // Sticky Bottom Save Bar
                  if (_currentTab == 0) _buildStickySaveBar(),
                ],
              ),
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  PreferredSizeWidget _buildTopBar(String storeName, String ownerName, String categoryShort) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(62),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFEEF2F6), width: 1.2)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Back Button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),

                // Pro Badge
                GestureDetector(
                  onTap: () => ProUpgradeModal.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          'Pro',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // QR Standee Button
                _buildCircleBtn(Icons.qr_code_2_rounded, () {
                  UpiStandeeModal.show(context);
                }),
                const SizedBox(width: 6),

                // WhatsApp Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GrowthCampaignsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(
                        'assets/images/whatsapp_logo.png',
                        width: 18,
                        height: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Store Details on Right
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    storeName,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '$ownerName • $categoryShort',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1528),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          size: 20,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color ?? const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildTabItem(0, Icons.storefront_rounded, 'Store & GST Profile'),
            const SizedBox(width: 8),
            _buildTabItem(1, Icons.qr_code_2_rounded, 'UPI QR & Banking'),
            const SizedBox(width: 8),
            _buildTabItem(2, Icons.receipt_long_rounded, 'Invoice & Bill Rules'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _currentTab == index;
    return Material(
      color: isSelected ? const Color(0xFF0F172A) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentTab = index);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 0: STORE & GST PROFILE (Screenshots 2, 3, 4)
  // ==========================================
  Widget _buildStoreProfileTab() {
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        // CARD 1: Store Identity & Branding (Screenshot 2)
        _buildSectionCard(
          icon: Icons.storefront_rounded,
          iconColor: const Color(0xFF0284C7),
          title: 'Store Identity & Branding',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dashed Logo Upload Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                ),
                child: Column(
                  children: [
                    // Dashed Camera Box
                    CustomPaint(
                      painter: DashedRectPainter(
                        color: const Color(0xFF94A3B8),
                        strokeWidth: 1.5,
                        gap: 5.0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 76,
                          height: 76,
                          color: const Color(0xFFFFFBEB),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Image.asset(
                                'assets/images/app_icon.png',
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover,
                              ),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Store Brand Logo (Printable on Tax Invoices)',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Recommended size: 250x250 PNG/JPG. Automatically compressed for thermal printing.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logo uploaded! It will print on all thermal and PDF bills.')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Upload Logo',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Business / Store Name *
              _buildFieldLabel('Business / Store Name *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _storeNameCtrl,
                validator: (v) => v!.trim().isEmpty ? 'Store name required' : null,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _fieldInputDecoration(hint: 'Rahul Shramas'),
              ),
              const SizedBox(height: 16),

              // Store Tagline / Slogan
              _buildFieldLabel('Store Tagline / Slogan'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _taglineCtrl,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _fieldInputDecoration(hint: 'e.g. Always Fresh, Best Wholesale Rates'),
              ),
              const SizedBox(height: 16),

              // Store Type / Retail Vertical
              _buildFieldLabel('Store Type / Business Vertical *'),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedBusinessType,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF0F172A)),
                    borderRadius: BorderRadius.circular(12),
                    items: BusinessVerticals.all.values.map((v) {
                      return DropdownMenuItem<String>(
                        value: v.id,
                        child: Row(
                          children: [
                            Text(v.emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                v.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedBusinessType = val;
                          final vert = BusinessVerticals.resolve(val);
                          _selectedCategory = vert.name;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adapts unit dropdowns, search hints, expiry/size fields, and menu tiles automatically.',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // CARD 2: Contact & Store Location (Screenshot 3)
        _buildSectionCard(
          icon: Icons.phone_in_talk_rounded,
          iconColor: const Color(0xFF059669),
          title: 'Contact & Store Location',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Owner / Contact Person *
              _buildFieldLabel('Owner / Contact Person *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _ownerNameCtrl,
                validator: (v) => v!.trim().isEmpty ? 'Owner name required' : null,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _fieldInputDecoration(hint: 'Divyaang Pratishthan'),
              ),
              const SizedBox(height: 16),

              // Store Mobile Number *
              _buildFieldLabel('Store Mobile Number *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                validator: (v) => AppValidators.validatePhone(v),
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _fieldInputDecoration(hint: '9595997711'),
              ),
              const SizedBox(height: 16),

              // Email Address (Optional)
              _buildFieldLabel('Email Address (Optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => AppValidators.validateEmail(v),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _fieldInputDecoration(hint: 'iamdivyaang@gmail.com'),
              ),
              const SizedBox(height: 16),

              // Full Store Address (Printed on Bill Header)
              _buildFieldLabel('Full Store Address (Printed on Bill Header)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _addressCtrl,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _fieldInputDecoration(hint: 'e.g. Shop No. 12, Gandhi Market, Station Road'),
              ),
              const SizedBox(height: 16),

              // Pincode
              _buildFieldLabel('Pincode (Optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _pincodeCtrl,
                keyboardType: TextInputType.number,
                validator: (v) => AppValidators.validatePincode(v),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _fieldInputDecoration(hint: 'e.g. 400001'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // CARD 3: GST & Statutory Licenses (Screenshot 4)
        _buildSectionCard(
          icon: Icons.apartment_rounded,
          iconColor: const Color(0xFF8B5CF6),
          title: 'GST & Statutory Licenses',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // GSTIN Number
              _buildFieldLabel('GSTIN Number (Optional - For GST Tax Invoices)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _gstinCtrl,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => AppValidators.validateGstin(v),
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _fieldInputDecoration(hint: 'e.g. 27AAAAA0000A1Z5'),
              ),
              const SizedBox(height: 16),

              // FSSAI License Number
              _buildFieldLabel('FSSAI License Number (Optional - Food & Restaurant)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _fssaiCtrl,
                keyboardType: TextInputType.number,
                validator: (v) => AppValidators.validateFssai(v),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _fieldInputDecoration(hint: 'e.g. 10019022009876'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // CARD 4: Account & Session Management (Screenshot 4)
        _buildSectionCard(
          icon: Icons.person_outline_rounded,
          iconColor: const Color(0xFF0F172A),
          title: 'Account & Session Management',
          trailing: Text(
            'Current Device Session',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Logged in as ${_ownerNameCtrl.text.isNotEmpty ? _ownerNameCtrl.text : "Divyaang Pratishthan"} (${_phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : "9595997711"})',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Log out to switch accounts or securely sign in from another phone number / Google account.',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _showLogoutDialog,
                icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFFE11D48)),
                label: Text(
                  'Logout Account',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFBE123C)),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF1F2),
                  side: const BorderSide(color: Color(0xFFFECDD3), width: 1.1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Sticky Save Button
  Widget _buildStickySaveBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Save Store Profile',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: UPI QR ACCOUNTS & BANKING (Screenshot 5)
  // ==========================================
  Widget _buildUpiBankingTab() {
    final activeVpa = _defaultUpiVpa;
    final storeName = _storeNameCtrl.text.isNotEmpty ? _storeNameCtrl.text : 'KamaiPlus Store';
    final qrData = 'upi://pay?pa=$activeVpa&pn=${Uri.encodeComponent(storeName)}&cu=INR';

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        // CARD 1: UPI QR Accounts & Auto-Matching (Screenshot 5)
        _buildSectionCard(
          icon: Icons.qr_code_2_rounded,
          iconColor: const Color(0xFF059669),
          title: 'UPI QR Accounts & Auto-Matching',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              '${_upiAccounts.length} Accounts',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // + Add UPI ID / Soundbox VPA Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '+ Add UPI ID / Soundbox VPA',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addUpiLabelCtrl,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: _fieldInputDecoration(hint: 'Account Label (e.g. Counter QR)'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addUpiVpaCtrl,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: _fieldInputDecoration(hint: 'UPI VPA (e.g. store@okaxis)'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _addUpiAccount,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          'Add Account',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Linked Accounts List
              ..._upiAccounts.map((account) {
                final isDef = account.isDefault;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDef ? const Color(0xFFECFDF5) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDef ? const Color(0xFF6EE7B7) : const Color(0xFFE2E8F0),
                      width: isDef ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _setDefaultUpi(account.id),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    account.label,
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (isDef) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD1FAE5),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFA7F3D0)),
                                      ),
                                      child: Text(
                                        'DEFAULT POS QR',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF065F46),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                account.upiVpa,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Delete button
                      IconButton(
                        onPressed: () => _deleteUpiAccount(account.id),
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // CARD 2: Live Dynamic QR Preview (Screenshot 5)
        _buildSectionCard(
          icon: Icons.qr_code_scanner_rounded,
          iconColor: const Color(0xFF0D9488),
          title: 'Live Dynamic QR Preview',
          child: Column(
            children: [
              Text(
                'Customer scans to pay directly to your linked bank account',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Centered QR Code
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 180.0,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Active UPI ID Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  activeVpa,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Accepted Brand Badges
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBrandBadge('BHIM UPI', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
                  const SizedBox(width: 6),
                  _buildBrandBadge('Google Pay', const Color(0xFF0284C7), const Color(0xFFF0F9FF)),
                  const SizedBox(width: 6),
                  _buildBrandBadge('PhonePe', const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
                  const SizedBox(width: 6),
                  _buildBrandBadge('Paytm', const Color(0xFF06B6D4), const Color(0xFFECFEFF)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrandBadge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: textColor),
      ),
    );
  }

  // ==========================================
  // TAB 2: INVOICE & BILL RULES
  // ==========================================
  Widget _buildInvoiceRulesTab() {
    final activeColor = _palette[_selectedColorIndex];

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        // Color Theme Card
        _buildSectionCard(
          icon: Icons.palette_rounded,
          iconColor: activeColor,
          title: 'Invoice Brand Color',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_palette.length, (idx) {
              final color = _palette[idx];
              final isSel = _selectedColorIndex == idx;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedColorIndex = idx);
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSel ? const Color(0xFF0F172A) : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSel ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),

        // Bill Heading Card
        _buildSectionCard(
          icon: Icons.title_rounded,
          iconColor: const Color(0xFF0284C7),
          title: 'Invoice Title Header',
          child: Column(
            children: _headings.map((heading) {
              final isSel = _selectedHeading == heading;
              return GestureDetector(
                onTap: () => setState(() => _selectedHeading = heading),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSel ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        heading,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const Spacer(),
                      if (isSel) const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // Print Toggles Card
        _buildSectionCard(
          icon: Icons.tune_rounded,
          iconColor: const Color(0xFF8B5CF6),
          title: 'Print Elements & Toggles',
          child: Column(
            children: [
              _buildToggleRow('Show Store Brand Logo', _showLogo, (v) => setState(() => _showLogo = v)),
              _buildToggleRow('Show Store Tagline / Slogan', _showTagline, (v) => setState(() => _showTagline = v)),
              _buildToggleRow('Show Store Contact Number', _showPhone, (v) => setState(() => _showPhone = v)),
              _buildToggleRow('Show Dynamic NPCI UPI QR', _showUpiQr, (v) => setState(() => _showUpiQr = v)),
              _buildToggleRow('Show Authorized Signatory', _showSignatory, (v) => setState(() => _showSignatory = v)),
              _buildToggleRow('Show GST & Tax Breakdown', _showGstBreakup, (v) => setState(() => _showGstBreakup = v)),
              _buildToggleRow('Show Total MRP Savings', _showMrpSavings, (v) => setState(() => _showMrpSavings = v)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow(String title, bool val, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
            ),
          ),
          Switch.adaptive(
            value: val,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF059669),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SHARED UI HELPERS
  // ==========================================
  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF334155),
      ),
    );
  }

  InputDecoration _fieldInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
      ),
    );
  }
}

// Custom Painter for Dashed Rectangle Border
class DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DashedRectPainter({
    this.color = const Color(0xFFCBD5E1),
    this.strokeWidth = 1.5,
    this.gap = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(16),
      ));

    final Path dashedPath = Path();
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double length = draw ? 6.0 : gap;
        if (draw) {
          dashedPath.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
