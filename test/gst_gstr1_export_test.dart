import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/services/gst_export_service.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  group('GSTR-1 Filing Period (B2 Fix)', () {
    final service = GstExportService.instance;
    final now = DateTime.now();

    test('This Month resolves to current month and year', () {
      final fp = service.resolveFilingPeriod('This Month');
      expect(fp.month, now.month);
      expect(fp.year, now.year);
      expect(fp.toFp().length, 6);
      expect(fp.toFp(), '${now.month.toString().padLeft(2, '0')}${now.year}');
    });

    test('Last Month resolves to previous month', () {
      final fp = service.resolveFilingPeriod('Last Month');
      final expectedDate = DateTime(now.year, now.month - 1);
      expect(fp.month, expectedDate.month);
      expect(fp.year, expectedDate.year);
      expect(fp.toFp(), '${expectedDate.month.toString().padLeft(2, '0')}${expectedDate.year}');
    });

    test('Quarterly periods resolve to end-of-quarter filing month', () {
      final q1 = service.resolveFilingPeriod('Q1 (Apr-Jun)');
      expect(q1.month, 6); // June
      expect(q1.toFp(), '06${now.year}');

      final q2 = service.resolveFilingPeriod('Q2 (Jul-Sep)');
      expect(q2.month, 9); // September
      expect(q2.toFp(), '09${now.year}');

      final q3 = service.resolveFilingPeriod('Q3 (Oct-Dec)');
      expect(q3.month, 12); // December
      expect(q3.toFp(), '12${now.year}');

      final q4 = service.resolveFilingPeriod('Q4 (Jan-Mar)');
      expect(q4.month, 3); // March
      expect(q4.toFp(), '03${now.year}');
    });
  });

  group('GSTR-1 Store GSTIN Requirement (B4 Fix)', () {
    final service = GstExportService.instance;

    test('Throws ArgumentError if store GSTIN is empty', () async {
      final profile = StoreProfileModel(
        storeName: 'Test Store',
        ownerName: 'Test Owner',
        phone: '9876543210',
        businessType: 'kirana',
        gstin: '', // Empty GSTIN
        address: '123 Main St',
      );

      expect(
        () => service.generateGstr1Json(
          profile: profile,
          period: 'This Month',
          sales: [],
          hsnList: [],
          customersMap: {},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('HSN Summary with Inter-State IGST (B5 Fix)', () {
    final service = GstExportService.instance;

    final mhProfile = StoreProfileModel(
      storeName: 'Maharashtra Store',
      ownerName: 'Owner',
      phone: '9876543210',
      businessType: 'kirana',
      gstin: '27AAAAA0000A1Z5', // State 27 (Maharashtra)
      address: 'Mumbai',
    );

    test('Intra-state supply (same state 27) splits into CGST + SGST', () {
      final sale = SaleModel(
        id: 'sale_1',
        businessId: 'biz_1',
        invoiceNumber: 'INV-001',
        createdAt: DateTime.now(),
        customerName: 'Local Customer',
        customerGstin: '27BBBBB1111B1Z2', // Same state 27
        paymentMethod: 'cash',
        subtotalPaise: 10000,
        taxAmountPaise: 1800,
        discountPaise: 0,
        totalAmountPaise: 11800,
        status: 'completed',
        items: [
          {
            'product_name': 'Test Item',
            'hsn_code': '1001',
            'quantity': 1,
            'tax_rate': 18.0,
            'is_tax_inclusive': false,
            'gross_total_paise': 10000,
          }
        ],
      );

      final hsnSummary = service.generateHsnSummary(
        sales: [sale],
        productsMap: {},
        profile: mhProfile,
      );

      expect(hsnSummary.isNotEmpty, true);
      final item = hsnSummary.first;
      expect(item.igstPaise, 0);
      expect(item.cgstPaise, 900);
      expect(item.sgstPaise, 900);
      expect(item.cgstPaise + item.sgstPaise, item.totalTaxPaise);
    });

    test('Inter-state supply (different state 07) allocates full IGST', () {
      final sale = SaleModel(
        id: 'sale_2',
        businessId: 'biz_1',
        invoiceNumber: 'INV-002',
        createdAt: DateTime.now(),
        customerName: 'Delhi Customer',
        customerGstin: '07CCCCC2222C1Z3', // State 07 (Delhi) vs Store State 27 (MH)
        paymentMethod: 'cash',
        subtotalPaise: 10000,
        taxAmountPaise: 1800,
        discountPaise: 0,
        totalAmountPaise: 11800,
        status: 'completed',
        items: [
          {
            'product_name': 'Test Item',
            'hsn_code': '1001',
            'quantity': 1,
            'tax_rate': 18.0,
            'is_tax_inclusive': false,
            'gross_total_paise': 10000,
          }
        ],
      );

      final hsnSummary = service.generateHsnSummary(
        sales: [sale],
        productsMap: {},
        profile: mhProfile,
      );

      expect(hsnSummary.isNotEmpty, true);
      final item = hsnSummary.first;
      expect(item.igstPaise, 1800);
      expect(item.cgstPaise, 0);
      expect(item.sgstPaise, 0);
      expect(item.totalTaxPaise, 1800);
    });

    test('Refunded sales are excluded from HSN summary (B3 Fix)', () {
      final refundedSale = SaleModel(
        id: 'sale_refunded',
        businessId: 'biz_1',
        invoiceNumber: 'INV-REF',
        createdAt: DateTime.now(),
        customerName: 'Customer',
        paymentMethod: 'cash',
        subtotalPaise: 10000,
        taxAmountPaise: 1800,
        discountPaise: 0,
        totalAmountPaise: 11800,
        status: 'refunded', // REFUNDED
        items: [
          {
            'product_name': 'Refunded Item',
            'hsn_code': '1001',
            'quantity': 1,
            'tax_rate': 18.0,
            'is_tax_inclusive': false,
            'gross_total_paise': 10000,
          }
        ],
      );

      final hsnSummary = service.generateHsnSummary(
        sales: [refundedSale],
        productsMap: {},
        profile: mhProfile,
      );

      // Refunded sale should NOT appear in HSN summary
      expect(hsnSummary.isEmpty, true);
    });
  });
}
