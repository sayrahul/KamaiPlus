import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/database/local_database.dart';
import 'remote_config_service.dart';

class ReferralStats {
  final int totalInvited;
  final int storesActivated;
  final int freeDaysEarned;
  final String? appliedReferralCode;

  ReferralStats({
    required this.totalInvited,
    required this.storesActivated,
    required this.freeDaysEarned,
    this.appliedReferralCode,
  });
}

class ReferralService {
  ReferralService._();
  static final ReferralService instance = ReferralService._();

  static const String _prefInvitedKey = 'referral_invited_count';
  static const String _prefActivatedKey = 'referral_activated_count';
  static const String _prefFreeDaysKey = 'referral_free_days_earned';
  static const String _prefAppliedCodeKey = 'referral_applied_code';
  /// Days of free PRO granted per activation, for BOTH sides of a referral.
  /// Read from Firebase Remote Config (`referral_reward_days`) so a growth
  /// campaign can change the offer without an app release; 30 is the offline
  /// fallback and the value the invite copy quoted when this was a constant.
  static int get _rewardDaysPerActivation =>
      RemoteConfigService.instance.referralRewardDays;

  /// Generates or retrieves the unique referral code for the current merchant.
  /// On first run, generates a unique code and registers it in Firestore.
  /// Existing locally-cached codes are preserved and registered if not yet in Firestore.
  Future<String> getMerchantReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString('merchant_referral_code');

    if (code != null && code.isNotEmpty) {
      // Ensure existing code is registered in Firestore (one-time migration)
      await _ensureCodeRegistered(code);
      return code;
    }

