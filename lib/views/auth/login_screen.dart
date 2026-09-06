import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/app_validators.dart';
import '../dashboard/home_dashboard_screen.dart';
import 'signup_store_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isOtpExpanded = false;
  bool _otpSent = false;
  bool _isLoading = false;

  final _phoneController = TextEditingController(text: '9876543210');
  final _otpController = TextEditingController(text: '1234');

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _proceedLogin({String? phone, bool isFresh = false}) async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final isOnboarded = prefs.getBool('is_onboarded') ?? false;

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    setState(() => _isLoading = false);

    if (!isOnboarded || isFresh) {
      if (!mounted) return;
      // First-time user -> Open Signup / Store Profile Setup Screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SignupStoreScreen(initialPhone: phone ?? _phoneController.text.trim()),
        ),
      );
    } else {
      // Existing user -> Mark logged in and launch POS Dashboard
      await prefs.setBool('is_logged_in', true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey)),
      );

    }
  }

  void _sendOtp() {
    final phone = _phoneController.text.trim();
    final error = AppValidators.validatePhone(phone);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final cleanPhone = AppValidators.cleanPhone(phone);
    HapticFeedback.lightImpact();
    setState(() => _otpSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ WhatsApp OTP sent to +91 $cleanPhone (Demo OTP: 1234)'),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _verifyOtp() {
    final otp = _otpController.text.trim();
    final error = AppValidators.validateOtp(otp, length: 4);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _proceedLogin(phone: AppValidators.cleanPhone(_phoneController.text.trim()));
  }

  void _showResetConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: Row(
          children: [
            const Icon(Icons.cleaning_services_rounded, color: Color(0xFFF59E0B), size: 22),
            const SizedBox(width: 10),
            Text(
              'Start Fresh Signup?',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Is option se aapka device onboarding reset ho jayega aur aap ek naya store profile create kar sakenge.',
          style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('is_onboarded', false);
              _proceedLogin(isFresh: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Start Fresh', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. BRANDING HEADER (Logo + Title + Subtitle)
                _buildBrandingHeader(),
                const SizedBox(height: 24),

                // 2. MAIN LOGIN CARD (Matching Screenshot 1)
                _buildLoginCard(),
                const SizedBox(height: 24),

                // 3. FOOTER LINKS (Terms • Privacy • Support)
                _buildFooterLinks(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandingHeader() {
    return Column(
      children: [
        // Official KamaiPlus Logo Image
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                blurRadius: 18,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Brand Name + Verified POS Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Kamai+',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFF59E0B),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF161A29),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.7), width: 1.1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_rounded, size: 13, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 4),
                  Text(
                    'Verified POS',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Subtitle in Hindi
        Text(
          'आपकी दुकान का डिजिटल साथी',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF93C5FD),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1628),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Accent Line (Emerald/Cyan gradient)
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                // Title
                Text(
                  'Welcome to KamaiPlus',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                // Subtitle
                Text(
                  'Offline-First Billing POS & Digital Khata Platform',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 20),

                // Button 1: Continue with WhatsApp (Solid Emerald Green)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _proceedLogin(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF022C22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/whatsapp_logo.png', width: 22, height: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Continue with WhatsApp',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF022C22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Accordion: "or get WhatsApp OTP v"
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isOtpExpanded = !_isOtpExpanded);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'or get WhatsApp OTP',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isOtpExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: const Color(0xFF94A3B8),
                        ),
                      ],
                    ),
                  ),
                ),

                // Expandable OTP Drawer
                if (_isOtpExpanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070B19),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            prefixIcon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              child: Text(
                                '🇮🇳 +91',
                                style: GoogleFonts.inter(color: const Color(0xFFF59E0B), fontWeight: FontWeight.w700),
                              ),
                            ),
                            hintText: 'Enter 10-digit mobile number',
                            hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF0E1628),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_otpSent)
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton(
                              onPressed: _sendOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: Text('Send OTP', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          )
                        else ...[
                          TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 4),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: '• • • •',
                              hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), letterSpacing: 4),
                              filled: true,
                              fillColor: const Color(0xFF0E1628),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton(
                              onPressed: _verifyOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: Text('Verify & Continue', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Divider with OR
                Row(
                  children: [
                    Expanded(child: Divider(color: const Color(0xFF1E293B), thickness: 1.1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: const Color(0xFF1E293B), thickness: 1.1)),
                  ],
                ),
                const SizedBox(height: 16),

                // Button 2: Continue with Google (Crisp White Button)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _proceedLogin(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildGoogleIcon(),
                        const SizedBox(width: 10),
                        Text(
                          'Continue with Google',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Reset Device Data Link (Start Fresh Signup)
                GestureDetector(
                  onTap: _showResetConfirmDialog,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cleaning_services_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      Text(
                        'Reset Device Data (Start Fresh Signup)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Feature Badges: 100% Offline POS & Cloud Sync & Backup
                Row(
                  children: [
                    Expanded(
                      child: _buildFeaturePill(
                        icon: Icons.bolt_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        label: '100% Offline POS',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFeaturePill(
                        icon: Icons.verified_user_rounded,
                        iconColor: const Color(0xFF10B981),
                        label: 'Cloud Sync & Backup',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      child: Text(
        'G',
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF4285F4),
        ),
      ),
    );
  }

  Widget _buildFeaturePill({
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF070B19),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildFooterText('Terms of Service'),
        _buildFooterDot(),
        _buildFooterText('Privacy Policy'),
        _buildFooterDot(),
        _buildFooterText('Support'),
      ],
    );
  }

  Widget _buildFooterText(String text) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$text link opened'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildFooterDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: Color(0xFF475569),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
