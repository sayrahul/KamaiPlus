// Tests for the fix to item 13 of the 2026-09-11 batch — WhatsApp only
// auto-links http(s):// text as tappable, so a raw upi://pay?... string
// embedded in a WhatsApp message sat inert. buildClickableUpiLink wraps it
// in a link to a first-party, self-hosted redirect page
// (kamaiplus-pay.web.app — see pay_redirect/index.html) instead of a
// third-party shortener, so no payment data leaves infrastructure this
// project already owns.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/utils/upi_link_utils.dart';

void main() {
  group('buildClickableUpiLink', () {
    // Extracting via Uri.parse(...).queryParameters — not a manual
    // Uri.decodeComponent — matches how the actual consumer (the redirect
    // page's `new URLSearchParams(location.search).get('u')`, in a real
    // browser) reads this value back out: a single, correct decode of
    // whatever percent-encoding Uri.https applied when building the link.
    String embeddedUpiUri(String link) => Uri.parse(link).queryParameters['u']!;

    test('returns an https link to the first-party redirect host, not a raw upi:// URI', () {
      final link = buildClickableUpiLink(upiId: 'store@okhdfcbank', payeeName: 'Test Store');
      expect(link.startsWith('https://kamaiplus-pay.web.app'), isTrue);
      expect(embeddedUpiUri(link).startsWith('upi://pay?'), isTrue, reason: 'the raw upi:// intent must round-trip intact inside the "u" query param');
    });

    test('carries the payee VPA and name through into the embedded upi:// URI', () {
      final link = buildClickableUpiLink(upiId: 'shop@ybl', payeeName: 'Kirana Store');
      final upiUri = embeddedUpiUri(link);
      expect(upiUri, contains('pa=shop@ybl'));
      // The payee name is percent-encoded WITHIN the upi:// URI itself
      // (a real UPI app expects a proper URI, same as before this fix) —
      // Uri.decodeComponent reverses exactly that one layer.
      expect(Uri.decodeComponent(upiUri), contains('pn=Kirana Store'));
    });

    test('includes the amount when provided, and omits it when not', () {
      final withAmount = embeddedUpiUri(buildClickableUpiLink(upiId: 'a@b', payeeName: 'S', amountRupees: '499.00'));
      expect(withAmount, contains('am=499.00'));

      final withoutAmount = embeddedUpiUri(buildClickableUpiLink(upiId: 'a@b', payeeName: 'S'));
      expect(withoutAmount, isNot(contains('am=')));
    });

    test('includes a transaction note when provided', () {
      final upiUri = embeddedUpiUri(buildClickableUpiLink(upiId: 'a@b', payeeName: 'S', transactionNote: 'Bill_INV001'));
      expect(upiUri, contains('tn=Bill_INV001'));
    });

    test('the redirect page also receives the store name and amount as separate display params', () {
      final link = buildClickableUpiLink(upiId: 'a@b', payeeName: 'My Shop', amountRupees: '100.00');
      final uri = Uri.parse(link);
      expect(uri.queryParameters['s'], 'My Shop');
      expect(uri.queryParameters['a'], '100.00');
    });
  });
}
