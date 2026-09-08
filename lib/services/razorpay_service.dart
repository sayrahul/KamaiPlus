import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/local_database.dart';
import '../models/models.dart';
import 'native_notification_service.dart';
import 'soundbox_service.dart';

/// Razorpay Payment Gateway Service (LIVE Mode)
/// Credentials configured from env.local
class RazorpayService {
  static final RazorpayService instance = RazorpayService._internal();
  RazorpayService._internal();

  static const String razorpayKeyId = 'rzp_live_TSJvcf9JnWpMMm';
  static const String razorpayKeySecret = 'bhs9g8FV7KjDV7xlqTcDOVcp';

  Razorpay? _razorpay;
  Function(PaymentSuccessResponse)? _onSuccessCallback;
  Function(PaymentFailureResponse)? _onErrorCallback;
  Function(ExternalWalletResponse)? _onWalletCallback;
  String _pendingPlan = 'annual';

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
  Future<void> openCheckout({
    required String plan,
    required StoreProfileModel profile,
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onError,
    Function(ExternalWalletResponse)? onWallet,
  }) async {
    init();
    _pendingPlan = plan;
    _onSuccessCallback = onSuccess;
    _onErrorCallback = onError;
    _onWalletCallback = onWallet;

    final isAnnual = plan == 'annual';
    // Strict integer paise: ₹1499 = 149900 paise, ₹199 = 19900 paise
    final int amountPaise = isAnnual ? 149900 : 19900;
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

    // 3. Audio & push celebration
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

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('Razorpay payment error: ${response.code} - ${response.message}');
    _onErrorCallback?.call(response);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('Razorpay external wallet: ${response.walletName}');
    _onWalletCallback?.call(response);
  }
}
