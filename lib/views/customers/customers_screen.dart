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
import '../../services/gstin_service.dart';
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

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Renders a stored `MM-DD` birthday as "14 Aug". Returns the raw value if
  /// it is not in the expected shape rather than throwing on bad data.
  static String _formatBirthdayLabel(String mmDd) {
    final parts = mmDd.split('-');
    if (parts.length != 2) return mmDd;
    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    if (month == null || day == null || month < 1 || month > 12) return mmDd;
    return '$day ${_monthNames[month - 1]}';
  }

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

  /// Add a customer, or edit [existing] when one is passed.
  ///
  /// One modal for both, deliberately. Customer CRM shipped with Create, Read
  /// and Delete but no Update — the detail sheet offered only a bin icon — and
  /// the fix for that must not become a second, slightly-different write path.
  /// LocalDatabase.upsertCustomer is already keyed on id with
  /// ConflictAlgorithm.replace, so it IS the update; no new repository method
  /// was needed.
  void _showAddCustomerModal({CustomerModel? existing}) {
    final isEditing = existing != null;

    // The free-plan cap counts customers; editing one does not add any.
    if (!isEditing && !_isPro && _customers.length >= 100) {
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
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final limitCtrl = TextEditingController(
      text: existing != null
          ? (existing.creditLimitPaise ~/ 100).toString()
          : '5000',
    );
    final gstinCtrl = TextEditingController(text: existing?.gstin ?? '');

    bool isVip = existing?.isVip ?? false;
    bool isVerifyingGstin = false;
    String? birthdayMmDd = existing?.birthday;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
          final navBarPadding = MediaQuery.paddingOf(modalCtx).bottom;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(modalCtx).size.height * 0.90,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + (navBarPadding > 0 ? navBarPadding + 10 : 18)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Drag Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isEditing ? 'Edit Customer' : 'Add New Customer', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
                        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(modalCtx)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                  labelText: 'Credit Limit (₹)',
                  hintText: '5000',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gstinCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'GSTIN Number (Optional - B2B)',
                  hintText: 'e.g. 27AAAAA0000A1Z5',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: isVerifyingGstin
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0284C7)),
                              ),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: () async {
                              final raw = gstinCtrl.text.trim();
                              if (raw.isEmpty) {
                                InAppNotification.error('Please enter 15-character GSTIN first', context: modalCtx);
                                return;
                              }
                              setModalState(() => isVerifyingGstin = true);
                              final data = await GstinService.instance.verifyGstin(raw);
                              if (!modalCtx.mounted) return;
                              setModalState(() {
                                isVerifyingGstin = false;
                                if (data.isValid) {
                                  if (data.tradeName.isNotEmpty && nameCtrl.text.trim().isEmpty) {
                                    nameCtrl.text = data.tradeName;
                                  }
                                }
                              });
                              if (data.isValid) {
                                InAppNotification.show(
                                  context: modalCtx,
                                  message: '✓ Verified: ${data.tradeName.isNotEmpty ? data.tradeName : data.legalName}',
                                  customIcon: Icons.verified_rounded,
                                  customColor: const Color(0xFF059669),
                                );
                              } else {
                                InAppNotification.error(data.errorMessage ?? 'Invalid GSTIN', context: modalCtx);
                              }
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF0284C7)),
                            label: Text(
                              'Verify',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Birthday (day + month only, no year). Feeds the Birthday
              // campaign in WhatsApp Growth, which before this field existed
              // had nothing real to filter on.
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final now = DateTime.now();
                  final existingParts = birthdayMmDd?.split('-');
                  final initial = (existingParts != null && existingParts.length == 2)
                      ? DateTime(
                          now.year,
                          int.tryParse(existingParts[0]) ?? now.month,
                          int.tryParse(existingParts[1]) ?? now.day,
                        )
                      : now;
                  final picked = await showDatePicker(
                    context: modalCtx,
                    initialDate: initial,
                    // A full calendar year — the year itself is thrown away,
                    // only day and month are kept.
                    firstDate: DateTime(now.year, 1, 1),
                    lastDate: DateTime(now.year, 12, 31),
                    helpText: 'Select Birthday (day & month)',
                  );
                  if (picked != null) {
                    setModalState(() {
                      birthdayMmDd =
                          '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Text('🎂', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Birthday (optional)',
                              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              birthdayMmDd == null
                                  ? 'Not set — tap to add for birthday offers'
                                  : _formatBirthdayLabel(birthdayMmDd!),
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: birthdayMmDd == null
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF059669),
                                fontWeight: birthdayMmDd == null ? FontWeight.w400 : FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (birthdayMmDd != null)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () => setModalState(() => birthdayMmDd = null),
                          tooltip: 'Clear birthday',
                        )
                      else
                        const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF94A3B8)),
                    ],
                  ),
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
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
            final clash = await LocalDatabase.instance.findCustomerByPhone(cleanPhone);
            // When editing, finding YOURSELF on this number is not a clash.
            if (clash != null && clash.id != existing?.id) {
              if (modalCtx.mounted) {
                InAppNotification.error('Customer with mobile $cleanPhone already exists (${clash.name})!', context: modalCtx);
              }
              return;
            }
            final limit = int.tryParse(limitCtrl.text.trim()) ?? 5000;
            final rawGstin = gstinCtrl.text.trim().toUpperCase();
            final saved = CustomerModel(
              // Keep the id when editing, or upsertCustomer would insert
              // a duplicate and strand the original's khata ledger.
              id: existing?.id ?? const Uuid().v4(),
              businessId: existing?.businessId ??
                  FirestoreSyncService.instance.activeBusinessId,
              name: name,
              phone: cleanPhone,
              // Not editable on this form — carry it forward rather than
              // letting a full-row replace blank it.
              address: existing?.address,
              gstin: rawGstin.isNotEmpty ? rawGstin : null,
              stateCode: rawGstin.length >= 2 ? rawGstin.substring(0, 2) : null,
              // Udhaar owed is ledger-derived money. An edit to a name or
              // credit limit must never rewrite it.
              currentBalancePaise: existing?.currentBalancePaise ?? 0,
              creditLimitPaise: limit * 100,
              isVip: isVip,
              birthday: birthdayMmDd,
              syncStatus: 'pending',
            );
            await LocalDatabase.instance.upsertCustomer(saved);
            FirestoreSyncService.instance
                .pushCustomerToCloud(saved)
                .catchError((_) {});
            if (!modalCtx.mounted) return;
            Navigator.pop(modalCtx);
            _loadCustomers();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(isEditing ? 'Save Changes' : 'Save Customer Account', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ],
  ),
),
),
);
},
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
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF2563EB)),
                    tooltip: 'Edit Customer',
                    onPressed: () async {
                      // Re-read before editing: this sheet may have been open a
                      // while, and a sale or a cloud sync could have moved the
                      // khata balance since. Editing from the stale copy would
                      // write that older balance straight back.
                      final fresh = await LocalDatabase.instance
                          .getCustomerById(customer.id);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _showAddCustomerModal(existing: fresh ?? customer);
                    },
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
                          Text('CURRENT BALANCE DUE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
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
                            ? Uri.encodeComponent('Dear ${customer.name},\n\nYour outstanding balance at KamaiPlus store is ${MoneyFormatter.formatPaise(customer.currentBalancePaise)}. Please clear your balance via UPI or counter.\n\nThank you!')
                            : Uri.encodeComponent('Dear ${customer.name},\n\nGreetings from KamaiPlus Store! Your account is fully settled.\n\nThank you!');
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
                      label: Text('+ Transaction', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
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
        content: Text(
          customer.currentBalancePaise > 0
              // deleteCustomer drops the customer AND every ledger_transactions
              // row in one transaction, so an unpaid udhaar balance and the
              // entire history proving it are destroyed together, with no undo.
              // Say so in terms the merchant can act on, rather than the
              // generic line that used to appear regardless of money owed.
              ? '${customer.name} still owes '
                  '${MoneyFormatter.formatPaise(customer.currentBalancePaise)} in udhaar. '
                  'Deleting them erases that outstanding balance AND the full ledger that proves it. '
                  'This cannot be undone. Settle the khata first if this money is still owed.'
              : 'Are you sure you want to delete ${customer.name}? Their transaction ledger will also be permanently deleted.',
        ),
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
            child: Text(
              customer.currentBalancePaise > 0 ? 'Delete Anyway' : 'Delete',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddKhataEntryDialog(CustomerModel customer) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'debit'; // 'debit' = Payment received (balance decreases), 'credit' = Credit given (balance increases)

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
                      label: const Text('Payment Received'),
                      selected: type == 'debit',
                      onSelected: (_) => setDialogState(() => type = 'debit'),
                      selectedColor: const Color(0xFF10B981),
                      labelStyle: TextStyle(color: type == 'debit' ? Colors.white : Colors.black),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Credit Given'),
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
                  description: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : (type == 'debit' ? 'Payment Received' : 'Credit Given'),
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
                  // Master CRM Header Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.people_alt_rounded, color: Color(0xFF0284C7), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customer Directory & CRM',
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_customers.length} registered buyers • Ledger & Khata records',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showAddCustomerModal,
                          icon: const Icon(Icons.person_add_rounded, size: 15),
                          label: Text('+ Add', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2x2 Metric Ribbon Grid (Matching Product Screen Standard)
                  _buildMetricsGrid(),
                  const SizedBox(height: 14),

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
      bottomNavigationBar: const KamaiBottomNav(activeScreen: 'customers'),
    );
  }

  Widget _buildMetricsGrid() {
    final vipCount = _customers.where((c) => c.isVip).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Tile 1: Total Directory
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.people_alt_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Total Directory',
                  tag: 'CRM',
                  value: '${_customers.length}',
                  valueColor: const Color(0xFF0F172A),
                  subtitle: 'Registered buyers',
                ),
              ),
              Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
              // Tile 2: VIP Club
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'VIP Club',
                  tag: 'Loyal',
                  value: '$vipCount',
                  valueColor: const Color(0xFFD97706),
                  subtitle: 'Priority accounts',
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFF1F5F9), height: 16),
          Row(
            children: [
              // Tile 3: Total Udhar
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: 'Total Credit Due',
                  tag: 'Pending',
                  value: MoneyFormatter.formatPaise(_totalUdharPaise),
                  valueColor: _totalUdharPaise > 0 ? const Color(0xFFEF4444) : const Color(0xFF059669),
                  subtitle: 'Market credit',
                ),
              ),
              Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
              // Tile 4: Due Customers
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.assignment_late_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'Due Customers',
                  tag: 'Collect',
                  value: '$_activeUdharCount',
                  valueColor: const Color(0xFF0F172A),
                  subtitle: 'Pending ledgers',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String tag,
    required String value,
    required Color valueColor,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.inter(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
          ),
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
                      hasDue ? 'Due Balance' : 'All Clear',
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
                    final text = Uri.encodeComponent('Dear ${customer.name}, Greetings from KamaiPlus Store!');
                    final uri = Uri.parse('https://wa.me/$waPhone?text=$text');
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
