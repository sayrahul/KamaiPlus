import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/utils/money_formatter.dart';

void main() {
  group('Integer Paise Math & GST Invariants', () {
    test('Standard INR Currency Formatting', () {
      expect(MoneyFormatter.formatINR(49900), '₹499.00');
      expect(MoneyFormatter.formatINR(2800), '₹28.00');
      expect(MoneyFormatter.formatINR(10000000), '₹1,00,000.00');
    });

    test('Rupees to Paise Parsing', () {
      expect(MoneyFormatter.parseRupeesToPaise('499.00'), 49900);
      expect(MoneyFormatter.parseRupeesToPaise('₹1,250.50'), 125050);
      expect(MoneyFormatter.parseRupeesToPaise('0'), 0);
      expect(MoneyFormatter.parseRupeesToPaise('2.675'), 268);
      expect(MoneyFormatter.parseRupeesToPaise('2.674'), 267);
      expect(MoneyFormatter.parseRupeesToPaise('10.5'), 1050);
      expect(MoneyFormatter.parseRupeesToPaise(''), 0);
    });

    test('Tax Inclusive GST Calculation (Zero Drift)', () {
      // Selling price 10000 paise (₹100) with 18% GST inclusive
      final res = MoneyFormatter.calculateGst(
        grossOrBasePaise: 10000,
        taxRatePercent: 18.0,
        isInclusive: true,
      );

      // Taxable = round(10000 * 10000 / 11800) = 8475 paise
      expect(res['taxableAmount'], 8475);
      expect(res['totalGst'], 1525);
      expect(res['cgst'], 763);
      expect(res['sgst'], 762);
      expect(res['cgst']! + res['sgst']!, res['totalGst']);
      expect(res['taxableAmount']! + res['totalGst']!, res['grossTotal']);
    });
  });
}
