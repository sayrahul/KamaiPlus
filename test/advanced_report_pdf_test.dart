// Advanced Sales Report PDFs (AdvancedReportPdfService).
//
// The built-in PDF fonts cover Latin-1 only; any character above U+00FF (the
// rupee sign, a bullet, a Hindi product name) throws "Unable to display U+..."
// and the export fails. These tests feed exactly that kind of text through
// both documents, and a statement long enough to span many pages.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/models/report_models.dart';
import 'package:kamaiplus_pos/services/advanced_report_pdf_service.dart';

const _letterhead = ReportLetterhead(
  storeName: 'Sharma Kirana • शर्मा', // bullet + Devanagari
  phone: '98765 43210',
  address: 'Shop 4 – Main Bazaar', // en dash
  gstin: '27ABCDE1234F1Z5',
);

SaleModel _bill(int n, List<Map<String, dynamic>> items, {String method = 'cash', String status = 'completed'}) {
  final total = items.fold<int>(0, (s, i) => s + (i['gross_total_paise'] as int));
  return SaleModel(
    id: 's$n',
    businessId: 'biz',
    invoiceNumber: 'INV-$n',
    customerId: 'cust_1',
    customerName: 'Ravi “Bhai”', // curly quotes
    subtotalPaise: total,
    taxAmountPaise: 0,
    totalAmountPaise: total,
    paymentMethod: method,
    status: status,
    items: items,
    createdAt: DateTime(2026, 9, 1).add(Duration(hours: n)),
  );
}

Map<String, dynamic> _item(String name, double qty, int unit, {double returned = 0}) => {
      'product_id': 'p_$name',
      'product_name': name,
      'quantity': qty,
      'unit_price_paise': unit,
      'gross_total_paise': (unit * qty).round(),
      'cost_price_paise': (unit * 0.8).round(),
      if (returned > 0) 'returned_quantity': returned,
    };

bool _isPdf(List<int> bytes) => bytes.length > 500 && ascii.decode(bytes.sublist(0, 5)) == '%PDF-';

