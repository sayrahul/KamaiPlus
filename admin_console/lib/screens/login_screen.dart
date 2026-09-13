import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';
import 'admin_shell.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final err = await AdminAuthService.instance.signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _error = err;
    });
    if (err == null) widget.onSignedIn();
  }

  Future<void> _handleEmailSignIn() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Enter both email and password');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final err = await AdminAuthService.instance.signInWithEmail(
      _emailCtrl.text,
      _passwordCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _error = err;
    });
    if (err == null) widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AdminColors.bgDark,
      body: Stack(
        children: [
          // Background ambient gradient orbs
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 480,
              height: 480,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AdminColors.accent.withValues(alpha: 0.18),
                    AdminColors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -120,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AdminColors.blue.withValues(alpha: 0.12),
                    AdminColors.blue.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 960 : 440),
                  child: isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Brand & Feature Highlights column
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 48),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AdminColors.accentSoft,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AdminColors.accent.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: AdminColors.accent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'MISSION CONTROL v4.21',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AdminColors.accent,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'KamaiPlus Enterprise Operations',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: AdminColors.textWhite,
                                        letterSpacing: -1,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Unified counter operations, merchant radar, vertical retail analytics, and remote release enforcement.',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        color: AdminColors.textMuted,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    _buildFeaturePill(Icons.radar_rounded, 'Inactive Merchant Radar', 'Detect & re-engage dropped off stores via WhatsApp'),
                                    const SizedBox(height: 16),
                                    _buildFeaturePill(Icons.pie_chart_rounded, 'Vertical Retail Analytics', 'Kirana vs Kapda vs Pharmacy real-time market share'),
                                    const SizedBox(height: 16),
                                    _buildFeaturePill(Icons.notifications_active_rounded, 'Direct System Push Alerts', 'FCM status-bar broadcast dispatcher with deep-linking'),
                                  ],
                                ),
                              ),
                            ),

                            // Right Card
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: _buildAuthCard(),
                            ),
                          ],
                        )
                      : _buildAuthCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AdminColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.borderDark),
          ),
          child: Icon(icon, color: AdminColors.accent, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.textWhite),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 12, color: AdminColors.textFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard() {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminColors.borderDark, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AdminColors.accent, AdminColors.accentGlow],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Sign In',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.textWhite,
                      ),
                    ),
                    Text(
                      'Authorized operators only',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          // Continue with Google Button
          ElevatedButton(
            onPressed: _isLoading ? null : _handleGoogleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.bgElevated,
              foregroundColor: AdminColors.textWhite,
              side: const BorderSide(color: AdminColors.borderDark),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.g_mobiledata_rounded, size: 28, color: AdminColors.accent),
                const SizedBox(width: 8),
                Text(
                  'Continue with Google Workspace',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider(color: AdminColors.borderDark)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR SIGN IN WITH EMAIL',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textFaint,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AdminColors.borderDark)),
            ],
          ),
          const SizedBox(height: 18),

          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Admin Email',
              prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18, color: AdminColors.textFaint),
              labelStyle: const TextStyle(color: AdminColors.textMuted),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            onSubmitted: (_) => _handleEmailSignIn(),
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: AdminColors.textFaint),
              labelStyle: const TextStyle(color: AdminColors.textMuted),
            ),
          ),
          const SizedBox(height: 18),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.redSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: AdminColors.redBorder),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AdminColors.redBorder, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          ElevatedButton(
            onPressed: _isLoading ? null : _handleEmailSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Access Mission Control',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
          ),

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: AdminColors.textFaint),
              const SizedBox(width: 6),
              Text(
                '256-bit Encrypted Multi-Tenant Isolation',
                style: GoogleFonts.inter(fontSize: 11, color: AdminColors.textFaint),
              ),
            ],
          ),

          if (kDebugMode) ...[
            const SizedBox(height: 16),
            const Divider(color: AdminColors.borderDark),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminShell()),
                );
              },
              icon: const Icon(Icons.flash_on_rounded, size: 16, color: AdminColors.accent),
              label: const Text(
                '⚡ Dev Preview: Enter Admin Shell',
                style: TextStyle(fontWeight: FontWeight.w700, color: AdminColors.accent, fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

