import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
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
      // 1. Guaranteed background sync to Cloud Firestore
      await FirestoreSyncService.syncAllPending();
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
}