    // Generate new unique code: KAMAI + 4 random alphanumeric chars
    code = await _generateUniqueCode();
    await prefs.setString('merchant_referral_code', code);
    await _registerCodeInFirestore(code);
    return code;
  }

  /// Generates a random 4-character alphanumeric suffix and checks Firestore
  /// for uniqueness. Retries up to 5 times on collision.
  Future<String> _generateUniqueCode() async {
    for (int attempt = 0; attempt < 5; attempt++) {
      final suffix = _generateRandomSuffix(4);
      final candidate = 'KAMAI$suffix';
      try {
        final doc = await FirebaseFirestore.instance
            .collection('referral_codes')
            .doc(candidate)
            .get();
        if (!doc.exists) return candidate;
      } catch (_) {
        // Offline fallback: use phone-based code like legacy behavior
        final profile = await LocalDatabase.instance.getStoreProfile();
        String fallbackSuffix = 'PLUS';
        if (profile.phone.trim().length >= 4) {
          final p = profile.phone.trim();
          fallbackSuffix = p.substring(p.length - 4);
        }
        return 'KAMAI$fallbackSuffix'.toUpperCase();
      }
    }
    // Extremely unlikely: 5 collisions, fallback to 6-char suffix
    return 'KAMAI${_generateRandomSuffix(6)}';
  }

  /// Generates random alphanumeric string of given length (A-Z, 0-9)
  String _generateRandomSuffix(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed ambiguous: I,O,0,1
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Registers a referral code in Firestore if not already present.
  Future<void> _registerCodeInFirestore(String code) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final profile = await LocalDatabase.instance.getStoreProfile();
      await FirebaseFirestore.instance
          .collection('referral_codes')
          .doc(code)
          .set({
        'merchant_id': uid ?? '',
        'phone': profile.phone,
        'store_name': profile.storeName,
        'created_at': FieldValue.serverTimestamp(),
        'activated_count': 0,
        'free_days_earned': 0,
      });
    } catch (_) {
      // Silently fail — will retry on next app open via _ensureCodeRegistered
    }
  }

  /// One-time migration: ensures a locally-cached code exists in Firestore.
  Future<void> _ensureCodeRegistered(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final migrationKey = 'referral_code_registered_$code';
    if (prefs.getBool(migrationKey) == true) return; // Already migrated

    try {
      final doc = await FirebaseFirestore.instance
          .collection('referral_codes')
          .doc(code)
          .get();
      if (!doc.exists) {
        await _registerCodeInFirestore(code);
      }
      await prefs.setBool(migrationKey, true);
    } catch (_) {
      // Offline — will retry next time
    }
  }

  /// Fetches current referral reward statistics.
  /// Syncs from Firestore first (cloud is source of truth for activated/earned),
  /// falls back to SharedPreferences cache if offline.
  Future<ReferralStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();

    // Try syncing activated_count and free_days_earned from Firestore
    await _syncStatsFromFirestore(prefs);

    return ReferralStats(
      totalInvited: prefs.getInt(_prefInvitedKey) ?? 0,
      storesActivated: prefs.getInt(_prefActivatedKey) ?? 0,
      freeDaysEarned: prefs.getInt(_prefFreeDaysKey) ?? 0,
      appliedReferralCode: prefs.getString(_prefAppliedCodeKey),
    );
  }

  /// Syncs referrer stats (activated_count, free_days_earned) from Firestore
  /// into local SharedPreferences cache. Silent on failure.
  Future<void> _syncStatsFromFirestore(SharedPreferences prefs) async {
    try {
      final code = prefs.getString('merchant_referral_code');
      if (code == null || code.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('referral_codes')
          .doc(code)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final activatedCount = (data['activated_count'] as num?)?.toInt() ?? 0;
        final freeDays = (data['free_days_earned'] as num?)?.toInt() ?? 0;
        await prefs.setInt(_prefActivatedKey, activatedCount);
        await prefs.setInt(_prefFreeDaysKey, freeDays);
      }
    } catch (_) {
      // Offline — use cached values
    }
  }

  /// Builds a friendly invite message in clean simple English
  String buildInviteMessage(String code, {String? storeName}) {
    final name = storeName != null && storeName.isNotEmpty ? storeName : 'my retail store';
    return 'Hello! 🙏 I am using *Kamai+ POS Billing App* for $name.\n\n'
        '• 100% Offline & Fast Counter Billing\n'
        '• 1-Click WhatsApp Invoices & Thermal Printing\n'
        '• Customer Credit & Udhar Ledger\n'
        '• Daily Profit, Stock & GST Reports\n\n'
        '👉 Sign up with my referral code and get *$_rewardDaysPerActivation Days FREE PRO Access*!\n\n'
        '📲 Download App: https://play.google.com/store/apps/details?id=com.kamaiplus.pos&referrer=$code\n'
        '🎁 Referral Code: *$code*';
  }

  /// 1-Tap Share on WhatsApp.
  /// Invited count increments ONLY after successful launch (not on button press).
  Future<bool> shareOnWhatsApp(String code, {String? storeName}) async {
    final message = buildInviteMessage(code, storeName: storeName);
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('whatsapp://send?text=$encoded');

    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) await _incrementInvitedCount();
      return launched;
    } else {
      // Fallback to web WhatsApp or generic share
      final webUri = Uri.parse('https://api.whatsapp.com/send?text=$encoded');
      if (await canLaunchUrl(webUri)) {
        final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
        if (launched) await _incrementInvitedCount();
        return launched;
      } else {
        await shareGeneral(code, storeName: storeName);
        return true;
      }
    }
  }

  /// Share via System Sheet (Telegram, SMS, Email, etc.)
  /// Uses ShareResult to only count if user actually shared.
  Future<void> shareGeneral(String code, {String? storeName}) async {
    final message = buildInviteMessage(code, storeName: storeName);
    final result = await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: 'Invite to Kamai+ POS - Get $_rewardDaysPerActivation Days Free PRO',
      ),
    );
    // Only count if share was successful (not dismissed/cancelled)
    if (result.status == ShareResultStatus.success) {
      await _incrementInvitedCount();
    }
  }

  /// Increments invited count in SharedPreferences
  Future<void> _incrementInvitedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefInvitedKey) ?? 0;
    await prefs.setInt(_prefInvitedKey, current + 1);
  }

  /// Copy referral code with haptic feedback
  Future<void> copyCode(String code) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: code));
  }

  /// Applies a referral code entered by this merchant to unlock 30 days free PRO.
  /// Validates code exists in Firestore before granting bonus.
  /// Also rewards the referrer with 30 days PRO and increments their counters.
  Future<({bool success, String message})> applyReferralCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) {
      return (success: false, message: 'Please enter a referral code');
    }

    final myCode = await getMerchantReferralCode();
    if (code == myCode) {
      return (success: false, message: 'You cannot use your own referral code!');
    }

    final prefs = await SharedPreferences.getInstance();
    final alreadyApplied = prefs.getString(_prefAppliedCodeKey);
    if (alreadyApplied != null && alreadyApplied.isNotEmpty) {
      return (success: false, message: 'You have already claimed a referral code ($alreadyApplied).');
    }

    // Validate code exists in Firestore (blocks random/fake codes)
    try {
      final codeDoc = await FirebaseFirestore.instance
          .collection('referral_codes')
          .doc(code)
          .get();

      if (!codeDoc.exists) {
        return (
          success: false,
          message: 'Invalid referral code. Please check the code and try again.',
        );
      }
    } catch (e) {
      return (
        success: false,
        message: 'Unable to verify referral code. Please check your internet connection and try again.',
      );
    }

    // Grant 30 Days Pro Free Trial Extension to the REFEREE (this merchant)
    final profile = await LocalDatabase.instance.getStoreProfile();
    final currentExpiry = profile.proExpiry.isNotEmpty
        ? DateTime.tryParse(profile.proExpiry) ?? DateTime.now()
        : DateTime.now();
    final baseDate = currentExpiry.isAfter(DateTime.now()) ? currentExpiry : DateTime.now();
    final newExpiry = baseDate.add(Duration(days: _rewardDaysPerActivation));

    await LocalDatabase.instance.activateProMembership(
      plan: 'pro_referral_bonus',
      paymentId: 'ref_bonus_$code',
      expiryDate: newExpiry,
    );

    await prefs.setString(_prefAppliedCodeKey, code);

    // Reward the REFERRER: increment their activated_count and free_days_earned
    await _rewardReferrer(code);

    return (
      success: true,
      message: '✓ Referral bonus activated! $_rewardDaysPerActivation Days Free PRO added to your store!',
    );
  }

  /// Rewards the referrer when someone applies their code:
  /// 1. Records the redemption in Firestore
  /// 2. Increments referrer's activated_count and free_days_earned
  /// 3. Extends referrer's Pro membership by 30 days (applied next time they open app)
  Future<void> _rewardReferrer(String referrerCode) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final firestore = FirebaseFirestore.instance;
      final codeRef = firestore.collection('referral_codes').doc(referrerCode);

      // Record this redemption
      await codeRef.collection('redemptions').doc(uid).set({
        'redeemed_at': FieldValue.serverTimestamp(),
        'referee_id': uid,
      });

      // Increment referrer's counters atomically
      await codeRef.update({
        'activated_count': FieldValue.increment(1),
        'free_days_earned': FieldValue.increment(_rewardDaysPerActivation),
      });

      // Also extend referrer's Pro membership via Firestore
      // (referrer's app will pick this up on next sync)
      final codeData = (await codeRef.get()).data();
      final referrerMerchantId = codeData?['merchant_id'] as String?;
      if (referrerMerchantId != null && referrerMerchantId.isNotEmpty) {
        final docId = referrerMerchantId.startsWith('biz_')
            ? referrerMerchantId
            : 'biz_$referrerMerchantId';
        final bizRef = firestore.collection('businesses').doc(docId);
        final bizDoc = await bizRef.get();

        if (bizDoc.exists) {
          final bizData = bizDoc.data()!;
          final existingExpiry = bizData['pro_expiry']?.toString() ?? '';
          final parsedExpiry = existingExpiry.isNotEmpty
              ? DateTime.tryParse(existingExpiry)
              : null;
          final referrerBase =
              (parsedExpiry != null && parsedExpiry.isAfter(DateTime.now()))
                  ? parsedExpiry
                  : DateTime.now();
          final referrerNewExpiry =
              referrerBase.add(Duration(days: _rewardDaysPerActivation));

          await bizRef.update({
            'is_pro': true,
            'pro_plan': 'pro_referral_reward',
            'pro_expiry': referrerNewExpiry.toIso8601String(),
          });
        }
      }
    } catch (_) {
      // Referrer reward is best-effort; referee still gets their bonus
    }
  }
}
