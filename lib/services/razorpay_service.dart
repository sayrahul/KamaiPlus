import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/local_database.dart';
import '../models/models.dart';
import 'firestore_sync_service.dart';
import 'native_notification_service.dart';
import 'remote_config_service.dart';
import 'soundbox_service.dart';

/// Razorpay Payment Gateway Service (LIVE Mode)
/// Credentials configured from env.local
class RazorpayService {
  static final RazorpayService instance = RazorpayService._internal();
  RazorpayService._internal();

  static const String razorpayKeyId = 'rzp_live_TcXNjRb5XAUYqR';
  

  Razorpay? _razorpay;
  Function(PaymentSuccessResponse)? _onSuccessCallback;
  Function(PaymentFailureResponse)? _onErrorCallback;
  Function(ExternalWalletResponse)? _onWalletCallback;
  String _pendingPlan = 'annual';
  String? _pendingCouponCode;

  void init() {
    if (_razorpay != null) return;
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }

  /// Open Razorpay Standard Checkout for Pro Upgrade
  /// [plan]: 'annual' (₹1499/year) or 'monthly' (₹199/month)
  /// [overrideAmountPaise]: coupon-discounted amount, when a valid coupon is
  /// applied (see `pro_upgrade_modal.dart`) — the caller has already floored
  /// this to a sane minimum, so it's trusted as-is here.
  /// [couponCode]: recorded in the Razorpay order notes and the Firestore
  /// activation doc purely for reconciliation — it does not affect pricing
  /// on this end beyond [overrideAmountPaise].
  Future<void> openCheckout({
    required String plan,
    required StoreProfileModel profile,
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onError,
    Function(ExternalWalletResponse)? onWallet,
    int? overrideAmountPaise,
    String? couponCode,
  }) async {
    init();
    _pendingPlan = plan;
    _pendingCouponCode = couponCode;
    _onSuccessCallback = onSuccess;
    _onErrorCallback = onError;
    _onWalletCallback = onWallet;

    final isAnnual = plan == 'annual';
    // Strict integer paise, from the same Remote Config values the upgrade
    // modal displays — previously hardcoded here AND in the modal, so a price
    // change had to be made in two places or the app would show one price and
    // charge another.
    final int amountPaise = overrideAmountPaise ??
        (isAnnual
            ? RemoteConfigService.instance.proAnnualPricePaise
            : RemoteConfigService.instance.proMonthlyPricePaise);
    final String planName = isAnnual ? 'Kamai+ Pro Business (1 Year)' : 'Kamai+ Pro Business (1 Month)';

    final options = {
      'key': razorpayKeyId,
      'amount': amountPaise,
      'name': 'Kamai+ POS',
      'description': planName,
      'timeout': 300,
      'prefill': {
        'contact': profile.phone.isNotEmpty ? profile.phone : '',
        'email': profile.email.isNotEmpty ? profile.email : 'billing@kamaiplus.com',
      },
      'notes': {
        'business_id': FirestoreSyncService.instance.activeBusinessId,
        'plan': plan,
        'store_name': profile.storeName,
        'merchant_phone': profile.phone,
        if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
      },
      'theme': {
        'color': '#059669', // Emerald brand theme
      },
      'external': {
        'wallets': ['paytm']
      }
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      debugPrint('Razorpay open exception: $e');
      onError(PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'Could not open checkout: $e', null));
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final paymentId = response.paymentId ?? 'pay_${DateTime.now().millisecondsSinceEpoch}';
    final isAnnual = _pendingPlan == 'annual';
    final expiryDate = DateTime.now().add(Duration(days: isAnnual ? 365 : 30));

    // 1. Activate in SQLite database
    await LocalDatabase.instance.activateProMembership(
      plan: _pendingPlan,
      paymentId: paymentId,
      expiryDate: expiryDate,
    );

    // 2. Cache in SharedPreferences for ultra-fast UI rendering
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro', true);
    await prefs.setString('pro_plan', _pendingPlan);
    await prefs.setString('pro_expiry', expiryDate.toIso8601String());
    await prefs.setString('razorpay_payment_id', paymentId);

    // 3. Ask the BACKEND to grant Pro in the cloud.
    //
    // This used to be a direct client write of `is_pro: true` into
    // businesses/{bizId}. Combined with firestore.rules letting a business
    // owner write any field on their own document, that meant Pro could be
    // switched on with no payment at all — and even a genuine payment was
    // never checked against Razorpay (no order_id, no signature, no amount
    // check). `verifyRazorpayPayment` now asks Razorpay what actually
    // happened and grants via the Admin SDK; rules forbid the client.
    //
    // Deliberately NOT awaited before the local activation above: the
    // offline-first contract says a merchant who just paid gets their
    // features immediately, even on a dead connection at the counter. The
    // local grant is optimistic; the cloud record is the durable truth, and
    // `_retryPendingVerification` picks up anything that failed here.
    final verified = await _verifyWithBackend(
      paymentId: paymentId,
      plan: _pendingPlan,
      couponCode: _pendingCouponCode,
    );
    if (!verified) {
      // Remember it so the next app launch can finish the handshake rather
      // than the merchant silently losing their purchase on a new device.
      await prefs.setString('pending_razorpay_verification', '$paymentId|$_pendingPlan');
    }

    // 4. Audio & push celebration
    SoundboxService.instance.speakCustom(
      'Badhaai ho! Kamai Plus Pro membership activate ho gayi hai.',
      lang: 'hi',
    );
    NativeNotificationService.showNotification(
      title: '🎉 Kamai+ Pro Activated!',
      body: 'Payment successful! Unlimited billing, thermal branding, and WhatsApp CRM are live.',
    );

    _onSuccessCallback?.call(response);
  }

