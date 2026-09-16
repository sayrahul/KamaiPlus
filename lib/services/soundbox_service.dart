import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/localization/app_language_service.dart';

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

  /// Announces a payment in the merchant's chosen language.
  ///
  /// Kept under the old name so every existing call site still compiles, but it
  /// is no longer Hindi-only: the language and the TTS voice both follow
  /// [AppLanguageService]. A Tamil or Bengali shop used to hear its takings
  /// read out in Hindi — and the soundbox is the one part of this app a busy
  /// shopkeeper listens to instead of reading, so getting it wrong is worse
  /// than an untranslated label.
  Future<void> announceHindiPayment(int paise, {String paymentMethod = 'UPI'}) =>
      announcePayment(paise, paymentMethod: paymentMethod);

  Future<void> announcePayment(int paise, {String paymentMethod = 'UPI'}) async {
    // Trigger visual wave ripple overlay immediately
    activeAnnouncementNotifier.value = SoundboxEvent(paise: paise, paymentMethod: paymentMethod);

    if (!_isAudioEnabled) return;
    try {
      final int rupees = paise ~/ 100;
      final lang = AppLanguageService.instance;
      // "Received <n> rupees" in the active language. Built from the same
      // string catalog as the rest of the app, so adding a language gives it a
      // voice at the same time.
      final received = lang.t('voice_received');
      final rupeesWord = lang.t('voice_rupees');
      final text = lang.currentLanguage == 'en'
          ? 'Received $rupees Rupees on Kamai Plus via $paymentMethod'
          : '$rupees $rupeesWord $received';

      await _channel.invokeMethod('speak', {
        'text': text,
        'lang': lang.ttsLocale,
      });
    } catch (_) {
      // A device with no voice for that language must still make the sale
      // audible rather than going silent.
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

  /// Speaks arbitrary text. Defaults to the merchant's chosen language rather
  /// than a hardcoded 'hi'.
  Future<void> speakCustom(String text, {String? lang}) async {
    if (!_isAudioEnabled) return;
    try {
      await _channel.invokeMethod('speak', {
        'text': text,
        'lang': lang ?? AppLanguageService.instance.ttsLocale,
      });
    } catch (_) {}
  }
}
