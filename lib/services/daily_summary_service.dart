import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/local_database.dart';
import '../core/utils/money_formatter.dart';
import 'native_notification_service.dart';

/// Fires the "yesterday's business summary" notification the first time the
/// app is opened on a new calendar day. Deliberately not a WorkManager
/// alarm scheduled for a fixed clock time — Android gives no reliable way to
/// fire something at an exact time of day without exact-alarm permissions
/// and battery-optimization fights, and the existing periodic background
/// sync (workmanager_sync_service.dart) already runs every 15 minutes
/// regardless of whether the app is open. Checking on app-open is simpler,
/// needs no extra permission, and matches what the merchant actually wants:
/// a recap waiting for them whenever they first check the app for the day.
class DailySummaryService {
  static const _prefKeyLastShownDate = 'daily_summary_last_shown_date';

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Checks whether today's summary has already been shown; if not, computes
  /// yesterday's sales (cash/UPI/total split) and fires one notification.
  static Future<void> checkAndNotify() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = _todayKey();
      final lastShown = prefs.getString(_prefKeyLastShownDate);
      if (lastShown == todayKey) return;

      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));

      final sales = await LocalDatabase.instance.getAllSales(limit: 1000);
      final ySales = sales.where((s) =>
          !s.isRefunded &&
          s.createdAt.year == yesterday.year &&
          s.createdAt.month == yesterday.month &&
          s.createdAt.day == yesterday.day).toList();

      // Mark today as shown regardless of whether there were any sales —
      // an empty yesterday is still worth a "no sales yesterday" nudge, and
      // this must never repeat later the same day.
      await prefs.setString(_prefKeyLastShownDate, todayKey);

      if (ySales.isEmpty) return;

      final totalPaise = ySales.fold<int>(0, (sum, s) => sum + s.totalAmountPaise);
      final cashPaise = ySales
              .where((s) => s.paymentMethod == 'cash')
              .fold<int>(0, (sum, s) => sum + s.totalAmountPaise) +
          ySales
              .where((s) => s.paymentMethod == 'split')
              .fold<int>(0, (sum, s) => sum + s.splitCashPaise);
      final upiPaise = ySales
              .where((s) => s.paymentMethod == 'upi')
              .fold<int>(0, (sum, s) => sum + s.totalAmountPaise) +
          ySales
              .where((s) => s.paymentMethod == 'split')
              .fold<int>(0, (sum, s) => sum + s.splitUpiPaise);

      await NativeNotificationService.notifyDailySummary(
        totalFormatted: MoneyFormatter.formatINR(totalPaise),
        billCount: ySales.length,
        cashFormatted: MoneyFormatter.formatINR(cashPaise),
        upiFormatted: MoneyFormatter.formatINR(upiPaise),
      );
    } catch (_) {}
  }
}
