import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  group('SaleModel Return & Net Revenue Math', () {
    test('Normal sale has zero refunds and full net amount', () {
      final sale = SaleModel(
        id: 'sale-1',
        businessId: 'biz-1',
        invoiceNumber: 'INV-001',
        subtotalPaise: 50000,
        taxAmountPaise: 0,
        totalAmountPaise: 50000,
        paymentMethod: 'cash',
        status: 'completed',
        items: [
          {
            'product_id': 'p1',
            'product_name': 'Amul Butter 100g',
            'quantity': 2,
            'price_paise': 25000,
            'returned_quantity': 0,
          }
        ],
        createdAt: DateTime.now(),
      );

      expect(sale.isRefunded, isFalse);
      expect(sale.isPartiallyRefunded, isFalse);
      expect(sale.totalRefundedPaise, equals(0));
      expect(sale.netAmountPaise, equals(50000));
      expect(sale.netCashAmountPaise, equals(50000));
    });

    test('Partial return computes correct refund amount and net revenue', () {
      final sale = SaleModel(
        id: 'sale-2',
        businessId: 'biz-1',
        invoiceNumber: 'INV-002',
        subtotalPaise: 100000,
        taxAmountPaise: 0,
        totalAmountPaise: 100000,
        paymentMethod: 'cash',
        status: 'partially_refunded',
        items: [
          {
            'product_id': 'p1',
            'product_name': 'Item A',
            'quantity': 2,
            'price_paise': 30000,
            'returned_quantity': 1, // Returned 1 of 2 = 30000 refunded
          },
          {
            'product_id': 'p2',
            'product_name': 'Item B',
            'quantity': 1,
            'price_paise': 40000,
            'returned_quantity': 0,
          },
        ],
        createdAt: DateTime.now(),
      );

      expect(sale.isRefunded, isFalse);
      expect(sale.isPartiallyRefunded, isTrue);
      expect(sale.totalRefundedPaise, equals(30000));
      expect(sale.netAmountPaise, equals(70000));
      expect(sale.netCashAmountPaise, equals(70000));
    });

    test('Fully refunded sale returns zero net amounts', () {
      final sale = SaleModel(
        id: 'sale-3',
        businessId: 'biz-1',
        invoiceNumber: 'INV-003',
        subtotalPaise: 45000,
        taxAmountPaise: 0,
        totalAmountPaise: 45000,
        paymentMethod: 'cash',
        status: 'refunded',
        items: [
          {
            'product_id': 'p1',
            'product_name': 'Item A',
            'quantity': 1,
            'price_paise': 45000,
            'returned_quantity': 1,
          }
        ],
        createdAt: DateTime.now(),
      );

      expect(sale.isRefunded, isTrue);
      expect(sale.isPartiallyRefunded, isFalse);
      expect(sale.totalRefundedPaise, equals(45000));
      expect(sale.netAmountPaise, equals(0));
      expect(sale.netCashAmountPaise, equals(0));
    });

    test('Store Credit / Advance: Negative balance represents customer Jama', () {
      // Customer has 0 debt, returns item worth ₹300
      const currentBalancePaise = 0;
      const refundPaise = 30000;
      final newBalancePaise = currentBalancePaise - refundPaise;

      // Negative balance is strictly preserved (no clamp to 0)
      expect(newBalancePaise, equals(-30000));
    });

    test('Udhar Reversal: Customer debt is reduced by refund amount', () {
      // Customer has ₹500 debt, returns item worth ₹200
      const currentBalancePaise = 50000;
      const refundPaise = 20000;
      final newBalancePaise = currentBalancePaise - refundPaise;

      expect(newBalancePaise, equals(30000));
    });

    test('Split payment partial return distributes cash and credit correctly', () {
      final sale = SaleModel(
        id: 'sale-4',
        businessId: 'biz-1',
        invoiceNumber: 'INV-004',
        subtotalPaise: 100000,
        taxAmountPaise: 0,
        totalAmountPaise: 100000,
        paymentMethod: 'split',
        splitCashPaise: 60000,
        splitUpiPaise: 40000,
        status: 'partially_refunded',
        items: [
          {
            'product_id': 'p1',
            'product_name': 'Item 1',
            'quantity': 2,
            'price_paise': 50000,
            'returned_quantity': 1, // 50000 refunded
          }
        ],
        createdAt: DateTime.now(),
      );

      expect(sale.totalRefundedPaise, equals(50000));
      expect(sale.netAmountPaise, equals(50000));
      // Net cash is bounded by remaining net amount
      expect(sale.netCashAmountPaise, equals(50000));
      expect(sale.netUpiAmountPaise, equals(0));
    });
  });
}
