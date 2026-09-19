import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/local_database.dart';
import '../models/models.dart';
import '../models/report_models.dart';

/// Store details printed at the top of every Advanced Report PDF.
class ReportLetterhead {
  final String storeName;
  final String phone;
  final String address;
  final String gstin;

  /// The merchant's invoice theme colour (`invoice_theme_color_hex`).
  final PdfColor accent;

  const ReportLetterhead({
    required this.storeName,
    this.phone = '',
    this.address = '',
    this.gstin = '',
    this.accent = const PdfColor.fromInt(0xFF0284C7),
  });
}

/// PDFs for the Advanced Sales Reports screen: the full period report
/// (owner-facing) and a per-customer account statement (customer-facing).
///
/// Built with the pure-Dart `pdf`/`printing` packages, like
/// `UpiStandeePdfService`. The built-in Helvetica font only covers Latin-1:
/// ANY character above U+00FF — the rupee sign, a bullet, an en dash, a Hindi
/// product name — throws "Unable to display U+..." and kills the export. So
/// every string that reaches the page goes through [pdfSafe], and money is
/// printed as "Rs." rather than "₹".
///
/// The customer statement never shows cost or profit — it is sent to the
/// customer. The period report shows profit only when the caller passes
/// `includeProfit` (the screen does so after the owner PIN is entered).
class AdvancedReportPdfService {
  static const _kSlate900 = PdfColor.fromInt(0xFF0F172A);
  static const _kSlate500 = PdfColor.fromInt(0xFF64748B);
  static const _kSlate200 = PdfColor.fromInt(0xFFE2E8F0);
  static const _kSlate50 = PdfColor.fromInt(0xFFF8FAFC);
  static const _kOrange = PdfColor.fromInt(0xFFC2410C);

