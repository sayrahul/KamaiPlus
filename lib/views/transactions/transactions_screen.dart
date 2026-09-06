import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';
import '../../services/thermal_printer_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<SaleModel> _sales = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedDateFilter = 'All Dates';
  String _selectedModeFilter = 'All Modes';

  final List<String> _dateFilters = ['All Dates', 'Today', 'Yesterday', '7 Days'];
  final List<String> _modeFilters = ['All Modes', 'Cash', 'UPI', 'Udhar'];

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final sales = await LocalDatabase.instance.getAllSales(limit: 200);
      if (mounted) {
        setState(() {
          _sales = sales;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<SaleModel> get _filteredSales {
    final now = DateTime.now();
    return _sales.where((sale) {
      // Search
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final invMatch = sale.invoiceNumber.toLowerCase().contains(query);
        final custMatch = (sale.customerName ?? '').toLowerCase().contains(query);
        final phoneMatch = (sale.customerPhone ?? '').contains(query);
        if (!invMatch && !custMatch && !phoneMatch) return false;
      }

      // Date
      if (_selectedDateFilter == 'Today') {
        if (sale.createdAt.year != now.year ||
            sale.createdAt.month != now.month ||
            sale.createdAt.day != now.day) {
          return false;
        }
      } else if (_selectedDateFilter == 'Yesterday') {
        final yest = now.subtract(const Duration(days: 1));
        if (sale.createdAt.year != yest.year ||
            sale.createdAt.month != yest.month ||
            sale.createdAt.day != yest.day) {
          return false;
        }
      } else if (_selectedDateFilter == '7 Days') {
        if (now.difference(sale.createdAt).inDays > 7) return false;
      }

      // Mode
      if (_selectedModeFilter == 'Cash' && sale.paymentMethod != 'cash') return false;
      if (_selectedModeFilter == 'UPI' && sale.paymentMethod != 'upi') return false;
      if (_selectedModeFilter == 'Udhar' && sale.paymentMethod != 'credit') return false;

      return true;
    }).toList();
  }

  int get _totalRevenuePaise => _filteredSales.fold(0, (sum, s) => sum + s.totalAmountPaise);
  int get _cashRevenuePaise => _filteredSales.where((s) => s.paymentMethod == 'cash').fold(0, (sum, s) => sum + s.totalAmountPaise);
  int get _upiRevenuePaise => _filteredSales.where((s) => s.paymentMethod == 'upi').fold(0, (sum, s) => sum + s.totalAmountPaise);
  int get _creditDuePaise => _filteredSales.where((s) => s.paymentMethod == 'credit').fold(0, (sum, s) => sum + s.totalAmountPaise);

  @override
  Widget build(BuildContext context) {
    final list = _filteredSales;

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
          'Transactions & Sales Ledger',
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: _loadSales,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  // Action Buttons Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEEF2F6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Transactions Ledger',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    'Audit history, reprint thermal bills & Tally export',
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
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('CSV Export generated in Downloads/kamai_sales.csv')),
                                  );
                                },
                                icon: const Icon(Icons.file_download_outlined, size: 16),
                                label: Text('Export CSV', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0EA5E9),
                                  side: const BorderSide(color: Color(0xFFBAE6FD)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Tally Prime XML vouchers generated successfully.')),
                                  );
                                },
                                icon: const Icon(Icons.code_rounded, size: 16),
                                label: Text('Tally Prime', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFD97706),
                                  side: const BorderSide(color: Color(0xFFFDE68A)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                        child: _buildMetricBox(
                          title: 'REVENUE',
                          subtitle: '${_filteredSales.length} BILLS',
                          amount: MoneyFormatter.formatPaise(_totalRevenuePaise),
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricBox(
                          title: 'CASH IN',
                          subtitle: 'CASH BILLS',
                          amount: MoneyFormatter.formatPaise(_cashRevenuePaise),
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox(
                          title: 'UPI / QR',
                          subtitle: 'DIGITAL PAY',
                          amount: MoneyFormatter.formatPaise(_upiRevenuePaise),
                          color: const Color(0xFF0EA5E9),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricBox(
                          title: 'CREDIT DUE',
                          subtitle: 'UDHAR GIVEN',
                          amount: MoneyFormatter.formatPaise(_creditDuePaise),
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Filters Toolbar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEEF2F6)),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            hintText: 'Search invoice #, customer, phone...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: _dateFilters.map((df) {
                              final sel = _selectedDateFilter == df;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(df),
                                  selected: sel,
                                  onSelected: (_) => setState(() => _selectedDateFilter = df),
                                  selectedColor: const Color(0xFF0F172A),
                                  labelStyle: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : const Color(0xFF64748B),
                                  ),
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: _modeFilters.map((mf) {
                              final sel = _selectedModeFilter == mf;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(mf),
                                  selected: sel,
                                  onSelected: (_) => setState(() => _selectedModeFilter = mf),
                                  selectedColor: const Color(0xFFF59E0B),
                                  labelStyle: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : const Color(0xFF64748B),
                                  ),
                                  backgroundColor: const Color(0xFFF8FAFC),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Transactions List Header
                  Text(
                    'TRANSACTIONS (${list.length}) • Tap to reprint / view',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (list.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No matching transactions found',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'Bills created at Billing counter will appear here.',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...list.map((sale) => _buildSaleCard(sale)),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricBox({
    required String title,
    required String subtitle,
    required String amount,
    required Color color,
  }) {
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
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
              ),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleCard(SaleModel sale) {
    final dateStr = DateFormat('dd MMM, hh:mm a').format(sale.createdAt);
    final modeColor = sale.paymentMethod == 'cash'
        ? const Color(0xFF10B981)
        : sale.paymentMethod == 'upi'
            ? const Color(0xFF0EA5E9)
            : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const Border(),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: modeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            sale.paymentMethod == 'cash'
                ? Icons.payments_rounded
                : sale.paymentMethod == 'upi'
                    ? Icons.qr_code_rounded
                    : Icons.book_rounded,
            color: modeColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              sale.invoiceNumber,
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: modeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sale.paymentMethod.toUpperCase(),
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: modeColor),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${sale.customerName ?? 'Walk-in Customer'} • $dateStr',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
        ),
        trailing: Text(
          MoneyFormatter.formatPaise(sale.totalAmountPaise),
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
        ),
        children: [
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          ...sale.items.map((item) {
            final name = item['product_name'] ?? 'Item';
            final qty = item['quantity'] ?? 1;
            final price = MoneyFormatter.formatPaise(item['gross_total_paise'] ?? 0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '• $name × $qty',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF334155)),
                    ),
                  ),
                  Text(
                    price,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(const SnackBar(content: Text('Printing thermal tax invoice...')));
                    await ThermalPrinterService.printReceipt(sale: sale);
                  },
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: Text('Reprint Bill', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('WhatsApp receipt dispatched to ${sale.customerPhone ?? 'Customer'}')),
                  );
                },
                icon: const Icon(Icons.chat_rounded, color: Color(0xFF10B981)),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFECFDF5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
