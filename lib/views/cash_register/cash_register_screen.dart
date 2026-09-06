import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';

class CashRegisterScreen extends StatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  bool _isDrawerOpen = true;
  final int _openingFloatPaise = 200000; // ₹2,000 default morning float
  int _cashInSalesPaise = 0;
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRegisterData();
  }

  Future<void> _loadRegisterData() async {
    try {
      final now = DateTime.now();
      final allSales = await LocalDatabase.instance.getAllSales(limit: 200);
      final todaySales = allSales.where((s) =>
          s.paymentMethod == 'cash' &&
          s.createdAt.year == now.year &&
          s.createdAt.month == now.month &&
          s.createdAt.day == now.day);
      final cashIn = todaySales.fold(0, (sum, s) => sum + s.totalAmountPaise);

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

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedCategory = 'Tea / Snacks';
    final categories = ['Tea / Snacks', 'Freight / Tempo', 'Cleaning / Store', 'Staff Advance', 'Supplier Pouch', 'Misc'];

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
                  Text(
                    'Record Petty Cash Outflow',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'CATEGORY',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final sel = selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: sel,
                        onSelected: (_) => setModalState(() => selectedCategory = cat),
                        selectedColor: const Color(0xFFEF4444),
                        labelStyle: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : const Color(0xFF64748B),
                        ),
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: BorderSide.none,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Expense Description',
                  hintText: 'e.g. Evening Chai & Biscuits for staff',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (₹) *',
                  hintText: 'e.g. 150',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (amt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid expense amount')),
                      );
                      return;
                    }
                    final exp = ExpenseModel(
                      id: const Uuid().v4(),
                      businessId: 'default_business',
                      title: titleCtrl.text.trim().isEmpty ? selectedCategory : titleCtrl.text.trim(),
                      amountPaise: (amt * 100).round(),
                      category: selectedCategory,
                      createdAt: DateTime.now(),
                    );
                    await LocalDatabase.instance.addExpense(exp);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _loadRegisterData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save Expense (-₹)', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDenominationCalculator() {
    final counts = <int, int>{
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          int countedTotal = 0;
          counts.forEach((denom, count) {
            countedTotal += denom * count;
          });
          final diff = countedTotal - (_expectedCashPaise / 100).round();

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Cash Denomination Counter',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('COUNTED TOTAL', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                          Text('₹${countedTotal.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF10B981))),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('EXPECTED IN DRAWER', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                          Text(MoneyFormatter.formatPaise(_expectedCashPaise), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                          Text(
                            diff == 0 ? '✓ Matched Exactly' : (diff > 0 ? '+₹$diff Excess' : '-₹${diff.abs()} Short'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: diff == 0 ? const Color(0xFF10B981) : (diff > 0 ? const Color(0xFF0EA5E9) : const Color(0xFFEF4444)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: counts.keys.map((denom) {
                      final count = counts[denom]!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text('₹$denom', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: count > 0 ? () => setModalState(() => counts[denom] = count - 1) : null,
                              icon: const Icon(Icons.remove_circle_outline_rounded),
                              color: const Color(0xFF64748B),
                            ),
                            Container(
                              width: 40,
                              alignment: Alignment.center,
                              child: Text('$count', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            IconButton(
                              onPressed: () => setModalState(() => counts[denom] = count + 1),
                              icon: const Icon(Icons.add_circle_outline_rounded),
                              color: const Color(0xFF10B981),
                            ),
                            const Spacer(),
                            Text(
                              '₹${denom * count}',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Confirm Cash Tally', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showZReportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.assessment_rounded, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 10),
            Text('Daily Z-Report Summary', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shift Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
            const SizedBox(height: 14),
            _buildReportRow('Opening Float', MoneyFormatter.formatPaise(_openingFloatPaise)),
            _buildReportRow('Cash Sales Inflow', '+${MoneyFormatter.formatPaise(_cashInSalesPaise)}', color: const Color(0xFF10B981)),
            _buildReportRow('Petty Expenses Outflow', '-${MoneyFormatter.formatPaise(_cashOutExpensesPaise)}', color: const Color(0xFFEF4444)),
            const Divider(height: 16),
            _buildReportRow('Net Expected Cash', MoneyFormatter.formatPaise(_expectedCashPaise), isBold: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Z-Report dispatched to Owner WhatsApp')),
              );
            },
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Send WhatsApp'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569))),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Cash Register & Petty Drawer',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: _loadRegisterData,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  // Top Status Card
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
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.point_of_sale_rounded, color: Color(0xFF10B981), size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cash Register & Petty Cash',
                                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                                  ),
                                  Text(
                                    'Track day opening cash, petty expenses & daily Z-report',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isDrawerOpen ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isDrawerOpen ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                _isDrawerOpen ? 'DRAWER OPEN' : 'CLOSED',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _isDrawerOpen ? const Color(0xFF059669) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _showAddExpenseDialog,
                                icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                                label: Text('- Expense', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFEE2E2),
                                  foregroundColor: const Color(0xFFDC2626),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() => _isDrawerOpen = !_isDrawerOpen);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(_isDrawerOpen ? 'Cash Drawer Opened' : 'Cash Drawer Locked')),
                                  );
                                },
                                icon: Icon(_isDrawerOpen ? Icons.lock_open_rounded : Icons.lock_rounded, size: 16),
                                label: Text(
                                  _isDrawerOpen ? 'Lock Drawer' : 'Open Drawer',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        child: _buildMetricTile(
                          title: 'Opening Float',
                          subtitle: 'Morning Cash',
                          amount: MoneyFormatter.formatPaise(_openingFloatPaise),
                          color: const Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricTile(
                          title: 'Cash In (Sales)',
                          subtitle: 'Today Received',
                          amount: '+${MoneyFormatter.formatPaise(_cashInSalesPaise)}',
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          title: 'Cash Out (Pouch)',
                          subtitle: 'Petty Expenses',
                          amount: '-${MoneyFormatter.formatPaise(_cashOutExpensesPaise)}',
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricTile(
                          title: 'Expected Cash',
                          subtitle: 'Physical In Drawer',
                          amount: MoneyFormatter.formatPaise(_expectedCashPaise),
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quick Tools Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showDenominationCalculator,
                          icon: const Icon(Icons.calculate_rounded, size: 18),
                          label: Text('Count Notes/Coins', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showZReportDialog,
                          icon: const Icon(Icons.summarize_rounded, size: 18),
                          label: Text('Day Z-Report', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFFA7F3D0)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Petty Cash Outflows List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TODAY\'S PETTY OUTFLOWS (${_expenses.length})',
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
                      ),
                      Text(
                        '-${MoneyFormatter.formatPaise(_cashOutExpensesPaise)}',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_expenses.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(Icons.coffee_rounded, size: 36, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('No petty cash expenses recorded today.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                          Text('Use "- Expense" button to record chai, tempo or cleaning bills.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  else
                    ..._expenses.map((exp) {
                      final timeStr = DateFormat('hh:mm a').format(exp.createdAt);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEEF2F6)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFDC2626), size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(exp.title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                                  Text('${exp.category} • $timeStr', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            Text(
                              '-${MoneyFormatter.formatPaise(exp.amountPaise)}',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () async {
                                await LocalDatabase.instance.deleteExpense(exp.id);
                                _loadRegisterData();
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricTile({required String title, required String subtitle, required String amount, required Color color}) {
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
          Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8))),
          const SizedBox(height: 6),
          Text(amount, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
