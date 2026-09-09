import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/database/local_database.dart';
import 'firestore_sync_service.dart';
import 'home_widget_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final cachedUserId = prefs.getString('auth_user_id');
      final savedBizId = prefs.getString('business_id');

      if (!isLoggedIn || cachedUserId == null || cachedUserId.isEmpty) {
        return true; // Don't run background sync if unauthenticated
      }

      // Switch SQLite connection to the logged-in merchant's database file
      await LocalDatabase.instance.switchUser(cachedUserId);

      // 1. Guaranteed background sync to Cloud Firestore for actual business
      final bizId = (savedBizId != null && savedBizId.isNotEmpty)
          ? savedBizId
          : 'biz_$cachedUserId';
      await FirestoreSyncService.syncAllPending(businessId: bizId);

      // 2. Refresh Android Home Screen Widgets
      await HomeWidgetService.instance.updateTodayMetrics();
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// WorkManager Service for reliable, battery-friendly Doze-mode background synchronization
class WorkmanagerSyncService {
  WorkmanagerSyncService._();
  static final WorkmanagerSyncService instance = WorkmanagerSyncService._();

  static const String periodicSyncTask = 'com.kamaiplus.pos.periodicSync';

  Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        'kamai_bg_sync',
        periodicSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {}
  }

  /// Cancels periodic background work on logout
  Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName('kamai_bg_sync');
    } catch (_) {}
  }
}
