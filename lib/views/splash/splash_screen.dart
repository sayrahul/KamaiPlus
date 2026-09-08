import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../auth/login_screen.dart';
import '../auth/signup_store_screen.dart';
import '../dashboard/home_dashboard_screen.dart';
import '../cash_register/cash_register_screen.dart';
import '../purchases/purchases_screen.dart';
import '../reports/gst_reports_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    _splashTimer = Timer(const Duration(milliseconds: 2200), () async {
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final authUserId = prefs.getString('auth_user_id') ?? firebaseUser?.uid;

        // Session check: User must be signed in with Firebase or have active logged-in flag with valid userId
        final bool hasActiveSession = (firebaseUser != null || isLoggedIn) && (authUserId != null && authUserId.isNotEmpty);

        bool hasStore = false;
        if (hasActiveSession) {
          try {
            await LocalDatabase.instance.switchUser(authUserId);
            hasStore = await LocalDatabase.instance.hasConfiguredStoreProfile();
            if (hasStore) {
              final profile = await LocalDatabase.instance.getStoreProfile();
              BusinessVerticals.updateActiveBusinessType(profile.businessType);
              await prefs.setBool('is_logged_in', true);
              await prefs.setBool('is_onboarded', true);
            } else {
              await prefs.setBool('is_onboarded', false);
            }
          } catch (_) {}
        }

        final testScreen = prefs.getString('test_screen');
        if (testScreen != null) {
          await prefs.remove('test_screen');
        }
        Widget target;
        if (testScreen == 'home') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 0);
        } else if (testScreen == 'product') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 1);
        } else if (testScreen == 'product_edit') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 1, autoOpenFirstEdit: true);
        } else if (testScreen == 'pos') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 2);
        } else if (testScreen == 'checkout') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 2, autoOpenCheckout: true);
        } else if (testScreen == 'checkout_customer') {
          target = HomeDashboardScreen(
            key: HomeDashboardScreen.dashboardKey,
            initialIndex: 2,
            autoOpenCheckout: true,
            autoOpenCustomerDropdown: true,
          );
        } else if (testScreen == 'checkout_split') {
          target = HomeDashboardScreen(
            key: HomeDashboardScreen.dashboardKey,
            initialIndex: 2,
            autoOpenCheckout: true,
            autoOpenSplit: true,
          );
        } else if (testScreen == 'khata') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 3);
        } else if (testScreen == 'menu') {
          target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey, initialIndex: 4);
        } else if (testScreen == 'cash_register') {
          target = const CashRegisterScreen();
        } else if (testScreen == 'purchases') {
          target = const PurchasesScreen();
        } else if (testScreen == 'gst_reports') {
          target = const GstReportsScreen();
        } else {
          if (hasActiveSession) {
            if (hasStore) {
              target = HomeDashboardScreen(key: HomeDashboardScreen.dashboardKey);
            } else {
              target = SignupStoreScreen(
                initialEmail: prefs.getString('auth_user_email') ?? firebaseUser?.email,
                initialOwnerName: prefs.getString('auth_user_name') ?? firebaseUser?.displayName,
                initialPhone: prefs.getString('merchant_phone') ?? '',
              );
            }
          } else {
            target = const LoginScreen();
          }
        }


        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (context, animation, secondaryAnimation) => target,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Center Logo & Branding
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Official App Icon with glowing neon rim
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2A),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.4),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.point_of_sale,
                              color: Color(0xFF10B981),
                              size: 54,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // App Title
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Kamai',
                          style: GoogleFonts.outfit(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Plus',
                          style: GoogleFonts.outfit(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF10B981),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Tagline
                    Text(
                      'Bharat Ka Smart Offline POS',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Version Tag & Indicator
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    'v4.18.0 • Pro Enterprise Edition',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
