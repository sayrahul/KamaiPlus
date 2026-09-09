import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../views/dashboard/home_dashboard_screen.dart';
import '../views/tools/barcode_studio_screen.dart';
import '../views/reports/gst_reports_screen.dart';

/// App Shortcuts Service (Launcher Icon Long-Press & Deep Links)
class ShortcutsService {
  ShortcutsService._();
  static final ShortcutsService instance = ShortcutsService._();

  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/shortcuts');

  GlobalKey<NavigatorState>? _navigatorKey;

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _channel.setMethodCallHandler(_handleMethodCall);
    checkInitialShortcut();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onShortcutReceived') {
      final shortcut = call.arguments?.toString();
      if (shortcut != null && shortcut.isNotEmpty) {
        handleShortcut(shortcut);
      }
    }
  }

  Future<void> checkInitialShortcut() async {
    try {
      final shortcut = await _channel.invokeMethod<String>('getInitialShortcut');
      if (shortcut != null && shortcut.isNotEmpty) {
        // Post frame so navigation stack is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleShortcut(shortcut);
        });
      }
    } catch (_) {}
  }

  void handleShortcut(String shortcut) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;

    switch (shortcut.toLowerCase()) {
      case 'pos':
      case 'new_sale':
        HomeDashboardScreen.switchTab(context, 2);
        break;
      case 'khata':
      case 'add_khata':
        HomeDashboardScreen.switchTab(context, 3);
        break;
      case 'barcode':
      case 'scan_barcode':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarcodeStudioScreen()),
        );
        break;
      case 'reports':
      case 'today_report':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GstReportsScreen()),
        );
        break;
    }
  }
}
