import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  FirebaseRemoteConfig? _remoteConfig;
  bool _isInitialized = false;

  /// Default values for fallback when offline
  static const Map<String, dynamic> _defaults = {
    'support_phone': '919595997711',
    'support_email': 'support@kamaiplus.com',
    'pro_monthly_price': 299,
    'pro_annual_price': 1999,
    'referral_reward_days': 30,
    'app_announcement_enabled': false,
    'app_announcement_text': '',
    'force_update_required': false,
    'min_supported_version': '4.20.0',
    'banner_promo_active': false,
    'banner_promo_message': '',
    'gemini_api_key': '',
  };

  /// Initialize and fetch latest parameters from Firebase Remote Config
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;

      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 4),
        ),
      );

      await _remoteConfig!.setDefaults(_defaults);
      await _remoteConfig!.fetchAndActivate();
      _isInitialized = true;
      debugPrint('✓ Firebase Remote Config successfully initialized & fetched');
    } catch (e) {
      debugPrint('Firebase Remote Config init notice (using defaults): $e');
    }
  }

  // Getters with safe fallbacks
  String get supportPhone => _remoteConfig?.getString('support_phone') ?? _defaults['support_phone'];
  String get supportEmail => _remoteConfig?.getString('support_email') ?? _defaults['support_email'];
  int get proMonthlyPrice => _remoteConfig?.getInt('pro_monthly_price') ?? _defaults['pro_monthly_price'];
  int get proAnnualPrice => _remoteConfig?.getInt('pro_annual_price') ?? _defaults['pro_annual_price'];
  int get referralRewardDays => _remoteConfig?.getInt('referral_reward_days') ?? _defaults['referral_reward_days'];
  bool get isAnnouncementEnabled => _remoteConfig?.getBool('app_announcement_enabled') ?? false;
  String get announcementText => _remoteConfig?.getString('app_announcement_text') ?? '';
  bool get forceUpdateRequired => _remoteConfig?.getBool('force_update_required') ?? false;
  String get minSupportedVersion => _remoteConfig?.getString('min_supported_version') ?? '4.20.0';
  bool get isBannerPromoActive => _remoteConfig?.getBool('banner_promo_active') ?? false;
  String get bannerPromoMessage => _remoteConfig?.getString('banner_promo_message') ?? '';
  String get geminiApiKey => _remoteConfig?.getString('gemini_api_key') ?? '';
}
