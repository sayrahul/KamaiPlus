import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/database/local_database.dart';
import 'firestore_sync_service.dart';
import 'remote_config_service.dart';

class ReferralStats {
  final int totalInvited;
  final int storesActivated;
  final int freeDaysEarned;
  final String? appliedReferralCode;

  /// This merchant's own code; empty until the server has confirmed one.
  final String code;

  /// False when the figures come from the on-device cache (offline).
  final bool isLive;

  /// A code claimed while offline, waiting to reach the server.
  final String? pendingReferralCode;

  ReferralStats({
    required this.totalInvited,
    required this.storesActivated,
    required this.freeDaysEarned,
    this.appliedReferralCode,
    this.code = '',
    this.isLive = false,
    this.pendingReferralCode,
  });
}

/// Outcome of claiming a referral code.
class ReferralClaimResult {
  final bool success;
  final String message;

  /// True when nothing was decided (offline, signed out, server hiccup) and
  /// the same claim should simply be tried again later.
  final bool retryable;

  /// Server error code (`NOT_FOUND`, `SELF`, `ALREADY_REDEEMED`, ...).
  final String? errorCode;

  /// The merchant's Pro expiry after the bonus, as stored in the cloud.
  final DateTime? proExpiry;
  final int bonusDays;

  const ReferralClaimResult({
    required this.success,
    required this.message,
    this.retryable = false,
    this.errorCode,
    this.proExpiry,
    this.bonusDays = 0,
  });
}

/// Raw reply from the `referral` Cloud Function.
class ReferralHttpResponse {
  final int statusCode;
  final Map<String, dynamic> json;

  const ReferralHttpResponse(this.statusCode, this.json);
}

typedef ReferralTransport = Future<ReferralHttpResponse> Function(Map<String, dynamic> body);

class _NotSignedIn implements Exception {}

/// Refer & Earn.
///
/// The offer: the merchant who JOINS with a code keeps the 7-day welcome
/// trial and gets [refereeBonusDays] (15) more; the merchant who SENT the
/// invite gets [referrerRewardDays] (30) more, per store that joins.
///
/// Every grant is made by the `referral` Cloud Function (functions/index.js,
/// logic in functions/referral_core.js). It used to be done from the phone,
/// reading `referral_codes/*` and writing the REFERRER's `businesses/*` doc
/// directly — firestore.rules deny both, so claims always failed with "check
/// your internet" and no referrer was ever credited. The server writes Pro
/// days to both merchants' cloud docs; each phone picks its own up through
/// FirestoreSyncService's live business listener, and the claiming phone
/// also applies its grant immediately so the countdown moves at once.
class ReferralService {
  ReferralService._();
  static final ReferralService instance = ReferralService._();

  static const String endpoint = 'https://us-central1-kamaiplus.cloudfunctions.net/referral';

  static const String _prefCodeKey = 'merchant_referral_code';
  static const String _prefInvitedKey = 'referral_invited_count';
  static const String _prefActivatedKey = 'referral_activated_count';
  static const String _prefFreeDaysKey = 'referral_free_days_earned';
  static const String _prefAppliedCodeKey = 'referral_applied_code';
  static const String _prefPendingCodeKey = 'pending_referral_code';

  /// Set once the server has a record of this device's applied code. Codes
  /// applied before the server flow existed never reached it (see above), so
  /// an applied code WITHOUT this flag is re-sent once.
  static const String _prefAppliedConfirmedKey = 'referral_applied_confirmed';

  static final RegExp _codePattern = RegExp(r'^KAMAI[A-Z0-9]{4,8}$');

  int get referrerRewardDays => RemoteConfigService.instance.referralRewardDays;
  int get refereeBonusDays => RemoteConfigService.instance.referralRefereeBonusDays;

  /// Replaced in tests; production posts to [endpoint].
  @visibleForTesting
  ReferralTransport? transportOverride;

