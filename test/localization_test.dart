import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kamaiplus_pos/core/localization/app_strings.dart';
import 'package:kamaiplus_pos/core/localization/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguageService.instance.init();
  });

  test('Multi-language dictionaries provide accurate translations across English, Hindi, Marathi, and Gujarati', () async {
    // 1. Check supported languages
    expect(AppStrings.supportedLanguages.length, 4);
    final codes = AppStrings.supportedLanguages.map((l) => l.code).toList();
    expect(codes, containsAll(['en', 'hi', 'mr', 'gu']));

    // 2. Test English
    await AppLanguageService.instance.setLanguage('en');
    expect('nav_home'.tr, 'Home');
    expect('nav_billing'.tr, 'Billing');
    expect('pos_billing_title'.tr, 'Fast Billing Counter');
    expect('cash'.tr, 'Cash');

    // 3. Test Hindi
    await AppLanguageService.instance.setLanguage('hi');
    expect('nav_home'.tr, 'होम');
    expect('nav_billing'.tr, 'बिलिंग');
    expect('nav_khata'.tr, 'खाता');
    expect('cash'.tr, 'नकद (Cash)');

    // 4. Test Marathi
    await AppLanguageService.instance.setLanguage('mr');
    expect('nav_home'.tr, 'मुख्य');
    expect('nav_billing'.tr, 'बिलिंग');
    expect('nav_khata'.tr, 'खाते');
    expect('cash'.tr, 'रोख (Cash)');

    // 5. Test Gujarati
    await AppLanguageService.instance.setLanguage('gu');
    expect('nav_home'.tr, 'હોમ');
    expect('nav_billing'.tr, 'બિલિંગ');
    expect('nav_khata'.tr, 'ખાતાવહી');
    expect('cash'.tr, 'રોકડ (Cash)');

    // 6. Test fallback for unknown key
    expect('unknown_test_key_xyz'.tr, 'unknown_test_key_xyz');
  });
}