  /// Endpoint for `verifyRazorpayPayment` in `functions/index.js`.
  ///
  /// A plain HTTPS call with the caller's Firebase ID token rather than the
  /// `cloud_functions` package — this app already talks to HTTPS JSON APIs
  /// this way (see `cloud_barcode_resolver_service.dart`), and adding a
  /// Firebase plugin purely for one call is not worth the build risk.
  static const String _verifyEndpoint =
      'https://us-central1-kamaiplus.cloudfunctions.net/verifyRazorpayPayment';

  Future<bool> _verifyWithBackend({
    required String paymentId,
    required String plan,
    String? couponCode,
  }) async {
    HttpClient? client;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('Pro verification skipped: not signed in.');
        return false;
      }

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      final req = await client.postUrl(Uri.parse(_verifyEndpoint));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.write(jsonEncode({
        'payment_id': paymentId,
        'plan': plan,
        if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
      }));

      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        debugPrint('Pro verified server-side: $body');
        return true;
      }
      debugPrint('Pro verification rejected (${res.statusCode}): $body');
      return false;
    } catch (e) {
      debugPrint('Pro verification network notice: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// Finishes a purchase whose server-side verification never went through —
  /// the merchant paid on a dead connection, or the app was killed between
  /// the Razorpay callback and the handshake. Safe to call on every launch:
  /// the backend treats a replayed payment_id as already-granted rather than
  /// extending the subscription again.
  Future<void> retryPendingVerification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString('pending_razorpay_verification');
      if (pending == null || pending.isEmpty) return;

      final parts = pending.split('|');
      if (parts.length != 2 || parts[0].isEmpty) {
        await prefs.remove('pending_razorpay_verification');
        return;
      }

      final ok = await _verifyWithBackend(paymentId: parts[0], plan: parts[1]);
      if (ok) {
        await prefs.remove('pending_razorpay_verification');
        debugPrint('Pending Pro purchase verified on retry.');
      }
    } catch (_) {}
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('Razorpay payment error: ${response.code} - ${response.message}');
    _onErrorCallback?.call(response);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('Razorpay external wallet: ${response.walletName}');
    _onWalletCallback?.call(response);
  }
}
