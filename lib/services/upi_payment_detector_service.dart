import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DetectedPaymentEvent {
  final int amountPaise;
  final String appName;
  final String sender;
  final String rawText;
  final DateTime timestamp;

  const DetectedPaymentEvent({
    required this.amountPaise,
    required this.appName,
    required this.sender,
    required this.rawText,
    required this.timestamp,
  });

  factory DetectedPaymentEvent.fromMap(Map<dynamic, dynamic> map) {
    return DetectedPaymentEvent(
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      appName: (map['appName'] as String?) ?? 'UPI',
      sender: (map['sender'] as String?) ?? '',
      rawText: (map['rawText'] as String?) ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class UpiPaymentDetectorService {
  static final UpiPaymentDetectorService instance = UpiPaymentDetectorService._init();

  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/payment_detector');

  final StreamController<DetectedPaymentEvent> _paymentController =
      StreamController<DetectedPaymentEvent>.broadcast();

  Stream<DetectedPaymentEvent> get onPaymentDetected => _paymentController.stream;

  int? _targetBillAmountPaise;
  void Function(DetectedPaymentEvent)? _activeBillMatchCallback;

  UpiPaymentDetectorService._init() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onPaymentDetected') {
      try {
        final map = call.arguments as Map<dynamic, dynamic>;
        final event = DetectedPaymentEvent.fromMap(map);
        _paymentController.add(event);

        // Check if matching active bill amount
        if (_targetBillAmountPaise != null &&
            _activeBillMatchCallback != null &&
            event.amountPaise == _targetBillAmountPaise) {
          _activeBillMatchCallback!(event);
        }
      } catch (e) {
        debugPrint('UpiPaymentDetectorService error: $e');
      }
    }
  }

  /// Checks if Android Notification Listener permission is granted
  Future<bool> isNotificationAccessGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Settings -> Notification Access for KamaiPlus
  Future<bool> openNotificationAccessSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openNotificationAccessSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets the active bill amount to match and trigger auto-complete callback
  void startListeningForBill({
    required int amountPaise,
    required void Function(DetectedPaymentEvent) onMatchedPayment,
  }) {
    _targetBillAmountPaise = amountPaise;
    _activeBillMatchCallback = onMatchedPayment;
  }

  /// Stops listening for the specific bill
  void stopListening() {
    _targetBillAmountPaise = null;
    _activeBillMatchCallback = null;
  }

  /// Simulates a live payment for testing or demo without actual money
  Future<void> simulatePayment({
    required int amountPaise,
    String appName = 'PhonePe',
  }) async {
    try {
      await _channel.invokeMethod('simulatePayment', {
        'amountPaise': amountPaise,
        'appName': appName,
      });
    } catch (_) {}
  }
}