  static String normalizeCode(String raw) => raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static bool isWellFormedCode(String code) => _codePattern.hasMatch(code);

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Future<ReferralHttpResponse> _post(Map<String, dynamic> body) async {
    final override = transportOverride;
    if (override != null) return override(body);

    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null || idToken.isEmpty) throw _NotSignedIn();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> json = {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
      return ReferralHttpResponse(res.statusCode, json);
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // My code & stats
  // ---------------------------------------------------------------------------

  /// Fetches this merchant's code and stats from the server (creating the
  /// code on first use), caching both. Offline, returns the cached copy.
  Future<ReferralStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await _post({
        'action': 'status',
        if ((prefs.getString(_prefCodeKey) ?? '').isNotEmpty) 'preferred_code': prefs.getString(_prefCodeKey),
      });
      if (res.statusCode == 200 && (res.json['code'] as String? ?? '').isNotEmpty) {
        final j = res.json;
        await prefs.setString(_prefCodeKey, j['code'] as String);
        await prefs.setInt(_prefActivatedKey, (j['activated_count'] as num?)?.toInt() ?? 0);
        await prefs.setInt(_prefFreeDaysKey, (j['free_days_earned'] as num?)?.toInt() ?? 0);
        final applied = j['applied_code'] as String?;
        if (applied != null && applied.isNotEmpty) {
          await prefs.setString(_prefAppliedCodeKey, applied);
          await prefs.setBool(_prefAppliedConfirmedKey, true);
        }
        return _cachedStats(prefs, isLive: true);
      }
    } catch (e) {
      debugPrint('Referral status notice: $e');
    }
    return _cachedStats(prefs, isLive: false);
  }

  /// The last known stats, without touching the network.
  Future<ReferralStats> getCachedStats() async =>
      _cachedStats(await SharedPreferences.getInstance(), isLive: false);

  ReferralStats _cachedStats(SharedPreferences prefs, {required bool isLive}) {
    final applied = prefs.getString(_prefAppliedCodeKey);
    return ReferralStats(
      totalInvited: prefs.getInt(_prefInvitedKey) ?? 0,
      storesActivated: prefs.getInt(_prefActivatedKey) ?? 0,
      freeDaysEarned: prefs.getInt(_prefFreeDaysKey) ?? 0,
      appliedReferralCode: (applied != null && applied.isNotEmpty) ? applied : null,
      code: prefs.getString(_prefCodeKey) ?? '',
      isLive: isLive,
      pendingReferralCode: prefs.getString(_prefPendingCodeKey),
    );
  }

  /// This merchant's code, or '' if it has never been confirmed and the
  /// server cannot be reached.
  Future<String> getMerchantReferralCode() async => (await getStats()).code;

  // ---------------------------------------------------------------------------
  // Sharing
  // ---------------------------------------------------------------------------

  String buildInviteMessage(String code, {String? storeName}) {
    final name = storeName != null && storeName.isNotEmpty ? storeName : 'my retail store';
    final total = 7 + refereeBonusDays;
    return 'Hello! 🙏 I am using *Kamai+ POS Billing App* for $name.\n\n'
        '• 100% Offline & Fast Counter Billing\n'
        '• 1-Click WhatsApp Invoices & Thermal Printing\n'
        '• Customer Credit & Udhar Ledger\n'
        '• Daily Profit, Stock & GST Reports\n\n'
        '👉 Sign up with my referral code and get *$total Days FREE PRO* '
        '(7-day trial + $refereeBonusDays bonus days)!\n\n'
        '📲 Download App: https://play.google.com/store/apps/details?id=com.kamaiplus.pos&referrer=$code\n'
        '🎁 Referral Code: *$code*';
  }

  /// 1-Tap Share on WhatsApp. The invited count only moves once the share
  /// actually opened.
  Future<bool> shareOnWhatsApp(String code, {String? storeName}) async {
    final message = buildInviteMessage(code, storeName: storeName);
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('whatsapp://send?text=$encoded');

    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) await _incrementInvitedCount();
      return launched;
    }
    final webUri = Uri.parse('https://api.whatsapp.com/send?text=$encoded');
    if (await canLaunchUrl(webUri)) {
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (launched) await _incrementInvitedCount();
      return launched;
    }
    await shareGeneral(code, storeName: storeName);
    return true;
  }

  /// Share via the system sheet; counted only if the share went through.
  Future<void> shareGeneral(String code, {String? storeName}) async {
    final message = buildInviteMessage(code, storeName: storeName);
    final result = await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: 'Invite to Kamai+ POS - Get ${7 + refereeBonusDays} Days Free PRO',
      ),
    );
    if (result.status == ShareResultStatus.success) {
      await _incrementInvitedCount();
    }
  }

  Future<void> _incrementInvitedCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefInvitedKey, (prefs.getInt(_prefInvitedKey) ?? 0) + 1);
  }

  Future<void> copyCode(String code) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: code));
  }

  // ---------------------------------------------------------------------------
  // Claiming a friend's code
  // ---------------------------------------------------------------------------

  /// Claims [rawCode]: the server credits this merchant +[refereeBonusDays]
  /// (after the 7-day trial) and the code's owner +[referrerRewardDays].
  /// If only the connection failed, the code is kept and claimed
  /// automatically later — which is what the returned message promises.
  Future<ReferralClaimResult> applyReferralCode(String rawCode) async {
    final result = await _claim(rawCode, isRetryOfSavedClaim: false);
    if (result.retryable) await savePendingReferral(rawCode);
    return result;
  }

  Future<ReferralClaimResult> _claim(String rawCode, {required bool isRetryOfSavedClaim}) async {
    final code = normalizeCode(rawCode);
    if (code.isEmpty) {
      return const ReferralClaimResult(success: false, message: 'Please enter a referral code');
    }
    if (!isWellFormedCode(code)) {
      return const ReferralClaimResult(
        success: false,
        errorCode: 'INVALID_FORMAT',
        message: 'That is not a valid Kamai+ referral code (it looks like KAMAI7XK2).',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    if (code == prefs.getString(_prefCodeKey)) {
      return const ReferralClaimResult(
        success: false,
        errorCode: 'SELF',
        message: 'You cannot use your own referral code!',
      );
    }
    final applied = prefs.getString(_prefAppliedCodeKey);
    final appliedConfirmed = prefs.getBool(_prefAppliedConfirmedKey) ?? false;
    if (!isRetryOfSavedClaim && applied != null && applied.isNotEmpty) {
      return ReferralClaimResult(
        success: false,
        errorCode: 'ALREADY_REDEEMED',
        message: 'You have already claimed a referral code ($applied).',
      );
    }

    final ReferralHttpResponse res;
    try {
      res = await _post({'action': 'redeem', 'code': code});
    } on _NotSignedIn {
      return const ReferralClaimResult(
        success: false,
        retryable: true,
        message: 'Please sign in to claim a referral code. We will add your bonus as soon as you do.',
      );
    } catch (e) {
      debugPrint('Referral redeem network notice: $e');
      return const ReferralClaimResult(
        success: false,
        retryable: true,
        message: 'No internet connection. Your referral bonus will be added automatically once you are online.',
      );
    }

    if (res.statusCode == 200 && res.json['ok'] == true) {
      final expiry = await _applyGrantLocally(res.json, code);
      await prefs.setString(_prefAppliedCodeKey, code);
      await prefs.setBool(_prefAppliedConfirmedKey, true);
      final bonus = (res.json['referee_bonus_days'] as num?)?.toInt() ?? refereeBonusDays;
      final till = expiry != null ? ' Free Pro is now valid till ${DateFormat('d MMM yyyy').format(expiry)}.' : '';
      return ReferralClaimResult(
        success: true,
        message: '🎉 Referral bonus activated! +$bonus days of Free PRO added to your store.$till',
        proExpiry: expiry,
        bonusDays: bonus,
      );
    }

    final serverCode = res.json['code'] as String?;
    final serverMessage = res.json['error'] as String?;
    final retryable = res.statusCode >= 500 || res.statusCode == 401 || res.statusCode == 429;

    if (!retryable && isRetryOfSavedClaim && applied == code && !appliedConfirmed) {
      // A code "applied" under the old phone-only flow that the server never
      // saw. If the server now rejects it, it was never really applied — let
      // the merchant enter a valid one. ALREADY_REDEEMED means the server has
      // a different code on record; the next status refresh stores that one.
      if (serverCode != 'ALREADY_REDEEMED') await prefs.remove(_prefAppliedCodeKey);
      await prefs.setBool(_prefAppliedConfirmedKey, true);
    }

    return ReferralClaimResult(
      success: false,
      retryable: retryable,
      errorCode: serverCode,
      message: serverMessage ??
          (retryable
              ? 'Referral service is busy. Your bonus will be added automatically — please check again shortly.'
              : 'Could not apply this referral code.'),
    );
  }

  /// Mirrors the server's grant into the local profile right away, so the
  /// Pro countdown moves before the cloud listener catches up. Never
  /// shortens a longer Pro the device already has.
  Future<DateTime?> _applyGrantLocally(Map<String, dynamic> json, String code) async {
    final expiry = DateTime.tryParse(json['pro_expiry'] as String? ?? '');
    if (expiry == null) return null;

    final current = await LocalDatabase.instance.getStoreProfile();
    final currentExpiry = current.isProEffective ? current.proExpiryDate : null;
    if (current.isProEffective && (currentExpiry == null || currentExpiry.isAfter(expiry))) {
      return currentExpiry;
    }

    final keepPaid = current.isProEffective && current.isPaidPlan;
    await LocalDatabase.instance.activateProMembership(
      plan: keepPaid ? current.proPlan : (json['pro_plan'] as String? ?? 'referral_bonus'),
      paymentId: keepPaid ? current.razorpayPaymentId : 'ref_bonus_$code',
      expiryDate: expiry,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro', true);
    FirestoreSyncService.isProNotifier.value = true;
    return expiry;
  }

  // ---------------------------------------------------------------------------
  // Claims that could not finish yet (signup offline, older app versions)
  // ---------------------------------------------------------------------------

  /// Remembers a code entered at signup, to be claimed by
  /// [redeemPendingReferral] — immediately if online, otherwise later.
  Future<void> savePendingReferral(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (code.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPendingCodeKey, code);
  }

  Future<ReferralClaimResult?>? _pendingRun;

  /// Claims a saved signup code, or re-sends a code applied under the old
  /// phone-only flow. Returns null when there is nothing to do. Safe to call
  /// on every launch; concurrent calls share one run.
  Future<ReferralClaimResult?> redeemPendingReferral() {
    return _pendingRun ??= _redeemPending().whenComplete(() => _pendingRun = null);
  }

  Future<ReferralClaimResult?> _redeemPending() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_prefPendingCodeKey);
    if (pending != null && pending.isNotEmpty) {
      final result = await _claim(pending, isRetryOfSavedClaim: false);
      if (!result.retryable) await prefs.remove(_prefPendingCodeKey);
      return result;
    }

    final legacy = prefs.getString(_prefAppliedCodeKey);
    final confirmed = prefs.getBool(_prefAppliedConfirmedKey) ?? false;
    if (legacy != null && legacy.isNotEmpty && !confirmed) {
      return _claim(legacy, isRetryOfSavedClaim: true);
    }
    return null;
  }
}
