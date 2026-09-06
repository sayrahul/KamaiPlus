import 'package:flutter/services.dart';

class SoundboxService {
  static final SoundboxService instance = SoundboxService._init();
  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/soundbox');

  SoundboxService._init();

  Future<void> init() async {}

  Future<void> announceHindiPayment(int paise, {String paymentMethod = 'UPI'}) async {
    try {
      final int rupees = paise ~/ 100;
      final String text = "कमाई प्लस पर $rupees रुपये प्राप्त हुए";
      await _channel.invokeMethod('speak', {'text': text, 'lang': 'hi'});
    } catch (_) {
      await announceEnglishPayment(paise, paymentMethod: paymentMethod);
    }
  }

  Future<void> announceEnglishPayment(int paise, {String paymentMethod = 'UPI'}) async {
    try {
      final int rupees = paise ~/ 100;
      final String text = "Received $rupees Rupees on Kamai Plus via $paymentMethod";
      await _channel.invokeMethod('speak', {'text': text, 'lang': 'en'});
    } catch (_) {}
  }
}