  static final NumberFormat _money = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 2);
  static final DateFormat _dateFmt = DateFormat('dd MMM yy', 'en_US');
  static final DateFormat _stampFmt = DateFormat('d MMM yyyy, hh:mm a', 'en_US');

  // ---------------------------------------------------------------------------
  // Text helpers
  // ---------------------------------------------------------------------------

  /// Makes [input] printable with the built-in Latin-1 PDF fonts. Common
  /// typographic characters get ASCII stand-ins; anything else outside
  /// Latin-1 becomes "?". Returns [fallback] when nothing readable is left
  /// (e.g. a product name written entirely in Devanagari).
  static String pdfSafe(String? input, {String fallback = ''}) {
    if (input == null) return fallback;
    final s = input
        .replaceAll('\u20B9', 'Rs.') // rupee sign
        .replaceAll(RegExp('[\u2018\u2019\u201A\u2032]'), "'") // curly single quotes, prime
        .replaceAll(RegExp('[\u201C\u201D\u201E\u2033]'), '"') // curly double quotes
        .replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-') // hyphens, en/em dash, minus
        .replaceAll(RegExp('[\u2022\u00B7\u25CF]'), '-') // bullets
        .replaceAll('\u2026', '...') // ellipsis
        .replaceAll('\u00D7', 'x'); // multiplication sign
    final out = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x0A || (r >= 0x20 && r <= 0x7E) || (r >= 0xA0 && r <= 0xFF)) {
        out.writeCharCode(r);
      } else if (r == 0x09) {
        out.write(' ');
      } else {
        out.write('?');
      }
    }
    final cleaned = out.toString().replaceAll(RegExp(r'\?{2,}'), '?').trim();
    return RegExp(r'[A-Za-z0-9]').hasMatch(cleaned) ? cleaned : fallback;
  }

  static String rs(int paise) => pdfSafe(_money.format(paise / 100));

  static String qty(double q) => formatReportQty(q);

  static String _pct(double v) => '${v.toStringAsFixed(1)}%';

  static String _fileSafe(String s, String fallback) {
    final f = s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return f.isEmpty ? fallback : f;
  }

  // ---------------------------------------------------------------------------
  // Share entry points used by the screens
  // ---------------------------------------------------------------------------

  static Future<ReportLetterhead> loadLetterhead() async {
    final profile = await LocalDatabase.instance.getStoreProfile();
    var accent = const PdfColor.fromInt(0xFF0284C7);
    try {
      final prefs = await SharedPreferences.getInstance();
      final hex = (prefs.getString('invoice_theme_color_hex') ?? '').replaceAll('#', '');
      if (hex.length == 6) accent = PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));
    } catch (_) {}
    return ReportLetterhead(
      storeName: profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Store',
      phone: profile.phone,
      address: profile.address,
      gstin: profile.gstin,
      accent: accent,
    );
  }

  static Future<void> shareGeneralReportPdf(
    AdvancedReportsData data,
    String periodLabel, {
    required DateTime start,
    required DateTime end,
    bool includeProfit = false,
  }) async {
    final letterhead = await loadLetterhead();
    final bytes = await buildGeneralReport(
      data: data,
      periodLabel: periodLabel,
      dateSpan: ReportPeriod.spanText(start, end, locale: 'en_US'),
      letterhead: letterhead,
      includeProfit: includeProfit,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Sales_Report_${_fileSafe(periodLabel, 'Period')}_${DateFormat('yyyyMMdd', 'en_US').format(start)}.pdf',
    );
  }

  static Future<void> sharePartyReportPdf(
    PartySalesSummary party,
    List<SaleModel> invoices,
    String periodLabel, {
    required DateTime start,
    required DateTime end,
  }) async {
    final letterhead = await loadLetterhead();
    final bytes = await buildPartyStatement(
      party: party,
      invoices: invoices,
      periodLabel: periodLabel,
      dateSpan: ReportPeriod.spanText(start, end, locale: 'en_US'),
      letterhead: letterhead,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Statement_${_fileSafe(party.partyName, 'Customer')}_${_fileSafe(periodLabel, 'Period')}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // Document builders (pure — no database or platform calls)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> buildGeneralReport({
    required AdvancedReportsData data,
    required String periodLabel,
    required String dateSpan,
    required ReportLetterhead letterhead,
    bool includeProfit = false,
    DateTime? generatedAt,
  }) {
    final ps = data.paymentSummary;
    final parties = [...data.partyData]..sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));
    final categories = [...data.categoryData]..sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));
    final items = data.soldItems..sort((a, b) => b.totalSalesPaise.compareTo(a.totalSalesPaise));
    final dead = data.deadStockItems..sort((a, b) => a.itemName.compareTo(b.itemName));

    final kpis = <_Kpi>[
      _Kpi('Total Revenue', rs(ps.totalPaise)),
      _Kpi('Cash', rs(ps.totalCashPaise)),
      _Kpi('UPI', rs(ps.totalUpiPaise)),
      _Kpi('Udhar (Credit)', rs(ps.totalCreditPaise), color: ps.totalCreditPaise > 0 ? _kOrange : null),
      if (includeProfit)
        _Kpi(
          data.isProfitPartial ? 'Est. Profit (partial)' : 'Est. Gross Profit',
          '${rs(data.totalProfitPaise)}  (${_pct(data.marginPercent)})',
        ),
    ];

    return _document(
      title: 'SALES ANALYTICS REPORT',
      letterhead: letterhead,
      periodLabel: periodLabel,
      dateSpan: dateSpan,
      generatedAt: generatedAt,
      body: [
        _kpiRibbon(kpis, letterhead.accent),
        if (includeProfit && data.isProfitPartial)
          _note('Profit covers only items with a buying price. ${data.uncostedLineCount} sold line(s) had no '
              'buying price and are left out of the margin.'),
        _section('Party-wise Sales (${parties.length})', letterhead.accent),
        if (parties.isEmpty)
          _note('No sales in this period.')
        else
          _table(
            accent: letterhead.accent,
            headers: ['#', 'Customer', 'Phone', 'Bills', 'Sales', 'Udhar', if (includeProfit) 'Profit'],
            numericFrom: 3,
            flexColumn: 1,
            rows: [
              for (var i = 0; i < parties.length; i++)
                [
                  '${i + 1}',
                  pdfSafe(parties[i].partyName, fallback: 'Customer'),
                  pdfSafe(parties[i].partyPhone, fallback: '-'),
                  '${parties[i].invoiceCount}',
                  rs(parties[i].totalSalesPaise),
                  parties[i].creditPaise > 0 ? rs(parties[i].creditPaise) : '-',
                  if (includeProfit) rs(parties[i].totalProfitPaise),
                ],
            ],
          ),
        _section('Category-wise Sales (${categories.length})', letterhead.accent),
        if (categories.isEmpty)
          _note('No items sold in this period.')
        else
          _table(
            accent: letterhead.accent,
            headers: ['#', 'Category', 'Qty Sold', 'Sales', if (includeProfit) 'Profit', if (includeProfit) 'Margin'],
            numericFrom: 2,
            flexColumn: 1,
            rows: [
              for (var i = 0; i < categories.length; i++)
                [
                  '${i + 1}',
                  pdfSafe(categories[i].categoryName, fallback: 'Category'),
                  qty(categories[i].quantitySold),
                  rs(categories[i].totalSalesPaise),
                  if (includeProfit) rs(categories[i].totalProfitPaise),
                  if (includeProfit) _pct(categories[i].marginPercent),
                ],
            ],
          ),
        _section('Item-wise Sales (${items.length})', letterhead.accent),
        if (items.isEmpty)
          _note('No items sold in this period.')
        else
          _table(
            accent: letterhead.accent,
            headers: ['#', 'Item', 'Category', 'Qty', 'Sales', if (includeProfit) 'Profit'],
            numericFrom: 3,
            flexColumn: 1,
            rows: [
              for (var i = 0; i < items.length; i++)
                [
                  '${i + 1}',
                  pdfSafe(items[i].itemName, fallback: 'Item'),
                  pdfSafe(items[i].categoryName, fallback: '-'),
                  qty(items[i].quantitySold),
                  rs(items[i].totalSalesPaise),
                  if (includeProfit) rs(items[i].totalProfitPaise),
                ],
            ],
          ),
        _section('Dead Stock - in stock, 0 sold (${dead.length})', letterhead.accent),
        if (dead.isEmpty)
          _note('Every in-stock item sold at least once in this period.')
        else
          _table(
            accent: letterhead.accent,
            headers: ['#', 'Item', 'Category', 'In Stock'],
            numericFrom: 3,
            flexColumn: 1,
            rows: [
              for (var i = 0; i < dead.length; i++)
                [
                  '${i + 1}',
                  pdfSafe(dead[i].itemName, fallback: 'Item'),
                  pdfSafe(dead[i].categoryName, fallback: '-'),
                  '${qty(dead[i].stockQuantity)} ${pdfSafe(dead[i].unit)}'.trim(),
                ],
            ],
          ),
      ],
    );
  }

  static Future<Uint8List> buildPartyStatement({
    required PartySalesSummary party,
    required List<SaleModel> invoices,
    required String periodLabel,
    required String dateSpan,
    required ReportLetterhead letterhead,
    DateTime? generatedAt,
  }) {
    final bills = invoices.where((s) => !s.isRefunded).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final billed = bills.fold<int>(0, (s, b) => s + b.netAmountPaise);
    final udhar = bills.fold<int>(0, (s, b) => s + b.netCreditAmountPaise);

    final rows = <List<String>>[];
    final totalRows = <int>{};
    var serial = 0;
    for (final bill in bills) {
      var first = true;
      for (final it in bill.items) {
        final sold = ((it['quantity'] ?? it['qty'] ?? 1) as num?)?.toDouble() ?? 1;
        final returned = ((it['returned_quantity'] ?? 0) as num?)?.toDouble() ?? 0;
        final kept = (sold - returned).clamp(0.0, sold).toDouble();
        if (kept <= 0) continue;
        final num gross = (it['gross_total_paise'] as num?) ??
            ((it['unit_price_paise'] ?? it['price_paise'] ?? 0) as num) * sold;
        final amount = kept == sold ? gross.round() : (gross * kept / sold).round();
        final rate = ((it['unit_price_paise'] ?? it['price_paise'] ?? 0) as num).round();
        var name = pdfSafe((it['product_name'] ?? it['name'])?.toString(), fallback: 'Item');
        if (returned > 0) name = '$name (returned ${qty(returned)})';
        serial++;
        rows.add([
          '$serial',
          first ? _dateFmt.format(bill.createdAt) : '',
          first ? pdfSafe(bill.invoiceNumber, fallback: '-') : '',
          name,
          qty(kept),
          rate > 0 ? rs(rate) : '-',
          rs(amount),
        ]);
        first = false;
      }
      totalRows.add(rows.length);
      rows.add([
        '',
        first ? _dateFmt.format(bill.createdAt) : '',
        first ? pdfSafe(bill.invoiceNumber, fallback: '-') : '',
        'Bill total incl. tax & discount - ${_modeLabel(bill)}',
        '',
        '',
        rs(bill.netAmountPaise),
      ]);
    }

    return _document(
      title: 'ACCOUNT STATEMENT',
      letterhead: letterhead,
      periodLabel: periodLabel,
      dateSpan: dateSpan,
      generatedAt: generatedAt,
      body: [
        _billedTo(party, periodLabel, dateSpan),
        pw.SizedBox(height: 10),
        _kpiRibbon([
          _Kpi('Bills', '${bills.length}'),
          _Kpi('Total Billed', rs(billed)),
          _Kpi('Paid', rs(billed - udhar)),
          _Kpi('Udhar (Credit)', rs(udhar), color: udhar > 0 ? _kOrange : null),
        ], letterhead.accent),
        _section('Itemised Bills', letterhead.accent),
        if (rows.isEmpty)
          _note('No bills for this customer in the selected period.')
        else
          _table(
            accent: letterhead.accent,
            headers: ['#', 'Date', 'Invoice', 'Particulars', 'Qty', 'Rate', 'Amount'],
            numericFrom: 4,
            flexColumn: 3,
            rows: rows,
            boldRows: totalRows,
          ),
        pw.SizedBox(height: 12),
        _totalsCard(billed, udhar, letterhead.accent),
      ],
    );
  }

  static String _modeLabel(SaleModel s) {
    switch (s.paymentMethod) {
      case 'credit':
        return 'UDHAR';
      case 'split':
        return 'SPLIT';
      default:
        return s.paymentMethod.toUpperCase();
    }
  }

  // ---------------------------------------------------------------------------
  // Layout pieces
  // ---------------------------------------------------------------------------

  static Future<Uint8List> _document({
    required String title,
    required ReportLetterhead letterhead,
    required String periodLabel,
    required String dateSpan,
    required List<pw.Widget> body,
    DateTime? generatedAt,
  }) {
    final doc = pw.Document(title: title, author: pdfSafe(letterhead.storeName));
    final stamp = _stampFmt.format(generatedAt ?? DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        // Long statements put one table across many pages; the default of 20
        // trips an assert in debug builds and tests.
        maxPages: 1000,
        header: (ctx) => ctx.pageNumber == 1
            ? _banner(title, letterhead, periodLabel, dateSpan, stamp)
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  '${pdfSafe(letterhead.storeName, fallback: 'Store')} - $title - ${pdfSafe(periodLabel)}',
                  style: const pw.TextStyle(fontSize: 8, color: _kSlate500),
                ),
              ),
        footer: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _kSlate200))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated by KAMAI+ POS on $stamp', style: const pw.TextStyle(fontSize: 7.5, color: _kSlate500)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: _kSlate500)),
            ],
          ),
        ),
        build: (ctx) => body,
      ),
    );
    return doc.save();
  }

  static pw.Widget _banner(String title, ReportLetterhead lh, String periodLabel, String dateSpan, String stamp) {
    final contact = [
      if (lh.address.trim().isNotEmpty) pdfSafe(lh.address),
      if (lh.phone.trim().isNotEmpty) 'Ph: ${pdfSafe(lh.phone)}',
      if (lh.gstin.trim().isNotEmpty) 'GSTIN: ${pdfSafe(lh.gstin)}',
    ].where((s) => s.isNotEmpty).join('  |  ');
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(color: lh.accent, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(pdfSafe(lh.storeName, fallback: 'Store'),
                    style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                if (contact.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(contact, style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.8)),
              pw.SizedBox(height: 4),
              pw.Text('${pdfSafe(periodLabel)}: ${pdfSafe(dateSpan)}',
                  style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.white)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _billedTo(PartySalesSummary party, String periodLabel, String dateSpan) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _kSlate50,
        border: pw.Border.all(color: _kSlate200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BILLED TO', style: const pw.TextStyle(fontSize: 7.5, color: _kSlate500, letterSpacing: 0.8)),
                pw.SizedBox(height: 3),
                pw.Text(pdfSafe(party.partyName, fallback: 'Customer'),
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _kSlate900)),
                if (party.partyPhone.trim().isNotEmpty)
                  pw.Text('Ph: ${pdfSafe(party.partyPhone)}', style: const pw.TextStyle(fontSize: 9, color: _kSlate500)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('PERIOD', style: const pw.TextStyle(fontSize: 7.5, color: _kSlate500, letterSpacing: 0.8)),
              pw.SizedBox(height: 3),
              pw.Text(pdfSafe(periodLabel),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kSlate900)),
              pw.Text(pdfSafe(dateSpan), style: const pw.TextStyle(fontSize: 8.5, color: _kSlate500)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _kpiRibbon(List<_Kpi> kpis, PdfColor accent) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _kSlate200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          for (final k in kpis)
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(k.label, style: const pw.TextStyle(fontSize: 7.5, color: _kSlate500)),
                    pw.SizedBox(height: 2),
                    pw.Text(k.value,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: k.color ?? _kSlate900)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _section(String title, PdfColor accent) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
      padding: const pw.EdgeInsets.only(left: 6),
      decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: accent, width: 3))),
      child: pw.Text(pdfSafe(title),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kSlate900)),
    );
  }

  static pw.Widget _note(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(pdfSafe(text), style: const pw.TextStyle(fontSize: 8.5, color: _kSlate500)),
      );

  /// A table that splits across pages and repeats its header row.
  static pw.Widget _table({
    required PdfColor accent,
    required List<String> headers,
    required List<List<String>> rows,
    required int numericFrom,
    required int flexColumn,
    Set<int> boldRows = const {},
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: null,
      headerDecoration: pw.BoxDecoration(color: accent),
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerAlignments: {
        for (var i = 0; i < headers.length; i++) i: i >= numericFrom ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      },
      cellStyle: const pw.TextStyle(fontSize: 8, color: _kSlate900),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      cellAlignments: {
        for (var i = 0; i < headers.length; i++) i: i >= numericFrom ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      },
      columnWidths: {flexColumn: const pw.FlexColumnWidth()},
      oddRowDecoration: const pw.BoxDecoration(color: _kSlate50),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kSlate200, width: 0.5)),
      ),
      textStyleBuilder: boldRows.isEmpty
          ? null
          : (col, data, row) =>
              // `row` counts the header, so data row i is row i + 1.
              boldRows.contains(row - 1) ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold) : null,
    );
  }

  static pw.Widget _totalsCard(int billed, int udhar, PdfColor accent) {
    pw.Widget line(String label, String value, {bool strong = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: strong ? 10 : 9, color: _kSlate500)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: strong ? 11 : 9,
                      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: color ?? _kSlate900)),
            ],
          ),
        );
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 230,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: accent, width: 1),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            line('Total billed', rs(billed)),
            line('Paid (Cash / UPI)', rs(billed - udhar)),
            pw.Divider(color: _kSlate200, height: 8),
            line('Udhar for this period', rs(udhar), strong: true, color: udhar > 0 ? _kOrange : null),
          ],
        ),
      ),
    );
  }
}

class _Kpi {
  final String label;
  final String value;
  final PdfColor? color;

  const _Kpi(this.label, this.value, {this.color});
}
