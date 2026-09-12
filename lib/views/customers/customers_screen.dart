import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/business_vertical_config.dart';
import '../../core/database/local_database.dart';
import '../../core/state/app_data_bus.dart';
import '../../core/state/data_bus_refresh.dart';
import '../../core/utils/app_validators.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/contacts_service.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/empty_state_card.dart';
import '../common/in_app_notification.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> with DataBusRefresh<CustomersScreen> {
  @override
  List<ValueNotifier<int>> get dataBusSignals => [
        AppDataBus.instance.customersRevision,
      ];

  @override
  void onDataBusChanged() => _loadCustomers();

  List<CustomerModel> _customers = [];
  bool _isLoading = true;
  bool _isPro = false;
  String _search = '';
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final customers = await LocalDatabase.instance.getAllCustomers();
      if (mounted) {
        setState(() {
          _isPro = profile.isPro;
          _customers = customers;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<CustomerModel> get _filteredCustomers {
    return _customers.where((c) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!c.name.toLowerCase().contains(q) && !c.phone.contains(q)) return false;
      }
      if (_filter == 'Udhar Due' && c.currentBalancePaise <= 0) return false;
      if (_filter == 'VIP') return c.isVip;
      if (_filter == 'Settled' && c.currentBalancePaise != 0) return false;
      return true;
    }).toList();
  }

  int get _totalUdharPaise =>
      _customers.where((c) => c.currentBalancePaise > 0).fold(0, (sum, c) => sum + c.currentBalancePaise);
  int get _activeUdharCount => _customers.where((c) => c.currentBalancePaise > 0).length;

  void _showAddCustomerModal() {
    if (!_isPro && _customers.length >= 100) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.group_add_rounded, color: Color(0xFFD97706), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Customer Limit Reached',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Text(
            'KamaiPlus Free plan supports up to 100 customers with basic ledger.\n\nTo manage unlimited customers, bulk WhatsApp reminders, and multi-device cloud backup, please upgrade to KamaiPlus Pro.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/settings');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBF24),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Upgrade to Pro', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      return;
    }
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '5000');

    bool isVip = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Add New Customer', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(modalCtx)),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final contact = await ContactsService.instance.pickContact();
                  if (contact != null) {
                    setModalState(() {
                      if (contact['name']?.isNotEmpty == true) {
                        nameCtrl.text = contact['name']!;
                      }
                      if (contact['phone']?.isNotEmpty == true) {
                        phoneCtrl.text = contact['phone']!;
                      }
                    });
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
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Customer Full Name *',
                  hintText: 'e.g. Ramesh Patel',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'WhatsApp Mobile Number *',
                  hintText: 'e.g. 9876543210',
                  prefixText: '+91 ',
                  suffixIcon: IconButton(
                    tooltip: 'Pick Contact',
                    icon: const Icon(Icons.contacts_rounded, color: Color(0xFF2563EB)),
                    onPressed: () async {
                      final contact = await ContactsService.instance.pickContact();
                      if (contact != null) {
                        setModalState(() {
                          if (contact['name']?.isNotEmpty == true) {
                            nameCtrl.text = contact['name']!;
                          }
                          if (contact['phone']?.isNotEmpty == true) {
                            phoneCtrl.text = contact['phone']!;
                          }
                        });
                      }
                    },
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Udhar Credit Limit (₹)',
                  hintText: '5000',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isVip ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isVip ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('👑', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VIP Customer Status',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isVip ? const Color(0xFFB45309) : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Special loyalty & priority service badge',
                              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: isVip,
                      activeThumbColor: const Color(0xFFF59E0B),
                      onChanged: (v) => setModalState(() => isVip = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      InAppNotification.error('Please enter customer full name', context: context);
                      return;
                    }
                    final phoneErr = AppValidators.validatePhone(phoneCtrl.text.trim());
                    if (phoneErr != null) {
                      InAppNotification.error(phoneErr, context: context);
                      return;
                    }
                    final cleanPhone = AppValidators.cleanPhone(phoneCtrl.text.trim());
                    final limit = int.tryParse(limitCtrl.text.trim()) ?? 5000;
                    final newCust = CustomerModel(
                      id: const Uuid().v4(),
                      businessId: FirestoreSyncService.instance.activeBusinessId,
                      name: name,
                      phone: cleanPhone,
                      creditLimitPaise: limit * 100,
                      isVip: isVip,
                    );
                    await LocalDatabase.instance.upsertCustomer(newCust);
                    if (!modalCtx.mounted) return;
                    Navigator.pop(modalCtx);
                    _loadCustomers();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save Customer Account', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomerDetailsModal(CustomerModel customer) async {
    HapticFeedback.lightImpact();
    final sales = await LocalDatabase.instance.getSalesForCustomer(customer.id, phone: customer.phone);
    final totalSpentPaise = sales.fold(0, (sum, s) => sum + s.totalAmountPaise);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final hasDue = customer.currentBalancePaise > 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: hasDue ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
                    foregroundColor: hasDue ? const Color(0xFFDC2626) : const Color(0xFF059669),
                    child: Text(
                      customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(customer.name, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                            ),
                            if (customer.isVip) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                ),
                                child: Text('👑 VIP', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFB45309))),
                              ),
                            ],
                          ],
                        ),
                        Text('+91 ${customer.phone}', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                    tooltip: 'Delete Customer',
                    onPressed: () => _confirmDeleteCustomer(ctx, customer),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Summary Stats Grid
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFEEF2F6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LIFETIME PURCHASES', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          Text(MoneyFormatter.formatPaise(totalSpentPaise), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          Text('${sales.length} Bills', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasDue ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: hasDue ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CURRENT UDHAR DUE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
                          const SizedBox(height: 4),
                          Text(MoneyFormatter.formatPaise(customer.currentBalancePaise), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
                          Text('Limit: ${MoneyFormatter.formatPaise(customer.creditLimitPaise)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // VIP Status Toggle Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: customer.isVip ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: customer.isVip ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('👑', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.isVip ? 'VIP Customer Account' : 'Standard Account',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: customer.isVip ? const Color(0xFFB45309) : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              customer.isVip ? 'Priority loyalty member' : 'Set as VIP member',
                              style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: customer.isVip,
                      activeThumbColor: const Color(0xFFF59E0B),
                      onChanged: (val) async {
                        HapticFeedback.lightImpact();
                        await LocalDatabase.instance.toggleCustomerVip(customer.id, val);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _loadCustomers();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final text = hasDue
                            ? 'Namaste%20${customer.name}%20Ji,%20Aapke%20KamaiPlus%20store%20ka%20Udhar%20balance%20${MoneyFormatter.formatPaise(customer.currentBalancePaise)}%20pending%20hai.%20Kripya%20UPI%20ya%20counter%20par%20clear%20karein.'
                            : 'Namaste%20${customer.name}%20Ji,%20Greetings%20from%20KamaiPlus%20Store!%20Aapka%20khata%20bilkul%20clear%20hai.';
                        final waPhone = AppValidators.formatWhatsAppPhone(customer.phone);
                        final uri = Uri.parse('https://wa.me/$waPhone?text=$text');
                        if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: Image.asset('assets/images/whatsapp_logo.png', width: 20, height: 20),
                      label: Text('WhatsApp', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddKhataEntryDialog(customer);
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                      label: Text('+ Jama / Udhar', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFF0F172A)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteCustomer(BuildContext modalContext, CustomerModel customer) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Customer?', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Kya aap ${customer.name} ko delete karna chahte hain? Inka khata ledger bhi permanently delete ho jayega.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              HapticFeedback.mediumImpact();
              Navigator.pop(dialogCtx);
              Navigator.pop(modalContext);
              await LocalDatabase.instance.deleteCustomer(customer.id);
              FirestoreSyncService.instance.deleteCustomerFromCloud(customer.id).catchError((_) {});
              if (!mounted) return;
              await _loadCustomers();
              if (!mounted) return;
              InAppNotification.success('Customer ${customer.name} deleted', context: context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showAddKhataEntryDialog(CustomerModel customer) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'debit'; // 'debit' = Jama mila (balance decreases), 'credit' = Udhar diya (balance increases)

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Record Entry for ${customer.name}', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Jama Mila (Paid)'),
                      selected: type == 'debit',
                      onSelected: (_) => setDialogState(() => type = 'debit'),
                      selectedColor: const Color(0xFF10B981),
                      labelStyle: TextStyle(color: type == 'debit' ? Colors.white : Colors.black),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Udhar Diya (Due)'),
                      selected: type == 'credit',
                      onSelected: (_) => setDialogState(() => type = 'credit'),
                      selectedColor: const Color(0xFFDC2626),
                      labelStyle: TextStyle(color: type == 'credit' ? Colors.white : Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount (₹) *',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: 'Note / Bill Reference',
                  hintText: 'e.g. Cash settlement, Tea snacks',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim());
                if (amt == null || amt <= 0) {
                  InAppNotification.error('Please enter a valid amount', context: context);
                  return;
                }
                final amountPaise = (amt * 100).round();
                await LocalDatabase.instance.recordCustomerLedgerEntry(
                  customer: customer,
                  type: type,
                  amountPaise: amountPaise,
                  description: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : (type == 'debit' ? 'Jama Mila' : 'Udhar Diya'),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                _loadCustomers();
                InAppNotification.success('Entry recorded for ${customer.name}', context: context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save Entry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredCustomers;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Customer Directory & CRM',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: _loadCustomers,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  // CRM Header Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEEF2F6)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.people_alt_rounded, color: Color(0xFF0284C7), size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Customer Directory & CRM',
                                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                                  ),
                                  Text(
                                    '${_customers.length} registered customers • ${MoneyFormatter.formatPaise(_totalUdharPaise)} market dues',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _showAddCustomerModal,
                                icon: const Icon(Icons.person_add_rounded, size: 16),
                                label: Text('+ Add Customer', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4-Metric Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox('Customers', 'Total', '${_customers.length}', const Color(0xFF0284C7)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricBox('VIP Members', 'High-Value', '${_customers.where((c) => c.isVip).length}', const Color(0xFFD97706)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox('Udhar Due', 'Pending', MoneyFormatter.formatPaise(_totalUdharPaise), const Color(0xFFEF4444)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricBox('Active Udhar', 'Ledgers', '$_activeUdharCount', const Color(0xFF8B5CF6)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search Bar & Filter Chips
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: GoogleFonts.inter(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: BusinessVerticals.resolve(BusinessVerticals.activeBusinessTypeNotifier.value).placeholders.customerSearch,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Udhar Due', 'VIP', 'Settled'].map((f) {
                        final sel = _filter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f),
                            selected: sel,
                            onSelected: (_) => setState(() => _filter = f),
                            selectedColor: const Color(0xFF0F172A),
                            labelStyle: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : const Color(0xFF64748B),
                            ),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Customer List
                  if (list.isEmpty)
                    EmptyStateCard(
                      icon: Icons.people_outline_rounded,
                      title: 'No Customers Found',
                      description: 'Add a new customer to start maintaining khata, credit limits, and CRM purchase history.',
                      actionText: '+ Add New Customer',
                      onAction: _showAddCustomerModal,
                    )
                  else
                    ...list.map((c) => _buildCustomerCard(c)),
                ],
              ),
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  Widget _buildMetricBox(String title, String subtitle, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8))),
            ],
          ),
          const SizedBox(height: 6),
          Text(amount, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(CustomerModel customer) {
    final hasDue = customer.currentBalancePaise > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showCustomerDetailsModal(customer),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: hasDue ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
                  foregroundColor: hasDue ? const Color(0xFFDC2626) : const Color(0xFF059669),
                  radius: 20,
                  child: Text(
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              customer.name,
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (customer.isVip) ...[
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
                      Text('+91 ${customer.phone}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hasDue ? MoneyFormatter.formatPaise(customer.currentBalancePaise) : '₹0.00',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                      ),
                    ),
                    Text(
                      hasDue ? 'Udhar Due' : 'All Clear',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Image.asset('assets/images/whatsapp_logo.png', width: 22, height: 22),
                  onPressed: () async {
                    final waPhone = AppValidators.formatWhatsAppPhone(customer.phone);
                    final uri = Uri.parse('https://wa.me/$waPhone?text=Namaste%20${customer.name},%20Greetings%20from%20KamaiPlus%20Store!');
                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
