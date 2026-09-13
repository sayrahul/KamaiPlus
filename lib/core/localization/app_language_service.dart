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
}

extension AppLocalizationsExtension on String {
  String get tr => AppLanguageService.instance.t(this);
}
