import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../core/database/local_database.dart';

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

  /// Generates or retrieves the unique referral code for the current merchant
  Future<String> getMerchantReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString('merchant_referral_code');
    if (code != null && code.isNotEmpty) return code;

    final profile = await LocalDatabase.instance.getStoreProfile();
    String suffix = 'PLUS';
    if (profile.phone.trim().length >= 4) {
      final p = profile.phone.trim();
      suffix = p.substring(p.length - 4);
    } else if (profile.ownerName.trim().isNotEmpty) {
      suffix = profile.ownerName.trim().replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
      if (suffix.length > 4) suffix = suffix.substring(0, 4);
    }

    code = 'KAMAI$suffix'.toUpperCase();
    await prefs.setString('merchant_referral_code', code);
    return code;
  }

  /// Fetches current referral reward statistics
  Future<ReferralStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    return ReferralStats(
      totalInvited: prefs.getInt(_prefInvitedKey) ?? 0,
      storesActivated: prefs.getInt(_prefActivatedKey) ?? 0,
      freeDaysEarned: prefs.getInt(_prefFreeDaysKey) ?? 0,
      appliedReferralCode: prefs.getString(_prefAppliedCodeKey),
    );
  }

  /// Builds a friendly invite message in clean simple English
  String buildInviteMessage(String code, {String? storeName}) {
    final name = storeName != null && storeName.isNotEmpty ? storeName : 'my retail store';
    return 'Hello! 🙏 I am using *Kamai+ POS Billing App* for $name.\n\n'
        '• 100% Offline & Fast Counter Billing\n'
        '• 1-Click WhatsApp Invoices & Thermal Printing\n'
        '• Customer Credit & Udhar Ledger\n'
        '• Daily Profit, Stock & GST Reports\n\n'
        '👉 Sign up with my referral code and get *15 Days FREE PRO Access*!\n\n'
        '📲 Download App: https://play.google.com/store/apps/details?id=com.kamaiplus.pos&referrer=$code\n'
        '🎁 Referral Code: *$code*';
  }

  /// 1-Tap Share on WhatsApp
  Future<bool> shareOnWhatsApp(String code, {String? storeName}) async {
    final message = buildInviteMessage(code, storeName: storeName);
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('whatsapp://send?text=$encoded');

    // Track invite share
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefInvitedKey) ?? 0;
    await prefs.setInt(_prefInvitedKey, current + 1);

    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback to web WhatsApp or generic share
      final webUri = Uri.parse('https://api.whatsapp.com/send?text=$encoded');
      if (await canLaunchUrl(webUri)) {
        return await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        await shareGeneral(code, storeName: storeName);
        return true;
      }
    }
  }

  /// Share via System Sheet (Telegram, SMS, Email, etc.)
  Future<void> shareGeneral(String code, {String? storeName}) async {
    final message = buildInviteMessage(code, storeName: storeName);
    // ignore: deprecated_member_use
    await Share.share(
      message,
      subject: 'Invite to Kamai+ POS - Get 15 Days Free PRO',
    );
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefInvitedKey) ?? 0;
    await prefs.setInt(_prefInvitedKey, current + 1);
  }

  /// Copy referral code with haptic feedback
  Future<void> copyCode(String code) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: code));
  }

  /// Applies a referral code entered by this merchant to unlock 15 days free PRO
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

    // Grant 15 Days Pro Free Trial Extension
    final profile = await LocalDatabase.instance.getStoreProfile();
    final currentExpiry = profile.proExpiry.isNotEmpty
        ? DateTime.tryParse(profile.proExpiry) ?? DateTime.now()
        : DateTime.now();
    final baseDate = currentExpiry.isAfter(DateTime.now()) ? currentExpiry : DateTime.now();
    final newExpiry = baseDate.add(const Duration(days: 15));

    await LocalDatabase.instance.activateProMembership(
      plan: 'pro_referral_bonus',
      paymentId: 'ref_bonus_$code',
      expiryDate: newExpiry,
    );

    await prefs.setString(_prefAppliedCodeKey, code);

    return (
      success: true,
      message: '✓ Referral bonus activated! 15 Days Free PRO added to your store!',
    );
  }
}
