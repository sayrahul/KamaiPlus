/// Builds a UPI payment link for WhatsApp/SMS message TEXT — deliberately
/// NOT for QR codes, which must keep using a raw `upi://pay?...` URI
/// directly (a scanner app parses that scheme; wrapping it would break
/// scanning). This is only for the several screens that paste a payment
/// link into a WhatsApp message string and tell the customer to tap it.
///
/// WhatsApp only auto-links `http(s)://` text as tappable — a bare
/// `upi://pay?...` string sits inert in a chat bubble. Fixing that needs an
/// `https://` link that hands off to `upi://` once opened. This points at
/// `https://kamaiplus-pay.web.app`, a small first-party, self-hosted static
/// page (see `pay_redirect/index.html` at the repo root) — not a
/// third-party shortener — so no payment data goes anywhere but
/// infrastructure this project already owns; the page just shows a
/// "Open UPI App to Pay" button that opens the same `upi://` URI this
/// function still builds internally.
String buildClickableUpiLink({
  required String upiId,
  required String payeeName,
  String? amountRupees,
  String? transactionNote,
}) {
  final buffer = StringBuffer('upi://pay?pa=$upiId&pn=${Uri.encodeComponent(payeeName)}');
  if (amountRupees != null && amountRupees.isNotEmpty) {
    buffer.write('&am=$amountRupees');
  }
  buffer.write('&cu=INR');
  if (transactionNote != null && transactionNote.isNotEmpty) {
    buffer.write('&tn=${Uri.encodeComponent(transactionNote)}');
  }
  final rawUpiUri = buffer.toString();

  final redirectUri = Uri.https('kamaiplus-pay.web.app', '/', {
    'u': rawUpiUri,
    's': payeeName,
    if (amountRupees != null && amountRupees.isNotEmpty) 'a': amountRupees,
  });
  return redirectUri.toString();
}
