// Rules behind POS Rapid Scan (lib/core/utils/scan_rules.dart): which camera
// detections count as a new scan, which reads are not product codes, and the
// stock limit every add and quantity edit goes through.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/utils/scan_rules.dart';
import 'package:kamaiplus_pos/models/models.dart';

ProductModel product({double stock = 10, String unit = 'pcs'}) => ProductModel(
      id: 'p1',
      businessId: 'b',
      name: 'Maggi 70g',
      sellingPricePaise: 1400,
      mrpPaise: 1500,
      stockQuantity: stock,
      unit: unit,
    );

void main() {
  group('ScanDebouncer', () {
    final t0 = DateTime(2026, 9, 19, 10);
    Duration ms(int n) => Duration(milliseconds: n);

    test('a pack held in view is one scan, however many frames report it', () {
      final d = ScanDebouncer();
      var accepted = 0;
      // The camera reports the code every ~250 ms for 3 seconds.
      for (var t = 0; t <= 3000; t += 250) {
        final now = t0.add(ms(t));
        if (!d.isRecent('890', now)) accepted++;
        d.seen('890', now);
      }
      expect(accepted, 1);
    });

    test('showing the same pack again after taking it away counts again', () {
      final d = ScanDebouncer();
      d.seen('890', t0);
      expect(d.isRecent('890', t0.add(ms(500))), isTrue);
      expect(d.isRecent('890', t0.add(ms(950))), isFalse);
    });

    test('two packs in view at once cannot ping-pong into the bill', () {
      final d = ScanDebouncer();
      final counted = <String>[];
      for (var t = 0; t <= 2000; t += 125) {
        final code = (t ~/ 125).isEven ? 'A' : 'B';
        final now = t0.add(ms(t));
        if (!d.isRecent(code, now)) counted.add(code);
        d.seen(code, now);
      }
      expect(counted, ['A', 'B']);
    });
  });

  group('normalizeScannedCode', () {
    test('keeps real product codes', () {
      expect(normalizeScannedCode(' 8901063010123 '), '8901063010123');
      expect(normalizeScannedCode('SKU-00042'), 'SKU-00042');
    });

    test('drops payment QRs, links and junk that must not be looked up', () {
      expect(normalizeScannedCode('upi://pay?pa=shop@okaxis&pn=Shop'), isNull);
      expect(normalizeScannedCode('https://example.com/p/1'), isNull);
      expect(normalizeScannedCode('WIFI:S:Shop;T:WPA;P:secret;;'), isNull);
      expect(normalizeScannedCode('12'), isNull);
      expect(normalizeScannedCode('line1\nline2'), isNull);
      expect(normalizeScannedCode(null), isNull);
    });
  });

  group('stockErrorFor', () {
    test('allows up to the stock on hand, refuses beyond it', () {
      expect(stockErrorFor(product(stock: 3), 3), isNull);
      expect(stockErrorFor(product(stock: 3), 4), contains('Only 3 pcs'));
      expect(stockErrorFor(product(stock: 0), 1), contains('Out of Stock'));
    });

    test('loose quantities compare exactly', () {
      expect(stockErrorFor(product(stock: 2.5, unit: 'kg'), 2.5), isNull);
      expect(stockErrorFor(product(stock: 2.5, unit: 'kg'), 2.75), contains('Only 2.5 kg'));
    });

    test('unlimited stock is never refused', () {
      expect(stockErrorFor(product(stock: 99999), 500000), isNull);
    });
  });

  test('formatCartQty keeps loose decimals', () {
    expect(formatCartQty(3), '3');
    expect(formatCartQty(2.5), '2.5');
    expect(formatCartQty(0.25), '0.25');
  });
}
