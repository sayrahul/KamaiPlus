import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InvoiceThemesScreen extends StatefulWidget {
  const InvoiceThemesScreen({super.key});

  @override
  State<InvoiceThemesScreen> createState() => _InvoiceThemesScreenState();
}

class _InvoiceThemesScreenState extends State<InvoiceThemesScreen> {
  int _selectedColorIndex = 0;
  final List<Color> _palette = [
    const Color(0xFF10B981), // Emerald
    const Color(0xFF0284C7), // Blue
    const Color(0xFFD97706), // Amber
    const Color(0xFF7C3AED), // Purple
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF0F172A), // Slate Dark
  ];

  String _selectedHeading = 'TAX INVOICE';
  final List<String> _headings = ['TAX INVOICE', 'RETAIL INVOICE', 'CASH MEMO', 'ESTIMATE / BILL'];

  bool _showLogo = true;
  bool _showTagline = true;
  bool _showPhone = true;
  bool _showUpiQr = true;
  bool _showSignatory = true;
  bool _showGstBreakup = true;
  bool _showMrpSavings = true;

  @override
  Widget build(BuildContext context) {
    final activeColor = _palette[_selectedColorIndex];

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
          'Invoice Themes & Design',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Invoice theme & header options saved!')),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save_rounded, size: 18, color: Color(0xFF10B981)),
            label: Text('Save', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: const Color(0xFF10B981))),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Section 1: Color Picker
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
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('1', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('Select Invoice Theme & Color', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(_palette.length, (idx) {
                    final isSel = _selectedColorIndex == idx;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColorIndex = idx),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _palette[idx],
                          shape: BoxShape.circle,
                          border: isSel ? Border.all(color: Colors.white, width: 3) : null,
                          boxShadow: isSel
                              ? [
                                  BoxShadow(
                                    color: _palette[idx].withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSel ? const Icon(Icons.check_rounded, color: Colors.white, size: 22) : null,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 2: Header & Options
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
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('2', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('Header & Invoice Display Options', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 14),
                Text('DOCUMENT HEADING', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _headings.map((h) {
                    final sel = _selectedHeading == h;
                    return ChoiceChip(
                      label: Text(h),
                      selected: sel,
                      onSelected: (_) => setState(() => _selectedHeading = h),
                      selectedColor: const Color(0xFF0F172A),
                      labelStyle: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : const Color(0xFF475569),
                      ),
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                _buildToggleRow('Show Store Logo', _showLogo, (v) => setState(() => _showLogo = v)),
                _buildToggleRow('Show Shop Tagline', _showTagline, (v) => setState(() => _showTagline = v)),
                _buildToggleRow('Show Owner & WhatsApp Phone', _showPhone, (v) => setState(() => _showPhone = v)),
                _buildToggleRow('Show Dynamic NPCI UPI QR', _showUpiQr, (v) => setState(() => _showUpiQr = v)),
                _buildToggleRow('Show Authorised Signatory', _showSignatory, (v) => setState(() => _showSignatory = v)),
                _buildToggleRow('Show GST Tax Split Breakup', _showGstBreakup, (v) => setState(() => _showGstBreakup = v)),
                _buildToggleRow('Show You Saved (MRP Savings)', _showMrpSavings, (v) => setState(() => _showMrpSavings = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 3: Live Interactive Preview
          Text('LIVE INVOICE PREVIEW', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: activeColor.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header Bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _selectedHeading,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: activeColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('SHARMA KIRANA & GENERAL STORE', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800)),
                if (_showTagline)
                  Text('Shudhata aur Vishwas ka Ekmatra Sthal', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                if (_showPhone)
                  Text('Phone: +91 98765 43210 • GSTIN: 27AAAAA0000A1Z5', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF475569))),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bill #: INV-2026-001', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('Date: 05 Sep 2026', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 12),
                _buildBillItem('Tata Salt (1kg)', '1', '₹28.00'),
                _buildBillItem('Parle-G Biscuit (80g)', '2', '₹20.00'),
                _buildBillItem('Maggi Noodles (70g)', '3', '₹42.00'),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Amount:', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('₹90.00', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: activeColor)),
                  ],
                ),
                if (_showMrpSavings) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
                    child: Text('You saved ₹12.00 on MRP in this bill!', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                  ),
                ],
                if (_showUpiQr) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 48, color: activeColor),
                      const SizedBox(width: 8),
                      Text('Scan to Pay via UPI', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155))),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }

  Widget _buildBillItem(String name, String qty, String price) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name, style: GoogleFonts.inter(fontSize: 11))),
          Text('× $qty', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
          const SizedBox(width: 20),
          Text(price, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
