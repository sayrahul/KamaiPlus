import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/app_validators.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/invoice_pdf_service.dart';
import '../customers/customers_screen.dart';
import '../../services/contacts_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../transactions/sale_detail_modal.dart';
import '../common/empty_state_card.dart';
import '../common/in_app_notification.dart';

class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key});

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  List<CustomerModel> _customers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All' | 'Due' | 'Clear' | 'VIP'
  CustomerModel? _selectedCustomer;
  StoreProfileModel _storeProfile = StoreProfileModel();

  // Selected customer data
  List<LedgerTransactionModel> _customerLedger = [];
  List<SaleModel> _customerBills = [];
  int _activeCustomerSubTab = 0; // 0: Ledger Timeline, 1: Pending Bills
  String _billsFilter = 'Pending'; // 'Pending' | 'All' | 'Settled'
  final Set<String> _selectedBillIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final customers = await LocalDatabase.instance.getAllCustomers();
      final profile = await LocalDatabase.instance.getStoreProfile();

      if (mounted) {
        setState(() {
          _customers = customers;
          _storeProfile = profile;
          _isLoading = false;

          // If a customer was selected, refresh their current state
          if (_selectedCustomer != null) {
            final updated = customers.where((c) => c.id == _selectedCustomer!.id).firstOrNull;
            if (updated != null) {
              _selectedCustomer = updated;
            }
          }
        });

        if (_selectedCustomer != null) {
          _loadCustomerDetails(_selectedCustomer!);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCustomerDetails(CustomerModel customer) async {
    try {
      final ledger = await LocalDatabase.instance.getLedgerForCustomer(customer.id);
      final bills = await LocalDatabase.instance.getSalesForCustomer(customer.id, phone: customer.phone);
      if (mounted) {
        setState(() {
          _customerLedger = ledger;
          _customerBills = bills;
        });
      }
    } catch (_) {}
  }

  int get _totalMarketUdharPaise {
    return _customers.where((c) => c.currentBalancePaise > 0).fold(0, (sum, c) => sum + c.currentBalancePaise);
  }

  int get _dueCustomersCount {
    return _customers.where((c) => c.currentBalancePaise > 0).length;
  }

  List<CustomerModel> get _filteredCustomers {
    return _customers.where((c) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = c.name.toLowerCase().contains(q);
        final matchPhone = c.phone.contains(q);
        final matchAddress = (c.address ?? '').toLowerCase().contains(q);
        if (!matchName && !matchPhone && !matchAddress) return false;
      }

      if (_selectedFilter == 'Due') return c.currentBalancePaise > 0;
      if (_selectedFilter == 'Clear') return c.currentBalancePaise <= 0;
      if (_selectedFilter == 'VIP') return c.isVip;

      return true;
    }).toList();
  }

  void _sendWhatsAppReminder(CustomerModel customer) async {
    HapticFeedback.lightImpact();
    final int rupees = customer.currentBalancePaise ~/ 100;
    final totalRupeesStr = (customer.currentBalancePaise / 100.0).toStringAsFixed(2);
    final storeName = _storeProfile.storeName.isNotEmpty ? _storeProfile.storeName : 'KamaiPlus Store';
    final upiId = _storeProfile.upiVpa.isNotEmpty ? _storeProfile.upiVpa : 'proventure@icici';
    final upiPayLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(storeName)}&am=$totalRupeesStr&cu=INR';

    final text = 'Namaste ${customer.name} ji! 🙏\n\n'
        '$storeName par aapka baki hisaab ₹$rupees hai.\n'
        'Kripya samay par chukta karein.\n\n'
        '📲 *Instant UPI Pay:* $upiPayLink\n'
        '📌 UPI ID: $upiId\n\n'
        'Dhanyawad!';

    // Generate Statement PDF and share
    try {
      final ledger = await LocalDatabase.instance.getLedgerForCustomer(customer.id);
      final shared = await InvoicePdfService.generateAndShareKhataStatementPdf(
        customer: customer,
        storeName: storeName,
        storePhone: _storeProfile.phone,
        upiId: upiId,
        ledger: ledger,
        customMessage: text,
      );

      if (!shared) {
        final waPhone = AppValidators.formatWhatsAppPhone(customer.phone);
        final url = Uri.parse('https://wa.me/$waPhone?text=${Uri.encodeComponent(text)}');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {
      final waPhone = AppValidators.formatWhatsAppPhone(customer.phone);
      final url = Uri.parse('https://wa.me/$waPhone?text=${Uri.encodeComponent(text)}');
      try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }
  }

  void _makePhoneCall(String phone) async {
    HapticFeedback.lightImpact();
    final url = Uri.parse('tel:$phone');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (_) {}
  }

  void _shareLedgerSlip(LedgerTransactionModel tx, CustomerModel customer) async {
    HapticFeedback.lightImpact();
    final isUdhar = tx.type == 'credit';
    final amtRupees = tx.amountPaise ~/ 100;
    final balRupees = tx.balanceAfterPaise ~/ 100;
    final storeName = _storeProfile.storeName.isNotEmpty ? _storeProfile.storeName : 'KamaiPlus Store';
    final upiId = _storeProfile.upiVpa.isNotEmpty ? _storeProfile.upiVpa : 'proventure@icici';
    final upiPayLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(storeName)}&am=$balRupees&cu=INR';
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(tx.createdAt);

    final text = '🧾 *HISAB PARCHA / HISAAB SLIP*\n'
        '🏪 *$storeName*\n'
        '👤 Customer: ${customer.name}\n'
        '📅 Date: $dateStr\n'
        '--------------------------\n'
        '${isUdhar ? "🔴 Udhar Diya (Given)" : "🟢 Jama Mila (Received)"}: ₹$amtRupees\n'
        '📝 Note: ${tx.description.isNotEmpty ? tx.description : "Khata Transaction"}\n'
        '--------------------------\n'
        '💰 *Kul Baki (Balance): ₹$balRupees*\n'
        '📲 *UPI Pay:* $upiPayLink\n\n'
        'Dhanyawad!';

    final waPhone = AppValidators.formatWhatsAppPhone(customer.phone);
    final url = Uri.parse('https://wa.me/$waPhone?text=${Uri.encodeComponent(text)}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _shareBillViaWhatsApp(SaleModel bill, CustomerModel customer) async {
    HapticFeedback.lightImpact();
    final amtRupees = bill.totalAmountPaise ~/ 100;
    final totalRupees = (bill.totalAmountPaise / 100.0).toStringAsFixed(2);
    final storeName = _storeProfile.storeName.isNotEmpty ? _storeProfile.storeName : 'KamaiPlus Store';
    final upiId = _storeProfile.upiVpa.isNotEmpty ? _storeProfile.upiVpa : 'proventure@icici';
    final upiPayLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(storeName)}&am=$totalRupees&cu=INR&tn=Bill_${bill.invoiceNumber}';
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(bill.createdAt);

    final buffer = StringBuffer();
    buffer.writeln('🧾 *INVOICE #${bill.invoiceNumber}*');
    buffer.writeln('🏪 *$storeName*');
    buffer.writeln('👤 Customer: ${customer.name}');
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('--------------------------');
    for (final it in bill.items) {
      final name = it['product_name'] ?? it['name'] ?? 'Item';
      final qty = it['quantity'] ?? it['qty'] ?? 1;
      final pricePaise = it['gross_total_paise'] ?? ((it['price'] as int? ?? 0) * (qty as num).toInt());
      final priceRupees = (pricePaise as int) ~/ 100;
      buffer.writeln('• ${qty}x $name = ₹$priceRupees');
    }
    buffer.writeln('--------------------------');
    buffer.writeln('💰 *Total Amount: ₹$amtRupees*');
    buffer.writeln('📌 Status: ${bill.status.toUpperCase()}');
    buffer.writeln('📲 *Instant UPI Pay / Receipt:* $upiPayLink');
    buffer.writeln('\nDhanyawad!');

    final fullPhone = AppValidators.formatWhatsAppPhone(customer.phone);

    // 1. Generate & Share PDF
    final filePath = await InvoicePdfService.generateAndDownloadPdf(
      sale: bill,
      storeName: storeName,
      storePhone: _storeProfile.phone,
      storeAddress: _storeProfile.address,
      gstin: _storeProfile.gstin,
      logoPath: _storeProfile.logoUrl,
      customerPhone: fullPhone,
    );

    bool shared = false;
    if (filePath != null && filePath.isNotEmpty) {
      shared = await InvoicePdfService.sharePdf(
        filePath: filePath,
        invoiceNumber: bill.invoiceNumber,
        storeName: storeName,
        phone: fullPhone,
        message: buffer.toString(),
        subject: 'Tax Invoice #${bill.invoiceNumber} - $storeName',
      );
    }

    if (!shared) {
      final url = Uri.parse('https://wa.me/$fullPhone?text=${Uri.encodeComponent(buffer.toString())}');
      try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }
  }

  // =========================================================================
  // BUILD METHOD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF059669))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _selectedCustomer == null
            ? _buildMainKhataDashboard()
            : _buildCustomerDetailView(_selectedCustomer!),
      ),
    );
  }

  // =========================================================================
  // LEVEL 1: MAIN KHATA DASHBOARD (OVERVIEW & CUSTOMER LIST)
  // =========================================================================
  Widget _buildMainKhataDashboard() {
    final filtered = _filteredCustomers;

    return RefreshIndicator(
      color: const Color(0xFF059669),
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: [
          // 1. Top Header Bar
          _buildTopBar(),
          const SizedBox(height: 14),

          // 2. Total Market Udhar Hero Card
          _buildMarketUdharHeroCard(),
          const SizedBox(height: 14),

          // 3. Search Bar
          _buildSearchBar(),
          const SizedBox(height: 10),

          // 4. Quick Filter Chips
          _buildFilterChips(),
          const SizedBox(height: 14),

          // 5. Customer Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CUSTOMER ACCOUNTS (${filtered.length})',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
              if (_selectedFilter != 'All')
                GestureDetector(
                  onTap: () => setState(() => _selectedFilter = 'All'),
                  child: Text(
                    'Clear Filter',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 6. Customer List Cards
          if (filtered.isEmpty)
            _buildEmptyCustomersState()
          else
            ...filtered.map((cust) => _buildCustomerCard(cust)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final totalAccounts = _customers.length;
    final dueCount = _dueCustomersCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Book Icon
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Icon(Icons.menu_book_rounded, color: Color(0xFFD97706), size: 22),
        ),
        const SizedBox(width: 10),

        // Title & Subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Digital Khata',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                '$dueCount Due • $totalAccounts Accounts',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),

        // 1. CRM Directory Button
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomersScreen()),
              ).then((_) => _loadData());
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
              ),
              child: const Icon(Icons.group_outlined, size: 18, color: Color(0xFF334155)),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 2. Golden Add Customer Button
        ElevatedButton.icon(
          onPressed: _showAddCustomerModal,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 15, color: Color(0xFF0F172A)),
          label: Text(
            '+ Add',
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: const Color(0xFF0F172A),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildMarketUdharHeroCard() {
    final udharPaise = _totalMarketUdharPaise;
    final dueCount = _dueCustomersCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Label + Outstanding Amount
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TOTAL MARKET UDHAR',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    MoneyFormatter.formatINR(udharPaise),
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Right: Compact Badges
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$dueCount Due',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFCA5A5),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_customers.length} Accounts',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
        decoration: InputDecoration(
          hintText: BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).placeholders.customerSearch,
          hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      {'key': 'All', 'label': 'All (${_customers.length})'},
      {'key': 'Due', 'label': 'Udhar Due ($_dueCustomersCount)'},
      {'key': 'Clear', 'label': 'Settled (${_customers.length - _dueCustomersCount})'},
      {'key': 'VIP', 'label': 'VIP'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              label: Text(
                f['label']!,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF0F172A),
              side: BorderSide(
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                width: 1.1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _selectedFilter = f['key']!);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
  Widget _buildCustomerCard(CustomerModel cust) {
    final hasUdhar = cust.currentBalancePaise > 0;
    final hasAdvance = cust.currentBalancePaise < 0;
    final absPaise = cust.currentBalancePaise.abs();
    final initial = cust.name.isNotEmpty ? cust.name[0].toUpperCase() : 'C';

    final Color cardBorderColor = hasUdhar
        ? const Color(0xFFFECACA)
        : hasAdvance
            ? const Color(0xFFA7F3D0)
            : const Color(0xFFE2E8F0);

    final Color avatarBg = hasUdhar
        ? const Color(0xFFFEF2F2)
        : hasAdvance
            ? const Color(0xFFECFDF5)
            : const Color(0xFFF1F5F9);

    final Color avatarText = hasUdhar
        ? const Color(0xFFDC2626)
        : hasAdvance
            ? const Color(0xFF059669)
            : const Color(0xFF475569);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedCustomer = cust);
            _loadCustomerDetails(cust);
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 1. Initial Avatar
                CircleAvatar(
                  radius: 19,
                  backgroundColor: avatarBg,
                  child: Text(
                    initial,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: avatarText,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 2. Name + Phone + Locality
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              cust.name,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (cust.isVip) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFFF59E0B), width: 0.7),
                              ),
                              child: Text(
                                '👑 VIP',
                                style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            cust.phone,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          if (cust.address != null && cust.address!.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                ' • ${cust.address}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Balance Amount & Status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasAdvance
                          ? '-${MoneyFormatter.formatINR(absPaise)}'
                          : MoneyFormatter.formatINR(absPaise),
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: hasUdhar
                            ? const Color(0xFFDC2626)
                            : hasAdvance
                                ? const Color(0xFF059669)
                                : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: hasUdhar
                            ? const Color(0xFFFEF2F2)
                            : hasAdvance
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        hasUdhar
                            ? 'UDHAR DUE'
                            : hasAdvance
                                ? 'ADVANCE'
                                : 'SETTLED',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: hasUdhar
                              ? const Color(0xFFDC2626)
                              : hasAdvance
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),

                // 4. Official WhatsApp Icon Button
                if (hasUdhar)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _sendWhatsAppReminder(cust),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        'assets/images/whatsapp_logo.png',
                        width: 24,
                        height: 24,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCustomersState() {
    return EmptyStateCard(
      icon: Icons.person_search_rounded,
      iconColor: const Color(0xFFD97706),
      iconBgColor: const Color(0xFFFEF3C7),
      title: 'Koi Grahak Nahi Mila',
      description: 'Search badal kar dekhein ya "+ Add" par click karke naya khata kholein.',
      actionText: '+ Naya Khata Kholein',
      onAction: _showAddCustomerModal,
    );
  }

  // =========================================================================
  // LEVEL 2: CUSTOMER 360° STATEMENT SCREEN (SCREENSHOTS 1, 2, 4, 5)
  // =========================================================================
  Widget _buildCustomerDetailView(CustomerModel customer) {
    final hasUdhar = customer.currentBalancePaise > 0;
    final initial = customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C';

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        // 1. Top Navigation Bar: < Back + Call + WhatsApp Reminder
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back Button
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCustomer = null);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new_rounded, size: 13, color: Color(0xFF0F172A)),
                      const SizedBox(width: 6),
                      Text(
                        'Back',
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Quick Call + WhatsApp Reminder Buttons
            Row(
              children: [
                Material(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => _makePhoneCall(customer.phone),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBAE6FD), width: 1.1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.call_rounded, size: 14, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                          Text(
                            'Call',
                            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => _sendWhatsAppReminder(customer),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/whatsapp_logo.png',
                            width: 16,
                            height: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'WhatsApp',
                            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF065F46)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. Compact Space-Saving Customer Identity & Balance Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasUdhar ? const Color(0xFFFED7AA) : const Color(0xFFE2E8F0),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Row 1: Avatar + Name/Phone + Outstanding Balance & Tag
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF0F172A),
                    child: Text(
                      initial,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                customer.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () async {
                                HapticFeedback.lightImpact();
                                final newStatus = !customer.isVip;
                                await LocalDatabase.instance.toggleCustomerVip(customer.id, newStatus);
                                final updated = customer.copyWith(isVip: newStatus);
                                setState(() {
                                  _selectedCustomer = updated;
                                  final idx = _customers.indexWhere((c) => c.id == customer.id);
                                  if (idx != -1) _customers[idx] = updated;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: customer.isVip ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: customer.isVip ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  customer.isVip ? '👑 VIP' : '+ Set VIP',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: customer.isVip ? const Color(0xFFB45309) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${customer.phone}${customer.address != null && customer.address!.isNotEmpty ? " • ${customer.address}" : ""}',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        MoneyFormatter.formatINR(customer.currentBalancePaise),
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: hasUdhar ? const Color(0xFFDC2626) : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: hasUdhar ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hasUdhar ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          hasUdhar ? 'UDHAR (बाकी)' : 'CLEAR (साफ)',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: hasUdhar ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: const Color(0xFFF1F5F9)),
              const SizedBox(height: 10),

              // Row 2: 2 Compact Retail Action Buttons (+ Udhar Diya vs - Jama Mila)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showGiveUdharModal(customer),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 15, color: Colors.white),
                      label: Text(
                        '+ Udhar Diya',
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showReceiveJamaModal(customer),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 15, color: Colors.white),
                      label: Text(
                        '- Jama Mila',
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. Segmented Sub-Tabs: 📜 Ledger Timeline (X) | 🧾 Pending Bills (Y)
        _buildCustomerSegmentedTabs(),
        const SizedBox(height: 12),

        // 4. Tab Content
        if (_activeCustomerSubTab == 0)
          _buildLedgerTimelineTab(customer)
        else
          _buildPendingBillsTab(customer),
      ],
    );
  }

  Widget _buildCustomerSegmentedTabs() {
    final timelineCount = _customerLedger.length;
    final pendingBillsCount = _customerBills.where((b) => b.paymentMethod == 'credit').length;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSubTabButton(
              index: 0,
              icon: '📜',
              label: 'Ledger Timeline ($timelineCount)',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildSubTabButton(
              index: 1,
              icon: '🧾',
              label: 'Pending Bills ($pendingBillsCount)',
              badgeCount: pendingBillsCount > 0 ? pendingBillsCount : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton({
    required int index,
    required String icon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = _activeCustomerSubTab == index;

    return Material(
      color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _activeCustomerSubTab = index);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
              if (badgeCount != null && badgeCount > 0 && !isSelected) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SUB-TAB 0: LEDGER TIMELINE (Full Chronological Statement)
  // -------------------------------------------------------------------------
  Widget _buildLedgerTimelineTab(CustomerModel customer) {
    if (_customerLedger.isEmpty) {
      return EmptyStateCard(
        icon: Icons.receipt_long_outlined,
        iconColor: const Color(0xFF0284C7),
        iconBgColor: const Color(0xFFE0F2FE),
        title: 'No Transaction History',
        description: 'Aapne abhi tak is grahak ka koi hisaab nahi joda hai. "+ Udhar Diya" ya "- Jama Mila" se start karein.',
        actionText: '+ Udhar Diya',
        onAction: () => _showGiveUdharModal(customer),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TRANSACTION STATEMENT (${_customerLedger.length})',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 0.6,
              ),
            ),
            Text(
              'Latest first',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._customerLedger.map((tx) => _buildLedgerCard(tx)),
      ],
    );
  }

  Widget _buildLedgerCard(LedgerTransactionModel tx) {
    final isUdhar = tx.type == 'credit'; // Udhar given to customer
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(tx.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUdhar ? const Color(0xFFFCA5A5).withValues(alpha: 0.5) : const Color(0xFFA7F3D0).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Tag badge + Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isUdhar ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUdhar ? Icons.north_east_rounded : Icons.south_west_rounded,
                      size: 13,
                      color: isUdhar ? const Color(0xFFDC2626) : const Color(0xFF059669),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUdhar ? 'YOU GAVE (उधार)' : 'YOU RECEIVED (जमा)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isUdhar ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${isUdhar ? "+" : "-"} ${MoneyFormatter.formatINR(tx.amountPaise)}',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: isUdhar ? const Color(0xFFDC2626) : const Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Description Note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tx.description.isNotEmpty ? tx.description : 'Khata Transaction',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          if (tx.description.contains('Voice Note') || tx.description.contains('🎙️')) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF2563EB), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recorded Voice Note', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF1E3A8A))),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(height: 3, width: 60, decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 4),
                            Expanded(child: Container(height: 2, color: const Color(0xFFCBD5E1))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('0:08s', style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF2563EB))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Date & Time
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text(
                dateStr,
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Bar: Balance After
          Container(height: 1, color: const Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bal: ${MoneyFormatter.formatINR(tx.balanceAfterPaise)}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
              Row(
                children: [
                  Material(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () {
                        if (_selectedCustomer != null) {
                          _shareLedgerSlip(tx, _selectedCustomer!);
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/whatsapp_logo.png', width: 14, height: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Share Slip',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SUB-TAB 1: PENDING BILLS (Credit sales invoices)
  // -------------------------------------------------------------------------
  Widget _buildPendingBillsTab(CustomerModel customer) {
    final creditBills = _customerBills.where((b) {
      if (_billsFilter == 'Pending') return b.paymentMethod == 'credit' && b.status != 'settled';
      if (_billsFilter == 'Settled') return b.status == 'settled';
      return true;
    }).toList();

    final unpaidBills = _customerBills.where((b) => b.paymentMethod == 'credit' && b.status != 'settled').toList();
    final selectedBills = _customerBills.where((b) => _selectedBillIds.contains(b.id)).toList();
    final selectedTotalPaise = selectedBills.fold<int>(0, (sum, b) => sum + b.totalAmountPaise);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter Pills: Pending (1) | All Bills (1) | Settled (0)
        Row(
          children: [
            _buildBillFilterChip('Pending', 'Pending (${_customerBills.where((b) => b.paymentMethod == 'credit' && b.status != 'settled').length})'),
            const SizedBox(width: 8),
            _buildBillFilterChip('All', 'All Bills (${_customerBills.length})'),
            const SizedBox(width: 8),
            _buildBillFilterChip('Settled', 'Settled (${_customerBills.where((b) => b.status == 'settled').length})'),
          ],
        ),
        const SizedBox(height: 10),

        if (unpaidBills.isNotEmpty && _billsFilter != 'Settled')
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedBillIds.isEmpty
                      ? 'Tick checkbox to select multiple bills'
                      : '${_selectedBillIds.length} of ${unpaidBills.length} bills selected',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                ),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_selectedBillIds.length == unpaidBills.length) {
                        _selectedBillIds.clear();
                      } else {
                        _selectedBillIds.addAll(unpaidBills.map((b) => b.id));
                      }
                    });
                  },
                  icon: Icon(
                    _selectedBillIds.length == unpaidBills.length ? Icons.deselect_rounded : Icons.select_all_rounded,
                    size: 16,
                    color: const Color(0xFF0284C7),
                  ),
                  label: Text(
                    _selectedBillIds.length == unpaidBills.length ? 'Deselect All' : 'Select All',
                    style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

        // Floating / Sticky Selection Bar
        if (_selectedBillIds.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_selectedBillIds.length} BILLS SELECTED',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MoneyFormatter.formatINR(selectedTotalPaise),
                        style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _openSelectiveBillSettlementModal(customer, selectedBills),
                  icon: const Icon(Icons.flash_on_rounded, size: 16, color: Colors.white),
                  label: Text('Settle Bills ⚡', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

        if (creditBills.isEmpty)
          const EmptyStateCard(
            icon: Icons.receipt_outlined,
            title: 'No Bills in this Filter',
            description: 'Jab aap POS Billing se credit bill banayenge, wo yahan automatic reflect hoga.',
          )
        else
          ...creditBills.map((bill) => _buildCreditBillCard(bill, customer)),
      ],
    );
  }

  Widget _buildBillFilterChip(String key, String label) {
    final isSelected = _billsFilter == key;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      label: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFF475569),
        ),
      ),
      backgroundColor: Colors.white,
      selectedColor: isSelected && key == 'Pending' ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
      side: BorderSide(
        color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0),
        width: 1.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _billsFilter = key);
      },
    );
  }

  Widget _buildCreditBillCard(SaleModel bill, CustomerModel customer) {
    final isSettled = bill.status == 'settled';
    final dateStr = DateFormat('d MMM yyyy • hh:mm a').format(bill.createdAt);
    final isSelected = _selectedBillIds.contains(bill.id);

    // Items preview string (Solved Issue 13: check product_name & quantity)
    String itemsPreview = '';
    if (bill.items.isNotEmpty) {
      final names = bill.items.map((it) {
        final q = it['quantity'] ?? it['qty'] ?? 1;
        final n = it['product_name'] ?? it['name'] ?? 'Item';
        return '${q}x $n';
      }).take(2).join(', ');
      itemsPreview = 'Items (${bill.items.length}): $names${bill.items.length > 2 ? "..." : ""}';
    } else {
      itemsPreview = 'Items (1): Store credit sale';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF059669)
              : (isSettled ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA)),
          width: isSelected ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Checkbox (if unpaid) + Invoice # + Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (!isSettled) ...[
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (val == true) {
                              _selectedBillIds.add(bill.id);
                            } else {
                              _selectedBillIds.remove(bill.id);
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '#${bill.invoiceNumber}',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSettled ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isSettled ? 'PAID (SETTLED)' : 'UNPAID (UDHAR)',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isSettled ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'CREDIT',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Date
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text(
                dateStr,
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Items Preview Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 15, color: Color(0xFFD97706)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    itemsPreview,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bill Total & Remaining Due
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BILL TOTAL',
                    style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8)),
                  ),
                  Text(
                    MoneyFormatter.formatINR(bill.totalAmountPaise),
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'REMAINING DUE',
                    style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFFDC2626)),
                  ),
                  Text(
                    isSettled ? '₹0.00' : MoneyFormatter.formatINR(bill.totalAmountPaise),
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isSettled ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Actions: View Bill + Clear Bill
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showBillDetailModal(bill),
                  icon: const Icon(Icons.receipt_long_rounded, size: 15, color: Color(0xFF0284C7)),
                  label: Text('View Bill 🧾', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7))),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF0F9FF),
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _shareBillViaWhatsApp(bill, customer),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Image.asset('assets/images/whatsapp_logo.png', width: 20, height: 20),
                ),
              ),
              if (!isSettled) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _settleBill(bill, customer),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 15, color: Colors.white),
                    label: Text('Clear Bill', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // MODALS & DIALOGS
  // =========================================================================

  // 1. ADD NEW CUSTOMER TO KHATA MODAL (SCREENSHOT 3)
  void _showAddCustomerModal() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0.00');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFD97706), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Add New Customer to Khata',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a new customer account to track Udhar and payment transactions.',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),

                InkWell(
                  onTap: () async {
                    final contact = await ContactsService.instance.pickContact();
                    if (contact != null) {
                      if (contact['name']?.isNotEmpty == true) {
                        nameCtrl.text = contact['name']!;
                      }
                      if (contact['phone']?.isNotEmpty == true) {
                        phoneCtrl.text = contact['phone']!;
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.contacts_rounded, size: 16, color: Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Text(
                          '📱 Phone Contacts se Chunein',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Customer Name
                _buildModalTextField(
                  label: 'Customer Name *',
                  hint: 'e.g. Ramesh Kumar',
                  controller: nameCtrl,
                ),
                const SizedBox(height: 12),

                // Phone Number
                _buildModalTextField(
                  label: 'Phone Number (For WhatsApp Statement & Reminders) *',
                  hint: '9876543210',
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),

                // Address / Locality
                _buildModalTextField(
                  label: 'Address / Locality (Optional)',
                  hint: 'e.g. Shop 4, Main Bazaar',
                  controller: addressCtrl,
                ),
                const SizedBox(height: 12),

                // Opening Balance
                _buildModalTextField(
                  label: 'Opening Balance (Purana Udhar / Advance) (₹)',
                  hint: '0.00',
                  controller: balanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  helper: 'Enter existing due balance if customer already owes money.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final address = addressCtrl.text.trim();
                final double openBalRupees = double.tryParse(balanceCtrl.text.trim()) ?? 0.0;
                final int openBalPaise = (openBalRupees * 100).round();

                if (name.isEmpty) {
                  InAppNotification.error('Please enter customer full name.', context: context);
                  return;
                }
                final phoneErr = AppValidators.validatePhone(phone);
                if (phoneErr != null) {
                  InAppNotification.error(phoneErr, context: context);
                  return;
                }
                final cleanPhone = AppValidators.cleanPhone(phone);

                final newCustomer = CustomerModel(
                  id: 'cust_${const Uuid().v4().substring(0, 8)}',
                  businessId: FirestoreSyncService.instance.activeBusinessId,
                  name: name,
                  phone: cleanPhone,
                  address: address.isNotEmpty ? address : null,
                  currentBalancePaise: openBalPaise,
                  creditLimitPaise: 500000,
                  syncStatus: 'pending',
                );

                await LocalDatabase.instance.upsertCustomer(newCustomer);

                // If opening balance > 0, insert opening balance ledger record
                if (openBalPaise > 0) {
                  final db = await LocalDatabase.instance.database;
                  await db.insert('ledger_transactions', {
                    'id': const Uuid().v4(),
                    'business_id': newCustomer.businessId,
                    'customer_id': newCustomer.id,
                    'type': 'credit',
                    'amount_paise': openBalPaise,
                    'balance_after_paise': openBalPaise,
                    'description': 'Initial opening balance',
                    'reference_id': null,
                    'created_at': DateTime.now().toIso8601String(),
                    'sync_status': 'pending',
                  });
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                _loadData();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Khata account opened for $name!'),
                    backgroundColor: const Color(0xFF059669),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Save Customer', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModalTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper, style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
        ],
      ],
    );
  }

  Widget _buildVoiceNoteRecorderSection({
    required bool isRecording,
    required bool hasVoiceNote,
    required VoidCallback onStartRecord,
    required VoidCallback onStopRecord,
    required VoidCallback onDeleteVoiceNote,
  }) {
    if (isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Recording voice note... Bol rahe hain',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: onStopRecord,
              icon: const Icon(Icons.stop_rounded, size: 14, color: Colors.white),
              label: Text('Attach', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      );
    }

    if (hasVoiceNote) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.mic_rounded, color: Color(0xFF2563EB), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🎙️ Voice Note Attached (0:08s)',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E3A8A)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
              onPressed: onDeleteVoiceNote,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onStartRecord,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_none_rounded, size: 17, color: Color(0xFF2563EB)),
            const SizedBox(width: 6),
            Text(
              '+ Add Voice Note (Bol kar likhein)',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
            ),
          ],
        ),
      ),
    );
  }

  // 2. RECEIVE PAYMENT (JAMA MILA) MODAL
  void _showReceiveJamaModal(CustomerModel customer) {
    final int defaultRupees = customer.currentBalancePaise ~/ 100;
    final amountCtrl = TextEditingController(text: defaultRupees > 0 ? '$defaultRupees' : '');
    final noteCtrl = TextEditingController(text: 'Cash Payment Received');
    String selectedMode = 'Cash';
    bool isRecording = false;
    bool hasVoice = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF059669), size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Receive Payment (Jama Settle)',
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  Text(
                    'Customer: ${customer.name} • Current Due: ${MoneyFormatter.formatINR(customer.currentBalancePaise)}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),

                  // Amount Received Input
                  Text('AMOUNT RECEIVED (₹) *', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF059669), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Quick Tender Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (defaultRupees > 0)
                          _buildQuickChip('Full: ₹$defaultRupees', defaultRupees.toString(), amountCtrl, setModalState),
                        _buildQuickChip('₹100', '100', amountCtrl, setModalState),
                        _buildQuickChip('₹500', '500', amountCtrl, setModalState),
                        _buildQuickChip('₹1,000', '1000', amountCtrl, setModalState),
                        _buildQuickChip('₹2,000', '2000', amountCtrl, setModalState),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Payment Mode
                  Text('PAYMENT METHOD', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                  const SizedBox(height: 6),
                  Row(
                    children: ['Cash', 'UPI', 'Bank'].map((m) {
                      final isSel = selectedMode == m;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: isSel,
                          label: Text(m, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: isSel ? Colors.white : const Color(0xFF334155))),
                          selectedColor: const Color(0xFF059669),
                          onSelected: (_) => setModalState(() => selectedMode = m),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Note
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Remarks / Description',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Voice Note Recorder (No Photo Attachment)
                  _buildVoiceNoteRecorderSection(
                    isRecording: isRecording,
                    hasVoiceNote: hasVoice,
                    onStartRecord: () => setModalState(() => isRecording = true),
                    onStopRecord: () {
                      setModalState(() {
                        isRecording = false;
                        hasVoice = true;
                      });
                    },
                    onDeleteVoiceNote: () => setModalState(() => hasVoice = false),
                  ),
                  const SizedBox(height: 20),

                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final double amtRupees = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                        final int amtPaise = (amtRupees * 100).round();

                        if (amtPaise <= 0) {
                          InAppNotification.error('Please enter a valid amount.', context: context);
                          return;
                        }

                        final voiceSuffix = hasVoice ? ' [🎙️ Voice Note]' : '';
                        await LocalDatabase.instance.recordCustomerLedgerEntry(
                          customer: customer,
                          type: 'debit', // payment received
                          amountPaise: amtPaise,
                          description: '${noteCtrl.text.trim()} ($selectedMode)$voiceSuffix',
                        );

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        _loadData();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Received ${MoneyFormatter.formatINR(amtPaise)} from ${customer.name}!'),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Confirm Jama (Receive Payment)', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 3. GIVE UDHAR (+ UDHAR DIYA) MODAL
  void _showGiveUdharModal(CustomerModel customer) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'Dukaan ration udhar');
    bool isRecording = false;
    bool hasVoice = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFDC2626), size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Give Credit (Udhar Diya)',
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  Text(
                    'Customer: ${customer.name} • Adding to outstanding due',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  Text('UDHAR AMOUNT (₹) *', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Item / Reason Note
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Items / Reason (e.g. Atta, Oil, Grocery)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Voice Note Recorder (No Photo Attachment)
                  _buildVoiceNoteRecorderSection(
                    isRecording: isRecording,
                    hasVoiceNote: hasVoice,
                    onStartRecord: () => setModalState(() => isRecording = true),
                    onStopRecord: () {
                      setModalState(() {
                        isRecording = false;
                        hasVoice = true;
                      });
                    },
                    onDeleteVoiceNote: () => setModalState(() => hasVoice = false),
                  ),
                  const SizedBox(height: 20),

                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final double amtRupees = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                        final int amtPaise = (amtRupees * 100).round();

                        if (amtPaise <= 0) {
                          InAppNotification.error('Please enter a valid amount.', context: context);
                          return;
                        }

                        final voiceSuffix = hasVoice ? ' [🎙️ Voice Note]' : '';
                        await LocalDatabase.instance.recordCustomerLedgerEntry(
                          customer: customer,
                          type: 'credit', // udhar given
                          amountPaise: amtPaise,
                          description: '${noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : "Udhar given"}$voiceSuffix',
                        );

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                    _loadData();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Recorded ${MoneyFormatter.formatINR(amtPaise)} Udhar for ${customer.name}!'),
                        backgroundColor: const Color(0xFFDC2626),
                      ),
                    );
                  },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Confirm Udhar Diya', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

  Widget _buildQuickChip(String label, String value, TextEditingController ctrl, StateSetter setModalState) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
        backgroundColor: const Color(0xFFF1F5F9),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        onPressed: () {
          HapticFeedback.selectionClick();
          setModalState(() => ctrl.text = value);
        },
      ),
    );
  }

  // 4. 1-TAP CLEAR SPECIFIC BILL
  void _settleBill(SaleModel bill, CustomerModel customer) {
    _openSelectiveBillSettlementModal(customer, [bill]);
  }

  // 5. VIEW BILL DETAILS MODAL (Solved Issue 13: route to professional SaleDetailModal)
  void _showBillDetailModal(SaleModel bill) {
    SaleDetailModal.show(
      context,
      sale: bill,
      onVoidOrRefund: () {
        _loadData();
      },
    );
  }

  // 6. SELECTIVE MULTI-BILL CREDIT SETTLEMENT MODAL (Solved Issue 14)
  void _openSelectiveBillSettlementModal(CustomerModel customer, List<SaleModel> bills) {
    if (bills.isEmpty) return;
    HapticFeedback.lightImpact();

    final totalPaise = bills.fold<int>(0, (sum, b) => sum + b.totalAmountPaise);
    final totalRupees = totalPaise ~/ 100;
    String selectedMode = 'cash'; // 'cash' | 'upi' | 'split'

    final cashReceivedCtrl = TextEditingController(text: totalRupees.toString());
    final splitCashCtrl = TextEditingController(text: (totalRupees ~/ 2).toString());
    final splitUpiCtrl = TextEditingController(text: (totalRupees - (totalRupees ~/ 2)).toString());

    final invoicesPreview = bills.map((b) => '#${b.invoiceNumber}').join(', ');
    final storeName = _storeProfile.storeName.isNotEmpty ? _storeProfile.storeName : 'KamaiPlus Store';
    final upiId = _storeProfile.upiVpa.isNotEmpty ? _storeProfile.upiVpa : 'proventure@icici';
    final upiPayUrl = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(storeName)}&am=${(totalPaise / 100.0).toStringAsFixed(2)}&cu=INR&tn=Settlement_${bills.length}_Bills';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final int cashReceivedPaise = MoneyFormatter.parseRupeesToPaise(cashReceivedCtrl.text);
            final int changeReturnPaise = (cashReceivedPaise - totalPaise).clamp(0, 999999999);

            return Container(
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Title & Close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settle Credit Bills',
                              style: GoogleFonts.outfit(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Customer: ${customer.name} • ${bills.length} Bill${bills.length > 1 ? "s" : ""}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Amount Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF047857)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL SETTLEMENT DUE',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFA7F3D0), letterSpacing: 0.5),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${bills.length} Bills',
                                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            MoneyFormatter.formatINR(totalPaise),
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Bills: $invoicesPreview',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD1FAE5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Payment Mode Segment Selector (Credit disabled!)
                    Text(
                      'Select Payment Mode Received:',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildSettlementModeChip(
                          mode: 'cash',
                          label: 'Cash 💵',
                          selected: selectedMode == 'cash',
                          onTap: () => setModalState(() => selectedMode = 'cash'),
                        ),
                        const SizedBox(width: 8),
                        _buildSettlementModeChip(
                          mode: 'upi',
                          label: 'UPI QR 📲',
                          selected: selectedMode == 'upi',
                          onTap: () => setModalState(() => selectedMode = 'upi'),
                        ),
                        const SizedBox(width: 8),
                        _buildSettlementModeChip(
                          mode: 'split',
                          label: 'Split 🔀',
                          selected: selectedMode == 'split',
                          onTap: () => setModalState(() => selectedMode = 'split'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Mode Specific Body
                    if (selectedMode == 'cash') ...[
                      Text(
                        'Cash Received from Customer (₹):',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: cashReceivedCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.currency_rupee, color: Color(0xFF059669), size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF059669), width: 1.8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 8),
                      // Quick Cash Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildQuickCashChip('Exact ₹$totalRupees', totalRupees.toString(), cashReceivedCtrl, setModalState),
                            if (totalRupees % 100 != 0)
                              _buildQuickCashChip('₹${((totalRupees ~/ 100) + 1) * 100}', (((totalRupees ~/ 100) + 1) * 100).toString(), cashReceivedCtrl, setModalState),
                            _buildQuickCashChip('₹${totalRupees + 100}', (totalRupees + 100).toString(), cashReceivedCtrl, setModalState),
                            _buildQuickCashChip('₹${totalRupees + 500}', (totalRupees + 500).toString(), cashReceivedCtrl, setModalState),
                          ],
                        ),
                      ),
                      if (changeReturnPaise > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Change to Return to Customer:',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E40AF)),
                              ),
                              Text(
                                MoneyFormatter.formatINR(changeReturnPaise),
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF1E40AF)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else if (selectedMode == 'upi') ...[
                      Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: upiPayUrl,
                                version: QrVersions.auto,
                                size: 160.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Scan with any UPI App (GPay, PhonePe, Paytm)',
                              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                            ),
                            Text(
                              'UPI ID: $upiId',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ] else if (selectedMode == 'split') ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cash (₹):', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: splitCashCtrl,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onChanged: (val) {
                                    final cashAmt = int.tryParse(val) ?? 0;
                                    final rem = (totalRupees - cashAmt).clamp(0, totalRupees);
                                    splitUpiCtrl.text = rem.toString();
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('UPI (₹):', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: splitUpiCtrl,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onChanged: (val) {
                                    final upiAmt = int.tryParse(val) ?? 0;
                                    final rem = (totalRupees - upiAmt).clamp(0, totalRupees);
                                    splitCashCtrl.text = rem.toString();
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Confirm Settle Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          final paymentModeStr = selectedMode == 'cash'
                              ? 'Cash Settle'
                              : (selectedMode == 'upi' ? 'UPI Settle' : 'Split Settle');

                          await LocalDatabase.instance.settleMultipleCustomerSaleBills(
                            saleIds: bills.map((b) => b.id).toList(),
                            customer: customer,
                            totalAmountPaise: totalPaise,
                            paymentMode: paymentModeStr,
                          );

                          if (!modalCtx.mounted) return;
                          Navigator.pop(modalCtx);

                          if (!mounted) return;
                          setState(() {
                            _selectedBillIds.clear();
                          });
                          _loadData();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Cleared ${bills.length} bills (${MoneyFormatter.formatINR(totalPaise)}) via $paymentModeStr!'),
                              backgroundColor: const Color(0xFF059669),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        label: Text(
                          'Confirm & Clear ${MoneyFormatter.formatINR(totalPaise)}',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettlementModeChip({
    required String mode,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickCashChip(String label, String value, TextEditingController ctrl, StateSetter setModalState) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
        backgroundColor: const Color(0xFFECFDF5),
        side: const BorderSide(color: Color(0xFFA7F3D0)),
        onPressed: () {
          HapticFeedback.selectionClick();
          setModalState(() => ctrl.text = value);
        },
      ),
    );
  }
}
