import '../common/upi_standee_modal.dart';
import '../common/pro_upgrade_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../cash_register/cash_register_screen.dart';
import '../transactions/transactions_screen.dart';
import '../inventory/inventory_screen.dart';
import '../purchases/purchases_screen.dart';
import '../customers/customers_screen.dart';
import '../reports/gst_reports_screen.dart';
import '../settings/invoice_themes_screen.dart';
import '../settings/backup_restore_screen.dart';
import '../settings/store_profile_screen.dart';
import '../settings/bluetooth_printer_dialog.dart';
import '../tools/barcode_studio_screen.dart';
import '../growth/growth_campaigns_screen.dart';

class MenuScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;

  const MenuScreen({super.key, this.onNavigateTab});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  StoreProfileModel _profile = StoreProfileModel();
  int _skuCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMenuData();
  }

  Future<void> _loadMenuData() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final products = await LocalDatabase.instance.getAllProducts();
      if (mounted) {
        setState(() {
          _profile = profile;
          _skuCount = products.length;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(66),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFEEF2F6), width: 1)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => ProUpgradeModal.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  _buildCircleBtn(Icons.qr_code_2_rounded, () {
                    UpiStandeeModal.show(context);
                  }),
                  const SizedBox(width: 6),
                  _buildCircleBtn(Icons.chat_bubble_outline_rounded, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GrowthCampaignsScreen()),
                    );
                  }, color: const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StoreProfileScreen()),
                        );
                        _loadMenuData();
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _profile.storeName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  '${_profile.ownerName} • ${_profile.category.split('/').first.trim()}',
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                // Quick Counter Hero Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF064E3B), Color(0xFF042F2E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF064E3B).withValues(alpha: 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.scale_rounded,
                          color: Color(0xFF34D399),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Kirana Fast Counter',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'GROCERY DESK',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF6EE7B7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Auto-focus barcode & loose staples weight',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (widget.onNavigateTab != null) {
                            widget.onNavigateTab!(2);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Counter',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section 1: DAILY COUNTER & OPS
                _buildSectionHeader('DAILY COUNTER & OPS', const Color(0xFF10B981)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.point_of_sale_rounded,
                        iconColor: const Color(0xFF10B981),
                        bgColor: const Color(0xFFECFDF5),
                        title: 'Billing (POS)',
                        subtitle: 'Instant Checkout',
                        onTap: () => widget.onNavigateTab?.call(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.calculate_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        bgColor: const Color(0xFFFFFBEB),
                        title: 'Cash Register',
                        subtitle: 'Shift & Z-Report',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CashRegisterScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildMenuGridTile(
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  bgColor: const Color(0xFFF0F9FF),
                  title: 'Transactions & Sales History',
                  subtitle: 'Audit ledger, reprints & refund returns',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                  ),
                ),
                const SizedBox(height: 20),

                // Section 2: STOCK & SOURCING
                _buildSectionHeader('STOCK & SOURCING', const Color(0xFF3B82F6)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.inventory_2_rounded,
                        iconColor: const Color(0xFF3B82F6),
                        bgColor: const Color(0xFFEFF6FF),
                        title: 'Products Master',
                        subtitle: '$_skuCount SKUs',
                        onTap: () => widget.onNavigateTab?.call(1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.radar_rounded,
                        iconColor: const Color(0xFF06B6D4),
                        bgColor: const Color(0xFFECFEFF),
                        title: 'Inventory & Expiry',
                        subtitle: 'Stock Radar',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const InventoryScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.shopping_bag_rounded,
                        iconColor: const Color(0xFFD97706),
                        bgColor: const Color(0xFFFFFBEB),
                        title: 'Purchases & Bills',
                        subtitle: 'Vendor Inward & AI',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PurchasesScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.qr_code_scanner_rounded,
                        iconColor: const Color(0xFF8B5CF6),
                        bgColor: const Color(0xFFF5F3FF),
                        title: 'Barcode Studio',
                        subtitle: 'Price Stickers',
                        badge: 'PRO',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BarcodeStudioScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Section 3: LEDGER, GROWTH & GST
                _buildSectionHeader('LEDGER, GROWTH & GST', const Color(0xFF8B5CF6)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.menu_book_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        bgColor: const Color(0xFFFFFBEB),
                        title: 'Khata Ledger',
                        subtitle: 'Customer Udhar',
                        onTap: () => widget.onNavigateTab?.call(3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.people_alt_rounded,
                        iconColor: const Color(0xFF0EA5E9),
                        bgColor: const Color(0xFFF0F9FF),
                        title: 'Customers CRM',
                        subtitle: 'Directory & Dues',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CustomersScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.trending_up_rounded,
                        iconColor: const Color(0xFFEC4899),
                        bgColor: const Color(0xFFFDF2F8),
                        title: 'WhatsApp Growth',
                        subtitle: 'Festival Offers',
                        badge: 'PRO',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GrowthCampaignsScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.receipt_rounded,
                        iconColor: const Color(0xFF6366F1),
                        bgColor: const Color(0xFFEEF2FF),
                        title: 'GST & Accounts',
                        subtitle: 'GSTR-1 & Tally',
                        badge: 'PRO',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GstReportsScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Section 4: SETTINGS, DESIGN & BACKUP
                _buildSectionHeader('STORE SETTINGS & BACKUP', const Color(0xFF64748B)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.palette_rounded,
                        iconColor: const Color(0xFF10B981),
                        bgColor: const Color(0xFFECFDF5),
                        title: 'Invoice Themes',
                        subtitle: 'PDF & Thermal',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const InvoiceThemesScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.cloud_sync_rounded,
                        iconColor: const Color(0xFF0284C7),
                        bgColor: const Color(0xFFF0F9FF),
                        title: 'Backup & Restore',
                        subtitle: 'JSON & Cloud Sync',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.store_rounded,
                        iconColor: const Color(0xFF8B5CF6),
                        bgColor: const Color(0xFFF5F3FF),
                        title: 'Store Profile',
                        subtitle: 'Name, UPI & VAT',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const StoreProfileScreen()),
                          );
                          _loadMenuData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMenuGridTile(
                        icon: Icons.print_rounded,
                        iconColor: const Color(0xFF475569),
                        bgColor: const Color(0xFFF1F5F9),
                        title: 'Thermal Printer',
                        subtitle: 'Bluetooth 58/80mm',
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => const BluetoothPrinterDialog(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, Color dotColor) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuGridTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Text(
                              badge,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFD97706),
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
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
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
}