void main() {
  group('pdfSafe', () {
    test('maps common typography to ASCII and strips everything outside Latin-1', () {
      expect(AdvancedReportPdfService.pdfSafe('₹ 500 • Atta – 5kg…'), 'Rs. 500 - Atta - 5kg...');
      expect(AdvancedReportPdfService.pdfSafe('‘Chai’ × 2'), "'Chai' x 2");
      expect(AdvancedReportPdfService.pdfSafe('Café'), 'Café', reason: 'Latin-1 accents are printable');
      expect(AdvancedReportPdfService.pdfSafe('Atta आटा'), 'Atta ?');
      for (final r in AdvancedReportPdfService.pdfSafe('\u{1F600} Maggi नूडल्स').runes) {
        expect(r <= 0xFF, isTrue);
      }
    });

    test('falls back when nothing readable is left', () {
      expect(AdvancedReportPdfService.pdfSafe('आटा', fallback: 'Item'), 'Item');
      expect(AdvancedReportPdfService.pdfSafe(null, fallback: 'Item'), 'Item');
    });

    test('money is printed with an ASCII "Rs." prefix and Indian grouping', () {
      expect(AdvancedReportPdfService.rs(12345650), 'Rs. 1,23,456.50');
    });

    test('loose quantities keep their decimals', () {
      expect(formatReportQty(3), '3');
      expect(formatReportQty(2.5), '2.5');
      expect(formatReportQty(0.25), '0.25');
    });
  });

  test('customer statement renders non-Latin text, partial returns and many pages', () async {
    final bills = [
      for (var n = 0; n < 120; n++)
        _bill(n, [
          _item('Atta आटा', 2, 25000, returned: n == 3 ? 1 : 0),
          _item('दाल', 1.5, 12000), // entirely Devanagari name
          _item('Oil ₹ offer • 1L', 1, 18000),
        ], method: n.isEven ? 'cash' : 'credit'),
      _bill(999, [_item('Refunded item', 1, 5000)], status: 'refunded'),
    ];
    final party = PartySalesSummary(
      partyId: 'cust_1',
      partyName: 'Ravi “Bhai” रवि',
      partyPhone: '98765 43210',
      totalSalesPaise: 0,
      totalCostPaise: 0,
      totalProfitPaise: 0,
      invoiceCount: bills.length,
    );

    final bytes = await AdvancedReportPdfService.buildPartyStatement(
      party: party,
      invoices: bills,
      periodLabel: 'This Month',
      dateSpan: '1 Sep 2026 – 19 Sep 2026',
      letterhead: _letterhead,
    );

    expect(_isPdf(bytes), isTrue);
  });

  test('period report renders with and without profit, including dead stock', () async {
    final data = AdvancedReportsData(
      partyData: [
        PartySalesSummary(
          partyId: 'walkin',
          partyName: 'Walk-in Customer',
          partyPhone: '',
          totalSalesPaise: 150000,
          totalCostPaise: 100000,
          totalProfitPaise: 20000,
          invoiceCount: 12,
          costedRevenuePaise: 120000,
          uncostedRevenuePaise: 30000,
          uncostedLineCount: 3,
        ),
      ],
      categoryData: [
        CategorySalesSummary(
          categoryName: 'अनाज', // Devanagari category
          totalSalesPaise: 150000,
          totalCostPaise: 100000,
          totalProfitPaise: 20000,
          quantitySold: 42.5,
          costedRevenuePaise: 120000,
          uncostedRevenuePaise: 30000,
          uncostedLineCount: 3,
        ),
      ],
      itemData: [
        for (var i = 0; i < 400; i++)
          ItemSalesSummary(
            itemId: 'p_$i',
            itemName: 'Item $i • वस्तु',
            categoryName: 'Staples',
            totalSalesPaise: 1000 + i,
            totalCostPaise: 800,
            totalProfitPaise: 200 + i,
            quantitySold: 1,
            costedRevenuePaise: 1000 + i,
          ),
        ItemSalesSummary(
          itemId: 'dead_p_x',
          itemName: 'Basmati राइस',
          categoryName: 'Staples',
          totalSalesPaise: 0,
          totalCostPaise: 0,
          totalProfitPaise: 0,
          quantitySold: 0,
          stockQuantity: 4,
          unit: 'kg',
        ),
      ],
      paymentSummary: PaymentModeSummary(totalCashPaise: 100000, totalUpiPaise: 30000, totalCreditPaise: 20000),
    );

    for (final includeProfit in [false, true]) {
      final bytes = await AdvancedReportPdfService.buildGeneralReport(
        data: data,
        periodLabel: 'This Month',
        dateSpan: '1 Sep 2026 - 19 Sep 2026',
        letterhead: _letterhead,
        includeProfit: includeProfit,
      );
      expect(_isPdf(bytes), isTrue, reason: 'includeProfit=$includeProfit');
    }
  });

  test('empty period still produces a valid report and statement', () async {
    final empty = AdvancedReportsData(
      partyData: const [],
      categoryData: const [],
      itemData: const [],
      paymentSummary: PaymentModeSummary(totalCashPaise: 0, totalUpiPaise: 0, totalCreditPaise: 0),
    );
    expect(
      _isPdf(await AdvancedReportPdfService.buildGeneralReport(
        data: empty,
        periodLabel: 'Today',
        dateSpan: '19 Sep 2026',
        letterhead: const ReportLetterhead(storeName: ''),
      )),
      isTrue,
    );
    expect(
      _isPdf(await AdvancedReportPdfService.buildPartyStatement(
        party: PartySalesSummary(
          partyId: 'walkin',
          partyName: 'Walk-in Customer',
          partyPhone: '',
          totalSalesPaise: 0,
          totalCostPaise: 0,
          totalProfitPaise: 0,
          invoiceCount: 0,
        ),
        invoices: const [],
        periodLabel: 'Today',
        dateSpan: '19 Sep 2026',
        letterhead: _letterhead,
      )),
      isTrue,
    );
  });
}
