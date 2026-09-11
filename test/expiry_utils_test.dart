// Tests for the Pharmacy FEFO stock-rotation nudge added 2026-09-11
// (Phase 4 of the KamaiPlus Playbook, part 2): parseProductExpiry is the
// single source the POS billing grid and search-results list use to decide
// whether to show a "SELL FIRST" / "EXPIRED" badge on a product, so a
// cashier naturally reaches for the older batch before a fresher one.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/utils/expiry_utils.dart';
import 'package:kamaiplus_pos/models/models.dart';

ProductModel _productWithExpiry(String? expiryDate) => ProductModel(
  id: 'p1',
  businessId: 'b1',
  name: 'Test Medicine',
  sellingPricePaise: 1000,
  mrpPaise: 1200,
  stockQuantity: 10,
  expiryDate: expiryDate,
);

void main() {
  group('parseProductExpiry', () {
    test('returns null when there is no expiry date', () {
      expect(parseProductExpiry(_productWithExpiry(null)), isNull);
      expect(parseProductExpiry(_productWithExpiry('')), isNull);
      expect(parseProductExpiry(_productWithExpiry('   ')), isNull);
    });

    test('parses ISO yyyy-MM-dd dates', () {
      final farFuture = DateTime.now().add(const Duration(days: 400));
      final iso = '${farFuture.year}-${farFuture.month.toString().padLeft(2, '0')}-${farFuture.day.toString().padLeft(2, '0')}';
      final status = parseProductExpiry(_productWithExpiry(iso));
      expect(status, isNotNull);
      expect(status!.isExpired, isFalse);
      expect(status.isExpiringSoon, isFalse);
    });

    test('parses MM/YY as the 28th of that month', () {
      final status = parseProductExpiry(_productWithExpiry('01/30'));
      expect(status, isNotNull);
      expect(status!.date.year, 2030);
      expect(status.date.month, 1);
      expect(status.date.day, 28);
    });

    test('parses dd/MM/yyyy dates', () {
      final status = parseProductExpiry(_productWithExpiry('15/06/2030'));
      expect(status, isNotNull);
      expect(status!.date, DateTime(2030, 6, 15));
    });

    test('an unparseable string returns null instead of throwing', () {
      expect(() => parseProductExpiry(_productWithExpiry('not-a-date')), returnsNormally);
      expect(parseProductExpiry(_productWithExpiry('not-a-date')), isNull);
    });

    test('a date in the past is flagged expired, not expiring-soon', () {
      final past = DateTime.now().subtract(const Duration(days: 5));
      final iso = '${past.year}-${past.month.toString().padLeft(2, '0')}-${past.day.toString().padLeft(2, '0')}';
      final status = parseProductExpiry(_productWithExpiry(iso));
      expect(status!.isExpired, isTrue);
      expect(status.isExpiringSoon, isFalse);
    });

    test('a date within 30 days is flagged expiring-soon, not expired', () {
      final soon = DateTime.now().add(const Duration(days: 10));
      final iso = '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
      final status = parseProductExpiry(_productWithExpiry(iso));
      expect(status!.isExpired, isFalse);
      expect(status.isExpiringSoon, isTrue);
    });

    test('a date 90 days out is neither expired nor expiring-soon', () {
      final later = DateTime.now().add(const Duration(days: 90));
      final iso = '${later.year}-${later.month.toString().padLeft(2, '0')}-${later.day.toString().padLeft(2, '0')}';
      final status = parseProductExpiry(_productWithExpiry(iso));
      expect(status!.isExpired, isFalse);
      expect(status.isExpiringSoon, isFalse);
    });
  });
}
