import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/local_database.dart';
import '../../core/utils/money_formatter.dart';

/// Service to keep Android Home Screen Widgets synchronized with real-time SQLite metrics
class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  /// Updates the Android Home Screen Widget with latest real-time store metrics
  Future<void> updateTodayMetrics() async {
    try {
      final db = await LocalDatabase.instance.database;
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD

      // 1. Today's Completed Sales (Paise) - Case-insensitive match
      final salesResult = await db.rawQuery('''
        SELECT SUM(total_amount_paise) as total
        FROM sales
        WHERE created_at LIKE ? AND LOWER(status) != 'refunded'
      ''', ['$todayStr%']);
      final int todaySalesPaise = (salesResult.first['total'] as int?) ?? 0;

      // 2. Total Khata Due (Paise)
      final khataResult = await db.rawQuery('''
        SELECT SUM(current_balance_paise) as total_due
        FROM customers
        WHERE current_balance_paise > 0
      ''');
      final int totalKhataDuePaise = (khataResult.first['total_due'] as int?) ?? 0;

      // 3. Cash-in-Hand (Opening Float + Today's Cash In - Today's Cash Out)
      final int openingFloatPaise = prefs.getInt('cash_register_opening_float_paise') ?? 0;

      final cashSalesResult = await db.rawQuery('''
        SELECT SUM(
          CASE 
            WHEN LOWER(payment_method) = 'cash' THEN total_amount_paise
            WHEN LOWER(payment_method) = 'split' THEN split_cash_paise
            ELSE 0
          END
        ) as total_cash
        FROM sales
        WHERE created_at LIKE ?
      ''', ['$todayStr%']);
      final int todayCashInPaise = (cashSalesResult.first['total_cash'] as int?) ?? 0;

      final expensesResult = await db.rawQuery('''
        SELECT SUM(amount_paise) as total_exp
        FROM expenses
        WHERE created_at LIKE ?
      ''', ['$todayStr%']);
      final int todayExpensesPaise = (expensesResult.first['total_exp'] as int?) ?? 0;

      final int cashInHandPaise = (openingFloatPaise + todayCashInPaise - todayExpensesPaise).clamp(0, 999999999999);

      // 4. Store Name
      String storeName = 'KamaiPlus';
      try {
        final profile = await LocalDatabase.instance.getStoreProfile();
        if (profile.storeName.trim().isNotEmpty) {
          storeName = profile.storeName.trim();
        }
      } catch (_) {}

      // Save to HomeWidget preferences
      await HomeWidget.saveWidgetData<String>('store_name', storeName);
      await HomeWidget.saveWidgetData<String>('today_sale', MoneyFormatter.formatINR(todaySalesPaise));
      await HomeWidget.saveWidgetData<String>('khata_due', MoneyFormatter.formatINR(totalKhataDuePaise));
      await HomeWidget.saveWidgetData<String>('cash_in_hand', MoneyFormatter.formatINR(cashInHandPaise));

      // Push update to Android AppWidgetManager with qualified names
      await HomeWidget.updateWidget(
        name: 'TodaySaleWidgetProvider',
        androidName: 'TodaySaleWidgetProvider',
        qualifiedAndroidName: 'com.kamaiplus.pos.widget.TodaySaleWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'QuickPosWidgetProvider',
        androidName: 'QuickPosWidgetProvider',
        qualifiedAndroidName: 'com.kamaiplus.pos.widget.QuickPosWidgetProvider',
      );
    } catch (_) {}
  }
}
