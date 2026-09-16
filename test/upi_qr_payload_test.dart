// Pins the UPI QR payload built by the shared [DynamicUpiQrSheet].
//
// The sheet became shared because it used to be a private method of
// `_PosCheckoutModalState`. The Khata "Settle Credit Bills" flow could not
// reach it and grew its own inert QR thumbnail instead — no enlarge, no
// countdown, no copyable UPI id — so a cashier taking an udhar payment saw a
// visibly worse screen than one taking the identical amount at the counter.
// Now all four call sites (counter UPI, POS split, khata settlement, khata
// split settlement) render the same sheet from the same payload builder.
//
// These assertions are about the string a customer's UPI app actually parses,
// so the amount and payee are the parts that matter most.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/views/common/dynamic_upi_qr_sheet.dart';

void main() {
  String payload({
    String vpa = 'shop@okaxis',
    String store = 'Kamai Kirana',
    int paise = 12500,
    String note = 'POS Bill',
    String ref = '1700000000000',
  }) =>
      DynamicUpiQrSheet.buildQrPayload(
        upiVpa: vpa,
        storeName: store,
        amountPaise: paise,
        note: note,
        txnRef: ref,
      );

  group('UPI QR payload', () {
    test('uses the raw upi:// scheme a scanner can parse', () {
      // Never an https wrapper — that would break scanning outright. The
      // https redirect exists only for tappable WhatsApp links
      // (upi_link_utils.dart), which is the opposite case.
      expect(payload(), startsWith('upi://pay?'));
    });

    test('carries payee, amount in rupees, and currency', () {
      final p = payload(vpa: 'ramesh@ybl', paise: 45050);
      expect(p, contains('pa=ramesh@ybl'));
      expect(p, contains('am=450.50'));
      expect(p, contains('cu=INR'));
    });

    test('amount is always two decimals, never paise', () {
      // A UPI app reads `am` as RUPEES. Handing it paise would ask the
      // customer for 100x the bill.
      expect(payload(paise: 10000), contains('am=100.00'));
      expect(payload(paise: 1), contains('am=0.01'));
      expect(payload(paise: 99999), contains('am=999.99'));
    });

    test('store name and note are URL-encoded', () {
      final p = payload(store: 'Sharma & Sons Kirana', note: 'Settle 3 Bill(s)');
      expect(p, contains('pn=Sharma%20%26%20Sons%20Kirana'));
      expect(p, contains('tn=Settle%203%20Bill'));
      expect(p, isNot(contains('Sharma & Sons')),
          reason: 'an unencoded & would truncate every parameter after it');
    });

    test('each generation carries its own transaction reference', () {
      // Without `tr`, every QR for every bill looks identical in the
      // merchant's UPI statement and none can be told apart.
      expect(payload(ref: 'abc123'), contains('tr=abc123'));
      expect(payload(ref: 'abc123'), isNot(equals(payload(ref: 'xyz789'))));
    });

    test('a split portion builds a smaller QR than the full bill', () {
      // The exact bug the shared sheet fixed: opening the enlarged QR from a
      // split used to read the whole-bill total and ask for too much.
      final full = payload(paise: 100000, note: 'POS Bill');
      final split = payload(paise: 40000, note: 'Split Bill');
      expect(full, contains('am=1000.00'));
      expect(split, contains('am=400.00'));
    });

    test('khata settlement builds against the settlement total', () {
      final p = payload(paise: 500000, note: 'Settle 3 Bill(s)');
      expect(p, contains('am=5000.00'));
      expect(p, contains('tn=Settle'));
    });
  });

  group('Countdown window', () {
    test('is five minutes', () {
      // The readout used to be the literal string 'Valid: 05:00' with no timer
      // behind it. If this constant ever changes, the label must follow.
      expect(DynamicUpiQrSheet.validity, const Duration(minutes: 5));
    });
  });
}
