import 'package:home_widget/home_widget.dart';
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
      final todayStr = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD

      // 1. Today's Completed Sales (Paise)
      final salesResult = await db.rawQuery('''
        SELECT SUM(total_amount_paise) as total
        FROM sales
        WHERE created_at LIKE ? AND status = 'COMPLETED'
      ''', ['$todayStr%']);
      final int todaySalesPaise = (salesResult.first['total'] as int?) ?? 0;

      // 2. Total Khata Due (Paise)
      final khataResult = await db.rawQuery('''
        SELECT SUM(current_balance_paise) as total_due
        FROM customers
        WHERE current_balance_paise > 0
      ''');
      final int totalKhataDuePaise = (khataResult.first['total_due'] as int?) ?? 0;

      // 3. Cash-in-Hand (From Active Cash Register Shift or Today's Cash Sales)
      int cashInHandPaise = 0;
      final shiftResult = await db.rawQuery('''
        SELECT opening_cash_paise, cash_sales_paise, cash_expenses_paise
        FROM cash_register_shifts
        WHERE status = 'OPEN'
        ORDER BY opened_at DESC LIMIT 1
      ''');
      if (shiftResult.isNotEmpty) {
        final row = shiftResult.first;
        final open = (row['opening_cash_paise'] as int?) ?? 0;
        final cashSales = (row['cash_sales_paise'] as int?) ?? 0;
        final cashExp = (row['cash_expenses_paise'] as int?) ?? 0;
        cashInHandPaise = open + cashSales - cashExp;
      } else {
        // Fallback: Cash sales today
        final cashSalesResult = await db.rawQuery('''
          SELECT SUM(
            CASE 
              WHEN payment_method = 'CASH' THEN total_amount_paise
              ELSE split_cash_paise
            END
          ) as total_cash
          FROM sales
          WHERE created_at LIKE ? AND status = 'COMPLETED'
        ''', ['$todayStr%']);
        cashInHandPaise = (cashSalesResult.first['total_cash'] as int?) ?? 0;
      }

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

      // Push update to Android AppWidgetManager
      await HomeWidget.updateWidget(
        name: 'TodaySaleWidgetProvider',
        androidName: 'TodaySaleWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'QuickPosWidgetProvider',
        androidName: 'QuickPosWidgetProvider',
      );
    } catch (_) {}
  }
}
