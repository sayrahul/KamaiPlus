import 'package:flutter/services.dart';

/// Service to control app lifecycle on Android
/// Allows minimizing the app to background instead of destroying the process on Back tap.
class AppControlService {
  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/app_control');

  static Future<void> minimizeToBackground() async {
    try {
      await _channel.invokeMethod('moveTaskToBack');
    } catch (_) {
      SystemNavigator.pop();
    }
  }
}
