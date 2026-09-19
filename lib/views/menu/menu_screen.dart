import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/business_vertical_config.dart';
import '../common/in_app_notification.dart';
import '../cash_register/cash_register_screen.dart';
import '../transactions/transactions_screen.dart';
import '../inventory/inventory_screen.dart';
import '../purchases/purchases_screen.dart';
import '../customers/customers_screen.dart';
import '../reports/gst_reports_screen.dart';
import '../reports/advanced_sales_reports_screen.dart';
import '../settings/invoice_themes_screen.dart';
import '../settings/backup_restore_screen.dart';
import '../settings/store_profile_screen.dart';
import '../settings/printer_settings_screen.dart';
import '../tools/barcode_studio_screen.dart';
import '../growth/growth_campaigns_screen.dart';
import '../growth/refer_and_earn_screen.dart';
import '../common/pro_upgrade_modal.dart';
import '../auth/login_screen.dart';
import '../../core/database/local_database.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/remote_config_service.dart';
import '../../main.dart';
import '../../core/localization/app_language_service.dart';
import '../../core/localization/app_strings.dart';
import '../common/language_selection_modal.dart';

class MenuScreen extends StatefulWidget {
  final bool isModal;
  final int? currentTabIndex;
  final String? activeScreen;
  final Function(int)? onNavigateTab;

  const MenuScreen({
    super.key,
    this.isModal = false,
    this.currentTabIndex,
    this.activeScreen,
    this.onNavigateTab,
  });

