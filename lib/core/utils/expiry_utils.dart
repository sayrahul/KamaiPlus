import '../../models/models.dart';

/// Parsed expiry state for a single product — Phase 4 of the KamaiPlus
/// Playbook (Pharmacy FEFO stock-rotation nudge). Deliberately built on the
/// single existing `ProductModel.expiryDate` field rather than a new
/// multi-batch schema: a real FEFO system tracks expiry per received batch,
/// but that needs a schema change this phase doesn't make. This gives the
/// same practical nudge — "sell this one first" — for the common single-batch
/// case, reusing the same date-parsing rules already proven in
/// `inventory_screen.dart`'s Near Expiry radar (so a date that radar flags
/// is exactly the date this flags too).
class ExpiryStatus {
  final DateTime date;
  final int daysLeft;
  bool get isExpired => daysLeft <= 0;
  bool get isExpiringSoon => daysLeft > 0 && daysLeft <= 30;

  const ExpiryStatus({required this.date, required this.daysLeft});
}

/// Parses `ProductModel.expiryDate`, accepting ISO (`yyyy-MM-dd`), `MM/YY`,
/// and `dd/MM/yyyy` — the same three shapes `inventory_screen.dart` already
/// handles. Returns null when there's no date or it's unparseable.
ExpiryStatus? parseProductExpiry(ProductModel product) {
  final raw = product.expiryDate?.trim();
  if (raw == null || raw.isEmpty) return null;

  DateTime? expiry = DateTime.tryParse(raw);
  if (expiry == null && raw.contains('/')) {
    final parts = raw.split('/');
    if (parts.length == 2) {
      final month = int.tryParse(parts[0]);
      var year = int.tryParse(parts[1]);
      if (month != null && year != null) {
        if (year < 100) year += 2000;
        expiry = DateTime(year, month, 28);
      }
    } else if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        expiry = DateTime(year, month, day);
      }
    }
  }
  if (expiry == null) return null;

  final daysLeft = expiry.difference(DateTime.now()).inDays;
  return ExpiryStatus(date: expiry, daysLeft: daysLeft);
}
