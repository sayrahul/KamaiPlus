import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

class AppLanguageService {
  AppLanguageService._();
  static final AppLanguageService instance = AppLanguageService._();

  static const String _prefKey = 'app_selected_language';
  final ValueNotifier<String> currentLanguageNotifier = ValueNotifier<String>('en');

  String get currentLanguage => currentLanguageNotifier.value;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && AppStrings.supportedLanguages.any((l) => l.code == saved)) {
        currentLanguageNotifier.value = saved;
      }
    } catch (_) {}
  }

  Future<void> setLanguage(String langCode) async {
    if (!AppStrings.supportedLanguages.any((l) => l.code == langCode)) return;
    currentLanguageNotifier.value = langCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, langCode);
    } catch (_) {}
  }

  String t(String key) {
    return AppStrings.get(key, lang: currentLanguageNotifier.value);
  }

  /// The active language's full metadata (native name, beta flag, TTS locale).
  AppLanguage get current => AppStrings.languageFor(currentLanguageNotifier.value);

  /// Locale for the platform text-to-speech engine.
  ///
  /// The soundbox used to hardcode 'hi' and 'en', so a Tamil or Bengali shop
  /// heard its takings announced in Hindi — the one part of the app a busy
  /// shopkeeper listens to rather than reads.
  String get ttsLocale => current.ttsLocale;

  /// True when the active language has not been reviewed by a speaker.
  bool get isBetaLanguage => current.isBeta;
}

extension AppLocalizationsExtension on String {
  String get tr => AppLanguageService.instance.t(this);
}
