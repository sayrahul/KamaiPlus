import 'package:flutter/services.dart';

class NativeNotificationService {
  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/notifications');

  /// Displays an authentic Android status bar notification
  static Future<bool> showNotification({
    required String title,
    required String body,
    int? id,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('showNotification', {
        'title': title,
        'body': body,
        'id': id ?? DateTime.now().millisecondsSinceEpoch % 100000,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Convenience shortcut for Sale Invoice notification
  static Future<void> notifySaleCompleted({
    required String invoiceNumber,
    required String amountFormatted,
    required String paymentMode,
  }) async {
    await showNotification(
      title: '🧾 Bill Completed: #$invoiceNumber',
      body: 'Received $amountFormatted via ${paymentMode.toUpperCase()}. Recorded in local ledger.',
    );
  }

  /// Convenience shortcut for Cloud Sync
  static Future<void> notifyCloudSynced({required int count}) async {
    await showNotification(
      title: '☁️ Cloud Sync Completed',
      body: '$count record(s) safely synced with Kamai+ Firestore Cloud Backup.',
    );
  }

  /// Convenience shortcut for WhatsApp dispatch
  static Future<void> notifyWhatsAppSent({
    required String invoiceNumber,
    required String phone,
  }) async {
    await showNotification(
      title: '💬 WhatsApp Receipt Dispatched',
      body: 'Tax invoice #$invoiceNumber successfully sent to +91 $phone.',
    );
  }

  /// Yesterday's sales recap — shown once, the first time the app is opened
  /// each day (see `daily_summary_service.dart`). One combined notification
  /// covering total sales, bill count, and the cash/UPI split, so an owner
  /// checking overnight/first-thing-in-the-morning doesn't have to open the
  /// app and dig through Transactions to see how yesterday went.
  static Future<void> notifyDailySummary({
    required String totalFormatted,
    required int billCount,
    required String cashFormatted,
    required String upiFormatted,
  }) async {
    await showNotification(
      id: 100001,
      title: '☀️ Kal ka Business Summary',
      body: '$totalFormatted total ($billCount bills) • Cash $cashFormatted • UPI $upiFormatted',
    );
  }
}
