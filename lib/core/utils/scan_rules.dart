import '../../models/models.dart';

/// Decides which camera detections are NEW scans in continuous (rapid)
/// scanning.
///
/// The camera reports a barcode several times a second for as long as it is
/// in view, so "same code again" cannot simply mean "one more unit". A code
/// counts again only after it has been OUT of view for [window] — the
/// cashier takes the pack away and shows the next one. Every code is tracked
/// separately, so two packs in view at once cannot ping-pong each other into
/// the bill.
class ScanDebouncer {
  ScanDebouncer({this.window = const Duration(milliseconds: 900)});

  final Duration window;
  final Map<String, DateTime> _lastSeen = {};

  /// True while [code] is still (or was just) in view.
  bool isRecent(String code, DateTime now) {
    final seen = _lastSeen[code];
    return seen != null && now.difference(seen) < window;
  }

  /// Records that [code] is in view at [now].
  void seen(String code, DateTime now) {
    _lastSeen[code] = now;
    if (_lastSeen.length > 64) {
      _lastSeen.removeWhere((_, t) => now.difference(t) > window * 4);
    }
  }

  void reset() => _lastSeen.clear();
}

/// Cleans a camera/scanner read into a product code, or null when it is not
/// one. A UPI payment QR or a web link printed near the counter must not be
/// looked up (and reported as "not found") on every frame.
String? normalizeScannedCode(String? raw) {
  if (raw == null) return null;
  final code = raw.trim();
  if (code.length < 3 || code.length > 64) return null;
  if (code.contains('\n') || code.contains('\r')) return null;
  final lower = code.toLowerCase();
  const nonProduct = ['upi:', 'http://', 'https://', 'www.', 'tel:', 'mailto:', 'wifi:', 'bharatqr'];
  if (nonProduct.any(lower.startsWith)) return null;
  return code;
}

/// "3", "2.5", "0.25" — whole counts without decimals, loose quantities kept.
String formatCartQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

/// Why [product] cannot be billed at [quantity], or null when it can.
///
/// The same rule the billing grid applies on every tap — a scan or a quick
/// quantity edit must not be a way around it.
String? stockErrorFor(ProductModel product, double quantity) {
  if (product.isUnlimitedStock) return null;
  if (quantity <= product.stockQuantity + 1e-9) return null;
  if (product.stockQuantity <= 0) {
    return '"${product.name}" is Out of Stock! (Available: 0)';
  }
  return 'Only ${formatCartQty(product.stockQuantity)} ${product.unit} of "${product.name}" in stock';
}
