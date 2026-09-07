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
import 'views/splash/splash_screen.dart';

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

  // 1. Initialize High-Speed Local SQLite Database
  await LocalDatabase.instance.database;

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

  // 5. Silent Auth Check (Non-blocking) — init GoogleSignIn singleton first (v7 requirement)
  AuthService.instance.initGoogleSignIn().then((_) => AuthService.instance.signInSilently());

  // 6. Initialize Cloud Firestore Realtime Sync Engine in Background
  final prefs = await SharedPreferences.getInstance();
  final savedBizId = prefs.getString('business_id') ?? 'biz_starter_pos';
  FirestoreSyncService.instance.initialize(businessId: savedBizId);

  runApp(const KamaiPlusApp());
}

class KamaiPlusApp extends StatelessWidget {
  const KamaiPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KamaiPlus POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
