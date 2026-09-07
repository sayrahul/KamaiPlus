import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/business_vertical_config.dart';
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
import '../settings/pro_membership_screen.dart';
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProMembershipScreen()),
    );
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
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
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
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
                children: [
                  // 1. DAILY BILLING & COUNTER (Bento Hero + Grid)
                  _buildSectionTitle('DAILY BILLING & COUNTER', subtitle: 'Fast register checkout, day history & cash till'),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Home Pulse',
                          subtitle: 'Live KPIs & Soundbox',
                          icon: Icons.home_rounded,
                          iconColor: const Color(0xFF2563EB),
                          iconBg: const Color(0xFFEFF6FF),
                          borderColor: const Color(0xFFDBEAFE),
                          badgeText: 'PULSE',
                          isDark: (widget.currentTabIndex ?? 0) == 0,
                          onTap: () => _handleTabTap(0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Transactions',
                          subtitle: 'Bills & Return Slips',
                          icon: Icons.receipt_long_rounded,
                          iconColor: const Color(0xFF0D9488),
                          iconBg: const Color(0xFFCCFBF1),
                          borderColor: const Color(0xFF99F6E4),
                          badgeText: 'HISTORY',
                          onTap: () => _handleScreenPush(const TransactionsScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildNavCard(
                    title: 'Cash Register & Galla Till',
                    subtitle: 'Cash In/Out, Physical Denomination Counter & Z-Report',
                    icon: Icons.calculate_rounded,
                    iconColor: const Color(0xFFD97706),
                    iconBg: const Color(0xFFFEF3C7),
                    borderColor: const Color(0xFFFDE68A),
                    badgeText: 'Z-REPORT',
                    badgeBg: const Color(0xFFFFFBEB),
                    badgeColor: const Color(0xFFB45309),
                    onTap: () => _handleScreenPush(const CashRegisterScreen()),
                  ),
                  const SizedBox(height: 22),

                  // 2. STOCK & INVENTORY (Bento Grid)
                  _buildSectionTitle('STOCK & INVENTORY', subtitle: 'SKU catalog, wholesale restock & barcode printing'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: vert.productsMenuTitle,
                          subtitle: vert.productsMenuSubtitle,
                          icon: Icons.inventory_2_rounded,
                          iconColor: const Color(0xFF3B82F6),
                          iconBg: const Color(0xFFEFF6FF),
                          borderColor: const Color(0xFFDBEAFE),
                          badgeText: 'CATALOG',
                          isDark: widget.currentTabIndex == 1,
                          onTap: () => _handleTabTap(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: vert.purchasesMenuTitle,
                          subtitle: vert.purchasesMenuSubtitle,
                          icon: Icons.shopping_bag_rounded,
                          iconColor: const Color(0xFF059669),
                          iconBg: const Color(0xFFECFDF5),
                          borderColor: const Color(0xFFA7F3D0),
                          badgeText: 'AI OCR',
                          badgeBg: const Color(0xFFECFDF5),
                          badgeColor: const Color(0xFF059669),
                          onTap: () => _handleScreenPush(const PurchasesScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Inventory & Alerts',
                          subtitle: 'Low Stock Radar',
                          icon: Icons.radar_rounded,
                          iconColor: const Color(0xFF0891B2),
                          iconBg: const Color(0xFFECFEFF),
                          borderColor: const Color(0xFFA5F3FC),
                          badgeText: 'ALERTS',
                          onTap: () => _handleScreenPush(const InventoryScreen()),
                        ),
                      ),
                      if (vert.toggles.showBarcode) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildNavCard(
                            title: 'Barcode Studio',
                            subtitle: 'Sticker & Label Print',
                            icon: Icons.document_scanner_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: const Color(0xFFF5F3FF),
                            borderColor: const Color(0xFFDDD6FE),
                            badgeText: 'PRINT',
                            onTap: () => _handleScreenPush(const BarcodeStudioScreen()),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 3. CUSTOMER & CREDIT LEDGER (Bento Grid)
                  _buildSectionTitle('CUSTOMER & CREDIT LEDGER', subtitle: 'Udhar reminders, voice notes & marketing campaigns'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Digital Khata',
                          subtitle: 'Credit & Udhar Dues',
                          icon: Icons.menu_book_rounded,
                          iconColor: const Color(0xFFEA580C),
                          iconBg: const Color(0xFFFFF7ED),
                          borderColor: const Color(0xFFFFEDD5),
                          badgeText: 'UDHAR',
                          badgeBg: const Color(0xFFFEF2F2),
                          badgeColor: const Color(0xFFDC2626),
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
                          iconBg: const Color(0xFFF0F9FF),
                          borderColor: const Color(0xFFBAE6FD),
                          badgeText: 'CRM',
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
                          subtitle: 'Offers & Festive SMS',
                          icon: Icons.trending_up_rounded,
                          iconColor: const Color(0xFF16A34A),
                          iconBg: const Color(0xFFF0FDF4),
                          borderColor: const Color(0xFFBBF7D0),
                          badgeText: 'AUTO',
                          onTap: () => _handleScreenPush(const GrowthCampaignsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Kamai+ Pro',
                          subtitle: 'Cloud & Multi-Staff',
                          icon: Icons.auto_awesome_rounded,
                          iconColor: const Color(0xFF9333EA),
                          iconBg: const Color(0xFFFAF5FF),
                          borderColor: const Color(0xFFE9D5FF),
                          badgeText: 'PRO',
                          badgeBg: const Color(0xFFFAF5FF),
                          badgeColor: const Color(0xFF7E22CE),
                          onTap: _handleProUpgrade,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 4. TAX, BACKUP & SETTINGS (Bento Grid)
                  _buildSectionTitle('TAX, BACKUP & SETTINGS', subtitle: 'GSTR-1, bill themes, Google Drive sync & shop profile'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'GSTR-1 & CA Pack',
                          subtitle: 'HSN Sales Summary',
                          icon: Icons.receipt_long_rounded,
                          iconColor: const Color(0xFF4F46E5),
                          iconBg: const Color(0xFFEEF2FF),
                          borderColor: const Color(0xFFC7D2FE),
                          badgeText: 'CA READY',
                          badgeBg: const Color(0xFFEEF2FF),
                          badgeColor: const Color(0xFF4338CA),
                          onTap: () => _handleScreenPush(const GstReportsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Invoice Themes',
                          subtitle: 'Bill Prints & Logo',
                          icon: Icons.palette_rounded,
                          iconColor: const Color(0xFFD97706),
                          iconBg: const Color(0xFFFFFBEB),
                          borderColor: const Color(0xFFFDE68A),
                          badgeText: 'DESIGN',
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
                          iconBg: const Color(0xFFF0F9FF),
                          borderColor: const Color(0xFFBAE6FD),
                          badgeText: 'SYNC',
                          onTap: () => _handleScreenPush(const BackupRestoreScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: 'Store Settings',
                          subtitle: 'Shop Profile & UPI QR',
                          icon: Icons.settings_suggest_rounded,
                          iconColor: const Color(0xFF475569),
                          iconBg: const Color(0xFFF1F5F9),
                          borderColor: const Color(0xFFE2E8F0),
                          badgeText: 'CONFIG',
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

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: const Color(0xFF64748B),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildNavCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    Color? iconBg,
    Color? borderColor,
    String? badgeText,
    Color? badgeBg,
    Color? badgeColor,
    bool isDark = false,
    required VoidCallback onTap,
  }) {
    final effectiveBorder = isDark ? const Color(0xFF1E293B) : (borderColor ?? const Color(0xFFE2E8F0));
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
              color: effectiveBorder,
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.12) : (iconBg ?? const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: isDark ? Colors.white : (iconColor ?? const Color(0xFF0F172A)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : (badgeBg ?? (iconBg ?? const Color(0xFFF1F5F9))),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : (badgeColor ?? (iconColor ?? const Color(0xFF475569))),
                              ),
                            ),
                          ),
                        ],
                      ],
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
