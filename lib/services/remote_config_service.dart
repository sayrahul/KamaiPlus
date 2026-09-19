import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  FirebaseRemoteConfig? _remoteConfig;
  bool _isInitialized = false;

  /// Default values, used offline and before the first successful fetch.
  ///
  /// **Deliberately short.** This map used to carry eleven parameters, of
  /// which exactly one (`gemini_api_key`) was ever read anywhere in the app —
  /// the rest were fetched on every launch and silently discarded. Worse, four
  /// of them looked like working controls while duplicating a mechanism that
  /// really is wired up:
  ///
  ///   * `app_announcement_*` / `banner_promo_*` — the live in-app banner
  ///     comes from Firestore `platform_settings/broadcast` (see
  ///     `FirestoreSyncService.broadcastNotifier`, rendered on Home Pulse).
  ///   * `force_update_required` / `min_supported_version` — force update
  ///     comes from Firestore `platform_settings/global_config` (see
  ///     `home_dashboard_screen.dart`'s `_forceUpdatePromptShown` flow).
  ///
  /// Anyone setting those in the Firebase Remote Config console would have
  /// watched nothing happen. They are removed rather than re-wired, because
  /// adding a second source of truth for "what banner is showing" is worse
  /// than having one. **Firestore `platform_settings` is the single source for
  /// broadcasts and force-update. Remote Config is for the values below.**
  static const Map<String, dynamic> _defaults = {
    'support_phone': '919595997711',
    'support_email': 'support@kamaiplus.com',
    // Integer RUPEES (not paise) — these are console-facing values a
    // non-engineer edits. Converted to paise at the point of use.
    // NOTE: `verifyRazorpayPayment` in functions/index.js holds its own
    // server-side minimum for each plan, so that a tampered client cannot pay
    // ₹1 and claim a year. Raising a price here is safe; lowering one below
    // that floor needs the function's PLAN_RULES updated and redeployed too.
    'pro_monthly_price': 199,
    'pro_annual_price': 1499,
    // Refer & Earn. The `referral` Cloud Function reads these same two keys
    // from the Remote Config template, so what the app promises is what the
    // server grants. reward = days for the merchant who SENT the invite;
    // referee bonus = days on top of the 7-day trial for the one who joined.
    'referral_reward_days': 30,
    'referral_referee_bonus_days': 15,
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

  /// Reads a string, falling back to the baked-in default when Remote Config
  /// has not fetched yet OR has fetched an empty value. `getString` returns ''
  /// for a parameter that exists but is blank, and '' is never a useful
  /// support phone number.
  String _string(String key) {
    final v = _remoteConfig?.getString(key).trim() ?? '';
    return v.isNotEmpty ? v : (_defaults[key] as String);
  }

  int _int(String key) {
    final v = _remoteConfig?.getInt(key) ?? 0;
    return v > 0 ? v : (_defaults[key] as int);
  }

  String get supportPhone => _string('support_phone');
  String get supportEmail => _string('support_email');

  /// Pro plan prices in integer RUPEES. Use [proMonthlyPricePaise] /
  /// [proAnnualPricePaise] for anything that touches money maths — this app's
  /// financial invariant is integer paise.
  int get proMonthlyPrice => _int('pro_monthly_price');
  int get proAnnualPrice => _int('pro_annual_price');

  int get proMonthlyPricePaise => proMonthlyPrice * 100;
  int get proAnnualPricePaise => proAnnualPrice * 100;

  int get referralRewardDays => _int('referral_reward_days');
  int get referralRefereeBonusDays => _int('referral_referee_bonus_days');

  String get geminiApiKey => _remoteConfig?.getString('gemini_api_key') ?? '';
}
