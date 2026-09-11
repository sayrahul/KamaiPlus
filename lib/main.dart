import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/database/local_database.dart';
import 'services/soundbox_service.dart';
import 'services/firestore_sync_service.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'services/shortcuts_service.dart';
import 'services/share_target_service.dart';
import 'services/home_widget_service.dart';
import 'services/workmanager_sync_service.dart';
import 'services/in_app_update_service.dart';
import 'views/splash/splash_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive status bar styling for clean light PWA theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // 1. Initialize High-Speed Local SQLite Database (User-scoped if logged in)
  final prefs = await SharedPreferences.getInstance();
  final cachedUserId = prefs.getString('auth_user_id');
  if (cachedUserId != null && cachedUserId.isNotEmpty) {
    await LocalDatabase.instance.switchUser(cachedUserId);
  } else {
    await LocalDatabase.instance.database;
  }

  // 2. Initialize Firebase Core Engine
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase.initializeApp warning: $e');
  }

  // 3. Initialize Voice Soundbox Audio Engine
  await SoundboxService.instance.init();

  // 4. Initialize Local Notifications & FCM Push Engine
  await NotificationService.instance.init();

  // 5. Initialize GoogleSignIn singleton (Non-blocking) — no unprompted dialog
  AuthService.instance.initGoogleSignIn();

  // 6. Initialize Cloud Firestore Realtime Sync Engine if already authenticated
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  if (isLoggedIn && cachedUserId != null && cachedUserId.isNotEmpty) {
    final savedBizId = prefs.getString('business_id') ?? 'biz_$cachedUserId';
    FirestoreSyncService.instance.initialize(businessId: savedBizId);
  }

  // 7. Initialize Native App Shortcuts & Share-To Receiver
  ShortcutsService.instance.init(rootNavigatorKey);
  ShareTargetService.instance.init(rootNavigatorKey);

  // 8. Update Home Screen Widgets with today's real-time metrics
  HomeWidgetService.instance.updateTodayMetrics();

  // 9. Initialize Android WorkManager for battery-friendly Doze-mode sync
  WorkmanagerSyncService.instance.initialize();

  // 10. Check for Google Play Store In-App Updates
  InAppUpdateService.instance.checkForUpdates();

  runApp(const KamaiPlusApp());
}

class KamaiPlusApp extends StatelessWidget {
  const KamaiPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'KamaiPlus POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
