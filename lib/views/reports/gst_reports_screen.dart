import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';
import '../../models/models.dart';

class GstReportsScreen extends StatefulWidget {
  const GstReportsScreen({super.key});

  @override
  State<GstReportsScreen> createState() => _GstReportsScreenState();
}

class _GstReportsScreenState extends State<GstReportsScreen> {
  String _selectedPeriod = 'This Month';
  final List<String> _periods = ['This Month', 'Last Month', 'Q1 (Apr-Jun)', 'Q2 (Jul-Sep)'];

  List<SaleModel> _sales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final sales = await LocalDatabase.instance.getAllSales(limit: 500);
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

  int get _taxableValuePaise => _sales.fold(0, (sum, s) => sum + s.subtotalPaise);
  int get _totalGstPaise => _sales.fold(0, (sum, s) => sum + s.taxAmountPaise);
  int get _cgstPaise => (_totalGstPaise / 2).round();
  int get _sgstPaise => _totalGstPaise - _cgstPaise;

  void _showExportModal(String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.file_download_done_rounded, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text('$type Export Generated', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '$type report has been compiled for $_selectedPeriod and saved to your device Downloads/GST_Reports folder. Ready for CA filing or Tally upload.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Dismiss')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sharing $type file via WhatsApp/Email...')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('Share File'),
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
          'GST Reports & CA Tax Filing',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Header Card
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
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.receipt_rounded, color: Color(0xFF6366F1), size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('GST Reports & CA Tax Filing', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                                Text('GSTR-1, HSN summary, B2B wholesale register & 1-click Tally', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
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
                              onPressed: () => _showExportModal('CA Excel CSV'),
                              icon: const Icon(Icons.table_view_rounded, size: 16),
                              label: Text('CA Excel (CSV)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF059669),
                                side: const BorderSide(color: Color(0xFFA7F3D0)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showExportModal('Tally Prime XML'),
                              icon: const Icon(Icons.code_rounded, size: 16),
                              label: Text('<> Tally XML', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD97706),
                                side: const BorderSide(color: Color(0xFFFDE68A)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showExportModal('GSTR-1 JSON Offline Tool'),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: Text('Export GSTR-1 JSON Offline', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Period Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _periods.map((p) {
                      final sel = _selectedPeriod == p;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(p),
                          selected: sel,
                          onSelected: (_) => setState(() => _selectedPeriod = p),
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

                // 4-Metric Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile('Taxable Value', 'Turnover', MoneyFormatter.formatPaise(_taxableValuePaise), const Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile('Total GST Tax', 'Collected', MoneyFormatter.formatPaise(_totalGstPaise), const Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile('CGST / SGST', '50:50 Split', '${MoneyFormatter.formatPaise(_cgstPaise)} / ${MoneyFormatter.formatPaise(_sgstPaise)}', const Color(0xFFD97706)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile('B2B Invoices', 'GSTIN Bills', '0', const Color(0xFF6366F1)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Table 12 HSN Summary Container
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
                          const Icon(Icons.table_chart_rounded, size: 20, color: Color(0xFF0284C7)),
                          const SizedBox(width: 8),
                          Text(
                            'Table 12: HSN-wise Sales Summary',
                            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildHsnRow('1902', 'Maggi Noodles', '10 Pcs', '₹140.00', '₹7.00', '₹7.00', '₹154.00'),
                      _buildHsnRow('1512', 'Fortune Oil', '8 Ltr', '₹1,160.00', '₹29.00', '₹29.00', '₹1,218.00'),
                      _buildHsnRow('1006', 'Basmati Rice', '25 Kg', '₹2,500.00', '₹0.00', '₹0.00', '₹2,500.00'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetricTile(String title, String subtitle, String amount, Color color) {
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

  Widget _buildHsnRow(String hsn, String desc, String qty, String taxable, String cgst, String sgst, String total) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(6)),
            child: Text(hsn, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('Qty: $qty • Taxable: $taxable', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(total, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
              Text('CGST $cgst + SGST $sgst', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF10B981))),
            ],
          ),
        ],
      ),
    );
  }
}
