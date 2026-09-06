import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../common/pro_upgrade_modal.dart';
import '../cash_register/cash_register_screen.dart';
import '../transactions/transactions_screen.dart';
import '../inventory/inventory_screen.dart';
import '../purchases/purchases_screen.dart';
import '../customers/customers_screen.dart';
import '../reports/gst_reports_screen.dart';
import '../settings/invoice_themes_screen.dart';
import '../settings/backup_restore_screen.dart';
import '../settings/store_profile_screen.dart';
import '../tools/barcode_studio_screen.dart';
import '../growth/growth_campaigns_screen.dart';
import '../auth/login_screen.dart';

class MenuScreen extends StatefulWidget {
  final bool isModal;
  final int? currentTabIndex;
  final Function(int)? onNavigateTab;

  const MenuScreen({
    super.key,
    this.isModal = false,
    this.currentTabIndex,
    this.onNavigateTab,
  });

  static Future<void> show(
    BuildContext context, {
    int? currentTabIndex,
    Function(int)? onNavigateTab,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) => MenuScreen(
        isModal: true,
        currentTabIndex: currentTabIndex,
        onNavigateTab: onNavigateTab,
      ),
    );
  }

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  void _closeNavigation() {
    HapticFeedback.lightImpact();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else if (widget.onNavigateTab != null) {
      widget.onNavigateTab!(2); // Return to default POS Billing
    }
  }

  void _handleTabTap(int index) {
    HapticFeedback.selectionClick();
    if (widget.isModal && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    widget.onNavigateTab?.call(index);
  }

  void _handleScreenPush(Widget screen) {
    HapticFeedback.selectionClick();
    if (widget.isModal && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _handleProUpgrade() {
    HapticFeedback.selectionClick();
    if (widget.isModal && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    ProUpgradeModal.show(context);
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
          'Aapka current session sign out ho jayega. Offline billing database device par surakshit rahega.',
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
              if (widget.isModal && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
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

  void _openAssistant() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.support_agent_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'KamaiPlus AI Assistant active: WhatsApp support ready!',
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = Container(
      height: widget.isModal ? MediaQuery.of(context).size.height * 0.88 : null,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: widget.isModal
            ? const BorderRadius.vertical(top: Radius.circular(22))
            : null,
      ),
      child: ClipRRect(
        borderRadius: widget.isModal
            ? const BorderRadius.vertical(top: Radius.circular(22))
            : BorderRadius.zero,
        child: Column(
          children: [
            // Dark Header Banner matching Screenshot
            _buildDarkHeader(),

            // Scrollable 4 Categories Grid
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                children: [
                  // 1. DAILY BILLING & COUNTER
                  _buildSectionTitle('DAILY BILLING & COUNTER'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Home',
                          subtitle: 'Overview & KPIs',
                          icon: Icons.home_rounded,
                          isDark: (widget.currentTabIndex ?? 0) == 0,
                          onTap: () => _handleTabTap(0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Billing (POS)',
                          subtitle: 'Fast Checkout',
                          icon: Icons.point_of_sale_rounded,
                          iconColor: const Color(0xFF10B981),
                          iconBg: const Color(0xFFECFDF5),
                          isDark: widget.currentTabIndex == 2,
                          onTap: () => _handleTabTap(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Transactions',
                          subtitle: 'History & Returns',
                          icon: Icons.verified_user_rounded,
                          iconColor: const Color(0xFF0D9488),
                          iconBg: const Color(0xFFCCFBF1),
                          onTap: () => _handleScreenPush(const TransactionsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Cash Register',
                          subtitle: 'Shift Closing & Z-Report',
                          icon: Icons.calculate_rounded,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFEF3C7),
                          onTap: () => _handleScreenPush(const CashRegisterScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. STOCK & INVENTORY
                  _buildSectionTitle('STOCK & INVENTORY'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Products & FMCG',
                          subtitle: 'Daily Essentials & Barcodes',
                          icon: Icons.inventory_2_rounded,
                          iconColor: const Color(0xFF3B82F6),
                          iconBg: const Color(0xFFEFF6FF),
                          isDark: widget.currentTabIndex == 1,
                          onTap: () => _handleTabTap(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Inventory & Alerts',
                          subtitle: 'Stock Alerts & Low Stock',
                          icon: Icons.radar_rounded,
                          iconColor: const Color(0xFF06B6D4),
                          iconBg: const Color(0xFFECFEFF),
                          onTap: () => _handleScreenPush(const InventoryScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Wholesale Inward',
                          subtitle: 'Mandi & Supplier Bills',
                          icon: Icons.shopping_bag_rounded,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFFFBEB),
                          onTap: () => _handleScreenPush(const PurchasesScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Barcode Studio',
                          subtitle: 'Price Stickers & Tags',
                          icon: Icons.document_scanner_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          iconBg: const Color(0xFFF5F3FF),
                          onTap: () => _handleScreenPush(const BarcodeStudioScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3. CUSTOMER & CREDIT LEDGER
                  _buildSectionTitle('CUSTOMER & CREDIT LEDGER'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Khata Ledger',
                          subtitle: 'Customer Credit & Udhar',
                          icon: Icons.menu_book_rounded,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFEF3C7),
                          isDark: widget.currentTabIndex == 3,
                          onTap: () => _handleTabTap(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Customers',
                          subtitle: 'Profiles & Loyalty',
                          icon: Icons.people_alt_rounded,
                          iconColor: const Color(0xFF0284C7),
                          iconBg: const Color(0xFFE0F2FE),
                          onTap: () => _handleScreenPush(const CustomersScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'WhatsApp Growth',
                          subtitle: 'Festival Greetings',
                          icon: Icons.trending_up_rounded,
                          iconColor: const Color(0xFF10B981),
                          iconBg: const Color(0xFFECFDF5),
                          onTap: () => _handleScreenPush(const GrowthCampaignsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Upgrade & Plans',
                          subtitle: 'Kamai+ Pro',
                          icon: Icons.auto_awesome_rounded,
                          iconColor: const Color(0xFFA855F7),
                          iconBg: const Color(0xFFFAF5FF),
                          onTap: _handleProUpgrade,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. TAX, BACKUP & SETTINGS
                  _buildSectionTitle('TAX, BACKUP & SETTINGS'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'GSTR-1 Reports',
                          subtitle: 'HSN Tax Filing',
                          icon: Icons.receipt_long_rounded,
                          iconColor: const Color(0xFF6366F1),
                          iconBg: const Color(0xFFEEF2FF),
                          onTap: () => _handleScreenPush(const GstReportsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Invoice Themes',
                          subtitle: 'Bill Templates',
                          icon: Icons.palette_rounded,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFFFBEB),
                          onTap: () => _handleScreenPush(const InvoiceThemesScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Cloud Backup',
                          subtitle: 'Google Drive Sync',
                          icon: Icons.cloud_done_rounded,
                          iconColor: const Color(0xFF0284C7),
                          iconBg: const Color(0xFFE0F2FE),
                          onTap: () => _handleScreenPush(const BackupRestoreScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Settings',
                          subtitle: 'Shop Profile & UPI',
                          icon: Icons.settings_suggest_rounded,
                          iconColor: const Color(0xFF475569),
                          iconBg: const Color(0xFFF1F5F9),
                          onTap: () => _handleScreenPush(const StoreProfileScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom Footer matching Screenshot 1
            _buildBottomFooter(),
          ],
        ),
      ),
    );

    if (widget.isModal) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        top: false,
        child: bodyContent,
      ),
    );

  }

  Widget _buildDarkHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: widget.isModal
            ? const BorderRadius.vertical(top: Radius.circular(22))
            : const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        top: !widget.isModal,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, widget.isModal ? 16 : 12, 16, 16),
          child: Row(
            children: [
              // Official KamaiPlus Logo Image
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Header Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'KamaiPlus App Navigation',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'All Store Management Tools',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              // Close Button [X]
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _closeNavigation,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildNavCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    Color? iconBg,
    bool isDark = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              width: 1.1,
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.12) : (iconBg ?? const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isDark ? Colors.white : (iconColor ?? const Color(0xFF0F172A)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.1)),
      ),
      child: Row(
        children: [
          // Assistant Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openAssistant,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Assistant',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF065F46),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Version Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              'v4.18.0',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          const Spacer(),

          // Logout Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showLogoutDialog,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout_rounded, color: Color(0xFFE11D48), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Logout',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFBE123C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
