import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundboxEvent {
  final int paise;
  final String paymentMethod;
  final DateTime timestamp;

  SoundboxEvent({
    required this.paise,
    required this.paymentMethod,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class SoundboxService {
  static final SoundboxService instance = SoundboxService._init();
  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/soundbox');

  /// Real-time notifier for visual soundbox ripple wave UI banner
  final ValueNotifier<SoundboxEvent?> activeAnnouncementNotifier = ValueNotifier<SoundboxEvent?>(null);

  bool _isAudioEnabled = true;
  bool get isAudioEnabled => _isAudioEnabled;

  SoundboxService._init() {
    init();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isAudioEnabled = prefs.getBool('soundbox_audio_enabled') ?? true;
    } catch (_) {}
  }

  Future<void> setAudioEnabled(bool enabled) async {
    _isAudioEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('soundbox_audio_enabled', enabled);
    } catch (_) {}
  }

  void dismissAnnouncement() {
    activeAnnouncementNotifier.value = null;
  }

  Future<void> announceHindiPayment(int paise, {String paymentMethod = 'UPI'}) async {
    // Trigger visual wave ripple overlay immediately
    activeAnnouncementNotifier.value = SoundboxEvent(paise: paise, paymentMethod: paymentMethod);

    if (!_isAudioEnabled) return;
    try {
      final int rupees = paise ~/ 100;
      final String text = "कमाई प्लस पर $rupees रुपये प्राप्त हुए";
      await _channel.invokeMethod('speak', {'text': text, 'lang': 'hi'});
    } catch (_) {
      await announceEnglishPayment(paise, paymentMethod: paymentMethod);
    }
  }

  Future<void> announceEnglishPayment(int paise, {String paymentMethod = 'UPI'}) async {
    // Trigger visual wave ripple overlay immediately
    activeAnnouncementNotifier.value = SoundboxEvent(paise: paise, paymentMethod: paymentMethod);

    if (!_isAudioEnabled) return;
    try {
      final int rupees = paise ~/ 100;
      final String text = "Received $rupees Rupees on Kamai Plus via $paymentMethod";
      await _channel.invokeMethod('speak', {'text': text, 'lang': 'en'});
    } catch (_) {}
  }

  Future<void> speakCustom(String text, {String lang = 'hi'}) async {
    if (!_isAudioEnabled) return;
    try {
      await _channel.invokeMethod('speak', {'text': text, 'lang': lang});
    } catch (_) {}
  }
}
