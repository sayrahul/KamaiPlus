import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/money_formatter.dart';
import 'firestore_sync_service.dart';

/// Top-level background FCM message handler (Must be outside of any class)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling FCM background message: ${message.messageId} - ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static const String channelId = 'kamai_pos_channel';
  static const String channelName = 'KamaiPlus POS Alerts & Invoices';
  static const String channelDescription = 'Realtime notifications for counter sales, invoices, stock radar, and shift alerts';

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Initialize Local Notifications & Firebase Cloud Messaging
  Future<void> init() async {
    try {
      // 1. Android & iOS Initialization Settings
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification clicked with payload: ${response.payload}');
        },
      );

      // 2. Create High-Priority Notification Channel for Android 8.0+
      final AndroidNotificationChannel channel = const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // 3. Request Notification Permission (Android 13+ & iOS)
      final NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('User granted notification permission: ${settings.authorizationStatus}');

      // 4. Register Background FCM Message Handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 5. Retrieve & Cache FCM Device Token
      try {
        _fcmToken = await _fcm.getToken();
        if (_fcmToken != null) {
          debugPrint('FCM Device Token: $_fcmToken');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('fcm_token', _fcmToken!);

          // Trigger background sync to push updated FCM token to cloud
          FirestoreSyncService.syncAllPending();
        }

        // Subscribe to Admin broadcast & announcement topics
        try {
          await _fcm.subscribeToTopic('all_merchants');
          await _fcm.subscribeToTopic('announcements');
          debugPrint('Subscribed to all_merchants and announcements topics');
        } catch (topicErr) {
          debugPrint('Could not subscribe to FCM topics: $topicErr');
        }
      } catch (tokenErr) {
        debugPrint('Could not fetch FCM token (offline or services unavailable): $tokenErr');
      }

      // 6. Listen for Token Refresh
      _fcm.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);
        debugPrint('FCM Token Refreshed: $newToken');
      });

      // 7. Handle Foreground Messages (Display as Heads-Up Banner)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground FCM Message received: ${message.notification?.title}');
        final notification = message.notification;
        if (notification != null) {
          showLocalNotification(
            id: message.hashCode,
            title: notification.title ?? 'KamaiPlus POS',
            body: notification.body ?? '',
            payload: jsonEncode(message.data),
          );
        }
      });

      // 8. Handle When User Taps Notification While App in Background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification opened from background: ${message.data}');
      });

    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// Show standard high-priority local notification banner
  Future<void> showLocalNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: payload,
    );
  }

  /// Specialized Helper: Sale Bill Completed Notification
  Future<void> showSaleNotification({
    required String invoiceNo,
    required int totalPaise,
    String? customerName,
  }) async {
    final formattedAmount = MoneyFormatter.formatINR(totalPaise);
    final customerInfo = (customerName != null && customerName.isNotEmpty) ? ' • $customerName' : '';
    await showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '✅ Bill Generated: $invoiceNo',
      body: '$formattedAmount received successfully$customerInfo',
      payload: jsonEncode({'type': 'sale', 'invoice': invoiceNo}),
    );
  }

  /// Specialized Helper: Low Stock Radar Notification
  Future<void> showStockAlertNotification({
    required String productName,
    required double remainingStock,
  }) async {
    await showLocalNotification(
      id: productName.hashCode,
      title: '⚠️ Low Stock Alert: $productName',
      body: 'Only ${remainingStock.toStringAsFixed(0)} units left in inventory. Restock soon!',
      payload: jsonEncode({'type': 'low_stock', 'product': productName}),
    );
  }

  /// Specialized Helper: Shift / Cash Drawer Report Notification
  Future<void> showShiftReportNotification({
    required int closingCashPaise,
    required int differencePaise,
  }) async {
    final cashText = MoneyFormatter.formatINR(closingCashPaise);
    final diffText = differencePaise == 0
        ? 'Drawer Balanced (₹0 diff)'
        : (differencePaise > 0
            ? 'Excess: +${MoneyFormatter.formatINR(differencePaise)}'
            : 'Shortage: -${MoneyFormatter.formatINR(differencePaise.abs())}');

    await showLocalNotification(
      id: 9999,
      title: '💼 Shift Closed: $cashText in Galla',
      body: 'Daily Cash reconciliation complete. $diffText',
      payload: jsonEncode({'type': 'shift_close'}),
    );
  }

  /// Test Notification trigger (for Settings verification)
  Future<void> showTestNotification() async {
    await showLocalNotification(
      id: 1001,
      title: '🔔 KamaiPlus POS Notification Active',
      body: 'Local in-app notifications and Firebase Cloud Messaging are running smoothly!',
      payload: jsonEncode({'type': 'test'}),
    );
  }
}