  static Future<void> show(
    BuildContext context, {
    int? currentTabIndex,
    String? activeScreen,
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
        activeScreen: activeScreen,
        onNavigateTab: onNavigateTab,
      ),
    );
  }

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _checkPro();
    FirestoreSyncService.isProNotifier.addListener(_onProNotifierChanged);
  }

  @override
  void dispose() {
    FirestoreSyncService.isProNotifier.removeListener(_onProNotifierChanged);
    super.dispose();
  }

  void _onProNotifierChanged() {
    if (mounted) {
      setState(() => _isPro = FirestoreSyncService.isProNotifier.value);
    }
  }

  Future<void> _checkPro() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _isPro = p.isProEffective || FirestoreSyncService.isProNotifier.value);
    } catch (_) {}
  }

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

  /// Support options sheet. Routing details (number, email) come from Remote
  /// Config so they can be changed for everyone without an app release.
  Future<void> _showSupportSheet() async {
    HapticFeedback.selectionClick();
    if (widget.isModal && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    final rootCtx = rootNavigatorKey.currentContext ?? context;
    if (!rootCtx.mounted) return;

    final phone = RemoteConfigService.instance.supportPhone;
    final email = RemoteConfigService.instance.supportEmail;

    // Context the support team would otherwise have to ask for, pre-filled.
    String storeLine = '';
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      final bits = <String>[
        if (p.storeName.trim().isNotEmpty) p.storeName.trim(),
        if (p.phone.trim().isNotEmpty) p.phone.trim(),
      ];
      if (bits.isNotEmpty) storeLine = '\n\nStore: ${bits.join(' • ')}';
    } catch (_) {}

    if (!rootCtx.mounted) return;
    await showModalBottomSheet(
      context: rootCtx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Help & Support',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Our team answers in Hindi and English.',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
              const SizedBox(height: 16),
              _buildSupportOption(
                ctx,
                icon: Icons.chat_rounded,
                color: const Color(0xFF059669),
                title: 'WhatsApp Support',
                subtitle: '+$phone',
                onTap: () async {
                  Navigator.pop(ctx);
                  final msg = Uri.encodeComponent('Hi KamaiPlus support, I need help with:$storeLine');
                  final uri = Uri.parse('https://wa.me/$phone?text=$msg');
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    await Clipboard.setData(ClipboardData(text: '+$phone'));
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildSupportOption(
                ctx,
                icon: Icons.mail_rounded,
                color: const Color(0xFF0284C7),
                title: 'Email Support',
                subtitle: email,
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri(
                    scheme: 'mailto',
                    path: email,
                    query: 'subject=${Uri.encodeComponent('KamaiPlus POS Support')}'
                        '&body=${Uri.encodeComponent('Describe your issue here:$storeLine')}',
                  );
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    await Clipboard.setData(ClipboardData(text: email));
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildSupportOption(
                ctx,
                icon: Icons.call_rounded,
                color: const Color(0xFF7C3AED),
                title: 'Call Us',
                subtitle: '+$phone',
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('tel:+$phone');
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    await Clipboard.setData(ClipboardData(text: '+$phone'));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupportOption(
    BuildContext ctx, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  void _handleProUpgrade() {
    HapticFeedback.selectionClick();
    ProUpgradeModal.show(context).then((_) => _checkPro());
  }

  void _showLogoutDialog() {
    HapticFeedback.mediumImpact();
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
          'Your current session will be signed out. The offline billing database remains secure on this device.',
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
              _performLogout();
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

  Future<void> _performLogout() async {
    HapticFeedback.heavyImpact();
    final rootCtx = rootNavigatorKey.currentContext ?? context;

    // Show non-dismissible loading indicator
    showDialog(
      context: rootCtx,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFF59E0B)),
                const SizedBox(height: 16),
                Text(
                  'Signing out...',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await AuthService.instance.signOut();
    } catch (_) {}

    // Route cleanly to LoginScreen on rootNavigatorKey
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openWhatsAppSupport() async {
    HapticFeedback.lightImpact();
    final url = Uri.parse('https://wa.me/918669997711?text=${Uri.encodeComponent("Hello KamaiPlus Team, I need assistance.")}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted) {
        InAppNotification.show(
          context: context,
          message: 'WhatsApp Support: +91 8669997711',
          customIcon: Icons.support_agent_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vert = BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value);
    final act = widget.activeScreen?.toLowerCase().trim();
    final tab = widget.currentTabIndex;

    final isHomeActive = act == 'home' || (act == null && tab == 0);
    final isProductsActive = act == 'products' || (act == null && tab == 1);
    final isPosActive = act == 'pos' || act == 'billing' || (act == null && tab == 2);
    final isKhataActive = act == 'khata' || (act == null && tab == 3);
    final isTransactionsActive = act == 'transactions';
    final isCashRegisterActive = act == 'cash_register';
    final isPurchasesActive = act == 'purchases';
    final isInventoryActive = act == 'inventory';
    final isBarcodeActive = act == 'barcode_studio';
    final isCustomersActive = act == 'customers';
    final isGrowthActive = act == 'growth_campaigns' || act == 'growth';
    final isReferActive = act == 'refer_and_earn';
    final isGstActive = act == 'gst_reports';
    final isInvoiceThemesActive = act == 'invoice_themes';
    final isBackupRestoreActive = act == 'backup_restore';
    final isStoreProfileActive = act == 'store_profile';
    final isPrinterActive = act == 'printer_settings';

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

                  // Center POS Counter Billing (Navigation Tab 2)
                  _buildNavCard(
                    title: 'POS Counter Billing',
                    subtitle: 'Fast Barcode Billing, Quick Cart & Rapid Checkout',
                    icon: Icons.point_of_sale_rounded,
                    iconColor: const Color(0xFF10B981),
                    iconBg: const Color(0xFFECFDF5),
                    borderColor: const Color(0xFFA7F3D0),
                    badgeText: isPosActive ? '● ACTIVE' : 'CENTER POS',
                    badgeBg: isPosActive ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    badgeColor: isPosActive ? const Color(0xFF34D399) : const Color(0xFF059669),
                    isDark: isPosActive,
                    onTap: () => _handleTabTap(2),
                  ),
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
                          badgeText: isHomeActive ? '● ACTIVE' : 'PULSE',
                          badgeBg: isHomeActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isHomeActive ? const Color(0xFF34D399) : null,
                          isDark: isHomeActive,
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
                          badgeText: isTransactionsActive ? '● ACTIVE' : 'HISTORY',
                          badgeBg: isTransactionsActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isTransactionsActive ? const Color(0xFF34D399) : null,
                          isDark: isTransactionsActive,
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
                    badgeText: isCashRegisterActive ? '● ACTIVE' : 'Z-REPORT',
                    badgeBg: isCashRegisterActive ? const Color(0xFF064E3B) : const Color(0xFFFFFBEB),
                    badgeColor: isCashRegisterActive ? const Color(0xFF34D399) : const Color(0xFFB45309),
                    isDark: isCashRegisterActive,
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
                          icon: vert.navActiveIcon,
                          iconColor: const Color(0xFF3B82F6),
                          iconBg: const Color(0xFFEFF6FF),
                          borderColor: const Color(0xFFDBEAFE),
                          badgeText: isProductsActive ? '● ACTIVE' : 'CATALOG',
                          badgeBg: isProductsActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isProductsActive ? const Color(0xFF34D399) : null,
                          isDark: isProductsActive,
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
                          badgeText: isPurchasesActive ? '● ACTIVE' : 'AI OCR',
                          badgeBg: isPurchasesActive ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                          badgeColor: isPurchasesActive ? const Color(0xFF34D399) : const Color(0xFF059669),
                          isDark: isPurchasesActive,
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
                          badgeText: isInventoryActive ? '● ACTIVE' : 'ALERTS',
                          badgeBg: isInventoryActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isInventoryActive ? const Color(0xFF34D399) : null,
                          isDark: isInventoryActive,
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
                            badgeText: isBarcodeActive ? '● ACTIVE' : 'PRINT',
                            badgeBg: isBarcodeActive ? const Color(0xFF064E3B) : null,
                            badgeColor: isBarcodeActive ? const Color(0xFF34D399) : null,
                            isDark: isBarcodeActive,
                            isLocked: true,
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
                          badgeText: isKhataActive ? '● ACTIVE' : 'UDHAR',
                          badgeBg: isKhataActive ? const Color(0xFF064E3B) : const Color(0xFFFEF2F2),
                          badgeColor: isKhataActive ? const Color(0xFF34D399) : const Color(0xFFDC2626),
                          isDark: isKhataActive,
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
                          badgeText: isCustomersActive ? '● ACTIVE' : 'CRM',
                          badgeBg: isCustomersActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isCustomersActive ? const Color(0xFF34D399) : null,
                          isDark: isCustomersActive,
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
                          badgeText: isGrowthActive ? '● ACTIVE' : 'AUTO',
                          badgeBg: isGrowthActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isGrowthActive ? const Color(0xFF34D399) : null,
                          isDark: isGrowthActive,
                          isLocked: true,
                          onTap: () => _handleScreenPush(const GrowthCampaignsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildNavCard(
                          title: _isPro ? 'Pro Active' : 'Kamai+ Pro',
                          subtitle: _isPro ? 'All Features Unlocked' : 'Cloud & Multi-Staff',
                          icon: Icons.auto_awesome_rounded,
                          iconColor: _isPro ? const Color(0xFF059669) : const Color(0xFF9333EA),
                          iconBg: _isPro ? const Color(0xFFECFDF5) : const Color(0xFFFAF5FF),
                          borderColor: _isPro ? const Color(0xFFA7F3D0) : const Color(0xFFE9D5FF),
                          badgeText: _isPro ? 'PRO ACTIVE' : 'PRO',
                          badgeBg: _isPro ? const Color(0xFFD1FAE5) : const Color(0xFFFAF5FF),
                          badgeColor: _isPro ? const Color(0xFF059669) : const Color(0xFF7E22CE),
                          onTap: _handleProUpgrade,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildNavCard(
                    title: 'Refer & Earn (Free PRO)',
                    subtitle: 'Invite merchant friends & earn ${RemoteConfigService.instance.referralRewardDays} Days Free PRO per store',
                    icon: Icons.card_giftcard_rounded,
                    iconColor: const Color(0xFFD97706),
                    iconBg: const Color(0xFFFFFBEB),
                    borderColor: const Color(0xFFFDE68A),
                    badgeText: isReferActive ? '● ACTIVE' : '30D FREE',
                    badgeBg: isReferActive ? const Color(0xFF064E3B) : const Color(0xFFFEF3C7),
                    badgeColor: isReferActive ? const Color(0xFF34D399) : const Color(0xFFB45309),
                    isDark: isReferActive,
                    onTap: () => _handleScreenPush(const ReferAndEarnScreen()),
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
                          badgeText: isGstActive ? '● ACTIVE' : 'CA READY',
                          badgeBg: isGstActive ? const Color(0xFF064E3B) : const Color(0xFFEEF2FF),
                          badgeColor: isGstActive ? const Color(0xFF34D399) : const Color(0xFF4338CA),
                          isDark: isGstActive,
                          isLocked: true,
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
                          badgeText: isInvoiceThemesActive ? '● ACTIVE' : 'DESIGN',
                          badgeBg: isInvoiceThemesActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isInvoiceThemesActive ? const Color(0xFF34D399) : null,
                          isDark: isInvoiceThemesActive,
                          onTap: () => _handleScreenPush(const InvoiceThemesScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildNavCard(
                    title: 'Advanced Sales Reports',
                    subtitle: 'Party-wise, Category & Item Summary',
                    icon: Icons.insights_rounded,
                    iconColor: const Color(0xFF4F46E5),
                    iconBg: const Color(0xFFEEF2FF),
                    borderColor: const Color(0xFFC7D2FE),
                    badgeText: 'ANALYTICS',
                    badgeBg: const Color(0xFFEEF2FF),
                    badgeColor: const Color(0xFF4338CA),
                    onTap: () => _handleScreenPush(const AdvancedSalesReportsScreen()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavCard(
                          title: 'Backup & Reset',
                          subtitle: 'Vault & Start Fresh',
                          icon: Icons.cloud_done_rounded,
                          iconColor: const Color(0xFF0284C7),
                          iconBg: const Color(0xFFF0F9FF),
                          borderColor: const Color(0xFFBAE6FD),
                          badgeText: isBackupRestoreActive ? '● ACTIVE' : 'RESET',
                          badgeBg: isBackupRestoreActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isBackupRestoreActive ? const Color(0xFF34D399) : null,
                          isDark: isBackupRestoreActive,
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
                          badgeText: isStoreProfileActive ? '● ACTIVE' : 'CONFIG',
                          badgeBg: isStoreProfileActive ? const Color(0xFF064E3B) : null,
                          badgeColor: isStoreProfileActive ? const Color(0xFF34D399) : null,
                          isDark: isStoreProfileActive,
                          onTap: () => _handleScreenPush(const StoreProfileScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildNavCard(
                    title: 'Printer & Hardware Setup',
                    subtitle: 'Bluetooth Thermal (58/80mm) & A4 System Spooler',
                    icon: Icons.print_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    iconBg: const Color(0xFFF5F3FF),
                    borderColor: const Color(0xFFDDD6FE),
                    badgeText: isPrinterActive ? '● ACTIVE' : 'HARDWARE',
                    badgeBg: isPrinterActive ? const Color(0xFF064E3B) : const Color(0xFFF5F3FF),
                    badgeColor: isPrinterActive ? const Color(0xFF34D399) : const Color(0xFF7C3AED),
                    isDark: isPrinterActive,
                    onTap: () => _handleScreenPush(const PrinterSettingsScreen()),
                  ),
                  const SizedBox(height: 10),
                  // Help & Support. Until now the app had no support entry
                  // point at all — a merchant with a stuck bill or a failed
                  // payment had nowhere in the app to turn. The number and
                  // email come from Firebase Remote Config, so support routing
                  // can change without an app release (previously those two
                  // parameters were fetched on every launch and never read).
                  _buildNavCard(
                    title: 'Help & Support',
                    subtitle: 'WhatsApp our team or email us — we reply fast',
                    icon: Icons.support_agent_rounded,
                    iconColor: const Color(0xFF059669),
                    iconBg: const Color(0xFFECFDF5),
                    borderColor: const Color(0xFFA7F3D0),
                    badgeText: 'SUPPORT',
                    badgeBg: const Color(0xFFECFDF5),
                    badgeColor: const Color(0xFF059669),
                    onTap: _showSupportSheet,
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
    bool isLocked = false,
    required VoidCallback onTap,
  }) {
    final showLock = isLocked && !_isPro;
    final effectiveBorder = isDark ? const Color(0xFF1E293B) : (borderColor ?? const Color(0xFFE2E8F0));
    return Material(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          if (showLock) {
            ProUpgradeModal.show(context).then((_) => _checkPro());
          } else {
            onTap();
          }
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
                        if (showLock) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_rounded, size: 9, color: Color(0xFFB45309)),
                                const SizedBox(width: 2.5),
                                Text(
                                  'PRO',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isLocked && _isPro) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFA7F3D0), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stars_rounded, size: 9, color: Color(0xFF059669)),
                                const SizedBox(width: 2.5),
                                Text(
                                  'PRO',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (badgeText != null) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? (badgeBg ?? (badgeText.contains('ACTIVE') ? const Color(0xFF064E3B) : Colors.white.withValues(alpha: 0.15)))
                                  : (badgeBg ?? (iconBg ?? const Color(0xFFF1F5F9))),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? (badgeColor ?? (badgeText.contains('ACTIVE') ? const Color(0xFF34D399) : Colors.white))
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1. Version Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Text(
                'v4.28.0',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),

            // 2. WhatsApp Support Button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openWhatsAppSupport,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/whatsapp_logo.png', width: 14, height: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Support',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Language Switcher Button (En)
            ValueListenableBuilder<String>(
              valueListenable: AppLanguageService.instance.currentLanguageNotifier,
              builder: (context, langCode, _) {
                final activeLang = AppStrings.supportedLanguages.firstWhere(
                  (l) => l.code == langCode,
                  orElse: () => AppStrings.supportedLanguages.first,
                );
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => LanguageSelectionModal.show(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(activeLang.flag, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            activeLang.code.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1D4ED8),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Color(0xFF1D4ED8)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // 4. Logout Button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showLogoutDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout_rounded, color: Color(0xFFE11D48), size: 13),
                      const SizedBox(width: 4),
                      Text(
                        'Logout',
                        style: GoogleFonts.inter(
                          fontSize: 11,
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
      ),
    );
  }
}
