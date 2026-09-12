import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_sync_service.dart';
import '../dashboard/home_dashboard_screen.dart';
import 'signup_store_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Shown once, right after this screen mounts, when the caller is routing
  /// here because of a forced sign-out (e.g. an admin disabled the account)
  /// rather than a normal user-initiated logout.
  final String? disabledMessage;
  const LoginScreen({super.key, this.disabledMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final msg = widget.disabledMessage;
    if (msg != null && msg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final userCredential = await AuthService.instance.signInWithGoogle();
      if (userCredential == null || userCredential.user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final user = userCredential.user!;
      final uid = user.uid;

      // 1. Switch to user-scoped isolated SQLite database
      await LocalDatabase.instance.switchUser(uid);

      // 2. Check if THIS specific user already has a configured store profile setup in SQLite
      bool hasStore = await LocalDatabase.instance.hasConfiguredStoreProfile();

      // 3. If not found locally, check Firestore Cloud Database (e.g. existing merchant on fresh install)
      if (!hasStore) {
        try {
          final bizDoc = await FirebaseFirestore.instance.collection('businesses').doc('biz_$uid').get();
          if (bizDoc.exists && bizDoc.data() != null) {
            final data = bizDoc.data()!;
            final sName = data['store_name']?.toString() ?? data['business_name']?.toString() ?? '';
            final bType = data['business_type']?.toString() ?? 'grocery';
            if (sName.trim().isNotEmpty && sName.trim() != 'KamaiPlus Store') {
              final isPro = data['is_pro'] == true || data['subscription_tier'] == 'pro';
              final proPlan = data['pro_plan']?.toString() ?? (isPro ? 'pro' : '');
              final proExpiry = data['pro_expiry'] != null
                  ? (data['pro_expiry'] is Timestamp
                      ? (data['pro_expiry'] as Timestamp).toDate().toIso8601String()
                      : data['pro_expiry'].toString())
                  : (data['subscription_expires_at'] != null
                      ? (data['subscription_expires_at'] is Timestamp
                          ? (data['subscription_expires_at'] as Timestamp).toDate().toIso8601String()
                          : data['subscription_expires_at'].toString())
                      : null);

              final restoredProfile = StoreProfileModel(
                storeName: sName,
                tagline: data['tagline']?.toString() ?? '',
                ownerName: data['owner_name']?.toString() ?? user.displayName ?? '',
                phone: data['phone']?.toString() ?? user.phoneNumber ?? '',
                email: data['email']?.toString() ?? user.email ?? '',
                upiVpa: data['upi_vpa']?.toString() ?? '',
                category: data['category']?.toString() ?? 'Grocery / Kirana',
                businessType: bType,
                address: data['address']?.toString() ?? '',
                pincode: data['pincode']?.toString() ?? '',
                gstin: data['gstin']?.toString() ?? '',
                fssai: data['fssai']?.toString() ?? '',
                logoUrl: data['logo_url']?.toString() ?? '',
                isPro: isPro,
                proPlan: proPlan,
                proExpiry: proExpiry ?? '',
                razorpayPaymentId: data['razorpay_payment_id']?.toString() ?? '',
              );
              await LocalDatabase.instance.saveStoreProfile(restoredProfile);
              hasStore = true;
              FirestoreSyncService.instance.initialize(businessId: 'biz_$uid');
              await FirestoreSyncService.instance.initialCloudRestore();
            }
          }
        } catch (e) {
          debugPrint('Cloud profile check notice: $e');
        }
      }

      final profile = await LocalDatabase.instance.getStoreProfile();

      // 3b. Refuse re-entry to an admin-disabled account right at login,
      // rather than letting them briefly reach the dashboard and only get
      // kicked out once FirestoreSyncService's live listener catches up.
      if (hasStore) {
        try {
          final bizDoc = await FirebaseFirestore.instance.collection('businesses').doc('biz_$uid').get();
          if (bizDoc.exists && bizDoc.data()?['account_disabled'] == true) {
            await AuthService.instance.signOut();
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your account access has been disabled. Contact support for help.'),
                backgroundColor: Color(0xFFDC2626),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 6),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('Account-disabled check notice: $e');
        }
      }

      // 4. Persist session flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user_id', uid);
      await prefs.setString('auth_user_email', user.email ?? '');
      await prefs.setString('auth_user_name', user.displayName ?? '');
      if (user.photoURL != null) {
        await prefs.setString('auth_user_photo', user.photoURL!);
      }

      if (hasStore) {
        await prefs.setBool('is_logged_in', true);
        await prefs.setBool('is_onboarded', true);
        await prefs.setString('business_id', 'biz_$uid');
        await prefs.setString('business_name', profile.storeName);
        await prefs.setString('business_type', profile.businessType);
        await prefs.setBool('is_pro', profile.isProEffective);
        if (profile.upiVpa.isNotEmpty) {
          await prefs.setString('store_upi_id', profile.upiVpa);
        }
        BusinessVerticals.updateActiveBusinessType(profile.businessType);
        FirestoreSyncService.instance.initialize(businessId: 'biz_$uid');
      } else {
        // User is NEW / NOT REGISTERED -> do not set is_logged_in until store registration is complete
        await prefs.setBool('is_logged_in', false);
        await prefs.setBool('is_onboarded', false);
        await prefs.remove('business_name');
        await prefs.remove('business_type');
        BusinessVerticals.updateActiveBusinessType('grocery');
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      final displayName = user.displayName ?? user.email ?? 'User';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Welcome, $displayName!'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (hasStore) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SignupStoreScreen(
              initialEmail: user.email,
              initialOwnerName: user.displayName,
              initialPhone: user.phoneNumber ?? '',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Sign-In: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                const SizedBox(height: 28),

                // 2. MAIN LOGIN CARD (Dedicated Google Auth)
                _buildLoginCard(),
                const SizedBox(height: 28),

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
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              children: [
                // Title
                Text(
                  'Welcome to KamaiPlus',
                  style: GoogleFonts.outfit(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                // Subtitle
                Text(
                  'Offline-First Billing POS & Digital Khata Platform',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 28),

                // Button: Continue with Google (Crisp White Premium Button)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F172A)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Signing in with Google...',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildGoogleIcon(),
                              const SizedBox(width: 12),
                              Text(
                                'Continue with Google',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Subtle Trust Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 5),
                    Text(
                      'Fast & secure 1-tap Google Authentication',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: GoogleFonts.outfit(
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
