import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Beep + vibration for barcode scans, like a counter scanner.
///
/// The beep is a native `ToneGenerator` tone (`beep` on the soundbox channel
/// in MainActivity.java) — short and high for a good scan, a low buzz for a
/// problem — so the cashier knows the result without looking at the screen.
/// Falls back to the system click if the native side is unavailable.
class ScanFeedbackService {
  ScanFeedbackService._();
  static final ScanFeedbackService instance = ScanFeedbackService._();

  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/soundbox');
  static const String _prefKey = 'pos_scan_beep_enabled';

  final ValueNotifier<bool> beepEnabled = ValueNotifier<bool>(true);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      beepEnabled.value = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  Future<void> setBeepEnabled(bool enabled) async {
    beepEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}
  }

  Future<void> success() async {
    HapticFeedback.lightImpact();
    await _beep('ok');
  }

  Future<void> error() async {
    HapticFeedback.heavyImpact();
    await _beep('error');
  }

  Future<void> _beep(String kind) async {
    if (!beepEnabled.value) return;
    try {
      final played = await _channel.invokeMethod<bool>('beep', {'kind': kind});
      if (played == true) return;
    } catch (_) {}
    SystemSound.play(SystemSoundType.click);
  }
}
