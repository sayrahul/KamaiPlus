import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/owner_privacy_modal.dart';
import '../common/empty_state_card.dart';
import 'denomination_tally_modal.dart';

class CashRegisterScreen extends StatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  bool _isDrawerOpen = true;
  bool _maskAmounts = false;
  int _openingFloatPaise = 200000; // ₹2,000 default morning float
  int _cashInSalesPaise = 0;
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;
  final String _selectedCategoryFilter = 'All';

  // Denomination notes state for quick tally
  final Map<int, int> _denominations = {
    500: 0,
    200: 0,
    100: 0,
    50: 0,
    20: 0,
    10: 0,
    5: 0,
    2: 0,
    1: 0,
  };

  @override
  void initState() {
    super.initState();
    _loadPersistedSettingsAndData();
  }

  Future<void> _loadPersistedSettingsAndData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFloat = prefs.getInt('cash_register_opening_float_paise');
      final drawerOpen = prefs.getBool('cash_register_is_drawer_open');
      final mask = prefs.getBool('cash_register_mask_amounts');

      if (savedFloat != null) _openingFloatPaise = savedFloat;
      if (drawerOpen != null) _isDrawerOpen = drawerOpen;
      if (mask != null) _maskAmounts = mask;

      await _loadRegisterData();
    } catch (_) {
      await _loadRegisterData();
    }
  }

  Future<void> _loadRegisterData() async {
    try {
      final now = DateTime.now();
      final allSales = await LocalDatabase.instance.getAllSales(limit: 300);
      final todaySales = allSales.where((s) =>
          (s.paymentMethod == 'cash' || (s.paymentMethod == 'split' && s.splitCashPaise > 0)) &&
          s.createdAt.year == now.year &&
          s.createdAt.month == now.month &&
          s.createdAt.day == now.day);
      final cashIn = todaySales.fold(0, (sum, s) {
        if (s.paymentMethod == 'split') {
          return sum + s.splitCashPaise;
        }
        return sum + s.totalAmountPaise;
      });

      final expenses = await LocalDatabase.instance.getAllExpenses();
      final todayExpenses = expenses.where((e) =>
          e.createdAt.year == now.year &&
          e.createdAt.month == now.month &&
          e.createdAt.day == now.day).toList();

      if (mounted) {
        setState(() {
          _cashInSalesPaise = cashIn;
          _expenses = todayExpenses;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _cashOutExpensesPaise => _expenses.fold(0, (sum, e) => sum + e.amountPaise);
  int get _expectedCashPaise => _openingFloatPaise + _cashInSalesPaise - _cashOutExpensesPaise;

  int get _countedTotalPaise {
    int total = 0;
    _denominations.forEach((denom, count) {
      total += denom * count * 100;
    });
    return total;
  }

  Future<void> _toggleMaskAmounts() async {
    HapticFeedback.selectionClick();
    if (_maskAmounts) {
      OwnerPrivacyModal.show(
        context,
        onUnlocked: () async {
          setState(() => _maskAmounts = false);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('cash_register_mask_amounts', false);
        },
      );
    } else {
      setState(() => _maskAmounts = true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cash_register_mask_amounts', true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🔒 Cash drawer register figures masked.'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _toggleDrawerStatus() async {
    HapticFeedback.mediumImpact();
    setState(() => _isDrawerOpen = !_isDrawerOpen);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cash_register_is_drawer_open', _isDrawerOpen);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(_isDrawerOpen ? Icons.lock_open_rounded : Icons.lock_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(_isDrawerOpen ? 'Cash Drawer Shift Opened' : 'Cash Drawer Shift Closed / Locked'),
            ],
          ),
          backgroundColor: _isDrawerOpen ? const Color(0xFF059669) : const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  String _formatAmount(int paise) {
    if (_maskAmounts) return '••••••';
    return MoneyFormatter.formatINR(paise);
  }

  List<ExpenseModel> get _filteredExpenses {
    if (_selectedCategoryFilter == 'All') return _expenses;
    return _expenses.where((e) => e.category == _selectedCategoryFilter).toList();
  }

  // =========================================================================
  // 1. ADD PETTY EXPENSE MODAL (INTERACTIVE CHIPS, RAPID NUMERIC AMOUNTS)
  // =========================================================================
  void _showAddExpenseDialog() {
    HapticFeedback.selectionClick();
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedCat = 'Tea / Snacks';

    final categories = [
      {'label': 'Tea / Snacks', 'emoji': '☕'},
      {'label': 'Packaging', 'emoji': '📦'},
      {'label': 'Cleaning', 'emoji': '🧹'},
      {'label': 'Delivery / Auto', 'emoji': '🛵'},
      {'label': 'Staff Advance', 'emoji': '👤'},
      {'label': 'Misc / Repair', 'emoji': '⚡'},
    ];

    final quickAmounts = [20, 50, 100, 200, 500];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFDC2626), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Record Petty Cash Outflow',
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Category Choice Chips
              Text(
                'CATEGORY',
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.6),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final isSel = selectedCat == cat['label'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Text(cat['emoji']!, style: const TextStyle(fontSize: 13)),
                        label: Text(cat['label']!),
                        selected: isSel,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setModalState(() => selectedCat = cat['label']!);
                        },
                        selectedColor: const Color(0xFFEF4444),
                        labelStyle: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : const Color(0xFF475569),
                        ),
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: BorderSide(
                          color: isSel ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Description input
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'Expense Description',
                  hintText: 'e.g. Chai & biscuits for shop staff',
                  hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.edit_note_rounded, color: Color(0xFF64748B), size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                ),
              ),
              const SizedBox(height: 12),

              // Amount input
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                decoration: InputDecoration(
                  labelText: 'Amount (₹) *',
                  hintText: '0',
                  prefixText: '₹ ',
                  prefixStyle: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),

              // Quick Amount Chips
              Row(
                children: [
                  Text(
                    'QUICK: ',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: quickAmounts.map((q) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text('+₹$q'),
                              labelStyle: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                              backgroundColor: const Color(0xFFF1F5F9),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                final cur = int.tryParse(amountCtrl.text.trim()) ?? 0;
                                amountCtrl.text = (cur + q).toString();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final rawAmt = amountCtrl.text.trim();
                    final amtRupees = int.tryParse(rawAmt) ?? 0;
                    if (amtRupees <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kripya valid expense amount enter karein.')),
                      );
                      return;
                    }
                    HapticFeedback.mediumImpact();

                    final exp = ExpenseModel(
                      id: const Uuid().v4(),
                      businessId: 'biz_default_retail',
                      title: titleCtrl.text.trim().isEmpty ? selectedCat : titleCtrl.text.trim(),
                      amountPaise: amtRupees * 100, // strictly integer paise
                      category: selectedCat,
                      createdAt: DateTime.now(),
                      note: '',
                    );

                    final messenger = ScaffoldMessenger.of(context);
                    await LocalDatabase.instance.addExpense(exp);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    await _loadRegisterData();
                    if (!mounted) return;

                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Petty expense recorded: -₹$amtRupees ($selectedCat)'),
                        backgroundColor: const Color(0xFFDC2626),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },

                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text('Save Expense (-₹)', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 2. SHIFT OPENING FLOAT MODAL
  // =========================================================================
  void _showEditOpeningFloatDialog() {
    HapticFeedback.selectionClick();
    final floatCtrl = TextEditingController(text: (_openingFloatPaise ~/ 100).toString());
    final presets = [1000, 2000, 3000, 5000];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
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
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFF0284C7), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Set Shift Opening Float',
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Subah counter kholte waqt drawer mein kitna starting cash dala gaya hai?',
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: floatCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0284C7)),
                decoration: InputDecoration(
                  labelText: 'Morning Opening Cash (₹)',
                  prefixText: '₹ ',
                  prefixStyle: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0284C7)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: presets.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text('₹$p'),
                      labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                      backgroundColor: const Color(0xFFEFF6FF),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        floatCtrl.text = p.toString();
                      },
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final val = int.tryParse(floatCtrl.text.trim()) ?? 0;
                    if (val < 0) return;
                    HapticFeedback.mediumImpact();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('cash_register_opening_float_paise', val * 100);

                    setState(() => _openingFloatPaise = val * 100);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save Opening Float', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. CASH DENOMINATION TALLY COUNTER
  // =========================================================================
  void _showDenominationCalculator() {
    HapticFeedback.selectionClick();
    DenominationTallyModal.show(
      context,
      expectedCashPaise: _expectedCashPaise,
      initialDenominations: _denominations,
      onSaved: (denoms, totalPaise) {
        setState(() {
          _denominations.clear();
          _denominations.addAll(denoms);
        });
      },
    );
  }

  // =========================================================================
  // 4. DAILY Z-REPORT & CASHIER HANDOVER MODAL
  // =========================================================================
  void _showZReportDialog() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(now);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF059669), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily Shift Z-Report', style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  Text(dateStr, style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildZReportRow('Opening Float', MoneyFormatter.formatINR(_openingFloatPaise)),
              _buildZReportRow('Cash Sales Inflow', '+${MoneyFormatter.formatINR(_cashInSalesPaise)}', color: const Color(0xFF059669)),
              _buildZReportRow('Petty Cash Expenses', '-${MoneyFormatter.formatINR(_cashOutExpensesPaise)}', color: const Color(0xFFDC2626)),
              const Divider(height: 14),
              _buildZReportRow('Expected Cash in Drawer', MoneyFormatter.formatINR(_expectedCashPaise), isBold: true),
              if (_countedTotalPaise > 0) ...[
                const SizedBox(height: 4),
                _buildZReportRow('Physical Counted', MoneyFormatter.formatINR(_countedTotalPaise), color: const Color(0xFF0284C7)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _shareZReportWhatsApp();
            },
            icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
            label: Text('Share WhatsApp', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZReportRow(String label, String val, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569))),
          Text(
            val,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: color ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  void _shareZReportWhatsApp() async {
    final now = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    final message = '''
📊 *KamaiPlus - Cash Drawer Z-Report*
📅 Date: $now
👤 Cashier: Counter 1

🌅 *Opening Float:* ${MoneyFormatter.formatINR(_openingFloatPaise)}
📥 *Cash Sales:* +${MoneyFormatter.formatINR(_cashInSalesPaise)}
📤 *Petty Expenses:* -${MoneyFormatter.formatINR(_cashOutExpensesPaise)}
━━━━━━━━━━━━━━━━━━
💼 *Net Expected Cash:* ${MoneyFormatter.formatINR(_expectedCashPaise)}
━━━━━━━━━━━━━━━━━━
Generated via KamaiPlus Retail POS
''';

    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('whatsapp://send?text=$encoded');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(Uri.parse('https://wa.me/?text=$encoded'), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp open nahi ho saka.')),
        );
      }
    }
  }

  Future<void> _saveCurrentShiftRecord() async {
    final shift = CashRegisterShiftModel(
      id: 'shift_${DateTime.now().millisecondsSinceEpoch}',
      businessId: 'biz_default_retail',
      openingCashPaise: _openingFloatPaise,
      cashSalesPaise: _cashInSalesPaise,
      cashExpensesPaise: _cashOutExpensesPaise,
      expectedClosingPaise: _expectedCashPaise,
      actualClosingPaise: _countedTotalPaise > 0 ? _countedTotalPaise : _expectedCashPaise,
      differencePaise: _countedTotalPaise > 0 ? (_countedTotalPaise - _expectedCashPaise) : 0,
      status: 'closed',
      openedAt: DateTime.now().subtract(const Duration(hours: 8)),
      closedAt: DateTime.now(),
    );
    await LocalDatabase.instance.saveCashRegisterShift(shift);
  }

  void _showShiftHistoryModal() async {
    HapticFeedback.selectionClick();
    List<CashRegisterShiftModel> allShifts = await LocalDatabase.instance.getAllCashRegisterShifts();

    if (!mounted) return;

    DateTime? customDate;
    String selectedFilter = 'All';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final now = DateTime.now();
          final filteredShifts = allShifts.where((s) {
            if (selectedFilter == 'Today') {
              return s.openedAt.year == now.year && s.openedAt.month == now.month && s.openedAt.day == now.day;
            }
            if (selectedFilter == 'Yesterday') {
              final yesterday = now.subtract(const Duration(days: 1));
              return s.openedAt.year == yesterday.year && s.openedAt.month == yesterday.month && s.openedAt.day == yesterday.day;
            }
            if (selectedFilter == '7 Days') {
              return s.openedAt.isAfter(now.subtract(const Duration(days: 7)));
            }
            if (selectedFilter == 'Custom' && customDate != null) {
              return s.openedAt.year == customDate!.year && s.openedAt.month == customDate!.month && s.openedAt.day == customDate!.day;
            }
            return true;
          }).toList();

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.history_rounded, color: Color(0xFF0284C7), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text('Past Shift Z-Reports', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),

                // Date Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...['All', 'Today', 'Yesterday', '7 Days'].map((f) {
                        final isSel = selectedFilter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f),
                            selected: isSel,
                            selectedColor: const Color(0xFF0F172A),
                            labelStyle: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: isSel ? Colors.white : const Color(0xFF475569)),
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: BorderSide.none,
                            onSelected: (_) => setModalState(() => selectedFilter = f),
                          ),
                        );
                      }),
                      ChoiceChip(
                        label: Text(customDate != null ? DateFormat('d MMM (E)').format(customDate!) : 'Pick Date 📅'),
                        selected: selectedFilter == 'Custom',
                        selectedColor: const Color(0xFF0F172A),
                        labelStyle: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: selectedFilter == 'Custom' ? Colors.white : const Color(0xFF475569)),
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: BorderSide.none,
                        onSelected: (_) async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: customDate ?? DateTime.now(),
                            firstDate: DateTime(2025),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() {
                              customDate = picked;
                              selectedFilter = 'Custom';
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // List of Past Shifts
                Expanded(
                  child: filteredShifts.isEmpty
                      ? EmptyStateCard(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'No Past Shifts Found',
                          description: 'Jab aap Z-report generate karenge, shifts yahan automatically archive hongi.',
                          actionText: 'Save Current Shift as Z-Report',
                          onAction: () async {
                            Navigator.pop(ctx);
                            await _saveCurrentShiftRecord();
                            _showZReportDialog();
                          },
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: filteredShifts.length,
                          itemBuilder: (context, i) {
                            final s = filteredShifts[i];
                            final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(s.openedAt);
                            final isMatched = s.differencePaise == 0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFEEF2F6)),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x050F172A), blurRadius: 4, offset: Offset(0, 1.5)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(dateStr, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isMatched ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isMatched ? '✓ Matched' : (s.differencePaise > 0 ? '+${MoneyFormatter.formatINR(s.differencePaise)} Excess' : '-${MoneyFormatter.formatINR(s.differencePaise.abs())} Short'),
                                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: isMatched ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Opening Float: ${MoneyFormatter.formatINR(s.openingCashPaise)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                      Text('Sales: +${MoneyFormatter.formatINR(s.cashSalesPaise)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF059669))),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Expenses: -${MoneyFormatter.formatINR(s.cashExpensesPaise)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFDC2626))),
                                      Text('Closing: ${MoneyFormatter.formatINR(s.actualClosingPaise)}', style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // BUILD SCREEN
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cash Register',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Shift Drawer & Petty Expenses',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          // Quick Note Tally Action
          IconButton(
            tooltip: 'Count Notes & Coins',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.calculate_rounded, size: 18, color: Color(0xFF0F172A)),
            ),
            onPressed: _showDenominationCalculator,
          ),
          // Z-Report Summary
          IconButton(
            tooltip: 'Z-Report Summary',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF059669)),
            ),
            onPressed: _showZReportDialog,
          ),
          // Shift History
          IconButton(
            tooltip: 'Past Shift History',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF0284C7)),
            ),
            onPressed: _showShiftHistoryModal,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _loadRegisterData,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  // 1. HERO DRAWER STATUS BANNER (DARK GRADIENT, COMPACT, HIGH CONTRAST)
                  _buildHeroDrawerBanner(),
                  const SizedBox(height: 12),

                  // 2. 4-METRIC MICRO GRID (SPACE SAVING & RESPONSIVE)
                  _buildMetricGrid(),
                  const SizedBox(height: 14),

                  // 3. QUICK SHORTCUT BAR
                  _buildQuickActionBar(),
                  const SizedBox(height: 16),

                  // 4. TODAY'S PETTY EXPENSES SECTION HEADER
                  _buildExpensesHeader(),
                  const SizedBox(height: 10),

                  // 5. EXPENSES LIST
                  if (_filteredExpenses.isEmpty)
                    _buildEmptyExpensesState()
                  else
                    ..._filteredExpenses.map((exp) => _buildExpenseCard(exp)),
                ],
              ),
            ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  // =========================================================================
  // HERO DRAWER BANNER
  // =========================================================================
  Widget _buildHeroDrawerBanner() {
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
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: Status pill & Eye toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isDrawerOpen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isDrawerOpen ? 'SHIFT ACTIVE • COUNTER 1' : 'DRAWER LOCKED / CLOSED',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: _isDrawerOpen ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _toggleMaskAmounts,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        _maskAmounts ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: const Color(0xFF94A3B8),
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _maskAmounts ? 'Hidden' : 'Hide',
                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Balance Display
          Text(
            'EXPECTED CASH IN DRAWER',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _formatAmount(_expectedCashPaise),
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),

          // Primary Actions in Banner
          Row(
            children: [
              // + Expense Button
              Expanded(
                child: GestureDetector(
                  onTap: _showAddExpenseDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '+ Outflow (-₹)',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Drawer Lock / Open Toggle
              Expanded(
                child: GestureDetector(
                  onTap: _toggleDrawerStatus,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF475569)),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_isDrawerOpen ? Icons.lock_outline_rounded : Icons.lock_open_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _isDrawerOpen ? 'Lock Drawer' : 'Open Shift',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
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
    );
  }

  // =========================================================================
  // 4-METRIC MICRO GRID
  // =========================================================================
  Widget _buildMetricGrid() {
    return Row(
      children: [
        // Left Column: Opening Float & Cash Out
        Expanded(
          child: Column(
            children: [
              _buildMicroMetricCard(
                title: 'Opening Float',
                amount: _formatAmount(_openingFloatPaise),
                tag: 'Morning Base',
                tagColor: const Color(0xFF0284C7),
                icon: Icons.wb_sunny_rounded,
                onTap: _showEditOpeningFloatDialog,
              ),
              const SizedBox(height: 8),
              _buildMicroMetricCard(
                title: 'Petty Outflow',
                amount: '-${_formatAmount(_cashOutExpensesPaise)}',
                tag: '${_expenses.length} expenses',
                tagColor: const Color(0xFFDC2626),
                icon: Icons.coffee_rounded,
                onTap: _showAddExpenseDialog,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Right Column: Cash In & Expected Net
        Expanded(
          child: Column(
            children: [
              _buildMicroMetricCard(
                title: 'Cash Sales',
                amount: '+${_formatAmount(_cashInSalesPaise)}',
                tag: 'From POS Bills',
                tagColor: const Color(0xFF059669),
                icon: Icons.point_of_sale_rounded,
              ),
              const SizedBox(height: 8),
              _buildMicroMetricCard(
                title: 'Expected Cash',
                amount: _formatAmount(_expectedCashPaise),
                tag: 'In Physical Till',
                tagColor: const Color(0xFF0F172A),
                icon: Icons.account_balance_wallet_rounded,
                isHighlighted: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMicroMetricCard({
    required String title,
    required String amount,
    required String tag,
    required Color tagColor,
    required IconData icon,
    bool isHighlighted = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? const Color(0xFF0F172A) : const Color(0xFFEEF2F6),
            width: isHighlighted ? 1.2 : 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x050F172A),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: tagColor),
                    const SizedBox(width: 4),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                if (onTap != null)
                  const Icon(Icons.edit_outlined, size: 12, color: Color(0xFF94A3B8)),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: GoogleFonts.outfit(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: tagColor,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tag,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // QUICK ACTION BAR
  // =========================================================================
  Widget _buildQuickActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Notes Tally shortcut
          InkWell(
            onTap: _showDenominationCalculator,
            child: Row(
              children: [
                const Icon(Icons.calculate_rounded, size: 15, color: Color(0xFF0284C7)),
                const SizedBox(width: 4),
                Text(
                  _countedTotalPaise > 0
                      ? 'Count: ${MoneyFormatter.formatINR(_countedTotalPaise)}'
                      : 'Count Till',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
          // Z-Report shortcut
          InkWell(
            onTap: _showZReportDialog,
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, size: 15, color: Color(0xFF059669)),
                const SizedBox(width: 4),
                Text(
                  'Z-Report',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
          // Shift History shortcut
          InkWell(
            onTap: _showShiftHistoryModal,
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 15, color: Color(0xFF7C3AED)),
                const SizedBox(width: 4),
                Text(
                  'Past Shifts',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF7C3AED)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // EXPENSES SECTION HEADER
  // =========================================================================
  Widget _buildExpensesHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              'PETTY OUTFLOWS (${_filteredExpenses.length})',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        Text(
          '-${_formatAmount(_cashOutExpensesPaise)}',
          style: GoogleFonts.outfit(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // EXPENSE CARD
  // =========================================================================
  Widget _buildExpenseCard(ExpenseModel exp) {
    final timeStr = DateFormat('hh:mm a').format(exp.createdAt);

    IconData catIcon = Icons.coffee_rounded;
    Color iconColor = const Color(0xFFD97706);
    Color iconBg = const Color(0xFFFEF3C7);

    if (exp.category.contains('Packaging')) {
      catIcon = Icons.inventory_2_rounded;
      iconColor = const Color(0xFF0284C7);
      iconBg = const Color(0xFFE0F2FE);
    } else if (exp.category.contains('Cleaning')) {
      catIcon = Icons.cleaning_services_rounded;
      iconColor = const Color(0xFF059669);
      iconBg = const Color(0xFFD1FAE5);
    } else if (exp.category.contains('Delivery') || exp.category.contains('Tempo')) {
      catIcon = Icons.local_shipping_rounded;
      iconColor = const Color(0xFF7C3AED);
      iconBg = const Color(0xFFEDE9FE);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(catIcon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exp.title,
                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${exp.category} • $timeStr',
                  style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-${_formatAmount(exp.amountPaise)}',
            style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () async {
              HapticFeedback.lightImpact();
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text('Delete Expense?', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
                  content: Text('Kya aap iss expense (-${MoneyFormatter.formatINR(exp.amountPaise)}) ko cancel karna chahte hain?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await LocalDatabase.instance.deleteExpense(exp.id);
                _loadRegisterData();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // EMPTY EXPENSES STATE
  // =========================================================================
  Widget _buildEmptyExpensesState() {
    return EmptyStateCard(
      icon: Icons.coffee_rounded,
      iconColor: const Color(0xFFDC2626),
      iconBgColor: const Color(0xFFFEE2E2),
      title: 'No Petty Cash Outflow Today',
      description: 'Chai, tempo, ya carry bag kharche ke liye "+ Outflow" tap karke hisaab darj karein.',
      actionText: '+ Record Outflow',
      onAction: _showAddExpenseDialog,
    );
  }
}
